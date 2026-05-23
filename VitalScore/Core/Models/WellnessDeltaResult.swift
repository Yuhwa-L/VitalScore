import Foundation

struct WellnessDeltaResult: Codable {
    let score: Int
    let confidence: String
    let insightText: String
    let availableMetricCount: Int
    let positiveMetricCount: Int
}
