import Foundation
import Observation

nonisolated struct FeedCard: Identifiable, Hashable, Sendable {
    let article: ArticleSummary
    let topicID: String
    let isExploration: Bool

    var id: Int { article.pageID }
}

nonisolated struct VideoCard: Identifiable, Hashable, Sendable {
    let video: YouTubeVideo
    let topicID: String
    let isExploration: Bool

    var id: String { video.id }
}

enum FeedItem: Identifiable, Hashable {
    case article(FeedCard)
    case video(VideoCard)
    case readingBreak(id: UUID, count: Int)

    var id: String {
        switch self {
        case .article(let card): "a\(card.id)"
        case .video(let card): "v\(card.id)"
        case .readingBreak(let id, _): "b\(id)"
        }
    }

    var topicID: String? {
        switch self {
        case .article(let card): card.topicID
        case .video(let card): card.topicID
        case .readingBreak: nil
        }
    }
}

@Observable
final class FeedViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(isOffline: Bool)
        case empty
    }

    private(set) var items: [FeedItem] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    /// Error while appending more cards to an already visible feed.
    private(set) var loadMoreFailed = false
    private(set) var savedIDs: Set<Int> = []
    private(set) var savedVideoIDs: Set<String> = []

    /// How many cards to keep loaded ahead of the one on screen.
    private let prefetchDistance = 3
    private let batchSize = 5

    private let services: AppServices
    private let topics: TopicPreferencesRepository
    private let seen: SeenArticlesRepository
    private let saved: SavedArticlesRepository
    private let seenVideos: SeenVideosRepository
    private let savedVideos: SavedVideosRepository
    private let counterStore: DailyReadingCounterStore
    private let breakInterval: () -> Int
    private let videoInterval: () -> Int

    private var seenIDs: Set<Int> = []
    private var seenVideoIDs: Set<String> = []
    private var cardNumber = 0
    private var counter: DailyReadingCounter

    init(
        services: AppServices,
        topics: TopicPreferencesRepository,
        seen: SeenArticlesRepository,
        saved: SavedArticlesRepository,
        seenVideos: SeenVideosRepository,
        savedVideos: SavedVideosRepository,
        counterStore: DailyReadingCounterStore = .init(),
        breakInterval: @escaping () -> Int,
        videoInterval: @escaping () -> Int
    ) {
        self.services = services
        self.topics = topics
        self.seen = seen
        self.saved = saved
        self.seenVideos = seenVideos
        self.savedVideos = savedVideos
        self.counterStore = counterStore
        self.breakInterval = breakInterval
        self.videoInterval = videoInterval
        counter = counterStore.load()
    }

    // MARK: Loading

    func start() async {
        guard phase == .idle else { return }
        seenIDs = seen.allIDs()
        seenVideoIDs = seenVideos.allIDs()
        refreshSavedState()
        await reload()
    }

    func reload() async {
        items = []
        cardNumber = 0
        phase = .loading
        loadMoreFailed = false
        await loadMore()
    }

    /// Restarts the feed after topic selection or video settings changed.
    func settingsChanged() async {
        guard phase != .idle else { return }
        seenIDs = seen.allIDs()
        seenVideoIDs = seenVideos.allIDs()
        await reload()
    }

    func refreshSavedState() {
        savedIDs = saved.savedIDs()
        savedVideoIDs = savedVideos.savedIDs()
    }

    func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }

        let selected = topics.selectedTopicIDs()
        guard !selected.isEmpty else {
            phase = .empty
            return
        }

        // A batch can come back empty when candidates were unsuitable; retry a couple of times.
        var lastError: Error?
        for _ in 0..<3 {
            let (added, error) = await loadBatch(selected: selected)
            lastError = error
            if added > 0 {
                phase = .loaded
                return
            }
            if error != nil { break }
        }

        if items.isEmpty {
            phase = lastError.map { .failed(isOffline: Self.isOffline($0)) } ?? .empty
        } else {
            loadMoreFailed = lastError != nil
        }
    }

    private func loadBatch(selected: Set<String>) async -> (added: Int, error: Error?) {
        let planner = FeedSlotPlanner(
            engine: services.engine,
            videoInterval: videoInterval(),
            videosAvailable: services.videoPool != nil
        )
        var rng = SystemRandomNumberGenerator()
        let slots = planner.slots(
            from: cardNumber + 1, count: batchSize, selected: selected,
            all: Set(TopicCatalog.all.map(\.id)), weights: topics.weights(), using: &rng
        )
        cardNumber += batchSize

        let excludedArticles = seenIDs.union(loadedPageIDs)
        let excludedVideos = seenVideoIDs.union(loadedVideoIDs)
        let loader = services.feedLoader
        let videoPool = services.videoPool

        // Load in parallel, append in slot order so the article/video ratio holds.
        var results: [Int: Result<FeedItem?, Error>] = [:]
        await withTaskGroup(of: (Int, Result<FeedItem?, Error>).self) { group in
            for (index, slot) in slots.enumerated() {
                guard let topic = TopicCatalog.topic(id: slot.pick.topicID) else { continue }
                group.addTask {
                    if slot.kind == .video, let videoPool,
                       let video = try? await videoPool.randomCandidate(for: topic.id, excluding: excludedVideos) {
                        return (index, .success(.video(VideoCard(video: video, topicID: topic.id, isExploration: slot.pick.isExploration))))
                    }
                    // Article slot, or video slot without an available video.
                    do {
                        let article = try await loader.article(for: topic, excluding: excludedArticles)
                        return (index, .success(article.map {
                            .article(FeedCard(article: $0, topicID: topic.id, isExploration: slot.pick.isExploration))
                        }))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                results[index] = result
            }
        }

        var added = 0
        var firstError: Error?
        for index in results.keys.sorted() {
            switch results[index]! {
            case .success(let item?) where !isDuplicate(item):
                items.append(item)
                added += 1
            case .success:
                break
            case .failure(let error):
                firstError = firstError ?? error
            }
        }
        return (added, firstError)
    }

    private func isDuplicate(_ item: FeedItem) -> Bool {
        switch item {
        case .article(let card): loadedPageIDs.contains(card.id) || seenIDs.contains(card.id)
        case .video(let card): loadedVideoIDs.contains(card.id) || seenVideoIDs.contains(card.id)
        case .readingBreak: false
        }
    }

    private var loadedPageIDs: Set<Int> {
        Set(items.compactMap { if case .article(let card) = $0 { card.id } else { nil } })
    }

    private var loadedVideoIDs: Set<String> {
        Set(items.compactMap { if case .video(let card) = $0 { card.id } else { nil } })
    }

    private static func isOffline(_ error: Error) -> Bool {
        (error as? WikipediaError) == .offline
    }

    // MARK: Card events

    /// Called when a card scrolls into view: remembers it, counts it and prefetches.
    func cardAppeared(_ item: FeedItem) async {
        guard let index = items.firstIndex(of: item) else { return }

        var isNew = false
        switch item {
        case .article(let card) where !seenIDs.contains(card.id):
            seenIDs.insert(card.id)
            seen.markSeen(card.id)
            isNew = true
        case .video(let card) where !seenVideoIDs.contains(card.id):
            seenVideoIDs.insert(card.id)
            seenVideos.markSeen(card.id)
            isNew = true
        default:
            break
        }
        if isNew {
            let count = counter.register(at: .now)
            counterStore.save(counter)
            if DailyReadingCounter.shouldSuggestBreak(afterCount: count, interval: breakInterval()) {
                items.insert(.readingBreak(id: UUID(), count: count), at: index + 1)
            }
        }

        if index >= items.count - prefetchDistance, !loadMoreFailed {
            await loadMore()
        }
    }

    func dismissBreak(_ item: FeedItem) {
        items.removeAll { $0 == item }
    }

    func notInterested(_ item: FeedItem) {
        guard let topicID = item.topicID else { return }
        apply(.dismissed, to: topicID)
        remove(item)
    }

    func toggleSaved(_ card: FeedCard) {
        if savedIDs.contains(card.id) {
            saved.remove(pageID: card.id)
            savedIDs.remove(card.id)
        } else {
            saved.save(card.article, topicID: card.topicID)
            savedIDs.insert(card.id)
            apply(.saved, to: card.topicID)
        }
    }

    func toggleSaved(_ card: VideoCard) {
        if savedVideoIDs.contains(card.id) {
            savedVideos.remove(videoID: card.id)
            savedVideoIDs.remove(card.id)
        } else {
            savedVideos.save(card.video, topicID: card.topicID)
            savedVideoIDs.insert(card.id)
            apply(.saved, to: card.topicID)
        }
    }

    /// The embedded player reported an error (removed, private, not embeddable…): skip quietly.
    func videoUnplayable(_ card: VideoCard) {
        remove(.video(card))
        Task { await services.videoPool?.reject(videoID: card.id, topicID: card.topicID) }
    }

    private func remove(_ item: FeedItem) {
        items.removeAll { $0 == item }
        if items.count <= prefetchDistance {
            Task { await loadMore() }
        }
    }

    private func apply(_ signal: PersonalizationEngine.Signal, to topicID: String) {
        let current = topics.weights()[topicID] ?? services.engine.configuration.initialWeight
        topics.setWeight(services.engine.updatedWeight(current, after: signal), for: topicID)
    }
}
