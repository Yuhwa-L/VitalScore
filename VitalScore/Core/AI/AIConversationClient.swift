import Foundation
import os

private let aiConversationLog = Logger(subsystem: "com.zeusya7015.vitalscore", category: "AIConversation")

enum AIConversationClientError: Error, LocalizedError {
    case missingEndpoint
    case missingAPIKey
    case missingVoiceAnalysisContext
    case invalidResponse
    case requestFailed(String)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "AI conversation endpoint is not configured."
        case .missingAPIKey:
            return "OpenAI API key is not configured."
        case .missingVoiceAnalysisContext:
            return "Voice analysis export did not include voice question context."
        case .invalidResponse:
            return "AI conversation response could not be read."
        case .requestFailed(let message):
            return message
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
        if let endpoint {
            do {
                return try await buildPlanViaDialogServer(endpoint: endpoint, context: context)
            } catch {
                aiConversationLog.error("Dialog server plan failed; falling back to direct OpenAI: \(String(describing: error), privacy: .public)")
            }
        }
        return try await buildPlanViaDirectOpenAI(context: context)
    }

    private func buildPlanViaDialogServer(
        endpoint: URL,
        context: VoiceAIConversationContext
    ) async throws -> VoiceAIConversationPlan {
        let payload = VoiceAIConversationRequestPayload(
            provider: provider,
            model: model,
            systemInstruction: VoiceAIConversationBuilder.systemInstruction,
            context: context
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

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

    private func buildPlanViaDirectOpenAI(context: VoiceAIConversationContext) async throws -> VoiceAIConversationPlan {
        guard let apiKey = Bundle.main.aiConversationOpenAIAPIKey else {
            throw AIConversationClientError.missingEndpoint
        }
        let modelName = Bundle.main.aiConversationOpenAIModel
        let url = URL(string: "https://api.openai.com/v1/responses")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let recentSummaries = context.recentHistory.prefix(3).map { summary -> String in
            "- score=\(String(format: "%.0f", summary.voiceScore)) confidence=\(summary.voiceConfidence)"
        }
        var lines: [String] = []
        lines.append("Generate a SINGLE opening message for a short voice wellness conversation.")
        lines.append("Target: 2-3 minutes total across about 4 turns. Keep this opening under 22 spoken words.")
        lines.append("It should warmly invite the user to share how they're feeling and what they did recently.")
        if !recentSummaries.isEmpty {
            lines.append("Recent voice-check context (do not mention numbers, just personalize tone):")
            lines.append(contentsOf: recentSummaries)
        }
        lines.append("Return JSON: {\"opening_message\": \"...\"}")
        let input = lines.joined(separator: "\n")

        let body: [String: Any] = [
            "model": modelName,
            "instructions": VoiceAIConversationBuilder.systemInstruction,
            "input": input,
            "max_output_tokens": 200,
            "store": false,
            "reasoning": ["effort": "minimal"],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "voice_opening_message",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "opening_message": ["type": "string"]
                        ],
                        "required": ["opening_message"]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            aiConversationLog.error("OpenAI plan HTTP \(http.statusCode, privacy: .public): \(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
            throw AIConversationClientError.serverError(http.statusCode)
        }
        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
        guard let outputText = envelope.outputText, !outputText.isEmpty else {
            throw AIConversationClientError.invalidResponse
        }
        struct OpeningShape: Decodable {
            let openingMessage: String
            enum CodingKeys: String, CodingKey { case openingMessage = "opening_message" }
        }
        let shape = try JSONDecoder().decode(OpeningShape.self, from: Data(outputText.utf8))

        let opening = shape.openingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !opening.isEmpty else {
            throw AIConversationClientError.invalidResponse
        }

        return VoiceAIConversationPlan(
            planId: "direct_openai_voice_conversation_v1",
            promptTag: VoiceAIConversationBuilder.promptTag,
            openingMessage: opening,
            conversationTurns: [
                VoiceAIConversationTurn(
                    id: "ai_free_talk_turn_1",
                    title: "AI Conversation",
                    prompt: opening,
                    targetDurationSeconds: VoiceAIConversationBuilder.advancedConversationTurnTargetSeconds
                )
            ],
            safetyNote: "This voice check supports wellness reflection only and is not a diagnosis.",
            source: "direct_openai"
        )
    }

    func buildVoiceChatReply(
        context: VoiceAIConversationContext,
        history: [VoiceAIChatMessage],
        latestUserTranscript: String,
        turnIndex: Int,
        maxTurns: Int
    ) async throws -> VoiceAIChatTurnResponse {
        if let endpoint = chatTurnEndpoint {
            do {
                return try await viaDialogServer(
                    endpoint: endpoint,
                    context: context,
                    history: history,
                    latestUserTranscript: latestUserTranscript,
                    turnIndex: turnIndex,
                    maxTurns: maxTurns
                )
            } catch {
                aiConversationLog.error("Dialog server chat-turn failed; falling back to direct OpenAI: \(String(describing: error), privacy: .public)")
            }
        }
        return try await viaDirectOpenAI(
            context: context,
            history: history,
            latestUserTranscript: latestUserTranscript,
            turnIndex: turnIndex,
            maxTurns: maxTurns
        )
    }

    private func viaDialogServer(
        endpoint: URL,
        context: VoiceAIConversationContext,
        history: [VoiceAIChatMessage],
        latestUserTranscript: String,
        turnIndex: Int,
        maxTurns: Int
    ) async throws -> VoiceAIChatTurnResponse {
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
        request.timeoutInterval = 20

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

    private func viaDirectOpenAI(
        context: VoiceAIConversationContext,
        history: [VoiceAIChatMessage],
        latestUserTranscript: String,
        turnIndex: Int,
        maxTurns: Int
    ) async throws -> VoiceAIChatTurnResponse {
        guard let apiKey = Bundle.main.aiConversationOpenAIAPIKey else {
            throw AIConversationClientError.missingEndpoint
        }

        let modelName = Bundle.main.aiConversationOpenAIModel
        let url = URL(string: "https://api.openai.com/v1/responses")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let input = Self.renderChatTurnInput(
            history: history,
            latestUserTranscript: latestUserTranscript,
            turnIndex: turnIndex,
            maxTurns: maxTurns,
            context: context
        )

        let body: [String: Any] = [
            "model": modelName,
            "instructions": VoiceAIConversationBuilder.chatTurnSystemInstruction,
            "input": input,
            "max_output_tokens": 400,
            "store": false,
            "reasoning": ["effort": "minimal"],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "voice_chat_reply",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "reply": ["type": "string"],
                            "should_continue": ["type": "boolean"]
                        ],
                        "required": ["reply", "should_continue"]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            aiConversationLog.error("OpenAI chat-turn HTTP \(http.statusCode, privacy: .public): \(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
            throw AIConversationClientError.serverError(http.statusCode)
        }

        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
        guard let outputText = envelope.outputText, !outputText.isEmpty else {
            throw AIConversationClientError.invalidResponse
        }
        let shape = try JSONDecoder().decode(OpenAIChatReplyShape.self, from: Data(outputText.utf8))
        let raw = VoiceAIChatTurnResponse(
            reply: shape.reply,
            shouldContinue: shape.shouldContinue,
            source: "direct_openai"
        )
        return VoiceAIConversationBuilder.normalizedChatReply(
            raw,
            turnIndex: turnIndex,
            maxTurns: maxTurns,
            latestUserTranscript: latestUserTranscript,
            history: history
        )
    }

    private static func renderChatTurnInput(
        history: [VoiceAIChatMessage],
        latestUserTranscript: String,
        turnIndex: Int,
        maxTurns: Int,
        context: VoiceAIConversationContext
    ) -> String {
        var lines: [String] = []
        lines.append("Turn \(turnIndex) of \(maxTurns).")
        lines.append("")
        lines.append("Latest user transcript:")
        let cleaned = latestUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(cleaned.isEmpty ? "(no speech detected)" : "\"\(cleaned)\"")
        lines.append("")
        if !history.isEmpty {
            lines.append("Prior conversation:")
            for message in history {
                lines.append("- \(message.role.capitalized): \(message.text)")
            }
            lines.append("")
        }
        let previousAssistantReplies = VoiceAIConversationBuilder.previousAssistantReplies(from: history)
        if !previousAssistantReplies.isEmpty {
            lines.append("Do NOT repeat any of these previous assistant questions verbatim or in essence:")
            for prior in previousAssistantReplies {
                lines.append("- \(prior)")
            }
            lines.append("")
        }
        lines.append("Reply requirements:")
        lines.append("- Stay under 18 spoken words when possible.")
        lines.append("- Reference one concrete detail from the user's latest answer.")
        if turnIndex < maxTurns {
            lines.append("- Ask ONE personalized follow-up question. Set should_continue=true.")
        } else {
            lines.append("- This is the final turn: give a short summary (no question). Set should_continue=false.")
        }
        lines.append("- Never repeat a prior assistant question.")
        lines.append("- Return JSON: {\"reply\": \"...\", \"should_continue\": true|false}")
        return lines.joined(separator: "\n")
    }

    func analyzeVoiceExport(
        at fileURL: URL,
        recentVoiceSessions: [VoiceTrackingSession] = [],
        recentDailyRecords: [DailyHealthRecord] = []
    ) async throws -> VoiceAIAnalysisResponse {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(MultimodalAnalysisExport.self, from: data)
        return try await analyzeVoiceExport(
            export,
            exportFileName: fileURL.lastPathComponent,
            recentVoiceSessions: recentVoiceSessions,
            recentDailyRecords: recentDailyRecords
        )
    }

    func analyzeVoiceExport(
        _ export: MultimodalAnalysisExport,
        exportFileName: String? = nil,
        recentVoiceSessions: [VoiceTrackingSession] = [],
        recentDailyRecords: [DailyHealthRecord] = []
    ) async throws -> VoiceAIAnalysisResponse {
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
            recentDailyRecords: Array(recentDailyRecords.sorted { $0.date < $1.date }.suffix(7)),
            debugAudioSamples: Self.debugAudioSamples(for: export.voiceSession)
        )

        // Voice service scoring is a post-session API call made directly from
        // the saved export. It does not depend on the live conversation server.
        return try await analyzeViaDirectOpenAI(payload: payload)
    }

    private func analyzeViaDirectOpenAI(
        payload: VoiceAIAnalysisRequestPayload
    ) async throws -> VoiceAIAnalysisResponse {
        guard let apiKey = Bundle.main.aiConversationOpenAIAPIKey else {
            throw AIConversationClientError.missingAPIKey
        }

        let modelName = Bundle.main.aiConversationOpenAIModel
        let url = URL(string: "https://api.openai.com/v1/responses")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        let input = try Self.renderVoiceAnalysisInput(payload: payload)
        let body: [String: Any] = [
            "model": modelName,
            "instructions": payload.systemInstruction,
            "input": input,
            "max_output_tokens": 900,
            "store": false,
            "reasoning": ["effort": "minimal"],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "vitalscore_voice_service_score",
                    "strict": true,
                    "schema": Self.voiceAnalysisSchema
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = Self.apiErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            aiConversationLog.error("OpenAI voice analysis HTTP \(http.statusCode, privacy: .public): \(message, privacy: .public)")
            throw AIConversationClientError.requestFailed(message)
        }

        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
        if let message = envelope.error?.message {
            throw AIConversationClientError.requestFailed(message)
        }
        guard let outputText = envelope.outputText, !outputText.isEmpty else {
            throw AIConversationClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let shape = try decoder.decode(DirectVoiceAnalysisShape.self, from: Data(outputText.utf8))
        let exportId = payload.analysisExport.id
        return VoiceAIAnalysisResponse(
            id: UUID(),
            exportId: exportId,
            createdAt: Date(),
            source: "direct_openai_voice_service",
            aiVoiceScore: shape.aiVoiceScore,
            aiScoreConfidence: shape.aiScoreConfidence,
            aiScoreRationale: shape.aiScoreRationale,
            summary: shape.summary,
            dataQuality: shape.dataQuality,
            notableSignals: shape.notableSignals,
            longitudinalContext: shape.longitudinalContext,
            missingData: shape.missingData,
            recommendedNextSteps: shape.recommendedNextSteps,
            safetyNote: shape.safetyNote
        )
    }

    private static func renderVoiceAnalysisInput(payload: VoiceAIAnalysisRequestPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        let payloadObject = try JSONSerialization.jsonObject(with: payloadData)
        let prompt: [String: Any] = [
            "task": "Generate the final VitalScore Voice service score after the recorded voice check is complete.",
            "importantDistinction": [
                "This is post-session scoring for the saved Voice service input data.",
                "Do not generate live conversation prompts or chat replies.",
                "If the protocol mode is fixed_prompt, score from the saved fixed prompts, acoustic task metrics, capture quality, recent voice history, and recent daily records; a conversation transcript is not required.",
                "If the protocol mode is advanced_freestyle_talk, also use saved assistant prompts, user transcripts, and conversation summary."
            ],
            "scoringRules": [
                "Return aiVoiceScore as a conservative 0-100 wellness voice score for this completed session.",
                "Use analysisExport.featureVector, analysisExport.voiceSession.result.taskAnalyses, questionBackground.questionSet, recentVoiceHistory, recentDailyRecords, and optional debugAudioSamples.",
                "Compare the current saved session against recentVoiceHistory when available; improvement means cleaner capture quality, steadier task completion, fewer quality issues, stronger usable speech signal, or better consistency with the user's own recent baseline.",
                "When fewer than seven usable prior sessions exist, rely more on capture quality and task completeness and set confidence Low or Medium.",
                "Missing conversation transcript in fixed_prompt mode is not a penalty.",
                "Missing fixed acoustic task metrics, low quality, high silence ratio, clipping, very low volume, or missing baseline should reduce confidence and may reduce score.",
                "Do not score medical risk, identity, protected traits, emotion, diagnosis, disease, or treatment need.",
                "Do not claim a voice feature caused a health or wellness state.",
                "Set aiScoreRationale to one short sentence naming the main saved-data reason for the score.",
                "Keep summary to one or two user-facing sentences."
            ],
            "payload": payloadObject
        ]
        let promptData = try JSONSerialization.data(withJSONObject: prompt, options: [.sortedKeys])
        return String(decoding: promptData, as: UTF8.self)
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?.error.message
    }

    private var chatTurnEndpoint: URL? {
        endpoint?
            .deletingLastPathComponent()
            .appendingPathComponent("voice-chat-turn")
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

private struct OpenAIResponsesEnvelope: Decodable {
    let output: [OutputItem]?
    let status: String?
    let error: OpenAIError?

    struct OutputItem: Decodable {
        let type: String?
        let content: [ContentItem]?
    }
    struct ContentItem: Decodable {
        let text: String?
    }

    var outputText: String? {
        output?
            .filter { ($0.type ?? "") == "message" }
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .first
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
}

private struct OpenAIChatReplyShape: Decodable {
    let reply: String
    let shouldContinue: Bool
    enum CodingKeys: String, CodingKey {
        case reply
        case shouldContinue = "should_continue"
    }
}

private struct DirectVoiceAnalysisShape: Decodable {
    let aiVoiceScore: Double
    let aiScoreConfidence: String
    let aiScoreRationale: String
    let summary: String
    let dataQuality: [String]
    let notableSignals: [String]
    let longitudinalContext: [String]
    let missingData: [String]
    let recommendedNextSteps: [String]
    let safetyNote: String
}

private extension AIConversationClient {
    static var voiceAnalysisSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "aiVoiceScore": ["type": "number", "minimum": 0, "maximum": 100],
                "aiScoreConfidence": ["type": "string", "enum": ["Low", "Medium", "High"]],
                "aiScoreRationale": ["type": "string"],
                "summary": ["type": "string"],
                "dataQuality": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "notableSignals": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "longitudinalContext": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "missingData": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "recommendedNextSteps": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "safetyNote": ["type": "string"]
            ],
            "required": [
                "aiVoiceScore",
                "aiScoreConfidence",
                "aiScoreRationale",
                "summary",
                "dataQuality",
                "notableSignals",
                "longitudinalContext",
                "missingData",
                "recommendedNextSteps",
                "safetyNote"
            ]
        ]
    }
}

private extension Bundle {
    var aiConversationOpenAIAPIKey: String? {
        let raw = (infoDictionary?["VitalScoreOpenAIAPIKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, !raw.contains("$("), !raw.contains("YOUR_") else { return nil }
        return raw
    }

    var aiConversationOpenAIModel: String {
        let raw = (infoDictionary?["VitalScoreOpenAIModel"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (raw.isEmpty || raw.contains("$(")) ? "gpt-5-mini" : raw
    }
}
