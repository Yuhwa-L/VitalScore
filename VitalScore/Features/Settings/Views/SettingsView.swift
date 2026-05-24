import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var storage: LocalStorageManager
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var experiments: ExperimentManager
    @Environment(\.dismiss) private var dismiss

    @State private var showResetConfirm = false
    #if DEBUG
    @AppStorage(VoiceRawAudioDebugExportSettings.userDefaultsKey) private var rawWavExportEnabled = false
    @AppStorage(VoiceRawAudioDebugExportSettings.aiUploadUserDefaultsKey) private var rawWavAIUploadEnabled = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Apple ID", value: "Mock User")
                    LabeledContent("Onboarded", value: storage.hasCompletedOnboarding ? "Yes" : "No")
                    LabeledContent("Health Connected", value: healthKit.isAuthorized ? "Yes" : "No")
                    NavigationLink {
                        VitalScoreSubscriptionView()
                    } label: {
                        Label("Subscription", systemImage: "crown")
                    }
                }

                #if DEBUG
                Section("Voice Export (Debug)") {
                    Toggle("Save raw WAV samples", isOn: $rawWavExportEnabled)
                    Toggle("Attach WAV samples to AI analysis", isOn: $rawWavAIUploadEnabled)
                        .disabled(!rawWavExportEnabled)
                    Text("Development only. Requires explicit local opt-in and writes WAV files under the app Documents folder for offline openSMILE comparison.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("The AI upload toggle attaches those WAV clips to direct API analysis after a voice test. Keep it off unless the user has agreed to raw-audio analysis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Folder", value: VoiceRawAudioDebugExportSettings.directoryName)
                }
                .onChange(of: rawWavExportEnabled) { _, enabled in
                    if !enabled {
                        rawWavAIUploadEnabled = false
                    }
                }
                #endif

                Section("Notifications") {
                    Toggle("Daily reminder", isOn: .constant(true)).disabled(true)
                    Toggle("Weekly insight email", isOn: .constant(false)).disabled(true)
                }

                Section("About") {
                    LabeledContent("App", value: "VitalScore")
                    LabeledContent("Version", value: Bundle.main.versionString)
                    LabeledContent("Build", value: Bundle.main.buildString)
                    LabeledContent("Voice STT Provider", value: Bundle.main.voiceTranscriptionProviderPreference.displayName)
                    LabeledContent("Apple Speech Mode", value: Bundle.main.speechRecognitionMode.displayName)
                    LabeledContent("Cloud STT Model", value: Bundle.main.aiTranscriptionModel)
                    Link("Privacy Policy", destination: Bundle.main.privacyPolicyURL)
                    Link("Terms of Service", destination: Bundle.main.termsURL)
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Reset App (clear all data)", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all app data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset Everything", role: .destructive) {
                    storage.resetAll()
                    healthKit.resetPermission()
                    experiments.clear()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears onboarding, permission, and all saved records. The next launch will start from the welcome screen.")
            }
        }
    }

}

extension Bundle {
    var versionString: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    var buildString: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    var apiBaseURL: URL {
        configuredURL(for: "VitalScoreAPIBaseURL", fallback: "https://api.example.com")
    }

    var privacyPolicyURL: URL {
        configuredURL(for: "VitalScorePrivacyPolicyURL", fallback: "https://example.com/privacy")
    }

    var termsURL: URL {
        configuredURL(for: "VitalScoreTermsURL", fallback: "https://example.com/terms")
    }

    var aiProvider: String {
        configuredString(for: "VitalScoreAIProvider", fallback: "openai")
    }

    private func configuredURL(for key: String, fallback: String) -> URL {
        let rawValue = infoDictionary?[key] as? String
        return URL(string: rawValue ?? fallback) ?? URL(string: fallback)!
    }

    private func configuredString(for key: String, fallback: String) -> String {
        configuredStringValue(for: key, fallback: fallback)
    }
}
