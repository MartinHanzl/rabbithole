import Foundation
import Testing
@testable import rabbithole

struct FeedLoaderTests {
    private let topic = Topic(id: "space", name: "Vesmír", symbol: "sparkles", categories: ["Root"])

    private func makeLoader(_ service: FakeWikipediaService) -> FeedLoader {
        FeedLoader(service: service, pool: ArticlePool(service: service, persistence: InMemoryPoolPersistence()))
    }

    @Test func skipsUnsuitableArticles() async throws {
        let service = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...3))])
        service.summaries = [
            "Článek 1": makeSummary(pageID: 1, title: "Článek 1", type: .disambiguation),
            "Článek 2": makeSummary(pageID: 2, title: "Článek 2", extractLength: 50),
            "Článek 3": makeSummary(pageID: 3, title: "Článek 3"),
        ]

        let article = try await makeLoader(service).article(for: topic, excluding: [])

        #expect(article?.pageID == 3)
    }

    @Test func skipsMissingPages() async throws {
        let service = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])
        service.summaries = ["Článek 2": makeSummary(pageID: 2, title: "Článek 2")]

        let article = try await makeLoader(service).article(for: topic, excluding: [])

        #expect(article?.pageID == 2)
    }

    @Test func skipsRedirectToAlreadySeenArticle() async throws {
        let service = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])
        service.summaries = [
            "Článek 1": makeSummary(pageID: 50, title: "Cíl přesměrování"),
            "Článek 2": makeSummary(pageID: 2, title: "Článek 2"),
        ]

        let article = try await makeLoader(service).article(for: topic, excluding: [50])

        #expect(article?.pageID == 2)
    }

    @Test func returnsNilWhenNothingSuitable() async throws {
        let service = FakeWikipediaService(categories: ["Root": .init(articles: refs(1...2))])

        #expect(try await makeLoader(service).article(for: topic, excluding: []) == nil)
    }
}

struct DailyReadingCounterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    @Test func countsWithinDayAndResetsNextDay() {
        var counter = DailyReadingCounter()
        let morning = Date(timeIntervalSince1970: 1_760_000_000)
        let nextDay = morning.addingTimeInterval(24 * 3600)

        #expect(counter.register(at: morning, calendar: calendar) == 1)
        #expect(counter.register(at: morning.addingTimeInterval(60), calendar: calendar) == 2)
        #expect(counter.todayCount(at: nextDay, calendar: calendar) == 0)
        #expect(counter.register(at: nextDay, calendar: calendar) == 1)
    }

    @Test func suggestsBreakEveryInterval() {
        let breaks = (1...60).filter { DailyReadingCounter.shouldSuggestBreak(afterCount: $0, interval: 20) }
        #expect(breaks == [20, 40, 60])
    }

    @Test func zeroIntervalDisablesBreaks() {
        #expect(!(1...100).contains { DailyReadingCounter.shouldSuggestBreak(afterCount: $0, interval: 0) })
    }
}
