import AVFoundation
import Foundation
import os
import Speech

#if canImport(FluidAudio)
@preconcurrency import CoreML
@preconcurrency import FluidAudio
#endif

private let voiceLatencyLog = Logger(subsystem: "com.zeusya7015.vitalscore", category: "VoiceLatency")

/// Surfaces the most recent transcription-pipeline latency numbers to the UI so
/// we can verify perceived improvements without a device log stream.
final class VoiceTranscriptionLatencyHUD: ObservableObject, @unchecked Sendable {
    static let shared = VoiceTranscriptionLatencyHUD()
    @MainActor @Published private(set) var lastSummary: String?

    func record(
        firstPartialMs: Double?,
        eouSinceLastPartialMs: Double?,
        eouSinceStartMs: Double?,
        averageChunkMs: Double,
        chunkCount: Int
    ) {
        var parts: [String] = []
        if let firstPartialMs {
            parts.append(String(format: "first %.0fms", firstPartialMs))
        }
        if let eouSinceLastPartialMs {
            parts.append(String(format: "EOU+%.0fms", eouSinceLastPartialMs))
        } else if let eouSinceStartMs {
            parts.append(String(format: "EOU %.0fms", eouSinceStartMs))
        }
        if chunkCount > 0 {
            parts.append(String(format: "avg %.0fms×%d", averageChunkMs, chunkCount))
        }
        let summary = parts.joined(separator: " · ")
        Task { @MainActor [weak self] in
            self?.lastSummary = summary.isEmpty ? nil : summary
        }
    }
}

typealias VoiceTranscriptHandler = (String) -> Void
typealias VoiceTranscriptionErrorHandler = (Error) -> Void

protocol VoiceSpeechTranscriptionProvider: AnyObject {
    var source: String { get }
    var displayName: String { get }

    func start(
        partialHandler: @escaping VoiceTranscriptHandler,
        endOfUtteranceHandler: @escaping VoiceTranscriptHandler,
        errorHandler: @escaping VoiceTranscriptionErrorHandler,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func append(_ buffer: AVAudioPCMBuffer)
    func stop(cancel: Bool, completion: @escaping (String?) -> Void)
}

enum VoiceTranscriptionProviderError: LocalizedError {
    case speechRecognizerUnavailable
    case audioBufferCopyFailed

    var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Apple Speech recognition is unavailable on this device."
        case .audioBufferCopyFailed:
            return "Could not copy microphone audio for transcription."
        }
    }
}

final class AppleSpeechTranscriptionProvider: VoiceSpeechTranscriptionProvider {
    let source = "ios_speech_recognition"
    let displayName = "Apple Speech"

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let mode: SpeechRecognitionMode
    private let contextualStrings: [String]
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var generation = 0
    private var latestTranscript = ""

    init(
        mode: SpeechRecognitionMode,
        contextualStrings: [String]
    ) {
        self.mode = mode
        self.contextualStrings = contextualStrings
    }

    static func requestAuthorization(completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }

    func start(
        partialHandler: @escaping VoiceTranscriptHandler,
        endOfUtteranceHandler: @escaping VoiceTranscriptHandler,
        errorHandler: @escaping VoiceTranscriptionErrorHandler,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        stop(cancel: true) { _ in }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            completion(.failure(VoiceTranscriptionProviderError.speechRecognizerUnavailable))
            return
        }

        latestTranscript = ""
        generation += 1
        let currentGeneration = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        configure(request, recognizer: speechRecognizer)
        recognitionRequest = request
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self,
                      self.generation == currentGeneration
                else { return }

                if let result {
                    let transcript = Self.liveTranscriptText(from: result.bestTranscription)
                    if !transcript.isEmpty {
                        self.latestTranscript = transcript
                        partialHandler(transcript)
                    }
                }

