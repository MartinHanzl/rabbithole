import Foundation
import Testing
@testable import rabbithole

struct WikipediaParserTests {
    // MARK: Summary

    @Test func parsesStandardSummary() throws {
        let summary = try WikipediaParser.summary(from: Fixtures.data("summary_standard"))

        #expect(summary.pageID == 771)
        #expect(summary.title == "Mars (planeta)")
        #expect(summary.type == .standard)
        #expect(summary.extract.hasPrefix("Mars je čtvrtá planeta"))
        #expect(summary.articleURL.absoluteString == "https://cs.wikipedia.org/wiki/Mars_(planeta)")
        #expect(summary.thumbnailURL != nil)
        #expect(summary.imageFileTitle == "OSIRIS Mars true color.jpg")
        #expect(summary.imageLicenseURL?.absoluteString == "https://cs.wikipedia.org/wiki/Soubor:OSIRIS_Mars_true_color.jpg")
    }

    @Test func parsesDisambiguationSummary() throws {
        let summary = try WikipediaParser.summary(from: Fixtures.data("summary_disambiguation"))

        #expect(summary.type == .disambiguation)
        #expect(summary.thumbnailURL == nil)
        #expect(summary.imageFileTitle == nil)
    }

    @Test func unknownPageTypeMapsToOther() throws {
        let json = #"{"type":"no-extract","title":"X","pageid":1}"#
        let summary = try WikipediaParser.summary(from: Data(json.utf8))

        #expect(summary.type == .other)
        #expect(summary.extract.isEmpty)
        #expect(summary.articleURL.absoluteString == "https://cs.wikipedia.org/wiki/X")
    }

    @Test func malformedSummaryThrows() {
        #expect(throws: DecodingError.self) {
            try WikipediaParser.summary(from: Data(#"{"title":"X"}"#.utf8))
        }
    }

    // MARK: Image file title

    @Test(arguments: [
        ("https://upload.wikimedia.org/wikipedia/commons/0/02/OSIRIS_Mars_true_color.jpg?utm_source=x", "OSIRIS Mars true color.jpg"),
        ("https://upload.wikimedia.org/wikipedia/commons/thumb/0/02/Mars.jpg/330px-Mars.jpg", "Mars.jpg"),
        ("https://upload.wikimedia.org/wikipedia/cs/a/ab/%C4%8Cesk%C3%BD_lev.png", "Český lev.png"),
    ])
    func extractsImageFileTitle(url: String, expected: String) throws {
        #expect(WikipediaURLs.fileTitle(fromImageURL: try #require(URL(string: url))) == expected)
    }

    // MARK: Category members

    @Test func parsesCategoryMembersWithContinuation() throws {
        let page = try WikipediaParser.categoryMembers(from: Fixtures.data("categorymembers"))

        #expect(page.articles.count == 8)
        #expect(page.articles.first == ArticleReference(pageID: 797, title: "Planeta"))
        #expect(page.subcategories.isEmpty)
        #expect(page.continuation != nil)
    }

    @Test func splitsSubcategoriesAndStripsPrefix() throws {
        let json = """
        {"batchcomplete":true,"query":{"categorymembers":[
          {"pageid":1,"ns":0,"title":"Jupiter (planeta)"},
          {"pageid":2,"ns":14,"title":"Kategorie:Exoplanety"},
          {"pageid":3,"ns":6,"title":"Soubor:Planety.png"}
        ]}}
        """
        let page = try WikipediaParser.categoryMembers(from: Data(json.utf8))

        #expect(page.articles == [ArticleReference(pageID: 1, title: "Jupiter (planeta)")])
        #expect(page.subcategories == ["Exoplanety"])
        #expect(page.continuation == nil)
    }

    @Test func emptyCategoryResponse() throws {
        let page = try WikipediaParser.categoryMembers(from: Data(#"{"batchcomplete":true}"#.utf8))
        #expect(page == .init(articles: [], subcategories: [], continuation: nil))
    }

    // MARK: Full article

    @Test func parsesArticleSectionsAndSkipsReferences() throws {
        let content = try WikipediaParser.content(from: Fixtures.data("extract"))
        let titles = content.sections.map(\.title)

        #expect(content.title == "Mars (planeta)")
        #expect(content.sections.first?.title == nil)
        #expect(content.sections.first?.paragraphs.first?.hasPrefix("Mars je čtvrtá planeta") == true)
        #expect(titles.contains("Vznik"))
        #expect(!titles.contains("Odkazy"))
        #expect(!titles.contains("Reference"))
        #expect(!titles.contains("Externí odkazy"))
        #expect(!titles.contains("Poznámky"))
    }

    @Test func skippedSectionResumesAtSameLevel() {
        let text = """
        Úvod.

        == Odkazy ==

        === Reference ===
        x

        == Historie ==
        Text historie.
        === Novověk ===
        Další text.
        """
        let sections = WikipediaParser.sections(fromPlainText: text)

        #expect(sections.map(\.title) == [nil, "Historie", "Novověk"])
        #expect(sections.map(\.level) == [1, 2, 3])
    }

    @Test func missingPageThrows() {
        let json = #"{"query":{"pages":[{"title":"Neexistuje","missing":true}]}}"#
        #expect(throws: WikipediaParseError.missingPage) {
            try WikipediaParser.content(from: Data(json.utf8))
        }
    }

    @Test(arguments: [
        ("== Historie ==", "Historie", 2),
        ("=== Novověk ===", "Novověk", 3),
        ("  ==== A b ====  ", "A b", 4),
    ])
    func parsesHeadings(line: String, title: String, level: Int) throws {
        let heading = try #require(WikipediaParser.parseHeading(line))
        #expect(heading.title == title)
        #expect(heading.level == level)
    }

    @Test(arguments: ["Text", "== Nesoulad ===", "====", "a == b =="])
    func rejectsNonHeadings(line: String) {
        #expect(WikipediaParser.parseHeading(line) == nil)
    }
}

struct ArticleFilterTests {
    private func article(
        title: String = "Mars (planeta)",
        type: ArticleSummary.PageType = .standard,
        extractLength: Int = 300,
        description: String? = nil
    ) -> ArticleSummary {
        ArticleSummary(
            pageID: 1, title: title, extract: String(repeating: "a", count: extractLength),
            description: description, type: type,
            articleURL: WikipediaURLs.article(title: title), thumbnailURL: nil, imageFileTitle: nil
        )
    }

    @Test func acceptsRegularArticle() {
        #expect(ArticleFilter.isSuitable(article()))
    }

    @Test func rejectsDisambiguation() throws {
        let fixture = try WikipediaParser.summary(from: Fixtures.data("summary_disambiguation"))
        #expect(!ArticleFilter.isSuitable(fixture))
        #expect(!ArticleFilter.isSuitable(article(description: "rozcestník na projektech Wikimedia")))
    }

    @Test func rejectsListsByTitle() {
        #expect(!ArticleFilter.isCandidateTitle("Seznam planet"))
        #expect(!ArticleFilter.isSuitable(article(title: "Seznamy hor")))
        #expect(ArticleFilter.isCandidateTitle("Seznamka"))
    }

    @Test func rejectsShortOrMissingExtract() {
        #expect(!ArticleFilter.isSuitable(article(extractLength: 0)))
        #expect(!ArticleFilter.isSuitable(article(extractLength: ArticleFilter.minimumExtractLength - 1)))
        #expect(ArticleFilter.isSuitable(article(extractLength: ArticleFilter.minimumExtractLength)))
    }

    @Test func rejectsNonStandardTypes() {
        #expect(!ArticleFilter.isSuitable(article(type: .other)))
    }
}
