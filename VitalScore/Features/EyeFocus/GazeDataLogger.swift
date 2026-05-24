import Foundation
import os
import CoreGraphics

private let log = Logger(subsystem: "com.vitalscore.app", category: "gaze-logger")

struct GazeLogSample: Codable {
    let timestamp: TimeInterval
    let rawGazeX: Double
    let rawGazeY: Double
    let gazeX: Double
    let gazeY: Double
    let targetX: Double
    let targetY: Double
    let leftBlink: Float
    let rightBlink: Float
    let trackingValid: Bool
    let inSettlingWindow: Bool
    let inMotionCooldown: Bool
    let motion: MotionSnapshot
    let headPose: HeadPoseSnapshot
    let headPositionDevM: Float
    let headAngularDevDeg: Float
}

struct ReactionLog: Codable {
    let averageReactionMs: Double
    let reactionStdDevMs: Double
    let missedTargets: Int
    let falseTaps: Int
    let hitCount: Int
    let reactionTimesMs: [Double]
}

struct GazeLogFile: Codable {
    let backend: String
    let startedAt: Date
    let testStartedAt: Date
    let durationSeconds: TimeInterval
    let frameCount: Int
    let screenWidthPx: Double
    let screenHeightPx: Double
    let calibration: CalibrationSummary?
    let metrics: GazeMetrics?
    let reaction: ReactionLog?
    let samples: [GazeLogSample]
}

enum GazeDataLogger {
    static func save(
        samples: [GazeSample],
        metrics: GazeMetrics?,
        backend: String,
        startedAt: Date,
        testStartedAt: Date,
        durationSeconds: TimeInterval,
        calibration: CalibrationSummary?,
        screenSize: CGSize,
        reaction: ReactionLog? = nil
    ) -> URL? {
        let logEntries = samples.map { s in
            GazeLogSample(
                timestamp: s.timestamp,
                rawGazeX: Double(s.rawGazePoint.x),
                rawGazeY: Double(s.rawGazePoint.y),
                gazeX: Double(s.gazePoint.x),
                gazeY: Double(s.gazePoint.y),
                targetX: Double(s.targetPoint.x),
                targetY: Double(s.targetPoint.y),
                leftBlink: s.leftBlink,
                rightBlink: s.rightBlink,
                trackingValid: s.trackingValid,
                inSettlingWindow: s.inSettlingWindow,
                inMotionCooldown: s.inMotionCooldown,
                motion: s.motion,
                headPose: s.headPose,
                headPositionDevM: s.headPositionDevM,
                headAngularDevDeg: s.headAngularDevDeg
            )
        }

        let file = GazeLogFile(
            backend: backend,
            startedAt: startedAt,
            testStartedAt: testStartedAt,
            durationSeconds: durationSeconds,
            frameCount: samples.count,
            screenWidthPx: Double(screenSize.width),
            screenHeightPx: Double(screenSize.height),
            calibration: calibration,
            metrics: metrics,
            reaction: reaction,
            samples: logEntries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(file) else {
            log.error("Failed to encode gaze log JSON")
            return nil
        }

        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            log.error("No documents directory")
            return nil
        }

        let dir = docs.appendingPathComponent("GazeLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fileName = "gaze_\(formatter.string(from: startedAt).replacingOccurrences(of: ":", with: "-")).json"
        let url = dir.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
            log.info("Saved gaze log: \(url.path, privacy: .public) (\(samples.count) samples, \(data.count) bytes)")
            return url
        } catch {
            log.error("Failed to write gaze log: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func listSavedLogs() -> [URL] {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let dir = docs.appendingPathComponent("GazeLogs", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
