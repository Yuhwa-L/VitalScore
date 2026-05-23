import SwiftUI

struct ExperimentSelectionView: View {
    @EnvironmentObject var experiments: ExperimentManager
    @State private var customLabel: String = ""
    let onSelected: () -> Void

    private let presetTags: [ExperimentTag] = [
        .noAlcohol, .magnesium, .lessCaffeine, .sleepSchedule,
        .morningSunlight, .exercise, .meditation
    ]

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose Your Experiment")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Pick one lifestyle change to track. VitalLens compares your metrics to your own baseline during this experiment.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(presetTags) { tag in
                        Button {
                            experiments.select(tag)
                            onSelected()
                        } label: {
                            Text(tag.displayName)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .padding()
                                .background(experiments.current == tag ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom").font(.headline)
                    TextField("Describe your experiment", text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                    Button("Use custom tag") {
                        let trimmed = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        experiments.select(.custom, customLabel: trimmed)
                        onSelected()
                    }
                    .disabled(customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}
