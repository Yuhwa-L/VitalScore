import Foundation

enum WellnessSuggestionCategory: String, Codable, CaseIterable {
    case sleep
    case activity
    case nutrition
    case stress
    case measurement
    case healthcare

    var displayName: String {
        switch self {
        case .sleep: return "Sleep"
        case .activity: return "Activity"
        case .nutrition: return "Food & Hydration"
        case .stress: return "Stress Load"
        case .measurement: return "Tracking"
        case .healthcare: return "Professional Support"
        }
    }
}

struct WellnessSuggestion: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let category: WellnessSuggestionCategory
    let reason: String
    let suggestion: String
    let trackingPlan: String
    let riskLevel: String
    let confidence: String
    let evidence: [String]
    let notMedicalAdvice: Bool

    init(
        id: UUID = UUID(),
        title: String,
        category: WellnessSuggestionCategory,
        reason: String,
        suggestion: String,
        trackingPlan: String,
        riskLevel: String = "low",
        confidence: String,
        evidence: [String],
        notMedicalAdvice: Bool = true
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.reason = reason
        self.suggestion = suggestion
        self.trackingPlan = trackingPlan
        self.riskLevel = riskLevel
        self.confidence = confidence
        self.evidence = evidence
        self.notMedicalAdvice = notMedicalAdvice
    }
}

struct WellnessSuggestionReport: Codable, Equatable, Identifiable {
    let id: UUID
    let generatedAt: Date
    let source: String
    let summary: String
    let confidence: String
    let analyzedRecordCount: Int
    let baselineWindowDays: Int
    let observedPatterns: [String]
    let suggestions: [WellnessSuggestion]
    let nextCheckIn: String
    let clinicianNote: String
    let safetyNote: String

    init(
        id: UUID = UUID(),
        generatedAt: Date = Date(),
        source: String,
        summary: String,
        confidence: String,
        analyzedRecordCount: Int,
        baselineWindowDays: Int = 7,
        observedPatterns: [String],
        suggestions: [WellnessSuggestion],
        nextCheckIn: String,
        clinicianNote: String,
        safetyNote: String
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.source = source
        self.summary = summary
        self.confidence = confidence
        self.analyzedRecordCount = analyzedRecordCount
        self.baselineWindowDays = baselineWindowDays
        self.observedPatterns = observedPatterns
        self.suggestions = suggestions
        self.nextCheckIn = nextCheckIn
        self.clinicianNote = clinicianNote
        self.safetyNote = safetyNote
    }
}

struct WellnessSuggestionRequestPayload: Codable {
    let provider: String
    let model: String
    let systemInstruction: String
    let generatedAt: Date
    let tagFilter: String?
    let periodSummary: String
    let baseline: BaselineMetrics
    let latestWellnessResult: WellnessDeltaResult?
    let recentDailyRecords: [DailyHealthRecord]
    let recentVoiceHistory: [VoiceAIConversationSessionSummary]
    let guardrails: [String]
}

struct WellnessSuggestionEngine {
    static let baselineWindowDays = 7

    func localReport(
        records: [DailyHealthRecord],
        voiceSessions: [VoiceTrackingSession] = [],
        tagFilter: String?,
        unavailableReason: String? = nil
    ) -> WellnessSuggestionReport {
        let sortedRecords = records.sorted { $0.date < $1.date }
        let latest = sortedRecords.last
        let baseline = WellnessScoreEngine().buildBaseline(
            from: sortedRecords,
            asOf: latest?.date ?? Date(),
            window: Self.baselineWindowDays
        )
        let observedPatterns = observedPatterns(
            latest: latest,
            baseline: baseline,
            records: sortedRecords,
            voiceSessions: voiceSessions
        )
        let suggestions = localSuggestions(
            latest: latest,
            baseline: baseline,
            records: sortedRecords,
            voiceSessions: voiceSessions
        )
        let scopedText = tagFilter.map { " for \($0)" } ?? ""
        let reasonText = unavailableReason.map { " AI suggestions were unavailable: \($0)" } ?? ""

        return WellnessSuggestionReport(
            source: "local_wellness_suggestions",
            summary: "Based on saved trends\(scopedText), these are optional low-risk experiments to track over the next few days.\(reasonText)",
            confidence: confidence(for: sortedRecords),
            analyzedRecordCount: sortedRecords.count,
            observedPatterns: observedPatterns,
            suggestions: suggestions,
            nextCheckIn: "Try one experiment for 3 to 7 days, then compare the next few VitalScore readings with your baseline.",
            clinicianNote: "If changes are sudden, persistent, worsening, or concerning, discuss them with a qualified professional.",
            safetyNote: "These suggestions are general wellness experiments, not diagnosis, treatment advice, or disease prediction."
        )
    }

