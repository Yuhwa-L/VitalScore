import Foundation

struct BaselineMetrics: Codable {
    let startDate: Date
    let endDate: Date
    let averageSleepHours: Double?
    let averageRestingHeartRateBPM: Double?
    let averageHRVMs: Double?
    let averageStepCount: Double?
    let averageEyeFocusScore: Double?
    let averageGazeScore: Double?
    let averageGazeAccuracyPx: Double?
    let averageBalanceScore: Double?
    let averageVoiceScore: Double?
    let averageSelfReportedEnergy: Double?
    let averageSelfReportedStress: Double?
    let averageSelfReportedSleepQuality: Double?

    init(
        startDate: Date,
        endDate: Date,
        averageSleepHours: Double?,
        averageRestingHeartRateBPM: Double?,
        averageHRVMs: Double?,
        averageStepCount: Double?,
        averageEyeFocusScore: Double?,
        averageGazeScore: Double? = nil,
        averageGazeAccuracyPx: Double? = nil,
        averageBalanceScore: Double?,
        averageVoiceScore: Double? = nil,
        averageSelfReportedEnergy: Double? = nil,
        averageSelfReportedStress: Double? = nil,
        averageSelfReportedSleepQuality: Double? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.averageSleepHours = averageSleepHours
        self.averageRestingHeartRateBPM = averageRestingHeartRateBPM
        self.averageHRVMs = averageHRVMs
        self.averageStepCount = averageStepCount
        self.averageEyeFocusScore = averageEyeFocusScore
        self.averageGazeScore = averageGazeScore
        self.averageGazeAccuracyPx = averageGazeAccuracyPx
        self.averageBalanceScore = averageBalanceScore
        self.averageVoiceScore = averageVoiceScore
        self.averageSelfReportedEnergy = averageSelfReportedEnergy
        self.averageSelfReportedStress = averageSelfReportedStress
        self.averageSelfReportedSleepQuality = averageSelfReportedSleepQuality
    }

    static let empty = BaselineMetrics(
        startDate: Date(),
        endDate: Date(),
        averageSleepHours: nil,
        averageRestingHeartRateBPM: nil,
        averageHRVMs: nil,
        averageStepCount: nil,
        averageEyeFocusScore: nil,
        averageGazeScore: nil,
        averageGazeAccuracyPx: nil,
        averageBalanceScore: nil,
        averageVoiceScore: nil,
        averageSelfReportedEnergy: nil,
        averageSelfReportedStress: nil,
        averageSelfReportedSleepQuality: nil
    )
}
