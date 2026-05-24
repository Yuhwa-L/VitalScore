import Foundation

enum VoiceTranscriptionProviderPreference: String {
    case fluidAudio = "fluid_audio"
    case appleSpeech = "apple_speech"

    init(configuredValue: String?) {
        let normalized = configuredValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        self = VoiceTranscriptionProviderPreference(rawValue: normalized ?? "") ?? .fluidAudio
    }

    var displayName: String {
        switch self {
        case .fluidAudio:
            return "FluidAudio Parakeet EOU"
        case .appleSpeech:
            return "Apple Speech"
        }
    }
}

enum SpeechRecognitionMode: String {
    case bestAvailable = "best_available"
    case onDevice = "on_device"

    init(configuredValue: String?) {
        let normalized = configuredValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        self = SpeechRecognitionMode(rawValue: normalized ?? "") ?? .bestAvailable
    }

    var displayName: String {
        switch self {
        case .bestAvailable:
            return "Best available"
        case .onDevice:
            return "On device"
        }
    }
}

extension Bundle {
    var voiceTranscriptionProviderPreference: VoiceTranscriptionProviderPreference {
        VoiceTranscriptionProviderPreference(
            configuredValue: configuredStringValue(
                for: "VitalScoreVoiceTranscriptionProvider",
                fallback: VoiceTranscriptionProviderPreference.fluidAudio.rawValue
            )
        )
    }

    var speechRecognitionMode: SpeechRecognitionMode {
        SpeechRecognitionMode(
            configuredValue: configuredStringValue(
                for: "VitalScoreSpeechRecognitionMode",
                fallback: SpeechRecognitionMode.bestAvailable.rawValue
            )
        )
    }

    var aiTranscriptionModel: String {
        configuredStringValue(
            for: "VitalScoreAITranscriptionModel",
            fallback: "gpt-realtime-whisper"
        )
    }

    func configuredStringValue(for key: String, fallback: String) -> String {
        let rawValue = (infoDictionary?[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue,
              !rawValue.isEmpty,
              !rawValue.contains("$(")
        else {
            return fallback
        }
        return rawValue
    }
}
