import Foundation

struct VoiceAIConversationRequestPayload: Codable {
    let provider: String
    let model: String
    let systemInstruction: String
    let context: VoiceAIConversationContext
}

struct VoiceAIConversationContext: Codable {
    let generatedAt: Date
    let experimentTag: String
    let recentHistory: [VoiceAIConversationSessionSummary]
    let missingInputs: [String]
    let requiredAcousticTasks: [String]
    let desiredConversationTurns: Int
    let guardrails: [String]
}

struct VoiceAIConversationSessionSummary: Codable, Identifiable {
    let id: UUID
    let date: Date
    let voiceScore: Double
    let voiceConfidence: String
    let usable: Bool
    let baselineSessionsUsed: Int
    let topDrivers: [String]
}

struct VoiceAIConversationPlan: Codable, Equatable {
    let planId: String
    let promptTag: String
    let openingMessage: String
    let conversationTurns: [VoiceAIConversationTurn]
    let safetyNote: String
    let source: String
}

struct VoiceAIConversationTurn: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let prompt: String
    let targetDurationSeconds: TimeInterval
}

struct VoiceAIChatMessage: Codable, Equatable {
    let role: String
    let text: String
}

struct VoiceAIChatTurnRequestPayload: Codable {
    let provider: String
    let model: String
    let systemInstruction: String
    let context: VoiceAIConversationContext
    let history: [VoiceAIChatMessage]
    let previousAssistantReplies: [String]
    let previousUserTranscripts: [String]
    let latestUserTranscript: String
    let turnIndex: Int
    let maxTurns: Int
}

struct VoiceAIChatTurnResponse: Codable, Equatable {
    let reply: String
    let shouldContinue: Bool
    let source: String
}

struct VoiceAIQuestionProtocolContext: Codable, Equatable {
    let protocolId: String
    let protocolVersion: String
    let mode: String
    let purpose: String
    let questionSet: [VoiceAIQuestionTaskContext]
    let scoringInterpretation: [String]
    let guardrails: [String]
}

struct VoiceAIQuestionTaskContext: Codable, Equatable, Identifiable {
    var id: String { promptId }

    let promptId: String
    let taskType: String
    let title: String
    let promptText: String
    let targetDurationSeconds: TimeInterval
    let minimumUsableDurationSeconds: TimeInterval
    let measurementPurpose: String
}

struct VoiceAIAnalysisRequestPayload: Codable {
    let provider: String
    let model: String
    let systemInstruction: String
    let exportFileName: String?
    let analysisExport: MultimodalAnalysisExport
    let questionBackground: VoiceAIQuestionProtocolContext
    let recentVoiceHistory: [VoiceAIConversationSessionSummary]
    let debugAudioSamples: [VoiceAIAudioSamplePayload]
}

struct VoiceAIAudioSamplePayload: Codable, Equatable, Identifiable {
    let id: UUID
    let taskType: VoiceTaskType
    let promptId: String
    let promptText: String
    let turnIndex: Int?
    let fileName: String
    let durationSeconds: TimeInterval?
    let sampleRate: Double
    let channels: Int
    let format: String
    let byteCount: Int
    let base64Audio: String
}

struct VoiceAIAnalysisResponse: Codable, Equatable, Identifiable {
    let id: UUID
    let exportId: UUID
    let createdAt: Date
    let source: String
    let summary: String
    let dataQuality: [String]
    let notableSignals: [String]
    let longitudinalContext: [String]
    let missingData: [String]
    let recommendedNextSteps: [String]
    let safetyNote: String
}

struct VoiceAIAnalysisStoredResult: Codable, Equatable {
    static let currentSchemaVersion = "vitalscore_voice_ai_analysis_result_v1"

    let schemaVersion: String
    let storedAt: Date
    let exportFileName: String
    let analysis: VoiceAIAnalysisResponse

