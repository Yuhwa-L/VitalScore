import XCTest
@testable import VitalScore

final class WellnessScoreEngineTests: XCTestCase {
    private let engine = WellnessScoreEngine()
    private let bannedPhrases = ["diagnose", "cure", "treat", "prevent", "proves", "caused"]

    func test_allMetricsMatchingBaseline_scoreNearZero_confidenceHigh() {
        let baseline = baseline(
            sleep: 7.5, rhr: 60, hrv: 50, steps: 8000, focus: 80
        )
        let today = record(sleep: 7.5, rhr: 60, hrv: 50, steps: 8000, focus: 80)
        let result = engine.calculate(today: today, baseline: baseline)
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.confidence, "High")
        XCTAssertEqual(result.availableMetricCount, 5)
    }

    func test_sleepIncrease_pushesScorePositive() {
        let baseline = baseline(sleep: 7.0, rhr: 60, hrv: 50, steps: 8000, focus: 80)
        let today = record(sleep: 8.4, rhr: 60, hrv: 50, steps: 8000, focus: 80)
        let result = engine.calculate(today: today, baseline: baseline)
        XCTAssertGreaterThan(result.score, 0)
    }

    func test_lowerRestingHeartRate_pushesScorePositive() {
        let baseline = baseline(sleep: 7.5, rhr: 65, hrv: 50, steps: 8000, focus: 80)
        let today = record(sleep: 7.5, rhr: 58, hrv: 50, steps: 8000, focus: 80)
        let result = engine.calculate(today: today, baseline: baseline)
        XCTAssertGreaterThan(result.score, 0)
    }

    func test_onlyOneMetricAvailable_confidenceLow_scoreStillComputed() {
        let baseline = BaselineMetrics(
            startDate: Date(), endDate: Date(),
            averageSleepHours: nil,
            averageRestingHeartRateBPM: nil,
            averageHRVMs: nil,
            averageStepCount: nil,
            averageEyeFocusScore: 70,
            averageBalanceScore: nil
        )
        let today = record(sleep: nil, rhr: nil, hrv: nil, steps: nil, focus: 85)
        let result = engine.calculate(today: today, baseline: baseline)
        XCTAssertEqual(result.availableMetricCount, 1)
        XCTAssertEqual(result.confidence, "Low")
    }

    func test_zeroBaselineValues_doNotCrash() {
        let baseline = baseline(sleep: 0, rhr: 0, hrv: 0, steps: 0, focus: 0)
        let today = record(sleep: 7.5, rhr: 60, hrv: 50, steps: 8000, focus: 80)
        let result = engine.calculate(today: today, baseline: baseline)
        XCTAssertEqual(result.availableMetricCount, 0)
        XCTAssertEqual(result.score, 0)
    }

    func test_noMetricsAvailable_returnsZeroScoreLowConfidence() {
        let baseline = BaselineMetrics.empty
        let today = record(sleep: nil, rhr: nil, hrv: nil, steps: nil, focus: nil)
        let result = engine.calculate(today: today, baseline: baseline)
        XCTAssertEqual(result.score, 0)
        XCTAssertEqual(result.confidence, "Low")
    }

    func test_insightText_doesNotContainBannedMedicalClaims() {
        let baseline = baseline(sleep: 7.0, rhr: 65, hrv: 50, steps: 8000, focus: 75)
        let today = record(sleep: 8.0, rhr: 60, hrv: 55, steps: 9000, focus: 82)
        let result = engine.calculate(today: today, baseline: baseline)
        let lower = result.insightText.lowercased()
        for phrase in bannedPhrases {
            XCTAssertFalse(lower.contains(phrase), "Insight text contains banned phrase: \(phrase)")
        }
    }

    func test_scoreClampedToRange() {
        let baseline = baseline(sleep: 1.0, rhr: 200, hrv: 1.0, steps: 10, focus: 1.0)
        let today = record(sleep: 20.0, rhr: 30, hrv: 200.0, steps: 50000, focus: 100.0)
        let result = engine.calculate(today: today, baseline: baseline)
        XCTAssertLessThanOrEqual(result.score, 20)
        XCTAssertGreaterThanOrEqual(result.score, -20)
    }

    private func baseline(sleep: Double?, rhr: Double?, hrv: Double?, steps: Double?, focus: Double?) -> BaselineMetrics {
        BaselineMetrics(
            startDate: Date(), endDate: Date(),
            averageSleepHours: sleep,
            averageRestingHeartRateBPM: rhr,
            averageHRVMs: hrv,
            averageStepCount: steps,
            averageEyeFocusScore: focus,
            averageBalanceScore: nil
        )
    }

    private func record(sleep: Double?, rhr: Double?, hrv: Double?, steps: Double?, focus: Double?) -> DailyHealthRecord {
        DailyHealthRecord(
            date: Date(),
            experimentTag: "No Alcohol",
            sleepHours: sleep,
            restingHeartRateBPM: rhr,
            hrvMs: hrv,
            stepCount: steps,
            activeEnergyKcal: nil,
            eyeFocusScore: focus,
            wellnessDeltaScore: 0,
            confidenceLevel: "Low",
            insightText: ""
        )
    }
}
