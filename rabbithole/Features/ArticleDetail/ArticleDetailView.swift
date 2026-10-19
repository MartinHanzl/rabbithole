import SwiftData
import SwiftUI

/// Builds the reader with dependencies from the environment.
struct ArticleDetailScreen: View {
    let article: ArticleSummary
    let topicID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.services) private var services

    var body: some View {
        ArticleDetailView(viewModel: ArticleDetailViewModel(
            article: article,
            topicID: topicID,
            services: services,
            saved: SavedArticlesRepository(context: modelContext),
            topics: TopicPreferencesRepository(context: modelContext)
        ))
    }
}

/// Native, reading-focused rendering of the full article text.
struct ArticleDetailView: View {
    @State var viewModel: ArticleDetailViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthService.self) private var auth
    @State private var showsShareToFriend = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ArticleImage(article: viewModel.article, height: 260)

                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: Theme.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if auth.sharingService != nil {
                    Button {
                        showsShareToFriend = true
                    } label: {
                        Label("Poslat příteli", systemImage: "paperplane")
                    }
                }
                ShareLink(item: viewModel.article.articleURL) {
                    Label("Sdílet", systemImage: "square.and.arrow.up")
                }
                Button {
                    viewModel.toggleSaved()
                } label: {
                    Label(viewModel.isSaved ? "Odebrat z uložených" : "Uložit",
                          systemImage: viewModel.isSaved ? "bookmark.fill" : "bookmark")
                }
                .sensoryFeedback(.selection, trigger: viewModel.isSaved)
            }
        }
        .sheet(isPresented: $showsShareToFriend) {
            if let sharing = auth.sharingService, let friends = auth.friendsService {
                ShareToFriendView(article: viewModel.article, sharing: sharing, friends: friends,
                                  challenges: auth.challengeService)
            }
        }
        .task { await viewModel.load() }
        .onAppear { viewModel.didAppear() }
        .onDisappear { viewModel.didDisappear() }
        .onChange(of: scenePhase) { _, phase in
            // Time in the background isn't reading.
            if phase == .active { viewModel.didAppear() } else { viewModel.didDisappear() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            TopicLabel(topicID: viewModel.topicID)
            Text(viewModel.article.title)
                .font(.readingTitle(.largeTitle))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            AttributionView(articleURL: viewModel.article.articleURL, imageLicenseURL: viewModel.article.imageLicenseURL)
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.phase {
        case .loading:
            paragraph(viewModel.article.extract)
            ProgressView()
                .frame(maxWidth: .infinity)
        case .loaded(let content):
            ForEach(content.sections) { section in
                SectionView(section: section, paragraph: paragraph)
            }
        case .failed(let isOffline):
            paragraph(viewModel.article.extract)
            VStack(alignment: .leading, spacing: 8) {
                Label(isOffline ? "Bez připojení se zobrazuje jen úvod článku." : "Celý článek se nepodařilo načíst.",
                      systemImage: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Zkusit znovu") {
                    Task { await viewModel.load() }
                }
            }
            .font(.callout)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.screenBackground, in: .rect(cornerRadius: 12))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Link(destination: viewModel.article.articleURL) {
                Label("Otevřít původní článek na Wikipedii", systemImage: "safari")
            }
            Text("Text pochází z české Wikipedie a je dostupný pod licencí Creative Commons Uveďte původ – Zachovejte licenci 4.0. Zobrazení je zjednodušené – tabulky, vzorce a obrázky v textu najdeš v původním článku.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.readingBody)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct SectionView<Paragraph: View>: View {
    let section: ArticleSection
    let paragraph: (String) -> Paragraph

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = section.title {
                Text(title)
                    .font(.readingTitle(section.level <= 2 ? .title2 : .title3))
                    .padding(.top, section.level <= 2 ? 12 : 4)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, text in
                paragraph(text)
            }
        }
    }
}