    init(
        schemaVersion: String = currentSchemaVersion,
        storedAt: Date = Date(),
        exportFileName: String,
        analysis: VoiceAIAnalysisResponse
    ) {
        self.schemaVersion = schemaVersion
        self.storedAt = storedAt
        self.exportFileName = exportFileName
        self.analysis = analysis
    }
}

struct VoiceAIAnalysisIndexEntry: Codable {
    let analysisId: UUID
    let exportId: UUID
    let createdAt: Date
    let fileName: String
    let exportFileName: String
    let source: String
}

enum VoiceAIConversationBuilder {
    static let advancedConversationQuestionCount = 4
    static let fixedPromptTag = "fixed_voice_check_v1"
    static let fixedPromptVersion = "fixed_voice_check_v1"
    static let promptTag = "ai_voice_conversation_v1"
    static let promptVersion = "ai_voice_conversation_v1"
    static let fallbackFreeTalkPrompt = "Hi, I am here with you. How are your energy and focus feeling right now?"
    static let systemInstruction = """
    You create the first spoken line for VitalScore's advanced AI voice conversation. This is a live check-in, \
    not a fixed acoustic test and not post-analysis. Start naturally with one short, friendly question about how \
    the user feels right now: energy, focus, stress, sleep, workload, environment, or routine. Avoid diagnosis, \
    treatment, disease prediction, and causal claims. Keep it easy to answer aloud in a few seconds.
    """
    static let chatTurnSystemInstruction = """
    You are the speaking AI guide in VitalScore's advanced voice talk. Respond like a concise, warm conversation \
    partner. Use a concrete detail from the user's latest transcribed answer and prior turns. Acknowledge briefly, \
    then ask one simple personalized follow-up when another turn remains. Do not repeat any previous assistant \
    question or generic fallback wording. When this is the final turn, return one short summary of the user's \
    answers and do not ask another question. Avoid scripted survey wording, diagnosis, treatment advice, disease \
    prediction, and causal claims. Keep each spoken reply under 18 words when possible.
    """
    static let analysisSystemInstruction = """
    You analyze completed VitalScore voice-check exports for wellness trend reflection. Use only the supplied \
    structured data, task/question background, transcripts, and recent history. Explain task quality, missing data, \
    baseline readiness, and notable acoustic or transcript signals without diagnosing, treating, predicting disease, \
    or making causal health claims. Keep the top summary short. Prefer validated or stable proxy acoustic fields; \
    label uncertainty clearly.
    """

    static func makeContext(
        experimentTag: String,
        history: [VoiceTrackingSession],
        generatedAt: Date = Date()
    ) -> VoiceAIConversationContext {
        let sorted = history.sorted { $0.date < $1.date }
        let recent = recentSessionSummaries(from: sorted, limit: 6)

        return VoiceAIConversationContext(
            generatedAt: generatedAt,
            experimentTag: experimentTag,
            recentHistory: recent,
            missingInputs: missingInputs(from: sorted),
            requiredAcousticTasks: [
                "advanced AI voice talk only",
                "no fixed ahh, counting, or reading prompts",
                "short natural user replies with transcript and acoustic feature capture"
            ],
            desiredConversationTurns: advancedConversationQuestionCount,
            guardrails: [
                "Wellness reflection only",
                "No medical diagnosis",
                "No treatment advice",
                "No causal claims",
                "Escalate urgent health concerns to a clinician"
            ]
        )
    }

    static func localPlan(for context: VoiceAIConversationContext) -> VoiceAIConversationPlan {
        return VoiceAIConversationPlan(
            planId: "local_voice_conversation_v1",
            promptTag: promptTag,
            openingMessage: "I will start a short, natural voice conversation.",
            conversationTurns: [
                VoiceAIConversationTurn(
                    id: "ai_free_talk_turn_1",
                    title: "AI Conversation",
                    prompt: fallbackFreeTalkPrompt,
                    targetDurationSeconds: 45
                )
            ],
            safetyNote: "This voice check supports wellness reflection only and is not a diagnosis.",
            source: "local_fallback"
        )
    }

