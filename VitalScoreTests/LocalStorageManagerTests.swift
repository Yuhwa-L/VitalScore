import XCTest
@testable import VitalScore

final class LocalStorageManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var storage: LocalStorageManager!
    private var exportDirectory: URL!
    private let suite = "com.vitalscore.tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitalScoreExportTests-\(UUID().uuidString)", isDirectory: true)
        storage = LocalStorageManager(defaults: defaults, exportDirectory: exportDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: exportDirectory)
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
        let r2 = DailyHealthRecord(date: date, experimentTag: "B", wellnessDeltaScore: 2, confidenceLevel: "Low", insightText: "")
        storage.saveRecord(r1)
        storage.saveRecord(r2)
        let loaded = storage.loadAllRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.experimentTag, "B")
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

    func test_saveVoiceSession_persistsExperimentAndPromptTags() {
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
            experimentTag: "Morning Sunlight",
            promptTag: "daily_voice_check_v1",
            result: result
        )

        storage.saveVoiceSession(session)

        let loaded = storage.loadVoiceSessions()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.experimentTag, "Morning Sunlight")
        XCTAssertEqual(loaded.first?.promptTag, "daily_voice_check_v1")
        XCTAssertEqual(loaded.first?.result.voiceScore, 91)
        XCTAssertEqual(loaded.first?.result.conversationSummary?.questionCount, 4)
        XCTAssertEqual(loaded.first?.result.conversationSummary?.summary, "Summary saved: focus and routine stood out across your answers.")
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
        XCTAssertTrue(export.availableModalities.contains("voice_acoustic_features"))
        XCTAssertTrue(export.availableModalities.contains("voice_conversation_transcript"))
        XCTAssertTrue(export.availableModalities.contains("voice_conversation_summary"))
        XCTAssertEqual(export.voiceSession?.id, session.id)
        XCTAssertEqual(export.voiceSession?.result.conversationExchanges.first?.userTranscript, "I feel steady but a little tired after lunch.")
        XCTAssertEqual(export.voiceSession?.result.conversationSummary?.questionCount, 1)
        XCTAssertEqual(export.questionProtocol?.mode, "advanced_freestyle_talk")
        XCTAssertTrue(export.questionProtocol?.questionSet.contains { $0.taskType == VoiceTaskType.guidedConversation.rawValue } == true)
        XCTAssertTrue(export.textContext.contains { $0.contains("Voice question protocol") })
        XCTAssertTrue(export.textContext.contains { $0.contains("AI conversation short summary") })
        XCTAssertEqual(export.voiceFeatureValidation?.first(where: { $0.key == "jitterLocalPercent" })?.status, .unsupported)
        XCTAssertEqual(export.featureVector["voice.score"], 82)
        XCTAssertEqual(export.featureVector["voice.ai_conversation_turn_count"], 1)
        XCTAssertEqual(export.featureVector["voice.ai_conversation_summary_word_count"], 12)
        XCTAssertEqual(export.featureVector["voice.ai_conversation.turn_1.transcript_word_count"], 9)
        XCTAssertEqual(export.featureVector["health.sleep_hours"], 7.2)

        let indexURL = storage.analysisExportDirectory.appendingPathComponent(LocalStorageManager.analysisIndexFileName)
        let indexText = try String(contentsOf: indexURL)
        XCTAssertTrue(indexText.contains(fileURL.lastPathComponent))
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
            summary: "The check had usable quality and enough speech for wellness reflection.",
            dataQuality: ["Usable task quality."],
            notableSignals: ["Voice score was available."],
            longitudinalContext: ["Baseline is still building."],
            missingData: ["No eye-focus data in this export."],
            recommendedNextSteps: ["Repeat the same fixed prompt over several days."],
            safetyNote: "Wellness-only, not medical advice."
        )
        let exportURL = storage.analysisExportDirectory
            .appendingPathComponent("20260524T000000Z_voice_tracking_export.json")

        let fileURL = try XCTUnwrap(storage.writeVoiceAIAnalysisResult(response, exportFileURL: exportURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        let stored = try JSONDecoder.iso8601.decode(VoiceAIAnalysisStoredResult.self, from: data)
        XCTAssertEqual(stored.schemaVersion, VoiceAIAnalysisStoredResult.currentSchemaVersion)
        XCTAssertEqual(stored.exportFileName, exportURL.lastPathComponent)
        XCTAssertEqual(stored.analysis.id, response.id)

        let indexURL = storage.analysisExportDirectory.appendingPathComponent(LocalStorageManager.aiAnalysisIndexFileName)
        let indexText = try String(contentsOf: indexURL)
        XCTAssertTrue(indexText.contains(fileURL.lastPathComponent))
        XCTAssertTrue(indexText.contains(exportURL.lastPathComponent))
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
}
