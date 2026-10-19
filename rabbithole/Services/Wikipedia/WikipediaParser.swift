import Foundation

nonisolated enum WikipediaParseError: Error, Equatable {
    case missingPage
}

/// Turns raw API responses into domain models. Pure functions – covered by unit tests.
nonisolated enum WikipediaParser {
    static let decoder = JSONDecoder()

    static func summary(from data: Data) throws -> ArticleSummary {
        let dto = try decoder.decode(SummaryResponse.self, from: data)
        return summary(from: dto)
    }

    static func summary(from dto: SummaryResponse) -> ArticleSummary {
        let imageURL = dto.originalimage?.source ?? dto.thumbnail?.source
        return ArticleSummary(
            pageID: dto.pageid,
            title: dto.title,
            extract: (dto.extract ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            description: dto.description,
            type: ArticleSummary.PageType(rawValue: dto.type) ?? .other,
            articleURL: dto.content_urls?.desktop.page ?? WikipediaURLs.article(title: dto.title),
            thumbnailURL: dto.thumbnail?.source,
            imageFileTitle: imageURL.flatMap(WikipediaURLs.fileTitle(fromImageURL:))
        )
    }

    struct CategoryPage: Sendable, Equatable {
        var articles: [String]
        var subcategories: [String]
        var continuation: String?
    }

    /// Splits members into article titles (ns 0) and subcategory names (ns 14, without prefix).
    static func categoryMembers(from data: Data) throws -> CategoryPage {
        let dto = try decoder.decode(CategoryMembersResponse.self, from: data)
        var page = CategoryPage(articles: [], subcategories: [], continuation: dto.continue?.cmcontinue)
        for member in dto.query?.categorymembers ?? [] {
            switch member.ns {
            case 0:
                page.articles.append(member.title)
            case 14:
                page.subcategories.append(stripCategoryPrefix(member.title))
            default:
                break
            }
        }
        return page
    }

    static func stripCategoryPrefix(_ title: String) -> String {
        for prefix in ["Kategorie:", "Category:"] where title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count))
        }
        return title
    }

    // MARK: - Full article

    /// Sections that only make sense on the web (references, links, navigation).
    static let skippedSectionTitles: Set<String> = [
        "Reference", "Poznámky", "Externí odkazy", "Související články",
        "Literatura", "Odkazy", "Zdroje", "Galerie", "Bibliografie", "Dílo", "Filmografie", "Diskografie",
    ]

    static func content(from data: Data) throws -> ArticleContent {
        let dto = try decoder.decode(ExtractResponse.self, from: data)
        guard let page = dto.query?.pages.first, page.missing != true, let extract = page.extract else {
            throw WikipediaParseError.missingPage
        }
        return ArticleContent(title: page.title, sections: sections(fromPlainText: extract))
    }

    /// Parses `explaintext` output with `== Heading ==` markers into sections.
    /// Skipped sections drop their subsections too; sections without text are removed.
    static func sections(fromPlainText text: String) -> [ArticleSection] {
        var result: [ArticleSection] = []
        var currentTitle: String?
        var currentLevel = 1
        var currentLines: [String] = []
        var skipBelowLevel: Int?

        func flush() {
            let paragraphs = currentLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !paragraphs.isEmpty, skipBelowLevel == nil {
                result.append(ArticleSection(title: currentTitle, level: currentLevel, paragraphs: paragraphs))
            }
            currentLines = []
        }

        for line in text.components(separatedBy: "\n") {
            if let heading = parseHeading(line) {
                flush()
                if let skip = skipBelowLevel, heading.level <= skip {
                    skipBelowLevel = nil
                }
                if skipBelowLevel == nil, skippedSectionTitles.contains(heading.title) {
                    skipBelowLevel = heading.level
                }
                currentTitle = heading.title
                currentLevel = heading.level
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return result
    }

    static func parseHeading(_ line: String) -> (title: String, level: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("=="), trimmed.hasSuffix("==") else { return nil }
        let level = trimmed.prefix(while: { $0 == "=" }).count
        let trailing = trimmed.reversed().prefix(while: { $0 == "=" }).count
        guard level == trailing, trimmed.count > level * 2 else { return nil }
        let title = trimmed.dropFirst(level).dropLast(level).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (title, level)
    }
}
