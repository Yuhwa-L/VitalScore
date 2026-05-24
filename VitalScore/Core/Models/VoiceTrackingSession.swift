import Foundation

struct VoiceTrackingSession: Codable, Identifiable {
    let id: UUID
    let date: Date
    let experimentTag: String
    let promptTag: String
    let language: String
    let promptVersion: String
    let deviceModel: String
    let osVersion: String
    let microphoneRoute: String
    let sampleRate: Double
    let channels: Int
    let consentVersion: String
    let rawAudioRetentionPolicy: String
    let baselineVersion: String
    let featureExtractorVersion: String
    let modelVersion: String
    let result: VoiceTrackingResult

    init(
        id: UUID = UUID(),
        date: Date,
        experimentTag: String,
        promptTag: String,
        language: String = Locale.current.identifier,
        promptVersion: String = "voice_check_v1",
        deviceModel: String = "unknown",
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        microphoneRoute: String = "unknown",
        sampleRate: Double = 0,
        channels: Int = 1,
        consentVersion: String = "voice_wellness_check_v1",
        rawAudioRetentionPolicy: String = "features_only_no_raw_audio",
        baselineVersion: String = "personal_median_mad_v1",
        featureExtractorVersion: String = "vitalscore_on_device_acoustic_v1",
        modelVersion: String = "personal_baseline_deviation_v1",
        result: VoiceTrackingResult
    ) {
        self.id = id
        self.date = date
        self.experimentTag = experimentTag
        self.promptTag = promptTag
        self.language = language
        self.promptVersion = promptVersion
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.microphoneRoute = microphoneRoute
        self.sampleRate = sampleRate
        self.channels = channels
        self.consentVersion = consentVersion
        self.rawAudioRetentionPolicy = rawAudioRetentionPolicy
        self.baselineVersion = baselineVersion
        self.featureExtractorVersion = featureExtractorVersion
        self.modelVersion = modelVersion
        self.result = result
    }
}
