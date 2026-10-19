import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        #if DEBUG
        if let article = Self.demoArticle {
            NavigationStack { ArticleDetailScreen(article: article, topicID: "space") }
        } else if let video = Self.demoVideo {
            NavigationStack { VideoDetailView(card: VideoCard(video: video, topicID: "space", isExploration: false)) }
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

    /// `-demoVideo M7lc1UVf-VE` opens the player directly (needs no API key) – for simulator checks.
    private static var demoVideo: YouTubeVideo? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoVideo"), index + 1 < arguments.count else { return nil }
        return YouTubeVideo(id: arguments[index + 1], title: "Ukázkové video", channelTitle: "YouTube",
                            duration: 300, thumbnailURL: nil, fetchedAt: .now)
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
    @Environment(AuthService.self) private var auth
    @AppStorage(SettingsKey.topicsVersion) private var topicsVersion = 0
    @State private var selectedTab = MainTabView.initialTab
    @State private var friendsBadge = 0
    @Environment(\.scenePhase) private var scenePhase

    enum Tab: String {
        case feed, search, friends, saved, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(viewModel: FeedViewModel(
                services: services,
                topics: TopicPreferencesRepository(context: modelContext),
                seen: SeenArticlesRepository(context: modelContext),
                saved: SavedArticlesRepository(context: modelContext),
                seenVideos: SeenVideosRepository(context: modelContext),
                savedVideos: SavedVideosRepository(context: modelContext),
                breakInterval: { Self.integer(SettingsKey.breakInterval, default: AppConfig.defaultBreakInterval) },
                videoInterval: { Self.integer(SettingsKey.videoInterval, default: FeedSlotPlanner.defaultVideoInterval) }
            ))
            .tabItem { Label("Objevuj", systemImage: "rectangle.stack") }
            .tag(Tab.feed)
            SearchView()
                .tabItem { Label("Hledat", systemImage: "magnifyingglass") }
                .tag(Tab.search)
            if auth.state != .unavailable {
                FromFriendsView()
                    .tabItem { Label("Od přátel", systemImage: "person.2") }
                    .tag(Tab.friends)
                    .badge(friendsBadge)
            }
            SavedArticlesView()
                .tabItem { Label("Uložené", systemImage: "bookmark") }
                .tag(Tab.saved)
            SettingsView()
                .tabItem { Label("Nastavení", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .fullScreenCover(isPresented: .constant(needsProfile)) {
            ProfileSetupView()
        }
        .task(id: BadgeTrigger(phase: scenePhase, tab: selectedTab, signedIn: auth.profile?.id)) {
            friendsBadge = await auth.activityBadgeCount()
        }
        .onChange(of: topicsVersion) {
            let topics = TopicPreferencesRepository(context: modelContext).selectedTopicIDs()
            Task { try? await auth.syncTopics(topics) }
        }
    }

    /// Re-count the badge when the app becomes active, the tab changes or the account changes.
    private struct BadgeTrigger: Equatable {
        let phase: ScenePhase
        let tab: Tab
        let signedIn: UUID?
    }

    /// `integer(forKey:)` also accepts string values, e.g. from `-videoInterval 1` launch arguments.
    private static func integer(_ key: String, default defaultValue: Int) -> Int {
        UserDefaults.standard.object(forKey: key) == nil ? defaultValue : UserDefaults.standard.integer(forKey: key)
    }

    /// DEBUG: `-demoTab settings` opens a tab directly – used for simulator screenshots.
    private static var initialTab: Tab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-demoTab"), index + 1 < arguments.count,
           let tab = Tab(rawValue: arguments[index + 1]) {
            return tab
        }
        #endif
        return .feed
    }

    private var needsProfile: Bool {
        if case .needsProfile = auth.state { true } else { false }
    }
}

#Preview {
    RootView()
        .environment(AuthService(client: nil))
        .modelContainer(for: PersistentSchema.models, inMemory: true)
}
