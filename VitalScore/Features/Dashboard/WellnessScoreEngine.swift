import Foundation

struct WellnessScoreEngine {
    static let sleepWeight = 0.22
    static let restingHeartRateWeight = 0.18
    static let hrvWeight = 0.18
    static let stepsWeight = 0.12
    static let eyeFocusWeight = 0.12
    static let voiceWeight = 0.10
    static let selfReportedEnergyWeight = 0.03
    static let selfReportedStressWeight = 0.03
    static let selfReportedSleepQualityWeight = 0.02

    func buildBaseline(from records: [DailyHealthRecord], asOf reference: Date = Date(), window: Int = 7) -> BaselineMetrics {
        let calendar = Calendar.current
        let endOfBaseline = calendar.startOfDay(for: reference)
        guard let cutoff = calendar.date(byAdding: .day, value: -window, to: endOfBaseline) else {
            return .empty
        }
        let scoped = records.filter { $0.date >= cutoff && $0.date < endOfBaseline }
        if scoped.isEmpty {
            return BaselineMetrics(
                startDate: cutoff,
                endDate: endOfBaseline,
                averageSleepHours: nil,
                averageRestingHeartRateBPM: nil,
                averageHRVMs: nil,
                averageStepCount: nil,
                averageEyeFocusScore: nil,
                averageGazeScore: nil,
                averageGazeAccuracyPx: nil,
                averageBalanceScore: nil,
                averageVoiceScore: nil,
                averageSelfReportedEnergy: nil,
                averageSelfReportedStress: nil,
                averageSelfReportedSleepQuality: nil
            )
        }
        return BaselineMetrics(
            startDate: cutoff,
            endDate: endOfBaseline,
            averageSleepHours: Self.average(scoped.compactMap { $0.sleepHours }),
            averageRestingHeartRateBPM: Self.average(scoped.compactMap { $0.restingHeartRateBPM }),
            averageHRVMs: Self.average(scoped.compactMap { $0.hrvMs }),
            averageStepCount: Self.average(scoped.compactMap { $0.stepCount }),
            averageEyeFocusScore: Self.average(scoped.compactMap { $0.eyeFocusScore }),
            averageGazeScore: Self.average(scoped.compactMap { $0.gazeScore }),
            averageGazeAccuracyPx: Self.average(scoped.compactMap { $0.gazeAccuracyPx }),
            averageBalanceScore: Self.average(scoped.compactMap { $0.balanceScore }),
            averageVoiceScore: Self.average(scoped.compactMap { $0.voiceScore }),
            averageSelfReportedEnergy: Self.average(scoped.compactMap { $0.selfReportedEnergy.map(Double.init) }),
            averageSelfReportedStress: Self.average(scoped.compactMap { $0.selfReportedStress.map(Double.init) }),
            averageSelfReportedSleepQuality: Self.average(scoped.compactMap { $0.selfReportedSleepQuality.map(Double.init) })
        )
    }

