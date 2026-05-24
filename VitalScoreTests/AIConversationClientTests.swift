import Foundation
import XCTest
@testable import VitalScore

final class AIConversationClientTests: XCTestCase {
    override func tearDown() {
        AIClientURLProtocol.handler = nil
        super.tearDown()
    }

    func test_buildVoiceChatReply_sendsTranscriptAndHistoryToChatTurnAPI() async throws {
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:8787/ai/voice-conversation"))
        let context = VoiceAIConversationBuilder.makeContext(
            experimentTag: "Morning check",
            history: [],
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let history = [
            VoiceAIChatMessage(role: "assistant", text: "How is your focus today?"),
            VoiceAIChatMessage(role: "user", text: "It is steady, but I feel a bit tired.")
        ]
        let latestTranscript = "The tired feeling is mostly from a late night."

        AIClientURLProtocol.handler = { request, body in
            XCTAssertEqual(request.url?.path, "/ai/voice-chat-turn")
            XCTAssertEqual(request.httpMethod, "POST")

            let payload = try JSONDecoder.iso8601.decode(VoiceAIChatTurnRequestPayload.self, from: body)
            XCTAssertEqual(payload.provider, "openai")
            XCTAssertEqual(payload.model, "unit-model")
            XCTAssertEqual(payload.context.experimentTag, "Morning check")
            XCTAssertEqual(payload.history, history)
            XCTAssertEqual(payload.previousAssistantReplies, ["How is your focus today?"])
            XCTAssertEqual(payload.previousUserTranscripts, ["It is steady, but I feel a bit tired."])
            XCTAssertEqual(payload.latestUserTranscript, latestTranscript)
            XCTAssertEqual(payload.turnIndex, 2)
            XCTAssertEqual(payload.maxTurns, 4)

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"reply":"That makes sense. What would help your energy now?","shouldContinue":true,"source":"test"}"#.utf8)
            )
        }

        let response = try await makeClient(endpoint: endpoint).buildVoiceChatReply(
            context: context,
            history: history,
            latestUserTranscript: latestTranscript,
            turnIndex: 2,
            maxTurns: 4
        )

        XCTAssertEqual(response.reply, "That makes sense. What would help your energy now?")
        XCTAssertTrue(response.shouldContinue)
    }

    func test_analyzeVoiceExport_sendsAdvancedConversationExportAndQuestionBackground() async throws {
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:8787/ai/voice-conversation"))
        let exportId = UUID()
        let analysisId = UUID()
        let session = makeAdvancedVoiceSession()
        let export = MultimodalAnalysisExport.voice(session: session, dailyRecord: nil)

        AIClientURLProtocol.handler = { request, body in
            XCTAssertEqual(request.url?.path, "/ai/voice-analysis")
            XCTAssertEqual(request.httpMethod, "POST")

            let payload = try JSONDecoder.iso8601.decode(VoiceAIAnalysisRequestPayload.self, from: body)
            XCTAssertEqual(payload.provider, "openai")
            XCTAssertEqual(payload.model, "unit-model")
            XCTAssertEqual(payload.exportFileName, "advanced-voice-export.json")
            XCTAssertEqual(payload.analysisExport.questionProtocol?.mode, "advanced_freestyle_talk")
            XCTAssertEqual(payload.questionBackground.mode, "advanced_freestyle_talk")
            XCTAssertEqual(payload.analysisExport.voiceSession?.result.conversationExchanges.count, 2)
            XCTAssertEqual(
                payload.analysisExport.voiceSession?.result.conversationExchanges.last?.userTranscript,
                "Stress from meetings is probably the biggest factor."
            )
            XCTAssertTrue(payload.analysisExport.availableModalities.contains("voice_conversation_transcript"))
            XCTAssertEqual(payload.recentVoiceHistory.first?.id, session.id)
            XCTAssertTrue(payload.debugAudioSamples.isEmpty)

            let response = VoiceAIAnalysisResponse(
                id: analysisId,
                exportId: exportId,
                createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                source: "test",
                summary: "Advanced voice conversation data was received.",
                dataQuality: ["Transcript and acoustic summary were present."],
                notableSignals: ["Conversation transcript available."],
                longitudinalContext: ["Recent history was included."],
                missingData: [],
                recommendedNextSteps: ["Repeat under similar conditions."],
                safetyNote: "Wellness-only, not medical advice."
            )
            let data = try JSONEncoder.iso8601.encode(response)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                data
            )
        }

        let response = try await makeClient(endpoint: endpoint).analyzeVoiceExport(
            export,
            exportFileName: "advanced-voice-export.json",
            recentVoiceSessions: [session]
        )

        XCTAssertEqual(response.id, analysisId)
        XCTAssertEqual(response.exportId, exportId)
    }

    private func makeClient(endpoint: URL) -> AIConversationClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIClientURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return AIConversationClient(
            endpoint: endpoint,
            model: "unit-model",
            provider: "openai",
            session: session
        )
    }

    private func makeAdvancedVoiceSession() -> VoiceTrackingSession {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let result = VoiceTrackingResult(
            completedAt: startedAt.addingTimeInterval(40),
            durationSeconds: 40,
            voiceScore: 81,
            voiceConfidence: "Low",
            averageVolumeDb: -24,
            volumeStdDevDb: 3,
            silenceRatio: 0.1,
            peakVolumeDb: -10,
            overallQualityScore: 0.9,
            usable: true,
            taskAnalyses: [
                VoiceTaskAnalysis(
                    taskType: .guidedConversation,
                    promptId: "ai_free_talk_turn_1",
                    promptText: "How are your energy and focus feeling right now?",
                    targetDurationSeconds: 45,
                    durationSeconds: 24,
                    sampleCount: 120,
                    averageVolumeDb: -24,
                    volumeStdDevDb: 3,
                    peakVolumeDb: -10,
                    silenceRatio: 0.1,
                    clippingPercentage: 0,
                    zeroCrossingRate: 0.12,
                    voicedFrameRatio: 0.9,
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
                    aiPrompt: "How are your energy and focus feeling right now?",
                    userTranscript: "My focus is okay, but my energy feels lower than usual.",
                    userResponseStartedAt: startedAt,
                    userResponseEndedAt: startedAt.addingTimeInterval(10),
                    responseDurationSeconds: 10,
                    source: "ios_speech_recognition"
                ),
                VoiceConversationExchange(
                    turnIndex: 2,
                    aiPrompt: "What feels like the biggest reason for that today?",
                    userTranscript: "Stress from meetings is probably the biggest factor.",
                    userResponseStartedAt: startedAt.addingTimeInterval(16),
                    userResponseEndedAt: startedAt.addingTimeInterval(24),
                    responseDurationSeconds: 8,
                    source: "ios_speech_recognition"
                )
            ],
            baselineSessionsUsed: 2,
            baselineStatus: "building_baseline",
            topDrivers: ["Building your voice baseline: 2 of 7 sessions collected."]
        )

        return VoiceTrackingSession(
            date: result.completedAt,
            experimentTag: "Morning check",
            promptTag: VoiceAIConversationBuilder.promptTag,
            promptVersion: VoiceAIConversationBuilder.promptVersion,
            result: result
        )
    }
}

private final class AIClientURLProtocol: URLProtocol {
    static var handler: ((URLRequest, Data) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request, requestBody)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private var requestBody: Data {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
