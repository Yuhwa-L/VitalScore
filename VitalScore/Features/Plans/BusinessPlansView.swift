import SwiftUI

struct BusinessPlansView: View {
    @State private var selectedAudience: BusinessPlanAudience = .schools

    private var selectedPlan: BusinessPlan {
        switch selectedAudience {
        case .schools:
            return .schools
        case .consumers:
            return .consumers
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                audiencePicker
                recommendationCard
                planSnapshot
                metricGrid

                ForEach(selectedPlan.sections) { section in
                    planSection(section)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Business Plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Business Model", systemImage: "briefcase.fill")
                .font(.title2.weight(.bold))

            Text("Dual-track growth: use the consumer plan to prove daily engagement, then sell schools a non-diagnostic early-warning workflow for student wellness risk.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var audiencePicker: some View {
        Picker("Audience", selection: $selectedAudience) {
            ForEach(BusinessPlanAudience.allCases) { audience in
                Text(audience.title).tag(audience)
            }
        }
        .pickerStyle(.segmented)
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.max.fill")
                    .foregroundStyle(.yellow)
                Text("Recommended Plan")
                    .font(.headline)
            }

            Text("Prioritize school pilots for revenue and distribution. Keep the $1.99/month consumer plan as a low-friction validation loop and a parent/student entry point.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private var planSnapshot: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedPlan.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selectedPlan.tint)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedPlan.title)
                        .font(.headline)
                    Text(selectedPlan.positioning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            planFact(label: "Revenue", value: selectedPlan.revenueModel)
            planFact(label: "Entry", value: selectedPlan.entryOffer)
            planFact(label: "Paid offer", value: selectedPlan.paidOffer)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(selectedPlan.metrics) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: metric.systemImage)
                        .font(.headline)
                        .foregroundStyle(metric.tint)
                    Text(metric.value)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(metric.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(8)
            }
        }
    }

    private func planSection(_ section: BusinessPlanSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(row.tint)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                            Text(row.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)

                    if index < section.rows.count - 1 {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(8)
        }
    }

    private func planFact(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum BusinessPlanAudience: String, CaseIterable, Identifiable {
    case schools
    case consumers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schools:
            return "Schools"
        case .consumers:
            return "Consumer"
        }
    }
}

private struct BusinessPlan {
    let audience: BusinessPlanAudience
    let title: String
    let positioning: String
    let revenueModel: String
    let entryOffer: String
    let paidOffer: String
    let systemImage: String
    let tint: Color
    let metrics: [BusinessPlanMetric]
    let sections: [BusinessPlanSection]

    static let schools = BusinessPlan(
        audience: .schools,
        title: "toB: School Health-Risk Early Warning",
        positioning: "Move schools from passive counseling to proactive, privacy-aware wellness risk monitoring across sleep, fatigue, focus, and voice signals.",
        revenueModel: "Paid pilot, then annual campus or district license",
        entryOffer: "60-90 day pilot with aggregate dashboard and counselor workflow",
        paidOffer: "$6-12 per student per year pricing hypothesis",
        systemImage: "building.columns.fill",
        tint: .indigo,
        metrics: [
            BusinessPlanMetric(label: "Pilot length", value: "60-90d", systemImage: "calendar.badge.clock", tint: .indigo),
            BusinessPlanMetric(label: "Buyer", value: "School", systemImage: "person.2.badge.gearshape", tint: .teal),
            BusinessPlanMetric(label: "Primary ROI", value: "Risk flags", systemImage: "exclamationmark.triangle.fill", tint: .orange),
            BusinessPlanMetric(label: "Scale unit", value: "Campus", systemImage: "rectangle.stack.fill", tint: .purple)
        ],
        sections: [
            BusinessPlanSection(
                title: "Why Schools Buy",
                rows: [
                    BusinessPlanRow(title: "Student health", body: "Aggregate trends help staff see wellness deterioration before a crisis escalates.", systemImage: "heart.text.square.fill", tint: .red),
                    BusinessPlanRow(title: "Mental health prevention", body: "The app reports non-diagnostic risk signals and directs staff toward earlier check-ins.", systemImage: "brain.head.profile", tint: .purple),
                    BusinessPlanRow(title: "Sleep and fatigue", body: "Sleep, HRV, focus, and voice measures create a daily fatigue signal tied to academic readiness.", systemImage: "bed.double.fill", tint: .blue),
                    BusinessPlanRow(title: "Retention and parent trust", body: "Schools can show a proactive care process without exposing private student-level data broadly.", systemImage: "person.crop.circle.badge.checkmark", tint: .green)
                ]
            ),
            BusinessPlanSection(
                title: "Package",
                rows: [
                    BusinessPlanRow(title: "Student app", body: "Daily assessments, baseline history, and intervention insights for students.", systemImage: "iphone", tint: .teal),
                    BusinessPlanRow(title: "Counselor dashboard", body: "Role-based alerts, cohort trends, and follow-up notes for authorized staff.", systemImage: "chart.line.uptrend.xyaxis", tint: .indigo),
                    BusinessPlanRow(title: "Privacy guardrails", body: "Use consent, minimum necessary data, and aggregate reporting as the default school workflow.", systemImage: "lock.shield.fill", tint: .gray)
                ]
            ),
            BusinessPlanSection(
                title: "Pilot Success Criteria",
                rows: [
                    BusinessPlanRow(title: "Adoption", body: "At least 50% of invited students complete three or more weekly check-ins.", systemImage: "person.3.fill", tint: .teal),
                    BusinessPlanRow(title: "Signal quality", body: "Counselors confirm that flagged trends match students who merit follow-up.", systemImage: "checkmark.seal.fill", tint: .green),
                    BusinessPlanRow(title: "Operational fit", body: "Staff can review weekly risk summaries in under 30 minutes per cohort.", systemImage: "timer", tint: .orange)
                ]
            )
        ]
    )

    static let consumers = BusinessPlan(
        audience: .consumers,
        title: "toC: Personal Wellness Baseline",
        positioning: "Help users build a month-long baseline, then keep them subscribed with longitudinal trends and intervention insights.",
        revenueModel: "Free trial, then low-cost monthly subscription",
        entryOffer: "1-month free trial to build baseline and intervention history",
        paidOffer: "$1.99 per month subscription",
        systemImage: "person.crop.circle.fill",
        tint: .teal,
        metrics: [
            BusinessPlanMetric(label: "Trial", value: "1 month", systemImage: "clock.badge.checkmark", tint: .teal),
            BusinessPlanMetric(label: "Price", value: "$1.99", systemImage: "dollarsign.circle.fill", tint: .green),
            BusinessPlanMetric(label: "Habit", value: "Daily", systemImage: "checklist.checked", tint: .indigo),
            BusinessPlanMetric(label: "Core value", value: "Trends", systemImage: "chart.xyaxis.line", tint: .purple)
        ],
        sections: [
            BusinessPlanSection(
                title: "Offer",
                rows: [
                    BusinessPlanRow(title: "Baseline month", body: "The free trial collects enough sleep, focus, voice, and HealthKit data to make trend feedback feel personal.", systemImage: "calendar", tint: .teal),
                    BusinessPlanRow(title: "Daily assessments", body: "Short check-ins create the product habit and make wellness changes visible.", systemImage: "waveform.path.ecg", tint: .indigo),
                    BusinessPlanRow(title: "Intervention insights", body: "Users compare days with alcohol, gym, morning routines, or custom tags against their baseline.", systemImage: "sparkles", tint: .orange)
                ]
            ),
            BusinessPlanSection(
                title: "Conversion Moments",
                rows: [
                    BusinessPlanRow(title: "Baseline complete", body: "Ask for subscription when the user has a personal before-and-after graph to protect.", systemImage: "flag.checkered", tint: .green),
                    BusinessPlanRow(title: "Weekly recap", body: "Show the top driver of wellness change and one suggested experiment for the next week.", systemImage: "doc.text.magnifyingglass", tint: .purple),
                    BusinessPlanRow(title: "School bridge", body: "Offer optional export or school pilot enrollment for users in partner institutions.", systemImage: "arrow.triangle.branch", tint: .blue)
                ]
            ),
            BusinessPlanSection(
                title: "Guardrails",
                rows: [
                    BusinessPlanRow(title: "Not diagnosis", body: "Position the app as wellness tracking and risk awareness, not clinical mental health diagnosis.", systemImage: "cross.case.fill", tint: .red),
                    BusinessPlanRow(title: "User control", body: "Make sharing opt-in and explain what data leaves the device before any school workflow.", systemImage: "hand.raised.fill", tint: .gray),
                    BusinessPlanRow(title: "Retention metric", body: "Track weekly active assessments and baseline completion before optimizing price.", systemImage: "chart.bar.xaxis", tint: .green)
                ]
            )
        ]
    )
}

private struct BusinessPlanMetric: Identifiable {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var id: String { label }
}

private struct BusinessPlanSection: Identifiable {
    let title: String
    let rows: [BusinessPlanRow]

    var id: String { title }
}

private struct BusinessPlanRow: Identifiable {
    let title: String
    let body: String
    let systemImage: String
    let tint: Color

    var id: String { title }
}
