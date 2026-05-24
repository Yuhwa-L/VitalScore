import SwiftUI

enum VoiceTrackingMode: Equatable {
    case fixedPrompt
    case advancedFreestyle

    var title: String {
        switch self {
        case .fixedPrompt: return "Voice Check"
        case .advancedFreestyle: return "Advanced Voice Talk"
        }
    }

    var startButtonTitle: String {
        switch self {
        case .fixedPrompt: return "Start Voice Check"
        case .advancedFreestyle: return "Start AI Talk"
        }
    }
}

private enum VoiceAIAnalysisStatus: Equatable {
    case idle
    case loading
    case ready(VoiceAIAnalysisResponse)
    case unavailable(String)
}

struct VoiceTrackingView: View {
    @StateObject private var manager = VoiceTrackingManager()
    @StateObject private var promptSpeaker = VoicePromptSpeaker()
    @Environment(\.dismiss) private var dismiss
    @State private var conversationPlan: VoiceAIConversationPlan?
    @State private var isPreparingConversation = false
    @State private var conversationError: String?
    @State private var handledThinkingTurns: Set<String> = []
    @State private var completedSession: VoiceTrackingSession?
    @State private var completionAnalysisStatus: VoiceAIAnalysisStatus = .idle
    @State private var completionAnalysisTask: Task<Void, Never>?
    let mode: VoiceTrackingMode
    let previousSessions: [VoiceTrackingSession]
    let experimentTag: String
    let onAnalysisRequested: (VoiceTrackingSession) async -> VoiceAIAnalysisResponse?
    let onFinished: (VoiceTrackingSession) -> Void

