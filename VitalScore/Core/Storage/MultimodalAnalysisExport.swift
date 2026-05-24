import Foundation

enum AnalysisExportSource: String, Codable, Equatable {
    case eyeFocusTest = "eye_focus_test"
    case voiceTracking = "voice_tracking"
}

struct MultimodalAnalysisExport: Codable, Identifiable {
    static let schemaVersion = "vitalscore_multimodal_analysis_export_v1"

    let id: UUID
    let schemaVersion: String
    let createdAt: Date
    let source: AnalysisExportSource
    let llmInputGuidance: String
    let availableModalities: [String]
    let missingModalities: [String]
    let privacy: AnalysisExportPrivacy
    let textContext: [String]
    let featureVector: [String: Double]
    let questionProtocol: VoiceAIQuestionProtocolContext?
    let voiceFeatureValidation: [VoiceFeatureValidation]?
    let dailyHealthRecord: DailyHealthRecord?
    let eyeFocusResult: EyeFocusTestResult?
    let voiceSession: VoiceTrackingSession?

    static func eyeFocus(result: EyeFocusTestResult, dailyRecord: DailyHealthRecord?) -> MultimodalAnalysisExport {
        MultimodalAnalysisExport(
            id: UUID(),
            schemaVersion: schemaVersion,
            createdAt: Date(),
            source: .eyeFocusTest,
            llmInputGuidance: guidance,
            availableModalities: availableModalities(dailyRecord: dailyRecord, eyeFocusResult: result, voiceSession: nil),
            missingModalities: missingModalities(dailyRecord: dailyRecord, eyeFocusResult: result, voiceSession: nil),
            privacy: .defaultWellnessFeaturesOnly,
            textContext: textContext(dailyRecord: dailyRecord, eyeFocusResult: result, voiceSession: nil),
            featureVector: featureVector(dailyRecord: dailyRecord, eyeFocusResult: result, voiceSession: nil),
            questionProtocol: nil,
            voiceFeatureValidation: nil,
            dailyHealthRecord: dailyRecord,
            eyeFocusResult: result,
            voiceSession: nil
        )
    }

    static func voice(session: VoiceTrackingSession, dailyRecord: DailyHealthRecord?) -> MultimodalAnalysisExport {
        MultimodalAnalysisExport(
            id: UUID(),
            schemaVersion: schemaVersion,
            createdAt: Date(),
            source: .voiceTracking,
            llmInputGuidance: guidance,
            availableModalities: availableModalities(dailyRecord: dailyRecord, eyeFocusResult: nil, voiceSession: session),
            missingModalities: missingModalities(dailyRecord: dailyRecord, eyeFocusResult: nil, voiceSession: session),
            privacy: .voice(session: session),
            textContext: textContext(dailyRecord: dailyRecord, eyeFocusResult: nil, voiceSession: session),
            featureVector: featureVector(dailyRecord: dailyRecord, eyeFocusResult: nil, voiceSession: session),
            questionProtocol: VoiceAIConversationBuilder.questionProtocolContext(for: session),
            voiceFeatureValidation: VoiceFeatureValidationCatalog.all,
            dailyHealthRecord: dailyRecord,
            eyeFocusResult: nil,
            voiceSession: session
        )
    }

    private static let guidance = """
    Use this file as structured wellness context for longitudinal, non-diagnostic analysis. The payload contains \
    health summaries, eye-focus metrics, voice acoustic features, prompt text, scores, and quality metadata. Raw \
    audio is excluded unless an explicit debug upload opt-in attached WAV clips to the AI request. Raw camera frames \
    are intentionally not stored. Treat missing modalities as unavailable rather than zero.
    """

