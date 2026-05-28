import Charts
import SwiftUI

struct WellnessHistoryView: View {
    let records: [DailyHealthRecord]
    let latestResult: WellnessDeltaResult?

    @Environment(\.dismiss) private var dismiss

    private var scoredRecords: [DailyHealthRecord] {
        records
            .filter { !$0.insightText.isEmpty || $0.wellnessDeltaScore != 0 }
            .sorted { $0.date < $1.date }
    }

    private var latestRecord: DailyHealthRecord? {
        scoredRecords.last
    }

    private var latestScoreText: String {
        guard let score = latestResult?.score ?? latestRecord?.wellnessDeltaScore else { return "--" }
        return "\(score >= 0 ? "+" : "")\(score)"
    }

    private var latestConfidence: String {
        latestResult?.confidence ?? latestRecord?.confidenceLevel ?? "Low"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                latestSummary

                if scoredRecords.isEmpty {
                    emptyState
                } else {
                    scoreTrend
                    analysisPanel
                    historyList
                }
            }
            .padding()
        }
        .navigationTitle("Wellness")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var latestSummary: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Latest Wellness Score")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(latestRecord?.date.formatted(date: .abbreviated, time: .omitted) ?? "No history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(latestConfidence) confidence")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(latestScoreText)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor(latestResult?.score ?? latestRecord?.wellnessDeltaScore))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No wellness history yet")
                .font(.headline)
            Text("Complete a tracking run after baseline data is available.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private var scoreTrend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Score History")
                .font(.headline)
            Chart(scoredRecords) { record in
                LineMark(
                    x: .value("Date", record.date),
                    y: .value("Score", record.wellnessDeltaScore)
                )
                .foregroundStyle(.blue)
                PointMark(
                    x: .value("Date", record.date),
                    y: .value("Score", record.wellnessDeltaScore)
                )
                .foregroundStyle(scoreColor(record.wellnessDeltaScore))
            }
            .chartYScale(domain: -20...20)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 190)
        }
        .panelStyle()
    }

    private var analysisPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest Report")
                .font(.headline)

            ForEach(latestInsightLines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclaimerBanner()
        }
        .panelStyle()
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)
            ForEach(Array(scoredRecords.reversed())) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.date, style: .date)
                            .font(.subheadline.weight(.semibold))
                        Text(record.confidenceLevel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(record.wellnessDeltaScore >= 0 ? "+" : "")\(record.wellnessDeltaScore)")
                        .font(.headline)
                        .foregroundStyle(scoreColor(record.wellnessDeltaScore))
                }
                .padding(.vertical, 6)
            }
        }
        .panelStyle()
    }

    private var latestInsightLines: [String] {
        let text = latestResult?.insightText ?? latestRecord?.insightText ?? ""
        let lines = text.split(separator: "\n").map(String.init)
        return lines.isEmpty ? ["More history is needed before a stable report is available."] : lines
    }

    private func scoreColor(_ score: Int?) -> Color {
        guard let score else { return .secondary }
        if score > 2 { return .green }
        if score < -2 { return .red }
        return .primary
    }
}

private extension View {
    func panelStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
    }
}

struct WellnessSuggestionsView: View {
    let records: [DailyHealthRecord]
    let voiceSessions: [VoiceTrackingSession]
    let tagFilter: String?
    let dateInterval: DateInterval?

    @Environment(\.dismiss) private var dismiss
    @State private var report: WellnessSuggestionReport?
    @State private var isLoading = false
    @State private var statusMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let report {
                    summaryPanel(report)
                    patternsPanel(report)
                    suggestionsList(report)
                    nextStepPanel(report)
                    DisclaimerBanner()
                } else {
                    loadingPanel
                }
            }
            .padding()
        }
        .navigationTitle("AI Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await loadSuggestions(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await loadSuggestions(force: false)
        }
    }

    private var loadingPanel: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.blue)
            Text("Reviewing saved trends")
                .font(.headline)
            Text("Suggestions will use baseline, score history, voice, eye-focus, sleep, HRV, resting heart rate, steps, and available tags.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func summaryPanel(_ report: WellnessSuggestionReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(sourceTitle(report), systemImage: sourceIcon(report))
                    .font(.headline)
                Spacer()
                Text(report.confidence)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(6)
            }

            Text(report.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(report.analyzedRecordCount) record\(report.analyzedRecordCount == 1 ? "" : "s") analyzed")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func patternsPanel(_ report: WellnessSuggestionReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Observed Patterns")
                .font(.headline)

            ForEach(report.observedPatterns.prefix(5), id: \.self) { pattern in
                Label(pattern, systemImage: "chart.xyaxis.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelStyle()
    }

    private func suggestionsList(_ report: WellnessSuggestionReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested Experiments")
                .font(.headline)

            ForEach(report.suggestions) { suggestion in
                WellnessSuggestionCard(suggestion: suggestion)
            }
        }
    }

    private func nextStepPanel(_ report: WellnessSuggestionReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Next Check-In", systemImage: "checklist")
                .font(.headline)

            Text(report.nextCheckIn)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text(report.clinicianNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    @MainActor
    private func loadSuggestions(force: Bool) async {
        if isLoading { return }
        if report != nil, !force { return }

        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            report = try await AIConversationClient().generateWellnessSuggestions(
                records: records,
                voiceSessions: voiceSessions,
                tagFilter: tagFilter,
                dateInterval: dateInterval
            )
        } catch {
            let fallback = WellnessSuggestionEngine().localReport(
                records: records,
                voiceSessions: voiceSessions,
                tagFilter: tagFilter,
                unavailableReason: error.localizedDescription
            )
            report = fallback
            statusMessage = "Using local suggestions because AI suggestions are unavailable."
        }
    }

    private func sourceTitle(_ report: WellnessSuggestionReport) -> String {
        report.source.contains("openai") ? "AI Suggestions" : "Local Suggestions"
    }

    private func sourceIcon(_ report: WellnessSuggestionReport) -> String {
        report.source.contains("openai") ? "sparkles" : "lock.shield"
    }
}

private struct WellnessSuggestionCard: View {
    let suggestion: WellnessSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.subheadline.weight(.semibold))
                    Text(suggestion.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(suggestion.confidence)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(suggestion.suggestion)
                .font(.subheadline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 5) {
                Text("Track")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(suggestion.trackingPlan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(suggestion.evidence.prefix(3), id: \.self) { evidence in
                Label(evidence, systemImage: "smallcircle.filled.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var iconName: String {
        switch suggestion.category {
        case .sleep: return "bed.double"
        case .activity: return "figure.walk"
        case .nutrition: return "fork.knife"
        case .stress: return "wind"
        case .measurement: return "calendar.badge.clock"
        case .healthcare: return "person.crop.circle.badge.questionmark"
        }
    }

    private var tint: Color {
        switch suggestion.category {
        case .sleep: return .indigo
        case .activity: return .green
        case .nutrition: return .orange
        case .stress: return .teal
        case .measurement: return .blue
        case .healthcare: return .gray
        }
    }
}
