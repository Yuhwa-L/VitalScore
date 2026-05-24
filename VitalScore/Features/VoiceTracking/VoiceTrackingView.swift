import SwiftUI

struct VoiceTrackingView: View {
    static let promptTag = "voice_check_v1"

    @StateObject private var manager = VoiceTrackingManager()
    @Environment(\.dismiss) private var dismiss
    let previousSessions: [VoiceTrackingSession]
    let experimentTag: String
    let onFinished: (VoiceTrackingSession) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            content
            Spacer()
        }
        .padding()
        .navigationTitle("Voice Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") {
                    manager.cancel()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.phase {
        case .idle:
            VStack(spacing: 18) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.teal)
                Text("Voice Wellness Check")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("We compare today’s voice signal with your usual baseline. Audio is analyzed on device for acoustic features and is not stored.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                Button {
                    manager.start()
                } label: {
                    Text("Start Voice Check")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        case .requestingPermission:
            ProgressView("Requesting microphone access...")
        case .countdown(let n):
            VStack(spacing: 12) {
                Text("\(n)")
                    .font(.system(size: 88, weight: .bold))
                Text("Get ready")
                    .foregroundColor(.secondary)
            }
        case .running:
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(manager.currentTask.title)
                        .font(.title3.weight(.semibold))
                    Text("Step \(manager.currentTaskIndex + 1) of \(VoiceTrackingManager.tasks.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(manager.currentTask.instruction)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                voiceMeter
                ProgressView(value: manager.elapsedSeconds, total: manager.currentTask.targetDurationSeconds)
                    .tint(.teal)
                Text("\(Int(ceil(manager.currentTask.targetDurationSeconds - manager.elapsedSeconds)))s remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if manager.currentTask.allowsEarlyFinish {
                    Button {
                        manager.finishEarly()
                    } label: {
                        Text("I Am Finished")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
        case .finished(let result):
            ScrollView {
                resultView(result)
            }
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.red)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    manager.start()
                }
                .font(.headline)
            }
        }
    }

    private var voiceMeter: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 18)
                Capsule()
                    .fill(Color.teal)
                    .frame(width: max(12, 260 * manager.liveLevel), height: 18)
                    .animation(.easeOut(duration: 0.08), value: manager.liveLevel)
            }
            .frame(width: 260)
            Text("Keep the meter moving near the middle.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func resultView(_ result: VoiceTrackingResult) -> some View {
        let scoredResult = VoiceTrackingManager.score(result, against: previousSessions)
        return VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text("Voice Score")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("\(Int(scoredResult.voiceScore))")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(scoreColor(scoredResult.voiceScore))
                Text("\(scoredResult.voiceConfidence) confidence")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Capture Quality")
                    .font(.headline)
                HStack(spacing: 12) {
                    resultMetric("Quality", "\(Int(scoredResult.overallQualityScore * 100))", "%")
                    resultMetric("Silence", "\(Int(scoredResult.silenceRatio * 100))", "%")
                    resultMetric("Baseline", "\(scoredResult.baselineSessionsUsed)", "")
                }
                HStack(spacing: 12) {
                    resultMetric("Avg volume", "\(Int(scoredResult.averageVolumeDb))", "dB")
                    resultMetric("Variability", String(format: "%.1f", scoredResult.volumeStdDevDb), "dB")
                    resultMetric("Peak", "\(Int(scoredResult.peakVolumeDb))", "dB")
                }
            }
            .resultPanel()

            if let features = scoredResult.eGeMAPS {
                VStack(alignment: .leading, spacing: 12) {
                    Text("eGeMAPS Snapshot")
                        .font(.headline)
                    HStack(spacing: 12) {
                        resultMetric("F0", format(features.f0MeanHz, digits: 0), "Hz")
                        resultMetric("Jitter", format(features.jitterLocalPercent, digits: 2), "%")
                        resultMetric("HNR", format(features.hnrMeanDb, digits: 1), "dB")
                    }
                    HStack(spacing: 12) {
                        resultMetric("Shimmer", format(features.shimmerLocalDb, digits: 2), "dB")
                        resultMetric("Flux", format(features.spectralFlux, digits: 3), "")
                        resultMetric("Voiced", format(features.meanVoicedSegmentLengthSeconds, digits: 2), "s")
                    }
                }
                .resultPanel()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Drivers")
                    .font(.headline)
                ForEach(scoredResult.topDrivers, id: \.self) { driver in
                    Text(driver)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .resultPanel()

            Button {
                onFinished(manager.makeSessionMetadata(result: scoredResult, experimentTag: experimentTag))
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }

    private func resultMetric(_ label: String, _ value: String?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text((value ?? "--") + (unit.isEmpty ? "" : " \(unit)"))
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func format(_ value: Double?, digits: Int) -> String? {
        guard let value = value else { return nil }
        return String(format: "%.\(digits)f", value)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score < 50 { return .orange }
        return .primary
    }
}

private extension View {
    func resultPanel() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
    }
}
