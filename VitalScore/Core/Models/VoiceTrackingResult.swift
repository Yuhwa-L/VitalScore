import Foundation

enum VoiceTaskType: String, Codable, CaseIterable {
    case silenceCalibration
    case sustainedVowelAFirst
    case sustainedVowelASecond
    case counting
    case fixedReading
    case guidedConversation

    var displayName: String {
        switch self {
        case .silenceCalibration: return "Quiet calibration"
        case .sustainedVowelAFirst: return "Ahh vowel"
        case .sustainedVowelASecond: return "Ahh repeat"
        case .counting: return "Counting"
        case .fixedReading: return "Fixed reading"
        case .guidedConversation: return "Guided conversation"
        }
    }
}

struct VoiceTaskAnalysis: Codable, Equatable, Identifiable {
    var id: String { promptId }

    let taskType: VoiceTaskType
    let promptId: String
    let promptText: String?
    let targetDurationSeconds: TimeInterval
    let durationSeconds: TimeInterval
    let sampleCount: Int
    let averageVolumeDb: Double
    let volumeStdDevDb: Double
    let peakVolumeDb: Double
    let silenceRatio: Double
    let clippingPercentage: Double
    let zeroCrossingRate: Double
    let voicedFrameRatio: Double
    let snrDb: Double?
    let eGeMAPS: VoiceEGeMAPSFeatureSet?
    let qualityScore: Double
    let qualityIssues: [String]
    let usable: Bool
    let featureVersion: String

    func removingLivePromptText() -> VoiceTaskAnalysis {
        guard taskType == .guidedConversation else { return self }
        return VoiceTaskAnalysis(
            taskType: taskType,
            promptId: promptId,
            promptText: nil,
            targetDurationSeconds: targetDurationSeconds,
            durationSeconds: durationSeconds,
            sampleCount: sampleCount,
            averageVolumeDb: averageVolumeDb,
            volumeStdDevDb: volumeStdDevDb,
            peakVolumeDb: peakVolumeDb,
            silenceRatio: silenceRatio,
            clippingPercentage: clippingPercentage,
            zeroCrossingRate: zeroCrossingRate,
            voicedFrameRatio: voicedFrameRatio,
            snrDb: snrDb,
            eGeMAPS: eGeMAPS,
            qualityScore: qualityScore,
            qualityIssues: qualityIssues,
            usable: usable,
            featureVersion: featureVersion
        )
    }
}

struct VoiceEGeMAPSFeatureSet: Codable, Equatable {
    let loudnessMeanDb: Double
    let loudnessStdDevDb: Double
    let f0MeanHz: Double?
    let f0StdDevHz: Double?
    let jitterLocalPercent: Double?
    let shimmerLocalDb: Double?
    let hnrMeanDb: Double?
    let alphaRatioDb: Double
    let hammarbergIndexDb: Double
    let spectralFlux: Double
    let slopeV0: Double
    let slopeUV0: Double
    let mfcc1Mean: Double
    let mfcc2Mean: Double
    let mfcc3Mean: Double
    let voicedSegmentsPerSecond: Double
    let meanVoicedSegmentLengthSeconds: Double
}

enum VoiceFeatureValidationStatus: String, Codable, Equatable, CaseIterable {
    case validated
    case proxy
    case unsupported

    var displayName: String {
        switch self {
        case .validated: return "Validated"
        case .proxy: return "Proxy"
        case .unsupported: return "Unsupported"
        }
    }
}

struct VoiceFeatureValidation: Codable, Equatable, Identifiable {
    var id: String { key }

    let key: String
    let label: String
    let status: VoiceFeatureValidationStatus
    let scoreEligible: Bool
    let note: String
}