    private static func availableModalities(
        dailyRecord: DailyHealthRecord?,
        eyeFocusResult: EyeFocusTestResult?,
        voiceSession: VoiceTrackingSession?
    ) -> [String] {
        var modalities: [String] = []
        if dailyRecord != nil { modalities.append("daily_health_summary") }
        if eyeFocusResult != nil { modalities.append("eye_focus_reaction_and_gaze") }
        if voiceSession != nil { modalities.append("voice_acoustic_features") }
        if voiceSession?.rawAudioDebugManifestPath != nil {
            modalities.append("debug_opt_in_voice_wav_audio")
        }
        if voiceSession?.result.conversationExchanges.isEmpty == false {
            modalities.append("voice_conversation_transcript")
        }
        if voiceSession?.result.conversationSummary != nil {
            modalities.append("voice_conversation_summary")
        }
        return modalities
    }

    private static func missingModalities(
        dailyRecord: DailyHealthRecord?,
        eyeFocusResult: EyeFocusTestResult?,
        voiceSession: VoiceTrackingSession?
    ) -> [String] {
        var missing: [String] = []
        if dailyRecord == nil { missing.append("daily_health_summary") }
        if eyeFocusResult == nil { missing.append("eye_focus_reaction_and_gaze") }
        if voiceSession == nil { missing.append("voice_acoustic_features") }
        return missing
    }

    private static func textContext(
        dailyRecord: DailyHealthRecord?,
        eyeFocusResult: EyeFocusTestResult?,
        voiceSession: VoiceTrackingSession?
    ) -> [String] {
        var context: [String] = []
        if let dailyRecord {
            context.append("Experiment tag: \(dailyRecord.experimentTag)")
            if !dailyRecord.insightText.isEmpty {
                context.append("Latest wellness insight: \(dailyRecord.insightText)")
            }
            context.append("Wellness score: \(dailyRecord.wellnessDeltaScore), confidence: \(dailyRecord.confidenceLevel)")
        }
        if let eyeFocusResult {
            context.append("Eye-focus score: \(Int(eyeFocusResult.eyeFocusScore)); average reaction \(Int(eyeFocusResult.averageReactionMs)) ms.")
        }
        if let voiceSession {
            let questionProtocol = VoiceAIConversationBuilder.questionProtocolContext(for: voiceSession)
            context.append("Voice prompt tag: \(voiceSession.promptTag); score: \(Int(voiceSession.result.voiceScore)); confidence: \(voiceSession.result.voiceConfidence).")
            context.append("Voice question protocol: \(questionProtocol.protocolId); mode: \(questionProtocol.mode); version: \(questionProtocol.protocolVersion).")
            for question in questionProtocol.questionSet {
                context.append("\(question.title) background: \(question.measurementPurpose)")
            }
            context.append(contentsOf: voiceSession.result.topDrivers)
            for task in voiceSession.result.taskAnalyses {
                if let promptText = task.promptText, !promptText.isEmpty {
                    context.append("\(task.taskType.displayName) prompt: \(promptText)")
                }
            }
            for exchange in voiceSession.result.conversationExchanges {
                context.append("AI conversation turn \(exchange.turnIndex) assistant: \(exchange.aiPrompt)")
                context.append("AI conversation turn \(exchange.turnIndex) user transcript: \(exchange.userTranscript)")
            }
            if let conversationSummary = voiceSession.result.conversationSummary {
                context.append("AI conversation short summary: \(conversationSummary.summary)")
            }
        }
        return context
    }

