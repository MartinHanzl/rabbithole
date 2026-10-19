import Foundation
import SwiftData

/// Remembers which articles were already shown so the feed never repeats them.
final class SeenArticlesRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allIDs() -> Set<Int> {
        let rows = (try? context.fetch(FetchDescriptor<SeenArticle>())) ?? []
        return Set(rows.map(\.pageID))
    }

    func markSeen(_ pageID: Int) {
        context.insert(SeenArticle(pageID: pageID))
        try? context.save()
    }

    func removeAll() {
        try? context.delete(model: SeenArticle.self)
        try? context.save()
    }
}

/// Posted when an article is saved or removed locally (object: `SavedArticleChange`).
extension Notification.Name {
    static let savedArticleChanged = Notification.Name("savedArticleChanged")
}

enum SavedArticleChange {
    case saved(ArticleSummary, Date)
    case removed(pageID: Int)
}

final class SavedArticlesRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() -> [SavedArticle] {
        (try? context.fetch(FetchDescriptor<SavedArticle>())) ?? []
    }

    func savedIDs() -> Set<Int> {
        let rows = (try? context.fetch(FetchDescriptor<SavedArticle>())) ?? []
        return Set(rows.map(\.pageID))
    }

    func save(_ article: ArticleSummary, topicID: String) {
        context.insert(SavedArticle(
            pageID: article.pageID,
            title: article.title,
            extract: article.extract,
            topicID: topicID,
            articleURL: article.articleURL,
            thumbnailURL: article.thumbnailURL,
            imageFileTitle: article.imageFileTitle
        ))
        try? context.save()
        NotificationCenter.default.post(name: .savedArticleChanged, object: SavedArticleChange.saved(article, .now))
    }

    func remove(pageID: Int) {
        try? context.delete(model: SavedArticle.self, where: #Predicate { $0.pageID == pageID })
        try? context.save()
        NotificationCenter.default.post(name: .savedArticleChanged, object: SavedArticleChange.removed(pageID: pageID))
    }
}

extension SavedArticle {
    /// Rebuilds a summary so saved articles open in the same reader as feed cards.
    var summary: ArticleSummary {
        ArticleSummary(
            pageID: pageID, title: title, extract: extract, description: nil, type: .standard,
            articleURL: articleURL, thumbnailURL: thumbnailURL, imageFileTitle: imageFileTitle
        )
    }
}

final class SeenVideosRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allIDs() -> Set<String> {
        let rows = (try? context.fetch(FetchDescriptor<SeenVideo>())) ?? []
        return Set(rows.map(\.videoID))
    }

    func markSeen(_ videoID: String) {
        context.insert(SeenVideo(videoID: videoID))
        try? context.save()
    }

    func removeAll() {
        try? context.delete(model: SeenVideo.self)
        try? context.save()
    }
}

final class SavedVideosRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func savedIDs() -> Set<String> {
        let rows = (try? context.fetch(FetchDescriptor<SavedVideo>())) ?? []
        return Set(rows.map(\.videoID))
    }

    func save(_ video: YouTubeVideo, topicID: String) {
        context.insert(SavedVideo(video: video, topicID: topicID))
        try? context.save()
    }

    func remove(videoID: String) {
        try? context.delete(model: SavedVideo.self, where: #Predicate { $0.videoID == videoID })
        try? context.save()
    }

    /// Refreshes saved videos whose metadata is older than `refreshAfter` (YouTube API Developer
    /// Policies: refresh or delete within 30 days). Videos the API no longer returns, or that are
    /// no longer playable, are removed; if refreshing fails, rows past the 30-day limit are removed.
    func refreshStale(using service: any YouTubeService, now: Date = .now, refreshAfter: TimeInterval = 7 * 24 * 3600) async {
        let rows = (try? context.fetch(FetchDescriptor<SavedVideo>())) ?? []
        let stale = rows.filter { now.timeIntervalSince($0.metadataFetchedAt) > refreshAfter }
        guard !stale.isEmpty else { return }
        do {
            let result = try await service.videos(ids: stale.map(\.videoID))
            let playable = Dictionary(result.playable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for row in stale {
                if let video = playable[row.videoID] {
                    row.title = video.title
                    row.channelTitle = video.channelTitle
                    row.duration = video.duration
                    row.thumbnailURL = video.thumbnailURL
                    row.metadataFetchedAt = video.fetchedAt
                } else {
                    context.delete(row)
                }
            }
        } catch {
            for row in stale where now.timeIntervalSince(row.metadataFetchedAt) > YouTubeConfiguration.maxDataAge {
                context.delete(row)
            }
        }
        try? context.save()
    }
}
