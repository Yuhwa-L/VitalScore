import Foundation

final class LocalStorageManager: ObservableObject {
    static let recordsKey = "com.vitalscore.records.v1"
    static let experimentKey = "com.vitalscore.experiment.v1"
    static let onboardingKey = "com.vitalscore.onboardingComplete.v1"
    static let healthPermissionKey = "com.vitalscore.healthPermissionGranted.v1"
    static let voiceSessionsKey = "com.vitalscore.voiceSessions.v1"
    static let analysisIndexFileName = "analysis_exports.jsonl"
    static let aiAnalysisIndexFileName = "ai_analysis_results.jsonl"

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

    @discardableResult
    func writeEyeFocusAnalysisExport(result: EyeFocusTestResult, dailyRecord: DailyHealthRecord?) -> URL? {
        writeAnalysisExport(.eyeFocus(result: result, dailyRecord: dailyRecord))
    }

    @discardableResult
    func writeVoiceAnalysisExport(session: VoiceTrackingSession, dailyRecord: DailyHealthRecord?) -> URL? {
        writeAnalysisExport(.voice(session: session, dailyRecord: dailyRecord))
    }

    @discardableResult
    func writeVoiceAIAnalysisResult(_ analysis: VoiceAIAnalysisResponse, exportFileURL: URL) -> URL? {
        writeVoiceAIAnalysisResult(
            VoiceAIAnalysisStoredResult(
                exportFileName: exportFileURL.lastPathComponent,
                analysis: analysis
            )
        )
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
        try? FileManager.default.removeItem(at: analysisExportDirectory)
    }

    var analysisExportDirectory: URL {
        if let exportDirectoryOverride {
            return exportDirectoryOverride
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("VitalScoreAnalysisExports", isDirectory: true)
    }

    private func writeAnalysisExport(_ export: MultimodalAnalysisExport) -> URL? {
        do {
            try FileManager.default.createDirectory(at: analysisExportDirectory, withIntermediateDirectories: true)
            let fileName = Self.fileName(for: export)
            let fileURL = analysisExportDirectory.appendingPathComponent(fileName)
            let encoder = Self.analysisEncoder()
            let data = try encoder.encode(export)
            try data.write(to: fileURL, options: [.atomic])
            try appendIndexEntry(for: export, fileName: fileName)
            return fileURL
        } catch {
            assertionFailure("Failed to write analysis export: \(error.localizedDescription)")
            return nil
        }
    }

    private func writeVoiceAIAnalysisResult(_ storedResult: VoiceAIAnalysisStoredResult) -> URL? {
        do {
            try FileManager.default.createDirectory(at: analysisExportDirectory, withIntermediateDirectories: true)
            let fileName = Self.fileName(for: storedResult)
            let fileURL = analysisExportDirectory.appendingPathComponent(fileName)
            let encoder = Self.analysisEncoder()
            let data = try encoder.encode(storedResult)
            try data.write(to: fileURL, options: [.atomic])
            try appendAIAnalysisIndexEntry(for: storedResult, fileName: fileName)
            return fileURL
        } catch {
            assertionFailure("Failed to write voice AI analysis result: \(error.localizedDescription)")
            return nil
        }
    }

    private func appendIndexEntry(
        for export: MultimodalAnalysisExport,
        fileName: String
    ) throws {
        let entry = AnalysisExportIndexEntry(
            exportId: export.id,
            createdAt: export.createdAt,
            source: export.source,
            fileName: fileName,
            availableModalities: export.availableModalities
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(entry)
        line.append(0x0A)

        let indexURL = analysisExportDirectory.appendingPathComponent(Self.analysisIndexFileName)
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let handle = try FileHandle(forWritingTo: indexURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: indexURL, options: [.atomic])
        }
    }

    private func appendAIAnalysisIndexEntry(
        for storedResult: VoiceAIAnalysisStoredResult,
        fileName: String
    ) throws {
        let analysis = storedResult.analysis
        let entry = VoiceAIAnalysisIndexEntry(
            analysisId: analysis.id,
            exportId: analysis.exportId,
            createdAt: analysis.createdAt,
            fileName: fileName,
            exportFileName: storedResult.exportFileName,
            source: analysis.source
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(entry)
        line.append(0x0A)

        let indexURL = analysisExportDirectory.appendingPathComponent(Self.aiAnalysisIndexFileName)
        if FileManager.default.fileExists(atPath: indexURL.path) {
            let handle = try FileHandle(forWritingTo: indexURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: indexURL, options: [.atomic])
        }
    }

    private static func fileName(for export: MultimodalAnalysisExport) -> String {
        let timestamp = exportFileDateFormatter.string(from: export.createdAt)
        return "\(timestamp)_\(export.source.rawValue)_\(export.id.uuidString).json"
    }

    private static func fileName(for storedResult: VoiceAIAnalysisStoredResult) -> String {
        let timestamp = exportFileDateFormatter.string(from: storedResult.analysis.createdAt)
        return "\(timestamp)_voice_ai_analysis_\(storedResult.analysis.exportId.uuidString).json"
    }

    private static func analysisEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static let exportFileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private struct ExperimentSelectionPayload: Codable {
        let tag: ExperimentTag?
        let customLabel: String?
    }
}
