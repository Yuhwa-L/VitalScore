import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    nonisolated static func isAsleepValue(_ rawValue: Int) -> Bool {
        if #available(iOS 16.0, *) {
            return rawValue == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                || rawValue == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                || rawValue == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                || rawValue == HKCategoryValueSleepAnalysis.asleepREM.rawValue
        } else {
            return rawValue == HKCategoryValueSleepAnalysis.asleep.rawValue
        }
    }

    nonisolated static func totalAsleepSeconds(from samples: [HKCategorySample]) -> Double {
        samples.reduce(0.0) { acc, sample in
            guard isAsleepValue(sample.value) else { return acc }
            return acc + sample.endDate.timeIntervalSince(sample.startDate)
        }
    }

    @Published var isAuthorized = false
    @Published var hasRequestedAuthorization = false
    @Published var isFetching = false
    @Published var lastFetchedAt: Date?

    @Published var latestRestingHeartRate: Double?
    @Published var latestHRV: Double?
    @Published var todaySteps: Double?
    @Published var todayActiveEnergy: Double?
    @Published var lastNightSleepHours: Double?

    private let permissionKey = "com.vitalscore.healthPermissionGranted.v1"

    init() {
        hasRequestedAuthorization = UserDefaults.standard.bool(forKey: permissionKey)
        isAuthorized = hasRequestedAuthorization
        loadFromBundleSync()
    }

    func requestAuthorization() {
        hasRequestedAuthorization = true
        isAuthorized = true
        UserDefaults.standard.set(true, forKey: permissionKey)
        loadFromBundleSync()
    }

    func resetPermission() {
        hasRequestedAuthorization = false
        isAuthorized = false
        UserDefaults.standard.set(false, forKey: permissionKey)
    }

    func fetchAllLatest() async {
        isFetching = true
        try? await Task.sleep(nanoseconds: 250_000_000)
        loadFromBundleSync()
        lastFetchedAt = Date()
        isFetching = false
    }

    func generateRandom() {
        latestRestingHeartRate = Double.random(in: 55...75).rounded()
        latestHRV = Double.random(in: 40...80).rounded()
        todaySteps = Double.random(in: 3000...14000).rounded()
        todayActiveEnergy = Double.random(in: 150...700).rounded()
        lastNightSleepHours = (Double.random(in: 5.5...8.5) * 10).rounded() / 10
        lastFetchedAt = Date()
    }

    func applyMockRecord(_ record: DailyHealthRecord) {
        latestRestingHeartRate = record.restingHeartRateBPM
        latestHRV = record.hrvMs
        todaySteps = record.stepCount
        todayActiveEnergy = record.activeEnergyKcal
        lastNightSleepHours = record.sleepHours
        lastFetchedAt = Date()
    }

    private func loadFromBundleSync() {
        latestRestingHeartRate = 62
        latestHRV = 58
        todaySteps = 7500
        todayActiveEnergy = 350
        lastNightSleepHours = 7.2
    }
}
