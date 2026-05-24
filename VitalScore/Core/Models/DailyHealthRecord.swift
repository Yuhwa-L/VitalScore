import Foundation

struct DailyHealthRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let experimentTag: String

    let sleepHours: Double?
    let restingHeartRateBPM: Double?
    let hrvMs: Double?
    let stepCount: Double?
    let activeEnergyKcal: Double?

    let eyeFocusScore: Double?
    let averageReactionMs: Double?
    let reactionStdDevMs: Double?
    let missedTargets: Int?
    let falseTaps: Int?

    let gazeAccuracyPx: Double?
    let gazeStabilityPx: Double?
    let gazeFixationMs: Double?
    let gazeBlinkRatePerMin: Double?
    let gazeTrackingLossPct: Double?
    let gazeScore: Double?

    let balanceScore: Double?
    let swayIndex: Double?

    let voiceScore: Double?
    let voiceAverageVolumeDb: Double?
    let voiceVolumeStdDevDb: Double?
    let voiceSilenceRatio: Double?
    let voicePeakVolumeDb: Double?

    let selfReportedEnergy: Int?
    let selfReportedStress: Int?
    let selfReportedSleepQuality: Int?

    let wellnessDeltaScore: Int
    let confidenceLevel: String
    let insightText: String

    init(
        id: UUID = UUID(),
        date: Date,
        experimentTag: String,
        sleepHours: Double? = nil,
        restingHeartRateBPM: Double? = nil,
        hrvMs: Double? = nil,
        stepCount: Double? = nil,
        activeEnergyKcal: Double? = nil,
        eyeFocusScore: Double? = nil,
        averageReactionMs: Double? = nil,
        reactionStdDevMs: Double? = nil,
        missedTargets: Int? = nil,
        falseTaps: Int? = nil,
        gazeAccuracyPx: Double? = nil,
        gazeStabilityPx: Double? = nil,
        gazeFixationMs: Double? = nil,
        gazeBlinkRatePerMin: Double? = nil,
        gazeTrackingLossPct: Double? = nil,
        gazeScore: Double? = nil,
        balanceScore: Double? = nil,
        swayIndex: Double? = nil,
        voiceScore: Double? = nil,
        voiceAverageVolumeDb: Double? = nil,
        voiceVolumeStdDevDb: Double? = nil,
        voiceSilenceRatio: Double? = nil,
        voicePeakVolumeDb: Double? = nil,
        selfReportedEnergy: Int? = nil,
        selfReportedStress: Int? = nil,
        selfReportedSleepQuality: Int? = nil,
        wellnessDeltaScore: Int,
        confidenceLevel: String,
        insightText: String
    ) {
        self.id = id
        self.date = date
        self.experimentTag = ExperimentTagValue.normalized(experimentTag)
        self.sleepHours = sleepHours
        self.restingHeartRateBPM = restingHeartRateBPM
        self.hrvMs = hrvMs
        self.stepCount = stepCount
        self.activeEnergyKcal = activeEnergyKcal
        self.eyeFocusScore = eyeFocusScore
        self.averageReactionMs = averageReactionMs
        self.reactionStdDevMs = reactionStdDevMs
        self.missedTargets = missedTargets
        self.falseTaps = falseTaps
        self.gazeAccuracyPx = gazeAccuracyPx
        self.gazeStabilityPx = gazeStabilityPx
        self.gazeFixationMs = gazeFixationMs
        self.gazeBlinkRatePerMin = gazeBlinkRatePerMin
        self.gazeTrackingLossPct = gazeTrackingLossPct
        self.gazeScore = gazeScore
        self.balanceScore = balanceScore
        self.swayIndex = swayIndex
        self.voiceScore = voiceScore
        self.voiceAverageVolumeDb = voiceAverageVolumeDb
        self.voiceVolumeStdDevDb = voiceVolumeStdDevDb
        self.voiceSilenceRatio = voiceSilenceRatio
        self.voicePeakVolumeDb = voicePeakVolumeDb
        self.selfReportedEnergy = selfReportedEnergy
        self.selfReportedStress = selfReportedStress
        self.selfReportedSleepQuality = selfReportedSleepQuality
        self.wellnessDeltaScore = wellnessDeltaScore
        self.confidenceLevel = confidenceLevel
        self.insightText = insightText
    }
}