    private static func featureVector(
        dailyRecord: DailyHealthRecord?,
        eyeFocusResult: EyeFocusTestResult?,
        voiceSession: VoiceTrackingSession?
    ) -> [String: Double] {
        var features: [String: Double] = [:]

        if let dailyRecord {
            add(&features, "health.sleep_hours", dailyRecord.sleepHours)
            add(&features, "health.resting_heart_rate_bpm", dailyRecord.restingHeartRateBPM)
            add(&features, "health.hrv_ms", dailyRecord.hrvMs)
            add(&features, "health.step_count", dailyRecord.stepCount)
            add(&features, "health.active_energy_kcal", dailyRecord.activeEnergyKcal)
            add(&features, "wellness.delta_score", Double(dailyRecord.wellnessDeltaScore))
            add(&features, "self_report.energy", dailyRecord.selfReportedEnergy)
            add(&features, "self_report.stress", dailyRecord.selfReportedStress)
            add(&features, "self_report.sleep_quality", dailyRecord.selfReportedSleepQuality)
        }

        if let eyeFocusResult {
            add(&features, "eye.eye_focus_score", eyeFocusResult.eyeFocusScore)
            add(&features, "eye.reaction_score", eyeFocusResult.reactionScore)
            add(&features, "eye.average_reaction_ms", eyeFocusResult.averageReactionMs)
            add(&features, "eye.reaction_std_dev_ms", eyeFocusResult.reactionStdDevMs)
            add(&features, "eye.missed_targets", eyeFocusResult.missedTargets)
            add(&features, "eye.false_taps", eyeFocusResult.falseTaps)
            add(&features, "eye.gaze_accuracy_px", eyeFocusResult.gazeMetrics?.gazeAccuracyPx)
            add(&features, "eye.gaze_stability_px", eyeFocusResult.gazeMetrics?.gazeStabilityPx)
            add(&features, "eye.gaze_fixation_ms", eyeFocusResult.gazeMetrics?.fixationDurationMs)
            add(&features, "eye.gaze_blink_rate_per_min", eyeFocusResult.gazeMetrics?.blinkRatePerMin)
            add(&features, "eye.gaze_tracking_loss_pct", eyeFocusResult.gazeMetrics?.trackingLossPct)
            add(&features, "eye.gaze_score", eyeFocusResult.gazeMetrics?.gazeScore)
        }

        if let voiceSession {
            let result = voiceSession.result
            add(&features, "voice.score", result.voiceScore)
            add(&features, "voice.duration_seconds", result.durationSeconds)
            add(&features, "voice.average_volume_db", result.averageVolumeDb)
            add(&features, "voice.volume_std_dev_db", result.volumeStdDevDb)
            add(&features, "voice.silence_ratio", result.silenceRatio)
            add(&features, "voice.peak_volume_db", result.peakVolumeDb)
            add(&features, "voice.overall_quality_score", result.overallQualityScore)
            add(&features, "voice.baseline_sessions_used", result.baselineSessionsUsed)
            add(&features, "voice.ai_conversation_turn_count", result.conversationExchanges.count)
            add(&features, "voice.ai_conversation_summary_word_count", result.conversationSummary?.summary.wordCount)
            addVoiceFeatures(&features, prefix: "voice.egemaps", features: result.eGeMAPS)

            for task in result.taskAnalyses {
                let prefix = "voice.task.\(task.promptId.sanitizedFeatureKey)"
                add(&features, "\(prefix).target_duration_seconds", task.targetDurationSeconds)
                add(&features, "\(prefix).duration_seconds", task.durationSeconds)
                add(&features, "\(prefix).sample_count", task.sampleCount)
                add(&features, "\(prefix).average_volume_db", task.averageVolumeDb)
                add(&features, "\(prefix).volume_std_dev_db", task.volumeStdDevDb)
                add(&features, "\(prefix).peak_volume_db", task.peakVolumeDb)
                add(&features, "\(prefix).silence_ratio", task.silenceRatio)
                add(&features, "\(prefix).clipping_percentage", task.clippingPercentage)
                add(&features, "\(prefix).zero_crossing_rate", task.zeroCrossingRate)
                add(&features, "\(prefix).voiced_frame_ratio", task.voicedFrameRatio)
                add(&features, "\(prefix).snr_db", task.snrDb)
                addVoiceFeatures(&features, prefix: "\(prefix).egemaps", features: task.eGeMAPS)
            }

            for exchange in result.conversationExchanges {
                let prefix = "voice.ai_conversation.turn_\(exchange.turnIndex)"
                add(&features, "\(prefix).duration_seconds", exchange.responseDurationSeconds)
                add(&features, "\(prefix).transcript_character_count", exchange.userTranscript.count)
                add(&features, "\(prefix).transcript_word_count", exchange.userTranscript.wordCount)
            }
        }

        return features
    }

