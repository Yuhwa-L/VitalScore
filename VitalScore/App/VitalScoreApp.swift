import SwiftUI

@main
struct VitalScoreApp: App {
    @StateObject private var storage = LocalStorageManager()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var experiments: ExperimentManager

    init() {
        let storage = LocalStorageManager()
        let cleanup = storage.removeLocallySavedLiveVoiceData()
        #if DEBUG
        if cleanup.voiceSessionsScrubbed > 0 ||
            cleanup.analysisExportFilesDeleted > 0 ||
            cleanup.aiAnalysisFilesDeleted > 0 ||
            cleanup.rawAudioDebugDirectoriesDeleted > 0 {
            print("[DEBUG] Removed locally saved live voice data: \(cleanup.voiceSessionsScrubbed) sessions, \(cleanup.analysisExportFilesDeleted) exports, \(cleanup.aiAnalysisFilesDeleted) analyses, \(cleanup.rawAudioDebugDirectoriesDeleted) raw-audio folders.")
        }
        if ProcessInfo.processInfo.arguments.contains("--reset-state-on-launch") {
            storage.resetAll()
            UserDefaults.standard.set(false, forKey: "com.vitalscore.healthPermissionGranted.v1")
            print("[DEBUG] App state reset on launch.")
        }
        if ProcessInfo.processInfo.arguments.contains("--delete-todays-json-data") ||
            ProcessInfo.processInfo.environment["VITALSCORE_DELETE_TODAYS_JSON_DATA"] == "1" {
            let jsonCleanup = storage.removeTodaysJSONData()
            print("[DEBUG] Removed today's JSON data: \(jsonCleanup.dailyRecordsRemoved) records, \(jsonCleanup.voiceSessionsRemoved) voice sessions, \(jsonCleanup.eyeFocusSummariesRemoved) eye summaries, \(jsonCleanup.analysisJSONFilesDeleted) analysis files, \(jsonCleanup.gazeLogFilesDeleted) gaze logs, \(jsonCleanup.debugJSONFilesDeleted) debug JSON files, \(jsonCleanup.analysisIndexEntriesRemoved) analysis index rows, \(jsonCleanup.aiAnalysisIndexEntriesRemoved) AI index rows.")
        }
        if storage.shouldAutoloadWellnessDemo {
            do {
                let result = try storage.loadWellnessDemoFixture()
                storage.saveSelectedExperiment(.morningSunlight)
                print("[DEBUG] Loaded wellness demo fixture: \(result.recordsImported) records, \(result.voiceSessionsImported) voice sessions.")
            } catch {
                print("[DEBUG] Failed to load wellness demo fixture: \(error.localizedDescription)")
            }
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
