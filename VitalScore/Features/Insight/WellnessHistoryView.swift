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
