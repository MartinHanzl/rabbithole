import Foundation
import Testing
@testable import rabbithole

struct ArticlePoolTests {
    private let topic = Topic(id: "space", name: "Vesmír", symbol: "sparkles", categories: ["Root"])

    private func makePool(
        _ service: FakeWikipediaService,
        persistence: InMemoryPoolPersistence = .init(),
        configuration: ArticlePool.Configuration = .init(maxDepth: 2, minimumAvailable: 1000),
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 0) }
    ) -> ArticlePool {
        ArticlePool(service: service, persistence: persistence, configuration: configuration, now: now)
    }

    @Test func crawlsSubcategoriesUpToMaxDepth() async throws {
        let service = FakeWikipediaService(categories: [
            "Root": .init(articles: refs(1...2), subcategories: ["A"]),
            "A": .init(articles: refs(3...4), subcategories: ["B"]),
            "B": .init(articles: refs(5...6), subcategories: ["C"]),
            "C": .init(articles: refs(7...8)),
        ])
        let pool = makePool(service)

        _ = try await pool.randomCandidate(for: topic, excluding: [])

        #expect(service.requestedCategories == ["Root", "A", "B"])
    }

    @Test func stopsCrawlingWhenEnoughCandidates() async throws {
        let service = FakeWikipediaService(categories: [
            "Root": .init(articles: refs(1...20), subcategories: ["A"]),
        ])
        let pool = makePool(service, configuration: .init(minimumAvailable: 10))

        _ = try await pool.randomCandidate(for: topic, excluding: [])

        #expect(service.requestedCategories == ["Root"])
    }

    @Test func excludesSeenAndListArticles() async throws {
        let service = FakeWikipediaService(categories: [
            "Root": .init(articles: refs(1...3) + [ArticleReference(pageID: 99, title: "Seznam planet")]),
        ])
        let pool = makePool(service)

        let candidate = try await pool.randomCandidate(for: topic, excluding: [1, 2])

        #expect(candidate?.pageID == 3)
    }

    @Test func returnsNilWhenExhausted() async throws {
        let service = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])
        let pool = makePool(service)

        #expect(try await pool.randomCandidate(for: topic, excluding: [1, 2]) == nil)
    }

    @Test func rejectedArticlesAreNeverReturned() async throws {
        let service = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])
        let pool = makePool(service)

        _ = try await pool.randomCandidate(for: topic, excluding: [])
        await pool.reject(pageID: 1, topicID: topic.id)

        for _ in 0..<10 {
            #expect(try await pool.randomCandidate(for: topic, excluding: [])?.pageID == 2)
        }
    }

    @Test func followsContinuation() async throws {
        let service = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...4), paginated: true)])
        let pool = makePool(service)

        let candidate = try await pool.randomCandidate(for: topic, excluding: [1, 2, 3])

        #expect(candidate?.pageID == 4)
        #expect(service.requestedCategories == ["Root", "Root"])
    }

    @Test func reusesPersistedPoolWithinTTL() async throws {
        let persistence = InMemoryPoolPersistence()
        let first = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])
        _ = try await makePool(first, persistence: persistence).randomCandidate(for: topic, excluding: [])

        let second = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])
        let candidate = try await makePool(second, persistence: persistence, now: { Date(timeIntervalSince1970: 3600) })
            .randomCandidate(for: topic, excluding: [])

        #expect(candidate != nil)
        #expect(second.requestedCategories.isEmpty)
    }

    @Test func rebuildsExpiredPool() async throws {
        let persistence = InMemoryPoolPersistence()
        let first = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])
        _ = try await makePool(first, persistence: persistence).randomCandidate(for: topic, excluding: [])

        let second = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])
        let eightDays: TimeInterval = 8 * 24 * 3600
        _ = try await makePool(second, persistence: persistence, now: { Date(timeIntervalSince1970: eightDays) })
            .randomCandidate(for: topic, excluding: [])

        #expect(second.requestedCategories == ["Root"])
    }

    @Test func rebuildsPoolWhenCatalogCategoriesChange() async throws {
        let persistence = InMemoryPoolPersistence()
        let service = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2)), "New": .init(articles: refs(3...4))])
        _ = try await makePool(service, persistence: persistence).randomCandidate(for: topic, excluding: [])

        let changed = Topic(id: "space", name: "Vesmír", symbol: "sparkles", categories: ["New"])
        let candidate = try await makePool(service, persistence: persistence).randomCandidate(for: changed, excluding: [])

        #expect([3, 4].contains(candidate?.pageID))
    }

    @Test func propagatesNetworkErrors() async {
        let service = FakeWikipediaService()
        service.error = WikipediaError.offline
        let pool = makePool(service)

        await #expect(throws: WikipediaError.offline) {
            try await pool.randomCandidate(for: topic, excluding: [])
        }
    }
}
