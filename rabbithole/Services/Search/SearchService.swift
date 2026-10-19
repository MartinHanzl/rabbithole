import Foundation
import Supabase

/// Search terms derived from what the user typed.
nonisolated struct SearchTerms: Codable, Equatable, Sendable {
    /// Short keywords – Wikipedia's search ranks poorly on whole questions.
    let wikipedia: String
    /// Natural phrasing works well on YouTube.
    let youtube: String
}

/// Offline fallback: drops Czech question and filler words ("jak funguje kapitalismus" → "kapitalismus").
nonisolated enum QuerySimplifier {
    static let stopWords: Set<String> = [
        "jak", "co", "proč", "kde", "kdy", "kdo", "který", "která", "které", "jaký", "jaká", "jaké", "čím", "kolik",
        "je", "jsou", "byl", "byla", "bylo", "byli", "být", "se", "si", "to", "ten", "ta", "a", "i", "nebo", "v", "ve",
        "na", "o", "u", "z", "ze", "do", "od", "po", "pro", "při", "s", "k", "ke", "za",
        "funguje", "fungují", "fungovat", "znamená", "znamenají", "vzniká", "vznikl", "vznikla", "vzniklo",
        "vysvětli", "vysvětlení", "vlastně", "prosím", "něco", "nějaký", "dělá", "dělají", "udělat", "vypadá",
        "dá", "lze", "můžu", "mohu", "chci", "vědět", "zajímá", "mě", "mi",
    ]

    static func keywords(_ query: String) -> String {
        let words = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let kept = words.filter { !stopWords.contains($0) }
        return (kept.isEmpty ? words : kept).joined(separator: " ")
    }

    static func terms(for query: String) -> SearchTerms {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return SearchTerms(wikipedia: keywords(trimmed), youtube: trimmed)
    }

    /// Cache key: case, spacing and trailing punctuation don't matter.
    static func normalized(_ query: String) -> String {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Per-device daily limit for YouTube searches (each costs 100 of the 10 000 daily quota units).
nonisolated struct DailySearchQuota: Codable, Equatable, Sendable {
    static let limit = 15

    private(set) var day: Date = .distantPast
    private(set) var used = 0

    func remaining(at date: Date, calendar: Calendar = .current) -> Int {
        calendar.startOfDay(for: date) == day ? max(0, Self.limit - used) : Self.limit
    }

    /// Consumes one search; `false` when today's limit is used up.
    mutating func consume(at date: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: date)
        if today != day {
            day = today
            used = 0
        }
        guard used < Self.limit else { return false }
        used += 1
        return true
    }

    /// Gives back a search that failed for reasons other than quota (network, rejected key…).
    mutating func refund() {
        used = max(0, used - 1)
    }
}

/// Cached YouTube search results (24 h – also well within the API's 30-day data rule).
nonisolated struct VideoSearchCache: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let videos: [YouTubeVideo]
        let storedAt: Date
    }

    static let lifetime: TimeInterval = 24 * 3600
    static let maxEntries = 100

    var entries: [String: Entry] = [:]

    func videos(for key: String, at date: Date) -> [YouTubeVideo]? {
        guard let entry = entries[key], date.timeIntervalSince(entry.storedAt) < Self.lifetime else { return nil }
        return entry.videos
    }

    mutating func store(_ videos: [YouTubeVideo], for key: String, at date: Date) {
        entries = entries.filter { date.timeIntervalSince($0.value.storedAt) < Self.lifetime }
        entries[key] = Entry(videos: videos, storedAt: date)
        if entries.count > Self.maxEntries,
           let oldest = entries.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            entries[oldest] = nil
        }
    }
}

nonisolated struct SearchResults: Sendable {
    enum VideoStatus: Equatable, Sendable {
        case found
        case unavailable          // no API key
        case dailyLimitReached
        case failed
    }

    let terms: SearchTerms
    let articles: [ArticleSummary]
    let videos: [YouTubeVideo]
    let videoStatus: VideoStatus
    let articlesFailed: Bool
}

/// Article + video search. Gemini (Edge Function `search-assist`) turns questions into search
/// terms; without it a local simplifier is used. YouTube searches are cached and limited per device.
actor SearchService {
    private let wikipedia: any WikipediaService
    private let youTube: (any YouTubeService)?
    private let client: SupabaseClient?
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let quotaKey = "youtubeSearchQuota"
    private let cacheURL: URL?
    private var cache: VideoSearchCache

    init(
        wikipedia: any WikipediaService,
        youTube: (any YouTubeService)?,
        client: SupabaseClient?,
        defaults: UserDefaults = .standard,
        cacheURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "YouTubeSearch.json"),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.wikipedia = wikipedia
        self.youTube = youTube
        self.client = client
        self.defaults = defaults
        self.cacheURL = cacheURL
        self.now = now
        cache = cacheURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(VideoSearchCache.self, from: $0) } ?? VideoSearchCache()
    }

    var remainingVideoSearches: Int {
        quota.remaining(at: now())
    }

    func search(_ query: String) async -> SearchResults {
        let terms = await self.terms(for: query)

        async let articles = try? wikipedia.search(terms.wikipedia)
        let (videos, status) = await searchVideos(terms.youtube)
        let found = await articles
        return SearchResults(terms: terms, articles: found ?? [], videos: videos, videoStatus: status,
                             articlesFailed: found == nil)
    }

    // MARK: Terms

    private func terms(for query: String) async -> SearchTerms {
        let fallback = QuerySimplifier.terms(for: query)
        guard let client else { return fallback }
        struct Body: Encodable { let q: String }
        let assisted: SearchTerms? = try? await withTimeout(seconds: 4) {
            try await client.functions.invoke("search-assist", options: FunctionInvokeOptions(body: Body(q: query)))
        }
        guard let assisted, !assisted.wikipedia.isEmpty, !assisted.youtube.isEmpty else { return fallback }
        return assisted
    }

    // MARK: Videos

    private func searchVideos(_ query: String) async -> ([YouTubeVideo], SearchResults.VideoStatus) {
        guard let youTube else { return ([], .unavailable) }
        let key = QuerySimplifier.normalized(query)
        if let cached = cache.videos(for: key, at: now()) {
            return (cached, .found)
        }
        var quota = self.quota
        guard quota.consume(at: now()) else { return ([], .dailyLimitReached) }
        self.quota = quota
        do {
            let ids = try await youTube.searchVideoIDs(query)
            let videos = ids.isEmpty ? [] : try await youTube.videos(ids: ids).playable
            // Keep relevance order from search.list.
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            let sorted = videos.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
            cache.store(sorted, for: key, at: now())
            persistCache()
            return (sorted, .found)
        } catch {
            if error as? YouTubeError == .quotaExceeded {
                return ([], .dailyLimitReached)
            }
            var quota = self.quota
            quota.refund()
            self.quota = quota
            return ([], .failed)
        }
    }

    private var quota: DailySearchQuota {
        get {
            defaults.data(forKey: quotaKey).flatMap { try? JSONDecoder().decode(DailySearchQuota.self, from: $0) }
                ?? DailySearchQuota()
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: quotaKey)
        }
    }

    private func persistCache() {
        guard let cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

/// Runs `operation`, giving up after `seconds`.
nonisolated func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
