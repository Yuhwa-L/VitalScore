import Foundation

enum VoiceTaskType: String, Codable, CaseIterable {
    case silenceCalibration
    case sustainedVowelAFirst
    case sustainedVowelASecond
    case counting
    case fixedReading

    var displayName: String {
        switch self {
        case .silenceCalibration: return "Quiet calibration"
        case .sustainedVowelAFirst: return "Ahh vowel"
        case .sustainedVowelASecond: return "Ahh repeat"
        case .counting: return "Counting"
        case .fixedReading: return "Fixed reading"
        }
    }
}

struct VoiceTaskAnalysis: Codable, Equatable, Identifiable {
    var id: String { taskType.rawValue }

    let taskType: VoiceTaskType
    let promptId: String
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
    let eGeMAPS: VoiceEGeMAPSFeatureSet?
    let baselineSessionsUsed: Int
    let baselineStatus: String
    let topDrivers: [String]
    let featureExtractorVersion: String
    let modelVersion: String

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
            eGeMAPS: eGeMAPS,
            baselineSessionsUsed: baselineSessionsUsed,
            baselineStatus: baselineStatus,
            topDrivers: topDrivers,
            featureExtractorVersion: featureExtractorVersion,
            modelVersion: modelVersion
        )
    }
}
