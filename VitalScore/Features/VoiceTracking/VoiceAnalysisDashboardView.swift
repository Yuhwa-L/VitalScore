import Charts
import SwiftUI

struct VoiceAnalysisDashboardView: View {
    let sessions: [VoiceTrackingSession]

    private var sortedSessions: [VoiceTrackingSession] {
        sessions.sorted { $0.date < $1.date }
    }

    private var latestSession: VoiceTrackingSession? {
        sortedSessions.last
    }

    private var usableSessions: [VoiceTrackingSession] {
        sortedSessions.filter { $0.result.usable }
    }

    private var latestTaskAnalyses: [VoiceTaskAnalysis] {
        latestSession?.result.taskAnalyses ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if sessions.isEmpty {
                    emptyState
                } else {
                    summaryGrid
                    scoreTrend
                    if let features = latestSession?.result.eGeMAPS {
                        eGeMAPSPanel(features)
                    }
                    taskBreakdown
                    historyList
                    longTermPanel
                }
            }
            .padding()
        }
        .navigationTitle("Voice Analysis")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 52))
                .foregroundStyle(.teal)
            Text("No voice analysis yet")
                .font(.headline)
            Text("Run voice tracking to start storing eGeMAPS acoustic features and building history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCard("Latest", value: format(latestSession?.result.voiceScore, digits: 0), unit: "")
            statCard("Sessions", value: "\(sessions.count)", unit: "")
            statCard("Baseline", value: "\(latestSession?.result.baselineSessionsUsed ?? 0)", unit: "sessions")
            statCard("Quality", value: format((latestSession?.result.overallQualityScore ?? 0) * 100, digits: 0), unit: "%")
        }
    }

    private var scoreTrend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice Score History")
                .font(.headline)
            Chart(sortedSessions) { session in
                LineMark(
                    x: .value("Date", session.date),
                    y: .value("Score", session.result.voiceScore)
                )
                .foregroundStyle(.teal)
                PointMark(
                    x: .value("Date", session.date),
                    y: .value("Score", session.result.voiceScore)
                )
                .foregroundStyle(session.result.usable ? .teal : .orange)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 180)
        }
        .panelStyle()
    }

    private func eGeMAPSPanel(_ features: VoiceEGeMAPSFeatureSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest eGeMAPS Features")
                    .font(.headline)
                Spacer()
                Text(latestSession?.result.featureExtractorVersion ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            featureSection(
                "Frequency",
                rows: [
                    ("F0 mean", format(features.f0MeanHz, digits: 0), "Hz"),
                    ("F0 variation", format(features.f0StdDevHz, digits: 1), "Hz"),
                    ("Jitter local", format(features.jitterLocalPercent, digits: 2), "%")
                ]
            )
            featureSection(
                "Energy",
                rows: [
                    ("Loudness mean", format(features.loudnessMeanDb, digits: 1), "dB"),
                    ("Loudness variation", format(features.loudnessStdDevDb, digits: 1), "dB"),
                    ("Shimmer local", format(features.shimmerLocalDb, digits: 2), "dB")
                ]
            )
            featureSection(
                "Spectral and Voice Quality",
                rows: [
                    ("HNR mean", format(features.hnrMeanDb, digits: 1), "dB"),
                    ("Alpha ratio", format(features.alphaRatioDb, digits: 1), "dB"),
                    ("Hammarberg index", format(features.hammarbergIndexDb, digits: 1), "dB"),
                    ("Spectral flux", format(features.spectralFlux, digits: 3), "")
                ]
            )
            featureSection(
                "Cepstral and Temporal",
                rows: [
                    ("MFCC 1", format(features.mfcc1Mean, digits: 2), ""),
                    ("MFCC 2", format(features.mfcc2Mean, digits: 2), ""),
                    ("MFCC 3", format(features.mfcc3Mean, digits: 2), ""),
                    ("Voiced segments", format(features.voicedSegmentsPerSecond, digits: 2), "/s"),
                    ("Mean voiced length", format(features.meanVoicedSegmentLengthSeconds, digits: 2), "s")
                ]
            )
        }
        .panelStyle()
    }

    private var taskBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Task Breakdown")
                .font(.headline)
            taskRow(at: 0)
            taskRow(at: 1)
            taskRow(at: 2)
            taskRow(at: 3)
            taskRow(at: 4)
        }
        .panelStyle()
    }

    @ViewBuilder
    private func taskRow(at index: Int) -> some View {
        if index >= 0 && index < latestTaskAnalyses.count {
            let task = latestTaskAnalyses[index]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(task.taskType.displayName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(task.qualityScore * 100))% quality")
                        .font(.caption)
                        .foregroundColor(task.usable ? .secondary : .orange)
                }
                HStack(spacing: 12) {
                    compactMetric("Volume", format(task.averageVolumeDb, digits: 0), "dB")
                    compactMetric("Silence", format(task.silenceRatio * 100, digits: 0), "%")
                    compactMetric("SNR", format(task.snrDb, digits: 0), "dB")
                }
                if let features = task.eGeMAPS {
                    HStack(spacing: 12) {
                        compactMetric("F0", format(features.f0MeanHz, digits: 0), "Hz")
                        compactMetric("Jitter", format(features.jitterLocalPercent, digits: 2), "%")
                        compactMetric("HNR", format(features.hnrMeanDb, digits: 1), "dB")
                    }
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stored Sessions")
                .font(.headline)
            ForEach(sortedSessions.reversed()) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.date, style: .date)
                            .font(.subheadline.weight(.semibold))
                        Text(session.experimentTag)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(format(session.result.voiceScore, digits: 0) ?? "--")
                            .font(.headline)
                        Text(session.result.voiceConfidence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .panelStyle()
    }

    private var longTermPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Long-Term Dashboard")
                .font(.headline)
            Text(longTermStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: min(Double(usableSessions.count), 30), total: 30)
                .tint(.teal)
        }
        .panelStyle()
    }

    private var longTermStatus: String {
        if usableSessions.count >= 30 {
            return "Ready for 30-session trend, variability, and experiment comparison analysis."
        }
        return "Collect \(max(0, 30 - usableSessions.count)) more usable sessions to unlock stable long-term trend analysis."
    }

    private func featureSection(_ title: String, rows: [(String, String?, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text((row.1 ?? "--") + (row.2.isEmpty ? "" : " \(row.2)"))
                        .fontWeight(.medium)
                }
                .font(.caption)
            }
        }
    }

    private func statCard(_ title: String, value: String?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "--")
                    .font(.title3.weight(.semibold))
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func compactMetric(_ label: String, _ value: String?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text((value ?? "--") + (unit.isEmpty ? "" : " \(unit)"))
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func format(_ value: Double?, digits: Int) -> String? {
        guard let value = value else { return nil }
        return String(format: "%.\(digits)f", value)
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
