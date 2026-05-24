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

    func test_scoreIgnoresUnsupportedEGeMAPSPlaceholders() {
        let baseline = (0..<7).map { index in
            makeSession(
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                eGeMAPS: makeFeatures(f0: 120, jitter: 1, shimmer: 0.2, hnr: 15, mfcc: 1)
            )
        }
        let current = makeResult(
            date: Date(timeIntervalSince1970: 100),
            eGeMAPS: makeFeatures(f0: 320, jitter: 60, shimmer: 12, hnr: -5, mfcc: 50)
        )

        let scored = VoiceTrackingManager.score(current, against: baseline)

        XCTAssertEqual(scored.voiceScore, 100, accuracy: 0.001)
        XCTAssertFalse(scored.topDrivers.contains { $0.localizedCaseInsensitiveContains("jitter") })
        XCTAssertFalse(scored.topDrivers.contains { $0.localizedCaseInsensitiveContains("shimmer") })
    }

    func test_aiConversationAutoSubmit_requiresMoreThanOneWord() {
        XCTAssertFalse(VoiceTrackingManager.shouldAutoSubmitConversationTranscript(
            "tired",
            elapsedSinceTurnStart: 10,
            elapsedSinceLastSpeech: 10
        ))
    }

    func test_aiConversationAutoSubmit_requiresClearPauseAndMinimumListeningTime() {
        let transcript = "I feel tired today"

        XCTAssertFalse(VoiceTrackingManager.shouldAutoSubmitConversationTranscript(
            transcript,
            elapsedSinceTurnStart: 1,
            elapsedSinceLastSpeech: 10
        ))
        XCTAssertFalse(VoiceTrackingManager.shouldAutoSubmitConversationTranscript(
            transcript,
            elapsedSinceTurnStart: 10,
            elapsedSinceLastSpeech: 0.5
        ))
        XCTAssertTrue(VoiceTrackingManager.shouldAutoSubmitConversationTranscript(
            transcript,
            elapsedSinceTurnStart: 4,
            elapsedSinceLastSpeech: 3
        ))
    }

    private func makeSession(date: Date, eGeMAPS: VoiceEGeMAPSFeatureSet) -> VoiceTrackingSession {
        let result = makeResult(date: date, eGeMAPS: eGeMAPS)
        return VoiceTrackingSession(date: date, experimentTag: "Test", promptTag: "test", result: result)
    }

    private func makeResult(date: Date, eGeMAPS: VoiceEGeMAPSFeatureSet) -> VoiceTrackingResult {
        VoiceTrackingResult(
            completedAt: date,
            durationSeconds: 20,
            voiceScore: 100,
            voiceConfidence: "Medium",
            averageVolumeDb: -24,
            volumeStdDevDb: 2,
            silenceRatio: 0.05,
            peakVolumeDb: -10,
            overallQualityScore: 1,
            usable: true,
            qualityIssues: [],
            taskAnalyses: [
                VoiceTaskAnalysis(
                    taskType: .sustainedVowelAFirst,
                    promptId: "ah_1",
                    promptText: nil,
                    targetDurationSeconds: 5,
                    durationSeconds: 5,
                    sampleCount: 50,
                    averageVolumeDb: -24,
                    volumeStdDevDb: 2,
                    peakVolumeDb: -10,
                    silenceRatio: 0.05,
                    clippingPercentage: 0,
                    zeroCrossingRate: 0.1,
                    voicedFrameRatio: 0.95,
                    snrDb: 20,
                    eGeMAPS: eGeMAPS,
                    qualityScore: 1,
                    qualityIssues: [],
                    usable: true,
                    featureVersion: VoiceTrackingManager.featureExtractorVersion
                ),
                VoiceTaskAnalysis(
                    taskType: .guidedConversation,
                    promptId: "talk",
                    promptText: nil,
                    targetDurationSeconds: 20,
                    durationSeconds: 20,
                    sampleCount: 200,
                    averageVolumeDb: -24,
                    volumeStdDevDb: 2,
                    peakVolumeDb: -10,
                    silenceRatio: 0.05,
                    clippingPercentage: 0,
                    zeroCrossingRate: 0.1,
                    voicedFrameRatio: 0.95,
                    snrDb: 20,
                    eGeMAPS: eGeMAPS,
                    qualityScore: 1,
                    qualityIssues: [],
                    usable: true,
                    featureVersion: VoiceTrackingManager.featureExtractorVersion
                )
            ],
            eGeMAPS: eGeMAPS,
            baselineSessionsUsed: 7,
            baselineStatus: "personal_baseline_active",
            topDrivers: []
        )
    }

    private func makeFeatures(
        f0: Double,
        jitter: Double,
        shimmer: Double,
        hnr: Double,
        mfcc: Double
    ) -> VoiceEGeMAPSFeatureSet {
        VoiceEGeMAPSFeatureSet(
            loudnessMeanDb: -24,
            loudnessStdDevDb: 2,
            f0MeanHz: f0,
            f0StdDevHz: f0 / 10,
            jitterLocalPercent: jitter,
            shimmerLocalDb: shimmer,
            hnrMeanDb: hnr,
            alphaRatioDb: mfcc,
            hammarbergIndexDb: mfcc,
            spectralFlux: 0.02,
            slopeV0: mfcc,
            slopeUV0: mfcc,
            mfcc1Mean: mfcc,
            mfcc2Mean: mfcc,
            mfcc3Mean: mfcc,
            voicedSegmentsPerSecond: 0.2,
            meanVoicedSegmentLengthSeconds: 4
        )
    }
}
