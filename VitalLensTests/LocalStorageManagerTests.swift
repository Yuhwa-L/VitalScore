import XCTest
@testable import VitalLens

final class LocalStorageManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var storage: LocalStorageManager!
    private let suite = "com.vitallens.tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        storage = LocalStorageManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func test_saveAndLoad_roundtripPreservesAllFields() {
        let record = DailyHealthRecord(
            date: Date(),
            experimentTag: "No Alcohol",
            sleepHours: 7.5,
            restingHeartRateBPM: 61,
            hrvMs: 48,
            stepCount: 8200,
            activeEnergyKcal: 350,
            eyeFocusScore: 84,
            averageReactionMs: 380,
            reactionStdDevMs: 60,
            missedTargets: 1,
            falseTaps: 0,
            wellnessDeltaScore: 7,
            confidenceLevel: "Medium",
            insightText: "Sleep increased by 30 minutes."
        )
        storage.saveRecord(record)
        let loaded = storage.loadAllRecords()
        XCTAssertEqual(loaded.count, 1)
        let first = loaded.first!
        XCTAssertEqual(first.experimentTag, "No Alcohol")
        XCTAssertEqual(first.sleepHours, 7.5)
        XCTAssertEqual(first.wellnessDeltaScore, 7)
        XCTAssertEqual(first.confidenceLevel, "Medium")
        XCTAssertEqual(first.insightText, "Sleep increased by 30 minutes.")
    }

    func test_savingSameDayTwice_overwrites() {
        let date = Date()
        let r1 = DailyHealthRecord(date: date, experimentTag: "A", wellnessDeltaScore: 1, confidenceLevel: "Low", insightText: "")
        let r2 = DailyHealthRecord(date: date, experimentTag: "B", wellnessDeltaScore: 2, confidenceLevel: "Low", insightText: "")
        storage.saveRecord(r1)
        storage.saveRecord(r2)
        let loaded = storage.loadAllRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.experimentTag, "B")
    }

    func test_customExperimentLabel_persistsAlongsideEnum() {
        storage.saveSelectedExperiment(.custom, customLabel: "Cold showers")
        let (tag, label) = storage.loadSelectedExperiment()
        XCTAssertEqual(tag, .custom)
        XCTAssertEqual(label, "Cold showers")
    }

    func test_loadFromEmptyDefaults_returnsEmptyArray() {
        XCTAssertEqual(storage.loadAllRecords().count, 0)
    }

    func test_recordsInWindow_filtersByDate() {
        let now = Date()
        let inside = DailyHealthRecord(date: now.addingTimeInterval(-3600 * 24 * 2), experimentTag: "x", wellnessDeltaScore: 0, confidenceLevel: "Low", insightText: "")
        let outside = DailyHealthRecord(date: now.addingTimeInterval(-3600 * 24 * 20), experimentTag: "x", wellnessDeltaScore: 0, confidenceLevel: "Low", insightText: "")
        storage.saveRecord(inside)
        storage.saveRecord(outside)
        let windowed = storage.recordsInWindow(days: 7, asOf: now)
        XCTAssertEqual(windowed.count, 1)
    }
}
