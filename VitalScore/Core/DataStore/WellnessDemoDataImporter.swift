import Foundation

struct WellnessDemoImportResult {
    let recordsImported: Int
    let voiceSessionsImported: Int
    let gazeLogsImported: Int
    let eyeFocusSummariesImported: Int
    let tagsImported: [String]
    let latestRecord: DailyHealthRecord?
}

enum WellnessDemoDataImportError: LocalizedError {
    case missingFixture
    case decodingFailed(Error)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingFixture:
            return "Could not find bundled tag data in the app bundle."
        case .decodingFailed(let error):
            return "Could not decode wellness demo data: \(error.localizedDescription)"
        case .encodingFailed:
            return "Could not save wellness demo data."
        }
    }
}

struct WellnessDemoDataFixture: Codable {
    let schemaVersion: String
    let description: String
    let dateEncoding: String
    let tag: String?
    let dailyRecords: [DailyHealthRecord]
    let eyeFocusResults: [EyeFocusTestResult]
    let voiceSessions: [VoiceTrackingSession]
}

extension LocalStorageManager {
    private static let bundledTagDataFixtureNames = [
        "morning_7_day",
        "gym_7_day",
        "alcohol_7_day"
    ]
    private static let legacyBundledTagNames = ["Morning Sunlight"]
    private static let bundledGazeLogSubdirectory = "TagData/GazeLogs"

    var shouldAutoloadTagDemoData: Bool {
        if defaults.bool(forKey: Self.tagDemoAutoloadSuppressedKey) {
            return false
        }
        let records = loadAllRecords()
        let existingTags = Set(records.map { ExperimentTagValue.normalized($0.experimentTag).lowercased() })
        return records.isEmpty ||
            existingTags.contains("morning sunlight") ||
            !["morning", "gym", "alcohol"].allSatisfy { existingTags.contains($0) } ||
            Self.hasMissingBundledGazeLogs()
    }

