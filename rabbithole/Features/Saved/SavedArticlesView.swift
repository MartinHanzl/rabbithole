import SwiftData
import SwiftUI

struct SavedArticlesView: View {
    @Query(sort: \SavedArticle.savedAt, order: .reverse) private var articles: [SavedArticle]
    @Query(sort: \SavedVideo.savedAt, order: .reverse) private var videos: [SavedVideo]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.services) private var services

    private enum Row: Identifiable {
        case article(SavedArticle)
        case video(SavedVideo)

        var id: String {
            switch self {
            case .article(let article): "a\(article.pageID)"
            case .video(let video): "v\(video.videoID)"
            }
        }

        var savedAt: Date {
            switch self {
            case .article(let article): article.savedAt
            case .video(let video): video.savedAt
            }
        }
    }

    private var rows: [Row] {
        (articles.map(Row.article) + videos.map(Row.video)).sorted { $0.savedAt > $1.savedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label("Zatím nic uloženého", systemImage: "bookmark")
                    } description: {
                        Text("Články a videa, které si ve feedu uložíš, najdeš tady. Články i bez připojení.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Uložené")
            .navigationDestination(for: SavedArticle.self) { saved in
                ArticleDetailScreen(article: saved.summary, topicID: saved.topicID)
            }
            .navigationDestination(for: SavedVideo.self) { saved in
                VideoDetailView(card: VideoCard(video: saved.video, topicID: saved.topicID, isExploration: false)) {
                    SavedVideosRepository(context: modelContext).remove(videoID: saved.videoID)
                }
            }
        }
        .task {
            // YouTube API Developer Policies: keep stored video metadata fresh (≤ 30 days).
            guard let youTube = services.youTube else { return }
            await SavedVideosRepository(context: modelContext).refreshStale(using: youTube)
        }
    }

    private var list: some View {
        List {
            ForEach(rows) { row in
                Group {
                    switch row {
                    case .article(let article):
                        NavigationLink(value: article) { SavedArticleRow(article: article) }
                    case .video(let video):
                        NavigationLink(value: video) { SavedVideoRow(video: video) }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        remove(row)
                    } label: {
                        Label("Odebrat", systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                let current = rows
                offsets.map { current[$0] }.forEach(remove)
            }
        }
        .toolbar { EditButton() }
    }

    private func remove(_ row: Row) {
        switch row {
        case .article(let article):
            SavedArticlesRepository(context: modelContext).remove(pageID: article.pageID)
        case .video(let video):
            SavedVideosRepository(context: modelContext).remove(videoID: video.videoID)
        }
    }
}

private struct SavedVideoRow: View {
    let video: SavedVideo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TopicLabel(topicID: video.topicID)
                Text(video.title)
                    .font(.readingTitle(.headline))
                Label("\(video.channelTitle) · \(video.video.formattedDuration)", systemImage: "play.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VideoThumbnail(video: video.video)
                .frame(width: 96)
                .clipShape(.rect(cornerRadius: 8))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
    }
}

private struct SavedArticleRow: View {
    let article: SavedArticle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TopicLabel(topicID: article.topicID)
                Text(article.title)
                    .font(.readingTitle(.headline))
                Text(article.extract)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let url = article.thumbnailURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }
}
