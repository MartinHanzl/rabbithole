import Foundation

nonisolated enum YouTubeConfiguration {
    /// Key from Info.plist (filled from gitignored `Config/Secrets.xcconfig`); `nil` disables videos.
    /// Interim solution – see README "Přesun YouTube API na backend".
    static let apiKey: String? = {
        guard let key = Bundle.main.infoDictionary?["YouTubeAPIKey"] as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }()

    static var isAvailable: Bool { apiKey != nil }

    /// Video lists are re-fetched after a day so new uploads appear and removed videos disappear.
    static let refreshInterval: TimeInterval = 24 * 3600
    /// YouTube API Developer Policies: stored API data must be refreshed or deleted within 30 days.
    static let maxDataAge: TimeInterval = 30 * 24 * 3600
}

nonisolated protocol YouTubeService: Sendable {
    /// Uploads playlist id for each channel that exists.
    func uploadsPlaylists(for channels: [YouTubeChannelRef]) async throws -> [YouTubeChannelRef: String]
    func playlistPage(_ playlistID: String, page: String?) async throws -> YouTubePlaylistPage
    /// `playable`: videos that may be shown; `returned`: every id the API still knows.
    func videos(ids: [String]) async throws -> (playable: [YouTubeVideo], returned: Set<String>)
    /// Video ids matching a query, biased to `language` (nil = any). Costs 100 quota units –
    /// callers must cache and limit.
    func searchVideoIDs(_ query: String, language: String?) async throws -> [String]
}

typealias YouTubePlaylistPage = YouTubeParser.PlaylistPage

/// YouTube Data API v3 client using only quota-cheap endpoints (1 unit per call):
/// channels.list → uploads playlist → playlistItems.list → videos.list. Never search.list (100 units).
/// `fields` trims responses to what we actually use.
nonisolated final class YouTubeClient: YouTubeService {
    private static let base = URL(string: "https://www.googleapis.com/youtube/v3/")!
    private let apiKey: String
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(apiKey: String, session: URLSession = .shared, now: @escaping @Sendable () -> Date = { .now }) {
        self.apiKey = apiKey
        self.session = session
        self.now = now
    }

    func uploadsPlaylists(for channels: [YouTubeChannelRef]) async throws -> [YouTubeChannelRef: String] {
        var result: [YouTubeChannelRef: String] = [:]
        let fields = "items(id,contentDetails/relatedPlaylists/uploads)"

        let ids = channels.compactMap { if case .id(let id) = $0 { id } else { nil } }
        for chunk in ids.chunked(into: 50) {
            let data = try await get("channels", [
                "part": "contentDetails", "id": chunk.joined(separator: ","), "maxResults": "50", "fields": fields,
            ])
            for (channelID, uploads) in try YouTubeParser.uploadsPlaylists(from: data) {
                result[.id(channelID)] = uploads
            }
        }

        for case .handle(let handle) in channels {
            let data = try await get("channels", ["part": "contentDetails", "forHandle": handle, "fields": fields])
            if let uploads = try YouTubeParser.uploadsPlaylists(from: data).values.first {
                result[.handle(handle)] = uploads
            }
        }
        return result
    }

    func playlistPage(_ playlistID: String, page: String?) async throws -> YouTubePlaylistPage {
        var query = [
            // 20 newest per page keeps a topic refresh around 20 quota units with ~15 channels.
            "part": "contentDetails,status", "playlistId": playlistID, "maxResults": "20",
            "fields": "nextPageToken,items(contentDetails/videoId,status/privacyStatus)",
        ]
        query["pageToken"] = page
        return try YouTubeParser.playlistPage(from: try await get("playlistItems", query))
    }

    func videos(ids: [String]) async throws -> (playable: [YouTubeVideo], returned: Set<String>) {
        var playable: [YouTubeVideo] = []
        var returned: Set<String> = []
        for chunk in ids.chunked(into: 50) {
            let data = try await get("videos", [
                "part": "snippet,contentDetails,status", "id": chunk.joined(separator: ","), "maxResults": "50",
                "fields": "items(id,snippet(title,channelTitle,thumbnails(medium,high,standard),liveBroadcastContent),"
                    + "contentDetails(duration,contentRating/ytRating),status(uploadStatus,privacyStatus,embeddable))",
            ])
            playable += try YouTubeParser.playableVideos(from: data, fetchedAt: now())
            returned.formUnion(try YouTubeParser.returnedVideoIDs(from: data))
        }
        return (playable, returned)
    }

    func searchVideoIDs(_ query: String, language: String?) async throws -> [String] {
        var parameters = [
            "part": "id", "type": "video", "videoEmbeddable": "true", "q": query, "maxResults": "15",
            "safeSearch": "moderate", "fields": "items(id/videoId)",
        ]
        let (relevanceLanguage, regionCode) = QueryLanguage.youTubeParameters(for: language)
        parameters["relevanceLanguage"] = relevanceLanguage
        parameters["regionCode"] = regionCode
        let data = try await get("search", parameters)
        return try YouTubeParser.searchVideoIDs(from: data)
    }

    private func get(_ endpoint: String, _ query: [String: String]) async throws -> Data {
        var components = URLComponents(url: Self.base.appending(path: endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Required when the key is restricted to this iOS app in Google Cloud Console.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                                             .cannotFindHost, .cannotConnectToHost].contains(error.code) {
            throw YouTubeError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw YouTubeError.http(status: 0, reason: nil) }
        guard (200..<300).contains(http.statusCode) else {
            throw YouTubeParser.error(from: data, status: http.statusCode)
        }
        return data
    }
}

extension Array {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
