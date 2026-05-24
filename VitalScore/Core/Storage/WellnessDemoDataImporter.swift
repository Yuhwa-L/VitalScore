import Foundation

struct WellnessDemoImportResult {
    let recordsImported: Int
    let voiceSessionsImported: Int
    let latestRecord: DailyHealthRecord?
}

enum WellnessDemoDataImportError: LocalizedError {
    case missingFixture
    case decodingFailed(Error)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingFixture:
            return "Could not find wellness_demo_7_day.json in the app bundle."
        case .decodingFailed(let error):
            return "Could not decode wellness demo data: \(error.localizedDescription)"
        case .encodingFailed:
            return "Could not save wellness demo data."
        }
    }
}

struct WellnessDemoDataFixture: Codable {
    let schemaVersion: String
    let description: String
    let dateEncoding: String
    let dailyRecords: [DailyHealthRecord]
    let eyeFocusResults: [EyeFocusTestResult]
    let voiceSessions: [VoiceTrackingSession]
}

extension LocalStorageManager {
    var shouldAutoloadWellnessDemo: Bool {
        let records = loadAllRecords()
        return records.isEmpty || records.allSatisfy { $0.wellnessDeltaScore == 0 }
    }

    @discardableResult
    func loadWellnessDemoFixture(bundle: Bundle = .main) throws -> WellnessDemoImportResult {
        guard let url = bundle.url(forResource: "wellness_demo_7_day", withExtension: "json", subdirectory: "MockData")
            ?? bundle.url(forResource: "wellness_demo_7_day", withExtension: "json")
        else {
            throw WellnessDemoDataImportError.missingFixture
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let fixture: WellnessDemoDataFixture
        do {
            fixture = try decoder.decode(WellnessDemoDataFixture.self, from: data)
        } catch {
            throw WellnessDemoDataImportError.decodingFailed(error)
        }

        let records = recalculateWellnessScores(for: fixture.dailyRecords)
        let sessions = fixture.voiceSessions.sorted { $0.date < $1.date }

        let encoder = JSONEncoder()
        guard let recordData = try? encoder.encode(records),
              let sessionData = try? encoder.encode(sessions)
        else {
            throw WellnessDemoDataImportError.encodingFailed
        }

        defaults.set(recordData, forKey: Self.recordsKey)
        defaults.set(sessionData, forKey: Self.voiceSessionsKey)
        revision += 1

        return WellnessDemoImportResult(
            recordsImported: records.count,
            voiceSessionsImported: sessions.count,
            latestRecord: records.last
        )
    }

    private func recalculateWellnessScores(for records: [DailyHealthRecord]) -> [DailyHealthRecord] {
        let engine = WellnessScoreEngine()
        var recalculated: [DailyHealthRecord] = []

        for record in records.sorted(by: { $0.date < $1.date }) {
            let baseline = engine.buildBaseline(from: recalculated, asOf: record.date)
            let result = engine.calculate(today: record, baseline: baseline)
            recalculated.append(record.copyingWellnessResult(result))
        }

        return recalculated
    }
}

private extension DailyHealthRecord {
    func copyingWellnessResult(_ result: WellnessDeltaResult) -> DailyHealthRecord {
        DailyHealthRecord(
            id: id,
            date: date,
            experimentTag: experimentTag,
            sleepHours: sleepHours,
            restingHeartRateBPM: restingHeartRateBPM,
            hrvMs: hrvMs,
            stepCount: stepCount,
            activeEnergyKcal: activeEnergyKcal,
            eyeFocusScore: eyeFocusScore,
            averageReactionMs: averageReactionMs,
            reactionStdDevMs: reactionStdDevMs,
            missedTargets: missedTargets,
            falseTaps: falseTaps,
            gazeAccuracyPx: gazeAccuracyPx,
            gazeStabilityPx: gazeStabilityPx,
            gazeFixationMs: gazeFixationMs,
            gazeBlinkRatePerMin: gazeBlinkRatePerMin,
            gazeTrackingLossPct: gazeTrackingLossPct,
            gazeScore: gazeScore,
            balanceScore: balanceScore,
            swayIndex: swayIndex,
            voiceScore: voiceScore,
            voiceAverageVolumeDb: voiceAverageVolumeDb,
            voiceVolumeStdDevDb: voiceVolumeStdDevDb,
            voiceSilenceRatio: voiceSilenceRatio,
            voicePeakVolumeDb: voicePeakVolumeDb,
            selfReportedEnergy: selfReportedEnergy,
            selfReportedStress: selfReportedStress,
            selfReportedSleepQuality: selfReportedSleepQuality,
            wellnessDeltaScore: result.score,
            confidenceLevel: result.confidence,
            insightText: result.insightText
        )
    }
}
