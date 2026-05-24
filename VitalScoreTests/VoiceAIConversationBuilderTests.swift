import XCTest
@testable import VitalScore

final class VoiceAIConversationBuilderTests: XCTestCase {
    func test_makeContext_includesRecentHistoryAndGuardrails() {
        let session = makeSession(score: 72, baselineSessionsUsed: 0, eGeMAPS: nil)

        let context = VoiceAIConversationBuilder.makeContext(
            experimentTag: "Morning sunlight",
            history: [session]
        )

        XCTAssertEqual(context.experimentTag, "Morning sunlight")
        XCTAssertEqual(context.recentHistory.first?.voiceScore, 72)
        XCTAssertEqual(context.desiredConversationTurns, 4)
        XCTAssertTrue(context.missingInputs.contains("personal voice baseline"))
        XCTAssertTrue(context.guardrails.contains("No medical diagnosis"))
    }

    func test_localPlan_returnsConversationPromptsInsteadOfPostAnalysis() {
        let context = VoiceAIConversationBuilder.makeContext(
            experimentTag: "Untagged",
            history: []
        )

        let plan = VoiceAIConversationBuilder.localPlan(for: context)

        XCTAssertEqual(plan.promptTag, VoiceAIConversationBuilder.promptTag)
        XCTAssertEqual(plan.conversationTurns.count, 1)
        XCTAssertEqual(plan.conversationTurns.first?.prompt, VoiceAIConversationBuilder.fallbackFreeTalkPrompt)
        XCTAssertEqual(plan.conversationTurns.first?.targetDurationSeconds, 45)
        XCTAssertTrue(plan.conversationTurns.allSatisfy { !$0.prompt.isEmpty })
        XCTAssertTrue(plan.safetyNote.lowercased().contains("not a diagnosis"))
    }

    func test_normalizedPlan_preservesRemotePromptAsConversationalOpening() {
        let context = VoiceAIConversationBuilder.makeContext(
            experimentTag: "Untagged",
            history: []
        )
        let remotePlan = VoiceAIConversationPlan(
            planId: "remote",
            promptTag: "remote_tag",
            openingMessage: "Remote opening",
            conversationTurns: [
                VoiceAIConversationTurn(
                    id: "remote_1",
                    title: "Remote Free Talk",
                    prompt: "Talk for one minute about what has shaped your energy and focus today.",
                    targetDurationSeconds: 22
                )
            ],
            safetyNote: "Remote safety note",
            source: "openai"
        )

        let plan = VoiceAIConversationBuilder.normalizedPlan(remotePlan, for: context)

        XCTAssertEqual(plan.promptTag, VoiceAIConversationBuilder.promptTag)
        XCTAssertEqual(plan.conversationTurns.count, 1)
        XCTAssertEqual(plan.conversationTurns[0].prompt, "Talk for one minute about what has shaped your energy and focus today.")
        XCTAssertEqual(plan.conversationTurns[0].targetDurationSeconds, 45)
    }