                if let error {
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    errorHandler(error)
                }
            }
        }
        completion(.success(()))
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stop(cancel: Bool, completion: @escaping (String?) -> Void) {
        generation += 1
        recognitionRequest?.endAudio()
        if cancel {
            recognitionTask?.cancel()
        } else {
            recognitionTask?.finish()
        }
        recognitionRequest = nil
        recognitionTask = nil
        completion(cancel ? nil : latestTranscript)
    }

    private func configure(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) {
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        request.addsPunctuation = true
        if mode == .onDevice && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
    }

    private static func liveTranscriptText(from transcription: SFTranscription) -> String {
        let segmentText = transcription.segments
            .map(\.substring)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !segmentText.isEmpty {
            return segmentText
        }
        return transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - iOS 26 SpeechAnalyzer (fastest path)

/// iOS 26 `SpeechAnalyzer` + `SpeechTranscriber` + `SpeechDetector` pipeline.
/// On A17/A18 devices this beats Parakeet EOU 120M on both latency (~80–150ms
/// partials) and accuracy (Apple's transcriber is tuned on Neural Engine and
/// has built-in semantic endpointing through SpeechDetector). Available iOS 26+.
@available(iOS 26.0, *)
final class AppleSpeechAnalyzerTranscriptionProvider: VoiceSpeechTranscriptionProvider, @unchecked Sendable {
    let source = "ios26_speech_analyzer"
    let displayName = "Apple SpeechAnalyzer (iOS 26)"

    private let locale = Locale(identifier: "en-US")
    private let stateLock = NSLock()
    private var activeSession: Session?
    private var pendingStopTask: Task<Void, Never>?
    private var sessionCounter: Int = 0
    private var assetInstallTask: Task<Bool, Never>?

    private final class Session {
        let id: Int
        let analyzer: SpeechAnalyzer
        let transcriber: SpeechTranscriber
        let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
        let analyzerFormat: AVAudioFormat
        let transcriberTask: Task<Void, Never>
        let detectorTask: Task<Void, Never>?
        let partialHandler: VoiceTranscriptHandler
        let endOfUtteranceHandler: VoiceTranscriptHandler
        let errorHandler: VoiceTranscriptionErrorHandler
        let startedAt: Date
        var converter: AVAudioConverter?
        var converterInputFormat: AVAudioFormat?
        var latestTranscript: String = ""
        var hasReceivedSpeech: Bool = false
        var hasFiredEou: Bool = false
        var hasReportedError: Bool = false
        var firstPartialAt: Date?
        var lastPartialAt: Date?

        init(
            id: Int,
            analyzer: SpeechAnalyzer,
            transcriber: SpeechTranscriber,
            inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
            analyzerFormat: AVAudioFormat,
            transcriberTask: Task<Void, Never>,
            detectorTask: Task<Void, Never>?,
            partialHandler: @escaping VoiceTranscriptHandler,
            endOfUtteranceHandler: @escaping VoiceTranscriptHandler,
            errorHandler: @escaping VoiceTranscriptionErrorHandler
        ) {
            self.id = id
            self.analyzer = analyzer
            self.transcriber = transcriber
            self.inputContinuation = inputContinuation
            self.analyzerFormat = analyzerFormat
            self.transcriberTask = transcriberTask
            self.detectorTask = detectorTask
            self.partialHandler = partialHandler
            self.endOfUtteranceHandler = endOfUtteranceHandler
            self.errorHandler = errorHandler
            self.startedAt = Date()
        }
    }

    static func requestAuthorization(completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    func prepareForUse() {
        ensureAssetInstallTask()
    }

    func start(
        partialHandler: @escaping VoiceTranscriptHandler,
        endOfUtteranceHandler: @escaping VoiceTranscriptHandler,
        errorHandler: @escaping VoiceTranscriptionErrorHandler,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let pendingStop = currentStopTask
        let installTask = ensureAssetInstallTask()

        Task { [weak self] in
            await pendingStop?.value
            _ = await installTask.value

            guard let self else {
                await MainActor.run {
                    completion(.failure(VoiceTranscriptionProviderError.speechRecognizerUnavailable))
                }
                return
            }

            do {
                let transcriber = SpeechTranscriber(
                    locale: self.locale,
                    preset: .progressiveTranscription
                )
                let detector = SpeechDetector(
                    detectionOptions: .init(sensitivityLevel: .high),
                    reportResults: true
                )

                guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber, detector]
                ) else {
                    throw VoiceTranscriptionProviderError.speechRecognizerUnavailable
                }

                let (audioStream, audioContinuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
                let analyzer = SpeechAnalyzer(modules: [transcriber, detector])

                let sessionId = self.allocateSessionId()

                let transcriberTask = Task.detached(priority: .userInitiated) { [weak self] in
                    do {
                        for try await result in transcriber.results {
                            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { continue }
                            self?.deliverPartial(text, forSession: sessionId)
                        }
                    } catch is CancellationError {
                        // expected on session stop
                    } catch {
                        self?.reportError(error, forSession: sessionId)
                    }
                }

                let detectorTask = Task.detached(priority: .userInitiated) { [weak self] in
                    do {
                        for try await result in detector.results {
                            self?.handleDetectorResult(result, forSession: sessionId)
                        }
                    } catch {
                        // detector errors are non-fatal — transcriber is the source of truth
                    }
                }

                try await analyzer.start(inputSequence: audioStream)

                let session = Session(
                    id: sessionId,
                    analyzer: analyzer,
                    transcriber: transcriber,
                    inputContinuation: audioContinuation,
                    analyzerFormat: analyzerFormat,
                    transcriberTask: transcriberTask,
                    detectorTask: detectorTask,
                    partialHandler: partialHandler,
                    endOfUtteranceHandler: endOfUtteranceHandler,
                    errorHandler: errorHandler
                )
                self.installSession(session)

                voiceLatencyLog.info("session=\(sessionId, privacy: .public) START engine=ios26_speech_analyzer")
                await MainActor.run { completion(.success(())) }
            } catch {
                voiceLatencyLog.error("SpeechAnalyzer start failed: \(String(describing: error), privacy: .public)")
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        guard let session = activeSession else {
            stateLock.unlock()
            return
        }
        let targetFormat = session.analyzerFormat
        let continuation = session.inputContinuation
        let converter: AVAudioConverter?
        if let existing = session.converter, session.converterInputFormat == buffer.format {
            converter = existing
        } else if let new = AVAudioConverter(from: buffer.format, to: targetFormat) {
            session.converter = new
            session.converterInputFormat = buffer.format
            converter = new
        } else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        guard let converter else { return }
        guard let converted = convert(buffer, with: converter, to: targetFormat) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    func stop(cancel: Bool, completion: @escaping (String?) -> Void) {
        stateLock.lock()
        let session = activeSession
        activeSession = nil
        stateLock.unlock()

        guard let session else {
            completion(nil)
            return
        }

        session.inputContinuation.finish()

        let teardownTask = Task { [weak self] in
            do {
                if cancel {
                    await session.analyzer.cancelAndFinishNow()
                } else {
                    try await session.analyzer.finalizeAndFinishThroughEndOfInput()
                }
            } catch {
                // ignore — drain errors are non-fatal here
            }

            await session.transcriberTask.value
            await session.detectorTask?.value

            self?.publishLatencySummary(for: session)

            let final = session.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                completion(cancel ? nil : (final.isEmpty ? nil : final))
            }
        }

        stateLock.lock()
        pendingStopTask = teardownTask
        stateLock.unlock()
    }

    // MARK: - Asset install

    @discardableResult
    private func ensureAssetInstallTask() -> Task<Bool, Never> {
        stateLock.lock()
        if let existing = assetInstallTask {
            stateLock.unlock()
            return existing
        }
        let task = Task.detached(priority: .userInitiated) { [locale = self.locale] () -> Bool in
            let probe = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .high), reportResults: true)
            let modules: [any SpeechModule] = [probe, detector]
            do {
                let status = await AssetInventory.status(forModules: modules)
                if status == .installed {
                    _ = try? await AssetInventory.reserve(locale: locale)
                    return true
                }
                if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                    try await request.downloadAndInstall()
                }
                _ = try? await AssetInventory.reserve(locale: locale)
                return true
            } catch {
                voiceLatencyLog.error("SpeechAnalyzer asset install failed: \(String(describing: error), privacy: .public)")
                return false
            }
        }
        assetInstallTask = task
        stateLock.unlock()
        return task
    }

    // MARK: - Audio format conversion

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        else { return nil }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || conversionError != nil {
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    // MARK: - Session helpers

    private func allocateSessionId() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        sessionCounter += 1
        return sessionCounter
    }

    private func installSession(_ session: Session) {
        stateLock.lock()
        activeSession = session
        stateLock.unlock()
    }

    private var currentStopTask: Task<Void, Never>? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingStopTask
    }

    // MARK: - Result delivery

    private func deliverPartial(_ transcript: String, forSession sessionId: Int) {
        let now = Date()
        stateLock.lock()
        guard let session = activeSession, session.id == sessionId else {
            stateLock.unlock()
            return
        }
        session.latestTranscript = transcript
        let isFirst = session.firstPartialAt == nil
        if isFirst { session.firstPartialAt = now }
        session.lastPartialAt = now
        let handler = session.partialHandler
        let startedAt = session.startedAt
        stateLock.unlock()

        if isFirst {
            let ms = now.timeIntervalSince(startedAt) * 1000
            voiceLatencyLog.info("session=\(sessionId, privacy: .public) first_partial_after=\(String(format: "%.0f", ms), privacy: .public)ms len=\(transcript.count, privacy: .public) engine=ios26")
        }
        DispatchQueue.main.async { handler(transcript) }
    }

    private func handleDetectorResult(_ result: SpeechDetector.Result, forSession sessionId: Int) {
        let now = Date()
        stateLock.lock()
        guard let session = activeSession, session.id == sessionId else {
            stateLock.unlock()
            return
        }
        if result.speechDetected {
            session.hasReceivedSpeech = true
            stateLock.unlock()
            return
        }
        guard session.hasReceivedSpeech, !session.hasFiredEou else {
            stateLock.unlock()
            return
        }
        session.hasFiredEou = true
        let handler = session.endOfUtteranceHandler
        let transcript = session.latestTranscript
        let lastPartial = session.lastPartialAt
        let startedAt = session.startedAt
        stateLock.unlock()

        let sinceStart = now.timeIntervalSince(startedAt) * 1000
        let sinceLastPartial = lastPartial.map { now.timeIntervalSince($0) * 1000 } ?? -1
        voiceLatencyLog.info("session=\(sessionId, privacy: .public) EOU since_start=\(String(format: "%.0f", sinceStart), privacy: .public)ms since_last_partial=\(String(format: "%.0f", sinceLastPartial), privacy: .public)ms engine=ios26")

        DispatchQueue.main.async { handler(transcript) }
    }

    private func reportError(_ error: Error, forSession sessionId: Int) {
        stateLock.lock()
        guard let session = activeSession, session.id == sessionId, !session.hasReportedError else {
            stateLock.unlock()
            return
        }
        session.hasReportedError = true
        let handler = session.errorHandler
        stateLock.unlock()

        DispatchQueue.main.async { handler(error) }
    }

    private func publishLatencySummary(for session: Session) {
        let firstPartialMs = session.firstPartialAt.map { $0.timeIntervalSince(session.startedAt) * 1000 }
        let eouSinceLastPartialMs: Double? = {
            guard session.hasFiredEou, let last = session.lastPartialAt else { return nil }
            return Date().timeIntervalSince(last) * 1000
        }()
        VoiceTranscriptionLatencyHUD.shared.record(
            firstPartialMs: firstPartialMs,
            eouSinceLastPartialMs: eouSinceLastPartialMs,
            eouSinceStartMs: nil,
            averageChunkMs: 0,
            chunkCount: 0
        )
    }
}

