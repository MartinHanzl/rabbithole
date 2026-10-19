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
            #if DEBUG
            .task { skipOnboardingIfRequested() }
            #endif
        }
    }

    #if DEBUG
    /// `-demoTopics space,history,biology` preselects topics – used for simulator screenshots.
    private func skipOnboardingIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoTopics"), index + 1 < arguments.count else { return }
        let ids = Set(arguments[index + 1].split(separator: ",").map(String.init))
        TopicPreferencesRepository(context: modelContext).setSelected(ids)
        hasCompletedOnboarding = true
    }
    #endif
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.services) private var services

    var body: some View {
        TabView {
            FeedView(viewModel: FeedViewModel(
                services: services,
                topics: TopicPreferencesRepository(context: modelContext),
                seen: SeenArticlesRepository(context: modelContext),
                saved: SavedArticlesRepository(context: modelContext),
                breakInterval: {
                    UserDefaults.standard.object(forKey: SettingsKey.breakInterval) as? Int ?? AppConfig.defaultBreakInterval
                }
            ))
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
