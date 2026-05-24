import AVFoundation
import Combine
import Foundation
import UIKit

struct VoiceTaskDefinition: Equatable {
    let type: VoiceTaskType
    let promptId: String
    let title: String
    let instruction: String
    let targetDurationSeconds: TimeInterval
    let minimumUsableDurationSeconds: TimeInterval
    let allowsEarlyFinish: Bool
}

final class VoiceTrackingManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case countdown(Int)
        case running
        case finished(VoiceTrackingResult)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var liveLevel: Double = 0
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var currentTaskIndex = 0
    @Published var currentTask = VoiceTaskDefinition(
        type: .silenceCalibration,
        promptId: "vw_en_v1_silence",
        title: "Quiet Calibration",
        instruction: "Please stay quiet while we measure background noise.",
        targetDurationSeconds: 3,
        minimumUsableDurationSeconds: 2.5,
        allowsEarlyFinish: false
    )

    static let silenceThresholdDb = -45.0
    static let featureExtractorVersion = "vitalscore_on_device_acoustic_v1"
    static let modelVersion = "personal_baseline_deviation_v1"
    static let promptVersion = "voice_check_v1"
    static let consentVersion = "voice_wellness_check_v1"
    static let rawAudioRetentionPolicy = "features_only_no_raw_audio"

    static let tasks: [VoiceTaskDefinition] = [
        VoiceTaskDefinition(
            type: .silenceCalibration,
            promptId: "vw_en_v1_silence",
            title: "Quiet Calibration",
            instruction: "Please stay quiet while we measure background noise.",
            targetDurationSeconds: 3,
            minimumUsableDurationSeconds: 2.5,
            allowsEarlyFinish: false
        ),
        VoiceTaskDefinition(
            type: .sustainedVowelAFirst,
            promptId: "vw_en_v1_ah_1",
            title: "Say Ahh",
            instruction: "Take a normal breath and say ahhh in your normal voice until the timer ends.",
            targetDurationSeconds: 5,
            minimumUsableDurationSeconds: 4,
            allowsEarlyFinish: true
        ),
        VoiceTaskDefinition(
            type: .sustainedVowelASecond,
            promptId: "vw_en_v1_ah_2",
            title: "Repeat Ahh",
            instruction: "Say ahhh one more time in the same comfortable voice.",
            targetDurationSeconds: 5,
            minimumUsableDurationSeconds: 4,
            allowsEarlyFinish: true
        ),
        VoiceTaskDefinition(
            type: .counting,
            promptId: "vw_en_v1_count_1_10",
            title: "Counting",
            instruction: "Count from 1 to 10 at a normal pace.",
            targetDurationSeconds: 6,
            minimumUsableDurationSeconds: 4,
            allowsEarlyFinish: true
        ),
        VoiceTaskDefinition(
            type: .fixedReading,
            promptId: "vw_en_v1_reading_001",
            title: "Read Aloud",
            instruction: "Read this in your normal voice: The morning light moved across the quiet city as people walked outside.",
            targetDurationSeconds: 18,
            minimumUsableDurationSeconds: 10,
            allowsEarlyFinish: true
        )
    ]

    var totalTargetDurationSeconds: TimeInterval {
        Self.tasks.reduce(0) { $0 + $1.targetDurationSeconds }
    }

    private let audioEngine = AVAudioEngine()
    private var countdownTimer: Timer?
    private var progressTimer: Timer?
    private var taskTimer: Timer?
    private var taskStartedAt: Date?
    private var sessionStartedAt: Date?
    private var currentFrames: [VoiceFrameSummary] = []
    private var completedTasks: [VoiceTaskAnalysis] = []
    private var isInputTapInstalled = false
    private var sessionSampleRate = 0.0
    private var sessionChannels = 1
    private var sessionMicrophoneRoute = "unknown"

    func start() {
        reset()
        phase = .requestingPermission
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.startCountdown()
                } else {
                    self.phase = .failed("Microphone access is required to run voice tracking.")
                }
            }
        }
    }

    func cancel() {
        stopAudio()
        invalidateTimers()
        reset()
        phase = .idle
    }

    func finishEarly() {
        guard case .running = phase, currentTask.allowsEarlyFinish else { return }
        completeCurrentTaskAndAdvance()
    }

    private func startCountdown() {
        phase = .countdown(3)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if case .countdown(let n) = self.phase {
                if n > 1 {
                    self.phase = .countdown(n - 1)
                } else {
                    self.countdownTimer?.invalidate()
                    self.beginSession()
                }
            }
        }
    }

    private func beginSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: [])
            sessionMicrophoneRoute = session.currentRoute.inputs.first?.portType.rawValue ?? "unknown"

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            sessionSampleRate = format.sampleRate
            sessionChannels = Int(format.channelCount)

            if isInputTapInstalled {
                input.removeTap(onBus: 0)
                isInputTapInstalled = false
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let frame = Self.frameSummary(from: buffer) else { return }
                DispatchQueue.main.async {
                    self?.recordFrame(frame)
                }
            }
            isInputTapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
            sessionStartedAt = Date()
            beginTask(at: 0)
        } catch {
            stopAudio()
            phase = .failed("Could not start the microphone. Please try again.")
        }
    }

    private func beginTask(at index: Int) {
        guard Self.tasks.indices.contains(index) else {
            finishSession()
            return
        }
        currentTaskIndex = index
        currentTask = Self.tasks[index]
        currentFrames.removeAll()
        liveLevel = 0
        elapsedSeconds = 0
        taskStartedAt = Date()
        phase = .running

        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let taskStartedAt = self.taskStartedAt else { return }
            self.elapsedSeconds = min(self.currentTask.targetDurationSeconds, Date().timeIntervalSince(taskStartedAt))
        }
        taskTimer?.invalidate()
        taskTimer = Timer.scheduledTimer(withTimeInterval: currentTask.targetDurationSeconds, repeats: false) { [weak self] _ in
            self?.completeCurrentTaskAndAdvance()
        }
    }

    private func completeCurrentTaskAndAdvance() {
        guard case .running = phase else { return }
        let duration = taskStartedAt.map { Date().timeIntervalSince($0) } ?? currentTask.targetDurationSeconds
        taskTimer?.invalidate()
        progressTimer?.invalidate()

        let noiseFloor = completedTasks.first(where: { $0.taskType == .silenceCalibration })?.averageVolumeDb
        completedTasks.append(Self.analyzeTask(
            currentTask,
            frames: currentFrames,
            durationSeconds: duration,
            noiseFloorDb: noiseFloor
        ))
        beginTask(at: currentTaskIndex + 1)
    }

    private func recordFrame(_ frame: VoiceFrameSummary) {
        guard case .running = phase else { return }
        currentFrames.append(frame)
        liveLevel = Self.normalizedLevel(from: frame.averagePowerDb)
    }

    private func finishSession() {
        stopAudio()
        invalidateTimers()
        let duration = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? totalTargetDurationSeconds
        phase = .finished(Self.makeResult(from: completedTasks, durationSeconds: duration))
    }

    private func stopAudio() {
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func reset() {
        currentTaskIndex = 0
        currentTask = Self.tasks[0]
        currentFrames.removeAll()
        completedTasks.removeAll()
        liveLevel = 0
        elapsedSeconds = 0
        taskStartedAt = nil
        sessionStartedAt = nil
        sessionSampleRate = 0
        sessionChannels = 1
        sessionMicrophoneRoute = "unknown"
    }

    private func invalidateTimers() {
        countdownTimer?.invalidate()
        progressTimer?.invalidate()
        taskTimer?.invalidate()
        countdownTimer = nil
        progressTimer = nil
        taskTimer = nil
    }

    func makeSessionMetadata(result: VoiceTrackingResult, experimentTag: String) -> VoiceTrackingSession {
        VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: experimentTag,
            promptTag: VoiceTrackingView.promptTag,
            language: "en-US",
            promptVersion: Self.promptVersion,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
            microphoneRoute: sessionMicrophoneRoute,
            sampleRate: sessionSampleRate,
            channels: sessionChannels,
            consentVersion: Self.consentVersion,
            rawAudioRetentionPolicy: Self.rawAudioRetentionPolicy,
            baselineVersion: "personal_median_mad_v1",
            featureExtractorVersion: Self.featureExtractorVersion,
            modelVersion: Self.modelVersion,
            result: result
        )
    }

    static func makeResult(from tasks: [VoiceTaskAnalysis], durationSeconds: TimeInterval) -> VoiceTrackingResult {
        let speechTasks = tasks.filter { $0.taskType != .silenceCalibration }
        let quality = average(tasks.map { $0.qualityScore }) ?? 0
        let usable = tasks.allSatisfy(\.usable)
        let issues = Array(Set(tasks.flatMap { $0.qualityIssues })).sorted()
        let averageVolume = average(speechTasks.map { $0.averageVolumeDb }) ?? -60
        let stdDev = average(speechTasks.map { $0.volumeStdDevDb }) ?? 0
        let silenceRatio = average(speechTasks.map { $0.silenceRatio }) ?? 1
        let peak = tasks.map { $0.peakVolumeDb }.max() ?? -60
        let eGeMAPS = aggregateEGeMAPS(from: speechTasks)
        let provisionalScore = calculateQualityOnlyScore(
            qualityScore: quality,
            volumeStdDevDb: stdDev,
            silenceRatio: silenceRatio,
            averageVolumeDb: averageVolume
        )

        return VoiceTrackingResult(
            completedAt: Date(),
            durationSeconds: durationSeconds,
            voiceScore: provisionalScore,
            voiceConfidence: usable ? "Low" : "Low",
            averageVolumeDb: averageVolume,
            volumeStdDevDb: stdDev,
            silenceRatio: silenceRatio,
            peakVolumeDb: peak,
            overallQualityScore: quality,
            usable: usable,
            qualityIssues: issues,
            taskAnalyses: tasks,
            eGeMAPS: eGeMAPS,
            baselineSessionsUsed: 0,
            baselineStatus: "building_baseline",
            topDrivers: usable ? ["Building your personal voice baseline."] : issues,
            featureExtractorVersion: featureExtractorVersion,
            modelVersion: modelVersion
        )
    }

    static func score(_ result: VoiceTrackingResult, against previousSessions: [VoiceTrackingSession]) -> VoiceTrackingResult {
        let usableBaseline = previousSessions
            .map(\.result)
            .filter { $0.usable && !$0.taskAnalyses.isEmpty }

        guard result.usable else {
            return result.scored(
                voiceScore: min(result.voiceScore, 50),
                confidence: "Low",
                baselineSessionsUsed: usableBaseline.count,
                baselineStatus: "recording_quality_low",
                topDrivers: result.qualityIssues
            )
        }

        guard usableBaseline.count >= 7 else {
            return result.scored(
                voiceScore: result.voiceScore,
                confidence: "Low",
                baselineSessionsUsed: usableBaseline.count,
                baselineStatus: "building_baseline",
                topDrivers: ["Building your voice baseline: \(usableBaseline.count) of 7 sessions collected."]
            )
        }

        let currentFeatures = baselineFeatures(from: result)
        var deviations: [(name: String, deviation: Double)] = []
        for (name, value) in currentFeatures {
            let baselineValues = usableBaseline.compactMap { baselineFeatures(from: $0)[name] }
            guard baselineValues.count >= 7 else { continue }
            let median = Self.median(baselineValues)
            let mad = Self.median(baselineValues.map { abs($0 - median) })
            let z = abs((value - median) / (1.4826 * mad + 0.001))
            deviations.append((name, min(z, 3)))
        }

        let voiceDeviation = weightedDeviation(deviations)
        let score = min(100, max(0, 100 - 20 * voiceDeviation))
        let confidence: String
        if usableBaseline.count >= 14 && result.overallQualityScore >= 0.8 {
            confidence = "High"
        } else if result.overallQualityScore >= 0.65 {
            confidence = "Medium"
        } else {
            confidence = "Low"
        }

        return result.scored(
            voiceScore: score,
            confidence: confidence,
            baselineSessionsUsed: usableBaseline.count,
            baselineStatus: "personal_baseline_active",
            topDrivers: deviations
                .sorted { $0.deviation > $1.deviation }
                .prefix(3)
                .map { driverLabel(for: $0.name, deviation: $0.deviation) }
        )
    }

    static func makeResult(from samples: [Double], durationSeconds: TimeInterval) -> VoiceTrackingResult {
        let frames = samples.map {
            VoiceFrameSummary(
                averagePowerDb: $0,
                peakAmplitude: 0,
                clippingPercentage: 0,
                zeroCrossingRate: 0,
                f0Hz: nil,
                hnrDb: nil
            )
        }
        let task = analyzeTask(
            VoiceTaskDefinition(
                type: .fixedReading,
                promptId: "legacy_single_task",
                title: "Voice check",
                instruction: "",
                targetDurationSeconds: durationSeconds,
                minimumUsableDurationSeconds: min(4, durationSeconds),
                allowsEarlyFinish: true
            ),
            frames: frames,
            durationSeconds: durationSeconds,
            noiseFloorDb: nil
        )
        return makeResult(from: [task], durationSeconds: durationSeconds)
    }

    static func analyzeTask(
        _ task: VoiceTaskDefinition,
        frames: [VoiceFrameSummary],
        durationSeconds: TimeInterval,
        noiseFloorDb: Double?
    ) -> VoiceTaskAnalysis {
        let dbValues = frames.map(\.averagePowerDb)
        let voiced = dbValues.filter { $0 > silenceThresholdDb }
        let analysisValues = task.type == .silenceCalibration ? dbValues : (voiced.isEmpty ? dbValues : voiced)
        let averageDb = average(analysisValues) ?? -80
        let stdDev = standardDeviation(analysisValues)
        let peakDb = dbValues.max() ?? -80
        let silenceRatio = dbValues.isEmpty ? 1 : Double(dbValues.filter { $0 <= silenceThresholdDb }.count) / Double(dbValues.count)
        let clipping = average(frames.map(\.clippingPercentage)) ?? 0
        let zcr = average(frames.map(\.zeroCrossingRate)) ?? 0
        let voicedRatio = dbValues.isEmpty ? 0 : Double(voiced.count) / Double(dbValues.count)
        let snr = noiseFloorDb.map { max(0, averageDb - $0) }
        let eGeMAPS = extractEGeMAPS(
            from: frames,
            durationSeconds: durationSeconds,
            fallbackAverageDb: averageDb,
            fallbackStdDevDb: stdDev
        )
        let issues = qualityIssues(
            task: task,
            durationSeconds: durationSeconds,
            silenceRatio: silenceRatio,
            clippingPercentage: clipping,
            snrDb: snr
        )
        let quality = qualityScore(
            durationSeconds: durationSeconds,
            minimumDuration: task.minimumUsableDurationSeconds,
            silenceRatio: silenceRatio,
            clippingPercentage: clipping,
            snrDb: snr
        )

        return VoiceTaskAnalysis(
            taskType: task.type,
            promptId: task.promptId,
            targetDurationSeconds: task.targetDurationSeconds,
            durationSeconds: durationSeconds,
            sampleCount: frames.count,
            averageVolumeDb: averageDb,
            volumeStdDevDb: stdDev,
            peakVolumeDb: peakDb,
            silenceRatio: silenceRatio,
            clippingPercentage: clipping,
            zeroCrossingRate: zcr,
            voicedFrameRatio: voicedRatio,
            snrDb: snr,
            eGeMAPS: eGeMAPS,
            qualityScore: quality,
            qualityIssues: issues,
            usable: issues.isEmpty || (quality >= 0.55 && !issues.contains("duration_too_short")),
            featureVersion: featureExtractorVersion
        )
    }

    static func calculateScore(volumeStdDevDb: Double, silenceRatio: Double, averageVolumeDb: Double) -> Double {
        calculateQualityOnlyScore(
            qualityScore: 1,
            volumeStdDevDb: volumeStdDevDb,
            silenceRatio: silenceRatio,
            averageVolumeDb: averageVolumeDb
        )
    }

    static func calculateQualityOnlyScore(
        qualityScore: Double,
        volumeStdDevDb: Double,
        silenceRatio: Double,
        averageVolumeDb: Double
    ) -> Double {
        let stabilityPenalty = volumeStdDevDb * 2
        let silencePenalty = silenceRatio * 45
        let quietPenalty = max(0, -38 - averageVolumeDb) * 1.5
        let clippingPenalty = max(0, averageVolumeDb + 8) * 1.5
        let qualityPenalty = (1 - qualityScore) * 35
        let raw = 100 - stabilityPenalty - silencePenalty - quietPenalty - clippingPenalty - qualityPenalty
        return min(100, max(0, raw))
    }

    static func frameSummary(from buffer: AVAudioPCMBuffer) -> VoiceFrameSummary? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let channel = channelData[0]
        var sumSquares: Float = 0
        var peak: Float = 0
        var clippingCount = 0
        var zeroCrossings = 0
        var previous = channel[0]

        for frame in 0..<frameLength {
            let sample = channel[frame]
            sumSquares += sample * sample
            peak = max(peak, abs(sample))
            if abs(sample) >= 0.98 { clippingCount += 1 }
            if frame > 0 && ((sample >= 0 && previous < 0) || (sample < 0 && previous >= 0)) {
                zeroCrossings += 1
            }
            previous = sample
        }

        let rms = sqrt(sumSquares / Float(frameLength))
        let db = rms > 0 ? max(-80, Double(20 * log10(rms))) : -80
        let pitch = estimatePitchAndHarmonics(channel: channel, frameLength: frameLength, sampleRate: buffer.format.sampleRate)
        return VoiceFrameSummary(
            averagePowerDb: db,
            peakAmplitude: Double(peak),
            clippingPercentage: Double(clippingCount) / Double(frameLength) * 100,
            zeroCrossingRate: Double(zeroCrossings) / Double(max(1, frameLength - 1)),
            f0Hz: pitch.f0Hz,
            hnrDb: pitch.hnrDb
        )
    }

    private static func estimatePitchAndHarmonics(
        channel: UnsafePointer<Float>,
        frameLength: Int,
        sampleRate: Double
    ) -> (f0Hz: Double?, hnrDb: Double?) {
        guard frameLength > 0, sampleRate > 0 else { return (nil, nil) }
        let minLag = max(1, Int(sampleRate / 500))
        let maxLag = min(frameLength / 2, Int(sampleRate / 70))
        guard minLag < maxLag else { return (nil, nil) }

        var energy = 0.0
        for i in 0..<frameLength {
            energy += Double(channel[i] * channel[i])
        }
        guard energy > 0.000001 else { return (nil, nil) }

        var bestLag = minLag
        var bestCorrelation = 0.0
        for lag in minLag...maxLag {
            var numerator = 0.0
            var delayedEnergy = 0.0
            let limit = frameLength - lag
            for i in 0..<limit {
                let current = Double(channel[i])
                let delayed = Double(channel[i + lag])
                numerator += current * delayed
                delayedEnergy += delayed * delayed
            }
            let normalized = numerator / sqrt(max(energy * delayedEnergy, 0.000001))
            if normalized > bestCorrelation {
                bestCorrelation = normalized
                bestLag = lag
            }
        }

        guard bestCorrelation > 0.35 else { return (nil, nil) }
        let harmonic = min(0.99, max(0.001, bestCorrelation))
        let noise = max(0.001, 1 - harmonic)
        return (sampleRate / Double(bestLag), 10 * log10(harmonic / noise))
    }

    static func averagePowerDb(from buffer: AVAudioPCMBuffer) -> Double? {
        frameSummary(from: buffer)?.averagePowerDb
    }

    static func normalizedLevel(from db: Double) -> Double {
        min(1, max(0, (db + 60) / 60))
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count))
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func qualityIssues(
        task: VoiceTaskDefinition,
        durationSeconds: TimeInterval,
        silenceRatio: Double,
        clippingPercentage: Double,
        snrDb: Double?
    ) -> [String] {
        var issues: [String] = []
        if durationSeconds < task.minimumUsableDurationSeconds {
            issues.append("duration_too_short")
        }
        if task.type == .silenceCalibration {
            if silenceRatio < 0.8 {
                issues.append("speech_during_silence_calibration")
            }
            return issues
        }
        if silenceRatio > 0.55 {
            issues.append("too_much_silence")
        }
        if clippingPercentage > 1 {
            issues.append("clipping_detected")
        }
        if let snrDb = snrDb, snrDb < 10 {
            issues.append("snr_low")
        }
        return issues
    }

    private static func qualityScore(
        durationSeconds: TimeInterval,
        minimumDuration: TimeInterval,
        silenceRatio: Double,
        clippingPercentage: Double,
        snrDb: Double?
    ) -> Double {
        let durationScore = min(1, max(0, durationSeconds / minimumDuration))
        let silenceScore = max(0, 1 - max(0, silenceRatio - 0.2) / 0.6)
        let clippingScore = max(0, 1 - clippingPercentage / 1)
        let snrScore = snrDb.map { min(1, max(0, $0 / 20)) } ?? 0.8
        return min(1, max(0, durationScore * 0.35 + silenceScore * 0.25 + clippingScore * 0.20 + snrScore * 0.20))
    }

    private static func baselineFeatures(from result: VoiceTrackingResult) -> [String: Double] {
        let vowelTasks = result.taskAnalyses.filter {
            $0.taskType == .sustainedVowelAFirst || $0.taskType == .sustainedVowelASecond
        }
        let speechTasks = result.taskAnalyses.filter {
            $0.taskType == .counting || $0.taskType == .fixedReading
        }
        return [
            "vowel_stability": average(vowelTasks.map(\.volumeStdDevDb)) ?? result.volumeStdDevDb,
            "vowel_clarity": average(vowelTasks.map(\.zeroCrossingRate)) ?? 0,
            "speech_pause_ratio": average(speechTasks.map(\.silenceRatio)) ?? result.silenceRatio,
            "speech_energy": average(speechTasks.map(\.averageVolumeDb)) ?? result.averageVolumeDb,
            "speech_rhythm": average(speechTasks.map(\.volumeStdDevDb)) ?? result.volumeStdDevDb,
            "quality": result.overallQualityScore,
            "f0_stability": result.eGeMAPS?.f0StdDevHz ?? 0,
            "jitter": result.eGeMAPS?.jitterLocalPercent ?? 0,
            "shimmer": result.eGeMAPS?.shimmerLocalDb ?? 0,
            "hnr": result.eGeMAPS?.hnrMeanDb ?? 0,
            "spectral_flux": result.eGeMAPS?.spectralFlux ?? 0
        ]
    }

    private static func weightedDeviation(_ deviations: [(name: String, deviation: Double)]) -> Double {
        guard !deviations.isEmpty else { return 0 }
        let weights: [String: Double] = [
            "vowel_stability": 0.25,
            "vowel_clarity": 0.15,
            "speech_pause_ratio": 0.25,
            "speech_energy": 0.15,
            "speech_rhythm": 0.15,
            "quality": 0.05,
            "f0_stability": 0.12,
            "jitter": 0.10,
            "shimmer": 0.10,
            "hnr": 0.10,
            "spectral_flux": 0.08
        ]
        let weighted = deviations.reduce((score: 0.0, weight: 0.0)) { partial, item in
            let weight = weights[item.name] ?? 0.1
            return (partial.score + item.deviation * weight, partial.weight + weight)
        }
        return weighted.weight > 0 ? weighted.score / weighted.weight : 0
    }

    private static func driverLabel(for featureName: String, deviation: Double) -> String {
        let amount: String
        if deviation >= 2 { amount = "large" }
        else if deviation >= 1 { amount = "moderate" }
        else { amount = "mild" }

        switch featureName {
        case "vowel_stability":
            return "\(amount.capitalized) change in sustained-vowel stability versus baseline."
        case "vowel_clarity":
            return "\(amount.capitalized) change in vowel acoustic clarity versus baseline."
        case "speech_pause_ratio":
            return "\(amount.capitalized) change in pause time versus baseline."
        case "speech_energy":
            return "\(amount.capitalized) change in speaking energy versus baseline."
        case "speech_rhythm":
            return "\(amount.capitalized) change in speech rhythm versus baseline."
        case "f0_stability":
            return "\(amount.capitalized) change in pitch stability versus baseline."
        case "jitter":
            return "\(amount.capitalized) change in cycle-to-cycle pitch variation versus baseline."
        case "shimmer":
            return "\(amount.capitalized) change in amplitude shimmer versus baseline."
        case "hnr":
            return "\(amount.capitalized) change in harmonic voice quality versus baseline."
        case "spectral_flux":
            return "\(amount.capitalized) change in frame-to-frame spectral movement versus baseline."
        default:
            return "\(amount.capitalized) voice-signal change versus baseline."
        }
    }

    private static func aggregateEGeMAPS(from tasks: [VoiceTaskAnalysis]) -> VoiceEGeMAPSFeatureSet? {
        let featureSets = tasks.compactMap(\.eGeMAPS)
        guard !featureSets.isEmpty else { return nil }
        return VoiceEGeMAPSFeatureSet(
            loudnessMeanDb: average(featureSets.map(\.loudnessMeanDb)) ?? -80,
            loudnessStdDevDb: average(featureSets.map(\.loudnessStdDevDb)) ?? 0,
            f0MeanHz: average(featureSets.compactMap(\.f0MeanHz)),
            f0StdDevHz: average(featureSets.compactMap(\.f0StdDevHz)),
            jitterLocalPercent: average(featureSets.compactMap(\.jitterLocalPercent)),
            shimmerLocalDb: average(featureSets.compactMap(\.shimmerLocalDb)),
            hnrMeanDb: average(featureSets.compactMap(\.hnrMeanDb)),
            alphaRatioDb: average(featureSets.map(\.alphaRatioDb)) ?? 0,
            hammarbergIndexDb: average(featureSets.map(\.hammarbergIndexDb)) ?? 0,
            spectralFlux: average(featureSets.map(\.spectralFlux)) ?? 0,
            slopeV0: average(featureSets.map(\.slopeV0)) ?? 0,
            slopeUV0: average(featureSets.map(\.slopeUV0)) ?? 0,
            mfcc1Mean: average(featureSets.map(\.mfcc1Mean)) ?? 0,
            mfcc2Mean: average(featureSets.map(\.mfcc2Mean)) ?? 0,
            mfcc3Mean: average(featureSets.map(\.mfcc3Mean)) ?? 0,
            voicedSegmentsPerSecond: average(featureSets.map(\.voicedSegmentsPerSecond)) ?? 0,
            meanVoicedSegmentLengthSeconds: average(featureSets.map(\.meanVoicedSegmentLengthSeconds)) ?? 0
        )
    }

    private static func extractEGeMAPS(
        from frames: [VoiceFrameSummary],
        durationSeconds: TimeInterval,
        fallbackAverageDb: Double,
        fallbackStdDevDb: Double
    ) -> VoiceEGeMAPSFeatureSet {
        let voicedFrames = frames.filter { $0.averagePowerDb > silenceThresholdDb }
        let analysisFrames = voicedFrames.isEmpty ? frames : voicedFrames
        let dbValues = analysisFrames.map(\.averagePowerDb)
        let zcrValues = analysisFrames.map(\.zeroCrossingRate)
        let f0Values = analysisFrames.compactMap(\.f0Hz)
        let hnrValues = analysisFrames.compactMap(\.hnrDb)
        let adjacentPitchDiffs = zip(f0Values.dropFirst(), f0Values).map { abs($0 - $1) }
        let f0Mean = average(f0Values)
        let jitter = f0Mean.flatMap { mean in
            mean > 0 ? average(adjacentPitchDiffs).map { $0 / mean * 100 } : nil
        }
        let shimmer = average(zip(dbValues.dropFirst(), dbValues).map { abs($0 - $1) })
        let spectralFlux = average(zip(dbValues.dropFirst(), dbValues).map { abs($0 - $1) / 80 }) ?? 0
        let zcrMean = average(zcrValues) ?? 0
        let voicedDurations = voicedSegmentDurations(from: frames, durationSeconds: durationSeconds)

        let loudnessStdDev = dbValues.count > 1 ? standardDeviation(dbValues) : fallbackStdDevDb

        return VoiceEGeMAPSFeatureSet(
            loudnessMeanDb: average(dbValues) ?? fallbackAverageDb,
            loudnessStdDevDb: loudnessStdDev,
            f0MeanHz: f0Mean,
            f0StdDevHz: f0Values.count > 1 ? standardDeviation(f0Values) : nil,
            jitterLocalPercent: jitter,
            shimmerLocalDb: shimmer,
            hnrMeanDb: average(hnrValues),
            alphaRatioDb: (zcrMean - 0.08) * 80,
            hammarbergIndexDb: max(0, 24 - zcrMean * 120),
            spectralFlux: spectralFlux,
            slopeV0: -zcrMean * 30,
            slopeUV0: -(average(frames.map(\.zeroCrossingRate)) ?? zcrMean) * 24,
            mfcc1Mean: (average(dbValues) ?? fallbackAverageDb) / 10,
            mfcc2Mean: zcrMean * 20,
            mfcc3Mean: (f0Mean ?? 0) / 100,
            voicedSegmentsPerSecond: durationSeconds > 0 ? Double(voicedDurations.count) / durationSeconds : 0,
            meanVoicedSegmentLengthSeconds: average(voicedDurations) ?? 0
        )
    }

    private static func voicedSegmentDurations(from frames: [VoiceFrameSummary], durationSeconds: TimeInterval) -> [Double] {
        guard !frames.isEmpty, durationSeconds > 0 else { return [] }
        let frameDuration = durationSeconds / Double(frames.count)
        var segments: [Double] = []
        var current = 0.0
        for frame in frames {
            if frame.averagePowerDb > silenceThresholdDb {
                current += frameDuration
            } else if current > 0 {
                segments.append(current)
                current = 0
            }
        }
        if current > 0 { segments.append(current) }
        return segments
    }
}

struct VoiceFrameSummary {
    let averagePowerDb: Double
    let peakAmplitude: Double
    let clippingPercentage: Double
    let zeroCrossingRate: Double
    let f0Hz: Double?
    let hnrDb: Double?
}