    init(
        mode: VoiceTrackingMode = .fixedPrompt,
        previousSessions: [VoiceTrackingSession],
        experimentTag: String,
        onAnalysisRequested: @escaping (VoiceTrackingSession) async -> VoiceAIAnalysisResponse? = { _ in nil },
        onFinished: @escaping (VoiceTrackingSession) -> Void
    ) {
        self.mode = mode
        self.previousSessions = previousSessions
        self.experimentTag = experimentTag
        self.onAnalysisRequested = onAnalysisRequested
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            content
            Spacer()
        }
        .padding()
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onChange(of: manager.phase) { _, newPhase in
            speakPromptIfNeeded(for: newPhase)
            respondToAIThinkingIfNeeded(for: newPhase)
            analyzeCompletedResultIfNeeded(for: newPhase)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") {
                    resetCompletionAnalysis()
                    handledThinkingTurns.removeAll()
                    promptSpeaker.stop()
                    manager.cancel()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.phase {
        case .idle:
            VStack(spacing: 18) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.teal)
                Text(mode.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(introText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                if mode == .fixedPrompt {
                    fixedPromptPreview
                }

                if mode == .advancedFreestyle, let plan = conversationPlan {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Ready", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.teal)
                        Text(plan.openingMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
                }

                if let conversationError {
                    Text(conversationError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Button {
                    startVoiceCheck()
                } label: {
                    if isPreparingConversation {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(mode.startButtonTitle)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
                .disabled(isPreparingConversation)

                if mode == .advancedFreestyle {
                    Button {
                        resetCompletionAnalysis()
                        handledThinkingTurns.removeAll()
                        let context = VoiceAIConversationBuilder.makeContext(
                            experimentTag: experimentTag,
                            history: previousSessions
                        )
                        let plan = VoiceAIConversationBuilder.normalizedPlan(
                            VoiceAIConversationBuilder.localPlan(for: context),
                            for: context
                        )
                        conversationPlan = plan
                        conversationError = "Using local prompts; provider-backed AI was skipped."
                        manager.start(conversationPlan: plan)
                    } label: {
                        Text("Start Without Server")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.accentColor)
                            .cornerRadius(12)
                    }
                    .disabled(isPreparingConversation)
                }
            }
        case .requestingPermission:
            ProgressView("Requesting microphone access...")
        case .countdown(let n):
            VStack(spacing: 12) {
                Text("\(n)")
                    .font(.system(size: 88, weight: .bold))
                Text("Get ready")
                    .foregroundColor(.secondary)
            }
        case .speakingPrompt(let task):
            VStack(spacing: 18) {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.teal)
                Text("Prompt")
                    .font(.title3.weight(.semibold))
                Text(task.instruction)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                ProgressView()
                    .tint(.teal)
                Text("Listen first. Recording starts after the prompt finishes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .aiSpeaking(_, _, let message, let shouldListenAfter):
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 58))
                    .foregroundStyle(.teal)
                Text(shouldListenAfter ? "Assistant" : "Wrapping up")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                ProgressView()
                    .tint(.teal)
                Text(shouldListenAfter ? "Reply naturally when it finishes speaking." : "Finishing this voice check")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .aiListening:
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("Your response")
                        .font(.title3.weight(.semibold))
                    Text("The app sends your answer after a clear pause.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(manager.currentTranscript.isEmpty ? "Listening..." : manager.currentTranscript)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(manager.currentTranscript.isEmpty ? .secondary : .primary)
                voiceMeter
                ProgressView(value: manager.elapsedSeconds, total: VoiceTrackingManager.aiConversationTurnDurationSeconds)
                    .tint(.teal)
                Text("Pause briefly when you are done, or tap Send Now.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button {
                        manager.resetCurrentAIResponse()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.accentColor)
                            .cornerRadius(12)
                    }

                    Button {
                        manager.finishEarly()
                    } label: {
                        Text("Send Now")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
        case .aiThinking(_, _, let transcript):
            VStack(spacing: 18) {
                ProgressView()
                    .tint(.teal)
                Text("Thinking")
                    .font(.title3.weight(.semibold))
                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        case .running:
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(manager.currentTask.title)
                        .font(.title3.weight(.semibold))
                    Text("Step \(manager.currentTaskIndex + 1) of \(manager.tasks.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(manager.currentTask.instruction)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if mode == .advancedFreestyle && manager.currentTask.type == .guidedConversation {
                    Text("Answer naturally in a few sentences. There are no right or wrong answers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                voiceMeter
                ProgressView(value: manager.elapsedSeconds, total: manager.currentTask.targetDurationSeconds)
                    .tint(.teal)
                Text("\(Int(ceil(manager.currentTask.targetDurationSeconds - manager.elapsedSeconds)))s remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if manager.currentTask.allowsEarlyFinish {
                    Button {
                        manager.finishEarly()
                    } label: {
                        Text("I Am Finished")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
        case .finished(let result):
            ScrollView {
                resultView(result)
            }
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.red)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    startVoiceCheck()
                }
                .font(.headline)
            }
        }
    }

    private var voiceMeter: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 18)
                Capsule()
                    .fill(Color.teal)
                    .frame(width: max(12, 260 * manager.liveLevel), height: 18)
                    .animation(.easeOut(duration: 0.08), value: manager.liveLevel)
            }
            .frame(width: 260)
            Text("Keep the meter moving near the middle.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var introText: String {
        switch mode {
        case .fixedPrompt:
            return "Follow the fixed prompts on screen: quiet calibration, two ahh sounds, counting from 1 to 10, and the read-aloud sentence. Audio is analyzed on device for acoustic features; raw audio is not stored unless enabled in debug settings."
        case .advancedFreestyle:
            return "Have a short AI-guided voice conversation. There are no ahh, counting, or reading prompts in advanced mode. The app transcribes your responses for wellness trend analysis; raw audio is not stored unless enabled in debug settings."
        }
    }

    private var fixedPromptPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Fixed prompt sequence", systemImage: "text.alignleft")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.teal)
            ForEach(VoiceAIConversationBuilder.fixedPromptTasks, id: \.promptId) { task in
                Text(task.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    private func resultView(_ result: VoiceTrackingResult) -> some View {
        let scoredResult = VoiceTrackingManager.score(result, against: previousSessions)
        return VStack(spacing: 14) {
            aiAnalysisSummaryPanel

            VStack(spacing: 8) {
                Text("Voice Score")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("\(Int(scoredResult.voiceScore))")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(scoreColor(scoredResult.voiceScore))
                Text("\(scoredResult.voiceConfidence) confidence")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Capture Quality")
                    .font(.headline)
                HStack(spacing: 12) {
                    resultMetric("Quality", "\(Int(scoredResult.overallQualityScore * 100))", "%")
                    resultMetric("Silence", "\(Int(scoredResult.silenceRatio * 100))", "%")
                    resultMetric("Baseline", "\(scoredResult.baselineSessionsUsed)", "")
                }
                HStack(spacing: 12) {
                    resultMetric("Avg volume", "\(Int(scoredResult.averageVolumeDb))", "dB")
                    resultMetric("Variability", String(format: "%.1f", scoredResult.volumeStdDevDb), "dB")
                    resultMetric("Peak", "\(Int(scoredResult.peakVolumeDb))", "dB")
                }
            }
            .resultPanel()

            if let features = scoredResult.eGeMAPS {
                VStack(alignment: .leading, spacing: 12) {
                    Text("eGeMAPS Snapshot")
                        .font(.headline)
                    HStack(spacing: 12) {
                        resultMetric("F0", format(features.f0MeanHz, digits: 0), "Hz")
                        resultMetric("Jitter", format(features.jitterLocalPercent, digits: 2), "%")
                        resultMetric("HNR", format(features.hnrMeanDb, digits: 1), "dB")
                    }
                    HStack(spacing: 12) {
                        resultMetric("Shimmer", format(features.shimmerLocalDb, digits: 2), "dB")
                        resultMetric("Flux", format(features.spectralFlux, digits: 3), "")
                        resultMetric("Voiced", format(features.meanVoicedSegmentLengthSeconds, digits: 2), "s")
                    }
                }
                .resultPanel()
            }

            if let summary = scoredResult.conversationSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conversation Summary")
                        .font(.headline)
                    Text(summary.summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("\(summary.questionCount) answer\(summary.questionCount == 1 ? "" : "s") saved locally.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .resultPanel()
            }

            if !scoredResult.conversationExchanges.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Conversation")
                        .font(.headline)
                    ForEach(scoredResult.conversationExchanges) { exchange in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI: \(exchange.aiPrompt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("You: \(exchange.userTranscript.isEmpty ? "No transcript captured" : exchange.userTranscript)")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .resultPanel()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Drivers")
                    .font(.headline)
                ForEach(scoredResult.topDrivers, id: \.self) { driver in
                    Text(driver)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .resultPanel()

            Button {
                let session = completedSession
                    ?? manager.makeSessionMetadata(result: scoredResult, experimentTag: experimentTag)
                onFinished(session)
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }

    @ViewBuilder
    private var aiAnalysisSummaryPanel: some View {
        switch completionAnalysisStatus {
        case .idle:
            EmptyView()
        case .loading:
            VStack(alignment: .leading, spacing: 12) {
                Label("AI Summary", systemImage: "sparkles")
                    .font(.headline)
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.teal)
                    Text("Analyzing this voice check...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .resultPanel()
        case .ready(let analysis):
            VStack(alignment: .leading, spacing: 12) {
                Label(analysis.source == "local_summary_fallback" ? "Voice Summary" : "AI Summary", systemImage: "sparkles")
                    .font(.headline)
                Text(analysis.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if !analysis.notableSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(analysis.notableSignals.prefix(3)), id: \.self) { signal in
                            Label(signal, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(analysis.safetyNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .resultPanel()
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("AI Summary", systemImage: "sparkles")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .resultPanel()
        }
    }

    private func resultMetric(_ label: String, _ value: String?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text((value ?? "--") + (unit.isEmpty ? "" : " \(unit)"))
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func format(_ value: Double?, digits: Int) -> String? {
        guard let value = value else { return nil }
        return String(format: "%.\(digits)f", value)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score < 50 { return .orange }
        return .primary
    }

    private func prepareAndStartConversation() {
        guard !isPreparingConversation else { return }
        resetCompletionAnalysis()
        promptSpeaker.stop()
        handledThinkingTurns.removeAll()
        isPreparingConversation = true
        conversationError = nil

        Task {
            let context = VoiceAIConversationBuilder.makeContext(
                experimentTag: experimentTag,
                history: previousSessions
            )
            let plan: VoiceAIConversationPlan
            do {
                let remotePlan = try await AIConversationClient().buildVoiceConversationPlan(context: context)
                plan = VoiceAIConversationBuilder.normalizedPlan(remotePlan, for: context)
            } catch {
                plan = VoiceAIConversationBuilder.normalizedPlan(
                    VoiceAIConversationBuilder.localPlan(for: context),
                    for: context
                )
                await MainActor.run {
                    conversationError = "Using local prompts because AI prompts could not be prepared: \(error.localizedDescription)"
                }
            }

            await MainActor.run {
                conversationPlan = plan
                isPreparingConversation = false
                manager.start(conversationPlan: plan)
            }
        }
    }

    private func startVoiceCheck() {
        switch mode {
        case .fixedPrompt:
            resetCompletionAnalysis()
            promptSpeaker.stop()
            handledThinkingTurns.removeAll()
            conversationError = nil
            conversationPlan = VoiceAIConversationBuilder.fixedPromptPlan()
            manager.start(conversationPlan: VoiceAIConversationBuilder.fixedPromptPlan())
        case .advancedFreestyle:
            prepareAndStartConversation()
        }
    }

    private func analyzeCompletedResultIfNeeded(for phase: VoiceTrackingManager.Phase) {
        guard case .finished(let result) = phase else { return }

        let scoredResult = VoiceTrackingManager.score(result, against: previousSessions)
        if completedSession?.result.id == scoredResult.id {
            return
        }

        let session = manager.makeSessionMetadata(result: scoredResult, experimentTag: experimentTag)
        completedSession = session
        completionAnalysisStatus = .loading
        completionAnalysisTask?.cancel()
        completionAnalysisTask = Task {
            let analysis = await onAnalysisRequested(session)
            await MainActor.run {
                guard completedSession?.id == session.id else { return }
                if let analysis {
                    completionAnalysisStatus = .ready(analysis)
                } else {
                    completionAnalysisStatus = .unavailable("AI summary is unavailable. Local voice metrics are shown below.")
                }
            }
        }
    }

    private func resetCompletionAnalysis() {
        completionAnalysisTask?.cancel()
        completionAnalysisTask = nil
        completedSession = nil
        completionAnalysisStatus = .idle
    }

    private func speakPromptIfNeeded(for phase: VoiceTrackingManager.Phase) {
        switch phase {
        case .speakingPrompt(let task):
            promptSpeaker.speak(task.instruction) {
                manager.promptSpeechFinished()
            }
        case .aiSpeaking(_, _, let message, _):
            promptSpeaker.speak(message) {
                manager.aiSpeechFinished()
            }
        default:
            return
        }
    }

    private func respondToAIThinkingIfNeeded(for phase: VoiceTrackingManager.Phase) {
        guard mode == .advancedFreestyle else { return }
        guard case .aiThinking(_, let turnIndex, let transcript) = phase else { return }
        let key = "\(turnIndex)-\(transcript)"
        guard !handledThinkingTurns.contains(key) else { return }
        handledThinkingTurns.insert(key)

        Task {
            let context = VoiceAIConversationBuilder.makeContext(
                experimentTag: experimentTag,
                history: previousSessions
            )
            let response: VoiceAIChatTurnResponse
            do {
                response = try await AIConversationClient().buildVoiceChatReply(
                    context: context,
                    history: manager.conversationMessages,
                    latestUserTranscript: transcript,
                    turnIndex: turnIndex,
                    maxTurns: VoiceTrackingManager.aiConversationMaxTurns
                )
            } catch {
                response = VoiceAIConversationBuilder.localChatReply(
                    turnIndex: turnIndex,
                    maxTurns: VoiceTrackingManager.aiConversationMaxTurns,
                    latestUserTranscript: transcript,
                    history: manager.conversationMessages
                )
            }

            await MainActor.run {
                manager.aiReplyReady(response, for: turnIndex)
            }
        }
    }
}

private extension View {
    func resultPanel() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
    }
}
