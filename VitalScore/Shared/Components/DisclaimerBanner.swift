import SwiftUI

struct DisclaimerBanner: View {
    static let text = """
    VitalScore is designed for personal wellness tracking and lifestyle experiment reflection. \
    It is not a medical device and does not diagnose, treat, prevent, or cure any disease. \
    Trends shown in the app are based on available data and may be incomplete or noisy. \
    If you have concerning symptoms, consult a qualified healthcare professional.
    """

    var body: some View {
        Text(Self.text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(10)
    }
}
