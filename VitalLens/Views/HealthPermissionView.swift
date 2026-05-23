import SwiftUI

struct HealthPermissionView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    let onComplete: () -> Void

    @State private var showPermissionSheet = false

    private let metrics: [(name: String, reason: String)] = [
        ("Sleep", "Sleep duration trend."),
        ("Resting Heart Rate", "Recovery and stress trend marker."),
        ("Heart Rate Variability", "Recovery and autonomic marker."),
        ("Steps", "Daily activity context."),
        ("Active Energy", "Activity intensity context.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect Apple Health")
                .font(.title)
                .fontWeight(.bold)
            Text("VitalLens reads available data with your permission. Each metric is optional — the app works with whatever you allow.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(metrics, id: \.name) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.name).font(.headline)
                            Text(metric.reason).font(.caption).foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
            }
            Spacer()
            Button {
                showPermissionSheet = true
            } label: {
                Text("Connect Apple Health")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            Button("Continue without connecting", action: onComplete)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .padding()
        .sheet(isPresented: $showPermissionSheet) {
            MockHealthAuthorizationSheet(
                metrics: metrics,
                onAllow: {
                    showPermissionSheet = false
                    healthKit.requestAuthorization()
                    Task {
                        await healthKit.fetchAllLatest()
                        onComplete()
                    }
                },
                onCancel: {
                    showPermissionSheet = false
                }
            )
        }
    }
}

private struct MockHealthAuthorizationSheet: View {
    let metrics: [(name: String, reason: String)]
    let onAllow: () -> Void
    let onCancel: () -> Void

    @State private var toggles: [String: Bool] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Allow “VitalLens” to access your health data in the categories below.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        SectionHeader("Turn On All")
                        turnOnAllRow

                        SectionHeader("Allow “VitalLens” to Read")
                        VStack(spacing: 0) {
                            ForEach(Array(metrics.enumerated()), id: \.element.name) { index, metric in
                                row(for: metric.name)
                                if index < metrics.count - 1 {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        Text("App Explanation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        Text("VitalLens reads heart rate, sleep, steps, and activity data to show wellness trends over time. This is not medical advice.")
                            .font(.footnote)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                Divider()
                Button(action: onAllow) {
                    Text("Allow")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Color(.systemBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Don’t Allow", action: onCancel).foregroundColor(.accentColor)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Health Access").font(.headline)
                    }
                }
            }
        }
        .onAppear {
            for metric in metrics where toggles[metric.name] == nil {
                toggles[metric.name] = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 36))
                .foregroundColor(.pink)
                .padding(.top, 12)
            Text("Health Access")
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var turnOnAllRow: some View {
        Button {
            let newValue = !allOn
            for metric in metrics {
                toggles[metric.name] = newValue
            }
        } label: {
            HStack {
                Text("Turn On All")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: allOn ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(allOn ? .accentColor : .secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func row(for name: String) -> some View {
        HStack {
            Image(systemName: icon(for: name))
                .foregroundColor(color(for: name))
                .frame(width: 30, height: 30)
                .background(color(for: name).opacity(0.15))
                .cornerRadius(6)
                .padding(.leading)
            Text(name)
                .padding(.leading, 8)
            Spacer()
            Toggle("", isOn: Binding(
                get: { toggles[name] ?? false },
                set: { toggles[name] = $0 }
            ))
            .labelsHidden()
            .padding(.trailing)
        }
        .padding(.vertical, 10)
    }

    private var allOn: Bool {
        metrics.allSatisfy { toggles[$0.name] ?? false }
    }

    private func icon(for name: String) -> String {
        switch name {
        case "Sleep": return "bed.double.fill"
        case "Resting Heart Rate": return "heart.fill"
        case "Heart Rate Variability": return "waveform.path.ecg"
        case "Steps": return "figure.walk"
        case "Active Energy": return "flame.fill"
        default: return "heart.fill"
        }
    }

    private func color(for name: String) -> Color {
        switch name {
        case "Sleep": return .indigo
        case "Resting Heart Rate", "Heart Rate Variability": return .red
        case "Steps": return .orange
        case "Active Energy": return .pink
        default: return .red
        }
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.top, 8)
    }
}
