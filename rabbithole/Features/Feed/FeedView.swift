import SwiftUI

struct FeedView: View {
    @State var viewModel: FeedViewModel
    @AppStorage(SettingsKey.topicsVersion) private var topicsVersion = 0

    var body: some View {
        NavigationStack {
            content
                .background(Theme.screenBackground)
                .navigationTitle("Objevuj")
                .navigationDestination(for: FeedCard.self) { card in
                    ArticleDetailScreen(article: card.article, topicID: card.topicID)
                }
                // Also fires when returning from the reader, which can change saved state.
                .onAppear { viewModel.refreshSavedState() }
        }
        .task { await viewModel.start() }
        .onChange(of: topicsVersion) {
            Task { await viewModel.topicsChanged() }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            ProgressView("Hledám zajímavé články…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let isOffline):
            ContentUnavailableView {
                Label(isOffline ? "Bez připojení" : "Něco se pokazilo",
                      systemImage: isOffline ? "wifi.slash" : "exclamationmark.triangle")
            } description: {
                Text(isOffline
                     ? "Články se načítají z Wikipedie. Zkontroluj připojení k internetu a zkus to znovu."
                     : "Články se nepodařilo načíst. Zkus to prosím za chvíli znovu.")
            } actions: {
                retryButton
            }
        case .empty:
            ContentUnavailableView {
                Label("Žádné články", systemImage: "tray")
            } description: {
                Text("Pro vybraná témata jsme nenašli nic nového. Zkus v nastavení přidat další témata.")
            } actions: {
                retryButton
            }
        case .loaded:
            feed
        }
    }

    private var retryButton: some View {
        Button("Zkusit znovu") {
            Task { await viewModel.reload() }
        }
        .buttonStyle(.borderedProminent)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(viewModel.items) { item in
                    row(for: item)
                        .task { await viewModel.cardAppeared(item) }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
                footer
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: Theme.readingWidth)
            .frame(maxWidth: .infinity)
            .animation(.default, value: viewModel.items)
        }
        .refreshable { await viewModel.reload() }
    }

    @ViewBuilder private func row(for item: FeedItem) -> some View {
        switch item {
        case .article(let card):
            ArticleCardView(
                card: card,
                isSaved: viewModel.savedIDs.contains(card.id),
                onToggleSave: { viewModel.toggleSaved(card) },
                onNotInterested: { viewModel.notInterested(card) }
            )
        case .readingBreak(_, let count):
            ReadingBreakCardView(count: count) {
                viewModel.dismissBreak(item)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if viewModel.loadMoreFailed {
            VStack(spacing: 8) {
                Text("Další články se nepodařilo načíst.")
                    .foregroundStyle(.secondary)
                Button("Zkusit znovu") {
                    Task { await viewModel.loadMore() }
                }
            }
            .padding()
        } else if viewModel.isLoadingMore {
            ProgressView()
                .padding()
        }
    }
}