    static func fixedPromptPlan() -> VoiceAIConversationPlan {
        VoiceAIConversationPlan(
            planId: fixedPromptTag,
            promptTag: fixedPromptTag,
            openingMessage: "Fixed voice check ready.",
            conversationTurns: [],
            safetyNote: "This voice check supports wellness reflection only and is not a diagnosis.",
            source: "fixed_prompt"
        )
    }

    static func localChatReply(
        turnIndex: Int,
        maxTurns: Int,
        latestUserTranscript: String,
        history: [VoiceAIChatMessage] = []
    ) -> VoiceAIChatTurnResponse {
        let cleanedTranscript = latestUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSpeech = !cleanedTranscript.isEmpty
        let shouldContinue = turnIndex < maxTurns
        let reply: String
        if shouldContinue {
            reply = hasSpeech
                ? personalizedFollowUp(
                    turnIndex: turnIndex,
                    transcript: cleanedTranscript,
                    previousAssistantReplies: previousAssistantReplies(from: history)
                )
                : clarificationFollowUp(
                    turnIndex: turnIndex,
                    previousAssistantReplies: previousAssistantReplies(from: history)
                )
        } else {
            reply = hasSpeech
                ? shortConversationSummary(
                    latestUserTranscript: cleanedTranscript,
                    history: history
                )
                : shortConversationSummary(
                    latestUserTranscript: nil,
                    history: history
                )
        }
        return VoiceAIChatTurnResponse(reply: reply, shouldContinue: shouldContinue, source: "local_personalized_fallback")
    }

    static func normalizedChatReply(
        _ response: VoiceAIChatTurnResponse,
        turnIndex: Int,
        maxTurns: Int,
        latestUserTranscript: String,
        history: [VoiceAIChatMessage]
    ) -> VoiceAIChatTurnResponse {
        let shouldContinue = turnIndex < maxTurns
        let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldContinue {
            let previousAssistant = previousAssistantReplies(from: history)
            let needsReplacement = reply.isEmpty
                || !reply.contains("?")
                || previousAssistant.contains { Self.normalizedPrompt($0) == Self.normalizedPrompt(reply) }

            if needsReplacement {
                return localChatReply(
                    turnIndex: turnIndex,
                    maxTurns: maxTurns,
                    latestUserTranscript: latestUserTranscript,
                    history: history
                )
            }
        }

        if !shouldContinue {
            if reply.isEmpty || reply.contains("?") {
                return localChatReply(
                    turnIndex: turnIndex,
                    maxTurns: maxTurns,
                    latestUserTranscript: latestUserTranscript,
                    history: history
                )
            }

            return VoiceAIChatTurnResponse(
                reply: conciseSentence(reply),
                shouldContinue: false,
                source: response.source.isEmpty ? "remote" : response.source
            )
        }

        return VoiceAIChatTurnResponse(
            reply: reply,
            shouldContinue: shouldContinue,
            source: response.source.isEmpty ? "remote" : response.source
        )
    }

    static func conversationSummary(
        from exchanges: [VoiceConversationExchange],
        closingReply: String,
        source: String
    ) -> VoiceConversationSummary {
        let cleanedClosing = conciseSentence(closingReply.trimmingCharacters(in: .whitespacesAndNewlines))
        let fallback = shortConversationSummary(transcripts: exchanges.map(\.userTranscript))
        let summary = cleanedClosing.isEmpty || cleanedClosing.contains("?") ? fallback : cleanedClosing

        return VoiceConversationSummary(
            questionCount: exchanges.count,
            summary: summary,
            source: source.isEmpty ? "local_summary" : source
        )
    }

