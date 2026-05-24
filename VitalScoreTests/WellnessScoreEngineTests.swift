import XCTest
@testable import VitalScore

final class WellnessScoreEngineTests: XCTestCase {
    private let engine = WellnessScoreEngine()
    private let suggestionEngine = WellnessSuggestionEngine()
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
        let today = record(sleep: 7.5, rhr: 50, hrv: 50, steps: 8000, focus: 80)
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

    func test_zeroPercentBaselineValues_skipPercentMetricsButKeepPointMetrics() {
        let baseline = baseline(sleep: 0, rhr: 0, hrv: 0, steps: 0, focus: 0)
        let today = record(sleep: 7.5, rhr: 60, hrv: 50, steps: 8000, focus: 80)
        let result = engine.calculate(today: today, baseline: baseline)
        XCTAssertEqual(result.availableMetricCount, 1)
        XCTAssertEqual(result.score, 20)
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

    func test_localWellnessSuggestions_useHistoryAndAvoidMedicalClaims() {
        let records = suggestionRecords()

        let report = suggestionEngine.localReport(records: records, voiceSessions: [], tagFilter: "Morning")
        let categories = Set(report.suggestions.map(\.category))

        XCTAssertTrue(categories.contains(.sleep))
        XCTAssertTrue(categories.contains(.nutrition))
        XCTAssertFalse(report.suggestions.isEmpty)
        XCTAssertTrue(report.suggestions.allSatisfy(\.notMedicalAdvice))

        let suggestionText = report.suggestions
            .flatMap { [$0.title, $0.reason, $0.suggestion, $0.trackingPlan] + $0.evidence }
            .joined(separator: " ")
            .lowercased()
        for phrase in bannedPhrases {
            XCTAssertFalse(suggestionText.contains(phrase), "Suggestion text contains banned phrase: \(phrase)")
        }
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

    private func suggestionRecords() -> [DailyHealthRecord] {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return (0..<8).map { offset in
            let lowerDay = offset >= 5
            return DailyHealthRecord(
                date: start.addingTimeInterval(TimeInterval(offset * 86_400)),
                experimentTag: "Morning",
                sleepHours: lowerDay ? 5.9 : 7.7,
                restingHeartRateBPM: lowerDay ? 70 : 61,
                hrvMs: lowerDay ? 29 : 45,
                stepCount: lowerDay ? 3_800 : 8_500,
                eyeFocusScore: lowerDay ? 60 : 79,
                voiceScore: lowerDay ? 57 : 74,
                wellnessDeltaScore: lowerDay ? -9 : 6,
                confidenceLevel: "Medium",
                insightText: "Scored record"
            )
        }
    }
}
