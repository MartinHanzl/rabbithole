import Foundation

// Raw API responses. Only fields we use are declared; everything else is ignored.

/// REST `page/summary/{title}`.
nonisolated struct SummaryResponse: Decodable, Sendable {
    struct Image: Decodable, Sendable {
        let source: URL
    }

    struct ContentURLs: Decodable, Sendable {
        struct Page: Decodable, Sendable {
            let page: URL
        }
        let desktop: Page
    }

    let type: String
    let title: String
    let pageid: Int
    let extract: String?
    let description: String?
    let thumbnail: Image?
    let originalimage: Image?
    let content_urls: ContentURLs?
}

/// Action API `list=categorymembers`.
nonisolated struct CategoryMembersResponse: Decodable, Sendable {
    struct Member: Decodable, Sendable {
        let pageid: Int
        let ns: Int
        let title: String
    }

    struct Query: Decodable, Sendable {
        let categorymembers: [Member]
    }

    struct Continue: Decodable, Sendable {
        let cmcontinue: String?
    }

    let query: Query?
    let `continue`: Continue?
}

/// Action API `prop=extracts&explaintext=1`.
nonisolated struct ExtractResponse: Decodable, Sendable {
    struct Page: Decodable, Sendable {
        let pageid: Int?
        let title: String
        let extract: String?
        let missing: Bool?
    }

    struct Query: Decodable, Sendable {
        let pages: [Page]
    }

    let query: Query?
}
