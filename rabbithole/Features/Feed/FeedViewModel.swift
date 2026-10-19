import Foundation
import Observation

nonisolated struct FeedCard: Identifiable, Hashable, Sendable {
    let article: ArticleSummary
    let topicID: String
    let isExploration: Bool

    var id: Int { article.pageID }
}

enum FeedItem: Identifiable, Hashable {
    case article(FeedCard)
    case readingBreak(id: UUID, count: Int)

    var id: String {
        switch self {
        case .article(let card): "a\(card.id)"
        case .readingBreak(let id, _): "b\(id)"
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

    /// How many cards to keep loaded ahead of the one on screen.
    private let prefetchDistance = 3
    private let batchSize = 5

    private let services: AppServices
    private let topics: TopicPreferencesRepository
    private let seen: SeenArticlesRepository
    private let saved: SavedArticlesRepository
    private let counterStore: DailyReadingCounterStore
    private let breakInterval: () -> Int

    private var seenIDs: Set<Int> = []
    private var cardNumber = 0
    private var counter: DailyReadingCounter

    init(
        services: AppServices,
        topics: TopicPreferencesRepository,
        seen: SeenArticlesRepository,
        saved: SavedArticlesRepository,
        counterStore: DailyReadingCounterStore = .init(),
        breakInterval: @escaping () -> Int
    ) {
        self.services = services
        self.topics = topics
        self.seen = seen
        self.saved = saved
        self.counterStore = counterStore
        self.breakInterval = breakInterval
        counter = counterStore.load()
    }

    // MARK: Loading

    func start() async {
        guard phase == .idle else { return }
        seenIDs = seen.allIDs()
        savedIDs = saved.savedIDs()
        await reload()
    }

    func reload() async {
        items = []
        phase = .loading
        loadMoreFailed = false
        await loadMore()
    }

    /// Restarts the feed after topic selection changed in settings.
    func topicsChanged() async {
        guard phase != .idle else { return }
        await reload()
    }

    func refreshSavedState() {
        savedIDs = saved.savedIDs()
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
        let weights = topics.weights()
        let allIDs = Set(TopicCatalog.all.map(\.id))
        var rng = SystemRandomNumberGenerator()
        let picks: [PersonalizationEngine.Pick] = (0..<batchSize).compactMap { _ in
            cardNumber += 1
            return services.engine.pickTopic(
                cardNumber: cardNumber, selected: selected, all: allIDs, weights: weights, using: &rng
            )
        }

        let excluded = seenIDs.union(loadedPageIDs)
        let loader = services.feedLoader
        var added = 0
        var firstError: Error?

        await withTaskGroup(of: Result<FeedCard?, Error>.self) { group in
            for pick in picks {
                guard let topic = TopicCatalog.topic(id: pick.topicID) else { continue }
                group.addTask {
                    do {
                        let article = try await loader.article(for: topic, excluding: excluded)
                        return .success(article.map {
                            FeedCard(article: $0, topicID: topic.id, isExploration: pick.isExploration)
                        })
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let card?):
                    if !loadedPageIDs.contains(card.id), !seenIDs.contains(card.id) {
                        items.append(.article(card))
                        added += 1
                    }
                case .success(nil):
                    break
                case .failure(let error):
                    firstError = firstError ?? error
                }
            }
        }
        return (added, firstError)
    }

    private var loadedPageIDs: Set<Int> {
        Set(items.compactMap {
            if case .article(let card) = $0 { card.id } else { nil }
        })
    }

    private static func isOffline(_ error: Error) -> Bool {
        (error as? WikipediaError) == .offline
    }

    // MARK: Card events

    /// Called when a card scrolls into view: remembers it, counts it and prefetches.
    func cardAppeared(_ item: FeedItem) async {
        guard let index = items.firstIndex(of: item) else { return }

        if case .article(let card) = item, !seenIDs.contains(card.id) {
            seenIDs.insert(card.id)
            seen.markSeen(card.id)
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

    func notInterested(_ card: FeedCard) {
        apply(.dismissed, to: card.topicID)
        items.removeAll { $0 == .article(card) }
        if items.count <= prefetchDistance {
            Task { await loadMore() }
        }
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

    /// Called when the reader closes; long reads boost the topic.
    func finishedReading(topicID: String, duration: TimeInterval) {
        guard services.engine.isLongRead(duration: duration) else { return }
        apply(.longRead, to: topicID)
    }

    private func apply(_ signal: PersonalizationEngine.Signal, to topicID: String) {
        let current = topics.weights()[topicID] ?? services.engine.configuration.initialWeight
        topics.setWeight(services.engine.updatedWeight(current, after: signal), for: topicID)
    }
}
