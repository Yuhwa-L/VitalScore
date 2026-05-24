import XCTest
@testable import VitalScore

final class LocalStorageManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var storage: LocalStorageManager!
    private var documentsDirectory: URL!
    private var exportDirectory: URL!
    private let suite = "com.vitalscore.tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        documentsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitalScoreStorageTests-\(UUID().uuidString)", isDirectory: true)
        exportDirectory = documentsDirectory.appendingPathComponent("Analysis", isDirectory: true)
        storage = LocalStorageManager(
            defaults: defaults,
            exportDirectory: exportDirectory,
            documentsDirectory: documentsDirectory
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: documentsDirectory)
        defaults.removePersistentDomain(forName: suite)
        UserDefaults.standard.removeObject(forKey: VoiceRawAudioDebugExportSettings.userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: VoiceRawAudioDebugExportSettings.aiUploadUserDefaultsKey)
        super.tearDown()
    }

    func test_saveAndLoad_roundtripPreservesAllFields() {
        let record = DailyHealthRecord(
            date: Date(),
            experimentTag: "No Alcohol",
            sleepHours: 7.5,
            restingHeartRateBPM: 61,
            hrvMs: 48,
            stepCount: 8200,
            activeEnergyKcal: 350,
            eyeFocusScore: 84,
            averageReactionMs: 380,
            reactionStdDevMs: 60,
            missedTargets: 1,
            falseTaps: 0,
            voiceScore: 88,
            voiceAverageVolumeDb: -24,
            voiceVolumeStdDevDb: 4.5,
            voiceSilenceRatio: 0.1,
            voicePeakVolumeDb: -12,
            wellnessDeltaScore: 7,
            confidenceLevel: "Medium",
            insightText: "Sleep increased by 30 minutes."
        )
        storage.saveRecord(record)
        let loaded = storage.loadAllRecords()
        XCTAssertEqual(loaded.count, 1)
        let first = loaded.first!
        XCTAssertEqual(first.experimentTag, "No Alcohol")
        XCTAssertEqual(first.sleepHours, 7.5)
        XCTAssertEqual(first.voiceScore, 88)
        XCTAssertEqual(first.voiceSilenceRatio, 0.1)
        XCTAssertEqual(first.wellnessDeltaScore, 7)
        XCTAssertEqual(first.confidenceLevel, "Medium")
        XCTAssertEqual(first.insightText, "Sleep increased by 30 minutes.")
    }

    func test_savingSameDayTwice_overwrites() {
        let date = Date()
        let r1 = DailyHealthRecord(date: date, experimentTag: "A", wellnessDeltaScore: 1, confidenceLevel: "Low", insightText: "")
        let r2 = DailyHealthRecord(date: date, experimentTag: "A", wellnessDeltaScore: 2, confidenceLevel: "Low", insightText: "")
        storage.saveRecord(r1)
        storage.saveRecord(r2)
        let loaded = storage.loadAllRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.experimentTag, "A")
        XCTAssertEqual(loaded.first?.wellnessDeltaScore, 2)
    }

    func test_savingSameDayWithDifferentTags_keepsSeparateRecords() {
        let date = Date()
        storage.saveRecord(DailyHealthRecord(date: date, experimentTag: "Morning", wellnessDeltaScore: 1, confidenceLevel: "Low", insightText: ""))
        storage.saveRecord(DailyHealthRecord(date: date, experimentTag: "Evening", wellnessDeltaScore: 2, confidenceLevel: "Low", insightText: ""))

        XCTAssertEqual(storage.loadAllRecords().count, 2)
        XCTAssertEqual(storage.loadAllRecords(tagFilter: "Morning").map(\.wellnessDeltaScore), [1])
        XCTAssertEqual(storage.loadAllRecords(tagFilter: "Evening").map(\.wellnessDeltaScore), [2])
    }

    func test_customDateIntervalFiltersRecordsVoiceAndEyeSummaries() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let before = base.addingTimeInterval(-86_400)
        let inside = base.addingTimeInterval(3_600)
        let after = base.addingTimeInterval(172_800)
        let interval = DateInterval(start: base, end: base.addingTimeInterval(86_400))

        storage.saveRecord(DailyHealthRecord(date: before, experimentTag: "Morning", wellnessDeltaScore: -1, confidenceLevel: "Low", insightText: "Before"))
        storage.saveRecord(DailyHealthRecord(date: inside, experimentTag: "Morning", wellnessDeltaScore: 4, confidenceLevel: "Low", insightText: "Inside"))
        storage.saveRecord(DailyHealthRecord(date: after, experimentTag: "Morning", wellnessDeltaScore: 9, confidenceLevel: "Low", insightText: "After"))

        storage.saveVoiceSession(VoiceTrackingSession(
            date: before,
            experimentTag: "Morning",
            promptTag: "daily_voice_check_v1",
            result: VoiceTrackingResult(completedAt: before, durationSeconds: 8, voiceScore: 55, averageVolumeDb: -28, volumeStdDevDb: 3, silenceRatio: 0.1, peakVolumeDb: -12)
        ))
        storage.saveVoiceSession(VoiceTrackingSession(
            date: inside,
            experimentTag: "Morning",
            promptTag: "daily_voice_check_v1",
            result: VoiceTrackingResult(completedAt: inside, durationSeconds: 8, voiceScore: 72, averageVolumeDb: -24, volumeStdDevDb: 3, silenceRatio: 0.1, peakVolumeDb: -11)
        ))

        storage.saveEyeFocusSummary(EyeFocusAISummary(
            resultCompletedAt: before,
            generatedAt: before,
            model: "fixture",
            sourceLogFileName: "before.json",
            experimentTag: "Morning",
            overallSummary: "Before",
            sections: []
        ))
        storage.saveEyeFocusSummary(EyeFocusAISummary(
            resultCompletedAt: inside,
            generatedAt: inside,
            model: "fixture",
            sourceLogFileName: "inside.json",
            experimentTag: "Morning",
            overallSummary: "Inside",
            sections: []
        ))

        XCTAssertEqual(storage.loadAllRecords(tagFilter: "Morning", dateInterval: interval).map(\.wellnessDeltaScore), [4])
        XCTAssertEqual(storage.loadVoiceSessions(tagFilter: "Morning", dateInterval: interval).map(\.result.voiceScore), [72])
        XCTAssertEqual(storage.loadEyeFocusSummaries(tagFilter: "Morning", dateInterval: interval).map(\.overallSummary), ["Inside"])
        XCTAssertEqual(storage.latestEyeFocusSummary(tagFilter: "Morning", dateInterval: interval)?.overallSummary, "Inside")
    }

    func test_customExperimentLabel_persistsAlongsideEnum() {
        storage.saveSelectedExperiment(.custom, customLabel: "Cold showers")
        let (tag, label) = storage.loadSelectedExperiment()
        XCTAssertEqual(tag, .custom)
        XCTAssertEqual(label, "Cold showers")
    }

    func test_loadFromEmptyDefaults_returnsEmptyArray() {
        XCTAssertEqual(storage.loadAllRecords().count, 0)
    }

    func test_recordsInWindow_filtersByDate() {
        let now = Date()
        let inside = DailyHealthRecord(date: now.addingTimeInterval(-3600 * 24 * 2), experimentTag: "x", wellnessDeltaScore: 0, confidenceLevel: "Low", insightText: "")
        let outside = DailyHealthRecord(date: now.addingTimeInterval(-3600 * 24 * 20), experimentTag: "x", wellnessDeltaScore: 0, confidenceLevel: "Low", insightText: "")
        storage.saveRecord(inside)
        storage.saveRecord(outside)
        let windowed = storage.recordsInWindow(days: 7, asOf: now)
        XCTAssertEqual(windowed.count, 1)
    }

    func test_availableExperimentTags_deduplicatesAndSortsStoredTags() {
        let now = Date()
        storage.saveRecord(DailyHealthRecord(date: now, experimentTag: "Evening", wellnessDeltaScore: 0, confidenceLevel: "Low", insightText: ""))
        storage.saveRecord(DailyHealthRecord(date: now.addingTimeInterval(-60), experimentTag: " Morning ", wellnessDeltaScore: 0, confidenceLevel: "Low", insightText: ""))
        storage.saveVoiceSession(VoiceTrackingSession(
            date: now,
            experimentTag: "Morning",
            promptTag: "daily_voice_check_v1",
            result: VoiceTrackingResult(
                completedAt: now,
                durationSeconds: 8,
                voiceScore: 80,
                averageVolumeDb: -24,
                volumeStdDevDb: 3,
                silenceRatio: 0.1,
                peakVolumeDb: -11
            )
        ))

        XCTAssertEqual(storage.availableExperimentTags(), ["Evening", "Morning"])
    }

    func test_saveVoiceSession_stripsLiveConversationData() {
        let result = VoiceTrackingResult(
            completedAt: Date(),
            durationSeconds: 12,
            voiceScore: 91,
            averageVolumeDb: -23,
            volumeStdDevDb: 3,
            silenceRatio: 0,
            peakVolumeDb: -10,
            conversationSummary: VoiceConversationSummary(
                questionCount: 4,
                summary: "Summary saved: focus and routine stood out across your answers.",
                source: "openai"
            )
        )
        let session = VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: "Morning",
            promptTag: "daily_voice_check_v1",
            result: result
        )

        storage.saveVoiceSession(session)

        let loaded = storage.loadVoiceSessions()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.experimentTag, "Morning")
        XCTAssertEqual(loaded.first?.promptTag, "daily_voice_check_v1")
        XCTAssertEqual(loaded.first?.result.voiceScore, 91)
        XCTAssertNil(loaded.first?.result.conversationSummary)
        XCTAssertEqual(loaded.first?.result.conversationExchanges.count, 0)
    }

    func test_voiceSessionsInWindow_filtersByDate() {
        let now = Date()
        let recentResult = VoiceTrackingResult(completedAt: now.addingTimeInterval(-3600), durationSeconds: 10, voiceScore: 80, averageVolumeDb: -25, volumeStdDevDb: 3, silenceRatio: 0, peakVolumeDb: -12)
        let oldResult = VoiceTrackingResult(completedAt: now.addingTimeInterval(-3600 * 24 * 12), durationSeconds: 10, voiceScore: 70, averageVolumeDb: -28, volumeStdDevDb: 4, silenceRatio: 0.1, peakVolumeDb: -14)
        storage.saveVoiceSession(VoiceTrackingSession(date: recentResult.completedAt, experimentTag: "A", promptTag: "daily_voice_check_v1", result: recentResult))
        storage.saveVoiceSession(VoiceTrackingSession(date: oldResult.completedAt, experimentTag: "A", promptTag: "daily_voice_check_v1", result: oldResult))

        let windowed = storage.voiceSessionsInWindow(days: 7, asOf: now)
        XCTAssertEqual(windowed.count, 1)
        XCTAssertEqual(windowed.first?.result.voiceScore, 80)
    }

    func test_writeVoiceAnalysisExport_createsLLMReadyJsonAndIndex() throws {
        let result = VoiceTrackingResult(
            completedAt: Date(),
            durationSeconds: 20,
            voiceScore: 82,
            averageVolumeDb: -24,
            volumeStdDevDb: 3.1,
            silenceRatio: 0.12,
            peakVolumeDb: -10,
            conversationExchanges: [
                VoiceConversationExchange(
                    turnIndex: 1,
                    aiPrompt: "How has your energy felt today?",
                    userTranscript: "I feel steady but a little tired after lunch.",
                    userResponseStartedAt: Date(),
                    userResponseEndedAt: Date().addingTimeInterval(8),
                    responseDurationSeconds: 8,
                    source: "ios_speech_recognition"
                )
            ],
            conversationSummary: VoiceConversationSummary(
                questionCount: 1,
                summary: "Summary saved: sleep or rest and steadiness stood out across your answers.",
                source: "openai"
            )
        )
        let session = VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: "Morning",
            promptTag: "ai_voice_conversation_v1",
            result: result
        )
        let record = DailyHealthRecord(
            date: result.completedAt,
            experimentTag: "Morning",
            sleepHours: 7.2,
            voiceScore: result.voiceScore,
            wellnessDeltaScore: 4,
            confidenceLevel: "Medium",
            insightText: "Voice and sleep data available."
        )

        let fileURL = try XCTUnwrap(storage.writeVoiceAnalysisExport(session: session, dailyRecord: record))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let export = try JSONDecoder.iso8601.decode(MultimodalAnalysisExport.self, from: data)
        XCTAssertEqual(export.schemaVersion, MultimodalAnalysisExport.schemaVersion)
        XCTAssertEqual(export.source, .voiceTracking)
        XCTAssertEqual(export.experimentTag, "Morning")
        XCTAssertTrue(export.availableModalities.contains("voice_acoustic_features"))
        XCTAssertFalse(export.availableModalities.contains("voice_conversation_transcript"))
        XCTAssertFalse(export.availableModalities.contains("voice_conversation_summary"))
        XCTAssertEqual(export.voiceSession?.id, session.id)
        XCTAssertEqual(export.voiceSession?.result.conversationExchanges.count, 0)
        XCTAssertNil(export.voiceSession?.result.conversationSummary)
        XCTAssertEqual(export.questionProtocol?.mode, "advanced_freestyle_talk")
        XCTAssertTrue(export.questionProtocol?.questionSet.contains { $0.taskType == VoiceTaskType.guidedConversation.rawValue } == true)
        XCTAssertTrue(export.textContext.contains { $0.contains("Voice question protocol") })
        XCTAssertFalse(export.textContext.contains { $0.contains("AI conversation short summary") })
        XCTAssertEqual(export.voiceFeatureValidation?.first(where: { $0.key == "jitterLocalPercent" })?.status, .unsupported)
        XCTAssertEqual(export.featureVector["voice.score"], 82)
        XCTAssertEqual(export.featureVector["voice.ai_conversation_turn_count"], 0)
        XCTAssertNil(export.featureVector["voice.ai_conversation_summary_word_count"])
        XCTAssertNil(export.featureVector["voice.ai_conversation.turn_1.transcript_word_count"])
        XCTAssertEqual(export.featureVector["health.sleep_hours"], 7.2)

        let indexURL = exportDirectory.appendingPathComponent(LocalStorageManager.analysisIndexFileName)
        let indexText = try String(contentsOf: indexURL)
        XCTAssertTrue(indexText.contains(fileURL.lastPathComponent))
    }

    func test_removeLocallySavedLiveVoiceData_scrubsSessionsAndDeletesLiveExports() throws {
        let rawAudioRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(VoiceRawAudioDebugExportSettings.directoryName, isDirectory: true)
        let rawAudioDirectory = rawAudioRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rawAudioDirectory, withIntermediateDirectories: true)
        let manifestURL = rawAudioDirectory.appendingPathComponent(VoiceRawAudioDebugExportSettings.manifestFileName)
        try Data("{}".utf8).write(to: manifestURL)

        let session = makeLiveVoiceSession(rawAudioDebugManifestPath: manifestURL.path)
        let sessionData = try JSONEncoder().encode([session])
        defaults.set(sessionData, forKey: LocalStorageManager.voiceSessionsKey)

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let export = MultimodalAnalysisExport.voice(session: session, dailyRecord: nil)
        let exportURL = exportDirectory.appendingPathComponent("legacy_live_voice_export.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(export).write(to: exportURL)
        let indexEntry = AnalysisExportIndexEntry(
            exportId: export.id,
            createdAt: export.createdAt,
            source: export.source,
            fileName: exportURL.lastPathComponent,
            availableModalities: export.availableModalities
        )
        try (String(data: encoder.encode(indexEntry), encoding: .utf8)! + "\n")
            .write(
                to: exportDirectory.appendingPathComponent(LocalStorageManager.analysisIndexFileName),
                atomically: true,
                encoding: .utf8
            )

        let analysis = VoiceAIAnalysisResponse(
            id: UUID(),
            exportId: export.id,
            createdAt: Date(),
            source: "openai",
            aiVoiceScore: 80,
            aiScoreConfidence: "Medium",
            aiScoreRationale: "Transcript was reviewed.",
            summary: "Live transcript details were summarized.",
            dataQuality: [],
            notableSignals: [],
            longitudinalContext: [],
            missingData: [],
            recommendedNextSteps: [],
            safetyNote: "Wellness-only."
        )
        let analysisURL = try XCTUnwrap(storage.writeVoiceAIAnalysisResult(analysis, exportFileURL: exportURL))

        let cleanup = storage.removeLocallySavedLiveVoiceData()

        XCTAssertEqual(cleanup.voiceSessionsScrubbed, 1)
        XCTAssertEqual(cleanup.analysisExportFilesDeleted, 1)
        XCTAssertEqual(cleanup.aiAnalysisFilesDeleted, 1)
        XCTAssertEqual(cleanup.rawAudioDebugDirectoriesDeleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: analysisURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rawAudioDirectory.path))

        let scrubbedSession = try XCTUnwrap(storage.loadVoiceSessions().first)
        XCTAssertEqual(scrubbedSession.result.conversationExchanges.count, 0)
        XCTAssertNil(scrubbedSession.result.conversationSummary)
        XCTAssertNil(scrubbedSession.result.taskAnalyses.first?.promptText)
        XCTAssertNil(scrubbedSession.rawAudioDebugManifestPath)

        let analysisIndexURL = exportDirectory.appendingPathComponent(LocalStorageManager.analysisIndexFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: analysisIndexURL.path))
        let aiIndexURL = exportDirectory.appendingPathComponent(LocalStorageManager.aiAnalysisIndexFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: aiIndexURL.path))
    }

    func test_removeTodaysJSONData_deletesTodaysGeneratedFilesAndRowsOnly() throws {
        let calendar = Calendar.current
        let referenceDate = Date()
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: referenceDate))

        storage.saveRecord(DailyHealthRecord(
            date: yesterday,
            experimentTag: "Old",
            wellnessDeltaScore: 1,
            confidenceLevel: "Low",
            insightText: "Old record"
        ))
        storage.saveRecord(DailyHealthRecord(
            date: referenceDate,
            experimentTag: "Today",
            wellnessDeltaScore: 2,
            confidenceLevel: "Low",
            insightText: "Today record"
        ))

        storage.saveVoiceSession(VoiceTrackingSession(
            date: yesterday,
            experimentTag: "Old",
            promptTag: "daily_voice_check_v1",
            result: VoiceTrackingResult(
                completedAt: yesterday,
                durationSeconds: 8,
                voiceScore: 70,
                averageVolumeDb: -26,
                volumeStdDevDb: 3,
                silenceRatio: 0.1,
                peakVolumeDb: -12
            )
        ))
        storage.saveVoiceSession(VoiceTrackingSession(
            date: referenceDate,
            experimentTag: "Today",
            promptTag: "daily_voice_check_v1",
            result: VoiceTrackingResult(
                completedAt: referenceDate,
                durationSeconds: 8,
                voiceScore: 80,
                averageVolumeDb: -24,
                volumeStdDevDb: 3,
                silenceRatio: 0.1,
                peakVolumeDb: -11
            )
        ))

        storage.saveEyeFocusSummary(EyeFocusAISummary(
            resultCompletedAt: yesterday,
            generatedAt: yesterday,
            model: "gpt-5-mini",
            sourceLogFileName: "old_gaze.json",
            overallSummary: "Old summary",
            sections: []
        ))
        storage.saveEyeFocusSummary(EyeFocusAISummary(
            resultCompletedAt: referenceDate,
            generatedAt: referenceDate,
            model: "gpt-5-mini",
            sourceLogFileName: "today_gaze.json",
            overallSummary: "Today summary",
            sections: []
        ))

        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let oldExportURL = exportDirectory.appendingPathComponent("voice_tracking_old.json")
        let todayExportURL = exportDirectory.appendingPathComponent("voice_tracking_today.json")
        let oldAIURL = exportDirectory.appendingPathComponent("voice_ai_old.json")
        let todayAIURL = exportDirectory.appendingPathComponent("voice_ai_today.json")
        try Data("{}".utf8).write(to: oldExportURL)
        try Data("{}".utf8).write(to: todayExportURL)
        try Data("{}".utf8).write(to: oldAIURL)
        try Data("{}".utf8).write(to: todayAIURL)
        try setModificationDate(yesterday, for: oldExportURL)
        try setModificationDate(referenceDate, for: todayExportURL)
        try setModificationDate(yesterday, for: oldAIURL)
        try setModificationDate(referenceDate, for: todayAIURL)

        let oldExportId = UUID()
        let todayExportId = UUID()
        try writeJSONLLines(
            [
                AnalysisExportIndexEntry(
                    exportId: oldExportId,
                    createdAt: yesterday,
                    source: .voiceTracking,
                    fileName: oldExportURL.lastPathComponent,
                    availableModalities: ["voice_acoustic_features"]
                ),
                AnalysisExportIndexEntry(
                    exportId: todayExportId,
                    createdAt: referenceDate,
                    source: .voiceTracking,
                    fileName: todayExportURL.lastPathComponent,
                    availableModalities: ["voice_acoustic_features"]
                )
            ],
            to: exportDirectory.appendingPathComponent(LocalStorageManager.analysisIndexFileName)
        )
        try writeJSONLLines(
            [
                VoiceAIAnalysisIndexEntry(
                    analysisId: UUID(),
                    exportId: oldExportId,
                    createdAt: yesterday,
                    fileName: oldAIURL.lastPathComponent,
                    exportFileName: oldExportURL.lastPathComponent,
                    source: "openai"
                ),
                VoiceAIAnalysisIndexEntry(
                    analysisId: UUID(),
                    exportId: todayExportId,
                    createdAt: referenceDate,
                    fileName: todayAIURL.lastPathComponent,
                    exportFileName: todayExportURL.lastPathComponent,
                    source: "openai"
                )
            ],
            to: exportDirectory.appendingPathComponent(LocalStorageManager.aiAnalysisIndexFileName)
        )

        let gazeDirectory = documentsDirectory.appendingPathComponent("GazeLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: gazeDirectory, withIntermediateDirectories: true)
        let oldGazeURL = gazeDirectory.appendingPathComponent("gaze_old.json")
        let todayGazeURL = gazeDirectory.appendingPathComponent("gaze_today.json")
        try Data("{}".utf8).write(to: oldGazeURL)
        try Data("{}".utf8).write(to: todayGazeURL)
        try setModificationDate(yesterday, for: oldGazeURL)
        try setModificationDate(referenceDate, for: todayGazeURL)

        let cleanup = storage.removeTodaysJSONData(referenceDate: referenceDate)

        XCTAssertEqual(cleanup.dailyRecordsRemoved, 1)
        XCTAssertEqual(cleanup.voiceSessionsRemoved, 1)
        XCTAssertEqual(cleanup.eyeFocusSummariesRemoved, 1)
        XCTAssertEqual(cleanup.analysisJSONFilesDeleted, 2)
        XCTAssertEqual(cleanup.gazeLogFilesDeleted, 1)
        XCTAssertEqual(cleanup.analysisIndexEntriesRemoved, 1)
        XCTAssertEqual(cleanup.aiAnalysisIndexEntriesRemoved, 1)

        XCTAssertEqual(storage.loadAllRecords().map(\.experimentTag), ["Old"])
        XCTAssertEqual(storage.loadVoiceSessions().map(\.experimentTag), ["Old"])
        XCTAssertEqual(storage.loadEyeFocusSummaries().map(\.overallSummary), ["Old summary"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldExportURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: todayExportURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldAIURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: todayAIURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldGazeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: todayGazeURL.path))

        let analysisIndex = try String(contentsOf: exportDirectory.appendingPathComponent(LocalStorageManager.analysisIndexFileName))
        XCTAssertTrue(analysisIndex.contains(oldExportURL.lastPathComponent))
        XCTAssertFalse(analysisIndex.contains(todayExportURL.lastPathComponent))
        let aiIndex = try String(contentsOf: exportDirectory.appendingPathComponent(LocalStorageManager.aiAnalysisIndexFileName))
        XCTAssertTrue(aiIndex.contains(oldAIURL.lastPathComponent))
        XCTAssertFalse(aiIndex.contains(todayAIURL.lastPathComponent))
    }

    func test_writeVoiceAnalysisExport_marksDebugRawAudioPrivacyWhenManifestAttached() throws {
        let result = VoiceTrackingResult(
            completedAt: Date(),
            durationSeconds: 8,
            voiceScore: 78,
            averageVolumeDb: -25,
            volumeStdDevDb: 3,
            silenceRatio: 0.1,
            peakVolumeDb: -11
        )
        let session = VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: "Morning",
            promptTag: "daily_voice_check_v1",
            rawAudioRetentionPolicy: "debug_opt_in_raw_wav_local_and_ai_upload",
            rawAudioDebugManifestPath: "/tmp/vitalscore-debug-manifest.json",
            result: result
        )

        let fileURL = try XCTUnwrap(storage.writeVoiceAnalysisExport(session: session, dailyRecord: nil))
        let data = try Data(contentsOf: fileURL)
        let export = try JSONDecoder.iso8601.decode(MultimodalAnalysisExport.self, from: data)

        XCTAssertTrue(export.privacy.rawAudioStored)
        XCTAssertTrue(export.availableModalities.contains("debug_opt_in_voice_wav_audio"))
        XCTAssertTrue(export.privacy.warning.contains("raw WAV clips"))
    }

    private func makeLiveVoiceSession(rawAudioDebugManifestPath: String? = nil) -> VoiceTrackingSession {
        let startedAt = Date().addingTimeInterval(-60)
        let result = VoiceTrackingResult(
            completedAt: startedAt.addingTimeInterval(30),
            durationSeconds: 30,
            voiceScore: 82,
            averageVolumeDb: -24,
            volumeStdDevDb: 3.1,
            silenceRatio: 0.12,
            peakVolumeDb: -10,
            taskAnalyses: [
                VoiceTaskAnalysis(
                    taskType: .guidedConversation,
                    promptId: "ai_free_talk_turn_1",
                    promptText: "How has your energy felt today?",
                    targetDurationSeconds: 140,
                    durationSeconds: 30,
                    sampleCount: 120,
                    averageVolumeDb: -24,
                    volumeStdDevDb: 3.1,
                    peakVolumeDb: -10,
                    silenceRatio: 0.12,
                    clippingPercentage: 0,
                    zeroCrossingRate: 0.11,
                    voicedFrameRatio: 0.88,
                    snrDb: nil,
                    eGeMAPS: nil,
                    qualityScore: 0.9,
                    qualityIssues: [],
                    usable: true,
                    featureVersion: VoiceTrackingManager.featureExtractorVersion
                )
            ],
            conversationExchanges: [
                VoiceConversationExchange(
                    turnIndex: 1,
                    aiPrompt: "How has your energy felt today?",
                    userTranscript: "I feel steady but a little tired after lunch.",
                    userResponseStartedAt: startedAt,
                    userResponseEndedAt: startedAt.addingTimeInterval(8),
                    responseDurationSeconds: 8,
                    source: "ios_speech_recognition"
                )
            ],
            conversationSummary: VoiceConversationSummary(
                questionCount: 1,
                summary: "Summary saved: sleep or rest and steadiness stood out across your answers.",
                source: "openai"
            )
        )
        return VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: "Morning",
            promptTag: "ai_voice_conversation_v1",
            rawAudioRetentionPolicy: rawAudioDebugManifestPath == nil
                ? "features_only_no_raw_audio"
                : "debug_opt_in_raw_wav_local_and_ai_upload",
            rawAudioDebugManifestPath: rawAudioDebugManifestPath,
            result: result
        )
    }

    func test_debugAudioSamples_loadsOptInWavPayload() throws {
        let directory = exportDirectory.appendingPathComponent("DebugWAV", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioData = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00])
        let audioURL = directory.appendingPathComponent("sample.wav")
        try audioData.write(to: audioURL)

        let sampleId = UUID()
        let manifest = VoiceRawAudioDebugManifest(
            schemaVersion: VoiceRawAudioDebugManifest.schemaVersion,
            sessionId: UUID(),
            createdAt: Date(),
            warning: "test",
            samples: [
                VoiceRawAudioDebugSample(
                    id: sampleId,
                    taskType: .fixedReading,
                    promptId: "fixed_reading",
                    promptText: "Read this sentence.",
                    turnIndex: nil,
                    fileName: audioURL.lastPathComponent,
                    startedAt: Date(),
                    endedAt: Date(),
                    durationSeconds: 4,
                    sampleRate: 44_100,
                    channels: 1,
                    status: "completed"
                )
            ]
        )
        let manifestURL = directory.appendingPathComponent(VoiceRawAudioDebugExportSettings.manifestFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL)

        UserDefaults.standard.set(true, forKey: VoiceRawAudioDebugExportSettings.userDefaultsKey)
        UserDefaults.standard.set(true, forKey: VoiceRawAudioDebugExportSettings.aiUploadUserDefaultsKey)

        let result = VoiceTrackingResult(
            completedAt: Date(),
            durationSeconds: 4,
            voiceScore: 80,
            averageVolumeDb: -25,
            volumeStdDevDb: 3,
            silenceRatio: 0,
            peakVolumeDb: -12
        )
        let session = VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: "Morning",
            promptTag: "daily_voice_check_v1",
            rawAudioRetentionPolicy: "debug_opt_in_raw_wav_local_and_ai_upload",
            rawAudioDebugManifestPath: manifestURL.path,
            result: result
        )

        let samples = AIConversationClient.debugAudioSamples(for: session)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.id, sampleId)
        XCTAssertEqual(samples.first?.format, "wav")
        XCTAssertEqual(samples.first?.byteCount, audioData.count)
        XCTAssertEqual(samples.first?.base64Audio, audioData.base64EncodedString())
    }

    func test_writeVoiceAIAnalysisResult_createsResultFileAndIndex() throws {
        let response = VoiceAIAnalysisResponse(
            id: UUID(),
            exportId: UUID(),
            createdAt: Date(),
            source: "openai",
            aiVoiceScore: 84,
            aiScoreConfidence: "Medium",
            aiScoreRationale: "Saved voice metrics were usable for scoring.",
            summary: "The check had usable quality and enough speech for wellness reflection.",
            dataQuality: ["Usable task quality."],
            notableSignals: ["Voice score was available."],
            longitudinalContext: ["Baseline is still building."],
            missingData: ["No eye-focus data in this export."],
            recommendedNextSteps: ["Repeat the same fixed prompt over several days."],
            safetyNote: "Wellness-only, not medical advice."
        )
        let exportURL = exportDirectory
            .appendingPathComponent("20260524T000000Z_voice_tracking_export.json")

        let fileURL = try XCTUnwrap(storage.writeVoiceAIAnalysisResult(response, exportFileURL: exportURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let stored = try JSONDecoder.iso8601.decode(VoiceAIAnalysisStoredResult.self, from: data)
        XCTAssertEqual(stored.schemaVersion, VoiceAIAnalysisStoredResult.currentSchemaVersion)
        XCTAssertEqual(stored.exportFileName, exportURL.lastPathComponent)
        XCTAssertEqual(stored.analysis.id, response.id)

        let indexURL = exportDirectory.appendingPathComponent(LocalStorageManager.aiAnalysisIndexFileName)
        let indexText = try String(contentsOf: indexURL)
        XCTAssertTrue(indexText.contains(fileURL.lastPathComponent))
        XCTAssertTrue(indexText.contains(exportURL.lastPathComponent))
    }

    func test_saveEyeFocusSummary_persistsLatestSummary() {
        let older = EyeFocusAISummary(
            resultCompletedAt: Date().addingTimeInterval(-3600),
            generatedAt: Date().addingTimeInterval(-3600),
            model: "gpt-5-mini",
            sourceLogFileName: "old.json",
            overallSummary: "Older summary",
            sections: [
                EyeFocusAISummarySection(title: "Reaction", summary: "Older reaction summary")
            ]
        )
        let newer = EyeFocusAISummary(
            resultCompletedAt: Date(),
            generatedAt: Date(),
            model: "gpt-5-mini",
            sourceLogFileName: "new.json",
            overallSummary: "Newer summary",
            sections: [
                EyeFocusAISummarySection(title: "Gaze accuracy", summary: "Newer gaze summary")
            ]
        )

        storage.saveEyeFocusSummary(older)
        storage.saveEyeFocusSummary(newer)

        XCTAssertEqual(storage.loadEyeFocusSummaries().count, 2)
        XCTAssertEqual(storage.latestEyeFocusSummary()?.overallSummary, "Newer summary")
        XCTAssertEqual(storage.latestEyeFocusSummary()?.sections.first?.title, "Gaze accuracy")
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func writeJSONLLines<T: Encodable>(_ entries: [T], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = try entries.map { entry -> String in
            let data = try encoder.encode(entry)
            return try XCTUnwrap(String(data: data, encoding: .utf8))
        }.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
