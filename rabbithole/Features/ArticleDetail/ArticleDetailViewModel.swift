import Foundation
import Observation

@Observable
final class ArticleDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded(ArticleContent)
        /// Full text failed; the reader still shows the summary extract.
        case failed(isOffline: Bool)
    }

    let article: ArticleSummary
    let topicID: String
    private(set) var phase: Phase = .loading
    private(set) var isSaved: Bool

    private let services: AppServices
    private let saved: SavedArticlesRepository
    private let topics: TopicPreferencesRepository
    private var openedAt: Date?

    init(
        article: ArticleSummary,
        topicID: String,
        services: AppServices,
        saved: SavedArticlesRepository,
        topics: TopicPreferencesRepository
    ) {
        self.article = article
        self.topicID = topicID
        self.services = services
        self.saved = saved
        self.topics = topics
        isSaved = saved.savedIDs().contains(article.pageID)
    }

    func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            phase = .loaded(try await services.wikipedia.content(title: article.title))
        } catch {
            phase = .failed(isOffline: (error as? WikipediaError) == .offline)
        }
    }

    func toggleSaved() {
        if isSaved {
            saved.remove(pageID: article.pageID)
        } else {
            saved.save(article, topicID: topicID)
            adjustWeight(.saved)
        }
        isSaved.toggle()
    }

    // MARK: Reading time

    func didAppear() {
        openedAt = .now
    }

    /// Returns how long the article was open and applies the long-read signal.
    @discardableResult
    func didDisappear() -> TimeInterval {
        guard let openedAt else { return 0 }
        self.openedAt = nil
        let duration = Date.now.timeIntervalSince(openedAt)
        if services.engine.isLongRead(duration: duration) {
            adjustWeight(.longRead)
        }
        return duration
    }

    private func adjustWeight(_ signal: PersonalizationEngine.Signal) {
        let current = topics.weights()[topicID] ?? services.engine.configuration.initialWeight
        topics.setWeight(services.engine.updatedWeight(current, after: signal), for: topicID)
    }
}
