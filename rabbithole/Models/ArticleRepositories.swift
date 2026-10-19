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

final class SavedArticlesRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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
    }

    func remove(pageID: Int) {
        try? context.delete(model: SavedArticle.self, where: #Predicate { $0.pageID == pageID })
        try? context.save()
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
