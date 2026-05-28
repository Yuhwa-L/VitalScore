import SwiftUI

struct HealthDashboardView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var experiments: ExperimentManager
    @EnvironmentObject var storage: LocalStorageManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var showEyeFocusTest = false
    @State private var showAdvancedVoiceTracking = false
    @State private var pendingTrackingMode: TrackingMode?
    @State private var activeTestTag: String = ExperimentTagValue.untagged
    @State private var showVoiceAnalysis = false
    @State private var showWellnessHistory = false
    @State private var showWellnessSuggestions = false
    @State private var lastWellnessResult: WellnessDeltaResult?
    @State private var showSettings = false
    @State private var showEyeFocusLogs = false
    @State private var selectedTagFilter: String?
    @State private var useCustomPeriod = false
    @State private var periodStartDate = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var periodEndDate = Date()

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
                    dashboardFilterControls
                    wellnessScoreCard
                    healthMetricGrid
                    trackingActionsRow
                    analysisOverview
                    wellnessSuggestionsCard
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await healthKit.fetchAllLatest()
                syncHealthValuesFromLatestStoredRecord()
            }
            .task {
                await healthKit.fetchAllLatest()
                syncHealthValuesFromLatestStoredRecord()
                refreshWellnessFromStorage()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await healthKit.fetchAllLatest()
                        syncHealthValuesFromLatestStoredRecord()
                    }
                }
            }
            .onChange(of: storage.revision) { _, _ in
                syncHealthValuesFromLatestStoredRecord()
                refreshWellnessFromStorage()
            }
            .onChange(of: selectedTagFilter) { _, _ in
                refreshForFilterChange()
            }
            .onChange(of: useCustomPeriod) { _, _ in
                refreshForFilterChange()
            }
            .onChange(of: periodStartDate) { _, _ in
                refreshForFilterChange()
            }
            .onChange(of: periodEndDate) { _, _ in
                refreshForFilterChange()
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
                        Task {
                            await healthKit.fetchAllLatest()
                            syncHealthValuesFromLatestStoredRecord()
                        }
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
                EyeFocusLogsView(tagFilter: selectedTagFilter, dateInterval: selectedDateInterval)
                    .environmentObject(storage)
            }
            .sheet(isPresented: $showWellnessHistory) {
                NavigationStack {
                    WellnessHistoryView(
                        records: filteredRecords,
                        latestResult: latestWellnessResult
                    )
                }
            }
            .sheet(isPresented: $showWellnessSuggestions) {
                NavigationStack {
                    WellnessSuggestionsView(
                        records: filteredRecords,
                        voiceSessions: filteredVoiceSessions,
                        tagFilter: selectedTagFilter,
                        dateInterval: selectedDateInterval
                    )
                }
            }
            .navigationDestination(isPresented: $showEyeFocusTest) {
                EyeFocusTestView(experimentTag: activeTestTag, onFinished: handleEyeFocusFinished)
            }
            .navigationDestination(isPresented: $showAdvancedVoiceTracking) {
                VoiceTrackingView(
                    mode: .advancedFreestyle,
                    previousSessions: storage.loadVoiceSessions(tagFilter: activeTestTag),
                    experimentTag: activeTestTag,
                    onAnalysisRequested: scoreCompletedVoiceSessionWithAPI,
                    onFinished: finishVoiceTrackingFlow
                )
            }
            .sheet(item: $pendingTrackingMode) { mode in
                TagPickerSheet(
                    title: mode.pickerTitle,
                    initialTag: trackingTag == ExperimentTagValue.untagged ? nil : trackingTag
                ) { chosenTag in
                    activeTestTag = ExperimentTagValue.normalized(chosenTag)
                    switch mode {
                    case .eyeFocus: showEyeFocusTest = true
                    case .voice: showAdvancedVoiceTracking = true
                    }
                }
            }
            .navigationDestination(isPresented: $showVoiceAnalysis) {
                VoiceAnalysisDashboardView(sessions: filteredVoiceSessions)
            }
        }
    }

    private var dashboardFilterControls: some View {
        VStack(spacing: 10) {
            tagFilterControl
            periodFilterControl
        }
    }

    private var tagFilterControl: some View {
        HStack(spacing: 10) {
            Label("Data tag", systemImage: "tag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Data tag", selection: $selectedTagFilter) {
                Text(ExperimentTagValue.allTagsLabel).tag(String?.none)
                ForEach(availableDashboardTags, id: \.self) { tag in
                    Text(tag).tag(String?.some(tag))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private var periodFilterControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Period", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(periodSummaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Toggle("Custom", isOn: $useCustomPeriod)
                    .font(.subheadline)
                    .toggleStyle(.switch)
                    .fixedSize()
            }

            if useCustomPeriod {
                Divider()
                DatePicker("Start", selection: $periodStartDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                DatePicker("End", selection: $periodEndDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
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
                pendingTrackingMode = .eyeFocus
            }

            trackingButton(
                title: "Voice",
                systemImage: "waveform.path.ecg",
                tint: .teal
            ) {
                pendingTrackingMode = .voice
            }
        }
    }

    private var analysisOverview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            AnalysisTile(
                title: "Eye Analysis",
                systemImage: "eye.circle",
                tint: .indigo,
                primaryValue: format(latestDisplayRecord?.eyeFocusScore, digits: 0) ?? "--",
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

    private var wellnessSuggestionsCard: some View {
        Button {
            showWellnessSuggestions = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Suggestions")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(suggestionCardSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

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
                title: "Resting HR",
                value: format(displayRestingHeartRate, digits: 0),
                unit: "bpm",
                baseline: format(baseline.averageRestingHeartRateBPM, digits: 0),
                delta: delta(displayRestingHeartRate, baseline.averageRestingHeartRateBPM, inverted: true),
                systemImage: "heart.fill",
                tint: .red
            ),
            HealthMetricTileData(
                title: "HRV",
                value: format(displayHRV, digits: 0),
                unit: "ms",
                baseline: format(baseline.averageHRVMs, digits: 0),
                delta: delta(displayHRV, baseline.averageHRVMs),
                systemImage: "waveform.path",
                tint: .purple
            ),
            HealthMetricTileData(
                title: "Steps",
                value: format(displaySteps, digits: 0),
                unit: "",
                baseline: format(baseline.averageStepCount, digits: 0),
                delta: delta(displaySteps, baseline.averageStepCount),
                systemImage: "figure.walk",
                tint: .green
            )
        ]
    }

    private var eyeAnalysisDetails: [String] {
        let record = latestDisplayRecord
        return [
            detailText("Gaze", value: format(record?.gazeScore, digits: 0), unit: ""),
            storage.latestEyeFocusSummary(tagFilter: selectedTagFilter, dateInterval: selectedDateInterval)?.overallSummary
                ?? detailText("Reaction", value: format(record?.averageReactionMs, digits: 0), unit: "ms")
        ]
    }

    private var voiceAnalysisDetails: [String] {
        [
            detailText("Sessions", value: "\(filteredVoiceSessions.count)", unit: ""),
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
        filteredRecords
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
        engine.buildBaseline(from: filteredRecords)
    }

    private var latestDisplayRecord: DailyHealthRecord? {
        filteredRecords
            .sorted { $0.date < $1.date }
            .last
    }

    private var isDashboardFiltered: Bool {
        selectedTagFilter != nil || useCustomPeriod
    }

    private var displayRestingHeartRate: Double? {
        isDashboardFiltered ? latestDisplayRecord?.restingHeartRateBPM : healthKit.latestRestingHeartRate
    }

    private var displayHRV: Double? {
        isDashboardFiltered ? latestDisplayRecord?.hrvMs : healthKit.latestHRV
    }

    private var displaySteps: Double? {
        isDashboardFiltered ? latestDisplayRecord?.stepCount : healthKit.todaySteps
    }

    private var selectedDateInterval: DateInterval? {
        guard useCustomPeriod else { return nil }
        let bounds = normalizedPeriodBounds
        let start = Calendar.current.startOfDay(for: bounds.start)
        let endDay = Calendar.current.startOfDay(for: bounds.end)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDay.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    private var normalizedPeriodBounds: (start: Date, end: Date) {
        periodStartDate <= periodEndDate
            ? (periodStartDate, periodEndDate)
            : (periodEndDate, periodStartDate)
    }

    private var periodSummaryText: String {
        guard useCustomPeriod else { return "All time" }
        let bounds = normalizedPeriodBounds
        return "\(shortDate(bounds.start)) - \(shortDate(bounds.end))"
    }

    private var trackingTag: String {
        ExperimentTagValue.normalized(experiments.current == nil ? nil : experiments.displayName)
    }

    private var availableDashboardTags: [String] {
        storage.availableExperimentTags(extraTags: [trackingTag])
    }

    private var filteredRecords: [DailyHealthRecord] {
        storage.loadAllRecords(tagFilter: selectedTagFilter, dateInterval: selectedDateInterval)
    }

    private var filteredVoiceSessions: [VoiceTrackingSession] {
        storage.loadVoiceSessions(tagFilter: selectedTagFilter, dateInterval: selectedDateInterval)
    }

    private var trackingTodayRecord: DailyHealthRecord? {
        recordForToday(tagFilter: trackingTag)
    }

    private var latestVoiceSession: VoiceTrackingSession? {
        filteredVoiceSessions.sorted { $0.date < $1.date }.last
    }

    private var suggestionCardSubtitle: String {
        if filteredRecords.count < 3 {
            return "Save more wellness history for stronger personal suggestions."
        }
        return "Optional low-risk experiments based on your saved trends."
    }

    private func recordForToday(tagFilter: String?) -> DailyHealthRecord? {
        storage.loadAllRecords(tagFilter: tagFilter)
            .sorted { $0.date < $1.date }
            .last(where: { Calendar.current.isDateInToday($0.date) })
    }

    private func baseline(for tagFilter: String?) -> BaselineMetrics {
        engine.buildBaseline(from: storage.loadAllRecords(tagFilter: tagFilter))
    }

    private func handleEyeFocusFinished(_ result: EyeFocusTestResult) {
        if let summary = result.aiSummary {
            storage.saveEyeFocusSummary(summary)
        }

        let baselineNow = baseline(for: activeTestTag)
        let existingRecord = recordForToday(tagFilter: activeTestTag)
        let todayRecord = DailyHealthRecord(
            id: existingRecord?.id ?? UUID(),
            date: existingRecord?.date ?? Date(),
            experimentTag: activeTestTag,
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
        let finalRecord = saveRecordWithWellness(todayRecord, baseline: baselineNow)
        storage.writeEyeFocusAnalysisExport(result: result, dailyRecord: finalRecord)
        showEyeFocusTest = false
        showWellnessHistory = false
    }

    @MainActor
    private func scoreCompletedVoiceSessionWithAPI(_ session: VoiceTrackingSession) async -> VoiceAIAnalysisResponse? {
        guard let exportURL = persistVoiceTrackingSession(session) else {
            return VoiceAIConversationBuilder.localAnalysisSummary(
                for: session.removingLocallySavedLiveData(),
                exportId: session.id,
                unavailableReason: "analysis export could not be written"
            )
        }

        let shouldPersistAnalysis = !session.containsLocallySavedLiveData
        let sessionTag = ExperimentTagValue.normalized(session.experimentTag)
        let analysisExport = MultimodalAnalysisExport.voice(
            session: session,
            dailyRecord: recordForToday(tagFilter: sessionTag)
        )
        let recentSessions = storage.loadVoiceSessions(tagFilter: sessionTag)
        let recentRecords = storage.loadAllRecords(tagFilter: sessionTag)
        do {
            let analysis = try await AIConversationClient().analyzeVoiceExport(
                analysisExport,
                exportFileName: exportURL.lastPathComponent,
                recentVoiceSessions: recentSessions,
                recentDailyRecords: recentRecords
            )
            applyAIScoreIfAvailable(analysis, to: session)
            if shouldPersistAnalysis {
                storage.writeVoiceAIAnalysisResult(analysis, exportFileURL: exportURL)
            }
            return analysis
        } catch AIConversationClientError.missingAPIKey {
            #if DEBUG
            print("Voice AI analysis skipped because no OpenAI API key is configured.")
            #endif
            let fallback = localVoiceAnalysisFallback(
                for: session,
                exportURL: exportURL,
                reason: "OpenAI API key is not configured"
            )
            if shouldPersistAnalysis {
                storage.writeVoiceAIAnalysisResult(fallback, exportFileURL: exportURL)
            }
            return fallback
        } catch {
            #if DEBUG
            print("Voice AI analysis failed: \(error.localizedDescription)")
            #endif
            let fallback = localVoiceAnalysisFallback(
                for: session,
                exportURL: exportURL,
                reason: error.localizedDescription
            )
            if shouldPersistAnalysis {
                storage.writeVoiceAIAnalysisResult(fallback, exportFileURL: exportURL)
            }
            return fallback
        }
    }

    private func applyAIScoreIfAvailable(_ analysis: VoiceAIAnalysisResponse, to session: VoiceTrackingSession) {
        guard let aiScore = analysis.aiVoiceScore else { return }
        let boundedScore = min(100, max(0, aiScore))
        let confidence = analysis.aiScoreConfidence?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rationale = analysis.aiScoreRationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        var topDrivers = session.result.topDrivers
        if let rationale, !rationale.isEmpty, !session.containsLocallySavedLiveData {
            topDrivers.insert("AI score rationale: \(rationale)", at: 0)
        }

        let updatedResult = session.result.scored(
            voiceScore: boundedScore,
            confidence: confidence?.isEmpty == false ? confidence! : session.result.voiceConfidence,
            baselineSessionsUsed: session.result.baselineSessionsUsed,
            baselineStatus: "ai_analysis_scored",
            topDrivers: topDrivers
        )
        let updatedSession = session.replacingResult(updatedResult)
        storage.saveVoiceSession(updatedSession)

        let sessionTag = ExperimentTagValue.normalized(session.experimentTag)
        let existing = recordForToday(tagFilter: sessionTag)
        let updatedRecord = DailyHealthRecord(
            id: existing?.id ?? UUID(),
            date: existing?.date ?? Date(),
            experimentTag: sessionTag,
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
            voiceScore: boundedScore,
            voiceAverageVolumeDb: updatedResult.averageVolumeDb,
            voiceVolumeStdDevDb: updatedResult.volumeStdDevDb,
            voiceSilenceRatio: updatedResult.silenceRatio,
            voicePeakVolumeDb: updatedResult.peakVolumeDb,
            selfReportedEnergy: existing?.selfReportedEnergy,
            selfReportedStress: existing?.selfReportedStress,
            selfReportedSleepQuality: existing?.selfReportedSleepQuality,
            wellnessDeltaScore: existing?.wellnessDeltaScore ?? 0,
            confidenceLevel: existing?.confidenceLevel ?? "Low",
            insightText: existing?.insightText ?? ""
        )
        _ = saveRecordWithWellness(updatedRecord, baseline: baseline(for: sessionTag))
    }

    private func localVoiceAnalysisFallback(
        for session: VoiceTrackingSession,
        exportURL: URL,
        reason: String
    ) -> VoiceAIAnalysisResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportId = ((try? Data(contentsOf: exportURL))
            .flatMap { try? decoder.decode(MultimodalAnalysisExport.self, from: $0) })?.id
            ?? session.id
        return VoiceAIConversationBuilder.localAnalysisSummary(
            for: session.removingLocallySavedLiveData(),
            exportId: exportId,
            unavailableReason: reason
        )
    }

    @discardableResult
    private func persistVoiceTrackingSession(_ session: VoiceTrackingSession) -> URL? {
        let scrubbedSession = session.removingLocallySavedLiveData()
        let sessionTag = ExperimentTagValue.normalized(scrubbedSession.experimentTag)
        let existing = recordForToday(tagFilter: sessionTag)
        let result = scrubbedSession.result
        storage.saveVoiceSession(scrubbedSession)

        let record = DailyHealthRecord(
            id: existing?.id ?? UUID(),
            date: existing?.date ?? Date(),
            experimentTag: sessionTag,
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
        let finalRecord = saveRecordWithWellness(record, baseline: baseline(for: sessionTag))
        return storage.writeVoiceAnalysisExport(session: scrubbedSession, dailyRecord: finalRecord)
    }

    private func finishVoiceTrackingFlow(_ session: VoiceTrackingSession) {
        showAdvancedVoiceTracking = false
        showVoiceAnalysis = true
    }

    private func saveRecordWithWellness(_ record: DailyHealthRecord, baseline: BaselineMetrics) -> DailyHealthRecord {
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
        if matchesDashboardFilters(finalRecord) {
            lastWellnessResult = computed
        } else {
            refreshWellnessFromStorage()
        }
        return finalRecord
    }

    private func refreshWellnessFromStorage() {
        guard let record = latestWellnessRecord else {
            lastWellnessResult = nil
            return
        }
        lastWellnessResult = WellnessDeltaResult(
            score: record.wellnessDeltaScore,
            confidence: record.confidenceLevel,
            insightText: record.insightText,
            availableMetricCount: 0,
            positiveMetricCount: 0
        )
    }

    private func refreshForFilterChange() {
        syncHealthValuesFromLatestStoredRecord()
        refreshWellnessFromStorage()
    }

    private func syncHealthValuesFromLatestStoredRecord() {
        guard let record = filteredRecords.sorted(by: { $0.date < $1.date }).last else { return }
        healthKit.applyMockRecord(record)
    }

    private func matchesDashboardFilters(_ record: DailyHealthRecord) -> Bool {
        ExperimentTagValue.matches(record.experimentTag, filter: selectedTagFilter) &&
        matchesSelectedPeriod(record.date)
    }

    private func matchesSelectedPeriod(_ date: Date) -> Bool {
        guard let interval = selectedDateInterval else { return true }
        return date >= interval.start && date < interval.end
    }

    private func detailText(_ label: String, value: String?, unit: String) -> String {
        guard let value else { return "\(label) --" }
        return "\(label) \(value)\(unit.isEmpty ? "" : " \(unit)")"
    }

    private func format(_ value: Double?, digits: Int) -> String? {
        guard let value else { return nil }
        return String(format: "%.\(digits)f", value)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
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

enum TrackingMode: String, Identifiable {
    case eyeFocus
    case voice

    var id: String { rawValue }

    var pickerTitle: String {
        switch self {
        case .eyeFocus: return "Tag this eye-focus test"
        case .voice: return "Tag this voice test"
        }
    }
}
