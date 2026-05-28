import SwiftUI

@main
struct VitalScoreApp: App {
    @StateObject private var storage = LocalStorageManager()
    @StateObject private var healthKit: HealthKitManager
    @StateObject private var experiments: ExperimentManager
    @StateObject private var tagCatalog: TagCatalog

    init() {
        let storage = LocalStorageManager()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-state-on-launch") {
            storage.resetAll()
            print("[DEBUG] App state reset on launch.")
        }
        #endif

        storage.hasCompletedOnboarding = true
        storage.hasGrantedHealthPermission = true

        let cleanup = storage.removeLocallySavedLiveVoiceData()
        #if DEBUG
        if cleanup.voiceSessionsScrubbed > 0 ||
            cleanup.analysisExportFilesDeleted > 0 ||
            cleanup.aiAnalysisFilesDeleted > 0 ||
            cleanup.rawAudioDebugDirectoriesDeleted > 0 {
            print("[DEBUG] Removed locally saved live voice data: \(cleanup.voiceSessionsScrubbed) sessions, \(cleanup.analysisExportFilesDeleted) exports, \(cleanup.aiAnalysisFilesDeleted) analyses, \(cleanup.rawAudioDebugDirectoriesDeleted) raw-audio folders.")
        }
        #endif

        _storage = StateObject(wrappedValue: storage)
        _healthKit = StateObject(wrappedValue: HealthKitManager())
        _experiments = StateObject(wrappedValue: ExperimentManager(storage: storage))
        _tagCatalog = StateObject(wrappedValue: TagCatalog(storage: storage))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(storage)
                .environmentObject(healthKit)
                .environmentObject(experiments)
                .environmentObject(tagCatalog)
        }
    }
}
