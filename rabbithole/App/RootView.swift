import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView(
                viewModel: OnboardingViewModel(repository: TopicPreferencesRepository(context: modelContext)),
                onFinish: { hasCompletedOnboarding = true }
            )
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Text("Feed")
                .tabItem { Label("Objevuj", systemImage: "rectangle.stack") }
            Text("Uložené")
                .tabItem { Label("Uložené", systemImage: "bookmark") }
            Text("Nastavení")
                .tabItem { Label("Nastavení", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: PersistentSchema.models, inMemory: true)
}