    static func recentSessionSummaries(
        from sessions: [VoiceTrackingSession],
        limit: Int = 8
    ) -> [VoiceAIConversationSessionSummary] {
        Array(sessions.sorted { $0.date < $1.date }.suffix(limit)).map(makeSummary)
    }

    static func localAnalysisSummary(
        for session: VoiceTrackingSession,
        exportId: UUID,
        unavailableReason: String? = nil
    ) -> VoiceAIAnalysisResponse {
        let result = session.result
        let qualityPercent = Int((result.overallQualityScore * 100).rounded())
        let turns = result.conversationExchanges.count
        let transcriptText = turns == 0
            ? "No AI conversation transcript was captured."
            : "Conversation transcript captured across \(turns) turn\(turns == 1 ? "" : "s")."
        let baselineText: String
        if result.baselineSessionsUsed >= 7 {
            baselineText = "Personal voice baseline is active with \(result.baselineSessionsUsed) usable sessions."
        } else {
            baselineText = "Personal voice baseline is still building with \(result.baselineSessionsUsed) of 7 usable sessions."
        }

        var dataQuality = [
            "Capture quality was \(qualityPercent)% with \(result.usable ? "usable" : "limited") recording quality.",
            transcriptText
        ]
        if let unavailableReason, !unavailableReason.isEmpty {
            dataQuality.append("Remote AI analysis was not available: \(unavailableReason)")
        }
        dataQuality.append(contentsOf: result.qualityIssues.prefix(3))

        var notableSignals = Array(result.topDrivers.prefix(3))
        if notableSignals.isEmpty {
            notableSignals.append("Voice score was \(Int(result.voiceScore.rounded())) with \(result.voiceConfidence.lowercased()) confidence.")
        }
        if let features = result.eGeMAPS {
            notableSignals.append("Latest acoustic snapshot includes loudness \(Int(features.loudnessMeanDb.rounded())) dB and voiced segment rate \(String(format: "%.2f", features.voicedSegmentsPerSecond))/s.")
        }

        var missingData: [String] = []
        if result.eGeMAPS == nil {
            missingData.append("latest eGeMAPS feature snapshot")
        }
        if result.baselineSessionsUsed < 7 {
            missingData.append("full seven-session personal voice baseline")
        }
        if turns == 0 {
            missingData.append("advanced conversation transcript")
        }

        return VoiceAIAnalysisResponse(
            id: UUID(),
            exportId: exportId,
            createdAt: Date(),
            source: "local_summary_fallback",
            summary: "This voice check was saved. Voice score was \(Int(result.voiceScore.rounded())) with \(result.voiceConfidence.lowercased()) confidence, and capture quality was \(qualityPercent)%. \(baselineText)",
            dataQuality: dataQuality,
            notableSignals: notableSignals,
            longitudinalContext: [baselineText],
            missingData: missingData,
            recommendedNextSteps: [
                "Repeat the voice check under similar conditions to strengthen the personal baseline.",
                "Compare future sessions against the same time of day and environment when possible."
            ],
            safetyNote: "Wellness-only summary, not medical advice."
        )
    }

    static func questionProtocolContext(for session: VoiceTrackingSession) -> VoiceAIQuestionProtocolContext {
        let hasAdvancedConversation = session.promptTag == promptTag || !session.result.conversationExchanges.isEmpty
        let protocolId = hasAdvancedConversation ? "advanced_freestyle_voice_talk" : "fixed_prompt_voice_check"
        let mode = hasAdvancedConversation ? "advanced_freestyle_talk" : "fixed_prompt"

        return VoiceAIQuestionProtocolContext(
            protocolId: protocolId,
            protocolVersion: session.promptVersion,
            mode: mode,
            purpose: "Collect standardized voice acoustic features and optional free-speech transcript context for non-diagnostic wellness trend analysis.",
            questionSet: questionTaskContexts(for: session, hasAdvancedConversation: hasAdvancedConversation),
            scoringInterpretation: [
                "Voice score is a wellness trend score based on task quality and available personal baseline comparison; it is not a medical score.",
                "Higher scores indicate the captured session looked steadier or closer to available baseline expectations, not that the user is healthy.",
                "Missing modalities should be treated as unavailable, not as zero or negative evidence.",
                "Unsupported eGeMAPS placeholders are display-only and should not drive conclusions.",
                "Validated and stable proxy features can support longitudinal observations when task quality is usable."
            ],
            guardrails: [
                "No medical diagnosis",
                "No treatment advice",
                "No disease prediction",
                "No causal claims between voice features and health outcomes",
                "Escalate urgent health concerns to a clinician or emergency services"
            ]
        )
    }