enum VoiceFeatureValidationCatalog {
    static let all: [VoiceFeatureValidation] = [
        VoiceFeatureValidation(
            key: "loudnessMeanDb",
            label: "Loudness mean",
            status: .proxy,
            scoreEligible: true,
            note: "RMS dB proxy; needs openSMILE loudness calibration."
        ),
        VoiceFeatureValidation(
            key: "loudnessStdDevDb",
            label: "Loudness variation",
            status: .proxy,
            scoreEligible: true,
            note: "RMS dB variability proxy."
        ),
        VoiceFeatureValidation(
            key: "f0MeanHz",
            label: "F0 mean",
            status: .proxy,
            scoreEligible: false,
            note: "Autocorrelation pitch estimate; not yet matched to canonical openSMILE."
        ),
        VoiceFeatureValidation(
            key: "f0StdDevHz",
            label: "F0 variation",
            status: .proxy,
            scoreEligible: false,
            note: "Autocorrelation pitch variation estimate; withheld from score."
        ),
        VoiceFeatureValidation(
            key: "jitterLocalPercent",
            label: "Jitter local",
            status: .unsupported,
            scoreEligible: false,
            note: "Frame-level approximation, not cycle-level jitter."
        ),
        VoiceFeatureValidation(
            key: "shimmerLocalDb",
            label: "Shimmer local",
            status: .unsupported,
            scoreEligible: false,
            note: "Frame-level dB delta, not cycle-level shimmer."
        ),
        VoiceFeatureValidation(
            key: "hnrMeanDb",
            label: "HNR mean",
            status: .proxy,
            scoreEligible: false,
            note: "Autocorrelation harmonicity proxy; withheld until offline comparison."
        ),
        VoiceFeatureValidation(
            key: "spectralFlux",
            label: "Spectral flux",
            status: .proxy,
            scoreEligible: true,
            note: "Frame-to-frame energy movement proxy."
        ),
        VoiceFeatureValidation(
            key: "mfcc1Mean",
            label: "MFCC 1",
            status: .unsupported,
            scoreEligible: false,
            note: "Placeholder transform, not a canonical MFCC."
        ),
        VoiceFeatureValidation(
            key: "mfcc2Mean",
            label: "MFCC 2",
            status: .unsupported,
            scoreEligible: false,
            note: "Placeholder transform, not a canonical MFCC."
        ),
        VoiceFeatureValidation(
            key: "mfcc3Mean",
            label: "MFCC 3",
            status: .unsupported,
            scoreEligible: false,
            note: "Placeholder transform, not a canonical MFCC."
        ),
        VoiceFeatureValidation(
            key: "voicedSegmentsPerSecond",
            label: "Voiced segment rate",
            status: .proxy,
            scoreEligible: true,
            note: "Silence-threshold segment proxy."
        ),
        VoiceFeatureValidation(
            key: "meanVoicedSegmentLengthSeconds",
            label: "Mean voiced length",
            status: .proxy,
            scoreEligible: true,
            note: "Silence-threshold segment proxy."
        ),
        VoiceFeatureValidation(
            key: "alphaRatioDb",
            label: "Alpha ratio",
            status: .unsupported,
            scoreEligible: false,
            note: "Placeholder estimate; display only until canonical comparison."
        ),
        VoiceFeatureValidation(
            key: "hammarbergIndexDb",
            label: "Hammarberg index",
            status: .unsupported,
            scoreEligible: false,
            note: "Placeholder estimate; display only until canonical comparison."
        ),
        VoiceFeatureValidation(
            key: "slopeV0",
            label: "Slope V0",
            status: .unsupported,
            scoreEligible: false,
            note: "Placeholder estimate; display only until canonical comparison."
        ),
        VoiceFeatureValidation(
            key: "slopeUV0",
            label: "Slope UV0",
            status: .unsupported,
            scoreEligible: false,
            note: "Placeholder estimate; display only until canonical comparison."
        )
    ]

    static func validation(for key: String) -> VoiceFeatureValidation {
        all.first { $0.key == key } ?? VoiceFeatureValidation(
            key: key,
            label: key,
            status: .unsupported,
            scoreEligible: false,
            note: "Not in the validation catalog."
        )
    }
}

struct VoiceConversationExchange: Codable, Equatable, Identifiable {
    let id: UUID
    let turnIndex: Int
    let aiPrompt: String
    let userTranscript: String
    let userResponseStartedAt: Date
    let userResponseEndedAt: Date
    let responseDurationSeconds: TimeInterval
    let source: String

    init(
        id: UUID = UUID(),
        turnIndex: Int,
        aiPrompt: String,
        userTranscript: String,
        userResponseStartedAt: Date,
        userResponseEndedAt: Date,
        responseDurationSeconds: TimeInterval,
        source: String
    ) {
        self.id = id
        self.turnIndex = turnIndex
        self.aiPrompt = aiPrompt
        self.userTranscript = userTranscript
        self.userResponseStartedAt = userResponseStartedAt
        self.userResponseEndedAt = userResponseEndedAt
        self.responseDurationSeconds = responseDurationSeconds
        self.source = source
    }
}

struct VoiceConversationSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let questionCount: Int
    let summary: String
    let source: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        questionCount: Int,
        summary: String,
        source: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.questionCount = questionCount
        self.summary = summary
        self.source = source
    }
}

struct VoiceTrackingResult: Codable, Equatable, Identifiable {
    let id: UUID
    let completedAt: Date
    let durationSeconds: TimeInterval
    let voiceScore: Double
    let voiceConfidence: String
    let averageVolumeDb: Double
    let volumeStdDevDb: Double
    let silenceRatio: Double
    let peakVolumeDb: Double
    let overallQualityScore: Double
    let usable: Bool
    let qualityIssues: [String]
    let taskAnalyses: [VoiceTaskAnalysis]
    let conversationExchanges: [VoiceConversationExchange]
    let conversationSummary: VoiceConversationSummary?
    let eGeMAPS: VoiceEGeMAPSFeatureSet?
    let baselineSessionsUsed: Int
    let baselineStatus: String
    let topDrivers: [String]
    let featureExtractorVersion: String
    let modelVersion: String

