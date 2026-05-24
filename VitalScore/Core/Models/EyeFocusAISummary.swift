import Foundation

struct EyeFocusAISummary: Codable, Equatable, Identifiable {
    let id: UUID
    let resultCompletedAt: Date
    let generatedAt: Date
    let model: String
    let sourceLogFileName: String?
    let overallSummary: String
    let confidence: String?
    let sections: [EyeFocusAISummarySection]

    init(
        id: UUID = UUID(),
        resultCompletedAt: Date,
        generatedAt: Date = Date(),
        model: String,
        sourceLogFileName: String?,
        overallSummary: String,
        confidence: String? = nil,
        sections: [EyeFocusAISummarySection]
    ) {
        self.id = id
        self.resultCompletedAt = resultCompletedAt
        self.generatedAt = generatedAt
        self.model = model
        self.sourceLogFileName = sourceLogFileName
        self.overallSummary = overallSummary
        self.confidence = confidence
        self.sections = sections
    }
}

struct EyeFocusAISummarySection: Codable, Equatable, Identifiable {
    let title: String
    let summary: String

    var id: String { title }
}