    static func normalizedPlan(_ plan: VoiceAIConversationPlan, for context: VoiceAIConversationContext) -> VoiceAIConversationPlan {
        let fallback = localPlan(for: context)
        var turns = Array(plan.conversationTurns.prefix(1))
        if turns.isEmpty {
            turns = fallback.conversationTurns
        }

        let first = turns[0]
        let prompt = first.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        turns[0] = VoiceAIConversationTurn(
            id: first.id.isEmpty ? "ai_free_talk_turn_1" : first.id,
            title: first.title.isEmpty ? "AI Conversation" : first.title,
            prompt: prompt.isEmpty ? fallbackFreeTalkPrompt : prompt,
            targetDurationSeconds: 45
        )

        return VoiceAIConversationPlan(
            planId: plan.planId.isEmpty ? fallback.planId : plan.planId,
            promptTag: promptTag,
            openingMessage: "I will start a short, natural voice conversation.",
            conversationTurns: turns,
            safetyNote: plan.safetyNote.isEmpty ? fallback.safetyNote : plan.safetyNote,
            source: plan.source.isEmpty ? fallback.source : plan.source
        )
    }

    static func tasks(for plan: VoiceAIConversationPlan) -> [VoiceTaskDefinition] {
        if plan.planId == fixedPromptTag || plan.source == "fixed_prompt" {
            return fixedPromptTasks
        }

        var generatedTasks: [VoiceTaskDefinition] = []
        let turns = plan.conversationTurns.prefix(2)
        for (index, turn) in turns.enumerated() {
            generatedTasks.append(
                VoiceTaskDefinition(
                    type: .guidedConversation,
                    promptId: turn.id.isEmpty ? "ai_conversation_turn_\(index + 1)" : turn.id,
                    title: turn.title.isEmpty ? "Conversation \(index + 1)" : turn.title,
                    instruction: turn.prompt,
                    targetDurationSeconds: min(75, max(30, turn.targetDurationSeconds)),
                    minimumUsableDurationSeconds: min(30, max(8, turn.targetDurationSeconds * 0.25)),
                    allowsEarlyFinish: true
                )
            )
        }

        if generatedTasks.isEmpty {
            return [
                VoiceTaskDefinition(
                    type: .guidedConversation,
                    promptId: "ai_free_talk_turn_1",
                    title: "AI Conversation",
                    instruction: fallbackFreeTalkPrompt,
                    targetDurationSeconds: 45,
                    minimumUsableDurationSeconds: 8,
                    allowsEarlyFinish: true
                )
            ]
        }
        return generatedTasks
    }

