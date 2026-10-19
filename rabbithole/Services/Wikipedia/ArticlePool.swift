import Foundation

/// Crawl state for one topic: articles found so far plus categories still to visit.
nonisolated struct TopicPool: Codable, Sendable, Equatable {
    struct PendingCategory: Codable, Sendable, Equatable {
        let name: String
        let depth: Int
        var continuation: String?
    }

    /// Categories from `TopicCatalog` the pool was built from – a change invalidates the pool.
    var sourceCategories: [String]
    var entries: [ArticleReference] = []
    var pending: [PendingCategory]
    var visitedCategories: Set<String> = []
    var rejectedPageIDs: Set<Int> = []
    var createdAt: Date

    init(topic: Topic, createdAt: Date) {
        sourceCategories = topic.categories
        pending = topic.categories.map { PendingCategory(name: $0, depth: 0) }
        visitedCategories = Set(topic.categories)
        self.createdAt = createdAt
    }
}

nonisolated protocol PoolPersistence: Sendable {
    func load(topicID: String) -> TopicPool?
    func save(_ pool: TopicPool, topicID: String)
}

/// Stores pools as JSON in Caches – the system may purge them, which just triggers a re-crawl.
nonisolated struct FilePoolPersistence: PoolPersistence {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "TopicPools")
    }

    func load(topicID: String) -> TopicPool? {
        guard let data = try? Data(contentsOf: url(for: topicID)) else { return nil }
        return try? JSONDecoder().decode(TopicPool.self, from: data)
    }

    func save(_ pool: TopicPool, topicID: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(pool) else { return }
        try? data.write(to: url(for: topicID), options: .atomic)
    }

    private func url(for topicID: String) -> URL {
        directory.appending(path: "\(topicID).json")
    }
}

/// Lazily crawls a topic's categories (breadth-first, limited depth) and hands out random
/// article candidates. Crawls only as much as needed to keep a small buffer of unseen articles,
/// so the first card appears after one or two requests and the API isn't hammered.
actor ArticlePool {
    struct Configuration: Sendable {
        var maxDepth = 2
        var maxCategoriesPerTopic = 60
        var minimumAvailable = 15
        var timeToLive: TimeInterval = 7 * 24 * 3600
    }

    private let service: any WikipediaService
    private let persistence: any PoolPersistence
    private let configuration: Configuration
    private let now: @Sendable () -> Date
    private var pools: [String: TopicPool] = [:]

    init(
        service: any WikipediaService,
        persistence: any PoolPersistence,
        configuration: Configuration = .init(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.service = service
        self.persistence = persistence
        self.configuration = configuration
        self.now = now
    }

    /// A random article from the topic that isn't in `excluded`, or `nil` if the topic is exhausted.
    func randomCandidate(for topic: Topic, excluding excluded: Set<Int>) async throws -> ArticleReference? {
        var pool = loadPool(for: topic)
        var available = availableEntries(in: pool, excluding: excluded)

        while available.count < configuration.minimumAvailable, !pool.pending.isEmpty {
            try await crawlNextCategory(in: &pool)
            pools[topic.id] = pool
            available = availableEntries(in: pool, excluding: excluded)
        }
        persistence.save(pool, topicID: topic.id)
        return available.randomElement()
    }

    /// Marks an article as unsuitable (e.g. a disambiguation) so it's never fetched again.
    func reject(pageID: Int, topicID: String) {
        guard var pool = pools[topicID] else { return }
        pool.rejectedPageIDs.insert(pageID)
        pools[topicID] = pool
        persistence.save(pool, topicID: topicID)
    }

    private func availableEntries(in pool: TopicPool, excluding excluded: Set<Int>) -> [ArticleReference] {
        pool.entries.filter { !excluded.contains($0.pageID) && !pool.rejectedPageIDs.contains($0.pageID) }
    }

    private func loadPool(for topic: Topic) -> TopicPool {
        let candidate = pools[topic.id] ?? persistence.load(topicID: topic.id)
        if let candidate,
           candidate.sourceCategories == topic.categories,
           now().timeIntervalSince(candidate.createdAt) < configuration.timeToLive {
            pools[topic.id] = candidate
            return candidate
        }
        let fresh = TopicPool(topic: topic, createdAt: now())
        pools[topic.id] = fresh
        return fresh
    }

    private func crawlNextCategory(in pool: inout TopicPool) async throws {
        var category = pool.pending.removeFirst()
        let page = try await service.categoryMembers(category: category.name, continuation: category.continuation)

        let known = Set(pool.entries.map(\.pageID))
        for member in page.articles where !known.contains(member.pageID) && ArticleFilter.isCandidateTitle(member.title) {
            pool.entries.append(member)
        }

        if category.depth < configuration.maxDepth {
            for subcategory in page.subcategories.shuffled()
            where !pool.visitedCategories.contains(subcategory)
                && pool.visitedCategories.count < configuration.maxCategoriesPerTopic {
                pool.visitedCategories.insert(subcategory)
                pool.pending.append(.init(name: subcategory, depth: category.depth + 1))
            }
        }

        if let continuation = page.continuation {
            category.continuation = continuation
            pool.pending.append(category)
        }
    }
}
