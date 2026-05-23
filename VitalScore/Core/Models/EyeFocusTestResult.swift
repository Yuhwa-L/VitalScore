import Foundation

struct EyeFocusTestResult: Codable, Equatable {
    let averageReactionMs: Double
    let reactionStdDevMs: Double
    let missedTargets: Int
    let falseTaps: Int
    let eyeFocusScore: Double
    let completedAt: Date
}
