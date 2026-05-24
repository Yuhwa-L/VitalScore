import Foundation

struct VoiceTrackingSession: Codable, Identifiable, Equatable {
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
    let rawAudioDebugManifestPath: String?
    let baselineVersion: String
    let featureExtractorVersion: String
    let modelVersion: String
    let result: VoiceTrackingResult

    var containsLocallySavedLiveData: Bool {
        result.containsLocallySavedLiveData ||
        (result.hasLiveConversationTask && rawAudioDebugManifestPath != nil)
    }

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
        rawAudioDebugManifestPath: String? = nil,
        baselineVersion: String = "personal_median_mad_v1",
        featureExtractorVersion: String = "vitalscore_on_device_acoustic_v1",
        modelVersion: String = "personal_baseline_deviation_v1",
        result: VoiceTrackingResult
    ) {
        self.id = id
        self.date = date
        self.experimentTag = ExperimentTagValue.normalized(experimentTag)
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
        self.rawAudioDebugManifestPath = rawAudioDebugManifestPath
        self.baselineVersion = baselineVersion
        self.featureExtractorVersion = featureExtractorVersion
        self.modelVersion = modelVersion
        self.result = result
    }

    func replacingResult(_ result: VoiceTrackingResult) -> VoiceTrackingSession {
        VoiceTrackingSession(
            id: id,
            date: date,
            experimentTag: experimentTag,
            promptTag: promptTag,
            language: language,
            promptVersion: promptVersion,
            deviceModel: deviceModel,
            osVersion: osVersion,
            microphoneRoute: microphoneRoute,
            sampleRate: sampleRate,
            channels: channels,
            consentVersion: consentVersion,
            rawAudioRetentionPolicy: rawAudioRetentionPolicy,
            rawAudioDebugManifestPath: rawAudioDebugManifestPath,
            baselineVersion: baselineVersion,
            featureExtractorVersion: featureExtractorVersion,
            modelVersion: modelVersion,
            result: result
        )
    }

    func removingLocallySavedLiveData() -> VoiceTrackingSession {
        guard containsLocallySavedLiveData else { return self }
        return VoiceTrackingSession(
            id: id,
            date: date,
            experimentTag: experimentTag,
            promptTag: promptTag,
            language: language,
            promptVersion: promptVersion,
            deviceModel: deviceModel,
            osVersion: osVersion,
            microphoneRoute: microphoneRoute,
            sampleRate: sampleRate,
            channels: channels,
            consentVersion: consentVersion,
            rawAudioRetentionPolicy: result.hasLiveConversationTask
                ? "features_only_no_raw_audio"
                : rawAudioRetentionPolicy,
            rawAudioDebugManifestPath: result.hasLiveConversationTask
                ? nil
                : rawAudioDebugManifestPath,
            baselineVersion: baselineVersion,
            featureExtractorVersion: featureExtractorVersion,
            modelVersion: modelVersion,
            result: result.removingLocallySavedLiveData()
        )
    }
}
