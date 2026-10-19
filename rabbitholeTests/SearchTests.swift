import Foundation
import Testing
@testable import rabbithole

struct QuerySimplifierTests {
    @Test(arguments: [
        ("jak funguje kapitalismus", "kapitalismus"),
        ("Jak funguje kapitalismus?", "kapitalismus"),
        ("Co je to černá díra", "černá díra"),
        ("proč je nebe modré", "nebe modré"),
        ("fotosyntéza", "fotosyntéza"),
    ])
    func extractsKeywords(query: String, expected: String) {
        #expect(QuerySimplifier.keywords(query) == expected)
    }

    @Test func keepsQueryWhenEverythingIsAStopWord() {
        #expect(QuerySimplifier.keywords("co je to") == "co je to")
    }

    @Test func youtubeGetsTheNaturalQuestion() {
        let terms = QuerySimplifier.terms(for: "  jak funguje kapitalismus ")
        #expect(terms == SearchTerms(wikipedia: "kapitalismus", youtube: "jak funguje kapitalismus", language: "cs"))
    }

    @Test func normalizationIgnoresCaseAndPunctuation() {
        #expect(QuerySimplifier.normalized("Jak funguje  KAPITALISMUS?!") == "jak funguje kapitalismus")
    }
}

struct QueryLanguageTests {
    @Test(arguments: [
        ("China", "en"), ("how does capitalism work", "en"), ("black holes", "en"),
        ("jak funguje kapitalismus", "cs"), ("kvantová fyzika", "cs"), ("Geschichte Roms", "de"),
    ])
    func detectsConfidentLanguages(query: String, expected: String) {
        #expect(QueryLanguage.detect(query) == expected)
    }

    @Test func ambiguousWordsDoNotForceALanguage() {
        #expect(QueryLanguage.detect("Mars") == nil)
    }

    @Test func czechRegionOnlyForCzechAndSlovak() {
        #expect(QueryLanguage.youTubeParameters(for: "cs") == ("cs", "CZ"))
        #expect(QueryLanguage.youTubeParameters(for: "sk") == ("sk", "CZ"))
        #expect(QueryLanguage.youTubeParameters(for: "en") == ("en", nil))
        #expect(QueryLanguage.youTubeParameters(for: nil) == (nil, nil))
    }
}

struct SearchTermsReconcilingTests {
    @Test func translatedYouTubeQueryFallsBackToWhatTheUserTyped() {
        let query = "jak funguje kapitalismus"
        let assisted = SearchTerms(wikipedia: "kapitalismus", youtube: "how capitalism works", language: "cs")
        let terms = SearchService.reconciled(assisted, query: query, fallback: QuerySimplifier.terms(for: query))
        #expect(terms == SearchTerms(wikipedia: "kapitalismus", youtube: "jak funguje kapitalismus", language: "cs"))
    }

    @Test func matchingLanguageIsKept() {
        let assisted = SearchTerms(wikipedia: "Čína", youtube: "China explained", language: "en")
        let terms = SearchService.reconciled(assisted, query: "China", fallback: QuerySimplifier.terms(for: "China"))
        #expect(terms == assisted)
    }

    @Test func missingLanguageIsFilledLocally() {
        let assisted = SearchTerms(wikipedia: "kvantová fyzika", youtube: "kvantová fyzika vysvětlení", language: nil)
        let terms = SearchService.reconciled(assisted, query: "kvantová fyzika", fallback: QuerySimplifier.terms(for: "kvantová fyzika"))
        #expect(terms.language == "cs")
        #expect(terms.youtube == "kvantová fyzika vysvětlení")
    }
}