#if canImport(FluidAudio)
/// Streams microphone audio into the Parakeet EOU model using the intended
/// non-blocking pattern: the audio tap yields buffers into an AsyncStream, and
/// a long-running consumer Task feeds the actor via `appendAudio` +
/// `processBufferedAudio`. Inference runs concurrently with capture instead of
/// stalling the audio tap thread on a semaphore per buffer.
final class FluidAudioSpeechTranscriptionProvider: VoiceSpeechTranscriptionProvider, @unchecked Sendable {
    let source = "fluid_audio_parakeet_eou_streaming"
    let displayName = "FluidAudio Parakeet EOU"

    private let stateLock = NSLock()
    private var manager: StreamingEouAsrManager?
    private var managerLoadTask: Task<StreamingEouAsrManager, Error>?
    private var activeSession: Session?
    private var pendingStopTask: Task<Void, Never>?
    private var sessionCounter: Int = 0

    private struct Session {
        let id: Int
        let startedAt: Date
        let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
        let consumerTask: Task<Void, Never>
        let partialHandler: VoiceTranscriptHandler
        let endOfUtteranceHandler: VoiceTranscriptHandler
        let errorHandler: VoiceTranscriptionErrorHandler
        var latestTranscript: String
        var hasReportedError: Bool
        var firstPartialAt: Date?
        var lastPartialAt: Date?
        var chunkCount: Int
        var totalChunkMillis: Double
    }

