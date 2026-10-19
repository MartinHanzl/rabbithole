import Foundation

nonisolated enum WikipediaError: Error, Equatable {
    case offline
    case notFound
    case http(status: Int)
    case invalidResponse
}

nonisolated protocol WikipediaService: Sendable {
    func summary(title: String) async throws -> ArticleSummary
    func categoryMembers(category: String, continuation: String?) async throws -> WikipediaParser.CategoryPage
    func content(title: String) async throws -> ArticleContent
    func search(_ query: String) async throws -> [ArticleSummary]
}

/// Talks to cs.wikipedia.org. Every request carries a descriptive User-Agent per Wikimedia policy,
/// and responses go through a dedicated on-disk `URLCache` honouring the server's cache headers.
nonisolated final class WikipediaClient: WikipediaService {
    private let session: URLSession
    private let userAgent: String

    init(userAgent: String, session: URLSession? = nil) {
        self.userAgent = userAgent
        self.session = session ?? Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appending(path: "WikipediaHTTP")
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 20
        configuration.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: configuration)
    }

    func summary(title: String) async throws -> ArticleSummary {
        let data = try await get(WikipediaURLs.summary(title: title))
        return try WikipediaParser.summary(from: data)
    }

    func categoryMembers(category: String, continuation: String?) async throws -> WikipediaParser.CategoryPage {
        var items = [
            URLQueryItem(name: "list", value: "categorymembers"),
            URLQueryItem(name: "cmtitle", value: "Kategorie:\(category)"),
            URLQueryItem(name: "cmnamespace", value: "0|14"),
            URLQueryItem(name: "cmprop", value: "ids|title"),
            URLQueryItem(name: "cmlimit", value: "200"),
        ]
        if let continuation {
            items.append(URLQueryItem(name: "cmcontinue", value: continuation))
        }
        let data = try await get(WikipediaURLs.actionQuery(items))
        return try WikipediaParser.categoryMembers(from: data)
    }

    func content(title: String) async throws -> ArticleContent {
        let data = try await get(WikipediaURLs.actionQuery([
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exsectionformat", value: "wiki"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "titles", value: title),
        ]))
        return try WikipediaParser.content(from: data)
    }

    func search(_ query: String) async throws -> [ArticleSummary] {
        let data = try await get(WikipediaURLs.actionQuery([
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: query),
            URLQueryItem(name: "gsrnamespace", value: "0"),
            URLQueryItem(name: "gsrlimit", value: "12"),
            URLQueryItem(name: "prop", value: "extracts|pageimages|pageprops"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exsentences", value: "3"),
            URLQueryItem(name: "exlimit", value: "max"),
            URLQueryItem(name: "piprop", value: "thumbnail|name"),
            URLQueryItem(name: "pithumbsize", value: "640"),
            URLQueryItem(name: "ppprop", value: "disambiguation"),
        ]))
        return try WikipediaParser.searchResults(from: data)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw WikipediaError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw WikipediaError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 404: throw WikipediaError.notFound
        default: throw WikipediaError.http(status: http.statusCode)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
        .cannotConnectToHost, .timedOut, .dataNotAllowed, .internationalRoamingOff,
    ]
}
