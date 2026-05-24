import Foundation

enum OpenAIEyeFocusSummaryError: LocalizedError {
    case missingAPIKey
    case invalidLogEncoding
    case logTooLarge
    case invalidRequestBody
    case requestFailed(String)
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured."
        case .invalidLogEncoding:
            return "Could not read gaze log JSON as UTF-8."
        case .logTooLarge:
            return "Gaze log JSON is too large to send for summary."
        case .invalidRequestBody:
            return "Could not build OpenAI request body."
        case .requestFailed(let message):
            return message
        case .missingOutput:
            return "OpenAI response did not include summary text."
        }
    }
}

struct OpenAIEyeFocusSummaryClient {
    private let session: URLSession
    private let bundle: Bundle
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let maxLogBytes = 8_000_000
    private let maxSamplesToSend = 400

    private static let systemInstructions = """
    You are analyzing eye-tracking test data for VitalScore, a personal wellness app.

    Your job is to summarize the user's eye-focus test performance in clear, short, non-medical language. The input may include computed metrics, calibration data, tracking quality data, and downsampled gaze samples.

    Important safety rules:
    - Do not diagnose disease or medical conditions.
    - Do not claim the user has ADHD, Parkinson's, concussion, fatigue disorder, eye disease, neurological disease, or any other condition.
    - Do not recommend treatment, medication, or clinical action.
    - You may describe observable test patterns only, such as reaction speed, gaze accuracy, gaze stability, blink rate, tracking loss, and calibration quality.
    - If the data quality is weak, say that the result should be interpreted cautiously.
    - Never include raw JSON, raw samples, file paths, logs, code blocks, or technical dumps in the response.
    - Do not mention internal implementation details.

    Interpretation rules:
    - Prefer precomputed metrics over individual raw samples.
    - Use raw/downsampled samples only as supporting evidence.
    - Tracking loss, unstable calibration, excessive motion, or low sample count should reduce confidence.
    - Separate user performance from sensor quality. For example, poor accuracy may come from calibration or tracking quality, not only the user.
    - If metrics conflict, explain the uncertainty briefly.
    - Keep wording neutral and calm.

    Analyze these areas:
    1. Reaction — Summarize reaction speed, consistency, missed targets, and false taps.
    2. Gaze accuracy — Summarize how close the gaze estimate was to the target.
    3. Gaze stability — Summarize whether the gaze signal looked steady or jumpy.
    4. Tracking quality — Summarize sample count, tracking loss, blink rate, and whether the camera/face tracking seemed reliable.
    5. Calibration — Summarize whether calibration quality supports trusting the result.
    6. Practical note — Give one short suggestion for improving the next test, such as holding the phone steady, keeping the face centered, improving lighting, or recalibrating carefully.

    Output requirements:
    - Return only valid JSON matching the provided schema.
    - Do not include markdown.
    - Do not include raw data.
    - Keep the overall summary under 35 words.
    - Keep each section summary under 22 words.
    - Use simple language suitable for a normal app user.
    - If a particular signal was not captured (e.g., reaction data missing in a re-analysis), state that briefly in that section.
    """

    init(session: URLSession = .shared, bundle: Bundle = .main) {
        self.session = session
        self.bundle = bundle
    }

    func summarizeLog(at logFileURL: URL, result: EyeFocusTestResult) async throws -> EyeFocusAISummary {
        try await summarize(at: logFileURL, resultCompletedAt: result.completedAt, promptBuilder: { prompt(logJSON: $0, result: result) })
    }