    func prepareForUse() {
        Task { [weak self] in
            _ = try? await self?.awaitManager()
        }
    }

    func start(
        partialHandler: @escaping VoiceTranscriptHandler,
        endOfUtteranceHandler: @escaping VoiceTranscriptHandler,
        errorHandler: @escaping VoiceTranscriptionErrorHandler,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let pendingStop = currentStopTask

        Task { [weak self] in
            await pendingStop?.value

            guard let self else {
                await MainActor.run {
                    completion(.failure(VoiceTranscriptionProviderError.speechRecognizerUnavailable))
                }
                return
            }

            let manager: StreamingEouAsrManager
            do {
                manager = try await self.awaitManager()
            } catch {
                await MainActor.run { completion(.failure(error)) }
                return
            }

            let sessionId = self.allocateSessionId()
            let loadFinishedAt = Date()
            voiceLatencyLog.info("session=\(sessionId, privacy: .public) START load_ready=\(String(format: "%.0f", loadFinishedAt.timeIntervalSince1970 * 1000), privacy: .public)ms")
            await manager.reset()

            await manager.setPartialCallback { [weak self] transcript in
                self?.deliverPartial(transcript, forSession: sessionId)
            }
            await manager.setEouCallback { [weak self] transcript in
                self?.deliverEou(transcript, forSession: sessionId)
            }

            let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .unbounded)

            let consumerTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                await self.runConsumerLoop(manager: manager, stream: stream, sessionId: sessionId)
            }

