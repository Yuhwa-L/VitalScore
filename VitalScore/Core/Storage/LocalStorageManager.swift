import Foundation

final class LocalStorageManager: ObservableObject {
    static let recordsKey = "com.vitalscore.records.v1"
    static let experimentKey = "com.vitalscore.experiment.v1"
    static let onboardingKey = "com.vitalscore.onboardingComplete.v1"
    static let healthPermissionKey = "com.vitalscore.healthPermissionGranted.v1"
    static let voiceSessionsKey = "com.vitalscore.voiceSessions.v1"
    static let eyeFocusSummariesKey = "com.vitalscore.eyeFocusSummaries.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func saveRecord(_ record: DailyHealthRecord) {
        var existing = loadAllRecords()
        existing.removeAll { Calendar.current.isDate($0.date, inSameDayAs: record.date) }
        existing.append(record)
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: Self.recordsKey)
        }
    }

    func loadAllRecords() -> [DailyHealthRecord] {
        guard let data = defaults.data(forKey: Self.recordsKey) else { return [] }
        return (try? JSONDecoder().decode([DailyHealthRecord].self, from: data)) ?? []
    }

    func recordsInWindow(days: Int, asOf reference: Date = Date()) -> [DailyHealthRecord] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: reference) else {
            return []
        }
        return loadAllRecords().filter { $0.date >= cutoff && $0.date < reference }
    }

    func saveVoiceSession(_ session: VoiceTrackingSession) {
        var existing = loadVoiceSessions()
        existing.removeAll { $0.id == session.id }
        existing.append(session)
        existing.sort { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: Self.voiceSessionsKey)
        }
    }

    func loadVoiceSessions() -> [VoiceTrackingSession] {
        guard let data = defaults.data(forKey: Self.voiceSessionsKey) else { return [] }
        return (try? JSONDecoder().decode([VoiceTrackingSession].self, from: data)) ?? []
    }

    func voiceSessionsInWindow(days: Int, asOf reference: Date = Date()) -> [VoiceTrackingSession] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: reference) else {
            return []
        }
        return loadVoiceSessions().filter { $0.date >= cutoff && $0.date < reference }
    }

    func saveEyeFocusSummary(_ summary: EyeFocusAISummary) {
        var existing = loadEyeFocusSummaries()
        existing.removeAll { $0.id == summary.id || $0.sourceLogFileName == summary.sourceLogFileName }
        existing.append(summary)
        existing.sort { $0.generatedAt < $1.generatedAt }
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: Self.eyeFocusSummariesKey)
        }
    }

    func loadEyeFocusSummaries() -> [EyeFocusAISummary] {
        guard let data = defaults.data(forKey: Self.eyeFocusSummariesKey) else { return [] }
        return (try? JSONDecoder().decode([EyeFocusAISummary].self, from: data)) ?? []
    }

    func latestEyeFocusSummary() -> EyeFocusAISummary? {
        loadEyeFocusSummaries().sorted { $0.generatedAt < $1.generatedAt }.last
    }

    func removeEyeFocusSummaries(forFileNames names: Set<String>) {
        guard !names.isEmpty else { return }
        let remaining = loadEyeFocusSummaries().filter { summary in
            guard let name = summary.sourceLogFileName else { return true }
            return !names.contains(name)
        }
        if let data = try? JSONEncoder().encode(remaining) {
            defaults.set(data, forKey: Self.eyeFocusSummariesKey)
        }
    }

    func saveSelectedExperiment(_ tag: ExperimentTag?, customLabel: String? = nil) {
        let payload = ExperimentSelectionPayload(tag: tag, customLabel: customLabel)
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.experimentKey)
        }
    }

    func loadSelectedExperiment() -> (ExperimentTag?, String?) {
        guard let data = defaults.data(forKey: Self.experimentKey),
              let payload = try? JSONDecoder().decode(ExperimentSelectionPayload.self, from: data)
        else {
            return (nil, nil)
        }
        return (payload.tag, payload.customLabel)
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Self.onboardingKey) }
        set { defaults.set(newValue, forKey: Self.onboardingKey) }
    }

    var hasGrantedHealthPermission: Bool {
        get { defaults.bool(forKey: Self.healthPermissionKey) }
        set { defaults.set(newValue, forKey: Self.healthPermissionKey) }
    }

    func resetAll() {
        defaults.removeObject(forKey: Self.recordsKey)
        defaults.removeObject(forKey: Self.experimentKey)
        defaults.removeObject(forKey: Self.onboardingKey)
        defaults.removeObject(forKey: Self.healthPermissionKey)
        defaults.removeObject(forKey: Self.voiceSessionsKey)
        defaults.removeObject(forKey: Self.eyeFocusSummariesKey)
    }

    private struct ExperimentSelectionPayload: Codable {
        let tag: ExperimentTag?
        let customLabel: String?
    }
}
