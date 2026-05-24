import XCTest
@testable import VitalScore

final class VoiceTrackingScoringTests: XCTestCase {
    func test_steadyVoice_scoresHigh() {
        let score = VoiceTrackingManager.calculateScore(
            volumeStdDevDb: 2,
            silenceRatio: 0,
            averageVolumeDb: -25
        )
        XCTAssertEqual(score, 96, accuracy: 0.001)
    }

    func test_silencePenalty_reducesScore() {
        let score = VoiceTrackingManager.calculateScore(
            volumeStdDevDb: 2,
            silenceRatio: 0.5,
            averageVolumeDb: -25
        )
        XCTAssertEqual(score, 73.5, accuracy: 0.001)
    }

    func test_scoreClampsToBounds() {
        let high = VoiceTrackingManager.calculateScore(
            volumeStdDevDb: 0,
            silenceRatio: 0,
            averageVolumeDb: -25
        )
        XCTAssertLessThanOrEqual(high, 100)

        let low = VoiceTrackingManager.calculateScore(
            volumeStdDevDb: 80,
            silenceRatio: 1,
            averageVolumeDb: -80
        )
        XCTAssertGreaterThanOrEqual(low, 0)
    }

    func test_resultUsesVoicedSamplesForVolumeMetrics() {
        let result = VoiceTrackingManager.makeResult(
            from: [-80, -24, -26, -80],
            durationSeconds: 20
        )

        XCTAssertEqual(result.averageVolumeDb, -25, accuracy: 0.001)
        XCTAssertEqual(result.silenceRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.peakVolumeDb, -24, accuracy: 0.001)
    }

    func test_normalizedLevelMapsDbIntoDisplayRange() {
        XCTAssertEqual(VoiceTrackingManager.normalizedLevel(from: -60), 0, accuracy: 0.001)
        XCTAssertEqual(VoiceTrackingManager.normalizedLevel(from: 0), 1, accuracy: 0.001)
        XCTAssertEqual(VoiceTrackingManager.normalizedLevel(from: -30), 0.5, accuracy: 0.001)
    }
}
