import XCTest
@testable import VitalLens

final class EyeFocusScoringTests: XCTestCase {
    func test_perfectPerformance_scores100() {
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 300,
            reactionStdDevMs: 0,
            missedTargets: 0,
            falseTaps: 0
        )
        XCTAssertEqual(score, 100, accuracy: 0.001)
    }

    func test_slowReaction_appliesReactionPenalty() {
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 700,
            reactionStdDevMs: 0,
            missedTargets: 0,
            falseTaps: 0
        )
        XCTAssertEqual(score, 50, accuracy: 0.001)
    }

    func test_manyMisses_clampsToZero() {
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 300,
            reactionStdDevMs: 0,
            missedTargets: 20,
            falseTaps: 0
        )
        XCTAssertEqual(score, 0, accuracy: 0.001)
    }

    func test_scoreNeverExceedsBounds() {
        let high = EyeFocusTestManager.calculateScore(averageReactionMs: 100, reactionStdDevMs: 0, missedTargets: 0, falseTaps: 0)
        XCTAssertLessThanOrEqual(high, 100)
        let low = EyeFocusTestManager.calculateScore(averageReactionMs: 5000, reactionStdDevMs: 9999, missedTargets: 999, falseTaps: 999)
        XCTAssertGreaterThanOrEqual(low, 0)
    }

    func test_variabilityPenalty() {
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 300,
            reactionStdDevMs: 150,
            missedTargets: 0,
            falseTaps: 0
        )
        XCTAssertEqual(score, 90, accuracy: 0.001)
    }

    func test_standardDeviation_singleValue_returnsZero() {
        XCTAssertEqual(EyeFocusTestManager.standardDeviation([500]), 0)
    }

    func test_standardDeviation_uniformValues_returnsZero() {
        XCTAssertEqual(EyeFocusTestManager.standardDeviation([500, 500, 500]), 0)
    }

    func test_standardDeviation_knownSpread() {
        let std = EyeFocusTestManager.standardDeviation([200, 400, 600])
        XCTAssertEqual(std, sqrt((40000.0 + 0 + 40000.0) / 3.0), accuracy: 0.001)
    }
}