struct SearchParsingTests {
    @Test func parsesWikipediaSearchInRelevanceOrder() throws {
        let results = try WikipediaParser.searchResults(from: Fixtures.data("search_wikipedia"))
        #expect(results.map(\.title) == ["Kapitalismus", "Státní kapitalismus", "O kapitalismu s láskou",
                                         "Protestantská etika a duch kapitalismu"])
        let protestant = try #require(results.last)
        #expect(protestant.thumbnailURL != nil)
        #expect(protestant.imageFileTitle?.hasPrefix("Die protestantische Ethik") == true)
        #expect(results.allSatisfy { !$0.extract.isEmpty })
    }

    @Test func dropsDisambiguationsAndEmptyIntros() throws {
        let json = #"""
        {"query":{"pages":[
          {"pageid":1,"title":"Mars","index":1,"extract":"Mars má více významů.","pageprops":{"disambiguation":""}},
          {"pageid":2,"title":"Prázdný","index":2,"extract":""},
          {"pageid":3,"title":"Seznam planet","index":3,"extract":"Seznam."},
          {"pageid":4,"title":"Mars (planeta)","index":4,"extract":"Mars je planeta."}
        ]}}
        """#
        #expect(try WikipediaParser.searchResults(from: Data(json.utf8)).map(\.pageID) == [4])
    }

    @Test func noResults() throws {
        #expect(try WikipediaParser.searchResults(from: Data(#"{"batchcomplete":true}"#.utf8)).isEmpty)
    }

    @Test func parsesYouTubeSearchSkippingNonVideos() throws {
        #expect(try YouTubeParser.searchVideoIDs(from: Fixtures.data("yt_search")) == ["vidSearch01", "vidSearch02"])
    }
}

struct SearchQuotaTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }()
    private let morning = Date(timeIntervalSince1970: 1_792_400_000)

    @Test func limitsSearchesPerDayAndResets() {
        var quota = DailySearchQuota()
        for _ in 0..<DailySearchQuota.limit {
            let allowed = quota.consume(at: morning, calendar: calendar)
            #expect(allowed)
        }
        let overLimit = quota.consume(at: morning, calendar: calendar)
        #expect(!overLimit)
        #expect(quota.remaining(at: morning, calendar: calendar) == 0)
        #expect(quota.remaining(at: morning + 86_400, calendar: calendar) == DailySearchQuota.limit)
        let nextDay = quota.consume(at: morning + 86_400, calendar: calendar)
        #expect(nextDay)
    }

    @Test func cacheExpiresAfterADay() {
        var cache = VideoSearchCache()
        let video = YouTubeVideo(id: "a", title: "A", channelTitle: "K", duration: 300, thumbnailURL: nil, fetchedAt: morning)
        cache.store([video], for: "kapitalismus", at: morning)
        #expect(cache.videos(for: "kapitalismus", at: morning + 3600)?.count == 1)
        #expect(cache.videos(for: "kapitalismus", at: morning + 25 * 3600) == nil)
    }

    @Test func cacheIsBounded() {
        var cache = VideoSearchCache()
        for i in 0...VideoSearchCache.maxEntries {
            cache.store([], for: "q\(i)", at: morning + Double(i))
        }
        #expect(cache.entries.count == VideoSearchCache.maxEntries)
        #expect(cache.entries["q0"] == nil)
    }
}

struct SearchServiceTests {
    private func makeService(youTube: FakeYouTubeService?, suite: String = UUID().uuidString) -> (SearchService, FakeWikipediaService) {
        let wikipedia = FakeWikipediaService()
        wikipedia.searchResults = [makeSummary(pageID: 1, title: "Kapitalismus")]
        let service = SearchService(wikipedia: wikipedia, youTube: youTube, client: nil,
                                    defaults: UserDefaults(suiteName: suite)!, cacheURL: nil)
        return (service, wikipedia)
    }

    private func fakeYouTube() -> FakeYouTubeService {
        let youTube = FakeYouTubeService()
        youTube.searchIDs = ["v2", "v1"]
        for id in ["v1", "v2"] {
            youTube.videos[id] = YouTubeVideo(id: id, title: id, channelTitle: "K", duration: 600, thumbnailURL: nil, fetchedAt: .now)
        }
        return youTube
    }

    @Test func findsArticlesAndVideosInRelevanceOrder() async {
        let youTube = fakeYouTube()
        let (service, _) = makeService(youTube: youTube)

        let results = await service.search("jak funguje kapitalismus")

        #expect(results.terms.wikipedia == "kapitalismus")
        #expect(results.articles.map(\.title) == ["Kapitalismus"])
        #expect(results.videos.map(\.id) == ["v2", "v1"])
        #expect(results.videoStatus == .found)
        #expect(youTube.calls.contains("search:jak funguje kapitalismus"))
        #expect(youTube.searchLanguages == ["cs"])
    }

    @Test func englishQueryGetsEnglishVideos() async {
        let youTube = fakeYouTube()
        let (service, _) = makeService(youTube: youTube)

        _ = await service.search("China")

        #expect(youTube.searchLanguages == ["en"])
    }

    @Test func sameWordsInAnotherLanguageAreCachedSeparately() {
        // The cache key includes the language, so a Czech and an English search don't mix.
        var cache = VideoSearchCache()
        cache.store([], for: "en|china", at: .now)
        #expect(cache.videos(for: "cs|china", at: .now) == nil)
    }

    @Test func repeatedSearchUsesCacheAndNoQuota() async {
        let youTube = fakeYouTube()
        let (service, _) = makeService(youTube: youTube)

        _ = await service.search("Jak funguje kapitalismus?")
        _ = await service.search("jak funguje kapitalismus")

        #expect(youTube.calls.filter { $0.hasPrefix("search:") }.count == 1)
        #expect(await service.remainingVideoSearches == DailySearchQuota.limit - 1)
    }

    @Test func stopsSearchingYouTubeAtTheDailyLimit() async {
        let youTube = fakeYouTube()
        let (service, _) = makeService(youTube: youTube)

        for i in 0..<DailySearchQuota.limit { _ = await service.search("dotaz \(i)") }
        let results = await service.search("ještě jeden")

        #expect(results.videoStatus == .dailyLimitReached)
        #expect(results.articles.count == 1, "articles still work")
        #expect(youTube.calls.filter { $0.hasPrefix("search:") }.count == DailySearchQuota.limit)
    }

    @Test func failedVideoSearchDoesNotCountAgainstTheLimit() async {
        let youTube = fakeYouTube()
        youTube.error = YouTubeError.invalidKey
        let (service, _) = makeService(youTube: youTube)

        let results = await service.search("kapitalismus")

        #expect(results.videoStatus == .failed)
        #expect(await service.remainingVideoSearches == DailySearchQuota.limit)
    }

    @Test func noYouTubeKeyStillFindsArticles() async {
        let (service, _) = makeService(youTube: nil)
        let results = await service.search("kapitalismus")
        #expect(results.videoStatus == .unavailable)
        #expect(!results.articles.isEmpty)
    }

    @Test func articleFailureIsReported() async {
        let (service, wikipedia) = makeService(youTube: nil)
        wikipedia.error = WikipediaError.offline
        let results = await service.search("kapitalismus")
        #expect(results.articlesFailed)
    }
}