    @discardableResult
    func loadTagDemoFixtures(bundle: Bundle = .main) throws -> WellnessDemoImportResult {
        let urls = Self.bundledTagDataFixtureNames.compactMap {
            bundle.url(forResource: $0, withExtension: "json", subdirectory: "TagData")
                ?? bundle.url(forResource: $0, withExtension: "json")
        }
        guard !urls.isEmpty else {
            throw WellnessDemoDataImportError.missingFixture
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var fixtures: [WellnessDemoDataFixture] = []
        for url in urls {
            do {
                fixtures.append(try decoder.decode(WellnessDemoDataFixture.self, from: Data(contentsOf: url)))
            } catch {
                throw WellnessDemoDataImportError.decodingFailed(error)
            }
        }

        var tagSet = Set<String>()
        for fixture in fixtures {
            if let tag = fixture.tag {
                tagSet.insert(ExperimentTagValue.normalized(tag))
            }
            for record in fixture.dailyRecords {
                tagSet.insert(ExperimentTagValue.normalized(record.experimentTag))
            }
            for session in fixture.voiceSessions {
                tagSet.insert(ExperimentTagValue.normalized(session.experimentTag))
            }
        }
        let importedTags = Array(tagSet)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let cleanupTags = Array(Set(importedTags + Self.legacyBundledTagNames))

        var existingRecords = loadAllRecords()
        existingRecords.removeAll { record in
            cleanupTags.contains { ExperimentTagValue.matches(record.experimentTag, filter: $0) }
        }
        var existingSessions = loadVoiceSessions()
        existingSessions.removeAll { session in
            cleanupTags.contains { ExperimentTagValue.matches(session.experimentTag, filter: $0) }
        }

        let records = fixtures
            .flatMap(\.dailyRecords)
            .sorted { $0.date < $1.date }
        let sessions = fixtures
            .flatMap(\.voiceSessions)
            .sorted { $0.date < $1.date }

        let mergedRecords = (existingRecords + records).sorted { $0.date < $1.date }
        let mergedSessions = (existingSessions + sessions).sorted { $0.date < $1.date }
        let gazeImport = try importGazeLogFixtures(
            bundle: bundle,
            importedTags: importedTags,
            cleanupTags: cleanupTags
        )

        let encoder = JSONEncoder()
        guard let recordData = try? encoder.encode(mergedRecords),
              let sessionData = try? encoder.encode(mergedSessions)
        else {
            throw WellnessDemoDataImportError.encodingFailed
        }

        defaults.set(recordData, forKey: Self.recordsKey)
        defaults.set(sessionData, forKey: Self.voiceSessionsKey)
        revision += 1

        return WellnessDemoImportResult(
            recordsImported: records.count,
            voiceSessionsImported: sessions.count,
            gazeLogsImported: gazeImport.logs,
            eyeFocusSummariesImported: gazeImport.summaries,
            tagsImported: importedTags,
            latestRecord: records.last
        )
    }

    @discardableResult
    func loadWellnessDemoFixture(bundle: Bundle = .main) throws -> WellnessDemoImportResult {
        try loadTagDemoFixtures(bundle: bundle)
    }

    private static func bundledGazeLogURLs(bundle: Bundle = .main) -> [URL] {
        let urls = bundle.urls(
            forResourcesWithExtension: "json",
            subdirectory: bundledGazeLogSubdirectory
        ) ?? []
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func hasMissingBundledGazeLogs(bundle: Bundle = .main) -> Bool {
        let expectedNames = Set(bundledGazeLogURLs(bundle: bundle).map(\.lastPathComponent))
        guard !expectedNames.isEmpty else { return false }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return true
        }
        let directory = documents.appendingPathComponent("GazeLogs", isDirectory: true)
        let existingNames = Set(
            ((try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []).map(\.lastPathComponent)
        )
        return !expectedNames.isSubset(of: existingNames)
    }

    private func importGazeLogFixtures(
        bundle: Bundle,
        importedTags: [String],
        cleanupTags: [String]
    ) throws -> (logs: Int, summaries: Int) {
        let sourceURLs = Self.bundledGazeLogURLs(bundle: bundle)
        guard !sourceURLs.isEmpty else { return (0, 0) }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (0, 0)
        }

        let directory = documents.appendingPathComponent("GazeLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let bundledNames = Set(sourceURLs.map(\.lastPathComponent))
        removeExistingGazeLogs(in: directory, importedTags: cleanupTags, bundledNames: bundledNames)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var copiedLogs = 0
        var importedSummaries: [EyeFocusAISummary] = []
        for sourceURL in sourceURLs {
            let data = try Data(contentsOf: sourceURL)
            let logFile = try decoder.decode(GazeLogFile.self, from: data)
            guard importedTags.contains(where: { ExperimentTagValue.matches(logFile.experimentTag, filter: $0) }) else {
                continue
            }

            let destinationURL = directory.appendingPathComponent(sourceURL.lastPathComponent)
            try data.write(to: destinationURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.modificationDate: logFile.testStartedAt],
                ofItemAtPath: destinationURL.path
            )
            copiedLogs += 1
            importedSummaries.append(
                eyeFocusFixtureSummary(for: logFile, sourceLogFileName: sourceURL.lastPathComponent)
            )
        }

        try saveImportedEyeFocusSummaries(
            importedSummaries,
            importedTags: cleanupTags,
            bundledNames: bundledNames
        )
        return (copiedLogs, importedSummaries.count)
    }

    private func removeExistingGazeLogs(
        in directory: URL,
        importedTags: [String],
        bundledNames: Set<String>
    ) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in urls where url.pathExtension == "json" {
            if bundledNames.contains(url.lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  let logFile = try? decoder.decode(GazeLogFile.self, from: data)
            else { continue }
            if importedTags.contains(where: { ExperimentTagValue.matches(logFile.experimentTag, filter: $0) }) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func saveImportedEyeFocusSummaries(
        _ summaries: [EyeFocusAISummary],
        importedTags: [String],
        bundledNames: Set<String>
    ) throws {
        var existing = loadEyeFocusSummaries()
        existing.removeAll { summary in
            if let sourceLogFileName = summary.sourceLogFileName,
               bundledNames.contains(sourceLogFileName) {
                return true
            }
            return importedTags.contains {
                ExperimentTagValue.matches(summary.experimentTag, filter: $0)
            }
        }

        let merged = (existing + summaries).sorted { $0.generatedAt < $1.generatedAt }
        guard let data = try? JSONEncoder().encode(merged) else {
            throw WellnessDemoDataImportError.encodingFailed
        }
        defaults.set(data, forKey: Self.eyeFocusSummariesKey)
    }

    private func eyeFocusFixtureSummary(
        for logFile: GazeLogFile,
        sourceLogFileName: String
    ) -> EyeFocusAISummary {
        let tag = ExperimentTagValue.normalized(logFile.experimentTag)
        let metrics = logFile.metrics
        let reaction = logFile.reaction
        let completedAt = logFile.testStartedAt.addingTimeInterval(logFile.durationSeconds)

        return EyeFocusAISummary(
            resultCompletedAt: completedAt,
            generatedAt: completedAt.addingTimeInterval(30),
            model: "fixture_eye_focus_summary_v1",
            sourceLogFileName: sourceLogFileName,
            experimentTag: tag,
            overallSummary: "\(tag) fixture shows a gaze score of \(whole(metrics?.gazeScore)) with \(whole(metrics?.trackingLossPct))% tracking loss.",
            confidence: fixtureConfidence(metrics),
            sections: [
                EyeFocusAISummarySection(
                    title: "Reaction",
                    summary: "Average reaction time was \(whole(reaction?.averageReactionMs)) ms with \(reaction?.missedTargets ?? 0) missed targets."
                ),
                EyeFocusAISummarySection(
                    title: "Gaze Control",
                    summary: "Accuracy averaged \(whole(metrics?.gazeAccuracyPx)) px and stability averaged \(whole(metrics?.gazeStabilityPx)) px."
                ),
                EyeFocusAISummarySection(
                    title: "Tracking Quality",
                    summary: "Fixation held for \(whole(metrics?.fixationDurationMs)) ms with a blink rate of \(whole(metrics?.blinkRatePerMin)) per minute."
                )
            ]
        )
    }

    private func fixtureConfidence(_ metrics: GazeMetrics?) -> String {
        guard let metrics else { return "Low" }
        if metrics.sampleCount >= 900 && metrics.trackingLossPct <= 10 {
            return "High"
        }
        if metrics.sampleCount >= 600 && metrics.trackingLossPct <= 22 {
            return "Medium"
        }
        return "Low"
    }

    private func whole(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
    }
}
