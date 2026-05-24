import Foundation
import XCTest
@testable import VitalScore

final class AIConversationClientTests: XCTestCase {
    override func tearDown() {
        AIClientURLProtocol.handler = nil
        super.tearDown()
    }

    func test_buildVoiceChatReply_sendsTranscriptAndHistoryToDirectOpenAI() async throws {
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
            XCTAssertEqual(request.url?.host, "api.openai.com")
            XCTAssertEqual(request.url?.path, "/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")

            let openAIRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(openAIRequest["model"] as? String, "unit-model")
            XCTAssertEqual(openAIRequest["store"] as? Bool, false)
            XCTAssertEqual(openAIRequest["instructions"] as? String, VoiceAIConversationBuilder.chatTurnSystemInstruction)

            let input = try XCTUnwrap(openAIRequest["input"] as? String)
            let prompt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let turnState = try XCTUnwrap(prompt["turnState"] as? [String: Any])
            XCTAssertEqual(turnState["turnIndex"] as? Int, 2)
            XCTAssertEqual(turnState["maxTurns"] as? Int, 4)
            let inputData = try XCTUnwrap(prompt["inputData"] as? [String: Any])
            XCTAssertEqual(inputData["latestUserTranscript"] as? String, latestTranscript)
            XCTAssertEqual(inputData["previousAssistantQuestions"] as? [String], ["How is your focus today?"])
            let priorConversation = try XCTUnwrap(inputData["priorConversation"] as? [[String: String]])
            XCTAssertEqual(priorConversation, history.map { ["role": $0.role, "text": $0.text] })
            let contextObject = try XCTUnwrap(inputData["context"] as? [String: Any])
            XCTAssertEqual(contextObject["experimentTag"] as? String, "Morning check")

            let replyShape: [String: Any] = [
                "reply": "That makes sense. What would help your energy now?",
                "should_continue": true
            ]
            let replyData = try JSONSerialization.data(withJSONObject: replyShape)
            let outputText = String(decoding: replyData, as: UTF8.self)
            let responseEnvelope: [String: Any] = [
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["text": outputText]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseEnvelope)
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

        let response = try await makeClient().buildVoiceChatReply(
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
        let session = makeAdvancedVoiceSession()
        let export = MultimodalAnalysisExport.voice(session: session, dailyRecord: nil)

        AIClientURLProtocol.handler = { request, body in
            XCTAssertEqual(request.url?.host, "api.openai.com")
            XCTAssertEqual(request.url?.path, "/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")

            let openAIRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(openAIRequest["store"] as? Bool, false)
            XCTAssertEqual(openAIRequest["instructions"] as? String, VoiceAIConversationBuilder.analysisSystemInstruction)

            let input = try XCTUnwrap(openAIRequest["input"] as? String)
            let prompt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let payloadObject = try XCTUnwrap(prompt["payload"] as? [String: Any])
            let payloadData = try JSONSerialization.data(withJSONObject: payloadObject)
            let payload = try JSONDecoder.iso8601.decode(VoiceAIAnalysisRequestPayload.self, from: payloadData)
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

            let analysisShape: [String: Any] = [
                "aiVoiceScore": 82,
                "aiScoreConfidence": "Medium",
                "aiScoreRationale": "Transcript and acoustic summary were usable.",
                "summary": "Advanced voice conversation data was received.",
                "dataQuality": ["Transcript and acoustic summary were present."],
                "notableSignals": ["Conversation transcript available."],
                "longitudinalContext": ["Recent history was included."],
                "missingData": [],
                "recommendedNextSteps": ["Repeat under similar conditions."],
                "safetyNote": "Wellness-only, not medical advice."
            ]
            let analysisData = try JSONSerialization.data(withJSONObject: analysisShape)
            let outputText = String(decoding: analysisData, as: UTF8.self)
            let responseEnvelope: [String: Any] = [
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["text": outputText]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseEnvelope)
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

        let response = try await makeClient().analyzeVoiceExport(
            export,
            exportFileName: "advanced-voice-export.json",
            recentVoiceSessions: [session]
        )

        XCTAssertEqual(response.exportId, export.id)
        XCTAssertEqual(response.source, "direct_openai_voice_service")
        XCTAssertEqual(response.aiVoiceScore, 82)
    }

    func test_generateWellnessSuggestions_sendsHistoricalPayloadAndSafetyRules() async throws {
        let records = makeSuggestionRecords()
        let voiceSession = makeAdvancedVoiceSession()

        AIClientURLProtocol.handler = { request, body in
            XCTAssertEqual(request.url?.host, "api.openai.com")
            XCTAssertEqual(request.url?.path, "/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")

            let openAIRequest = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(openAIRequest["store"] as? Bool, false)
            XCTAssertEqual(openAIRequest["instructions"] as? String, AIConversationClient.wellnessSuggestionSystemInstruction)

            let input = try XCTUnwrap(openAIRequest["input"] as? String)
            let prompt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
            let payloadObject = try XCTUnwrap(prompt["payload"] as? [String: Any])
            let payloadData = try JSONSerialization.data(withJSONObject: payloadObject)
            let payload = try JSONDecoder.iso8601.decode(WellnessSuggestionRequestPayload.self, from: payloadData)

            XCTAssertEqual(payload.provider, "openai")
            XCTAssertEqual(payload.model, "unit-model")
            XCTAssertEqual(payload.tagFilter, "Morning")
            XCTAssertEqual(payload.recentDailyRecords.count, records.count)
            XCTAssertEqual(payload.recentVoiceHistory.first?.id, voiceSession.id)
            XCTAssertTrue(payload.guardrails.contains("Suggestions only"))

            let suggestionShape: [String: Any] = [
                "summary": "Shorter sleep lined up with lower wellness deltas in recent records.",
                "confidence": "Medium",
                "observedPatterns": ["Sleep was shorter on lower-score days."],
                "suggestions": [
                    [
                        "title": "Try a consistent sleep window",
                        "category": "sleep",
                        "reason": "Lower-score days lined up with shorter sleep.",
                        "suggestion": "Keep bedtime and wake time within a 30-minute window for 3 nights.",
                        "trackingPlan": "Compare sleep, HRV, eye-focus, voice, and wellness delta after each check-in.",
                        "riskLevel": "low",
                        "confidence": "Medium",
                        "evidence": ["Lower-score sleep averaged 6.1h."],
                        "notMedicalAdvice": true
                    ],
                    [
                        "title": "Log food and hydration timing",
                        "category": "nutrition",
                        "reason": "Food and hydration inputs are not directly captured yet.",
                        "suggestion": "Add simple tags for meal timing, hydration, and caffeine timing for one week.",
                        "trackingPlan": "Review whether tags cluster with wellness delta or HRV changes.",
                        "riskLevel": "low",
                        "confidence": "Low",
                        "evidence": ["Nutrition inputs are missing from current records."],
                        "notMedicalAdvice": true
                    ]
                ],
                "nextCheckIn": "Try one experiment for 3 to 7 days and compare similar check-ins.",
                "clinicianNote": "If changes feel persistent or concerning, consider discussing trends with a qualified healthcare professional.",
                "safetyNote": "Wellness-only suggestions, not medical advice."
            ]
            let suggestionData = try JSONSerialization.data(withJSONObject: suggestionShape)
            let outputText = String(decoding: suggestionData, as: UTF8.self)
            let responseEnvelope: [String: Any] = [
                "output": [
                    [
                        "type": "message",
                        "content": [
                            ["text": outputText]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: responseEnvelope)
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

        let response = try await makeClient().generateWellnessSuggestions(
            records: records,
            voiceSessions: [voiceSession],
            tagFilter: "Morning"
        )

        XCTAssertEqual(response.source, "direct_openai_wellness_suggestions")
        XCTAssertEqual(response.suggestions.count, 2)
        XCTAssertEqual(response.suggestions.first?.category, .sleep)
        XCTAssertTrue(response.suggestions.allSatisfy(\.notMedicalAdvice))
    }

    private func makeClient() -> AIConversationClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIClientURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return AIConversationClient(
            provider: "openai",
            session: session,
            directOpenAIAPIKey: "unit-test-key",
            directOpenAIModel: "unit-model"
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

    private func makeSuggestionRecords() -> [DailyHealthRecord] {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return (0..<8).map { offset in
            let lowerDay = offset >= 5
            return DailyHealthRecord(
                date: start.addingTimeInterval(TimeInterval(offset * 86_400)),
                experimentTag: "Morning",
                sleepHours: lowerDay ? 6.0 : 7.6,
                restingHeartRateBPM: lowerDay ? 68 : 61,
                hrvMs: lowerDay ? 31 : 44,
                stepCount: lowerDay ? 4_200 : 8_200,
                eyeFocusScore: lowerDay ? 64 : 78,
                voiceScore: lowerDay ? 58 : 74,
                wellnessDeltaScore: lowerDay ? -8 : 6,
                confidenceLevel: "Medium",
                insightText: "Scored record"
            )
        }
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
