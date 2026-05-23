import SwiftUI

struct InsightReportView: View {
    let result: WellnessDeltaResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Wellness Delta")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("\(result.score >= 0 ? "+" : "")\(result.score)")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(scoreColor)
                    Text("Confidence: \(result.confidence)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(insightLines, id: \.self) { line in
                        Text("• " + line)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                DisclaimerBanner()

                Button("Done") { dismiss() }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Insight")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var insightLines: [String] {
        result.insightText.split(separator: "\n").map(String.init)
    }

    private var scoreColor: Color {
        if result.score > 2 { return .green }
        if result.score < -2 { return .red }
        return .primary
    }
}
