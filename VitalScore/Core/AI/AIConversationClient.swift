import Foundation

enum AIConversationClientError: Error, LocalizedError {
    case missingEndpoint
    case missingVoiceAnalysisContext
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "AI conversation endpoint is not configured."
        case .missingVoiceAnalysisContext:
            return "Voice analysis export did not include voice question context."
        case .invalidResponse:
            return "AI conversation response could not be read."
        case .serverError(let statusCode):
            return "AI conversation request failed with status \(statusCode)."
        }
    }
}

final class AIConversationClient {
    private let endpoint: URL?
    private let model: String
    private let provider: String
    private let session: URLSession

    init(
        endpoint: URL? = Bundle.main.aiDialogEndpointURL,
        model: String = Bundle.main.aiDialogModel,
        provider: String = Bundle.main.aiProvider,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.model = model
        self.provider = provider
        self.session = session
    }

    func buildVoiceConversationPlan(context: VoiceAIConversationContext) async throws -> VoiceAIConversationPlan {
        guard let endpoint else {
            throw AIConversationClientError.missingEndpoint
        }

        let payload = VoiceAIConversationRequestPayload(
            provider: provider,
            model: model,
            systemInstruction: VoiceAIConversationBuilder.systemInstruction,
            context: context
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIConversationClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIConversationClientError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VoiceAIConversationPlan.self, from: data)
    }

    func buildVoiceChatReply(
        context: VoiceAIConversationContext,
        history: [VoiceAIChatMessage],
        latestUserTranscript: String,
        turnIndex: Int,
        maxTurns: Int
    ) async throws -> VoiceAIChatTurnResponse {
        guard let endpoint = chatTurnEndpoint else {
            throw AIConversationClientError.missingEndpoint
        }

        let payload = VoiceAIChatTurnRequestPayload(
            provider: provider,
            model: model,
            systemInstruction: VoiceAIConversationBuilder.chatTurnSystemInstruction,
            context: context,
            history: history,
            previousAssistantReplies: VoiceAIConversationBuilder.previousAssistantReplies(from: history),
            previousUserTranscripts: VoiceAIConversationBuilder.previousUserTranscripts(from: history),
            latestUserTranscript: latestUserTranscript,
            turnIndex: turnIndex,
            maxTurns: maxTurns
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIConversationClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIConversationClientError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedResponse = try decoder.decode(VoiceAIChatTurnResponse.self, from: data)
        return VoiceAIConversationBuilder.normalizedChatReply(
            decodedResponse,
            turnIndex: turnIndex,
            maxTurns: maxTurns,
            latestUserTranscript: latestUserTranscript,
            history: history
        )
    }

    func analyzeVoiceExport(
        at fileURL: URL,
        recentVoiceSessions: [VoiceTrackingSession] = []
    ) async throws -> VoiceAIAnalysisResponse {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(MultimodalAnalysisExport.self, from: data)
        return try await analyzeVoiceExport(
            export,
            exportFileName: fileURL.lastPathComponent,
            recentVoiceSessions: recentVoiceSessions
        )
    }

    func analyzeVoiceExport(
        _ export: MultimodalAnalysisExport,
        exportFileName: String? = nil,
        recentVoiceSessions: [VoiceTrackingSession] = []
    ) async throws -> VoiceAIAnalysisResponse {
        guard let endpoint = analysisEndpoint else {
            throw AIConversationClientError.missingEndpoint
        }
        guard let questionBackground = export.questionProtocol
            ?? export.voiceSession.map(VoiceAIConversationBuilder.questionProtocolContext(for:))
        else {
            throw AIConversationClientError.missingVoiceAnalysisContext
        }

        let payload = VoiceAIAnalysisRequestPayload(
            provider: provider,
            model: model,
            systemInstruction: VoiceAIConversationBuilder.analysisSystemInstruction,
            exportFileName: exportFileName,
            analysisExport: export,
            questionBackground: questionBackground,
            recentVoiceHistory: VoiceAIConversationBuilder.recentSessionSummaries(from: recentVoiceSessions),
            debugAudioSamples: Self.debugAudioSamples(for: export.voiceSession)
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIConversationClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIConversationClientError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VoiceAIAnalysisResponse.self, from: data)
    }

    private var chatTurnEndpoint: URL? {
        endpoint?
            .deletingLastPathComponent()
            .appendingPathComponent("voice-chat-turn")
    }

    private var analysisEndpoint: URL? {
        endpoint?
            .deletingLastPathComponent()
            .appendingPathComponent("voice-analysis")
    }

    static func debugAudioSamples(for session: VoiceTrackingSession?) -> [VoiceAIAudioSamplePayload] {
        guard VoiceRawAudioDebugExportSettings.isAIUploadEnabled,
              let manifestPath = session?.rawAudioDebugManifestPath
        else { return [] }

        let manifestURL = URL(fileURLWithPath: manifestPath)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder.iso8601.decode(VoiceRawAudioDebugManifest.self, from: data)
        else { return [] }

        let sampleDirectory = manifestURL.deletingLastPathComponent()
        var totalBytes = 0
        var samples: [VoiceAIAudioSamplePayload] = []

        for sample in manifest.samples.prefix(VoiceRawAudioDebugExportSettings.maxAIUploadSampleCount) {
            guard sample.status == "completed" || sample.status == "stopped" else { continue }
            let fileURL = sampleDirectory.appendingPathComponent(sample.fileName)
            guard let audioData = try? Data(contentsOf: fileURL), !audioData.isEmpty else { continue }
            guard totalBytes + audioData.count <= VoiceRawAudioDebugExportSettings.maxAIUploadTotalBytes else { break }

            totalBytes += audioData.count
            samples.append(
                VoiceAIAudioSamplePayload(
                    id: sample.id,
                    taskType: sample.taskType,
                    promptId: sample.promptId,
                    promptText: sample.promptText,
                    turnIndex: sample.turnIndex,
                    fileName: sample.fileName,
                    durationSeconds: sample.durationSeconds,
                    sampleRate: sample.sampleRate,
                    channels: sample.channels,
                    format: "wav",
                    byteCount: audioData.count,
                    base64Audio: audioData.base64EncodedString()
                )
            )
        }

        return samples
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