    var hasLiveConversationTask: Bool {
        taskAnalyses.contains { $0.taskType == .guidedConversation }
    }

    var containsLocallySavedLiveData: Bool {
        !conversationExchanges.isEmpty ||
        conversationSummary != nil ||
        taskAnalyses.contains {
            $0.taskType == .guidedConversation &&
            $0.promptText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    init(
        id: UUID = UUID(),
        completedAt: Date,
        durationSeconds: TimeInterval,
        voiceScore: Double,
        voiceConfidence: String = "Low",
        averageVolumeDb: Double,
        volumeStdDevDb: Double,
        silenceRatio: Double,
        peakVolumeDb: Double,
        overallQualityScore: Double = 0,
        usable: Bool = true,
        qualityIssues: [String] = [],
        taskAnalyses: [VoiceTaskAnalysis] = [],
        conversationExchanges: [VoiceConversationExchange] = [],
        conversationSummary: VoiceConversationSummary? = nil,
        eGeMAPS: VoiceEGeMAPSFeatureSet? = nil,
        baselineSessionsUsed: Int = 0,
        baselineStatus: String = "building_baseline",
        topDrivers: [String] = [],
        featureExtractorVersion: String = "vitalscore_on_device_acoustic_v1",
        modelVersion: String = "personal_baseline_deviation_v1"
    ) {
        self.id = id
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.voiceScore = voiceScore
        self.voiceConfidence = voiceConfidence
        self.averageVolumeDb = averageVolumeDb
        self.volumeStdDevDb = volumeStdDevDb
        self.silenceRatio = silenceRatio
        self.peakVolumeDb = peakVolumeDb
        self.overallQualityScore = overallQualityScore
        self.usable = usable
        self.qualityIssues = qualityIssues
        self.taskAnalyses = taskAnalyses
        self.conversationExchanges = conversationExchanges
        self.conversationSummary = conversationSummary
        self.eGeMAPS = eGeMAPS
        self.baselineSessionsUsed = baselineSessionsUsed
        self.baselineStatus = baselineStatus
        self.topDrivers = topDrivers
        self.featureExtractorVersion = featureExtractorVersion
        self.modelVersion = modelVersion
    }

    func scored(
        voiceScore: Double,
        confidence: String,
        baselineSessionsUsed: Int,
        baselineStatus: String,
        topDrivers: [String]
    ) -> VoiceTrackingResult {
        VoiceTrackingResult(
            id: id,
            completedAt: completedAt,
            durationSeconds: durationSeconds,
            voiceScore: voiceScore,
            voiceConfidence: confidence,
            averageVolumeDb: averageVolumeDb,
            volumeStdDevDb: volumeStdDevDb,
            silenceRatio: silenceRatio,
            peakVolumeDb: peakVolumeDb,
            overallQualityScore: overallQualityScore,
            usable: usable,
            qualityIssues: qualityIssues,
            taskAnalyses: taskAnalyses,
            conversationExchanges: conversationExchanges,
            conversationSummary: conversationSummary,
            eGeMAPS: eGeMAPS,
            baselineSessionsUsed: baselineSessionsUsed,
            baselineStatus: baselineStatus,
            topDrivers: topDrivers,
            featureExtractorVersion: featureExtractorVersion,
            modelVersion: modelVersion
        )
    }

    func removingLocallySavedLiveData() -> VoiceTrackingResult {
        guard containsLocallySavedLiveData else { return self }
        return VoiceTrackingResult(
            id: id,
            completedAt: completedAt,
            durationSeconds: durationSeconds,
            voiceScore: voiceScore,
            voiceConfidence: voiceConfidence,
            averageVolumeDb: averageVolumeDb,
            volumeStdDevDb: volumeStdDevDb,
            silenceRatio: silenceRatio,
            peakVolumeDb: peakVolumeDb,
            overallQualityScore: overallQualityScore,
            usable: usable,
            qualityIssues: qualityIssues,
            taskAnalyses: taskAnalyses.map { $0.removingLivePromptText() },
            conversationExchanges: [],
            conversationSummary: nil,
            eGeMAPS: eGeMAPS,
            baselineSessionsUsed: baselineSessionsUsed,
            baselineStatus: baselineStatus,
            topDrivers: topDrivers,
            featureExtractorVersion: featureExtractorVersion,
            modelVersion: modelVersion
        )
    }
}