    static func normalized(
        _ report: WellnessSuggestionReport,
        fallback: WellnessSuggestionReport
    ) -> WellnessSuggestionReport {
        let suggestions = report.suggestions
            .map(normalizedSuggestion)
            .filter { !$0.title.isEmpty && !$0.suggestion.isEmpty }

        let usableSuggestions = suggestions.isEmpty ? fallback.suggestions : Array(suggestions.prefix(4))
        let observedPatterns = report.observedPatterns.isEmpty
            ? fallback.observedPatterns
            : Array(report.observedPatterns.prefix(5))
        let confidence = normalizedConfidence(report.confidence, fallback: fallback.confidence)

        return WellnessSuggestionReport(
            id: report.id,
            generatedAt: report.generatedAt,
            source: report.source.isEmpty ? fallback.source : report.source,
            summary: report.summary.isEmpty ? fallback.summary : report.summary,
            confidence: confidence,
            analyzedRecordCount: max(report.analyzedRecordCount, fallback.analyzedRecordCount),
            observedPatterns: observedPatterns,
            suggestions: usableSuggestions,
            nextCheckIn: report.nextCheckIn.isEmpty ? fallback.nextCheckIn : report.nextCheckIn,
            clinicianNote: report.clinicianNote.isEmpty ? fallback.clinicianNote : report.clinicianNote,
            safetyNote: report.safetyNote.isEmpty ? fallback.safetyNote : report.safetyNote
        )
    }

    private func observedPatterns(
        latest: DailyHealthRecord?,
        baseline: BaselineMetrics,
        records: [DailyHealthRecord],
        voiceSessions: [VoiceTrackingSession]
    ) -> [String] {
        var patterns: [String] = []
        if let latest {
            if let sleep = latest.sleepHours, let base = baseline.averageSleepHours {
                let minutes = Int(round((sleep - base) * 60))
                if minutes != 0 {
                    patterns.append("Latest sleep was \(abs(minutes)) minutes \(minutes > 0 ? "above" : "below") the recent baseline.")
                }
            }
            if let hrv = latest.hrvMs, let base = baseline.averageHRVMs {
                let diff = Int(round(hrv - base))
                if diff != 0 {
                    patterns.append("Latest HRV was \(abs(diff)) ms \(diff > 0 ? "above" : "below") baseline.")
                }
            }
            if let restingHeartRate = latest.restingHeartRateBPM, let base = baseline.averageRestingHeartRateBPM {
                let diff = Int(round(restingHeartRate - base))
                if diff != 0 {
                    patterns.append("Resting heart rate was \(abs(diff)) BPM \(diff > 0 ? "above" : "below") baseline.")
                }
            }
            let score = latest.wellnessDeltaScore
            patterns.append("Latest Wellness Delta was \(score >= 0 ? "+" : "")\(score) with \(latest.confidenceLevel.lowercased()) confidence.")
        }

        if let latestVoice = voiceSessions.sorted(by: { $0.date < $1.date }).last {
            patterns.append("Latest voice score was \(Int(latestVoice.result.voiceScore.rounded())) with \(latestVoice.result.voiceConfidence.lowercased()) confidence.")
        }
        if patterns.isEmpty {
            patterns.append(records.isEmpty ? "No saved wellness records are available yet." : "Saved data is still building a stable baseline.")
        }
        return Array(patterns.prefix(5))
    }