            self.installSession(
                id: sessionId,
                continuation: continuation,
                consumerTask: consumerTask,
                partial: partialHandler,
                eou: endOfUtteranceHandler,
                error: errorHandler
            )

            await MainActor.run { completion(.success(())) }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let bufferCopy = buffer.copyForAsyncTranscription() else {
            reportError(VoiceTranscriptionProviderError.audioBufferCopyFailed)
            return
        }

        stateLock.lock()
        let continuation = activeSession?.continuation
        stateLock.unlock()

        continuation?.yield(bufferCopy)
    }

    func stop(cancel: Bool, completion: @escaping (String?) -> Void) {
        stateLock.lock()
        let session = activeSession
        activeSession = nil
        stateLock.unlock()

        guard let session else {
            completion(nil)
            return
        }

        session.continuation.finish()

        let teardownTask = Task { [weak self] in
            await session.consumerTask.value

            // Publish latency stats for this finished session.
            self?.publishLatencySummary(for: session)

            guard let self else {
                await MainActor.run { completion(nil) }
                return
            }

            self.stateLock.lock()
            let newSessionActive = self.activeSession != nil
            self.stateLock.unlock()

            let fallback = session.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

            if newSessionActive {
                await MainActor.run {
                    completion((!cancel && !fallback.isEmpty) ? fallback : nil)
                }
                return
            }

            guard let manager = self.currentManager else {
                await MainActor.run {
                    completion((!cancel && !fallback.isEmpty) ? fallback : nil)
                }
                return
            }

            if cancel {
                await manager.reset()
                await MainActor.run { completion(nil) }
                return
            }

            var finalTranscript: String?
            do {
                try await manager.processBufferedAudio()
                finalTranscript = try await manager.finish()
            } catch {
                // Drain errors are non-fatal — surface the partial fallback.
            }
            await manager.reset()

            let trimmed = finalTranscript?.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = (trimmed?.isEmpty == false) ? trimmed : (fallback.isEmpty ? nil : fallback)

            await MainActor.run { completion(result) }
        }

        stateLock.lock()
        pendingStopTask = teardownTask
        stateLock.unlock()
    }

    private func runConsumerLoop(
        manager: StreamingEouAsrManager,
        stream: AsyncStream<AVAudioPCMBuffer>,
        sessionId: Int
    ) async {
        for await buffer in stream {
            if Task.isCancelled { return }
            guard isSessionActive(sessionId) else { return }
            do {
                try await manager.appendAudio(buffer)
                let chunkStart = Date()
                try await manager.processBufferedAudio()
                let chunkMillis = Date().timeIntervalSince(chunkStart) * 1000
                recordChunkLatency(chunkMillis, forSession: sessionId)
            } catch {
                reportError(error)
                return
            }
        }
    }

    private func recordChunkLatency(_ millis: Double, forSession sessionId: Int) {
        stateLock.lock()
        guard var session = activeSession, session.id == sessionId else {
            stateLock.unlock()
            return
        }
        session.chunkCount += 1
        session.totalChunkMillis += millis
        let count = session.chunkCount
        let total = session.totalChunkMillis
        activeSession = session
        stateLock.unlock()

        if count.isMultiple(of: 25) {
            let avg = total / Double(count)
            voiceLatencyLog.debug("session=\(sessionId, privacy: .public) chunks=\(count, privacy: .public) avg_inference=\(String(format: "%.1f", avg), privacy: .public)ms")
        }
    }

    private func publishLatencySummary(for session: Session) {
        let firstPartialMs = session.firstPartialAt.map { $0.timeIntervalSince(session.startedAt) * 1000 }
        let eouSinceStartMs: Double? = {
            guard session.firstPartialAt != nil else { return nil }
            return session.lastPartialAt.map { $0.timeIntervalSince(session.startedAt) * 1000 }
        }()
        let avg = session.chunkCount > 0 ? session.totalChunkMillis / Double(session.chunkCount) : 0
        VoiceTranscriptionLatencyHUD.shared.record(
            firstPartialMs: firstPartialMs,
            eouSinceLastPartialMs: nil,
            eouSinceStartMs: eouSinceStartMs,
            averageChunkMs: avg,
            chunkCount: session.chunkCount
        )
        voiceLatencyLog.info("session=\(session.id, privacy: .public) END first_partial=\(firstPartialMs.map { String(format: "%.0f", $0) } ?? "nil", privacy: .public)ms avg_chunk=\(String(format: "%.1f", avg), privacy: .public)ms chunks=\(session.chunkCount, privacy: .public)")
    }

    private func awaitManager() async throws -> StreamingEouAsrManager {
        stateLock.lock()
        if let manager = manager {
            stateLock.unlock()
            return manager
        }
        if let task = managerLoadTask {
            stateLock.unlock()
            return try await task.value
        }
        let task = makeLoadTask()
        managerLoadTask = task
        stateLock.unlock()
        return try await task.value
    }

    private func makeLoadTask() -> Task<StreamingEouAsrManager, Error> {
        Task.detached(priority: .userInitiated) { [weak self] in
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            let manager = StreamingEouAsrManager(
                configuration: configuration,
                chunkSize: .ms160,
                eouDebounceMs: 240
            )
            try await manager.loadModels()
            self?.recordManager(manager)
            return manager
        }
    }

    private func recordManager(_ manager: StreamingEouAsrManager) {
        stateLock.lock()
        self.manager = manager
        self.managerLoadTask = nil
        stateLock.unlock()
    }

    private var currentManager: StreamingEouAsrManager? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return manager
    }

    private var currentStopTask: Task<Void, Never>? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingStopTask
    }

    private func allocateSessionId() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        sessionCounter += 1
        return sessionCounter
    }

    private func installSession(
        id: Int,
        continuation: AsyncStream<AVAudioPCMBuffer>.Continuation,
        consumerTask: Task<Void, Never>,
        partial: @escaping VoiceTranscriptHandler,
        eou: @escaping VoiceTranscriptHandler,
        error: @escaping VoiceTranscriptionErrorHandler
    ) {
        stateLock.lock()
        activeSession = Session(
            id: id,
            startedAt: Date(),
            continuation: continuation,
            consumerTask: consumerTask,
            partialHandler: partial,
            endOfUtteranceHandler: eou,
            errorHandler: error,
            latestTranscript: "",
            hasReportedError: false,
            firstPartialAt: nil,
            lastPartialAt: nil,
            chunkCount: 0,
            totalChunkMillis: 0
        )
        stateLock.unlock()
    }

    private func isSessionActive(_ id: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeSession?.id == id
    }

    private func deliverPartial(_ transcript: String, forSession sessionId: Int) {
        let now = Date()
        stateLock.lock()
        guard var session = activeSession, session.id == sessionId else {
            stateLock.unlock()
            return
        }
        session.latestTranscript = transcript
        let isFirst = session.firstPartialAt == nil
        if isFirst {
            session.firstPartialAt = now
        }
        session.lastPartialAt = now
        let sessionStart = session.startedAt
        activeSession = session
        let handler = session.partialHandler
        stateLock.unlock()

        if isFirst {
            let ms = now.timeIntervalSince(sessionStart) * 1000
            voiceLatencyLog.info("session=\(sessionId, privacy: .public) first_partial_after=\(String(format: "%.0f", ms), privacy: .public)ms len=\(transcript.count, privacy: .public)")
        }

        DispatchQueue.main.async {
            handler(transcript)
        }
    }

    private func deliverEou(_ transcript: String, forSession sessionId: Int) {
        let now = Date()
        stateLock.lock()
        guard var session = activeSession, session.id == sessionId else {
            stateLock.unlock()
            return
        }
        if !transcript.isEmpty {
            session.latestTranscript = transcript
        }
        let sessionStart = session.startedAt
        let lastPartial = session.lastPartialAt
        activeSession = session
        let handler = session.endOfUtteranceHandler
        stateLock.unlock()

        let sinceStart = now.timeIntervalSince(sessionStart) * 1000
        let sinceLastPartial = lastPartial.map { now.timeIntervalSince($0) * 1000 } ?? -1
        voiceLatencyLog.info("session=\(sessionId, privacy: .public) EOU since_start=\(String(format: "%.0f", sinceStart), privacy: .public)ms since_last_partial=\(String(format: "%.0f", sinceLastPartial), privacy: .public)ms len=\(transcript.count, privacy: .public)")

        DispatchQueue.main.async {
            handler(transcript)
        }
    }

    private func reportError(_ error: Error) {
        stateLock.lock()
        guard var session = activeSession, !session.hasReportedError else {
            stateLock.unlock()
            return
        }
        session.hasReportedError = true
        activeSession = session
        let handler = session.errorHandler
        stateLock.unlock()

        DispatchQueue.main.async {
            handler(error)
        }
    }
}

#endif

private extension AVAudioPCMBuffer {
    func copyForAsyncTranscription() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copy.frameLength = frameLength

        let channelCount = Int(format.channelCount)
        let frameCount = Int(frameLength)

        if let source = floatChannelData,
           let destination = copy.floatChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return copy
        }

        if let source = int16ChannelData,
           let destination = copy.int16ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return copy
        }

        if let source = int32ChannelData,
           let destination = copy.int32ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
            return copy
        }

        return nil
    }
}
