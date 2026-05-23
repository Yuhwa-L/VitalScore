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

    let balanceScore: Double?
    let swayIndex: Double?

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
        balanceScore: Double? = nil,
        swayIndex: Double? = nil,
        selfReportedEnergy: Int? = nil,
        selfReportedStress: Int? = nil,
        selfReportedSleepQuality: Int? = nil,
        wellnessDeltaScore: Int,
        confidenceLevel: String,
        insightText: String
    ) {
        self.id = id
        self.date = date
        self.experimentTag = experimentTag
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
        self.balanceScore = balanceScore
        self.swayIndex = swayIndex
        self.selfReportedEnergy = selfReportedEnergy
        self.selfReportedStress = selfReportedStress
        self.selfReportedSleepQuality = selfReportedSleepQuality
        self.wellnessDeltaScore = wellnessDeltaScore
        self.confidenceLevel = confidenceLevel
        self.insightText = insightText
    }
}
