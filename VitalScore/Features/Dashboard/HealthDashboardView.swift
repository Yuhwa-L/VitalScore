import SwiftUI

struct HealthDashboardView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var experiments: ExperimentManager
    @EnvironmentObject var storage: LocalStorageManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var showEyeFocusTest = false
    @State private var showVoiceTracking = false
    @State private var showVoiceAnalysis = false
    @State private var showWellnessHistory = false
    @State private var lastWellnessResult: WellnessDeltaResult?
    @State private var showSettings = false
    @State private var showEyeFocusLogs = false

    private let engine = WellnessScoreEngine()
    private let healthColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    wellnessScoreCard
                    healthMetricGrid
                    trackingActionsRow
                    analysisOverview
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await healthKit.fetchAllLatest()
            }
            .task {
                await healthKit.fetchAllLatest()
                refreshWellnessFromStorage()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await healthKit.fetchAllLatest() }
                }
            }
            .overlay(alignment: .top) {
                if healthKit.isFetching {
                    ProgressView().padding(8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await healthKit.fetchAllLatest() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(healthKit.isFetching)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showEyeFocusLogs) {
                EyeFocusLogsView()
                    .environmentObject(storage)
            }
            .sheet(isPresented: $showWellnessHistory) {
                NavigationStack {
                    WellnessHistoryView(
                        records: storage.loadAllRecords(),
                        latestResult: latestWellnessResult
                    )
                }
            }
            .navigationDestination(isPresented: $showEyeFocusTest) {
                EyeFocusTestView(onFinished: handleEyeFocusFinished)
            }
            .navigationDestination(isPresented: $showVoiceTracking) {
                VoiceTrackingView(
                    previousSessions: storage.loadVoiceSessions(),
                    experimentTag: trackingTag,
                    onFinished: handleVoiceTrackingFinished
                )
            }
            .navigationDestination(isPresented: $showVoiceAnalysis) {
                VoiceAnalysisDashboardView(sessions: storage.loadVoiceSessions())
            }
        }
    }

    private var wellnessScoreCard: some View {
        Button {
            showWellnessHistory = true
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wellness Score")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(latestWellnessDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let confidence = latestWellnessResult?.confidence {
                        Text("\(confidence) confidence")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(latestWellnessScoreText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(wellnessScoreColor)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var healthMetricGrid: some View {
        LazyVGrid(columns: healthColumns, spacing: 10) {
            ForEach(healthMetrics) { metric in
                HealthMetricTile(metric: metric)
            }
        }
    }

    private var trackingActionsRow: some View {
        HStack(spacing: 10) {
            trackingButton(
                title: "Eye-Focus",
                systemImage: "eye",
                tint: .indigo
            ) {
                showEyeFocusTest = true
            }

            trackingButton(
                title: "Voice",
                systemImage: "waveform.path.ecg",
                tint: .teal
            ) {
                showVoiceTracking = true
            }
        }
    }

    private var analysisOverview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            AnalysisTile(
                title: "Eye Analysis",
                systemImage: "eye.circle",
                tint: .indigo,
                primaryValue: format(todayRecord?.eyeFocusScore, digits: 0) ?? "--",
                primaryUnit: "score",
                details: eyeAnalysisDetails,
                action: { showEyeFocusLogs = true }
            )

            AnalysisTile(
                title: "Voice Analysis",
                systemImage: "waveform.circle",
                tint: .teal,
                primaryValue: format(latestVoiceSession?.result.voiceScore, digits: 0) ?? "--",
                primaryUnit: "score",
                details: voiceAnalysisDetails,
                action: { showVoiceAnalysis = true }
            )
        }
    }

    private func trackingButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(tint)
            .foregroundStyle(.white)
            .cornerRadius(8)
        }
    }

    private var healthMetrics: [HealthMetricTileData] {
        [
            HealthMetricTileData(
                title: "Sleep",
                value: format(healthKit.lastNightSleepHours, digits: 1),
                unit: "h",
                baseline: format(baseline.averageSleepHours, digits: 1),
                delta: delta(healthKit.lastNightSleepHours, baseline.averageSleepHours),
                systemImage: "bed.double.fill",
                tint: .blue
            ),
            HealthMetricTileData(
                title: "Resting HR",
                value: format(healthKit.latestRestingHeartRate, digits: 0),
                unit: "bpm",
                baseline: format(baseline.averageRestingHeartRateBPM, digits: 0),
                delta: delta(healthKit.latestRestingHeartRate, baseline.averageRestingHeartRateBPM, inverted: true),
                systemImage: "heart.fill",
                tint: .red
            ),
            HealthMetricTileData(
                title: "HRV",
                value: format(healthKit.latestHRV, digits: 0),
                unit: "ms",
                baseline: format(baseline.averageHRVMs, digits: 0),
                delta: delta(healthKit.latestHRV, baseline.averageHRVMs),
                systemImage: "waveform.path",
                tint: .purple
            ),
            HealthMetricTileData(
                title: "Steps",
                value: format(healthKit.todaySteps, digits: 0),
                unit: "",
                baseline: format(baseline.averageStepCount, digits: 0),
                delta: delta(healthKit.todaySteps, baseline.averageStepCount),
                systemImage: "figure.walk",
                tint: .green
            ),
            HealthMetricTileData(
                title: "Energy",
                value: format(healthKit.todayActiveEnergy, digits: 0),
                unit: "kcal",
                baseline: nil,
                delta: nil,
                systemImage: "flame.fill",
                tint: .orange
            )
        ]
    }

    private var eyeAnalysisDetails: [String] {
        let record = todayRecord
        return [
            detailText("Gaze", value: format(record?.gazeScore, digits: 0), unit: ""),
            storage.latestEyeFocusSummary()?.overallSummary
                ?? detailText("Reaction", value: format(record?.averageReactionMs, digits: 0), unit: "ms")
        ]
    }

    private var voiceAnalysisDetails: [String] {
        [
            detailText("Sessions", value: "\(storage.loadVoiceSessions().count)", unit: ""),
            latestVoiceSession?.result.eGeMAPS == nil ? "eGeMAPS pending" : "eGeMAPS ready"
        ]
    }

    private var latestWellnessResult: WellnessDeltaResult? {
        if let lastWellnessResult {
            return lastWellnessResult
        }
        guard let record = latestWellnessRecord else { return nil }
        return WellnessDeltaResult(
            score: record.wellnessDeltaScore,
            confidence: record.confidenceLevel,
            insightText: record.insightText,
            availableMetricCount: 0,
            positiveMetricCount: 0
        )
    }

    private var latestWellnessRecord: DailyHealthRecord? {
        storage.loadAllRecords()
            .filter { !$0.insightText.isEmpty || $0.wellnessDeltaScore != 0 }
            .sorted { $0.date < $1.date }
            .last
    }

    private var latestWellnessScoreText: String {
        guard let result = latestWellnessResult else { return "--" }
        return "\(result.score >= 0 ? "+" : "")\(result.score)"
    }

    private var latestWellnessDateText: String {
        guard let record = latestWellnessRecord else { return "No score yet" }
        return record.date.formatted(date: .abbreviated, time: .omitted)
    }

    private var wellnessScoreColor: Color {
        guard let score = latestWellnessResult?.score else { return .secondary }
        if score > 2 { return .green }
        if score < -2 { return .red }
        return .primary
    }

    private var baseline: BaselineMetrics {
        engine.buildBaseline(from: storage.loadAllRecords())
    }

    private var todayRecord: DailyHealthRecord? {
        storage.loadAllRecords()
            .first(where: { Calendar.current.isDateInToday($0.date) })
    }

    private var trackingTag: String {
        experiments.current == nil ? "Untagged" : experiments.displayName
    }

    private var latestVoiceSession: VoiceTrackingSession? {
        storage.loadVoiceSessions().sorted { $0.date < $1.date }.last
    }

    private func handleEyeFocusFinished(_ result: EyeFocusTestResult) {
        if let summary = result.aiSummary {
            storage.saveEyeFocusSummary(summary)
        }

        let baselineNow = baseline
        let existingRecord = todayRecord
        let todayRecord = DailyHealthRecord(
            id: existingRecord?.id ?? UUID(),
            date: existingRecord?.date ?? Date(),
            experimentTag: existingRecord?.experimentTag ?? trackingTag,
            sleepHours: existingRecord?.sleepHours ?? healthKit.lastNightSleepHours,
            restingHeartRateBPM: existingRecord?.restingHeartRateBPM ?? healthKit.latestRestingHeartRate,
            hrvMs: existingRecord?.hrvMs ?? healthKit.latestHRV,
            stepCount: existingRecord?.stepCount ?? healthKit.todaySteps,
            activeEnergyKcal: existingRecord?.activeEnergyKcal ?? healthKit.todayActiveEnergy,
            eyeFocusScore: result.eyeFocusScore,
            averageReactionMs: result.averageReactionMs,
            reactionStdDevMs: result.reactionStdDevMs,
            missedTargets: result.missedTargets,
            falseTaps: result.falseTaps,
            gazeAccuracyPx: result.gazeMetrics?.gazeAccuracyPx,
            gazeStabilityPx: result.gazeMetrics?.gazeStabilityPx,
            gazeFixationMs: result.gazeMetrics?.fixationDurationMs,
            gazeBlinkRatePerMin: result.gazeMetrics?.blinkRatePerMin,
            gazeTrackingLossPct: result.gazeMetrics?.trackingLossPct,
            gazeScore: result.gazeMetrics?.gazeScore,
            balanceScore: existingRecord?.balanceScore,
            swayIndex: existingRecord?.swayIndex,
            voiceScore: existingRecord?.voiceScore,
            voiceAverageVolumeDb: existingRecord?.voiceAverageVolumeDb,
            voiceVolumeStdDevDb: existingRecord?.voiceVolumeStdDevDb,
            voiceSilenceRatio: existingRecord?.voiceSilenceRatio,
            voicePeakVolumeDb: existingRecord?.voicePeakVolumeDb,
            selfReportedEnergy: existingRecord?.selfReportedEnergy,
            selfReportedStress: existingRecord?.selfReportedStress,
            selfReportedSleepQuality: existingRecord?.selfReportedSleepQuality,
            wellnessDeltaScore: 0,
            confidenceLevel: "Low",
            insightText: ""
        )
        saveRecordWithWellness(todayRecord, baseline: baselineNow)
        showEyeFocusTest = false
        showWellnessHistory = false
    }

    private func handleVoiceTrackingFinished(_ session: VoiceTrackingSession) {
        let existing = todayRecord
        let result = session.result
        storage.saveVoiceSession(session)

        let record = DailyHealthRecord(
            id: existing?.id ?? UUID(),
            date: existing?.date ?? Date(),
            experimentTag: existing?.experimentTag ?? trackingTag,
            sleepHours: existing?.sleepHours ?? healthKit.lastNightSleepHours,
            restingHeartRateBPM: existing?.restingHeartRateBPM ?? healthKit.latestRestingHeartRate,
            hrvMs: existing?.hrvMs ?? healthKit.latestHRV,
            stepCount: existing?.stepCount ?? healthKit.todaySteps,
            activeEnergyKcal: existing?.activeEnergyKcal ?? healthKit.todayActiveEnergy,
            eyeFocusScore: existing?.eyeFocusScore,
            averageReactionMs: existing?.averageReactionMs,
            reactionStdDevMs: existing?.reactionStdDevMs,
            missedTargets: existing?.missedTargets,
            falseTaps: existing?.falseTaps,
            gazeAccuracyPx: existing?.gazeAccuracyPx,
            gazeStabilityPx: existing?.gazeStabilityPx,
            gazeFixationMs: existing?.gazeFixationMs,
            gazeBlinkRatePerMin: existing?.gazeBlinkRatePerMin,
            gazeTrackingLossPct: existing?.gazeTrackingLossPct,
            gazeScore: existing?.gazeScore,
            balanceScore: existing?.balanceScore,
            swayIndex: existing?.swayIndex,
            voiceScore: result.voiceScore,
            voiceAverageVolumeDb: result.averageVolumeDb,
            voiceVolumeStdDevDb: result.volumeStdDevDb,
            voiceSilenceRatio: result.silenceRatio,
            voicePeakVolumeDb: result.peakVolumeDb,
            selfReportedEnergy: existing?.selfReportedEnergy,
            selfReportedStress: existing?.selfReportedStress,
            selfReportedSleepQuality: existing?.selfReportedSleepQuality,
            wellnessDeltaScore: existing?.wellnessDeltaScore ?? 0,
            confidenceLevel: existing?.confidenceLevel ?? "Low",
            insightText: existing?.insightText ?? ""
        )
        saveRecordWithWellness(record, baseline: baseline)
        showVoiceTracking = false
        showVoiceAnalysis = true
    }

    private func saveRecordWithWellness(_ record: DailyHealthRecord, baseline: BaselineMetrics) {
        let computed = engine.calculate(today: record, baseline: baseline)
        let finalRecord = DailyHealthRecord(
            id: record.id,
            date: record.date,
            experimentTag: record.experimentTag,
            sleepHours: record.sleepHours,
            restingHeartRateBPM: record.restingHeartRateBPM,
            hrvMs: record.hrvMs,
            stepCount: record.stepCount,
            activeEnergyKcal: record.activeEnergyKcal,
            eyeFocusScore: record.eyeFocusScore,
            averageReactionMs: record.averageReactionMs,
            reactionStdDevMs: record.reactionStdDevMs,
            missedTargets: record.missedTargets,
            falseTaps: record.falseTaps,
            gazeAccuracyPx: record.gazeAccuracyPx,
            gazeStabilityPx: record.gazeStabilityPx,
            gazeFixationMs: record.gazeFixationMs,
            gazeBlinkRatePerMin: record.gazeBlinkRatePerMin,
            gazeTrackingLossPct: record.gazeTrackingLossPct,
            gazeScore: record.gazeScore,
            balanceScore: record.balanceScore,
            swayIndex: record.swayIndex,
            voiceScore: record.voiceScore,
            voiceAverageVolumeDb: record.voiceAverageVolumeDb,
            voiceVolumeStdDevDb: record.voiceVolumeStdDevDb,
            voiceSilenceRatio: record.voiceSilenceRatio,
            voicePeakVolumeDb: record.voicePeakVolumeDb,
            selfReportedEnergy: record.selfReportedEnergy,
            selfReportedStress: record.selfReportedStress,
            selfReportedSleepQuality: record.selfReportedSleepQuality,
            wellnessDeltaScore: computed.score,
            confidenceLevel: computed.confidence,
            insightText: computed.insightText
        )
        storage.saveRecord(finalRecord)
        lastWellnessResult = computed
    }

    private func refreshWellnessFromStorage() {
        guard let record = latestWellnessRecord else { return }
        lastWellnessResult = WellnessDeltaResult(
            score: record.wellnessDeltaScore,
            confidence: record.confidenceLevel,
            insightText: record.insightText,
            availableMetricCount: 0,
            positiveMetricCount: 0
        )
    }

    private func detailText(_ label: String, value: String?, unit: String) -> String {
        guard let value else { return "\(label) --" }
        return "\(label) \(value)\(unit.isEmpty ? "" : " \(unit)")"
    }

    private func format(_ value: Double?, digits: Int) -> String? {
        guard let value else { return nil }
        return String(format: "%.\(digits)f", value)
    }

    private func delta(_ current: Double?, _ base: Double?, inverted: Bool = false) -> Double? {
        guard let current, let base, base > 0 else { return nil }
        let raw = (current - base) / base * 100
        return inverted ? -raw : raw
    }
}

private struct HealthMetricTileData: Identifiable {
    let id = UUID()
    let title: String
    let value: String?
    let unit: String
    let baseline: String?
    let delta: Double?
    let systemImage: String
    let tint: Color
}

private struct HealthMetricTile: View {
    let metric: HealthMetricTileData

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: metric.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Spacer()
                if let delta = metric.delta {
                    deltaIcon(delta)
                }
            }

            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.value ?? "--")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(metric.baseline.map { "Base \($0)" } ?? "Base --")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func deltaIcon(_ delta: Double) -> some View {
        let icon: String
        let color: Color
        if delta > 0.5 {
            icon = "arrow.up"
            color = .green
        } else if delta < -0.5 {
            icon = "arrow.down"
            color = .red
        } else {
            icon = "minus"
            color = .secondary
        }

        return Image(systemName: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
    }
}

private struct AnalysisTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    let primaryValue: String
    let primaryUnit: String
    let details: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(tint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(primaryValue)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(primaryUnit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(details.prefix(2), id: \.self) { detail in
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
