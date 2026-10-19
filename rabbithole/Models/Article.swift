import Foundation

/// Minimal pointer to an article, as listed in a category.
nonisolated struct ArticleReference: Codable, Hashable, Sendable {
    let pageID: Int
    let title: String
}

/// A short article shown on a feed card.
nonisolated struct ArticleSummary: Identifiable, Hashable, Sendable {
    enum PageType: String, Sendable {
        case standard
        case disambiguation
        case other
    }

    let pageID: Int
    let title: String
    let extract: String
    let description: String?
    let type: PageType
    let articleURL: URL
    let thumbnailURL: URL?
    /// File name of the lead image (e.g. `Mars.jpg`), used to link to its license page.
    let imageFileTitle: String?

    var id: Int { pageID }

    /// File description page with author and license (redirects to Commons for shared files).
    var imageLicenseURL: URL? {
        guard let imageFileTitle else { return nil }
        return WikipediaURLs.filePage(fileTitle: imageFileTitle)
    }
}

/// Full article text split into sections for the native reader.
nonisolated struct ArticleContent: Hashable, Sendable {
    let title: String
    let sections: [ArticleSection]
}

nonisolated struct ArticleSection: Hashable, Sendable, Identifiable {
    /// `nil` for the lead section.
    let title: String?
    /// 2 for `== H ==`, 3 for `=== H ===`, …; 1 for the lead.
    let level: Int
    let paragraphs: [String]

    var id: String { "\(level)|\(title ?? "")|\(paragraphs.first?.prefix(32) ?? "")" }
}
