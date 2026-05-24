import SwiftUI

struct ContentView: View {
    @EnvironmentObject var storage: LocalStorageManager

    var body: some View {
        HealthDashboardView()
            .onAppear {
                storage.hasCompletedOnboarding = true
            }
    }
}