    static let standardAcousticTasks: [VoiceTaskDefinition] = [
        VoiceTaskDefinition(
            type: .silenceCalibration,
            promptId: "vw_en_v2_silence",
            title: "Quiet Calibration",
            instruction: "Please stay quiet while we measure background noise.",
            targetDurationSeconds: 3,
            minimumUsableDurationSeconds: 2.5,
            allowsEarlyFinish: false
        ),
        VoiceTaskDefinition(
            type: .sustainedVowelAFirst,
            promptId: "vw_en_v2_ah_1",
            title: "Say Ahh",
            instruction: "Take a normal breath and say ahhh in your normal voice until the timer ends.",
            targetDurationSeconds: 5,
            minimumUsableDurationSeconds: 4,
            allowsEarlyFinish: true
        ),
        VoiceTaskDefinition(
            type: .sustainedVowelASecond,
            promptId: "vw_en_v2_ah_2",
            title: "Repeat Ahh",
            instruction: "Say ahhh one more time in the same comfortable voice.",
            targetDurationSeconds: 5,
            minimumUsableDurationSeconds: 4,
            allowsEarlyFinish: true
        ),
        VoiceTaskDefinition(
            type: .counting,
            promptId: "vw_en_v2_count_1_10",
            title: "Counting",
            instruction: "Count from 1 to 10 at a normal pace.",
            targetDurationSeconds: 6,
            minimumUsableDurationSeconds: 4,
            allowsEarlyFinish: true
        )
    ]

    static let fixedPromptTasks: [VoiceTaskDefinition] = standardAcousticTasks + [
        VoiceTaskDefinition(
            type: .fixedReading,
            promptId: "vw_en_v2_reading_001",
            title: "Read Aloud",
            instruction: "Read this in your normal voice: The morning light moved across the quiet city as people walked outside.",
            targetDurationSeconds: 18,
            minimumUsableDurationSeconds: 10,
            allowsEarlyFinish: true
        )
    ]

    private static let emptyContext = VoiceAIConversationContext(
        generatedAt: Date(timeIntervalSince1970: 0),
        experimentTag: "Untagged",
        recentHistory: [],
        missingInputs: ["personal voice baseline"],
        requiredAcousticTasks: [],
        desiredConversationTurns: advancedConversationQuestionCount,
        guardrails: []
    )

    private static func makeSummary(_ session: VoiceTrackingSession) -> VoiceAIConversationSessionSummary {
        VoiceAIConversationSessionSummary(
            id: session.id,
            date: session.date,
            voiceScore: session.result.voiceScore,
            voiceConfidence: session.result.voiceConfidence,
            usable: session.result.usable,
            baselineSessionsUsed: session.result.baselineSessionsUsed,
            topDrivers: session.result.topDrivers
        )
    }

    private static func questionTaskContexts(
        for session: VoiceTrackingSession,
        hasAdvancedConversation: Bool
    ) -> [VoiceAIQuestionTaskContext] {
        if !session.result.taskAnalyses.isEmpty {
            return session.result.taskAnalyses.map { analysis in
                VoiceAIQuestionTaskContext(
                    promptId: analysis.promptId,
                    taskType: analysis.taskType.rawValue,
                    title: analysis.taskType.displayName,
                    promptText: analysis.promptText ?? "",
                    targetDurationSeconds: analysis.targetDurationSeconds,
                    minimumUsableDurationSeconds: 0,
                    measurementPurpose: measurementPurpose(for: analysis.taskType)
                )
            }
        }

        let fallbackTasks = hasAdvancedConversation
            ? tasks(for: localPlan(for: emptyContext))
            : fixedPromptTasks
        var contexts = fallbackTasks.map { definition in
            VoiceAIQuestionTaskContext(
                promptId: definition.promptId,
                taskType: definition.type.rawValue,
                title: definition.title,
                promptText: definition.instruction,
                targetDurationSeconds: definition.targetDurationSeconds,
                minimumUsableDurationSeconds: definition.minimumUsableDurationSeconds,
                measurementPurpose: measurementPurpose(for: definition.type)
            )
        }

        if hasAdvancedConversation {
            for exchange in session.result.conversationExchanges {
                contexts.append(
                    VoiceAIQuestionTaskContext(
                        promptId: "ai_conversation_turn_\(exchange.turnIndex)",
                        taskType: VoiceTaskType.guidedConversation.rawValue,
                        title: "Advanced Freestyle Talk \(exchange.turnIndex)",
                        promptText: exchange.aiPrompt,
                        targetDurationSeconds: exchange.responseDurationSeconds,
                        minimumUsableDurationSeconds: min(30, exchange.responseDurationSeconds),
                        measurementPurpose: measurementPurpose(for: .guidedConversation)
                    )
                )
            }
        }

        return contexts
    }

