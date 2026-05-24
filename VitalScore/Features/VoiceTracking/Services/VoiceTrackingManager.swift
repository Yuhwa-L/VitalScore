import AVFoundation
import Combine
import Foundation
import Speech
import UIKit

struct VoiceTaskDefinition: Equatable {
    let type: VoiceTaskType
    let promptId: String
    let title: String
    let instruction: String
    let targetDurationSeconds: TimeInterval
    let minimumUsableDurationSeconds: TimeInterval
    let allowsEarlyFinish: Bool
}

final class VoiceTrackingManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case countdown(Int)
        case speakingPrompt(VoiceTaskDefinition)
        case aiSpeaking(VoiceTaskDefinition, Int, String, Bool)
        case aiListening(VoiceTaskDefinition, Int, String)
        case aiThinking(VoiceTaskDefinition, Int, String)
        case running
        case finished(VoiceTrackingResult)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var liveLevel: Double = 0
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var currentTaskIndex = 0
    @Published var currentTranscript = ""
    /// True from the moment the user taps Send Now until the recogniser
    /// finalises its transcript. UI uses this to swap controls for a spinner
    /// while the on-device pipeline drains.
    @Published var isFinalizingTranscript = false
    static let conversationFinalizationDelaySeconds: TimeInterval = 2
    @Published private(set) var conversationExchanges: [VoiceConversationExchange] = []
    @Published private(set) var conversationSummary: VoiceConversationSummary?
    @Published private(set) var tasks = VoiceAIConversationBuilder.fixedPromptTasks
    @Published var currentTask = VoiceAIConversationBuilder.fixedPromptTasks[0]

    static let silenceThresholdDb = -45.0
    static let featureExtractorVersion = "vitalscore_on_device_acoustic_v1"
    static let modelVersion = "personal_baseline_deviation_v1"
    static let promptVersion = VoiceAIConversationBuilder.fixedPromptVersion
    static let consentVersion = "voice_wellness_check_v1"
    static var rawAudioRetentionPolicy: String {
        VoiceRawAudioDebugExportSettings.rawAudioRetentionPolicy
    }
    static let aiConversationMaxTurns = VoiceAIConversationBuilder.advancedConversationQuestionCount
    static let aiConversationTurnDurationSeconds = VoiceAIConversationBuilder.advancedConversationTurnTargetSeconds
    static let aiConversationTotalDurationSeconds = VoiceAIConversationBuilder.advancedConversationTotalTargetSeconds
    static let speechContextualStrings = [
        "VitalScore",
        "energy",
        "focus",
        "stress",
        "sleep",
        "rest",
        "tired",
        "fatigue",
        "workload",
        "hydration",
        "hydrated",
        "caffeine",
        "coffee",
        "meditation",
        "breathing",
        "screen time",
        "workout",
        "exercise",
        "meeting",
        "commute",
        "routine",
        "environment",
        "calm",
        "steady",
        "busy",
        "morning",
        "afternoon",
        "evening"
    ]
    private(set) var promptTag = VoiceAIConversationBuilder.fixedPromptTag
    private(set) var activePromptVersion = VoiceAIConversationBuilder.fixedPromptVersion

    var totalTargetDurationSeconds: TimeInterval {
        tasks.reduce(0) { $0 + $1.targetDurationSeconds }
    }

    private let audioEngine = AVAudioEngine()
    private var countdownTimer: Timer?
    private var progressTimer: Timer?
    private var taskTimer: Timer?
    private var taskStartedAt: Date?
    private var sessionStartedAt: Date?
    private var currentFrames: [VoiceFrameSummary] = []
    private var completedTasks: [VoiceTaskAnalysis] = []
    private var isInputTapInstalled = false
    private var sessionSampleRate = 0.0
    private var sessionChannels = 1
    private var sessionMicrophoneRoute = "unknown"
    private var spokenPromptIds: Set<String> = []
    private lazy var appleSpeechTranscriptionProvider = AppleSpeechTranscriptionProvider(
        mode: Bundle.main.speechRecognitionMode,
        contextualStrings: Self.speechContextualStrings
    )
    private lazy var appleSpeechAnalyzerProvider: VoiceSpeechTranscriptionProvider? = {
        if #available(iOS 26.0, *) {
            return AppleSpeechAnalyzerTranscriptionProvider()
        }
        return nil
    }()
    #if canImport(FluidAudio)
    private lazy var fluidAudioSpeechTranscriptionProvider = FluidAudioSpeechTranscriptionProvider()
    #endif
    private var speechTranscriptionProvider: VoiceSpeechTranscriptionProvider?
    private var speechRecognitionGeneration = 0
    private var activeSpeechTranscriptionSource = "none"
    private var isCompletingConversationTurn = false
    private var conversationRecordedSeconds: TimeInterval = 0
    private var conversationTurnStartedAt: Date?
    private var conversationTurnFrameStartIndex = 0
    private let rawAudioDebugExporter = VoiceRawAudioDebugExporter()

    func start(conversationPlan: VoiceAIConversationPlan? = nil) {
        resetRecordingState()
        if let conversationPlan {
            tasks = VoiceAIConversationBuilder.tasks(for: conversationPlan)
            promptTag = conversationPlan.promptTag
            activePromptVersion = conversationPlan.source == "fixed_prompt"
                ? VoiceAIConversationBuilder.fixedPromptVersion
                : VoiceAIConversationBuilder.promptVersion
        } else {
            let fixedPlan = VoiceAIConversationBuilder.fixedPromptPlan()
            tasks = VoiceAIConversationBuilder.tasks(for: fixedPlan)
            promptTag = fixedPlan.promptTag
            activePromptVersion = VoiceAIConversationBuilder.fixedPromptVersion
        }
        currentTask = tasks[0]
        phase = .requestingPermission
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    if self.tasks.contains(where: { $0.type == .guidedConversation }) {
                        if self.shouldRequestSpeechRecognitionPermissionBeforeConversation {
                            self.requestSpeechRecognitionPermission()
                        } else {
                            self.beginSession()
                        }
                    } else {
                        self.startCountdown()
                    }
                } else {
                    self.phase = .failed("Microphone access is required to run voice tracking.")
                }
            }
        }
    }

    func cancel() {
        stopAudio()
        invalidateTimers()
        reset()
        phase = .idle
    }

    func finishEarly() {
        switch phase {
        case .running where currentTask.allowsEarlyFinish:
            completeCurrentTaskAndAdvance()
        case .aiListening where currentTask.allowsEarlyFinish:
            scheduleConversationTurnFinalization()
        default:
            return
        }
    }

    /// Hold the audio + STT pipeline open for a brief settling window after the
    /// user taps Send Now, giving the recognizer time to finalise any in-flight
    /// tokens before we hand the transcript to GPT.
    private func scheduleConversationTurnFinalization() {
        guard !isCompletingConversationTurn, !isFinalizingTranscript else { return }
        isFinalizingTranscript = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.conversationFinalizationDelaySeconds) { [weak self] in
            self?.completeCurrentConversationTurn()
        }
    }

    func resetCurrentAIResponse() {
        guard case .aiListening(let task, let turnIndex, let aiPrompt) = phase,
              task.promptId == currentTask.promptId
        else { return }

        let resetAt = Date()
        isFinalizingTranscript = false
        taskTimer?.invalidate()
        stopSpeechRecognition(cancel: true)
        rawAudioDebugExporter.finishActiveSample(
            endedAt: resetAt,
            durationSeconds: nil,
            status: "discarded"
        )

        if conversationTurnFrameStartIndex < currentFrames.count {
            currentFrames.removeSubrange(conversationTurnFrameStartIndex..<currentFrames.count)
        }

        currentTranscript = ""
        liveLevel = 0
        elapsedSeconds = 0
        conversationTurnStartedAt = resetAt
        conversationTurnFrameStartIndex = currentFrames.count
        rawAudioDebugExporter.beginSample(task: task, turnIndex: turnIndex, startedAt: resetAt)
        phase = .aiListening(task, turnIndex, aiPrompt)
        startSpeechRecognition()

        taskTimer = Timer.scheduledTimer(withTimeInterval: Self.aiConversationTurnDurationSeconds, repeats: false) { [weak self] _ in
            self?.completeCurrentConversationTurn()
        }
    }

    func promptSpeechFinished() {
        guard case .speakingPrompt(let task) = phase,
              task.promptId == currentTask.promptId
        else { return }
        beginCurrentTaskRecording()
    }

    func aiSpeechFinished() {
        guard case .aiSpeaking(let task, let turnIndex, let message, let shouldListenAfter) = phase,
              task.promptId == currentTask.promptId
        else { return }

        if shouldListenAfter {
            beginAIListeningTurn(task: task, turnIndex: turnIndex, aiPrompt: message)
        } else {
            finishAIConversationTask()
        }
    }

    func aiReplyReady(_ response: VoiceAIChatTurnResponse, for turnIndex: Int) {
        guard case .aiThinking(let task, let currentTurnIndex, let latestTranscript) = phase,
              currentTurnIndex == turnIndex,
              task.promptId == currentTask.promptId
        else { return }

        let normalized = VoiceAIConversationBuilder.normalizedChatReply(
            response,
            turnIndex: turnIndex,
            maxTurns: Self.aiConversationMaxTurns,
            latestUserTranscript: latestTranscript,
            history: conversationMessages
        )
        let spokenReply = normalized.reply
        let shouldContinue = normalized.shouldContinue && turnIndex < Self.aiConversationMaxTurns
        if !shouldContinue {
            conversationSummary = VoiceAIConversationBuilder.conversationSummary(
                from: conversationExchanges,
                closingReply: spokenReply,
                source: normalized.source
            )
        }
        phase = .aiSpeaking(task, shouldContinue ? turnIndex + 1 : turnIndex, spokenReply, shouldContinue)
    }

    var conversationMessages: [VoiceAIChatMessage] {
        conversationExchanges.flatMap {
            [
                VoiceAIChatMessage(role: "assistant", text: $0.aiPrompt),
                VoiceAIChatMessage(role: "user", text: $0.userTranscript)
            ]
        }
    }

    private var shouldRequestSpeechRecognitionPermissionBeforeConversation: Bool {
        // SpeechAnalyzer uses the same Speech Recognition authorization as
        // SFSpeechRecognizer, so request it up front when the analyzer will be used.
        if #available(iOS 26.0, *),
           Bundle.main.voiceTranscriptionProviderPreference != .appleSpeech,
           appleSpeechAnalyzerProvider != nil {
            return true
        }
        switch Bundle.main.voiceTranscriptionProviderPreference {
        case .appleSpeech:
            return true
        case .fluidAudio:
            #if canImport(FluidAudio)
            return false
            #else
            return true
            #endif
        }
    }

    private func requestSpeechRecognitionPermission() {
        requestAppleSpeechRecognitionPermission { [weak self] granted, message in
            guard let self else { return }
            if granted {
                if self.currentTask.type == .guidedConversation {
                    self.beginSession()
                } else {
                    self.startCountdown()
                }
            } else {
                self.phase = .failed(message ?? "Speech recognition is required for the AI conversation.")
            }
        }
    }

    private func requestAppleSpeechRecognitionPermission(completion: @escaping (Bool, String?) -> Void) {
        AppleSpeechTranscriptionProvider.requestAuthorization { status in
            switch status {
            case .authorized:
                completion(true, nil)
            case .denied, .restricted, .notDetermined:
                completion(false, "Speech recognition access is required for the Apple Speech fallback.")
            @unknown default:
                completion(false, "Speech recognition is unavailable on this device.")
            }
        }
    }

    private func startCountdown() {
        phase = .countdown(3)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if case .countdown(let n) = self.phase {
                if n > 1 {
                    self.phase = .countdown(n - 1)
                } else {
                    self.countdownTimer?.invalidate()
                    self.beginSession()
                }
            }
        }
    }

    private func beginSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: [])
            sessionMicrophoneRoute = session.currentRoute.inputs.first?.portType.rawValue ?? "unknown"

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            sessionSampleRate = format.sampleRate
            sessionChannels = Int(format.channelCount)
            let startedAt = Date()
            rawAudioDebugExporter.beginSession(startedAt: startedAt, inputFormat: format)

            if isInputTapInstalled {
                input.removeTap(onBus: 0)
                isInputTapInstalled = false
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.speechTranscriptionProvider?.append(buffer)
                self?.rawAudioDebugExporter.write(buffer)
                guard let frame = Self.frameSummary(from: buffer) else { return }
                DispatchQueue.main.async {
                    self?.recordFrame(frame)
                }
            }
            isInputTapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
            sessionStartedAt = startedAt
            beginTask(at: 0)
        } catch {
            stopAudio()
            phase = .failed("Could not start the microphone. Please try again.")
        }
    }

    private func beginTask(at index: Int) {
        guard tasks.indices.contains(index) else {
            finishSession()
            return
        }
        currentTaskIndex = index
        currentTask = tasks[index]
        currentFrames.removeAll()
        liveLevel = 0
        elapsedSeconds = 0
        taskStartedAt = nil

        if currentTask.type == .guidedConversation {
            beginAIConversationTask()
            return
        }

        if !spokenPromptIds.contains(currentTask.promptId) {
            spokenPromptIds.insert(currentTask.promptId)
            phase = .speakingPrompt(currentTask)
            return
        }

        beginCurrentTaskRecording()
    }

    private func beginCurrentTaskRecording() {
        let startedAt = Date()
        taskStartedAt = startedAt
        rawAudioDebugExporter.beginSample(task: currentTask, turnIndex: nil, startedAt: startedAt)
        phase = .running
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let taskStartedAt = self.taskStartedAt else { return }
            self.elapsedSeconds = min(self.currentTask.targetDurationSeconds, Date().timeIntervalSince(taskStartedAt))
        }
        taskTimer?.invalidate()
        taskTimer = Timer.scheduledTimer(withTimeInterval: currentTask.targetDurationSeconds, repeats: false) { [weak self] _ in
            self?.completeCurrentTaskAndAdvance()
        }
    }

    private func beginAIConversationTask() {
        conversationRecordedSeconds = 0
        conversationTurnStartedAt = nil
        currentTranscript = ""
        preparePreferredSpeechTranscriptionProvider()
        phase = .aiSpeaking(currentTask, 1, currentTask.instruction, true)
    }

    /// Kick off background model load so the Parakeet weights are warm by the
    /// time the user starts a conversation. Safe to call multiple times.
    func prewarmTranscription() {
        preparePreferredSpeechTranscriptionProvider()
    }

    private func preparePreferredSpeechTranscriptionProvider() {
        if #available(iOS 26.0, *),
           Bundle.main.voiceTranscriptionProviderPreference != .appleSpeech,
           let analyzer = appleSpeechAnalyzerProvider as? AppleSpeechAnalyzerTranscriptionProvider {
            analyzer.prepareForUse()
            return
        }
        guard Bundle.main.voiceTranscriptionProviderPreference == .fluidAudio else { return }
        #if canImport(FluidAudio)
        fluidAudioSpeechTranscriptionProvider.prepareForUse()
        #endif
    }

    private func beginAIListeningTurn(task: VoiceTaskDefinition, turnIndex: Int, aiPrompt: String) {
        currentTranscript = ""
        conversationTurnStartedAt = Date()
        isCompletingConversationTurn = false
        conversationTurnFrameStartIndex = currentFrames.count
        rawAudioDebugExporter.beginSample(task: task, turnIndex: turnIndex, startedAt: conversationTurnStartedAt ?? Date())
        phase = .aiListening(task, turnIndex, aiPrompt)
        startSpeechRecognition()

        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startedAt = self.conversationTurnStartedAt else { return }
            let currentTurnSeconds = Date().timeIntervalSince(startedAt)
            self.elapsedSeconds = min(Self.aiConversationTurnDurationSeconds, currentTurnSeconds)
        }

        taskTimer?.invalidate()
        taskTimer = Timer.scheduledTimer(withTimeInterval: Self.aiConversationTurnDurationSeconds, repeats: false) { [weak self] _ in
            self?.completeCurrentConversationTurn()
        }
    }

    private func completeCurrentConversationTurn() {
        guard case .aiListening(let task, let turnIndex, let aiPrompt) = phase,
              task.promptId == currentTask.promptId,
              !isCompletingConversationTurn
        else { return }

        isCompletingConversationTurn = true
        isFinalizingTranscript = false
        let completedAt = Date()
        let startedAt = conversationTurnStartedAt ?? completedAt
        let duration = max(0, completedAt.timeIntervalSince(startedAt))
        conversationRecordedSeconds = min(Self.aiConversationTotalDurationSeconds, conversationRecordedSeconds + duration)
        elapsedSeconds = conversationRecordedSeconds

        taskTimer?.invalidate()
        progressTimer?.invalidate()
        let transcriptionSource = activeSpeechTranscriptionSource
        rawAudioDebugExporter.finishActiveSample(
            endedAt: completedAt,
            durationSeconds: duration
        )

        stopSpeechRecognition(cancel: false) { [weak self] finalTranscript in
            DispatchQueue.main.async {
                guard let self else { return }
                let fallbackTranscript = self.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                let finishedTranscript = finalTranscript?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let transcript = (finishedTranscript?.isEmpty == false ? finishedTranscript : fallbackTranscript) ?? fallbackTranscript
                self.currentTranscript = transcript
                self.conversationExchanges.append(
                    VoiceConversationExchange(
                        turnIndex: turnIndex,
                        aiPrompt: aiPrompt,
                        userTranscript: transcript,
                        userResponseStartedAt: startedAt,
                        userResponseEndedAt: completedAt,
                        responseDurationSeconds: duration,
                        source: transcriptionSource
                    )
                )
                self.isCompletingConversationTurn = false
                self.phase = .aiThinking(task, turnIndex, transcript)
            }
        }
    }

    private func finishAIConversationTask() {
        taskTimer?.invalidate()
        progressTimer?.invalidate()
        stopSpeechRecognition(cancel: true)

        let noiseFloor = completedTasks.first(where: { $0.taskType == .silenceCalibration })?.averageVolumeDb
        completedTasks.append(Self.analyzeTask(
            currentTask,
            frames: currentFrames,
            durationSeconds: max(conversationRecordedSeconds, elapsedSeconds),
            noiseFloorDb: noiseFloor
        ))
        beginTask(at: currentTaskIndex + 1)
    }

    private func completeCurrentTaskAndAdvance() {
        guard case .running = phase else { return }
        let duration = taskStartedAt.map { Date().timeIntervalSince($0) } ?? currentTask.targetDurationSeconds
        let completedAt = Date()
        taskTimer?.invalidate()
        progressTimer?.invalidate()
        rawAudioDebugExporter.finishActiveSample(
            endedAt: completedAt,
            durationSeconds: duration
        )

        let noiseFloor = completedTasks.first(where: { $0.taskType == .silenceCalibration })?.averageVolumeDb
        completedTasks.append(Self.analyzeTask(
            currentTask,
            frames: currentFrames,
            durationSeconds: duration,
            noiseFloorDb: noiseFloor
        ))
        beginTask(at: currentTaskIndex + 1)
    }

    private func recordFrame(_ frame: VoiceFrameSummary) {
        switch phase {
        case .running, .aiListening:
            break
        default:
            return
        }
        currentFrames.append(frame)
        liveLevel = Self.normalizedLevel(from: frame.averagePowerDb)
    }

    private func finishSession() {
        stopAudio()
        invalidateTimers()
        let duration = sessionStartedAt.map { Date().timeIntervalSince($0) } ?? totalTargetDurationSeconds
        phase = .finished(Self.makeResult(
            from: completedTasks,
            durationSeconds: duration,
            conversationExchanges: conversationExchanges,
            conversationSummary: conversationSummary
        ))
    }

    private func stopAudio() {
        stopSpeechRecognition(cancel: true)
        rawAudioDebugExporter.finishSession()
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startSpeechRecognition() {
        stopSpeechRecognition(cancel: true)
        currentTranscript = ""
        speechRecognitionGeneration += 1
        let generation = speechRecognitionGeneration
        startTranscriptionProvider(
            preferredSpeechTranscriptionProvider,
            generation: generation,
            allowsAppleFallback: true
        )
    }

    private var preferredSpeechTranscriptionProvider: VoiceSpeechTranscriptionProvider {
        // iOS 26 SpeechAnalyzer wins on latency + accuracy on A17/A18 Neural Engine.
        // Use it whenever available unless the user explicitly forced Apple Speech.
        if Bundle.main.voiceTranscriptionProviderPreference != .appleSpeech,
           let analyzer = appleSpeechAnalyzerProvider {
            return analyzer
        }

        switch Bundle.main.voiceTranscriptionProviderPreference {
        case .fluidAudio:
            #if canImport(FluidAudio)
            return fluidAudioSpeechTranscriptionProvider
            #else
            return appleSpeechTranscriptionProvider
            #endif
        case .appleSpeech:
            return appleSpeechTranscriptionProvider
        }
    }

    private func startTranscriptionProvider(
        _ provider: VoiceSpeechTranscriptionProvider,
        generation: Int,
        allowsAppleFallback: Bool
    ) {
        speechTranscriptionProvider = provider
        activeSpeechTranscriptionSource = provider.source
        provider.start(
            partialHandler: { [weak self, weak provider] transcript in
                DispatchQueue.main.async {
                    guard let self,
                          let provider,
                          self.speechRecognitionGeneration == generation,
                          self.speechTranscriptionProvider === provider
                    else { return }

                    let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !transcript.isEmpty {
                        self.currentTranscript = transcript
                    }
                }
            },
            endOfUtteranceHandler: { [weak self, weak provider] transcript in
                DispatchQueue.main.async {
                    guard let self,
                          let provider,
                          self.speechRecognitionGeneration == generation,
                          self.speechTranscriptionProvider === provider
                    else { return }

                    let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !transcript.isEmpty {
                        self.currentTranscript = transcript
                    }

                    if case .aiListening = self.phase {
                        self.completeCurrentConversationTurn()
                    }
                }
            },
            errorHandler: { [weak self, weak provider] _ in
                DispatchQueue.main.async {
                    guard let self,
                          let provider,
                          self.speechRecognitionGeneration == generation,
                          self.speechTranscriptionProvider === provider
                    else { return }

                    if allowsAppleFallback && provider.source != self.appleSpeechTranscriptionProvider.source {
                        self.startAppleSpeechFallback(generation: generation)
                    }
                }
            },
            completion: { [weak self, weak provider] result in
                DispatchQueue.main.async {
                    guard let self,
                          let provider,
                          self.speechRecognitionGeneration == generation,
                          self.speechTranscriptionProvider === provider
                    else { return }

                    switch result {
                    case .success:
                        break
                    case .failure:
                        if allowsAppleFallback && provider.source != self.appleSpeechTranscriptionProvider.source {
                            self.startAppleSpeechFallback(generation: generation)
                        } else {
                            self.speechTranscriptionProvider = nil
                            self.activeSpeechTranscriptionSource = "none"
                        }
                    }
                }
            }
        )
    }

    private func startAppleSpeechFallback(generation: Int) {
        let previousProvider = speechTranscriptionProvider
        speechTranscriptionProvider = nil
        previousProvider?.stop(cancel: true) { _ in }

        requestAppleSpeechRecognitionPermission { [weak self] granted, _ in
            guard let self,
                  self.speechRecognitionGeneration == generation,
                  granted
            else { return }

            self.startTranscriptionProvider(
                self.appleSpeechTranscriptionProvider,
                generation: generation,
                allowsAppleFallback: false
            )
        }
    }

    private func stopSpeechRecognition(cancel: Bool, completion: ((String?) -> Void)? = nil) {
        speechRecognitionGeneration += 1
        let provider = speechTranscriptionProvider
        speechTranscriptionProvider = nil
        if cancel {
            activeSpeechTranscriptionSource = "none"
        }
        guard let provider else {
            completion?(nil)
            return
        }

        provider.stop(cancel: cancel) { transcript in
            completion?(transcript)
        }
    }

    private func reset() {
        let fixedPlan = VoiceAIConversationBuilder.fixedPromptPlan()
        tasks = VoiceAIConversationBuilder.tasks(for: fixedPlan)
        promptTag = fixedPlan.promptTag
        activePromptVersion = VoiceAIConversationBuilder.fixedPromptVersion
        resetRecordingState()
    }

    private func resetRecordingState() {
        currentTaskIndex = 0
        currentTask = tasks[0]
        currentFrames.removeAll()
        completedTasks.removeAll()
        liveLevel = 0
        elapsedSeconds = 0
        taskStartedAt = nil
        sessionStartedAt = nil
        sessionSampleRate = 0
        sessionChannels = 1
        sessionMicrophoneRoute = "unknown"
        spokenPromptIds.removeAll()
        currentTranscript = ""
        conversationExchanges.removeAll()
        conversationSummary = nil
        conversationRecordedSeconds = 0
        conversationTurnStartedAt = nil
        conversationTurnFrameStartIndex = 0
        isCompletingConversationTurn = false
        isFinalizingTranscript = false
        stopSpeechRecognition(cancel: true)
        rawAudioDebugExporter.reset()
    }

    private func invalidateTimers() {
        countdownTimer?.invalidate()
        progressTimer?.invalidate()
        taskTimer?.invalidate()
        countdownTimer = nil
        progressTimer = nil
        taskTimer = nil
    }

    func makeSessionMetadata(result: VoiceTrackingResult, experimentTag: String) -> VoiceTrackingSession {
        VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: experimentTag,
            promptTag: promptTag,
            language: "en-US",
            promptVersion: activePromptVersion,
            deviceModel: UIDevice.current.model,
            osVersion: UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
            microphoneRoute: sessionMicrophoneRoute,
            sampleRate: sessionSampleRate,
            channels: sessionChannels,
            consentVersion: Self.consentVersion,
            rawAudioRetentionPolicy: Self.rawAudioRetentionPolicy,
            rawAudioDebugManifestPath: VoiceRawAudioDebugExportSettings.isAIUploadEnabled
                ? rawAudioDebugExporter.manifestURL?.path
                : nil,
            baselineVersion: "personal_median_mad_v1",
            featureExtractorVersion: Self.featureExtractorVersion,
            modelVersion: Self.modelVersion,
            result: result
        )
    }

    static func makeResult(
        from tasks: [VoiceTaskAnalysis],
        durationSeconds: TimeInterval,
        conversationExchanges: [VoiceConversationExchange] = [],
        conversationSummary: VoiceConversationSummary? = nil
    ) -> VoiceTrackingResult {
        let speechTasks = tasks.filter { $0.taskType != .silenceCalibration }
        let quality = average(tasks.map { $0.qualityScore }) ?? 0
        let usable = tasks.allSatisfy(\.usable)
        let issues = Array(Set(tasks.flatMap { $0.qualityIssues })).sorted()
        let averageVolume = average(speechTasks.map { $0.averageVolumeDb }) ?? -60
        let stdDev = average(speechTasks.map { $0.volumeStdDevDb }) ?? 0
        let silenceRatio = average(speechTasks.map { $0.silenceRatio }) ?? 1
        let peak = tasks.map { $0.peakVolumeDb }.max() ?? -60
        let eGeMAPS = aggregateEGeMAPS(from: speechTasks)
        let provisionalScore = calculateQualityOnlyScore(
            qualityScore: quality,
            volumeStdDevDb: stdDev,
            silenceRatio: silenceRatio,
            averageVolumeDb: averageVolume
        )

        return VoiceTrackingResult(
            completedAt: Date(),
            durationSeconds: durationSeconds,
            voiceScore: provisionalScore,
            voiceConfidence: usable ? "Low" : "Low",
            averageVolumeDb: averageVolume,
            volumeStdDevDb: stdDev,
            silenceRatio: silenceRatio,
            peakVolumeDb: peak,
            overallQualityScore: quality,
            usable: usable,
            qualityIssues: issues,
            taskAnalyses: tasks,
            conversationExchanges: conversationExchanges,
            conversationSummary: conversationSummary,
            eGeMAPS: eGeMAPS,
            baselineSessionsUsed: 0,
            baselineStatus: "building_baseline",
            topDrivers: usable ? ["Building your personal voice baseline."] : issues,
            featureExtractorVersion: featureExtractorVersion,
            modelVersion: modelVersion
        )
    }

    static func score(_ result: VoiceTrackingResult, against previousSessions: [VoiceTrackingSession]) -> VoiceTrackingResult {
        let usableBaseline = previousSessions
            .map(\.result)
            .filter { $0.usable && !$0.taskAnalyses.isEmpty }

        guard result.usable else {
            return result.scored(
                voiceScore: min(result.voiceScore, 50),
                confidence: "Low",
                baselineSessionsUsed: usableBaseline.count,
                baselineStatus: "recording_quality_low",
                topDrivers: result.qualityIssues
            )
        }

        guard usableBaseline.count >= 7 else {
            return result.scored(
                voiceScore: result.voiceScore,
                confidence: "Low",
                baselineSessionsUsed: usableBaseline.count,
                baselineStatus: "building_baseline",
                topDrivers: ["Building your voice baseline: \(usableBaseline.count) of 7 sessions collected."]
            )
        }

        let currentFeatures = baselineFeatures(from: result)
        var deviations: [(name: String, deviation: Double)] = []
        for (name, value) in currentFeatures {
            let baselineValues = usableBaseline.compactMap { baselineFeatures(from: $0)[name] }
            guard baselineValues.count >= 7 else { continue }
            let median = Self.median(baselineValues)
            let mad = Self.median(baselineValues.map { abs($0 - median) })
            let z = abs((value - median) / (1.4826 * mad + 0.001))
            deviations.append((name, min(z, 3)))
        }

        let voiceDeviation = weightedDeviation(deviations)
        let score = min(100, max(0, 100 - 20 * voiceDeviation))
        let confidence: String
        if usableBaseline.count >= 14 && result.overallQualityScore >= 0.8 {
            confidence = "High"
        } else if result.overallQualityScore >= 0.65 {
            confidence = "Medium"
        } else {
            confidence = "Low"
        }

        return result.scored(
            voiceScore: score,
            confidence: confidence,
            baselineSessionsUsed: usableBaseline.count,
            baselineStatus: "personal_baseline_active",
            topDrivers: deviations
                .sorted { $0.deviation > $1.deviation }
                .prefix(3)
                .map { driverLabel(for: $0.name, deviation: $0.deviation) }
        )
    }

    static func makeResult(from samples: [Double], durationSeconds: TimeInterval) -> VoiceTrackingResult {
        let frames = samples.map {
            VoiceFrameSummary(
                averagePowerDb: $0,
                peakAmplitude: 0,
                clippingPercentage: 0,
                zeroCrossingRate: 0,
                f0Hz: nil,
                hnrDb: nil
            )
        }
        let task = analyzeTask(
            VoiceTaskDefinition(
                type: .fixedReading,
                promptId: "legacy_single_task",
                title: "Voice check",
                instruction: "",
                targetDurationSeconds: durationSeconds,
                minimumUsableDurationSeconds: min(4, durationSeconds),
                allowsEarlyFinish: true
            ),
            frames: frames,
            durationSeconds: durationSeconds,
            noiseFloorDb: nil
        )
        return makeResult(from: [task], durationSeconds: durationSeconds)
    }

    static func analyzeTask(
        _ task: VoiceTaskDefinition,
        frames: [VoiceFrameSummary],
        durationSeconds: TimeInterval,
        noiseFloorDb: Double?
    ) -> VoiceTaskAnalysis {
        let dbValues = frames.map(\.averagePowerDb)
        let voiced = dbValues.filter { $0 > silenceThresholdDb }
        let analysisValues = task.type == .silenceCalibration ? dbValues : (voiced.isEmpty ? dbValues : voiced)
        let averageDb = average(analysisValues) ?? -80
        let stdDev = standardDeviation(analysisValues)
        let peakDb = dbValues.max() ?? -80
        let silenceRatio = dbValues.isEmpty ? 1 : Double(dbValues.filter { $0 <= silenceThresholdDb }.count) / Double(dbValues.count)
        let clipping = average(frames.map(\.clippingPercentage)) ?? 0
        let zcr = average(frames.map(\.zeroCrossingRate)) ?? 0
        let voicedRatio = dbValues.isEmpty ? 0 : Double(voiced.count) / Double(dbValues.count)
        let snr = noiseFloorDb.map { max(0, averageDb - $0) }
        let eGeMAPS = extractEGeMAPS(
            from: frames,
            durationSeconds: durationSeconds,
            fallbackAverageDb: averageDb,
            fallbackStdDevDb: stdDev
        )
        let issues = qualityIssues(
            task: task,
            durationSeconds: durationSeconds,
            silenceRatio: silenceRatio,
            clippingPercentage: clipping,
            snrDb: snr
        )
        let quality = qualityScore(
            durationSeconds: durationSeconds,
            minimumDuration: task.minimumUsableDurationSeconds,
            silenceRatio: silenceRatio,
            clippingPercentage: clipping,
            snrDb: snr
        )

        return VoiceTaskAnalysis(
            taskType: task.type,
            promptId: task.promptId,
            promptText: task.instruction,
            targetDurationSeconds: task.targetDurationSeconds,
            durationSeconds: durationSeconds,
            sampleCount: frames.count,
            averageVolumeDb: averageDb,
            volumeStdDevDb: stdDev,
            peakVolumeDb: peakDb,
            silenceRatio: silenceRatio,
            clippingPercentage: clipping,
            zeroCrossingRate: zcr,
            voicedFrameRatio: voicedRatio,
            snrDb: snr,
            eGeMAPS: eGeMAPS,
            qualityScore: quality,
            qualityIssues: issues,
            usable: issues.isEmpty || (quality >= 0.55 && !issues.contains("duration_too_short")),
            featureVersion: featureExtractorVersion
        )
    }

    static func calculateScore(volumeStdDevDb: Double, silenceRatio: Double, averageVolumeDb: Double) -> Double {
        calculateQualityOnlyScore(
            qualityScore: 1,
            volumeStdDevDb: volumeStdDevDb,
            silenceRatio: silenceRatio,
            averageVolumeDb: averageVolumeDb
        )
    }

    static func calculateQualityOnlyScore(
        qualityScore: Double,
        volumeStdDevDb: Double,
        silenceRatio: Double,
        averageVolumeDb: Double
    ) -> Double {
        let stabilityPenalty = volumeStdDevDb * 2
        let silencePenalty = silenceRatio * 45
        let quietPenalty = max(0, -38 - averageVolumeDb) * 1.5
        let clippingPenalty = max(0, averageVolumeDb + 8) * 1.5
        let qualityPenalty = (1 - qualityScore) * 35
        let raw = 100 - stabilityPenalty - silencePenalty - quietPenalty - clippingPenalty - qualityPenalty
        return min(100, max(0, raw))
    }

    static func frameSummary(from buffer: AVAudioPCMBuffer) -> VoiceFrameSummary? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        let channel = channelData[0]
        var sumSquares: Float = 0
        var peak: Float = 0
        var clippingCount = 0
        var zeroCrossings = 0
        var previous = channel[0]

        for frame in 0..<frameLength {
            let sample = channel[frame]
            sumSquares += sample * sample
            peak = max(peak, abs(sample))
            if abs(sample) >= 0.98 { clippingCount += 1 }
            if frame > 0 && ((sample >= 0 && previous < 0) || (sample < 0 && previous >= 0)) {
                zeroCrossings += 1
            }
            previous = sample
        }

        let rms = sqrt(sumSquares / Float(frameLength))
        let db = rms > 0 ? max(-80, Double(20 * log10(rms))) : -80
        let pitch = estimatePitchAndHarmonics(channel: channel, frameLength: frameLength, sampleRate: buffer.format.sampleRate)
        return VoiceFrameSummary(
            averagePowerDb: db,
            peakAmplitude: Double(peak),
            clippingPercentage: Double(clippingCount) / Double(frameLength) * 100,
            zeroCrossingRate: Double(zeroCrossings) / Double(max(1, frameLength - 1)),
            f0Hz: pitch.f0Hz,
            hnrDb: pitch.hnrDb
        )
    }

    private static func estimatePitchAndHarmonics(
        channel: UnsafePointer<Float>,
        frameLength: Int,
        sampleRate: Double
    ) -> (f0Hz: Double?, hnrDb: Double?) {
        guard frameLength > 0, sampleRate > 0 else { return (nil, nil) }
        let minLag = max(1, Int(sampleRate / 500))
        let maxLag = min(frameLength / 2, Int(sampleRate / 70))
        guard minLag < maxLag else { return (nil, nil) }

        var energy = 0.0
        for i in 0..<frameLength {
            energy += Double(channel[i] * channel[i])
        }
        guard energy > 0.000001 else { return (nil, nil) }

        var bestLag = minLag
        var bestCorrelation = 0.0
        for lag in minLag...maxLag {
            var numerator = 0.0
            var delayedEnergy = 0.0
            let limit = frameLength - lag
            for i in 0..<limit {
                let current = Double(channel[i])
                let delayed = Double(channel[i + lag])
                numerator += current * delayed
                delayedEnergy += delayed * delayed
            }
            let normalized = numerator / sqrt(max(energy * delayedEnergy, 0.000001))
            if normalized > bestCorrelation {
                bestCorrelation = normalized
                bestLag = lag
            }
        }

        guard bestCorrelation > 0.35 else { return (nil, nil) }
        let harmonic = min(0.99, max(0.001, bestCorrelation))
        let noise = max(0.001, 1 - harmonic)
        return (sampleRate / Double(bestLag), 10 * log10(harmonic / noise))
    }

    static func averagePowerDb(from buffer: AVAudioPCMBuffer) -> Double? {
        frameSummary(from: buffer)?.averagePowerDb
    }

    static func normalizedLevel(from db: Double) -> Double {
        min(1, max(0, (db + 60) / 60))
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count))
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func qualityIssues(
        task: VoiceTaskDefinition,
        durationSeconds: TimeInterval,
        silenceRatio: Double,
        clippingPercentage: Double,
        snrDb: Double?
    ) -> [String] {
        var issues: [String] = []
        if durationSeconds < task.minimumUsableDurationSeconds {
            issues.append("duration_too_short")
        }
        if task.type == .silenceCalibration {
            if silenceRatio < 0.8 {
                issues.append("speech_during_silence_calibration")
            }
            return issues
        }
        if silenceRatio > 0.55 {
            issues.append("too_much_silence")
        }
        if clippingPercentage > 1 {
            issues.append("clipping_detected")
        }
        if let snrDb = snrDb, snrDb < 10 {
            issues.append("snr_low")
        }
        return issues
    }

    private static func qualityScore(
        durationSeconds: TimeInterval,
        minimumDuration: TimeInterval,
        silenceRatio: Double,
        clippingPercentage: Double,
        snrDb: Double?
    ) -> Double {
        let durationScore = min(1, max(0, durationSeconds / minimumDuration))
        let silenceScore = max(0, 1 - max(0, silenceRatio - 0.2) / 0.6)
        let clippingScore = max(0, 1 - clippingPercentage / 1)
        let snrScore = snrDb.map { min(1, max(0, $0 / 20)) } ?? 0.8
        return min(1, max(0, durationScore * 0.35 + silenceScore * 0.25 + clippingScore * 0.20 + snrScore * 0.20))
    }

    private static func baselineFeatures(from result: VoiceTrackingResult) -> [String: Double] {
        let vowelTasks = result.taskAnalyses.filter {
            $0.taskType == .sustainedVowelAFirst || $0.taskType == .sustainedVowelASecond
        }
        let speechTasks = result.taskAnalyses.filter {
            $0.taskType == .counting || $0.taskType == .fixedReading || $0.taskType == .guidedConversation
        }
        return [
            "vowel_loudness_stability": average(vowelTasks.map(\.volumeStdDevDb)) ?? result.volumeStdDevDb,
            "speech_pause_ratio": average(speechTasks.map(\.silenceRatio)) ?? result.silenceRatio,
            "speech_energy": average(speechTasks.map(\.averageVolumeDb)) ?? result.averageVolumeDb,
            "speech_energy_variability": average(speechTasks.map(\.volumeStdDevDb)) ?? result.volumeStdDevDb,
            "quality": result.overallQualityScore,
            "loudness_mean_proxy": result.eGeMAPS?.loudnessMeanDb ?? result.averageVolumeDb,
            "loudness_variability_proxy": result.eGeMAPS?.loudnessStdDevDb ?? result.volumeStdDevDb,
            "spectral_flux_proxy": result.eGeMAPS?.spectralFlux ?? 0,
            "voiced_segment_rate_proxy": result.eGeMAPS?.voicedSegmentsPerSecond ?? 0,
            "mean_voiced_length_proxy": result.eGeMAPS?.meanVoicedSegmentLengthSeconds ?? 0
        ]
    }

    private static func weightedDeviation(_ deviations: [(name: String, deviation: Double)]) -> Double {
        guard !deviations.isEmpty else { return 0 }
        let weights: [String: Double] = [
            "vowel_loudness_stability": 0.20,
            "speech_pause_ratio": 0.18,
            "speech_energy": 0.14,
            "speech_energy_variability": 0.14,
            "quality": 0.12,
            "loudness_mean_proxy": 0.08,
            "loudness_variability_proxy": 0.06,
            "spectral_flux_proxy": 0.04,
            "voiced_segment_rate_proxy": 0.02,
            "mean_voiced_length_proxy": 0.02
        ]
        let weighted = deviations.reduce((score: 0.0, weight: 0.0)) { partial, item in
            guard let weight = weights[item.name] else { return partial }
            return (partial.score + item.deviation * weight, partial.weight + weight)
        }
        return weighted.weight > 0 ? weighted.score / weighted.weight : 0
    }

    private static func driverLabel(for featureName: String, deviation: Double) -> String {
        let amount: String
        if deviation >= 2 { amount = "large" }
        else if deviation >= 1 { amount = "moderate" }
        else { amount = "mild" }

        switch featureName {
        case "vowel_loudness_stability":
            return "\(amount.capitalized) change in sustained-vowel stability versus baseline."
        case "speech_pause_ratio":
            return "\(amount.capitalized) change in pause time versus baseline."
        case "speech_energy":
            return "\(amount.capitalized) change in speaking energy versus baseline."
        case "speech_energy_variability":
            return "\(amount.capitalized) change in speech rhythm versus baseline."
        case "quality":
            return "\(amount.capitalized) change in recording quality versus baseline."
        case "loudness_mean_proxy":
            return "\(amount.capitalized) change in loudness proxy versus baseline."
        case "loudness_variability_proxy":
            return "\(amount.capitalized) change in loudness variability versus baseline."
        case "spectral_flux_proxy":
            return "\(amount.capitalized) change in energy movement proxy versus baseline."
        case "voiced_segment_rate_proxy":
            return "\(amount.capitalized) change in voiced segment rate versus baseline."
        case "mean_voiced_length_proxy":
            return "\(amount.capitalized) change in voiced segment length versus baseline."
        default:
            return "\(amount.capitalized) voice-signal change versus baseline."
        }
    }

    private static func aggregateEGeMAPS(from tasks: [VoiceTaskAnalysis]) -> VoiceEGeMAPSFeatureSet? {
        let featureSets = tasks.compactMap(\.eGeMAPS)
        guard !featureSets.isEmpty else { return nil }
        return VoiceEGeMAPSFeatureSet(
            loudnessMeanDb: average(featureSets.map(\.loudnessMeanDb)) ?? -80,
            loudnessStdDevDb: average(featureSets.map(\.loudnessStdDevDb)) ?? 0,
            f0MeanHz: average(featureSets.compactMap(\.f0MeanHz)),
            f0StdDevHz: average(featureSets.compactMap(\.f0StdDevHz)),
            jitterLocalPercent: average(featureSets.compactMap(\.jitterLocalPercent)),
            shimmerLocalDb: average(featureSets.compactMap(\.shimmerLocalDb)),
            hnrMeanDb: average(featureSets.compactMap(\.hnrMeanDb)),
            alphaRatioDb: average(featureSets.map(\.alphaRatioDb)) ?? 0,
            hammarbergIndexDb: average(featureSets.map(\.hammarbergIndexDb)) ?? 0,
            spectralFlux: average(featureSets.map(\.spectralFlux)) ?? 0,
            slopeV0: average(featureSets.map(\.slopeV0)) ?? 0,
            slopeUV0: average(featureSets.map(\.slopeUV0)) ?? 0,
            mfcc1Mean: average(featureSets.map(\.mfcc1Mean)) ?? 0,
            mfcc2Mean: average(featureSets.map(\.mfcc2Mean)) ?? 0,
            mfcc3Mean: average(featureSets.map(\.mfcc3Mean)) ?? 0,
            voicedSegmentsPerSecond: average(featureSets.map(\.voicedSegmentsPerSecond)) ?? 0,
            meanVoicedSegmentLengthSeconds: average(featureSets.map(\.meanVoicedSegmentLengthSeconds)) ?? 0
        )
    }

    private static func extractEGeMAPS(
        from frames: [VoiceFrameSummary],
        durationSeconds: TimeInterval,
        fallbackAverageDb: Double,
        fallbackStdDevDb: Double
    ) -> VoiceEGeMAPSFeatureSet {
        let voicedFrames = frames.filter { $0.averagePowerDb > silenceThresholdDb }
        let analysisFrames = voicedFrames.isEmpty ? frames : voicedFrames
        let dbValues = analysisFrames.map(\.averagePowerDb)
        let zcrValues = analysisFrames.map(\.zeroCrossingRate)
        let f0Values = analysisFrames.compactMap(\.f0Hz)
        let hnrValues = analysisFrames.compactMap(\.hnrDb)
        let adjacentPitchDiffs = zip(f0Values.dropFirst(), f0Values).map { abs($0 - $1) }
        let f0Mean = average(f0Values)
        let jitter = f0Mean.flatMap { mean in
            mean > 0 ? average(adjacentPitchDiffs).map { $0 / mean * 100 } : nil
        }
        let shimmer = average(zip(dbValues.dropFirst(), dbValues).map { abs($0 - $1) })
        let spectralFlux = average(zip(dbValues.dropFirst(), dbValues).map { abs($0 - $1) / 80 }) ?? 0
        let zcrMean = average(zcrValues) ?? 0
        let voicedDurations = voicedSegmentDurations(from: frames, durationSeconds: durationSeconds)

        let loudnessStdDev = dbValues.count > 1 ? standardDeviation(dbValues) : fallbackStdDevDb

        return VoiceEGeMAPSFeatureSet(
            loudnessMeanDb: average(dbValues) ?? fallbackAverageDb,
            loudnessStdDevDb: loudnessStdDev,
            f0MeanHz: f0Mean,
            f0StdDevHz: f0Values.count > 1 ? standardDeviation(f0Values) : nil,
            jitterLocalPercent: jitter,
            shimmerLocalDb: shimmer,
            hnrMeanDb: average(hnrValues),
            alphaRatioDb: (zcrMean - 0.08) * 80,
            hammarbergIndexDb: max(0, 24 - zcrMean * 120),
            spectralFlux: spectralFlux,
            slopeV0: -zcrMean * 30,
            slopeUV0: -(average(frames.map(\.zeroCrossingRate)) ?? zcrMean) * 24,
            mfcc1Mean: (average(dbValues) ?? fallbackAverageDb) / 10,
            mfcc2Mean: zcrMean * 20,
            mfcc3Mean: (f0Mean ?? 0) / 100,
            voicedSegmentsPerSecond: durationSeconds > 0 ? Double(voicedDurations.count) / durationSeconds : 0,
            meanVoicedSegmentLengthSeconds: average(voicedDurations) ?? 0
        )
    }

    private static func voicedSegmentDurations(from frames: [VoiceFrameSummary], durationSeconds: TimeInterval) -> [Double] {
        guard !frames.isEmpty, durationSeconds > 0 else { return [] }
        let frameDuration = durationSeconds / Double(frames.count)
        var segments: [Double] = []
        var current = 0.0
        for frame in frames {
            if frame.averagePowerDb > silenceThresholdDb {
                current += frameDuration
            } else if current > 0 {
                segments.append(current)
                current = 0
            }
        }
        if current > 0 { segments.append(current) }
        return segments
    }
}

struct VoiceFrameSummary {
    let averagePowerDb: Double
    let peakAmplitude: Double
    let clippingPercentage: Double
    let zeroCrossingRate: Double
    let f0Hz: Double?
    let hnrDb: Double?
}
