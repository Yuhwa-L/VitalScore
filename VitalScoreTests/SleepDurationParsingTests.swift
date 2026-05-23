import XCTest
import HealthKit
@testable import VitalScore

final class SleepDurationParsingTests: XCTestCase {
    func test_singleAsleepSample_totalsCorrectDuration() throws {
        let start = Date()
        let end = start.addingTimeInterval(8 * 3600)
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return XCTFail("Sleep type unavailable")
        }
        let value: Int = {
            if #available(iOS 16.0, *) {
                return HKCategoryValueSleepAnalysis.asleepCore.rawValue
            } else {
                return HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        }()
        let sample = HKCategorySample(type: sleepType, value: value, start: start, end: end)
        let seconds = HealthKitManager.totalAsleepSeconds(from: [sample])
        XCTAssertEqual(seconds, 8 * 3600, accuracy: 0.001)
    }

    func test_twoNonOverlappingAsleepSamples_sum() throws {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return XCTFail("Sleep type unavailable")
        }
        let value: Int = {
            if #available(iOS 16.0, *) {
                return HKCategoryValueSleepAnalysis.asleepCore.rawValue
            } else {
                return HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        }()
        let now = Date()
        let s1 = HKCategorySample(type: sleepType, value: value, start: now, end: now.addingTimeInterval(3600))
        let s2 = HKCategorySample(type: sleepType, value: value, start: now.addingTimeInterval(7200), end: now.addingTimeInterval(7200 + 3600))
        let seconds = HealthKitManager.totalAsleepSeconds(from: [s1, s2])
        XCTAssertEqual(seconds, 2 * 3600, accuracy: 0.001)
    }

    func test_inBedSample_excludedFromTotal() throws {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return XCTFail("Sleep type unavailable")
        }
        let start = Date()
        let inBed = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
            start: start,
            end: start.addingTimeInterval(3600)
        )
        XCTAssertFalse(HealthKitManager.isAsleepValue(HKCategoryValueSleepAnalysis.inBed.rawValue))
        let seconds = HealthKitManager.totalAsleepSeconds(from: [inBed])
        XCTAssertEqual(seconds, 0, accuracy: 0.001)
    }

    func test_allIOS16SleepStages_countAsAsleep() {
        guard #available(iOS 16.0, *) else { return }
        XCTAssertTrue(HealthKitManager.isAsleepValue(HKCategoryValueSleepAnalysis.asleepCore.rawValue))
        XCTAssertTrue(HealthKitManager.isAsleepValue(HKCategoryValueSleepAnalysis.asleepDeep.rawValue))
        XCTAssertTrue(HealthKitManager.isAsleepValue(HKCategoryValueSleepAnalysis.asleepREM.rawValue))
        XCTAssertTrue(HealthKitManager.isAsleepValue(HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue))
    }
}
