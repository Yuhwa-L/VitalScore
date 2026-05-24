import SwiftUI

struct HealthDashboardView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var experiments: ExperimentManager
    @EnvironmentObject var storage: LocalStorageManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var showEyeFocusTest = false
    @State private var lastWellnessResult: WellnessDeltaResult?
    @State private var showInsight = false
    @State private var seedMessage: String?
    @State private var showSettings = false

    private let engine = WellnessScoreEngine()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    experimentHeader
                    MetricCard(
                        title: "Sleep",
                        value: format(healthKit.lastNightSleepHours, digits: 1),
                        baseline: format(baseline.averageSleepHours, digits: 1),
                        delta: delta(healthKit.lastNightSleepHours, baseline.averageSleepHours),
                        unit: "hours"
                    )
                    MetricCard(
                        title: "Resting Heart Rate",
                        value: format(healthKit.latestRestingHeartRate, digits: 0),
                        baseline: format(baseline.averageRestingHeartRateBPM, digits: 0),
                        delta: delta(healthKit.latestRestingHeartRate, baseline.averageRestingHeartRateBPM, inverted: true),
                        unit: "BPM"
                    )
                    MetricCard(
                        title: "HRV",
                        value: format(healthKit.latestHRV, digits: 0),
                        baseline: format(baseline.averageHRVMs, digits: 0),
                        delta: delta(healthKit.latestHRV, baseline.averageHRVMs),
                        unit: "ms"
                    )
                    MetricCard(
                        title: "Steps",
                        value: format(healthKit.todaySteps, digits: 0),
                        baseline: format(baseline.averageStepCount, digits: 0),
                        delta: delta(healthKit.todaySteps, baseline.averageStepCount),
                        unit: ""
                    )
                    MetricCard(
                        title: "Active Energy",
                        value: format(healthKit.todayActiveEnergy, digits: 0),
                        baseline: nil,
                        delta: nil,
                        unit: "kcal"
                    )
                    MetricCard(
                        title: "Wellness Delta",
                        value: lastWellnessResult.map { ($0.score >= 0 ? "+" : "") + "\($0.score)" },
                        baseline: lastWellnessResult?.confidence,
                        delta: lastWellnessResult.map { Double($0.score) },
                        unit: ""
                    )

                    Button {
                        showEyeFocusTest = true
                    } label: {
                        Text("Run Eye-Focus Test")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    #if DEBUG
                    Button {
                        healthKit.generateRandom()
                        seedMessage = "New mock data generated ✓"
                    } label: {
                        Text("Generate Random Data")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(12)
                    }
                    if let seedMessage = seedMessage {
                        Text(seedMessage).font(.caption).foregroundColor(.secondary)
                    }
                    #endif
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
            .navigationDestination(isPresented: $showEyeFocusTest) {
                EyeFocusTestView(onFinished: handleEyeFocusFinished)
            }
            .navigationDestination(isPresented: $showInsight) {
                if let result = lastWellnessResult {
                    InsightReportView(result: result)
                }
            }
        }
    }

    private var experimentHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Experiment")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(experiments.displayName)
                    .font(.headline)
            }
            Spacer()
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    private var baseline: BaselineMetrics {
        engine.buildBaseline(from: storage.loadAllRecords())
    }

    private func handleEyeFocusFinished(_ result: EyeFocusTestResult) {
        let baselineNow = baseline
        let todayRecord = DailyHealthRecord(
            date: Date(),
            experimentTag: experiments.displayName,
            sleepHours: healthKit.lastNightSleepHours,
            restingHeartRateBPM: healthKit.latestRestingHeartRate,
            hrvMs: healthKit.latestHRV,
            stepCount: healthKit.todaySteps,
            activeEnergyKcal: healthKit.todayActiveEnergy,
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
            wellnessDeltaScore: 0,
            confidenceLevel: "Low",
            insightText: ""
        )
        let computed = engine.calculate(today: todayRecord, baseline: baselineNow)
        let finalRecord = DailyHealthRecord(
            id: todayRecord.id,
            date: todayRecord.date,
            experimentTag: todayRecord.experimentTag,
            sleepHours: todayRecord.sleepHours,
            restingHeartRateBPM: todayRecord.restingHeartRateBPM,
            hrvMs: todayRecord.hrvMs,
            stepCount: todayRecord.stepCount,
            activeEnergyKcal: todayRecord.activeEnergyKcal,
            eyeFocusScore: todayRecord.eyeFocusScore,
            averageReactionMs: todayRecord.averageReactionMs,
            reactionStdDevMs: todayRecord.reactionStdDevMs,
            missedTargets: todayRecord.missedTargets,
            falseTaps: todayRecord.falseTaps,
            gazeAccuracyPx: todayRecord.gazeAccuracyPx,
            gazeStabilityPx: todayRecord.gazeStabilityPx,
            gazeFixationMs: todayRecord.gazeFixationMs,
            gazeBlinkRatePerMin: todayRecord.gazeBlinkRatePerMin,
            gazeTrackingLossPct: todayRecord.gazeTrackingLossPct,
            gazeScore: todayRecord.gazeScore,
            wellnessDeltaScore: computed.score,
            confidenceLevel: computed.confidence,
            insightText: computed.insightText
        )
        storage.saveRecord(finalRecord)
        lastWellnessResult = computed
        showEyeFocusTest = false
        showInsight = true
    }

    private func refreshWellnessFromStorage() {
        let today = storage.loadAllRecords()
            .first(where: { Calendar.current.isDateInToday($0.date) })
        guard let today = today else { return }
        lastWellnessResult = WellnessDeltaResult(
            score: today.wellnessDeltaScore,
            confidence: today.confidenceLevel,
            insightText: today.insightText,
            availableMetricCount: 0,
            positiveMetricCount: 0
        )
    }

    private func format(_ value: Double?, digits: Int) -> String? {
        guard let value = value else { return nil }
        return String(format: "%.\(digits)f", value)
    }

    private func delta(_ current: Double?, _ base: Double?, inverted: Bool = false) -> Double? {
        guard let current = current, let base = base, base > 0 else { return nil }
        let raw = (current - base) / base * 100
        return inverted ? -raw : raw
    }
}
