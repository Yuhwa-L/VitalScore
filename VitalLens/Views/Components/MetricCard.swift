import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String?
    let baseline: String?
    let delta: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let value = value {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let delta = delta {
                        Spacer()
                        deltaLabel(delta)
                    }
                }
                if let baseline = baseline {
                    Text("Baseline: \(baseline) \(unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Not Available")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func deltaLabel(_ delta: Double) -> some View {
        let arrow: String
        let color: Color
        if delta > 0.5 {
            arrow = "↑"
            color = .green
        } else if delta < -0.5 {
            arrow = "↓"
            color = .red
        } else {
            arrow = "—"
            color = .secondary
        }
        return Text(arrow)
            .font(.headline)
            .foregroundColor(color)
    }
}
