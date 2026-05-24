import Foundation

final class LocalStorageManager: ObservableObject {
    static let recordsKey = "com.vitalscore.records.v1"
    static let experimentKey = "com.vitalscore.experiment.v1"
    static let onboardingKey = "com.vitalscore.onboardingComplete.v1"
    static let healthPermissionKey = "com.vitalscore.healthPermissionGranted.v1"
    static let voiceSessionsKey = "com.vitalscore.voiceSessions.v1"
    static let analysisIndexFileName = "analysis_exports.jsonl"
    static let aiAnalysisIndexFileName = "ai_analysis_results.jsonl"
    static let eyeFocusSummariesKey = "com.vitalscore.eyeFocusSummaries.v1"

    private let defaults: UserDefaults
    private let exportDirectoryOverride: URL?

    init(defaults: UserDefaults = .standard, exportDirectory: URL? = nil) {
        self.defaults = defaults
        self.exportDirectoryOverride = exportDirectory
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

    @discardableResult
    func writeEyeFocusAnalysisExport(result: EyeFocusTestResult, dailyRecord: DailyHealthRecord?) -> URL? {
        persist(export: MultimodalAnalysisExport.eyeFocus(result: result, dailyRecord: dailyRecord))
    }

    @discardableResult
    func writeVoiceAnalysisExport(session: VoiceTrackingSession, dailyRecord: DailyHealthRecord?) -> URL? {
        persist(export: MultimodalAnalysisExport.voice(session: session, dailyRecord: dailyRecord))
    }

    @discardableResult
    func writeVoiceAIAnalysisResult(_ analysis: VoiceAIAnalysisResponse, exportFileURL: URL) -> URL? {
        guard let dir = ensureExportDirectory() else { return nil }
        let stored = VoiceAIAnalysisStoredResult(
            schemaVersion: VoiceAIAnalysisStoredResult.currentSchemaVersion,
            storedAt: Date(),
            exportFileName: exportFileURL.lastPathComponent,
            analysis: analysis
        )
        let fileName = "voice_ai_\(stored.analysis.id.uuidString).json"
        let url = dir.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(stored) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            appendAIIndexLine(fileName: fileName, in: dir)
            return url
        } catch {
            return nil
        }
    }

    private func persist(export: MultimodalAnalysisExport) -> URL? {
        guard let dir = ensureExportDirectory() else { return nil }
        let stamp = ISO8601DateFormatter().string(from: export.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(export.source.rawValue)_\(stamp)_\(export.id.uuidString).json"
        let url = dir.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(export) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            let entry = AnalysisExportIndexEntry(
                exportId: export.id,
                createdAt: export.createdAt,
                source: export.source,
                fileName: fileName,
                availableModalities: export.availableModalities
            )
            appendIndex(entry: entry, in: dir)
            return url
        } catch {
            return nil
        }
    }

    private func ensureExportDirectory() -> URL? {
        let base: URL
        if let override = exportDirectoryOverride {
            base = override
        } else {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            base = docs.appendingPathComponent("Analysis", isDirectory: true)
        }
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private func appendIndex(entry: AnalysisExportIndexEntry, in directory: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let line = (try? encoder.encode(entry))
            .flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        appendLine(line, fileName: Self.analysisIndexFileName, in: directory)
    }

    private func appendAIIndexLine(fileName analysisFileName: String, in directory: URL) {
        appendLine(analysisFileName, fileName: Self.aiAnalysisIndexFileName, in: directory)
    }

    private func appendLine(_ line: String, fileName: String, in directory: URL) {
        let url = directory.appendingPathComponent(fileName)
        let payload = line + "\n"
        guard let data = payload.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
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
    }

    private struct ExperimentSelectionPayload: Codable {
        let tag: ExperimentTag?
        let customLabel: String?
    }
}
