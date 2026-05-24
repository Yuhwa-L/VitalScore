import SwiftUI

struct VitalScoreSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPurchasePlaceholder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                planPanel
                benefits
                legalText
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Purchase Not Connected", isPresented: $showPurchasePlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The subscription UI is ready. Connect an App Store subscription product with StoreKit before accepting purchases.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 52, height: 52)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Unlock VitalScore Plus")
                .font(.largeTitle.weight(.bold))
                .lineLimit(2)

            Text("Track health changes by tag, period, eye-focus, voice analysis, and AI trend suggestions as your routine changes.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Monthly")
                        .font(.headline)
                    Text("1 month free trial")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("$1.99")
                        .font(.title.weight(.bold))
                    Text("/ month after")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button {
                showPurchasePlaceholder = true
            } label: {
                Text("Start 1 Month Free Trial")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                showPurchasePlaceholder = true
            } label: {
                Text("Restore Purchase")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Included")
                .font(.headline)

            SubscriptionBenefitRow(
                systemImage: "tag",
                title: "Tag-based tracking",
                detail: "Compare health trends across routines like Morning, Gym, travel, or alcohol."
            )
            SubscriptionBenefitRow(
                systemImage: "calendar",
                title: "Custom period review",
                detail: "Focus on the exact dates around a lifestyle or environment change."
            )
            SubscriptionBenefitRow(
                systemImage: "brain.head.profile",
                title: "AI wellness suggestions",
                detail: "Get non-medical pattern summaries and low-risk ideas for what to track next."
            )
            SubscriptionBenefitRow(
                systemImage: "eye",
                title: "Eye and voice insights",
                detail: "Review focus and voice wellness signals alongside daily health data."
            )
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var legalText: some View {
        Text("After the 1 month free trial, the plan renews at $1.99 per month unless canceled. Subscription billing, cancellation, and restore purchase behavior must be connected through App Store StoreKit before release.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SubscriptionBenefitRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(Color.blue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        VitalScoreSubscriptionView()
    }
}
