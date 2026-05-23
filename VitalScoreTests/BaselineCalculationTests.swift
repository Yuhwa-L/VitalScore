import XCTest
@testable import VitalScore

final class BaselineCalculationTests: XCTestCase {
    private let engine = WellnessScoreEngine()

    func test_sevenRecords_returnsArithmeticMean() {
        let reference = Date()
        let records = (1...7).map { offset in
            makeRecord(daysAgo: offset, sleep: Double(offset), reference: reference)
        }
        let baseline = engine.buildBaseline(from: records, asOf: reference, window: 7)
        let expected = (1.0 + 2.0 + 3.0 + 4.0 + 5.0 + 6.0 + 7.0) / 7.0
        XCTAssertEqual(baseline.averageSleepHours ?? 0, expected, accuracy: 0.001)
    }

    func test_recordsOlderThanWindow_excluded() {
        let reference = Date()
        let inWindow = (1...3).map { makeRecord(daysAgo: $0, sleep: 8.0, reference: reference) }
        let outOfWindow = (8...10).map { makeRecord(daysAgo: $0, sleep: 1.0, reference: reference) }
        let baseline = engine.buildBaseline(from: inWindow + outOfWindow, asOf: reference, window: 7)
        XCTAssertEqual(baseline.averageSleepHours ?? 0, 8.0, accuracy: 0.001)
    }

    func test_nilMetric_doesNotSkewAverage() {
        let reference = Date()
        let records: [DailyHealthRecord] = [
            makeRecord(daysAgo: 1, sleep: nil, reference: reference, hrv: 50),
            makeRecord(daysAgo: 2, sleep: 7.0, reference: reference, hrv: nil),
            makeRecord(daysAgo: 3, sleep: 8.0, reference: reference, hrv: nil)
        ]
        let baseline = engine.buildBaseline(from: records, asOf: reference, window: 7)
        XCTAssertEqual(baseline.averageSleepHours ?? 0, 7.5, accuracy: 0.001)
        XCTAssertEqual(baseline.averageHRVMs ?? 0, 50.0, accuracy: 0.001)
    }

    func test_emptyRecords_returnsNilAverages() {
        let baseline = engine.buildBaseline(from: [], asOf: Date(), window: 7)
        XCTAssertNil(baseline.averageSleepHours)
        XCTAssertNil(baseline.averageRestingHeartRateBPM)
        XCTAssertNil(baseline.averageHRVMs)
        XCTAssertNil(baseline.averageStepCount)
        XCTAssertNil(baseline.averageEyeFocusScore)
    }

    private func makeRecord(daysAgo: Int, sleep: Double?, reference: Date, hrv: Double? = nil) -> DailyHealthRecord {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: reference)!
        return DailyHealthRecord(
            date: date,
            experimentTag: "Test",
            sleepHours: sleep,
            restingHeartRateBPM: nil,
            hrvMs: hrv,
            stepCount: nil,
            activeEnergyKcal: nil,
            eyeFocusScore: nil,
            wellnessDeltaScore: 0,
            confidenceLevel: "Low",
            insightText: ""
        )
    }
}
