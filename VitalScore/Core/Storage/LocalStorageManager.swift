import Combine
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

    let defaults: UserDefaults
    private let exportDirectoryOverride: URL?
    private let documentsDirectoryOverride: URL?
    @Published var revision = 0

    init(defaults: UserDefaults = .standard, exportDirectory: URL? = nil, documentsDirectory: URL? = nil) {
        self.defaults = defaults
        self.exportDirectoryOverride = exportDirectory
        self.documentsDirectoryOverride = documentsDirectory
    }

    private static func matches(_ date: Date, dateInterval: DateInterval?) -> Bool {
        guard let dateInterval else { return true }
        return date >= dateInterval.start && date < dateInterval.end
    }

    func saveRecord(_ record: DailyHealthRecord) {
        var existing = loadAllRecords()
        existing.removeAll {
            Calendar.current.isDate($0.date, inSameDayAs: record.date) &&
            ExperimentTagValue.matches($0.experimentTag, filter: record.experimentTag)
        }
        existing.append(record)
        existing.sort { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: Self.recordsKey)
            revision += 1
        }
    }

    func loadAllRecords(tagFilter: String? = nil, dateInterval: DateInterval? = nil) -> [DailyHealthRecord] {
        guard let data = defaults.data(forKey: Self.recordsKey) else { return [] }
        let decoded = (try? JSONDecoder().decode([DailyHealthRecord].self, from: data)) ?? []
        return decoded.filter {
            ExperimentTagValue.matches($0.experimentTag, filter: tagFilter) &&
            Self.matches($0.date, dateInterval: dateInterval)
        }
    }

    func recordsInWindow(days: Int, asOf reference: Date = Date(), tagFilter: String? = nil) -> [DailyHealthRecord] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: reference) else {
            return []
        }
        return loadAllRecords(tagFilter: tagFilter).filter { $0.date >= cutoff && $0.date < reference }
    }

    func saveVoiceSession(_ session: VoiceTrackingSession) {
        let session = session.removingLocallySavedLiveData()
        var existing = loadVoiceSessions()
        existing.removeAll { $0.id == session.id }
        existing.append(session)
        // Strip anything dated in the future — clock skew or stale debug data
        // would otherwise push real points behind on the trend graph.
        let now = Date()
        existing.removeAll { $0.date > now }
        existing.sort { $0.date < $1.date }
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: Self.voiceSessionsKey)
            revision += 1
        }
    }

    func loadVoiceSessions(tagFilter: String? = nil, dateInterval: DateInterval? = nil) -> [VoiceTrackingSession] {
        guard let data = defaults.data(forKey: Self.voiceSessionsKey) else { return [] }
        let decoded = (try? JSONDecoder().decode([VoiceTrackingSession].self, from: data)) ?? []
        let now = Date()
        let cleaned = decoded.filter { $0.date <= now }
        // Persist the cleanup so future-dated rows can't keep coming back.
        if cleaned.count != decoded.count,
           let data = try? JSONEncoder().encode(cleaned) {
            defaults.set(data, forKey: Self.voiceSessionsKey)
        }
        return cleaned.filter {
            ExperimentTagValue.matches($0.experimentTag, filter: tagFilter) &&
            Self.matches($0.date, dateInterval: dateInterval)
        }
    }

    func voiceSessionsInWindow(days: Int, asOf reference: Date = Date(), tagFilter: String? = nil) -> [VoiceTrackingSession] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: reference) else {
            return []
        }
        return loadVoiceSessions(tagFilter: tagFilter).filter { $0.date >= cutoff && $0.date < reference }
    }

    func saveEyeFocusSummary(_ summary: EyeFocusAISummary) {
        var existing = loadEyeFocusSummaries()
        existing.removeAll { $0.id == summary.id || $0.sourceLogFileName == summary.sourceLogFileName }
        existing.append(summary)
        existing.sort { $0.generatedAt < $1.generatedAt }
        if let data = try? JSONEncoder().encode(existing) {
            defaults.set(data, forKey: Self.eyeFocusSummariesKey)
            revision += 1
        }
    }

    func loadEyeFocusSummaries(tagFilter: String? = nil, dateInterval: DateInterval? = nil) -> [EyeFocusAISummary] {
        guard let data = defaults.data(forKey: Self.eyeFocusSummariesKey) else { return [] }
        let decoded = (try? JSONDecoder().decode([EyeFocusAISummary].self, from: data)) ?? []
        return decoded.filter {
            ExperimentTagValue.matches($0.experimentTag, filter: tagFilter) &&
            Self.matches($0.resultCompletedAt, dateInterval: dateInterval)
        }
    }

    func latestEyeFocusSummary(tagFilter: String? = nil, dateInterval: DateInterval? = nil) -> EyeFocusAISummary? {
        loadEyeFocusSummaries(tagFilter: tagFilter, dateInterval: dateInterval)
            .sorted { $0.resultCompletedAt < $1.resultCompletedAt }
            .last
    }

    func availableExperimentTags(extraTags: [String] = []) -> [String] {
        let tags = loadAllRecords().map(\.experimentTag) +
            loadVoiceSessions().map(\.experimentTag) +
            loadEyeFocusSummaries().map { ExperimentTagValue.normalized($0.experimentTag) } +
            extraTags
        return Array(Set(tags.map { ExperimentTagValue.normalized($0) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func removeEyeFocusSummaries(forFileNames names: Set<String>) {
        guard !names.isEmpty else { return }
        let remaining = loadEyeFocusSummaries().filter { summary in
            guard let name = summary.sourceLogFileName else { return true }
            return !names.contains(name)
        }
        if let data = try? JSONEncoder().encode(remaining) {
            defaults.set(data, forKey: Self.eyeFocusSummariesKey)
            revision += 1
        }
    }

    @discardableResult
    func writeEyeFocusAnalysisExport(result: EyeFocusTestResult, dailyRecord: DailyHealthRecord?) -> URL? {
        persist(export: MultimodalAnalysisExport.eyeFocus(result: result, dailyRecord: dailyRecord))
    }

    @discardableResult
    func writeVoiceAnalysisExport(session: VoiceTrackingSession, dailyRecord: DailyHealthRecord?) -> URL? {
        persist(export: MultimodalAnalysisExport.voice(
            session: session.removingLocallySavedLiveData(),
            dailyRecord: dailyRecord
        ))
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
            let entry = VoiceAIAnalysisIndexEntry(
                analysisId: stored.analysis.id,
                exportId: stored.analysis.exportId,
                createdAt: stored.analysis.createdAt,
                fileName: fileName,
                exportFileName: stored.exportFileName,
                source: stored.analysis.source
            )
            appendAIIndex(entry: entry, in: dir)
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
        guard let base = exportDirectoryURL else { return nil }
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private var exportDirectoryURL: URL? {
        if let override = exportDirectoryOverride {
            return override
        }
        return documentsDirectoryURL?.appendingPathComponent("Analysis", isDirectory: true)
    }

    private var existingExportDirectoryURL: URL? {
        guard let url = exportDirectoryURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    private var documentsDirectoryURL: URL? {
        if let override = documentsDirectoryOverride {
            return override
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func appendIndex(entry: AnalysisExportIndexEntry, in directory: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let line = (try? encoder.encode(entry))
            .flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        appendLine(line, fileName: Self.analysisIndexFileName, in: directory)
    }

    private func appendAIIndex(entry: VoiceAIAnalysisIndexEntry, in directory: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let line = (try? encoder.encode(entry))
            .flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        appendLine(line, fileName: Self.aiAnalysisIndexFileName, in: directory)
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
        revision += 1
    }

    @discardableResult
    func removeTodaysJSONData(referenceDate: Date = Date()) -> TodaysJSONDataCleanupResult {
        let calendar = Calendar.current
        var result = TodaysJSONDataCleanupResult()

        result.dailyRecordsRemoved = removeTodaysDailyRecords(referenceDate: referenceDate, calendar: calendar)
        result.voiceSessionsRemoved = removeTodaysVoiceSessions(referenceDate: referenceDate, calendar: calendar)
        result.eyeFocusSummariesRemoved = removeTodaysEyeFocusSummaries(referenceDate: referenceDate, calendar: calendar)

        if result.dailyRecordsRemoved > 0 ||
            result.voiceSessionsRemoved > 0 ||
            result.eyeFocusSummariesRemoved > 0 {
            revision += 1
        }

        var removedAnalysisFileNames: Set<String> = []
        if let directory = existingExportDirectoryURL {
            removedAnalysisFileNames.formUnion(removeJSONFiles(
                in: directory,
                referenceDate: referenceDate,
                calendar: calendar,
                extensions: ["json"],
                recursive: false,
                deletedCount: &result.analysisJSONFilesDeleted
            ))
            result.analysisIndexEntriesRemoved = rewriteAnalysisIndexForToday(
                in: directory,
                referenceDate: referenceDate,
                calendar: calendar,
                removedFileNames: removedAnalysisFileNames
            )
            result.aiAnalysisIndexEntriesRemoved = rewriteAIAnalysisIndexForToday(
                in: directory,
                referenceDate: referenceDate,
                calendar: calendar,
                removedFileNames: removedAnalysisFileNames
            )
        }

        if let documents = documentsDirectoryURL {
            let gazeDirectory = documents.appendingPathComponent("GazeLogs", isDirectory: true)
            _ = removeJSONFiles(
                in: gazeDirectory,
                referenceDate: referenceDate,
                calendar: calendar,
                extensions: ["json"],
                recursive: false,
                deletedCount: &result.gazeLogFilesDeleted
            )
        }

        let debugDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(VoiceRawAudioDebugExportSettings.directoryName, isDirectory: true)
        _ = removeJSONFiles(
            in: debugDirectory,
            referenceDate: referenceDate,
            calendar: calendar,
            extensions: ["json", "jsonl"],
            recursive: true,
            deletedCount: &result.debugJSONFilesDeleted
        )

        return result
    }

    @discardableResult
    func removeLocallySavedLiveVoiceData() -> LiveVoiceDataCleanupResult {
        var result = LiveVoiceDataCleanupResult()
        let sessions = decodedVoiceSessions()
        let cleanedSessions = sessions.map { session -> VoiceTrackingSession in
            guard session.containsLocallySavedLiveData else { return session }
            result.voiceSessionsScrubbed += 1
            if let manifestPath = session.rawAudioDebugManifestPath,
               removeRawAudioDebugDirectory(manifestPath: manifestPath) {
                result.rawAudioDebugDirectoriesDeleted += 1
            }
            return session.removingLocallySavedLiveData()
        }

        if cleanedSessions != sessions,
           let data = try? JSONEncoder().encode(cleanedSessions) {
            defaults.set(data, forKey: Self.voiceSessionsKey)
            revision += 1
        }

        guard let directory = existingExportDirectoryURL,
              let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              )
        else {
            return result
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var removedExportIds: Set<UUID> = []
        var removedExportFileNames: Set<String> = []

        for url in fileURLs where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let export = try? decoder.decode(MultimodalAnalysisExport.self, from: data),
                  export.containsLocallySavedLiveVoiceData
            else { continue }
            try? FileManager.default.removeItem(at: url)
            removedExportIds.insert(export.id)
            removedExportFileNames.insert(url.lastPathComponent)
            result.analysisExportFilesDeleted += 1
        }

        if !removedExportIds.isEmpty || !removedExportFileNames.isEmpty {
            rewriteAnalysisIndex(
                in: directory,
                removingExportIds: removedExportIds,
                removingFileNames: removedExportFileNames
            )
            removeLinkedAIAnalysisResults(
                in: directory,
                removedExportIds: removedExportIds,
                removedExportFileNames: removedExportFileNames,
                deletedCount: &result.aiAnalysisFilesDeleted
            )
        }

        return result
    }

    private func removeTodaysDailyRecords(referenceDate: Date, calendar: Calendar) -> Int {
        let records = loadAllRecords()
        let remaining = records.filter { !calendar.isDate($0.date, inSameDayAs: referenceDate) }
        guard remaining.count != records.count,
              let data = try? JSONEncoder().encode(remaining)
        else { return 0 }
        defaults.set(data, forKey: Self.recordsKey)
        return records.count - remaining.count
    }

    private func removeTodaysVoiceSessions(referenceDate: Date, calendar: Calendar) -> Int {
        let sessions = decodedVoiceSessions()
        let remaining = sessions.filter { !calendar.isDate($0.date, inSameDayAs: referenceDate) }
        guard remaining.count != sessions.count,
              let data = try? JSONEncoder().encode(remaining)
        else { return 0 }
        defaults.set(data, forKey: Self.voiceSessionsKey)
        return sessions.count - remaining.count
    }

    private func removeTodaysEyeFocusSummaries(referenceDate: Date, calendar: Calendar) -> Int {
        let summaries = loadEyeFocusSummaries()
        let remaining = summaries.filter {
            !calendar.isDate($0.resultCompletedAt, inSameDayAs: referenceDate) &&
            !calendar.isDate($0.generatedAt, inSameDayAs: referenceDate)
        }
        guard remaining.count != summaries.count,
              let data = try? JSONEncoder().encode(remaining)
        else { return 0 }
        defaults.set(data, forKey: Self.eyeFocusSummariesKey)
        return summaries.count - remaining.count
    }

    private func decodedVoiceSessions() -> [VoiceTrackingSession] {
        guard let data = defaults.data(forKey: Self.voiceSessionsKey) else { return [] }
        return (try? JSONDecoder().decode([VoiceTrackingSession].self, from: data)) ?? []
    }

    private func removeRawAudioDebugDirectory(manifestPath: String) -> Bool {
        let manifestURL = URL(fileURLWithPath: manifestPath)
        guard manifestURL.lastPathComponent == VoiceRawAudioDebugExportSettings.manifestFileName,
              manifestURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == VoiceRawAudioDebugExportSettings.directoryName
        else { return false }
        do {
            try FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent())
            return true
        } catch {
            return false
        }
    }

    private func rewriteAnalysisIndex(
        in directory: URL,
        removingExportIds removedExportIds: Set<UUID>,
        removingFileNames removedFileNames: Set<String>
    ) {
        let url = directory.appendingPathComponent(Self.analysisIndexFileName)
        let entries: [AnalysisExportIndexEntry] = readJSONL(AnalysisExportIndexEntry.self, from: url)
            .filter { !removedExportIds.contains($0.exportId) && !removedFileNames.contains($0.fileName) }
        writeJSONL(entries, to: url)
    }

    private func removeLinkedAIAnalysisResults(
        in directory: URL,
        removedExportIds: Set<UUID>,
        removedExportFileNames: Set<String>,
        deletedCount: inout Int
    ) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        var removedAnalysisFileNames: Set<String> = []
        for url in fileURLs where url.lastPathComponent.hasPrefix("voice_ai_") && url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let stored = try? decoder.decode(VoiceAIAnalysisStoredResult.self, from: data),
                  removedExportIds.contains(stored.analysis.exportId) ||
                  removedExportFileNames.contains(stored.exportFileName)
            else { continue }
            try? FileManager.default.removeItem(at: url)
            removedAnalysisFileNames.insert(url.lastPathComponent)
            deletedCount += 1
        }

        let indexURL = directory.appendingPathComponent(Self.aiAnalysisIndexFileName)
        let entries: [VoiceAIAnalysisIndexEntry] = readJSONL(VoiceAIAnalysisIndexEntry.self, from: indexURL)
            .filter {
                !removedExportIds.contains($0.exportId) &&
                !removedExportFileNames.contains($0.exportFileName) &&
                !removedAnalysisFileNames.contains($0.fileName)
        }
        writeJSONL(entries, to: indexURL)
    }

    private func rewriteAnalysisIndexForToday(
        in directory: URL,
        referenceDate: Date,
        calendar: Calendar,
        removedFileNames: Set<String>
    ) -> Int {
        let url = directory.appendingPathComponent(Self.analysisIndexFileName)
        let entries: [AnalysisExportIndexEntry] = readJSONL(AnalysisExportIndexEntry.self, from: url)
        let remaining = entries.filter { entry in
            guard !calendar.isDate(entry.createdAt, inSameDayAs: referenceDate),
                  !removedFileNames.contains(entry.fileName)
            else { return false }
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.fileName).path)
        }
        writeJSONL(remaining, to: url)
        return entries.count - remaining.count
    }

    private func rewriteAIAnalysisIndexForToday(
        in directory: URL,
        referenceDate: Date,
        calendar: Calendar,
        removedFileNames: Set<String>
    ) -> Int {
        let url = directory.appendingPathComponent(Self.aiAnalysisIndexFileName)
        let entries: [VoiceAIAnalysisIndexEntry] = readJSONL(VoiceAIAnalysisIndexEntry.self, from: url)
        let remaining = entries.filter { entry in
            guard !calendar.isDate(entry.createdAt, inSameDayAs: referenceDate),
                  !removedFileNames.contains(entry.fileName),
                  !removedFileNames.contains(entry.exportFileName)
            else { return false }
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.fileName).path)
        }
        writeJSONL(remaining, to: url)
        return entries.count - remaining.count
    }

    private func removeJSONFiles(
        in directory: URL,
        referenceDate: Date,
        calendar: Calendar,
        extensions: Set<String>,
        recursive: Bool,
        deletedCount: inout Int
    ) -> Set<String> {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls: [URL]
        if recursive,
           let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
           ) {
            urls = enumerator.compactMap { $0 as? URL }
        } else {
            urls = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            )) ?? []
        }

        var removedFileNames: Set<String> = []
        for url in urls {
            guard extensions.contains(url.pathExtension.lowercased()),
                  isRegularFile(url),
                  fileIsFromDay(url, referenceDate: referenceDate, calendar: calendar)
            else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removedFileNames.insert(url.lastPathComponent)
                deletedCount += 1
            } catch {
                continue
            }
        }
        return removedFileNames
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard let value = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile else {
            return false
        }
        return value == true
    }

    private func fileIsFromDay(_ url: URL, referenceDate: Date, calendar: Calendar) -> Bool {
        if let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           calendar.isDate(modifiedAt, inSameDayAs: referenceDate) {
            return true
        }
        return fileName(url.lastPathComponent, containsDayOf: referenceDate, calendar: calendar)
    }

    private func fileName(_ fileName: String, containsDayOf date: Date, calendar: Calendar) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if fileName.contains(formatter.string(from: date)) {
            return true
        }
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return fileName.contains(formatter.string(from: date))
    }

    private func readJSONL<T: Decodable>(_ type: T.Type, from url: URL) -> [T] {
        guard let text = try? String(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(T.self, from: Data(line.utf8))
        }
    }

    private func writeJSONL<T: Encodable>(_ entries: [T], to url: URL) {
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let lines = entries.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private struct ExperimentSelectionPayload: Codable {
        let tag: ExperimentTag?
        let customLabel: String?
    }
}

struct LiveVoiceDataCleanupResult: Equatable {
    var voiceSessionsScrubbed = 0
    var analysisExportFilesDeleted = 0
    var aiAnalysisFilesDeleted = 0
    var rawAudioDebugDirectoriesDeleted = 0
}

struct TodaysJSONDataCleanupResult: Equatable {
    var dailyRecordsRemoved = 0
    var voiceSessionsRemoved = 0
    var eyeFocusSummariesRemoved = 0
    var analysisJSONFilesDeleted = 0
    var gazeLogFilesDeleted = 0
    var debugJSONFilesDeleted = 0
    var analysisIndexEntriesRemoved = 0
    var aiAnalysisIndexEntriesRemoved = 0
}