    private func localSuggestions(
        latest: DailyHealthRecord?,
        baseline: BaselineMetrics,
        records: [DailyHealthRecord],
        voiceSessions: [VoiceTrackingSession]
    ) -> [WellnessSuggestion] {
        var suggestions: [WellnessSuggestion] = []

        if let latest,
           let sleep = latest.sleepHours,
           let base = baseline.averageSleepHours,
           sleep < base - 0.5 {
            suggestions.append(
                WellnessSuggestion(
                    title: "Stabilize the sleep window",
                    category: .sleep,
                    reason: "Recent sleep is below your personal baseline.",
                    suggestion: "Choose a consistent bedtime and wake time for the next few nights and track whether your baseline gap narrows.",
                    trackingPlan: "Run the daily check each morning and compare sleep hours plus Wellness Delta.",
                    confidence: confidence(for: records),
                    evidence: ["Latest sleep \(String(format: "%.1f", sleep))h", "Baseline \(String(format: "%.1f", base))h"]
                )
            )
        }

        if let latest,
           let steps = latest.stepCount,
           let base = baseline.averageStepCount,
           steps < base * 0.80 {
            suggestions.append(
                WellnessSuggestion(
                    title: "Add a light movement block",
                    category: .activity,
                    reason: "Steps are running below your recent baseline.",
                    suggestion: "Add one short walk or light movement block and track whether activity returns closer to baseline.",
                    trackingPlan: "Compare steps, resting heart rate, HRV, and Wellness Delta after 3 days.",
                    confidence: confidence(for: records),
                    evidence: ["Latest steps \(Int(steps.rounded()))", "Baseline \(Int(base.rounded()))"]
                )
            )
        }

        if let latest,
           let hrv = latest.hrvMs,
           let base = baseline.averageHRVMs,
           hrv < base * 0.85 {
            suggestions.append(
                WellnessSuggestion(
                    title: "Reduce evening load",
                    category: .stress,
                    reason: "HRV is below your recent baseline.",
                    suggestion: "Try a quieter evening routine and avoid stacking intense work or training late in the day.",
                    trackingPlan: "Watch HRV, resting heart rate, sleep, and next-day focus for one week.",
                    confidence: confidence(for: records),
                    evidence: ["Latest HRV \(Int(hrv.rounded())) ms", "Baseline \(Int(base.rounded())) ms"]
                )
            )
        }

        if let latest,
           let voice = latest.voiceScore,
           let base = baseline.averageVoiceScore,
           voice < base - 10 {
            suggestions.append(
                WellnessSuggestion(
                    title: "Repeat voice checks under consistent conditions",
                    category: .measurement,
                    reason: "Voice score is below baseline, but recording context can affect this metric.",
                    suggestion: "Run the voice check at the same time of day in a quiet place before interpreting the trend.",
                    trackingPlan: "Use two or three consistent captures and compare voice score plus quality notes.",
                    confidence: confidence(for: records),
                    evidence: ["Latest voice \(Int(voice.rounded()))", "Baseline \(Int(base.rounded()))"]
                )
            )
        }

        if !suggestions.contains(where: { $0.category == .sleep }) {
            suggestions.insert(
                WellnessSuggestion(
                    title: "Keep sleep timing comparable",
                    category: .sleep,
                    reason: "Sleep is one of the strongest baseline inputs, and consistent timing makes the trend easier to read.",
                    suggestion: "Use a consistent sleep window for a few nights and compare morning readings with your baseline.",
                    trackingPlan: "Check sleep duration, HRV, resting heart rate, and Wellness Delta after each morning check.",
                    confidence: confidence(for: records),
                    evidence: ["Saved records \(records.count)", "Baseline window \(Self.baselineWindowDays) days"]
                ),
                at: 0
            )
        }

        if suggestions.count < 2 {
            suggestions.append(
                WellnessSuggestion(
                    title: "Build a stronger baseline",
                    category: .measurement,
                    reason: "More repeated measurements will make suggestions more reliable.",
                    suggestion: "Keep daily checks short and consistent until at least a week of comparable data is available.",
                    trackingPlan: "Collect daily Health, eye-focus, and voice readings for 7 days.",
                    confidence: confidence(for: records),
                    evidence: ["Saved records \(records.count)", "Voice sessions \(voiceSessions.count)"]
                )
            )
        }

        if !suggestions.contains(where: { $0.category == .nutrition }) {
            let nutritionSuggestion = WellnessSuggestion(
                title: "Log food and hydration timing",
                category: .nutrition,
                reason: "Food and hydration context is not directly captured in current wellness records.",
                suggestion: "For one week, tag meal timing, hydration, and caffeine timing, then compare those tags with similar check-ins.",
                trackingPlan: "Review whether those tags cluster with sleep, HRV, focus, voice, or Wellness Delta changes.",
                confidence: "Low",
                evidence: ["No nutrition data is currently stored", "Use this as a tracking experiment only"]
            )
            if suggestions.count >= 4 {
                suggestions.insert(nutritionSuggestion, at: 1)
            } else {
                suggestions.append(nutritionSuggestion)
            }
        }

        return Array(suggestions.prefix(4))
    }

    private func confidence(for records: [DailyHealthRecord]) -> String {
        if records.count >= 14 { return "High" }
        if records.count >= 7 { return "Medium" }
        return "Low"
    }

    private static func normalizedSuggestion(_ suggestion: WellnessSuggestion) -> WellnessSuggestion {
        WellnessSuggestion(
            id: suggestion.id,
            title: suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: suggestion.category,
            reason: suggestion.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            suggestion: suggestion.suggestion.trimmingCharacters(in: .whitespacesAndNewlines),
            trackingPlan: suggestion.trackingPlan.trimmingCharacters(in: .whitespacesAndNewlines),
            riskLevel: "low",
            confidence: normalizedConfidence(suggestion.confidence, fallback: "Low"),
            evidence: Array(suggestion.evidence.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(3)),
            notMedicalAdvice: true
        )
    }

    private static func normalizedConfidence(_ confidence: String, fallback: String) -> String {
        switch confidence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return "High"
        case "medium": return "Medium"
        case "low": return "Low"
        default: return fallback
        }
    }
}
