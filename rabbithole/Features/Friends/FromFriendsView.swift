import SwiftUI

/// "Od přátel" tab: what friends saved or shared, conversations, and friend management.
struct FromFriendsView: View {
    @Environment(AuthService.self) private var auth
    @State private var showsSignIn = false

    var body: some View {
        NavigationStack {
            Group {
                if let friends = auth.friendsService, let sharing = auth.sharingService {
                    SignedInContent(friends: friends, sharing: sharing)
                } else {
                    ContentUnavailableView {
                        Label("Od přátel", systemImage: "person.2")
                    } description: {
                        Text("Přihlas se, přidej si přátele a posílejte si zajímavé články.")
                    } actions: {
                        Button("Přihlásit se") { showsSignIn = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Od přátel")
            .background(Theme.screenBackground)
        }
        .sheet(isPresented: $showsSignIn) { SignInView() }
    }
}

private struct SignedInContent: View {
    enum Section: Hashable {
        case activity, conversations
    }

    let sharing: SharingService
    @Environment(AuthService.self) private var auth
    @State private var friendsModel: FriendsViewModel
    @State private var section: Section = .activity
    @State private var feed: PagedList<FriendActivity>
    @State private var threads: PagedList<ShareThread>

    init(friends: FriendsService, sharing: SharingService) {
        self.sharing = sharing
        _friendsModel = State(initialValue: FriendsViewModel(service: friends))
        _feed = State(initialValue: PagedList { try await sharing.activity(page: $0) })
        _threads = State(initialValue: PagedList { try await sharing.threads(page: $0) })
    }

    var body: some View {
        List {
            Picker("Zobrazit", selection: $section) {
                Text("Aktivita").tag(Section.activity)
                Text("Konverzace").tag(Section.conversations)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch section {
            case .activity: activityRows
            case .conversations: conversationRows
            }
        }
        .refreshable {
            await friendsModel.load()
            await feed.reload()
            await threads.reload()
        }
        .task {
            await friendsModel.load()
            await feed.loadFirstPageIfNeeded()
            await threads.loadFirstPageIfNeeded()
        }
        .navigationDestination(for: UUID.self) { shareID in
            ChatView(viewModel: ChatViewModel(shareID: shareID, service: sharing, friends: friendsModel.service,
                                              challenges: auth.challengeService))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    FriendsView(viewModel: friendsModel)
                } label: {
                    Label("Přátelé", systemImage: "person.2")
                }
                .badge(friendsModel.pendingIncomingCount)
            }
        }
    }

    @ViewBuilder private var activityRows: some View {
        if feed.isLoaded, feed.items.isEmpty {
            Text("Zatím tu nic není. Tady uvidíš články, které ti přátelé pošlou nebo si uloží (pokud to mají povolené).")
                .foregroundStyle(.secondary)
        }
        ForEach(feed.items) { item in
            Group {
                if let shareID = item.shareID {
                    NavigationLink(value: shareID) { ActivityRow(item: item) }
                } else {
                    NavigationLink {
                        ArticleDetailScreen(article: item.article, topicID: "")
                    } label: {
                        ActivityRow(item: item)
                    }
                }
            }
            .task { if item == feed.items.last { await feed.loadNextPage() } }
        }
        if feed.failed {
            Button("Zkusit znovu") { Task { await feed.reload() } }
        }
    }

    @ViewBuilder private var conversationRows: some View {
        if threads.isLoaded, threads.items.isEmpty {
            Text("Zatím žádné konverzace. Pošli někomu článek tlačítkem „Poslat příteli“ ve čtečce.")
                .foregroundStyle(.secondary)
        }
        ForEach(threads.items) { thread in
            NavigationLink(value: thread.id) {
                ThreadRow(thread: thread, me: sharing.me)
            }
            .task { if thread == threads.items.last { await threads.loadNextPage() } }
        }
        if threads.failed {
            Button("Zkusit znovu") { Task { await threads.reload() } }
        }
    }
}

private struct ActivityRow: View {
    let item: FriendActivity
    @Environment(AuthService.self) private var auth
    private var showsChallenges: Bool { auth.challengeService != nil }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .shared ? "paperplane" : "bookmark")
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.readingTitle(.headline))
                Text(item.kind == .shared ? "Poslal(a) ti \(item.nickname)" : "Uložil(a) si \(item.nickname)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if showsChallenges, let question = item.challengeQuestion, item.challengeAnswered == false {
                    Label("\(item.nickname) tě vyzývá: \(question)", systemImage: "questionmark.bubble")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ThreadRow: View {
    let thread: ShareThread
    let me: UUID

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(thread.isUnread(for: me) ? Color.accentColor : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.other(than: me)?.nickname ?? String(localized: "Smazaný uživatel"))
                    .font(.headline)
                Text(thread.title)
                    .font(.readingTitle(.subheadline))
                if let last = thread.lastMessage {
                    Text(last.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(thread.isUnread(for: me) ? Text("Nepřečteno") : Text(verbatim: ""))
    }
}

/// Page-by-page loading for list screens (free tier: small requests, only on demand).
@Observable
final class PagedList<Item: Identifiable & Sendable> {
    private(set) var items: [Item] = []
    private(set) var isLoaded = false
    private(set) var failed = false
    private var nextPage = 0
    private var hasMore = true
    private var isLoading = false
    private let fetch: (Int) async throws -> [Item]

    init(fetch: @escaping (Int) async throws -> [Item]) {
        self.fetch = fetch
    }

    func loadFirstPageIfNeeded() async {
        if !isLoaded { await reload() }
    }

    func reload() async {
        nextPage = 0
        hasMore = true
        items = []
        await loadNextPage()
    }

    func loadNextPage() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false; isLoaded = true }
        do {
            let page = try await fetch(nextPage)
            let known = Set(items.map(\.id))
            items += page.filter { !known.contains($0.id) }
            hasMore = page.count == SharingService.pageSize
            nextPage += 1
            failed = false
        } catch {
            failed = true
        }
    }
}
