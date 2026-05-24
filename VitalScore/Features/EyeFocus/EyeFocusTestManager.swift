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
    @Published private(set) var dotHitFlash = false
    @Published private(set) var lastSavedLogURL: URL?
    @Published var startupError: String?
    @Published private(set) var isPreparing: Bool = false
    @Published private(set) var calibrationProgress: Double = 0
    @Published private(set) var calibrationIsCollecting: Bool = false
    @Published private(set) var displayGazePoint: CGPoint?
    @Published private(set) var aiSummaryError: String?

    let gazeBackend: GazeBackend
    let arkitService: GazeTrackingService?
    let visionService: VisionGazeTrackingService?

    var gazeAvailable: Bool { gazeBackend != .none }
    var calibrationTargetCount: Int { GazeCalibrator.targets.count }

    static let testDurationSeconds: TimeInterval = 30.0
    static let reactionWindowSeconds: TimeInterval = 1.5
    static let calibrationPointDuration: TimeInterval = 2.2
    static let calibrationCollectStart: TimeInterval = 0.7
    static let motionCooldownSeconds: TimeInterval = 0.25
    static let gazeHitRadiusPx: CGFloat = 22
    static let gazeHitSlackPx: CGFloat = 6
    static let postHitPauseSeconds: TimeInterval = 1.5
    static let postMissPauseSeconds: TimeInterval = 0.4
    static let adaptiveBiasGain: Double = 0
    static let maxAdaptiveBias: CGFloat = 0
    static let minRuntimeJumpAllowance: CGFloat = 0.18
    static let maxRuntimeJumpPerSecond: CGFloat = 2.4

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

    private var calibrationSamples: [[CalibrationSample]] = []
    private var calibrationRecords: [CalibrationRecord] = []
    private var calibrationTransform: CalibrationTransform = .identity
    private var calibrationResidual: Double = 0
    private var adaptiveBias: CGVector = .zero
    private var lastSignificantMotionAt: Date = .distantPast
    private var lastAcceptedGazePoint: CGPoint?
    private var lastAcceptedGazeAt: Date?

    private let gazeSmoother = OneEuroFilter2D(minCutoff: 1.2, beta: 0.015)
    private let calibSmoother = OneEuroFilter2D(minCutoff: 1.0, beta: 0.01)
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
        calibrationSamples = Array(repeating: [], count: GazeCalibrator.targets.count)
        calibrationRecords = []
        calibrationTransform = .identity
        calibrationResidual = 0
        adaptiveBias = .zero
        lastSignificantMotionAt = .distantPast
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
                dotHitFlash = true
                scheduleNextCycle(after: Self.postHitPauseSeconds)
                return
            }
        }
        falseTaps += 1
    }

    private func recordGazeSample(rawGaze: CGPoint, leftBlink: Float, rightBlink: Float, valid: Bool) {
        let sampleDate = Date()
        let now = sampleDate.timeIntervalSinceReferenceDate
        let isBlinking = leftBlink > Self.blinkThreshold && rightBlink > Self.blinkThreshold
        let motion = motionTracker.snapshot
        let currentPose = currentHeadPose()

        if !motion.isStable {
            lastSignificantMotionAt = sampleDate
        }
        let inMotionCooldown = sampleDate.timeIntervalSince(lastSignificantMotionAt) < Self.motionCooldownSeconds

        if case .calibrating(let idx) = phase {
            let smoothedRaw = calibSmoother.filter(rawGaze, at: now)
            let input = CalibrationInput(rawGaze: smoothedRaw, headPose: currentPose, motion: motion)
            if valid && !isBlinking && motion.isUsableForCalibration && calibrationIsCollecting {
                if idx < calibrationSamples.count {
                    calibrationSamples[idx].append(
                        CalibrationSample(targetPoint: GazeCalibrator.targets[idx], input: input)
                    )
                }
            }
            displayGazePoint = smoothedRaw
            return
        }

        guard case .running = phase, let start = testStartedAt else {
            if valid && !isBlinking {
                let smoothedRaw = gazeSmoother.filter(rawGaze, at: now)
                let input = CalibrationInput(rawGaze: smoothedRaw, headPose: currentPose, motion: motion)
                let calibrated = clampedNormalized(calibrationTransform.apply(input))
                if !inMotionCooldown {
                    displayGazePoint = calibrated
                }
            } else {
                displayGazePoint = nil
            }
            return
        }

        let smoothedRaw = gazeSmoother.filter(rawGaze, at: now)
        let input = CalibrationInput(rawGaze: smoothedRaw, headPose: currentPose, motion: motion)
        let calibratedBase = clampedNormalized(calibrationTransform.apply(input))
        let inSettling = sampleDate.timeIntervalSince(lastDotMoveAt) < Self.saccadeWindowSeconds
        let isOutlier = isRuntimeGazeOutlier(calibratedBase, at: sampleDate)

        if Self.adaptiveBiasGain > 0,
           valid && !isBlinking && !isOutlier && !inSettling && !inMotionCooldown && motion.isStable {
            updateAdaptiveBias(estimatedPoint: calibratedBase, targetPoint: dotPosition)
        }

        let calibrated = clampedNormalized(applyAdaptiveBias(to: calibratedBase))
        let trackingValid = valid && !isBlinking && !isOutlier && !inMotionCooldown

        if trackingValid {
            displayGazePoint = calibrated
            rememberAcceptedGaze(calibratedBase, at: sampleDate)
        } else if !valid || isBlinking || isOutlier {
            displayGazePoint = nil
        }

        let rawPx = CGPoint(x: rawGaze.x * screenSize.width, y: rawGaze.y * screenSize.height)
        let calibratedPx = CGPoint(x: calibrated.x * screenSize.width, y: calibrated.y * screenSize.height)
        let targetPx = CGPoint(x: dotPosition.x * screenSize.width, y: dotPosition.y * screenSize.height)

        let posDev: Float
        let angDev: Float
        if let baseline = calibrationBaselineHeadPose {
            posDev = currentPose.deviation(from: baseline)
            angDev = currentPose.angularDeviationDeg(from: baseline)
        } else {
            posDev = 0
            angDev = 0
        }

        let sample = GazeSample(
            timestamp: sampleDate.timeIntervalSince(start),
            rawGazePoint: rawPx,
            gazePoint: calibratedPx,
            targetPoint: targetPx,
            leftBlink: leftBlink,
            rightBlink: rightBlink,
            trackingValid: trackingValid,
            inSettlingWindow: inSettling,
            inMotionCooldown: inMotionCooldown,
            motion: motion,
            headPose: currentPose,
            headPositionDevM: posDev,
            headAngularDevDeg: angDev
        )
        gazeSamples.append(sample)

        registerGazeHitIfNeeded(gazePx: calibratedPx, targetPx: targetPx, at: sampleDate, valid: trackingValid, blinking: isBlinking)
    }

    private func registerGazeHitIfNeeded(gazePx: CGPoint, targetPx: CGPoint, at time: Date, valid: Bool, blinking: Bool) {
        guard case .running = phase else { return }
        guard dotIsTarget, let last = lastColorChangeAt else { return }
        guard valid, !blinking else { return }
        let dx = gazePx.x - targetPx.x
        let dy = gazePx.y - targetPx.y
        let distance = sqrt(dx * dx + dy * dy)
        let threshold = Self.gazeHitRadiusPx + Self.gazeHitSlackPx
        guard distance <= threshold else { return }
        let delay = time.timeIntervalSince(last) * 1000.0
        guard delay >= 0, delay <= Self.reactionWindowSeconds * 1000.0 else { return }
        hits.append((colorChange: last, tapDelayMs: delay))
        dotIsTarget = false
        dotHitFlash = true
        scheduleNextCycle(after: Self.postHitPauseSeconds)
    }

    private func currentHeadPose() -> HeadPoseSnapshot {
        guard let arkit = arkitService else { return .zero }
        return HeadPoseSnapshot(transformInCamera: arkit.latestFaceTransformInCamera)
    }

    private func updateAdaptiveBias(estimatedPoint: CGPoint, targetPoint: CGPoint) {
        let errorX = targetPoint.x - estimatedPoint.x
        let errorY = targetPoint.y - estimatedPoint.y
        let errorDistance = hypot(errorX, errorY)
        guard errorDistance < 0.25 else { return }

        let gain = CGFloat(Self.adaptiveBiasGain)
        adaptiveBias.dx = clampAdaptiveBias(adaptiveBias.dx * (1 - gain) + errorX * gain)
        adaptiveBias.dy = clampAdaptiveBias(adaptiveBias.dy * (1 - gain) + errorY * gain)
    }

    private func applyAdaptiveBias(to point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + adaptiveBias.dx, y: point.y + adaptiveBias.dy)
    }

    private func clampAdaptiveBias(_ value: CGFloat) -> CGFloat {
        max(-Self.maxAdaptiveBias, min(Self.maxAdaptiveBias, value))
    }

    private func isRuntimeGazeOutlier(_ point: CGPoint, at date: Date) -> Bool {
        guard let previous = lastAcceptedGazePoint, let previousDate = lastAcceptedGazeAt else {
            return false
        }
        let dt = max(1.0 / 120.0, date.timeIntervalSince(previousDate))
        let allowedJump = max(Self.minRuntimeJumpAllowance, CGFloat(dt) * Self.maxRuntimeJumpPerSecond)
        return hypot(point.x - previous.x, point.y - previous.y) > allowedJump
    }

    private func rememberAcceptedGaze(_ point: CGPoint, at date: Date) {
        lastAcceptedGazePoint = point
        lastAcceptedGazeAt = date
    }

    private func clampedNormalized(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(1, point.x)),
            y: max(0, min(1, point.y))
        )
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
        let samples = calibrationSamples[index]
        let target = GazeCalibrator.targets[index]
        if !samples.isEmpty {
            let robust = GazeCalibrator.robustMean(samples.map { $0.input.rawPoint })
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
        let allSamples = calibrationSamples.flatMap { $0 }
        if let transform = CalibrationTransform.solve(samples: allSamples) {
            calibrationTransform = transform
            calibrationResidual = transform.meanResidualNorm(samples: allSamples)
            log.info("Calibration solved kind=\(transform.kind.rawValue, privacy: .public) residual=\(self.calibrationResidual, privacy: .public)")
        } else if let transform = CalibrationTransform.solve(
            rawPoints: calibrationRecords.map { $0.rawAvgPoint },
            targetPoints: calibrationRecords.map { $0.targetPoint }
        ) {
            calibrationTransform = transform
            calibrationResidual = transform.meanResidualNorm(
                rawPoints: calibrationRecords.map { $0.rawAvgPoint },
                targetPoints: calibrationRecords.map { $0.targetPoint }
            )
            log.info("Calibration fallback solved kind=\(transform.kind.rawValue, privacy: .public) residual=\(self.calibrationResidual, privacy: .public)")
        } else {
            calibrationTransform = .identity
            calibrationResidual = 0
            log.error("Calibration failed — using identity transform")
        }
        calibrationBaselineHeadPose = GazeCalibrator.meanHeadPose(samples: allSamples) ?? currentHeadPose()
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
        armTarget()
    }

    private var testDurationExceeded: Bool {
        guard let start = testStartedAt else { return false }
        return Date().timeIntervalSince(start) >= Self.testDurationSeconds
    }

    private func armTarget() {
        dotHitFlash = false
        dotIsTarget = true
        let stamp = Date()
        lastColorChangeAt = stamp
        colorChangeTimestamps.append(stamp)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reactionWindowSeconds) { [weak self] in
            Task { @MainActor in
                guard let self = self, case .running = self.phase else { return }
                guard self.dotIsTarget, self.lastColorChangeAt == stamp else { return }
                self.missedTargets += 1
                self.dotIsTarget = false
                self.scheduleNextCycle(after: Self.postMissPauseSeconds)
            }
        }
    }

    private func scheduleNextCycle(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in
                guard let self = self, case .running = self.phase else { return }
                self.dotHitFlash = false
                if self.testDurationExceeded {
                    self.finish()
                    return
                }
                self.moveDot()
                self.armTarget()
            }
        }
    }

    private func moveDot() {
        let x = CGFloat.random(in: 0.15...0.85)
        let y = CGFloat.random(in: 0.20...0.75)
        lastDotMoveAt = Date()
        lastAcceptedGazePoint = nil
        lastAcceptedGazeAt = nil
        withAnimation(.easeInOut(duration: 0.6)) {
            dotPosition = CGPoint(x: x, y: y)
        }
    }

    private func finish() {
        invalidateTimers()
        if gazeBackend == .vision { visionService?.stop() }
        motionTracker.stop()
        phase = .processing
        aiSummaryError = nil

        let samplesSnapshot = gazeSamples
        let hitsSnapshot = hits
        let missedSnapshot = missedTargets
        let falseTapsSnapshot = falseTaps
        let recordsSnapshot = calibrationRecords
        let transformSnapshot = calibrationTransform
        let residualSnapshot = calibrationResidual
        let calibrationSampleCountSnapshot = calibrationSamples.reduce(0) { $0 + $1.count }
        let calibrationBaselineSnapshot = calibrationBaselineHeadPose
        let backendName = gazeBackend.rawValue
        let calibStart = calibrationStartedAt ?? Date()
        let testStart = testStartedAt ?? Date()
        let availSnapshot = gazeAvailable
        let screenSnapshot = screenSize
        let durationSnapshot = Self.testDurationSeconds

        Task.detached(priority: .userInitiated) { [weak self] in
            let reactionTimes = hitsSnapshot.map { $0.tapDelayMs }
            let avg = reactionTimes.isEmpty ? 0 : reactionTimes.reduce(0, +) / Double(reactionTimes.count)
            let stdDev = EyeFocusTestManager.standardDeviation(reactionTimes)
            let reactionScore = EyeFocusTestManager.calculateScore(
                averageReactionMs: avg,
                reactionStdDevMs: stdDev,
                hitCount: reactionTimes.count,
                missedTargets: missedSnapshot,
                falseTaps: falseTapsSnapshot
            )
            let gazeMetrics = availSnapshot
                ? GazeAggregator.aggregate(samples: samplesSnapshot, durationSeconds: durationSnapshot)
                : nil

            let combined = EyeFocusTestResult.blend(reactionScore: reactionScore, gazeScore: gazeMetrics?.gazeScore)
            let completedAt = Date()
            let baseResult = EyeFocusTestResult(
                averageReactionMs: avg,
                reactionStdDevMs: stdDev,
                missedTargets: missedSnapshot,
                falseTaps: falseTapsSnapshot,
                reactionScore: reactionScore,
                gazeMetrics: gazeMetrics,
                eyeFocusScore: combined,
                aiSummary: nil,
                completedAt: completedAt
            )

            var savedURL: URL? = nil
            if availSnapshot {
                let summary = CalibrationSummary(
                    records: recordsSnapshot,
                    transform: transformSnapshot,
                    meanResidualNorm: residualSnapshot,
                    sampleCount: calibrationSampleCountSnapshot,
                    baselineHeadPose: calibrationBaselineSnapshot
                )
                let reactionLog = ReactionLog(
                    averageReactionMs: avg,
                    reactionStdDevMs: stdDev,
                    missedTargets: missedSnapshot,
                    falseTaps: falseTapsSnapshot,
                    hitCount: reactionTimes.count,
                    reactionTimesMs: reactionTimes
                )
                savedURL = GazeDataLogger.save(
                    samples: samplesSnapshot,
                    metrics: gazeMetrics,
                    backend: backendName,
                    startedAt: calibStart,
                    testStartedAt: testStart,
                    durationSeconds: durationSnapshot,
                    calibration: summary,
                    screenSize: screenSnapshot,
                    reaction: reactionLog
                )
            }

            let aiSummary: EyeFocusAISummary?
            var aiSummaryErrorMessage: String?
            if let savedURL {
                do {
                    aiSummary = try await OpenAIEyeFocusSummaryClient().summarizeLog(
                        at: savedURL,
                        result: baseResult
                    )
                } catch OpenAIEyeFocusSummaryError.missingAPIKey {
                    aiSummaryErrorMessage = "OpenAI API key is not configured in this app build. Regenerate local config, rebuild, and reinstall the app."
                    aiSummary = nil
                } catch {
                    aiSummaryErrorMessage = error.localizedDescription
                    log.error("AI gaze summary failed: \(error.localizedDescription, privacy: .public)")
                    aiSummary = nil
                }
            } else if availSnapshot {
                aiSummaryErrorMessage = "Gaze log was not saved, so the API summary could not be generated."
                aiSummary = nil
            } else {
                aiSummaryErrorMessage = "API summary requires gaze tracking data, which is not available on this device."
                aiSummary = nil
            }

            let result = EyeFocusTestResult(
                averageReactionMs: avg,
                reactionStdDevMs: stdDev,
                missedTargets: missedSnapshot,
                falseTaps: falseTapsSnapshot,
                reactionScore: reactionScore,
                gazeMetrics: gazeMetrics,
                eyeFocusScore: combined,
                aiSummary: aiSummary,
                completedAt: completedAt
            )
            let finalSavedURL = savedURL
            let finalAISummaryErrorMessage = aiSummaryErrorMessage

            await MainActor.run { [weak self] in
                self?.lastSavedLogURL = finalSavedURL
                self?.aiSummaryError = finalAISummaryErrorMessage
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
        calibrationSamples.removeAll()
        calibrationRecords.removeAll()
        calibrationTransform = .identity
        calibrationResidual = 0
        adaptiveBias = .zero
        lastSignificantMotionAt = .distantPast
        lastAcceptedGazePoint = nil
        lastAcceptedGazeAt = nil
        calibrationProgress = 0
        calibrationIsCollecting = false
        displayGazePoint = nil
        aiSummaryError = nil
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
        hitCount: Int,
        missedTargets: Int,
        falseTaps: Int
    ) -> Double {
        let totalTargets = hitCount + missedTargets
        guard totalTargets > 0 else { return 0 }
        let hitRate = Double(hitCount) / Double(totalTargets)
        let base = hitRate * 100.0

        let speedFactor: Double
        if hitCount > 0 {
            let overage = max(0, averageReactionMs - 400)
            speedFactor = max(0.3, min(1.0, 1.0 - overage / 1500.0))
        } else {
            speedFactor = 1.0
        }

        let consistencyFactor: Double
        if hitCount > 1 {
            consistencyFactor = max(0.6, min(1.0, 1.0 - reactionStdDevMs / 1500.0))
        } else {
            consistencyFactor = 1.0
        }

        let falseTapPenalty = Double(falseTaps) * 3
        let raw = base * speedFactor * consistencyFactor - falseTapPenalty
        return min(100, max(0, raw))
    }

    nonisolated static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count))
    }
}
