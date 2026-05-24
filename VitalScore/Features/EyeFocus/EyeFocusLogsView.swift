import SwiftUI
import Charts

struct EyeFocusLogEntry: Identifiable {
    let id: String
    let url: URL
    let date: Date
    let metrics: GazeMetrics?
    var summary: EyeFocusAISummary?

    init(url: URL, file: GazeLogFile?, summary: EyeFocusAISummary?) {
        self.id = url.lastPathComponent
        self.url = url
        self.date = file?.testStartedAt ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        self.metrics = file?.metrics
        self.summary = summary
    }
}

struct EyeFocusLogsView: View {
    @EnvironmentObject var storage: LocalStorageManager
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [EyeFocusLogEntry] = []
    @State private var analyzing: Set<String> = []
    @State private var attempted: Set<String> = []
    @State private var autoRunning = false
    @State private var errorMessage: String?

    private let client = OpenAIEyeFocusSummaryClient()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if entries.isEmpty {
                        emptyState
                    } else {
                        if hasChartableData {
                            trendChartSection
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Eye Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Analysis failed", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                reload()
                await runAutoSummarization()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No saved gaze logs yet.")
                .font(.headline)
            Text("Run an eye-focus test to generate one.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var trendChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trends")
                    .font(.headline)
                Spacer()
                if autoRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Analyzing \(analyzing.count)…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(chartMetrics) { metric in
                trendChart(for: metric)
            }
        }
    }

    private func trendChart(for metric: ChartMetric) -> some View {
        let points = entries.compactMap { entry -> (Date, Double)? in
            guard let value = metric.value(entry.metrics) else { return nil }
            return (entry.date, value)
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Chart(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.0), y: .value(metric.title, point.1))
                    .foregroundStyle(metric.color)
                PointMark(x: .value("Date", point.0), y: .value(metric.title, point.1))
                    .foregroundStyle(metric.color)
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: metric.invertAxis))
            .frame(height: 110)
            .padding(8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions")
                .font(.headline)

            ForEach(entries.reversed()) { entry in
                sessionCard(for: entry)
            }
        }
    }

    private func sessionCard(for entry: EyeFocusLogEntry) -> some View {
        let isAnalyzing = analyzing.contains(entry.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.semibold))
                    Text(entry.id)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    Task { await analyze(entry: entry, force: true) }
                } label: {
                    if isAnalyzing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(entry.summary == nil ? "Analyze" : "Re-analyze")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isAnalyzing)
            }

            if let metrics = entry.metrics {
                metricRow(metrics: metrics)
            }

            if let summary = entry.summary {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(summary.overallSummary)
                            .font(.footnote)
                        Spacer(minLength: 0)
                        if let confidence = summary.confidence {
                            confidenceChip(confidence)
                        }
                    }
                    ForEach(summary.sections) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(section.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(6)
            } else if isAnalyzing {
                Text("Generating summary…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if attempted.contains(entry.id) {
                Text("Auto-analysis failed. Tap Analyze to retry.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func metricRow(metrics: GazeMetrics) -> some View {
        HStack(spacing: 12) {
            metricChip("Score", value: String(format: "%.0f", metrics.gazeScore), tint: .indigo)
            metricChip("Accuracy", value: String(format: "%.0f px", metrics.gazeAccuracyPx), tint: .blue)
            metricChip("Stability", value: String(format: "%.0f px", metrics.gazeStabilityPx), tint: .teal)
            metricChip("Loss", value: String(format: "%.0f%%", metrics.trackingLossPct), tint: .orange)
        }
    }

    private func confidenceChip(_ confidence: String) -> some View {
        let lower = confidence.lowercased()
        let tint: Color
        switch lower {
        case "high": tint = .green
        case "medium": tint = .orange
        case "low": tint = .red
        default: tint = .secondary
        }
        return Text(lower.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15))
            .cornerRadius(4)
    }

    private func metricChip(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct ChartMetric: Identifiable {
        let id: String
        let title: String
        let color: Color
        let invertAxis: Bool
        let value: (GazeMetrics?) -> Double?
    }

    private var chartMetrics: [ChartMetric] {
        [
            ChartMetric(id: "score", title: "Gaze Score (↑ better)", color: .indigo, invertAxis: false) { $0.map { $0.gazeScore } },
            ChartMetric(id: "accuracy", title: "Accuracy (↑ better, raw px)", color: .blue, invertAxis: true) { $0.map { $0.gazeAccuracyPx } },
            ChartMetric(id: "stability", title: "Stability (↑ better, raw px)", color: .teal, invertAxis: true) { $0.map { $0.gazeStabilityPx } }
        ]
    }

    private var hasChartableData: Bool {
        entries.contains { $0.metrics != nil }
    }

    private func reload() {
        let urls = GazeDataLogger.listSavedLogs()
        let summariesByName = Dictionary(uniqueKeysWithValues: storage.loadEyeFocusSummaries().compactMap { summary -> (String, EyeFocusAISummary)? in
            guard let name = summary.sourceLogFileName else { return nil }
            return (name, summary)
        })

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        entries = urls.map { url -> EyeFocusLogEntry in
            let file = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(GazeLogFile.self, from: $0) }
            return EyeFocusLogEntry(url: url, file: file, summary: summariesByName[url.lastPathComponent])
        }
        .sorted { $0.date < $1.date }
    }

    private func runAutoSummarization() async {
        guard !autoRunning else { return }
        autoRunning = true
        defer { autoRunning = false }

        for entry in entries where entry.summary == nil && !attempted.contains(entry.id) {
            await analyze(entry: entry, force: false)
        }
    }

    private func analyze(entry: EyeFocusLogEntry, force: Bool) async {
        if analyzing.contains(entry.id) { return }
        if !force && attempted.contains(entry.id) { return }
        analyzing.insert(entry.id)
        attempted.insert(entry.id)
        defer { analyzing.remove(entry.id) }
        do {
            let summary = try await client.summarizeLog(at: entry.url)
            storage.saveEyeFocusSummary(summary)
            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[idx].summary = summary
            }
        } catch OpenAIEyeFocusSummaryError.missingAPIKey {
            errorMessage = "OpenAI API key is not configured. Add VITALSCORE_OPENAI_API_KEY to the local config to enable auto-analysis."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
