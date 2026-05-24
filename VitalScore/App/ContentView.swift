import SwiftUI

struct ContentView: View {
    @EnvironmentObject var storage: LocalStorageManager
    @EnvironmentObject var healthKit: HealthKitManager

    @State private var onboardingComplete: Bool = false
    @State private var permissionComplete: Bool = false

    var body: some View {
        Group {
            if !onboardingComplete {
                OnboardingView {
                    storage.hasCompletedOnboarding = true
                    onboardingComplete = true
                }
            } else if !permissionComplete && !healthKit.hasRequestedAuthorization {
                HealthPermissionView {
                    permissionComplete = true
                }
            } else {
                HealthDashboardView()
            }
        }
        .onAppear {
            onboardingComplete = storage.hasCompletedOnboarding
            permissionComplete = healthKit.hasRequestedAuthorization
        }
    }
}
