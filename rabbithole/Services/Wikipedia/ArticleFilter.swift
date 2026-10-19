import Foundation

/// Rejects pages that make poor feed cards: disambiguations, lists, stubs, pages without a lead.
nonisolated enum ArticleFilter {
    static let minimumExtractLength = 200

    private static let rejectedTitlePrefixes = ["Seznam ", "Seznamy ", "Rozcestník"]

    /// Cheap check on a title alone – used before fetching the summary to save requests.
    static func isCandidateTitle(_ title: String) -> Bool {
        !rejectedTitlePrefixes.contains { title.hasPrefix($0) }
    }

    static func isSuitable(_ article: ArticleSummary) -> Bool {
        guard article.type == .standard else { return false }
        guard isCandidateTitle(article.title) else { return false }
        if let description = article.description, description.localizedCaseInsensitiveContains("rozcestník") {
            return false
        }
        return article.extract.count >= minimumExtractLength
    }
}
