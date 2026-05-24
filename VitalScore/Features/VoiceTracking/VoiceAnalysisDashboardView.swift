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
                    baselineReadinessPanel
                    scoreTrend
                    topDriversPanel
                    transcriptPanel
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
        let xDomain = scoreTrendXDomain
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Voice Score History")
                    .font(.headline)
                Spacer()
                if let latest = latestSession {
                    Text("Latest \(format(latest.result.voiceScore, digits: 0) ?? "--")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }
            Chart(sortedSessions) { session in
                LineMark(
                    x: .value("Date", session.date),
                    y: .value("Score", session.result.voiceScore)
                )
                .foregroundStyle(.teal)
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", session.date),
                    y: .value("Score", session.result.voiceScore)
                )
                .foregroundStyle(session.result.usable ? .teal : .orange)
                .symbolSize(session.id == latestSession?.id ? 110 : 60)
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: xDomain.lowerBound...xDomain.upperBound)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100])
            }
            .frame(height: 200)
        }
        .panelStyle()
    }

    private var scoreTrendXDomain: ClosedRange<Date> {
        let now = Date()
        let earliest = sortedSessions.first?.date ?? now
        let latest = min(sortedSessions.last?.date ?? now, now)
        let lower = min(earliest, latest)
        // Always give the chart at least a 24h window so a single point doesn't collapse.
        let upper = max(latest, lower.addingTimeInterval(86_400))
        return lower...upper
    }

    private var baselineReadinessPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Personal Baseline v2")
                .font(.headline)
            Text("Wellness reflection only. This dashboard tracks personal change and avoids medical interpretation.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: min(Double(usableSessions.count), 7), total: 7)
                .tint(.teal)
            HStack {
                compactMetric("Baseline", "\(min(usableSessions.count, 7))/7", "usable")
                compactMetric("Long term", "\(min(usableSessions.count, 30))/30", "usable")
                compactMetric("Status", latestSession?.result.baselineStatus.replacingOccurrences(of: "_", with: " "), "")
            }
        }
        .panelStyle()
    }

    private var topDriversPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Changed Acoustic Drivers")
                .font(.headline)
            ForEach(latestSession?.result.topDrivers ?? [], id: \.self) { driver in
                Text(driver)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if latestSession?.result.topDrivers.isEmpty != false {
                Text("Top drivers appear after enough usable personal baseline sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript-Derived Speech")
                .font(.headline)
            HStack(spacing: 12) {
                compactMetric("Words", "\(latestTranscriptStats.wordCount)", "")
                compactMetric("Speech rate", format(latestTranscriptStats.wordsPerMinute, digits: 0), "wpm")
                compactMetric("Turns", "\(latestTranscriptStats.turnCount)", "")
            }
            if latestTranscriptStats.turnCount == 0 {
                Text("No AI conversation transcript was captured for the latest session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                    featureRow("f0MeanHz", "F0 mean", format(features.f0MeanHz, digits: 0), "Hz"),
                    featureRow("f0StdDevHz", "F0 variation", format(features.f0StdDevHz, digits: 1), "Hz"),
                    featureRow("jitterLocalPercent", "Jitter local", format(features.jitterLocalPercent, digits: 2), "%")
                ]
            )
            featureSection(
                "Energy",
                rows: [
                    featureRow("loudnessMeanDb", "Loudness mean", format(features.loudnessMeanDb, digits: 1), "dB"),
                    featureRow("loudnessStdDevDb", "Loudness variation", format(features.loudnessStdDevDb, digits: 1), "dB"),
                    featureRow("shimmerLocalDb", "Shimmer local", format(features.shimmerLocalDb, digits: 2), "dB")
                ]
            )
            featureSection(
                "Spectral and Voice Quality",
                rows: [
                    featureRow("hnrMeanDb", "HNR mean", format(features.hnrMeanDb, digits: 1), "dB"),
                    featureRow("alphaRatioDb", "Alpha ratio", format(features.alphaRatioDb, digits: 1), "dB"),
                    featureRow("hammarbergIndexDb", "Hammarberg index", format(features.hammarbergIndexDb, digits: 1), "dB"),
                    featureRow("spectralFlux", "Spectral flux", format(features.spectralFlux, digits: 3), "")
                ]
            )
            featureSection(
                "Cepstral and Temporal",
                rows: [
                    featureRow("mfcc1Mean", "MFCC 1", format(features.mfcc1Mean, digits: 2), ""),
                    featureRow("mfcc2Mean", "MFCC 2", format(features.mfcc2Mean, digits: 2), ""),
                    featureRow("mfcc3Mean", "MFCC 3", format(features.mfcc3Mean, digits: 2), ""),
                    featureRow("voicedSegmentsPerSecond", "Voiced segments", format(features.voicedSegmentsPerSecond, digits: 2), "/s"),
                    featureRow("meanVoicedSegmentLengthSeconds", "Mean voiced length", format(features.meanVoicedSegmentLengthSeconds, digits: 2), "s")
                ]
            )
            Text("Score uses validated fields or stable proxies only; unsupported feature placeholders are excluded.")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            Text("Long-Term Analysis")
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

    private func featureSection(_ title: String, rows: [FeatureRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(rows) { row in
                HStack {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text((row.value ?? "--") + (row.unit.isEmpty ? "" : " \(row.unit)"))
                        .fontWeight(.medium)
                    validationBadge(row.validation.status)
                }
                .font(.caption)
            }
        }
    }

    private func featureRow(_ key: String, _ label: String, _ value: String?, _ unit: String) -> FeatureRow {
        FeatureRow(label: label, value: value, unit: unit, validation: VoiceFeatureValidationCatalog.validation(for: key))
    }

    private func validationBadge(_ status: VoiceFeatureValidationStatus) -> some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.16))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: VoiceFeatureValidationStatus) -> Color {
        switch status {
        case .validated: return .green
        case .proxy: return .teal
        case .unsupported: return .orange
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

    private var latestTranscriptStats: TranscriptStats {
        let exchanges = latestSession?.result.conversationExchanges ?? []
        let wordCount = exchanges.reduce(0) { $0 + $1.userTranscript.wordCount }
        let duration = exchanges.reduce(0) { $0 + $1.responseDurationSeconds }
        let wordsPerMinute = duration > 0 ? Double(wordCount) / duration * 60 : 0
        return TranscriptStats(
            turnCount: exchanges.count,
            wordCount: wordCount,
            durationSeconds: duration,
            wordsPerMinute: wordsPerMinute
        )
    }
}

private struct FeatureRow: Identifiable {
    var id: String { label }
    let label: String
    let value: String?
    let unit: String
    let validation: VoiceFeatureValidation
}

private struct TranscriptStats {
    let turnCount: Int
    let wordCount: Int
    let durationSeconds: TimeInterval
    let wordsPerMinute: Double
}

private extension View {
    func panelStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
    }
}

private extension String {
    var wordCount: Int {
        split { $0.isWhitespace || $0.isNewline }.count
    }
}