    func test_tasks_forAdvancedTalkUseOnlyGuidedConversation() {
        let context = VoiceAIConversationBuilder.makeContext(
            experimentTag: "Untagged",
            history: []
        )
        let plan = VoiceAIConversationBuilder.localPlan(for: context)

        let tasks = VoiceAIConversationBuilder.tasks(for: plan)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.filter { $0.type == .guidedConversation }.count, 1)
        XCTAssertEqual(tasks.last?.targetDurationSeconds, 45)
        XCTAssertFalse(tasks.contains { $0.type == .silenceCalibration })
        XCTAssertFalse(tasks.contains { $0.type == .sustainedVowelAFirst })
        XCTAssertFalse(tasks.contains { $0.type == .sustainedVowelASecond })
        XCTAssertFalse(tasks.contains { $0.type == .counting })
        XCTAssertFalse(tasks.contains { $0.type == .fixedReading })
    }

    func test_fixedPromptPlan_usesReadAloudInsteadOfFreestyleConversation() {
        let tasks = VoiceAIConversationBuilder.tasks(for: VoiceAIConversationBuilder.fixedPromptPlan())

        XCTAssertEqual(tasks.count, 5)
        XCTAssertTrue(tasks.contains { $0.type == .fixedReading })
        XCTAssertFalse(tasks.contains { $0.type == .guidedConversation })
        XCTAssertEqual(tasks.last?.instruction, "Read this in your normal voice: The morning light moved across the quiet city as people walked outside.")
    }

    func test_questionProtocolContext_includesTaskBackgroundAndScoreGuardrails() {
        let session = makeSession(score: 84, baselineSessionsUsed: 2, eGeMAPS: nil)

        let context = VoiceAIConversationBuilder.questionProtocolContext(for: session)

        XCTAssertEqual(context.mode, "fixed_prompt")
        XCTAssertTrue(context.questionSet.contains { $0.taskType == VoiceTaskType.fixedReading.rawValue })
        XCTAssertTrue(context.questionSet.contains { $0.measurementPurpose.contains("standardized read-aloud") })
        XCTAssertTrue(context.scoringInterpretation.contains { $0.contains("not a medical score") })
        XCTAssertTrue(context.guardrails.contains("No medical diagnosis"))
    }

    func test_localChatReply_continuesUntilMaxTurn() {
        let firstReply = VoiceAIConversationBuilder.localChatReply(
            turnIndex: 1,
            maxTurns: 4,
            latestUserTranscript: "I slept poorly and feel low energy."
        )
        let finalReply = VoiceAIConversationBuilder.localChatReply(
            turnIndex: 4,
            maxTurns: 4,
            latestUserTranscript: "Stress is the biggest factor today."
        )

        XCTAssertTrue(firstReply.shouldContinue)
        XCTAssertFalse(firstReply.reply.isEmpty)
        XCTAssertFalse(finalReply.shouldContinue)
        XCTAssertFalse(finalReply.reply.isEmpty)
        XCTAssertFalse(finalReply.reply.contains("?"))
        XCTAssertTrue(finalReply.reply.contains("Summary saved"))
    }

    func test_localChatReply_personalizesAndAvoidsRepeatedFollowUps() {
        let firstReply = VoiceAIConversationBuilder.localChatReply(
            turnIndex: 1,
            maxTurns: 4,
            latestUserTranscript: "I slept late and feel tired this morning."
        )
        let history = [
            VoiceAIChatMessage(role: "assistant", text: firstReply.reply),
            VoiceAIChatMessage(role: "user", text: "I slept late and feel tired this morning.")
        ]

        let secondReply = VoiceAIConversationBuilder.localChatReply(
            turnIndex: 2,
            maxTurns: 4,
            latestUserTranscript: "Meetings and a deadline are adding stress.",
            history: history
        )

        XCTAssertTrue(firstReply.shouldContinue)
        XCTAssertTrue(secondReply.shouldContinue)
        XCTAssertNotEqual(firstReply.reply, secondReply.reply)
        XCTAssertTrue(firstReply.reply.contains("?"))
        XCTAssertTrue(secondReply.reply.contains("?"))
        XCTAssertTrue(secondReply.reply.localizedCaseInsensitiveContains("workload")
            || secondReply.reply.localizedCaseInsensitiveContains("manageable")
            || secondReply.reply.localizedCaseInsensitiveContains("attention"))
    }

    func test_normalizedChatReply_replacesRepeatedRemoteQuestion() {
        let repeated = "Got it. What feels like the biggest reason for that today?"
        let history = [
            VoiceAIChatMessage(role: "assistant", text: repeated),
            VoiceAIChatMessage(role: "user", text: "I feel tired after poor sleep.")
        ]
        let remote = VoiceAIChatTurnResponse(
            reply: repeated,
            shouldContinue: true,
            source: "openai"
        )

        let normalized = VoiceAIConversationBuilder.normalizedChatReply(
            remote,
            turnIndex: 2,
            maxTurns: 4,
            latestUserTranscript: "The workload is heavy today.",
            history: history
        )

        XCTAssertTrue(normalized.shouldContinue)
        XCTAssertNotEqual(normalized.reply, repeated)
        XCTAssertEqual(normalized.source, "local_personalized_fallback")
    }

    func test_normalizedChatReply_replacesFinalQuestionWithSummary() {
        let remote = VoiceAIChatTurnResponse(
            reply: "Thanks. What should we check next?",
            shouldContinue: true,
            source: "openai"
        )
        let history = [
            VoiceAIChatMessage(role: "assistant", text: "How is your energy?"),
            VoiceAIChatMessage(role: "user", text: "Sleep was short and work is busy.")
        ]

        let normalized = VoiceAIConversationBuilder.normalizedChatReply(
            remote,
            turnIndex: 4,
            maxTurns: 4,
            latestUserTranscript: "Focus is okay but stress is high.",
            history: history
        )

        XCTAssertFalse(normalized.shouldContinue)
        XCTAssertFalse(normalized.reply.contains("?"))
        XCTAssertTrue(normalized.reply.contains("Summary saved"))
    }

    func test_conversationSummary_buildsLocalSummaryRecord() {
        let exchange = VoiceConversationExchange(
            turnIndex: 4,
            aiPrompt: "What is one thing shaping your focus?",
            userTranscript: "Sleep was short and meetings made the day stressful.",
            userResponseStartedAt: Date(),
            userResponseEndedAt: Date(),
            responseDurationSeconds: 6,
            source: "ios_speech_recognition"
        )

        let summary = VoiceAIConversationBuilder.conversationSummary(
            from: [exchange],
            closingReply: "Summary saved: sleep or rest and workload or stress stood out across your answers.",
            source: "openai"
        )

        XCTAssertEqual(summary.questionCount, 1)
        XCTAssertEqual(summary.source, "openai")
        XCTAssertTrue(summary.summary.contains("sleep"))
    }

    func test_localAnalysisSummary_returnsUsableFallbackWhenRemoteAnalysisFails() {
        let session = makeSession(score: 84, baselineSessionsUsed: 2, eGeMAPS: nil)

        let summary = VoiceAIConversationBuilder.localAnalysisSummary(
            for: session,
            exportId: UUID(),
            unavailableReason: "server offline"
        )

        XCTAssertEqual(summary.source, "local_summary_fallback")
        XCTAssertTrue(summary.summary.contains("Voice score"))
        XCTAssertTrue(summary.dataQuality.contains { $0.contains("server offline") })
        XCTAssertFalse(summary.safetyNote.isEmpty)
    }

    private func makeSession(
        score: Double,
        baselineSessionsUsed: Int,
        eGeMAPS: VoiceEGeMAPSFeatureSet?
    ) -> VoiceTrackingSession {
        let result = VoiceTrackingResult(
            completedAt: Date(),
            durationSeconds: 30,
            voiceScore: score,
            voiceConfidence: "Medium",
            averageVolumeDb: -24,
            volumeStdDevDb: 3.2,
            silenceRatio: 0.08,
            peakVolumeDb: -12,
            overallQualityScore: 0.92,
            usable: true,
            qualityIssues: [],
            taskAnalyses: [],
            eGeMAPS: eGeMAPS,
            baselineSessionsUsed: baselineSessionsUsed,
            baselineStatus: baselineSessionsUsed > 0 ? "baseline_ready" : "building_baseline",
            topDrivers: ["Voice signal was steady compared with recent captures."]
        )
        return VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: "Untagged",
            promptTag: "voice_check_v1",
            result: result
        )
    }
}
