import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        #if DEBUG
        if let article = Self.demoArticle {
            NavigationStack { ArticleDetailScreen(article: article, topicID: "space") }
        } else {
            content
        }
        #else
        content
        #endif
    }

    @ViewBuilder private var content: some View {
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
    /// `-demoArticle "Mars (planeta)"` opens the reader directly – used for simulator screenshots.
    private static var demoArticle: ArticleSummary? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoArticle"), index + 1 < arguments.count else { return nil }
        let title = arguments[index + 1]
        return ArticleSummary(
            pageID: -1, title: title, extract: "", description: nil, type: .standard,
            articleURL: WikipediaURLs.article(title: title), thumbnailURL: nil, imageFileTitle: nil
        )
    }

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
            SavedArticlesView()
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
