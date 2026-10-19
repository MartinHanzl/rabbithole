import SwiftUI

/// "Hledat": articles and videos for a question. Searches on submit only, so typing doesn't
/// spend the YouTube quota.
struct SearchView: View {
    @Environment(\.services) private var services
    @State private var query = ""
    @State private var phase: Phase = .idle
    @State private var remainingVideoSearches: Int?
    @State private var showsAllArticles = false
    private let collapsedArticleCount = 5
    @AppStorage("recentSearches") private var recentData = Data()

    private enum Phase {
        case idle
        case searching(String)
        case results(SearchResults)
    }

    private static let examples = ["jak funguje kapitalismus", "proč je nebe modré", "co je černá díra"]

    var body: some View {
        NavigationStack {
            List {
                switch phase {
                case .idle:
                    suggestions
                case .searching(let text):
                    HStack {
                        ProgressView()
                        Text("Hledám „\(text)“…").foregroundStyle(.secondary)
                    }
                case .results(let results):
                    resultSections(results)
                }
            }
            .navigationTitle("Hledat")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Na co jsi zvědavý?")
            .onSubmit(of: .search) { run(query) }
            .onChange(of: query) { _, text in
                if text.isEmpty { phase = .idle }
            }
            .navigationDestination(for: ArticleSummary.self) { article in
                ArticleDetailScreen(article: article, topicID: "")
            }
            .navigationDestination(for: YouTubeVideo.self) { video in
                VideoDetailView(card: VideoCard(video: video, topicID: "", isExploration: false))
            }
            .task {
                remainingVideoSearches = await services.search.remainingVideoSearches
                #if DEBUG
                // `-demoSearch "jak funguje kapitalismus"` runs a search right away (simulator checks).
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-demoSearch"), index + 1 < arguments.count, query.isEmpty {
                    query = arguments[index + 1]
                    run(query)
                }
                #endif
            }
        }
    }

    // MARK: Idle

    @ViewBuilder private var suggestions: some View {
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { text in
                    Button {
                        query = text
                        run(text)
                    } label: {
                        Label(text, systemImage: "clock.arrow.circlepath")
                    }
                }
                Button("Smazat historii hledání", role: .destructive) { recent = [] }
                    .font(.footnote)
            } header: {
                Text("Naposledy")
            }
        }
        Section {
            ForEach(Self.examples, id: \.self) { text in
                Button {
                    query = text
                    run(text)
                } label: {
                    Label(text, systemImage: "sparkle.magnifyingglass")
                }
            }
        } header: {
            Text("Zkus třeba")
        } footer: {
            Text("Ptej se celou větou – najdeme články z Wikipedie a vysvětlující videa z YouTube.")
        }
    }

    // MARK: Results

    @ViewBuilder private func resultSections(_ results: SearchResults) -> some View {
        Section {
            if results.articlesFailed {
                Label("Články se nepodařilo načíst. Zkontroluj připojení.", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            } else if results.articles.isEmpty {
                Text("Žádné články.").foregroundStyle(.secondary)
            }
            ForEach(showsAllArticles ? results.articles : Array(results.articles.prefix(collapsedArticleCount))) { article in
                NavigationLink(value: article) { ArticleResultRow(article: article) }
            }
            if !showsAllArticles, results.articles.count > collapsedArticleCount {
                Button("Zobrazit všechny články (\(results.articles.count))") { showsAllArticles = true }
            }
        } header: {
            Text("Články")
        } footer: {
            if results.terms.wikipedia.lowercased() != query.trimmingCharacters(in: .whitespaces).lowercased() {
                Text("Na Wikipedii hledáno jako „\(results.terms.wikipedia)“.")
            }
        }

        Section {
            switch results.videoStatus {
            case .unavailable:
                Text("Videa nejsou v této verzi k dispozici.").foregroundStyle(.secondary)
            case .dailyLimitReached:
                Text("Dnešní limit hledání videí je vyčerpaný. Zítra to půjde znovu – články hledat můžeš dál.")
                    .foregroundStyle(.secondary)
            case .failed:
                Text("Videa se nepodařilo načíst.").foregroundStyle(.secondary)
            case .found where results.videos.isEmpty:
                Text("Žádná videa.").foregroundStyle(.secondary)
            case .found:
                ForEach(results.videos) { video in
                    NavigationLink(value: video) { VideoResultRow(video: video) }
                }
            }
        } header: {
            Text("Videa z YouTube")
        } footer: {
            if let remainingVideoSearches, results.videoStatus != .unavailable {
                Text("Dnes zbývá hledání videí: \(remainingVideoSearches)")
            }
        }
    }

    // MARK: Actions

    private func run(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        remember(trimmed)
        showsAllArticles = false
        phase = .searching(trimmed)
        Task {
            let results = await services.search.search(trimmed)
            remainingVideoSearches = await services.search.remainingVideoSearches
            // Ignore results of an older query.
            if case .searching(let current) = phase, current == trimmed {
                phase = .results(results)
            }
        }
    }

    private var recent: [String] {
        get { (try? JSONDecoder().decode([String].self, from: recentData)) ?? [] }
        nonmutating set { recentData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    private func remember(_ text: String) {
        recent = Array(([text] + recent.filter { $0.lowercased() != text.lowercased() }).prefix(8))
    }
}

private struct ArticleResultRow: View {
    let article: ArticleSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title).font(.readingTitle(.headline))
                Text(article.extract)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            if let url = article.thumbnailURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct VideoResultRow: View {
    let video: YouTubeVideo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VideoThumbnail(video: video)
                .frame(width: 120)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                Text("\(video.channelTitle) · \(video.formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
