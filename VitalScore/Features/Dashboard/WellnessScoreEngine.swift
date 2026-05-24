import Foundation

struct WellnessScoreEngine {
    static let sleepWeight = 0.30
    static let restingHeartRateWeight = 0.25
    static let hrvWeight = 0.20
    static let eyeFocusWeight = 0.15
    static let stepsWeight = 0.10

    func buildBaseline(from records: [DailyHealthRecord], asOf reference: Date = Date(), window: Int = 7) -> BaselineMetrics {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -window, to: reference) else {
            return .empty
        }
        let scoped = records.filter { $0.date >= cutoff && $0.date < reference }
        if scoped.isEmpty {
            return BaselineMetrics(
                startDate: cutoff,
                endDate: reference,
                averageSleepHours: nil,
                averageRestingHeartRateBPM: nil,
                averageHRVMs: nil,
                averageStepCount: nil,
                averageEyeFocusScore: nil,
                averageGazeScore: nil,
                averageGazeAccuracyPx: nil,
                averageBalanceScore: nil
            )
        }
        return BaselineMetrics(
            startDate: cutoff,
            endDate: reference,
            averageSleepHours: Self.average(scoped.compactMap { $0.sleepHours }),
            averageRestingHeartRateBPM: Self.average(scoped.compactMap { $0.restingHeartRateBPM }),
            averageHRVMs: Self.average(scoped.compactMap { $0.hrvMs }),
            averageStepCount: Self.average(scoped.compactMap { $0.stepCount }),
            averageEyeFocusScore: Self.average(scoped.compactMap { $0.eyeFocusScore }),
            averageGazeScore: Self.average(scoped.compactMap { $0.gazeScore }),
            averageGazeAccuracyPx: Self.average(scoped.compactMap { $0.gazeAccuracyPx }),
            averageBalanceScore: Self.average(scoped.compactMap { $0.balanceScore })
        )
    }

    func calculate(today: DailyHealthRecord, baseline: BaselineMetrics) -> WellnessDeltaResult {
        var weightedScore = 0.0
        var totalWeight = 0.0
        var availableCount = 0
        var positiveCount = 0

        if let todaySleep = today.sleepHours, let baseSleep = baseline.averageSleepHours, baseSleep > 0 {
            let delta = (todaySleep - baseSleep) / baseSleep
            let metricScore = max(-100, min(100, delta * 100))
            weightedScore += metricScore * Self.sleepWeight
            totalWeight += Self.sleepWeight
            availableCount += 1
            if metricScore > 0 { positiveCount += 1 }
        }

        if let todayRHR = today.restingHeartRateBPM, let baseRHR = baseline.averageRestingHeartRateBPM, baseRHR > 0 {
            let delta = (baseRHR - todayRHR) / baseRHR
            let metricScore = max(-100, min(100, delta * 100))
            weightedScore += metricScore * Self.restingHeartRateWeight
            totalWeight += Self.restingHeartRateWeight
            availableCount += 1
            if metricScore > 0 { positiveCount += 1 }
        }

        if let todayHRV = today.hrvMs, let baseHRV = baseline.averageHRVMs, baseHRV > 0 {
            let delta = (todayHRV - baseHRV) / baseHRV
            let metricScore = max(-100, min(100, delta * 100))
            weightedScore += metricScore * Self.hrvWeight
            totalWeight += Self.hrvWeight
            availableCount += 1
            if metricScore > 0 { positiveCount += 1 }
        }

        if let todayFocus = today.eyeFocusScore, let baseFocus = baseline.averageEyeFocusScore, baseFocus > 0 {
            let delta = (todayFocus - baseFocus) / baseFocus
            let metricScore = max(-100, min(100, delta * 100))
            weightedScore += metricScore * Self.eyeFocusWeight
            totalWeight += Self.eyeFocusWeight
            availableCount += 1
            if metricScore > 0 { positiveCount += 1 }
        }

        if let todaySteps = today.stepCount, let baseSteps = baseline.averageStepCount, baseSteps > 0 {
            let delta = (todaySteps - baseSteps) / baseSteps
            let metricScore = max(-100, min(100, delta * 100))
            weightedScore += metricScore * Self.stepsWeight
            totalWeight += Self.stepsWeight
            availableCount += 1
            if metricScore > 0 { positiveCount += 1 }
        }

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
        let finalScore = Int(max(-20, min(20, normalized / 5)))

        let confidence: String
        if totalWeight >= 0.75 { confidence = "High" }
        else if totalWeight >= 0.45 { confidence = "Medium" }
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
        lines.append("Confidence: \(confidence) (\(availableCount) of 5 metrics available).")
        return lines.joined(separator: "\n")
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
