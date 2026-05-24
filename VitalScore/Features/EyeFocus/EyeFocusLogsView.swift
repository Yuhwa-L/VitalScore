import SwiftUI
import Charts

struct EyeFocusLogEntry: Identifiable {
    let id: String
    let url: URL
    let date: Date
    let experimentTag: String
    let metrics: GazeMetrics?

    init(url: URL, file: GazeLogFile?, summary: EyeFocusAISummary?) {
        self.id = url.lastPathComponent
        self.url = url
        self.date = file?.testStartedAt ?? summary?.resultCompletedAt ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        self.experimentTag = ExperimentTagValue.normalized(file?.experimentTag ?? summary?.experimentTag)
        self.metrics = file?.metrics
    }
}

struct EyeFocusLogsView: View {
    let tagFilter: String?
    let dateInterval: DateInterval?

    @EnvironmentObject var storage: LocalStorageManager
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [EyeFocusLogEntry] = []

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
            .task {
                reload()
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
            Text("Trends")
                .font(.headline)

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
        let summariesByName = Dictionary(uniqueKeysWithValues: storage.loadEyeFocusSummaries(tagFilter: tagFilter, dateInterval: dateInterval).compactMap { summary -> (String, EyeFocusAISummary)? in
            guard let name = summary.sourceLogFileName else { return nil }
            return (name, summary)
        })

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        entries = urls.map { url -> EyeFocusLogEntry in
            let file = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(GazeLogFile.self, from: $0) }
            return EyeFocusLogEntry(url: url, file: file, summary: summariesByName[url.lastPathComponent])
        }
        .filter { ExperimentTagValue.matches($0.experimentTag, filter: tagFilter) }
        .filter { matchesSelectedPeriod($0.date) }
        .sorted { $0.date < $1.date }
    }

    private func matchesSelectedPeriod(_ date: Date) -> Bool {
        guard let dateInterval else { return true }
        return date >= dateInterval.start && date < dateInterval.end
    }
}
