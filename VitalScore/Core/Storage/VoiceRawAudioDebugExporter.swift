import AVFoundation
import Foundation

enum VoiceRawAudioDebugExportSettings {
    static let userDefaultsKey = "com.vitalscore.debug.voiceRawWavExport.enabled"
    static let aiUploadUserDefaultsKey = "com.vitalscore.debug.voiceRawWavUpload.enabled"
    static let directoryName = "VitalScoreDebugVoiceWAV"
    static let manifestFileName = "manifest.json"
    static let maxAIUploadSampleCount = 6
    static let maxAIUploadTotalBytes = 6_000_000

    static var isEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
        #else
        return false
        #endif
    }

    static var isAIUploadEnabled: Bool {
        #if DEBUG
        return isEnabled && UserDefaults.standard.bool(forKey: aiUploadUserDefaultsKey)
        #else
        return false
        #endif
    }

    static var rawAudioRetentionPolicy: String {
        guard isEnabled else { return "features_only_no_raw_audio" }
        return isAIUploadEnabled ? "debug_opt_in_raw_wav_local_and_ai_upload" : "debug_opt_in_raw_wav_local_only"
    }

    static var rootDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(directoryName, isDirectory: true)
    }
}

struct VoiceRawAudioDebugManifest: Codable {
    static let schemaVersion = "vitalscore_debug_voice_wav_manifest_v1"

    let schemaVersion: String
    let sessionId: UUID
    let createdAt: Date
    let warning: String
    var samples: [VoiceRawAudioDebugSample]
}

struct VoiceRawAudioDebugSample: Codable, Identifiable {
    let id: UUID
    let taskType: VoiceTaskType
    let promptId: String
    let promptText: String
    let turnIndex: Int?
    let fileName: String
    let startedAt: Date
    var endedAt: Date?
    var durationSeconds: TimeInterval?
    let sampleRate: Double
    let channels: Int
    var status: String
}

final class VoiceRawAudioDebugExporter {
    private var manifest: VoiceRawAudioDebugManifest?
    private var sessionDirectory: URL?
    private var activeFile: AVAudioFile?
    private var activeSampleId: UUID?
    private var audioFormat: AVAudioFormat?
    private let fileManager = FileManager.default

    var manifestURL: URL? {
        sessionDirectory?.appendingPathComponent(VoiceRawAudioDebugExportSettings.manifestFileName)
    }

    func beginSession(startedAt: Date, inputFormat: AVAudioFormat) {
        guard VoiceRawAudioDebugExportSettings.isEnabled else { return }
        reset()

        let sessionId = UUID()
        let directory = VoiceRawAudioDebugExportSettings.rootDirectory
            .appendingPathComponent(Self.sessionDirectoryName(date: startedAt, id: sessionId), isDirectory: true)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            sessionDirectory = directory
            audioFormat = inputFormat
            manifest = VoiceRawAudioDebugManifest(
                schemaVersion: VoiceRawAudioDebugManifest.schemaVersion,
                sessionId: sessionId,
                createdAt: startedAt,
                warning: "Development-only raw WAV export. Use only with explicit local opt-in. Do not ship or upload raw audio.",
                samples: []
            )
            writeManifest()
        } catch {
            assertionFailure("Failed to create debug WAV export directory: \(error.localizedDescription)")
            reset()
        }
    }

    func beginSample(task: VoiceTaskDefinition, turnIndex: Int?, startedAt: Date) {
        guard VoiceRawAudioDebugExportSettings.isEnabled,
              let sessionDirectory,
              let audioFormat
        else { return }

        finishActiveSample(endedAt: startedAt, durationSeconds: nil, status: "interrupted")

        let sampleId = UUID()
        let fileName = Self.fileName(
            date: startedAt,
            promptId: task.promptId,
            turnIndex: turnIndex,
            id: sampleId
        )
        let fileURL = sessionDirectory.appendingPathComponent(fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audioFormat.sampleRate,
            AVNumberOfChannelsKey: Int(audioFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            activeFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            activeSampleId = sampleId
            manifest?.samples.append(
                VoiceRawAudioDebugSample(
                    id: sampleId,
                    taskType: task.type,
                    promptId: task.promptId,
                    promptText: task.instruction,
                    turnIndex: turnIndex,
                    fileName: fileName,
                    startedAt: startedAt,
                    endedAt: nil,
                    durationSeconds: nil,
                    sampleRate: audioFormat.sampleRate,
                    channels: Int(audioFormat.channelCount),
                    status: "recording"
                )
            )
            writeManifest()
        } catch {
            assertionFailure("Failed to create debug WAV file: \(error.localizedDescription)")
            activeFile = nil
            activeSampleId = nil
        }
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        guard VoiceRawAudioDebugExportSettings.isEnabled,
              let activeFile
        else { return }

        do {
            try activeFile.write(from: buffer)
        } catch {
            assertionFailure("Failed to write debug WAV buffer: \(error.localizedDescription)")
        }
    }

    func finishActiveSample(
        endedAt: Date,
        durationSeconds: TimeInterval?,
        status: String = "completed"
    ) {
        guard let activeSampleId else { return }
        activeFile = nil

        if let index = manifest?.samples.firstIndex(where: { $0.id == activeSampleId }) {
            manifest?.samples[index].endedAt = endedAt
            manifest?.samples[index].durationSeconds = durationSeconds
            manifest?.samples[index].status = status
        }
        self.activeSampleId = nil
        writeManifest()
    }

    func finishSession(endedAt: Date = Date()) {
        finishActiveSample(endedAt: endedAt, durationSeconds: nil, status: "stopped")
        writeManifest()
    }

    func reset() {
        activeFile = nil
        activeSampleId = nil
        manifest = nil
        sessionDirectory = nil
        audioFormat = nil
    }

    private func writeManifest() {
        guard let manifest, let manifestURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to write debug WAV manifest: \(error.localizedDescription)")
        }
    }

    private static func sessionDirectoryName(date: Date, id: UUID) -> String {
        "\(fileDateFormatter.string(from: date))_\(id.uuidString)"
    }

    private static func fileName(date: Date, promptId: String, turnIndex: Int?, id: UUID) -> String {
        let turnSuffix = turnIndex.map { "_turn_\($0)" } ?? ""
        return "\(fileDateFormatter.string(from: date))_\(promptId.sanitizedFileComponent)\(turnSuffix)_\(id.uuidString).wav"
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()
}

private extension String {
    var sanitizedFileComponent: String {
        map { character in
            character.isLetter || character.isNumber || character == "_" || character == "-" ? character : "_"
        }
        .reduce(into: "") { $0.append($1) }
    }
}