    private static func measurementPurpose(for taskType: VoiceTaskType) -> String {
        switch taskType {
        case .silenceCalibration:
            return "Estimate background noise floor so later acoustic features can be interpreted with recording-quality context."
        case .sustainedVowelAFirst, .sustainedVowelASecond:
            return "Capture a steady vowel for loudness stability, voiced-frame quality, and pitch or harmonicity proxy features."
        case .counting:
            return "Capture short connected speech with a standardized number sequence for volume, pauses, and spectral movement."
        case .fixedReading:
            return "Capture standardized read-aloud speech so future sessions can be compared against the same text."
        case .guidedConversation:
            return "Capture natural speech and transcript context for wellness reflection while keeping interpretation non-diagnostic."
        }
    }

    private static func missingInputs(from sessions: [VoiceTrackingSession]) -> [String] {
        var missing: [String] = []
        if sessions.filter({ $0.result.usable }).count < 7 {
            missing.append("personal voice baseline")
        }
        if sessions.last?.result.eGeMAPS == nil {
            missing.append("latest eGeMAPS features")
        }
        return missing
    }

    static func previousAssistantReplies(from history: [VoiceAIChatMessage]) -> [String] {
        history
            .filter { $0.role == "assistant" }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func previousUserTranscripts(from history: [VoiceAIChatMessage]) -> [String] {
        history
            .filter { $0.role == "user" }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func personalizedFollowUp(
        turnIndex: Int,
        transcript: String,
        previousAssistantReplies: [String]
    ) -> String {
        let lower = transcript.lowercased()
        let candidates: [String]

        if containsAny(lower, ["sleep", "slept", "tired", "fatigue", "late night", "rest"]) {
            candidates = [
                "That sleep piece matters. What affected your rest most before this check-in?",
                "I hear the low energy. What would make the next hour feel a bit steadier?",
                "Thanks for naming that. What part of today is using the most energy?"
            ]
        } else if containsAny(lower, ["stress", "stressed", "meeting", "meetings", "workload", "busy", "deadline", "pressure"]) {
            candidates = [
                "That sounds like a full load. Which part is taking the most attention right now?",
                "I hear the workload theme. What would make the rest of today feel more manageable?",
                "Thanks for sharing that. What has helped you stay steady so far?"
            ]
        } else if containsAny(lower, ["focus", "focused", "concentrate", "distracted", "attention"]) {
            candidates = [
                "That focus detail helps. What has made attention easier or harder today?",
                "I hear the focus shift. What is one thing that could help you stay on track next?",
                "Thanks. When did your focus feel clearest today?"
            ]
        } else if containsAny(lower, ["coffee", "caffeine", "food", "meal", "hydration", "water", "exercise", "walk"]) {
            candidates = [
                "That routine detail helps. How has it changed your energy today?",
                "I hear that habit coming through. What else in your routine feels different today?",
                "Thanks for that context. What would you keep the same for your next check-in?"
            ]
        } else if containsAny(lower, ["calm", "steady", "okay", "good", "fine", "better"]) {
            candidates = [
                "Good to hear there is some steadiness. What has helped that most today?",
                "That sounds steadier. What part of the day has supported that feeling?",
                "Thanks. What would help you keep that steadiness going?"
            ]
        } else {
            candidates = [
                "Thanks for that context. What feels like the biggest reason for it today?",
                "I hear you. What part of today has shaped that the most?",
                "That helps. What would be useful to notice before your next check-in?"
            ]
        }

        return firstUnusedReply(
            in: turnIndex == 1 ? candidates : Array(candidates.dropFirst()) + Array(candidates.prefix(1)),
            previousAssistantReplies: previousAssistantReplies
        )
    }

    private static func clarificationFollowUp(
        turnIndex: Int,
        previousAssistantReplies: [String]
    ) -> String {
        let candidates = [
            "I did not catch enough words. Could you share one detail about energy or focus?",
            "Could you add one specific detail about what is affecting you right now?",
            "I missed that. What is the main thing you notice right now?"
        ]
        return firstUnusedReply(
            in: turnIndex == 1 ? candidates : Array(candidates.dropFirst()) + Array(candidates.prefix(1)),
            previousAssistantReplies: previousAssistantReplies
        )
    }

    private static func shortConversationSummary(
        latestUserTranscript: String?,
        history: [VoiceAIChatMessage]
    ) -> String {
        var transcripts = previousUserTranscripts(from: history)
        if let latest = latestUserTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty,
           transcripts.last != latest {
            transcripts.append(latest)
        }
        return shortConversationSummary(transcripts: transcripts)
    }

    private static func shortConversationSummary(transcripts: [String]) -> String {
        let cleaned = transcripts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            return "Summary saved: your voice data was captured for this check-in."
        }

        let combined = cleaned.joined(separator: " ").lowercased()
        var themes: [String] = []
        appendTheme("sleep or rest", to: &themes, when: containsAny(combined, ["sleep", "slept", "tired", "fatigue", "rest", "late night"]))
        appendTheme("workload or stress", to: &themes, when: containsAny(combined, ["stress", "stressed", "meeting", "meetings", "workload", "busy", "deadline", "pressure"]))
        appendTheme("focus", to: &themes, when: containsAny(combined, ["focus", "focused", "concentrate", "distracted", "attention"]))
        appendTheme("routine", to: &themes, when: containsAny(combined, ["coffee", "caffeine", "food", "meal", "hydration", "water", "exercise", "walk", "routine"]))
        appendTheme("steadiness", to: &themes, when: containsAny(combined, ["calm", "steady", "okay", "good", "fine", "better"]))

        if themes.isEmpty {
            return "Summary saved: your \(cleaned.count) answer\(cleaned.count == 1 ? "" : "s") and voice data were captured."
        }

        return "Summary saved: \(formattedThemeList(themes)) stood out across your answers."
    }

    private static func conciseSentence(_ text: String, characterLimit: Int = 180) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > characterLimit else { return trimmed }

        let limited = String(trimmed.prefix(characterLimit))
        if let lastSentenceIndex = limited.lastIndex(where: { ".!".contains($0) }) {
            return String(limited[...lastSentenceIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let lastSpaceIndex = limited.lastIndex(where: \.isWhitespace) {
            return String(limited[..<lastSpaceIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "."
        }
        return limited + "."
    }

    private static func appendTheme(_ theme: String, to themes: inout [String], when condition: Bool) {
        guard condition, !themes.contains(theme) else { return }
        themes.append(theme)
    }

    private static func formattedThemeList(_ themes: [String]) -> String {
        let visibleThemes = Array(themes.prefix(3))
        switch visibleThemes.count {
        case 0:
            return "your check-in context"
        case 1:
            return visibleThemes[0]
        case 2:
            return "\(visibleThemes[0]) and \(visibleThemes[1])"
        default:
            return "\(visibleThemes[0]), \(visibleThemes[1]), and \(visibleThemes[2])"
        }
    }

    private static func firstUnusedReply(
        in candidates: [String],
        previousAssistantReplies: [String]
    ) -> String {
        let used = Set(previousAssistantReplies.map(Self.normalizedPrompt))
        return candidates.first { !used.contains(Self.normalizedPrompt($0)) }
            ?? "Thanks. What is one different detail you notice right now?"
    }

    private static func normalizedPrompt(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split { $0.isWhitespace }
            .joined(separator: " ")
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
