import SwiftUI

@main
struct VitalScoreApp: App {
    @StateObject private var storage = LocalStorageManager()
    @StateObject private var healthKit: HealthKitManager
    @StateObject private var experiments: ExperimentManager

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
        if storage.shouldAutoloadTagDemoData {
            do {
                let result = try storage.loadTagDemoFixtures()
                storage.saveSelectedExperiment(.gym)
                print("[DEBUG] Loaded tag demo fixtures: \(result.recordsImported) records, \(result.voiceSessionsImported) voice sessions, \(result.gazeLogsImported) gaze logs, \(result.eyeFocusSummariesImported) eye summaries, tags: \(result.tagsImported.joined(separator: ", ")).")
            } catch {
                print("[DEBUG] Failed to load tag demo fixtures: \(error.localizedDescription)")
            }
        }
        #endif

        let jsonCleanup = storage.removeTodaysJSONData()
        #if DEBUG
        print("[DEBUG] Removed today's startup data: \(jsonCleanup.dailyRecordsRemoved) records, \(jsonCleanup.voiceSessionsRemoved) voice sessions, \(jsonCleanup.eyeFocusSummariesRemoved) eye summaries, \(jsonCleanup.analysisJSONFilesDeleted) analysis files, \(jsonCleanup.gazeLogFilesDeleted) gaze logs, \(jsonCleanup.debugJSONFilesDeleted) debug JSON files, \(jsonCleanup.analysisIndexEntriesRemoved) analysis index rows, \(jsonCleanup.aiAnalysisIndexEntriesRemoved) AI index rows.")
        #endif

        _storage = StateObject(wrappedValue: storage)
        _healthKit = StateObject(wrappedValue: HealthKitManager())
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
