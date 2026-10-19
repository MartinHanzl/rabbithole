import Foundation

/// Turns a topic into a ready-to-show article: draws candidates from the pool, fetches their
/// summaries and skips unsuitable pages (remembering them so they're never fetched again).
nonisolated struct FeedLoader: Sendable {
    let service: any WikipediaService
    let pool: ArticlePool
    var maxAttempts = 6

    func article(for topic: Topic, excluding excluded: Set<Int>) async throws -> ArticleSummary? {
        var excluded = excluded
        for _ in 0..<maxAttempts {
            guard let candidate = try await pool.randomCandidate(for: topic, excluding: excluded) else {
                return nil
            }
            excluded.insert(candidate.pageID)
            do {
                let summary = try await service.summary(title: candidate.title)
                // Redirects can resolve to an article that was already shown.
                let isRepeat = summary.pageID != candidate.pageID && excluded.contains(summary.pageID)
                if ArticleFilter.isSuitable(summary), !isRepeat {
                    return summary
                }
                await pool.reject(pageID: candidate.pageID, topicID: topic.id)
            } catch WikipediaError.notFound {
                await pool.reject(pageID: candidate.pageID, topicID: topic.id)
            }
        }
        return nil
    }
}
