import AVFoundation
import Foundation

final class VoicePromptSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    private static let preferredVoiceNames = ["Ava", "Samantha", "Allison", "Nicky", "Susan"]

    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        stop()
        self.completion = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.84
        utterance.pitchMultiplier = 1.06
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.2

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeech()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    private func finishSpeech() {
        DispatchQueue.main.async {
            self.isSpeaking = false
            let completion = self.completion
            self.completion = nil
            completion?()
        }
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let configuredIdentifier = Bundle.main.aiVoiceIdentifier {
            let configuredVoice = voices.first {
                $0.identifier == configuredIdentifier || $0.name.localizedCaseInsensitiveContains(configuredIdentifier)
            }
            if let configuredVoice {
                return configuredVoice
            }
        }

        let englishVoices = voices
            .filter { $0.language == "en-US" || $0.language.hasPrefix("en-") }

        return englishVoices.max { voiceScore($0) < voiceScore($1) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = voice.language == "en-US" ? 100 : 40

        if let nameIndex = preferredVoiceNames.firstIndex(where: { voice.name.localizedCaseInsensitiveContains($0) }) {
            score += 80 - nameIndex
        }

        switch voice.quality {
        case .premium:
            score += 50
        case .enhanced:
            score += 35
        case .default:
            score += 0
        @unknown default:
            score += 0
        }

        if voice.identifier.localizedCaseInsensitiveContains("compact") {
            score -= 20
        }

        return score
    }
}

private extension Bundle {
    var aiVoiceIdentifier: String? {
        let rawValue = (infoDictionary?["VitalScoreAIVoiceIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rawValue?.isEmpty == false ? rawValue : nil
    }
}