    private static func addVoiceFeatures(
        _ features: inout [String: Double],
        prefix: String,
        features voiceFeatures: VoiceEGeMAPSFeatureSet?
    ) {
        guard let voiceFeatures else { return }
        add(&features, "\(prefix).loudness_mean_db", voiceFeatures.loudnessMeanDb)
        add(&features, "\(prefix).loudness_std_dev_db", voiceFeatures.loudnessStdDevDb)
        add(&features, "\(prefix).f0_mean_hz", voiceFeatures.f0MeanHz)
        add(&features, "\(prefix).f0_std_dev_hz", voiceFeatures.f0StdDevHz)
        add(&features, "\(prefix).jitter_local_percent", voiceFeatures.jitterLocalPercent)
        add(&features, "\(prefix).shimmer_local_db", voiceFeatures.shimmerLocalDb)
        add(&features, "\(prefix).hnr_mean_db", voiceFeatures.hnrMeanDb)
        add(&features, "\(prefix).alpha_ratio_db", voiceFeatures.alphaRatioDb)
        add(&features, "\(prefix).hammarberg_index_db", voiceFeatures.hammarbergIndexDb)
        add(&features, "\(prefix).spectral_flux", voiceFeatures.spectralFlux)
        add(&features, "\(prefix).slope_v0", voiceFeatures.slopeV0)
        add(&features, "\(prefix).slope_uv0", voiceFeatures.slopeUV0)
        add(&features, "\(prefix).mfcc1_mean", voiceFeatures.mfcc1Mean)
        add(&features, "\(prefix).mfcc2_mean", voiceFeatures.mfcc2Mean)
        add(&features, "\(prefix).mfcc3_mean", voiceFeatures.mfcc3Mean)
        add(&features, "\(prefix).voiced_segments_per_second", voiceFeatures.voicedSegmentsPerSecond)
        add(&features, "\(prefix).mean_voiced_segment_length_seconds", voiceFeatures.meanVoicedSegmentLengthSeconds)
    }

    private static func add(_ features: inout [String: Double], _ key: String, _ value: Double?) {
        guard let value else { return }
        features[key] = value
    }

    private static func add(_ features: inout [String: Double], _ key: String, _ value: Int?) {
        guard let value else { return }
        features[key] = Double(value)
    }
}

struct AnalysisExportPrivacy: Codable {
    let rawAudioStored: Bool
    let rawCameraFramesStored: Bool
    let includesHealthKitSummary: Bool
    let intendedUse: String
    let warning: String

    static let defaultWellnessFeaturesOnly = AnalysisExportPrivacy(
        rawAudioStored: false,
        rawCameraFramesStored: false,
        includesHealthKitSummary: true,
        intendedUse: "Wellness trend analysis and longitudinal model input only.",
        warning: "Not for diagnosis, treatment, or disease prediction."
    )

    static func voice(session: VoiceTrackingSession) -> AnalysisExportPrivacy {
        let hasRawAudio = session.rawAudioRetentionPolicy != "features_only_no_raw_audio"
        let uploadsRawAudio = session.rawAudioDebugManifestPath != nil
        return AnalysisExportPrivacy(
            rawAudioStored: hasRawAudio,
            rawCameraFramesStored: false,
            includesHealthKitSummary: true,
            intendedUse: "Wellness trend analysis and longitudinal model input only.",
            warning: uploadsRawAudio
                ? "Debug opt-in enabled: raw WAV clips may be attached to the configured AI analysis request. Not for diagnosis, treatment, or disease prediction."
                : "Not for diagnosis, treatment, or disease prediction."
        )
    }
}

struct AnalysisExportIndexEntry: Codable {
    let exportId: UUID
    let createdAt: Date
    let source: AnalysisExportSource
    let fileName: String
    let availableModalities: [String]
}

private extension String {
    var wordCount: Int {
        split { $0.isWhitespace || $0.isNewline }.count
    }

    var sanitizedFeatureKey: String {
        map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        .reduce(into: "") { $0.append($1) }
    }
}
