import Foundation
@testable import rabbithole

/// In-memory Wikipedia with a fixed category tree. Records every category request.
nonisolated final class FakeWikipediaService: WikipediaService, @unchecked Sendable {
    struct Category {
        var articles: [ArticleReference] = []
        var subcategories: [String] = []
        /// When set, `articles` are split into two pages.
        var paginated = false
    }

    private let lock = NSLock()
    private var _requestedCategories: [String] = []
    var categories: [String: Category]
    var summaries: [String: ArticleSummary] = [:]
    var error: Error?
    /// When set, unknown categories return this many generated articles (unique per category),
    /// and their summaries are generated too.
    var generatedArticlesPerCategory: Int?
    private var generated: [String: Int] = [:]

    init(categories: [String: Category] = [:]) {
        self.categories = categories
    }

    var requestedCategories: [String] {
        lock.withLock { _requestedCategories }
    }

    func summary(title: String) async throws -> ArticleSummary {
        if let error { throw error }
        if let summary = summaries[title] { return summary }
        if let pageID = lock.withLock({ generated[title] }) { return makeSummary(pageID: pageID, title: title) }
        throw WikipediaError.notFound
    }

    func categoryMembers(category: String, continuation: String?) async throws -> WikipediaParser.CategoryPage {
        lock.withLock { _requestedCategories.append(category) }
        if let error { throw error }
        if categories[category] == nil, let count = generatedArticlesPerCategory {
            let base = abs(category.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % 1_000_000 * 1000
            let articles = (1...count).map { ArticleReference(pageID: base + $0, title: "\(category) \($0)") }
            lock.withLock { for article in articles { generated[article.title] = article.pageID } }
            return .init(articles: articles, subcategories: [], continuation: nil)
        }
        let node = categories[category] ?? Category()
        guard node.paginated else {
            return .init(articles: node.articles, subcategories: node.subcategories, continuation: nil)
        }
        let half = node.articles.count / 2
        return continuation == nil
            ? .init(articles: Array(node.articles[..<half]), subcategories: node.subcategories, continuation: "next")
            : .init(articles: Array(node.articles[half...]), subcategories: [], continuation: nil)
    }

    func content(title: String) async throws -> ArticleContent {
        if let error { throw error }
        return ArticleContent(title: title, sections: [])
    }
}

nonisolated final class InMemoryPoolPersistence: PoolPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var pools: [String: TopicPool] = [:]

    func load(topicID: String) -> TopicPool? {
        lock.withLock { pools[topicID] }
    }

    func save(_ pool: TopicPool, topicID: String) {
        lock.withLock { pools[topicID] = pool }
    }
}

nonisolated func refs(_ ids: ClosedRange<Int>, prefix: String = "Článek") -> [ArticleReference] {
    ids.map { ArticleReference(pageID: $0, title: "\(prefix) \($0)") }
}

nonisolated func makeSummary(pageID: Int, title: String, extractLength: Int = 300, type: ArticleSummary.PageType = .standard) -> ArticleSummary {
    ArticleSummary(
        pageID: pageID, title: title, extract: String(repeating: "a", count: extractLength),
        description: nil, type: type, articleURL: WikipediaURLs.article(title: title),
        thumbnailURL: nil, imageFileTitle: nil
    )
}
