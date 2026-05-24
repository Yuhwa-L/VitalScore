import SwiftUI

@main
struct VitalScoreApp: App {
    @StateObject private var storage = LocalStorageManager()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var experiments: ExperimentManager

    init() {
        let storage = LocalStorageManager()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-state-on-launch") {
            storage.resetAll()
            UserDefaults.standard.set(false, forKey: "com.vitalscore.healthPermissionGranted.v1")
            print("[DEBUG] App state reset on launch.")
        }
        #endif
        _storage = StateObject(wrappedValue: storage)
        _experiments = StateObject(wrappedValue: ExperimentManager(storage: storage))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storage)
                .environmentObject(healthKit)
                .environmentObject(experiments)
        }
    }
}