    func summarizeLog(at logFileURL: URL) async throws -> EyeFocusAISummary {
        let logData = try Data(contentsOf: logFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parsed = try? decoder.decode(GazeLogFile.self, from: logData)
        let completedAt = parsed?.testStartedAt ?? Date()
        return try await summarize(at: logFileURL, resultCompletedAt: completedAt, promptBuilder: { promptFromLog(logJSON: $0) }, preloaded: logData)
    }

    private func summarize(
        at logFileURL: URL,
        resultCompletedAt: Date,
        promptBuilder: (String) -> String,
        preloaded: Data? = nil
    ) async throws -> EyeFocusAISummary {
        guard let apiKey = bundle.openAIAPIKey else {
            throw OpenAIEyeFocusSummaryError.missingAPIKey
        }

        let rawData = try preloaded ?? Data(contentsOf: logFileURL)
        guard rawData.count <= maxLogBytes else {
            throw OpenAIEyeFocusSummaryError.logTooLarge
        }
        let logData = downsampledLogData(from: rawData) ?? rawData
        guard let logJSON = String(data: logData, encoding: .utf8) else {
            throw OpenAIEyeFocusSummaryError.invalidLogEncoding
        }

        let model = bundle.openAIModel
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try requestBody(model: model, input: promptBuilder(logJSON))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let apiError = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data)
            let message = apiError?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw OpenAIEyeFocusSummaryError.requestFailed(message)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
        if let message = decoded.error?.message {
            throw OpenAIEyeFocusSummaryError.requestFailed(message)
        }

        guard let outputText = decoded.outputText else {
            if decoded.status == "incomplete", let reason = decoded.incompleteDetails?.reason {
                throw OpenAIEyeFocusSummaryError.requestFailed("OpenAI response incomplete: \(reason)")
            }
            throw OpenAIEyeFocusSummaryError.missingOutput
        }

        let aiResponse = try JSONDecoder().decode(EyeFocusStructuredSummary.self, from: Data(outputText.utf8))
        return EyeFocusAISummary(
            resultCompletedAt: resultCompletedAt,
            model: model,
            sourceLogFileName: logFileURL.lastPathComponent,
            overallSummary: aiResponse.overallSummary,
            confidence: aiResponse.confidence,
            sections: aiResponse.sections.map {
                EyeFocusAISummarySection(title: $0.title, summary: $0.summary)
            }
        )
    }

