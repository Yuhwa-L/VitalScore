import XCTest
@testable import VitalScore

final class EyeFocusScoringTests: XCTestCase {
    func test_perfectPerformance_scores100() {
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 300,
            reactionStdDevMs: 0,
            hitCount: 15,
            missedTargets: 0,
            falseTaps: 0
        )
        XCTAssertEqual(score, 100, accuracy: 0.001)
    }

    func test_slowReaction_appliesSpeedFactor() {
        // 700ms avg → overage 300 → speedFactor 0.8 → 100 * 0.8 = 80
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 700,
            reactionStdDevMs: 0,
            hitCount: 10,
            missedTargets: 0,
            falseTaps: 0
        )
        XCTAssertEqual(score, 80, accuracy: 0.001)
    }

    func test_zeroHits_scoresZero() {
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 0,
            reactionStdDevMs: 0,
            hitCount: 0,
            missedTargets: 15,
            falseTaps: 0
        )
        XCTAssertEqual(score, 0, accuracy: 0.001)
    }

    func test_partialHitRate_scoresProportionally() {
        // 6 hits / 15 total = 40% base, fast reactions, low variability
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 350,
            reactionStdDevMs: 80,
            hitCount: 6,
            missedTargets: 9,
            falseTaps: 0
        )
        XCTAssertEqual(score, 40 * 1.0 * (1.0 - 80.0 / 1500.0), accuracy: 0.001)
    }

    func test_scoreNeverExceedsBounds() {
        let high = EyeFocusTestManager.calculateScore(averageReactionMs: 100, reactionStdDevMs: 0, hitCount: 15, missedTargets: 0, falseTaps: 0)
        XCTAssertLessThanOrEqual(high, 100)
        let low = EyeFocusTestManager.calculateScore(averageReactionMs: 5000, reactionStdDevMs: 9999, hitCount: 0, missedTargets: 999, falseTaps: 999)
        XCTAssertGreaterThanOrEqual(low, 0)
    }

    func test_variabilityPenalty() {
        // stddev 150 → consistencyFactor 0.9 → score 100 * 1.0 * 0.9 = 90
        let score = EyeFocusTestManager.calculateScore(
            averageReactionMs: 300,
            reactionStdDevMs: 150,
            hitCount: 10,
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

    func test_calibrationUsesTargetLevelRobustMeans() throws {
        var samples: [CalibrationSample] = []

        for target in GazeCalibrator.targets {
            for i in 0..<8 {
                let jitter = CGFloat(i - 4) * 0.001
                let raw = CGPoint(
                    x: target.x * 0.86 + 0.06 + jitter,
                    y: target.y * 0.90 + 0.03 - jitter
                )
                let input = CalibrationInput(rawGaze: raw, headPose: .zero, motion: .zero)
                samples.append(CalibrationSample(targetPoint: target, input: input))
            }
            samples.append(
                CalibrationSample(
                    targetPoint: target,
                    input: CalibrationInput(rawGaze: CGPoint(x: 1.4, y: -0.5))
                )
            )
        }

        let transform = try XCTUnwrap(CalibrationTransform.solve(samples: samples))
        XCTAssertNotEqual(transform.kind, .poseAware)

        let target = CGPoint(x: 0.58, y: 0.43)
        let shiftedInput = CalibrationInput(
            rawGaze: CGPoint(
                x: target.x * 0.86 + 0.06,
                y: target.y * 0.90 + 0.03
            )
        )

        let mapped = transform.apply(shiftedInput)
        XCTAssertEqual(mapped.x, target.x, accuracy: 0.03)
        XCTAssertEqual(mapped.y, target.y, accuracy: 0.03)
    }

    func test_calibrationDoesNotUsePoseAwareWithoutPoseVariation() throws {
        var samples: [CalibrationSample] = []
        for target in GazeCalibrator.targets {
            for _ in 0..<4 {
                let raw = CGPoint(x: target.x * 0.88 + 0.05, y: target.y * 0.91 + 0.04)
                let input = CalibrationInput(rawGaze: raw, headPose: .zero, motion: .zero)
                samples.append(CalibrationSample(targetPoint: target, input: input))
            }
        }

        let transform = try XCTUnwrap(CalibrationTransform.solve(samples: samples))
        XCTAssertNotEqual(transform.kind, .poseAware)
    }

    func test_calibrationRobustSamplesDropFixationOutlier() {
        let target = CGPoint(x: 0.5, y: 0.5)
        var samples = (0..<10).map { i in
            CalibrationSample(
                targetPoint: target,
                input: CalibrationInput(rawGaze: CGPoint(x: 0.5 + CGFloat(i) * 0.001, y: 0.5))
            )
        }
        samples.append(
            CalibrationSample(
                targetPoint: target,
                input: CalibrationInput(rawGaze: CGPoint(x: 1.8, y: -0.6))
            )
        )

        let filtered = GazeCalibrator.robustSamples(samples)
        XCTAssertLessThan(filtered.count, samples.count)
        XCTAssertFalse(filtered.contains { $0.input.rawX > 1 || $0.input.rawY < 0 })
    }

    func test_gazeAggregatorTrimsLargeErrorOutlier() throws {
        var samples: [GazeSample] = []
        for i in 0..<19 {
            samples.append(Self.gazeSample(timestamp: Double(i) * 0.1, gazeX: 110, gazeY: 100))
        }
        samples.append(Self.gazeSample(timestamp: 2.0, gazeX: 2100, gazeY: 100))

        let metrics = try XCTUnwrap(GazeAggregator.aggregate(samples: samples, durationSeconds: 3))
        XCTAssertLessThan(metrics.gazeAccuracyPx, 20)
        XCTAssertEqual(metrics.sampleCount, 20)
    }

    private static func gazeSample(timestamp: TimeInterval, gazeX: CGFloat, gazeY: CGFloat) -> GazeSample {
        GazeSample(
            timestamp: timestamp,
            rawGazePoint: CGPoint(x: gazeX, y: gazeY),
            gazePoint: CGPoint(x: gazeX, y: gazeY),
            targetPoint: CGPoint(x: 100, y: 100),
            leftBlink: 0,
            rightBlink: 0,
            trackingValid: true,
            inSettlingWindow: false,
            inMotionCooldown: false,
            motion: .zero,
            headPose: .zero,
            headPositionDevM: 0,
            headAngularDevDeg: 0
        )
    }
}
