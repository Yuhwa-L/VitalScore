import Foundation
import CoreGraphics

struct GazeMetrics: Codable, Equatable {
    let gazeAccuracyPx: Double
    let gazeStabilityPx: Double
    let fixationDurationMs: Double
    let blinkRatePerMin: Double
    let trackingLossPct: Double
    let gazeScore: Double
    let sampleCount: Int

    static func calculateScore(
        gazeAccuracyPx: Double,
        gazeStabilityPx: Double,
        fixationDurationMs: Double,
        trackingLossPct: Double
    ) -> Double {
        let accuracyPenalty = max(0, gazeAccuracyPx - 60) / 4
        let stabilityPenalty = gazeStabilityPx / 5
        let fixationBonus = min(20, max(0, (fixationDurationMs - 200) / 25))
        let trackingPenalty = trackingLossPct / 2
        let raw = 100 - accuracyPenalty - stabilityPenalty - trackingPenalty + fixationBonus
        return min(100, max(0, raw))
    }
}

struct GazeSample {
    let timestamp: TimeInterval
    let rawGazePoint: CGPoint
    let gazePoint: CGPoint
    let targetPoint: CGPoint
    let leftBlink: Float
    let rightBlink: Float
    let trackingValid: Bool
    let inSettlingWindow: Bool
    let inMotionCooldown: Bool
    let motion: MotionSnapshot
    let headPose: HeadPoseSnapshot
    let headPositionDevM: Float
    let headAngularDevDeg: Float

    var euclideanErrorPx: Double {
        let dx = Double(gazePoint.x - targetPoint.x)
        let dy = Double(gazePoint.y - targetPoint.y)
        return sqrt(dx * dx + dy * dy)
    }

    var isBlinking: Bool {
        leftBlink > 0.6 && rightBlink > 0.6
    }
}

enum GazeAggregator {
    static func aggregate(samples: [GazeSample], durationSeconds: TimeInterval) -> GazeMetrics? {
        guard !samples.isEmpty else { return nil }

        let validSamples = samples.filter {
            $0.trackingValid && !$0.isBlinking && !$0.inSettlingWindow && !$0.inMotionCooldown && $0.motion.isStable
        }
        guard !validSamples.isEmpty else {
            return GazeMetrics(
                gazeAccuracyPx: 0,
                gazeStabilityPx: 0,
                fixationDurationMs: 0,
                blinkRatePerMin: 0,
                trackingLossPct: 100,
                gazeScore: 0,
                sampleCount: samples.count
            )
        }

        let errors = validSamples.map { $0.euclideanErrorPx }.sorted()
        let coreErrors = trimmed(errors, keeping: 0.9)
        let meanError = coreErrors.reduce(0, +) / Double(coreErrors.count)
        let variance = coreErrors.map { pow($0 - meanError, 2) }.reduce(0, +) / Double(coreErrors.count)
        let stability = sqrt(variance)

        let trackingLossPct = (1.0 - Double(validSamples.count) / Double(samples.count)) * 100

        let blinkRate = blinkRatePerMinute(samples: samples, durationSeconds: durationSeconds)
        let fixationMs = averageFixationDurationMs(samples: validSamples, toleranceRadiusPx: 50)

        let score = GazeMetrics.calculateScore(
            gazeAccuracyPx: meanError,
            gazeStabilityPx: stability,
            fixationDurationMs: fixationMs,
            trackingLossPct: trackingLossPct
        )

        return GazeMetrics(
            gazeAccuracyPx: meanError,
            gazeStabilityPx: stability,
            fixationDurationMs: fixationMs,
            blinkRatePerMin: blinkRate,
            trackingLossPct: trackingLossPct,
            gazeScore: score,
            sampleCount: samples.count
        )
    }

    private static func trimmed(_ values: [Double], keeping fraction: Double) -> [Double] {
        guard !values.isEmpty else { return values }
        let keepCount = max(1, min(values.count, Int(ceil(Double(values.count) * fraction))))
        return Array(values.prefix(keepCount))
    }

    private static func blinkRatePerMinute(samples: [GazeSample], durationSeconds: TimeInterval) -> Double {
        guard durationSeconds > 0 else { return 0 }
        var blinks = 0
        var inBlink = false
        for sample in samples {
            if sample.isBlinking {
                if !inBlink { blinks += 1; inBlink = true }
            } else {
                inBlink = false
            }
        }
        return Double(blinks) / durationSeconds * 60.0
    }

    private static func averageFixationDurationMs(samples: [GazeSample], toleranceRadiusPx: Double) -> Double {
        guard samples.count > 1 else { return 0 }
        var fixations: [Double] = []
        var fixationStart: TimeInterval?
        var anchorPoint: CGPoint = .zero

        for sample in samples {
            if let start = fixationStart {
                let dx = Double(sample.gazePoint.x - anchorPoint.x)
                let dy = Double(sample.gazePoint.y - anchorPoint.y)
                let dist = sqrt(dx * dx + dy * dy)
                if dist <= toleranceRadiusPx {
                    continue
                }
                let durationMs = (sample.timestamp - start) * 1000
                if durationMs > 80 { fixations.append(durationMs) }
                fixationStart = sample.timestamp
                anchorPoint = sample.gazePoint
            } else {
                fixationStart = sample.timestamp
                anchorPoint = sample.gazePoint
            }
        }

        if let start = fixationStart, let last = samples.last {
            let durationMs = (last.timestamp - start) * 1000
            if durationMs > 80 { fixations.append(durationMs) }
        }

        guard !fixations.isEmpty else { return 0 }
        return fixations.reduce(0, +) / Double(fixations.count)
    }
}
