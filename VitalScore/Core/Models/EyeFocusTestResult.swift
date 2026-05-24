import Foundation

struct EyeFocusTestResult: Codable, Equatable {
    let averageReactionMs: Double
    let reactionStdDevMs: Double
    let missedTargets: Int
    let falseTaps: Int
    let reactionScore: Double
    let gazeMetrics: GazeMetrics?
    let eyeFocusScore: Double
    let completedAt: Date

    static let gazeBlendWeight = 0.6
    static let reactionBlendWeight = 0.4

    static func blend(reactionScore: Double, gazeScore: Double?) -> Double {
        guard let gazeScore else { return reactionScore }
        return reactionScore * reactionBlendWeight + gazeScore * gazeBlendWeight
    }
}