    private func requestBody(model: String, input: String) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "instructions": Self.systemInstructions,
            "input": input,
            "max_output_tokens": 1800,
            "store": false,
            "reasoning": [
                "effort": "minimal"
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "eye_focus_summary",
                    "strict": true,
                    "schema": summarySchema
                ]
            ]
        ]

        guard JSONSerialization.isValidJSONObject(body) else {
            throw OpenAIEyeFocusSummaryError.invalidRequestBody
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func prompt(logJSON: String, result: EyeFocusTestResult) -> String {
        """
        Test type: live eye-focus test with reaction taps + gaze tracking.

        Computed result:
        - Eye-focus score: \(rounded(result.eyeFocusScore))
        - Reaction score: \(rounded(result.reactionScore))
        - Average reaction: \(rounded(result.averageReactionMs)) ms
        - Reaction variability: \(rounded(result.reactionStdDevMs)) ms
        - Missed targets: \(result.missedTargets)
        - False taps: \(result.falseTaps)
        - Gaze score: \(rounded(result.gazeMetrics?.gazeScore))
        - Gaze accuracy: \(rounded(result.gazeMetrics?.gazeAccuracyPx)) px
        - Gaze stability: \(rounded(result.gazeMetrics?.gazeStabilityPx)) px
        - Fixation duration: \(rounded(result.gazeMetrics?.fixationDurationMs)) ms
        - Blink rate: \(rounded(result.gazeMetrics?.blinkRatePerMin)) / min
        - Tracking loss: \(rounded(result.gazeMetrics?.trackingLossPct))%

        Gaze log JSON (includes calibration and downsampled samples):
        \(logJSON)
        """
    }

    private func downsampledLogData(from data: Data) -> Data? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(GazeLogFile.self, from: data) else { return nil }
        let originalCount = file.samples.count
        guard originalCount > maxSamplesToSend else { return nil }

        let kept = bestSamplesPerBucket(file.samples, bucketCount: maxSamplesToSend)

        let reduced = GazeLogFile(
            backend: file.backend,
            startedAt: file.startedAt,
            testStartedAt: file.testStartedAt,
            durationSeconds: file.durationSeconds,
            frameCount: file.frameCount,
            screenWidthPx: file.screenWidthPx,
            screenHeightPx: file.screenHeightPx,
            calibration: file.calibration,
            metrics: file.metrics,
            reaction: file.reaction,
            samples: kept
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(reduced)
    }

    private func bestSamplesPerBucket(_ samples: [GazeLogSample], bucketCount: Int) -> [GazeLogSample] {
        let total = samples.count
        guard total > 0, bucketCount > 0 else { return [] }
        let bucketSize = max(1, Int(ceil(Double(total) / Double(bucketCount))))
        var kept: [GazeLogSample] = []
        kept.reserveCapacity(bucketCount + 1)

        var start = 0
        while start < total {
            let end = min(start + bucketSize, total)
            let slice = samples[start..<end]
            if let best = slice.max(by: { qualityScore($0) < qualityScore($1) }) {
                kept.append(best)
            }
            start = end
        }
        return kept
    }

    private func qualityScore(_ s: GazeLogSample) -> Int {
        var score = 0
        if s.trackingValid { score += 2 }
        if !(s.leftBlink > 0.6 && s.rightBlink > 0.6) { score += 1 }
        if !s.inSettlingWindow { score += 1 }
        if !s.inMotionCooldown { score += 1 }
        if s.motion.isStable { score += 1 }
        return score
    }

    private func promptFromLog(logJSON: String) -> String {
        """
        Test type: re-analysis from saved gaze log.
        The JSON includes precomputed gaze metrics, calibration summary, a "reaction" block
        (avg/stddev/missed/false taps/individual reaction times), and downsampled samples.
        Note: "frameCount" is the original captured frame count; the "samples" array is
        bucketed by time with only the best-quality sample per bucket retained
        (preferring trackingValid, stable device, no blink, outside settling/cooldown).
        Treat metrics, calibration, and reaction as authoritative; use samples as a
        quality-filtered trace. If the "reaction" field is missing, note it briefly.

        Gaze log JSON:
        \(logJSON)
        """
    }

    private func rounded(_ value: Double?) -> String {
        guard let value else { return "not available" }
        return String(format: "%.1f", value)
    }

    private var summarySchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "overall_summary": [
                    "type": "string"
                ],
                "confidence": [
                    "type": "string",
                    "enum": ["high", "medium", "low"]
                ],
                "sections": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "title": [
                                "type": "string"
                            ],
                            "summary": [
                                "type": "string"
                            ]
                        ],
                        "required": ["title", "summary"]
                    ]
                ]
            ],
            "required": ["overall_summary", "confidence", "sections"]
        ]
    }
}

private struct EyeFocusStructuredSummary: Decodable {
    let overallSummary: String
    let confidence: String?
    let sections: [Section]

    enum CodingKeys: String, CodingKey {
        case overallSummary = "overall_summary"
        case confidence
        case sections
    }

    struct Section: Decodable {
        let title: String
        let summary: String
    }
}

private struct OpenAIResponsesEnvelope: Decodable {
    let output: [OutputItem]?
    let error: OpenAIError?
    let status: String?
    let incompleteDetails: IncompleteDetails?

    enum CodingKeys: String, CodingKey {
        case output
        case error
        case status
        case incompleteDetails = "incomplete_details"
    }

    var outputText: String? {
        output?
            .filter { ($0.type ?? "") == "message" }
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .first
    }

    struct OutputItem: Decodable {
        let type: String?
        let content: [ContentItem]?
    }

    struct ContentItem: Decodable {
        let text: String?
    }

    struct IncompleteDetails: Decodable {
        let reason: String?
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
}

private extension Bundle {
    var openAIAPIKey: String? {
        let rawValue = infoDictionary?["VitalScoreOpenAIAPIKey"] as? String
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.contains("$("), !trimmed.contains("YOUR_") else {
            return nil
        }
        return trimmed
    }

    var openAIModel: String {
        let rawValue = infoDictionary?["VitalScoreOpenAIModel"] as? String
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty || trimmed.contains("$(") ? "gpt-5-mini" : trimmed
    }
}
