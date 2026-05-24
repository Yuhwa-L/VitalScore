import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var storage: LocalStorageManager
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var experiments: ExperimentManager
    @Environment(\.dismiss) private var dismiss

    @State private var showResetConfirm = false
    @State private var showExperimentPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Apple ID", value: "Mock User")
                    LabeledContent("Onboarded", value: storage.hasCompletedOnboarding ? "Yes" : "No")
                    LabeledContent("Health Connected", value: healthKit.isAuthorized ? "Yes" : "No")
                }

                Section("Experiment") {
                    LabeledContent("Current", value: experiments.displayName)
                    Button("Change Experiment") {
                        showExperimentPicker = true
                    }
                }

                Section("Mock Data (Debug)") {
                    Button {
                        healthKit.generateRandom()
                    } label: {
                        Label("Generate Random Data", systemImage: "shuffle")
                    }
                    Button {
                        Task { await healthKit.fetchAllLatest() }
                    } label: {
                        Label("Reload from JSON Seed", systemImage: "arrow.clockwise")
                    }
                    if let lastFetched = healthKit.lastFetchedAt {
                        LabeledContent("Last refresh", value: lastFetched.formatted(date: .omitted, time: .standard))
                    }
                }

                Section("Notifications") {
                    Toggle("Daily reminder", isOn: .constant(true)).disabled(true)
                    Toggle("Weekly insight email", isOn: .constant(false)).disabled(true)
                }

                Section("About") {
                    LabeledContent("App", value: "VitalScore")
                    LabeledContent("Version", value: Bundle.main.versionString)
                    LabeledContent("Build", value: Bundle.main.buildString)
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
                Text("This clears onboarding, experiment selection, permission, and all saved records. The next launch will start from the welcome screen.")
            }
            .sheet(isPresented: $showExperimentPicker) {
                ExperimentSelectionView { showExperimentPicker = false }
                    .environmentObject(experiments)
                    .environmentObject(storage)
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

    private func configuredURL(for key: String, fallback: String) -> URL {
        let rawValue = infoDictionary?[key] as? String
        return URL(string: rawValue ?? fallback) ?? URL(string: fallback)!
    }
}
