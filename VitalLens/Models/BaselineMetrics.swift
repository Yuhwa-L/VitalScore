import Foundation

struct BaselineMetrics: Codable {
    let startDate: Date
    let endDate: Date
    let averageSleepHours: Double?
    let averageRestingHeartRateBPM: Double?
    let averageHRVMs: Double?
    let averageStepCount: Double?
    let averageEyeFocusScore: Double?
    let averageBalanceScore: Double?

    static let empty = BaselineMetrics(
        startDate: Date(),
        endDate: Date(),
        averageSleepHours: nil,
        averageRestingHeartRateBPM: nil,
        averageHRVMs: nil,
        averageStepCount: nil,
        averageEyeFocusScore: nil,
        averageBalanceScore: nil
    )
}
