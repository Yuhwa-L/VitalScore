import Foundation
import Combine
import SwiftUI
import ARKit
import os

private let log = Logger(subsystem: "com.vitalscore.app", category: "eye-focus-manager")

enum GazeBackend: String {
    case arkit
    case vision
    case none

    var displayName: String {
        switch self {
        case .arkit: return "ARKit TrueDepth"
        case .vision: return "Vision (RGB camera)"
        case .none: return "Not available"
        }
    }

    static func detect() -> GazeBackend {
        if ARFaceTrackingConfiguration.isSupported { return .arkit }
        if VisionGazeTrackingService.isSupported { return .vision }
        return .none
    }
}

@MainActor
final class EyeFocusTestManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case ready
        case calibrating(pointIndex: Int)
        case countdown(Int)
        case running
        case processing
        case finished(EyeFocusTestResult)
    }

    @Published var phase: Phase = .idle
    @Published var dotPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var dotIsTarget = false
    @Published private(set) var lastSavedLogURL: URL?
    @Published var startupError: String?
    @Published private(set) var isPreparing: Bool = false
    @Published private(set) var calibrationProgress: Double = 0
    @Published private(set) var calibrationIsCollecting: Bool = false
    @Published private(set) var displayGazePoint: CGPoint?

    let gazeBackend: GazeBackend
    let arkitService: GazeTrackingService?
    let visionService: VisionGazeTrackingService?

    var gazeAvailable: Bool { gazeBackend != .none }
    var calibrationTargetCount: Int { GazeCalibrator.targets.count }

    static let testDurationSeconds: TimeInterval = 30.0
    static let reactionWindowSeconds: TimeInterval = 1.5
    static let calibrationPointDuration: TimeInterval = 1.6
    static let calibrationCollectStart: TimeInterval = 0.6

    private var startTime: Date?
    private var calibrationStartedAt: Date?
    private var testStartedAt: Date?

    private var lastColorChangeAt: Date?
    private var colorChangeTimestamps: [Date] = []
    private var tapTimestamps: [Date] = []
    private var hits: [(colorChange: Date, tapDelayMs: Double)] = []
    private var missedTargets: Int = 0
    private var falseTaps: Int = 0
    private var gazeSamples: [GazeSample] = []
    private var screenSize: CGSize = CGSize(width: 390, height: 844)

    private var calibrationRawSamples: [[CGPoint]] = []
    private var calibrationRecords: [CalibrationRecord] = []
    private var calibrationTransform: CalibrationTransform = .identity
    private var calibrationResidual: Double = 0

    private let gazeSmoother = OneEuroFilter2D(minCutoff: 0.8, beta: 0.006)
    private let calibSmoother = OneEuroFilter2D(minCutoff: 1.5, beta: 0.005)
    let motionTracker = DeviceMotionTracker()
    static let blinkThreshold: Float = 0.5
    static let saccadeWindowSeconds: TimeInterval = 0.20
    private var lastDotMoveAt: Date = Date.distantPast
    private var calibrationBaselineHeadPose: HeadPoseSnapshot?

    private var timer: Timer?
    private var movementTimer: Timer?
    private var countdownTimer: Timer?
    private var endTimer: Timer?
    private var calibrationTimer: Timer?

    init() {
        let backend = GazeBackend.detect()
        self.gazeBackend = backend

        switch backend {
        case .arkit:
            let svc = GazeTrackingService()
            self.arkitService = svc
            self.visionService = nil
            svc.onGazeUpdate = { [weak self] gazePoint, leftBlink, rightBlink, valid in
                self?.recordGazeSample(rawGaze: gazePoint, leftBlink: leftBlink, rightBlink: rightBlink, valid: valid)
            }
        case .vision:
            let svc = VisionGazeTrackingService()
            self.arkitService = nil
            self.visionService = svc
            svc.onGazeUpdate = { [weak self] gazePoint, leftBlink, rightBlink, valid in
                self?.recordGazeSample(rawGaze: gazePoint, leftBlink: leftBlink, rightBlink: rightBlink, valid: valid)
            }
        case .none:
            self.arkitService = nil
            self.visionService = nil
        }
    }

    func setScreenSize(_ size: CGSize) {
        screenSize = size
    }

    func start() async {
        reset()
        startupError = nil
        motionTracker.start()

        if gazeBackend == .vision, let vision = visionService {
            isPreparing = true
            let result = await vision.start()
            isPreparing = false
            switch result {
            case .ok: break
            case .permissionDenied:
                startupError = "Camera permission denied. Open Settings to enable Camera for VitalScore."
                return
            case .noCamera(let msg):
                startupError = msg
                return
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        if gazeAvailable {
            phase = .ready
        } else {
            beginCountdown()
        }
    }

    func beginCalibration() {
        guard gazeAvailable else { return beginCountdown() }
        calibrationStartedAt = Date()
        calibrationRawSamples = Array(repeating: [], count: GazeCalibrator.targets.count)
        calibrationRecords = []
        calibrationTransform = .identity
        calibrationResidual = 0
        runCalibrationPoint(0)
    }

    func cancel() {
        invalidateTimers()
        if gazeBackend == .vision { visionService?.stop() }
        motionTracker.stop()
        reset()
        phase = .idle
    }

    func recordTap(at time: Date = Date()) {
        guard case .running = phase else { return }
        tapTimestamps.append(time)

        if dotIsTarget, let last = lastColorChangeAt {
            let delay = time.timeIntervalSince(last) * 1000.0
            if delay >= 0 && delay <= Self.reactionWindowSeconds * 1000.0 {
                hits.append((colorChange: last, tapDelayMs: delay))
                dotIsTarget = false
                return
            }
        }
        falseTaps += 1
    }

    private func recordGazeSample(rawGaze: CGPoint, leftBlink: Float, rightBlink: Float, valid: Bool) {
        let now = Date().timeIntervalSinceReferenceDate
        let isBlinking = leftBlink > Self.blinkThreshold && rightBlink > Self.blinkThreshold
        let motion = motionTracker.snapshot

        if case .calibrating(let idx) = phase {
            let smoothedRaw = calibSmoother.filter(rawGaze, at: now)
            if valid && !isBlinking && motion.isStable && calibrationIsCollecting {
                if idx < calibrationRawSamples.count {
                    calibrationRawSamples[idx].append(smoothedRaw)
                }
            }
            displayGazePoint = smoothedRaw
            return
        }

        guard case .running = phase, let start = testStartedAt else {
            if valid && !isBlinking {
                displayGazePoint = calibrationTransform.apply(gazeSmoother.filter(rawGaze, at: now))
            } else {
                displayGazePoint = nil
            }
            return
        }

        let smoothedRaw = gazeSmoother.filter(rawGaze, at: now)
        let calibrated = calibrationTransform.apply(smoothedRaw)
        displayGazePoint = calibrated

        let rawPx = CGPoint(x: rawGaze.x * screenSize.width, y: rawGaze.y * screenSize.height)
        let calibratedPx = CGPoint(x: calibrated.x * screenSize.width, y: calibrated.y * screenSize.height)
        let targetPx = CGPoint(x: dotPosition.x * screenSize.width, y: dotPosition.y * screenSize.height)
        let inSettling = Date().timeIntervalSince(lastDotMoveAt) < Self.saccadeWindowSeconds

        let currentPose: HeadPoseSnapshot
        let posDev: Float
        let angDev: Float
        if let arkit = arkitService {
            currentPose = HeadPoseSnapshot(transformInCamera: arkit.latestFaceTransformInCamera)
            if let baseline = calibrationBaselineHeadPose {
                posDev = currentPose.deviation(from: baseline)
                angDev = currentPose.angularDeviationDeg(from: baseline)
            } else {
                posDev = 0
                angDev = 0
            }
        } else {
            currentPose = .zero
            posDev = 0
            angDev = 0
        }

        let sample = GazeSample(
            timestamp: Date().timeIntervalSince(start),
            rawGazePoint: rawPx,
            gazePoint: calibratedPx,
            targetPoint: targetPx,
            leftBlink: leftBlink,
            rightBlink: rightBlink,
            trackingValid: valid,
            inSettlingWindow: inSettling,
            motion: motion,
            headPose: currentPose,
            headPositionDevM: posDev,
            headAngularDevDeg: angDev
        )
        gazeSamples.append(sample)
    }

    // MARK: - Calibration

    private func runCalibrationPoint(_ index: Int) {
        guard index < GazeCalibrator.targets.count else { return finishCalibration() }
        let target = GazeCalibrator.targets[index]
        phase = .calibrating(pointIndex: index)
        withAnimation(.easeInOut(duration: 0.3)) {
            dotPosition = target
        }
        calibrationIsCollecting = false
        calibrationProgress = 0
        let pointStart = Date()

        calibrationTimer?.invalidate()
        calibrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let elapsed = Date().timeIntervalSince(pointStart)
                self.calibrationProgress = min(1.0, elapsed / Self.calibrationPointDuration)
                if elapsed >= Self.calibrationCollectStart && elapsed < Self.calibrationPointDuration {
                    self.calibrationIsCollecting = true
                }
                if elapsed >= Self.calibrationPointDuration {
                    self.calibrationTimer?.invalidate()
                    self.calibrationTimer = nil
                    self.calibrationIsCollecting = false
                    self.completeCalibrationPoint(index)
                }
            }
        }
    }

    private func completeCalibrationPoint(_ index: Int) {
        let samples = calibrationRawSamples[index]
        let target = GazeCalibrator.targets[index]
        if !samples.isEmpty {
            let robust = GazeCalibrator.robustMean(samples)
            let rec = CalibrationRecord(
                targetPoint: target,
                rawAvgPoint: robust,
                sampleCount: samples.count
            )
            calibrationRecords.append(rec)
            log.info("Calibration point \(index, privacy: .public) robust=(\(Double(robust.x), privacy: .public),\(Double(robust.y), privacy: .public)) n=\(samples.count, privacy: .public)")
        } else {
            log.error("Calibration point \(index, privacy: .public) collected 0 valid samples")
        }
        runCalibrationPoint(index + 1)
    }

    private func finishCalibration() {
        let rawPts = calibrationRecords.map { $0.rawAvgPoint }
        let tgtPts = calibrationRecords.map { $0.targetPoint }
        if let transform = CalibrationTransform.solve(rawPoints: rawPts, targetPoints: tgtPts) {
            calibrationTransform = transform
            calibrationResidual = transform.meanResidualNorm(rawPoints: rawPts, targetPoints: tgtPts)
            log.info("Calibration solved kind=\(transform.kind.rawValue, privacy: .public) residual=\(self.calibrationResidual, privacy: .public)")
        } else {
            calibrationTransform = .identity
            calibrationResidual = 0
            log.error("Calibration failed — using identity transform")
        }
        if let arkit = arkitService {
            calibrationBaselineHeadPose = HeadPoseSnapshot(transformInCamera: arkit.latestFaceTransformInCamera)
        }
        beginCountdown()
    }

    // MARK: - Countdown + Test

    private func beginCountdown() {
        phase = .countdown(3)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if case .countdown(let n) = self.phase {
                    if n > 1 {
                        self.phase = .countdown(n - 1)
                    } else {
                        self.countdownTimer?.invalidate()
                        self.beginRunning()
                    }
                }
            }
        }
    }

    private func beginRunning() {
        phase = .running
        testStartedAt = Date()
        if startTime == nil { startTime = testStartedAt }
        moveDot()
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.moveDot() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.toggleColor() }
        }
        endTimer = Timer.scheduledTimer(withTimeInterval: Self.testDurationSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    private func moveDot() {
        let x = CGFloat.random(in: 0.15...0.85)
        let y = CGFloat.random(in: 0.20...0.75)
        lastDotMoveAt = Date()
        withAnimation(.easeInOut(duration: 0.6)) {
            dotPosition = CGPoint(x: x, y: y)
        }
    }

    private func toggleColor() {
        if dotIsTarget {
            missedTargets += 1
        }
        dotIsTarget = true
        lastColorChangeAt = Date()
        colorChangeTimestamps.append(lastColorChangeAt!)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reactionWindowSeconds) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.dotIsTarget, let last = self.lastColorChangeAt, Date().timeIntervalSince(last) >= Self.reactionWindowSeconds {
                    self.missedTargets += 1
                    self.dotIsTarget = false
                }
            }
        }
    }

    private func finish() {
        invalidateTimers()
        if gazeBackend == .vision { visionService?.stop() }
        motionTracker.stop()
        phase = .processing

        let samplesSnapshot = gazeSamples
        let hitsSnapshot = hits
        let missedSnapshot = missedTargets
        let falseTapsSnapshot = falseTaps
        let recordsSnapshot = calibrationRecords
        let transformSnapshot = calibrationTransform
        let residualSnapshot = calibrationResidual
        let backendName = gazeBackend.rawValue
        let calibStart = calibrationStartedAt ?? Date()
        let testStart = testStartedAt ?? Date()
        let availSnapshot = gazeAvailable
        let screenSnapshot = screenSize

        Task.detached(priority: .userInitiated) { [weak self] in
            let reactionTimes = hitsSnapshot.map { $0.tapDelayMs }
            let avg = reactionTimes.isEmpty ? 0 : reactionTimes.reduce(0, +) / Double(reactionTimes.count)
            let stdDev = EyeFocusTestManager.standardDeviation(reactionTimes)
            let reactionScore = EyeFocusTestManager.calculateScore(
                averageReactionMs: avg,
                reactionStdDevMs: stdDev,
                missedTargets: missedSnapshot,
                falseTaps: falseTapsSnapshot
            )
            let gazeMetrics = availSnapshot
                ? GazeAggregator.aggregate(samples: samplesSnapshot, durationSeconds: Self.testDurationSeconds)
                : nil

            let combined = EyeFocusTestResult.blend(reactionScore: reactionScore, gazeScore: gazeMetrics?.gazeScore)
            let result = EyeFocusTestResult(
                averageReactionMs: avg,
                reactionStdDevMs: stdDev,
                missedTargets: missedSnapshot,
                falseTaps: falseTapsSnapshot,
                reactionScore: reactionScore,
                gazeMetrics: gazeMetrics,
                eyeFocusScore: combined,
                completedAt: Date()
            )

            var savedURL: URL? = nil
            if availSnapshot {
                let summary = CalibrationSummary(
                    records: recordsSnapshot,
                    transform: transformSnapshot,
                    meanResidualNorm: residualSnapshot
                )
                savedURL = GazeDataLogger.save(
                    samples: samplesSnapshot,
                    metrics: gazeMetrics,
                    backend: backendName,
                    startedAt: calibStart,
                    testStartedAt: testStart,
                    durationSeconds: Self.testDurationSeconds,
                    calibration: summary,
                    screenSize: screenSnapshot
                )
            }

            await MainActor.run { [weak self] in
                self?.lastSavedLogURL = savedURL
                self?.phase = .finished(result)
            }
            _ = self
        }
    }

    private func reset() {
        startTime = nil
        calibrationStartedAt = nil
        testStartedAt = nil
        lastColorChangeAt = nil
        colorChangeTimestamps.removeAll()
        tapTimestamps.removeAll()
        hits.removeAll()
        missedTargets = 0
        falseTaps = 0
        gazeSamples.removeAll()
        calibrationRawSamples.removeAll()
        calibrationRecords.removeAll()
        calibrationTransform = .identity
        calibrationResidual = 0
        calibrationProgress = 0
        calibrationIsCollecting = false
        displayGazePoint = nil
        gazeSmoother.reset()
        calibSmoother.reset()
        calibrationBaselineHeadPose = nil
        dotIsTarget = false
        dotPosition = CGPoint(x: 0.5, y: 0.5)
    }

    private func invalidateTimers() {
        countdownTimer?.invalidate()
        timer?.invalidate()
        movementTimer?.invalidate()
        endTimer?.invalidate()
        calibrationTimer?.invalidate()
        countdownTimer = nil
        timer = nil
        movementTimer = nil
        endTimer = nil
        calibrationTimer = nil
    }

    nonisolated static func calculateScore(
        averageReactionMs: Double,
        reactionStdDevMs: Double,
        missedTargets: Int,
        falseTaps: Int
    ) -> Double {
        let reactionPenalty = max(0, averageReactionMs - 300) / 8
        let variabilityPenalty = reactionStdDevMs / 15
        let missPenalty = Double(missedTargets) * 8
        let falseTapPenalty = Double(falseTaps) * 5
        let raw = 100 - reactionPenalty - variabilityPenalty - missPenalty - falseTapPenalty
        return min(100, max(0, raw))
    }

    nonisolated static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count))
    }
}
