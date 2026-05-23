import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("VitalScore")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Turn Apple Health data into personal lifestyle experiments. Combine sleep, heart, activity, and focus signals into a Wellness Delta Score against your own baseline.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            DisclaimerBanner()
                .padding(.horizontal)
            Spacer()
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}