    func calculate(today: DailyHealthRecord, baseline: BaselineMetrics) -> WellnessDeltaResult {
        var weightedScore = 0.0
        var totalWeight = 0.0
        var availableCount = 0
        var positiveCount = 0

        addPercentMetric(
            today: today.sleepHours,
            baseline: baseline.averageSleepHours,
            weight: Self.sleepWeight,
            fullScaleChange: 0.20,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
        addPercentMetric(
            today: today.restingHeartRateBPM,
            baseline: baseline.averageRestingHeartRateBPM,
            weight: Self.restingHeartRateWeight,
            fullScaleChange: 0.12,
            inverted: true,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
        addPercentMetric(
            today: today.hrvMs,
            baseline: baseline.averageHRVMs,
            weight: Self.hrvWeight,
            fullScaleChange: 0.30,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
        addPercentMetric(
            today: today.stepCount,
            baseline: baseline.averageStepCount,
            weight: Self.stepsWeight,
            fullScaleChange: 0.50,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
        addPointMetric(
            today: today.eyeFocusScore,
            baseline: baseline.averageEyeFocusScore,
            weight: Self.eyeFocusWeight,
            fullScalePoints: 20,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
        addPointMetric(
            today: today.voiceScore,
            baseline: baseline.averageVoiceScore,
            weight: Self.voiceWeight,
            fullScalePoints: 20,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
        addPointMetric(
            today: today.selfReportedEnergy.map(Double.init),
            baseline: baseline.averageSelfReportedEnergy,
            weight: Self.selfReportedEnergyWeight,
            fullScalePoints: 3,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
        addPointMetric(
            today: today.selfReportedStress.map(Double.init),
            baseline: baseline.averageSelfReportedStress,
            weight: Self.selfReportedStressWeight,
            fullScalePoints: 3,
            inverted: true,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
        addPointMetric(
            today: today.selfReportedSleepQuality.map(Double.init),
            baseline: baseline.averageSelfReportedSleepQuality,
            weight: Self.selfReportedSleepQualityWeight,
            fullScalePoints: 3,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )

        guard totalWeight > 0 else {
            return WellnessDeltaResult(
                score: 0,
                confidence: "Low",
                insightText: "Not enough data to calculate a wellness trend yet. Track for a few days to build your baseline.",
                availableMetricCount: 0,
                positiveMetricCount: 0
            )
        }

        let normalized = weightedScore / totalWeight
        let finalScore = Int(max(-20, min(20, (normalized * 20).rounded())))

        let confidence: String
        if totalWeight >= 0.70 { confidence = "High" }
        else if totalWeight >= 0.40 { confidence = "Medium" }
        else { confidence = "Low" }

        let insight = generateInsightText(
            today: today,
            baseline: baseline,
            score: finalScore,
            confidence: confidence,
            availableCount: availableCount,
            positiveCount: positiveCount
        )

        return WellnessDeltaResult(
            score: finalScore,
            confidence: confidence,
            insightText: insight,
            availableMetricCount: availableCount,
            positiveMetricCount: positiveCount
        )
    }

    func generateInsightText(
        today: DailyHealthRecord,
        baseline: BaselineMetrics,
        score: Int,
        confidence: String,
        availableCount: Int,
        positiveCount: Int
    ) -> String {
        var lines: [String] = []
        let direction: String
        if score > 0 { direction = "trending positively" }
        else if score < 0 { direction = "trending downward" }
        else { direction = "roughly steady" }
        lines.append("Your Wellness Delta is \(score >= 0 ? "+" : "")\(score) compared with your 7-day baseline.")

        if let todaySleep = today.sleepHours, let baseSleep = baseline.averageSleepHours {
            let minutesDiff = Int(round((todaySleep - baseSleep) * 60))
            if minutesDiff > 0 {
                lines.append("Sleep increased by \(minutesDiff) minutes versus baseline.")
            } else if minutesDiff < 0 {
                lines.append("Sleep decreased by \(-minutesDiff) minutes versus baseline.")
            }
        }
        if let todayRHR = today.restingHeartRateBPM, let baseRHR = baseline.averageRestingHeartRateBPM {
            let diff = Int(round(todayRHR - baseRHR))
            if diff < 0 {
                lines.append("Resting heart rate decreased by \(-diff) BPM versus baseline.")
            } else if diff > 0 {
                lines.append("Resting heart rate increased by \(diff) BPM versus baseline.")
            }
        }
        if let todayFocus = today.eyeFocusScore, let baseFocus = baseline.averageEyeFocusScore {
            let diff = Int(round(todayFocus - baseFocus))
            if diff > 0 {
                lines.append("Eye-focus score improved by \(diff) points versus baseline.")
            } else if diff < 0 {
                lines.append("Eye-focus score decreased by \(-diff) points versus baseline.")
            }
        }
        if let todayGaze = today.gazeScore {
            if let baseGaze = baseline.averageGazeScore {
                let diff = Int(round(todayGaze - baseGaze))
                if diff > 0 {
                    lines.append("Gaze stability improved by \(diff) points versus baseline.")
                } else if diff < 0 {
                    lines.append("Gaze stability decreased by \(-diff) points versus baseline.")
                }
            } else {
                lines.append("Gaze stability captured for the first time: \(Int(round(todayGaze)))/100.")
            }
        }

        let tag = today.experimentTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.isEmpty || tag == "None" || tag == "Untagged" {
            lines.append("Your wellness markers are \(direction) compared with your recent baseline.")
        } else {
            lines.append("Your wellness markers are \(direction) during your \(tag) experiment.")
        }
        lines.append("This is a wellness trend, not a diagnosis, and does not show causation.")
        lines.append("Confidence: \(confidence) (\(availableCount) of 9 metrics available).")
        return lines.joined(separator: "\n")
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func addPercentMetric(
        today: Double?,
        baseline: Double?,
        weight: Double,
        fullScaleChange: Double,
        inverted: Bool = false,
        weightedScore: inout Double,
        totalWeight: inout Double,
        availableCount: inout Int,
        positiveCount: inout Int
    ) {
        guard let today, let baseline, baseline > 0, fullScaleChange > 0 else { return }
        let delta = inverted ? (baseline - today) / baseline : (today - baseline) / baseline
        addNormalizedMetric(
            delta / fullScaleChange,
            weight: weight,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
    }

    private func addPointMetric(
        today: Double?,
        baseline: Double?,
        weight: Double,
        fullScalePoints: Double,
        inverted: Bool = false,
        weightedScore: inout Double,
        totalWeight: inout Double,
        availableCount: inout Int,
        positiveCount: inout Int
    ) {
        guard let today, let baseline, fullScalePoints > 0 else { return }
        let delta = inverted ? baseline - today : today - baseline
        addNormalizedMetric(
            delta / fullScalePoints,
            weight: weight,
            weightedScore: &weightedScore,
            totalWeight: &totalWeight,
            availableCount: &availableCount,
            positiveCount: &positiveCount
        )
    }

    private func addNormalizedMetric(
        _ rawScore: Double,
        weight: Double,
        weightedScore: inout Double,
        totalWeight: inout Double,
        availableCount: inout Int,
        positiveCount: inout Int
    ) {
        let metricScore = max(-1, min(1, rawScore))
        weightedScore += metricScore * weight
        totalWeight += weight
        availableCount += 1
        if metricScore > 0 { positiveCount += 1 }
    }
}
