import Foundation

nonisolated enum YouTubeError: Error, Equatable {
    case notConfigured
    case offline
    case quotaExceeded
    case invalidKey
    case http(status: Int, reason: String?)
}

/// Pure parsing and filtering of YouTube Data API responses – covered by unit tests.
nonisolated enum YouTubeParser {
    static let decoder = JSONDecoder()

    /// Channel id → uploads playlist id.
    static func uploadsPlaylists(from data: Data) throws -> [String: String] {
        let response = try decoder.decode(ChannelListResponse.self, from: data)
        var result: [String: String] = [:]
        for channel in response.items ?? [] {
            if let uploads = channel.contentDetails?.relatedPlaylists.uploads {
                result[channel.id] = uploads
            }
        }
        return result
    }

    struct PlaylistPage: Equatable, Sendable {
        var videoIDs: [String]
        var nextPage: String?
    }

    /// Video ids from a playlist page, skipping items already known to be non-public.
    static func playlistPage(from data: Data) throws -> PlaylistPage {
        let response = try decoder.decode(PlaylistItemListResponse.self, from: data)
        let ids = (response.items ?? [])
            .filter { ($0.status?.privacyStatus ?? "public") == "public" }
            .map(\.contentDetails.videoId)
        return PlaylistPage(videoIDs: ids, nextPage: response.nextPageToken)
    }

    /// Videos that may be shown: public, processed, embeddable, not live/upcoming, not
    /// age-restricted (those can't play in the embedded player) and within `durationRange`.
    static func playableVideos(
        from data: Data,
        durationRange: ClosedRange<TimeInterval> = VideoChannelCatalog.durationRange,
        fetchedAt: Date
    ) throws -> [YouTubeVideo] {
        let response = try decoder.decode(VideoListResponse.self, from: data)
        return (response.items ?? []).compactMap { item in
            guard let snippet = item.snippet,
                  let details = item.contentDetails,
                  let status = item.status,
                  status.privacyStatus == "public",
                  status.embeddable == true,
                  (status.uploadStatus ?? "processed") == "processed",
                  (snippet.liveBroadcastContent ?? "none") == "none",
                  details.contentRating?.ytRating != "ytAgeRestricted",
                  let duration = duration(fromISO8601: details.duration),
                  durationRange.contains(duration) else {
                return nil
            }
            let thumbnail = snippet.thumbnails?.high ?? snippet.thumbnails?.standard ?? snippet.thumbnails?.medium
            return YouTubeVideo(
                id: item.id,
                title: snippet.title,
                channelTitle: snippet.channelTitle,
                duration: duration,
                thumbnailURL: thumbnail?.url,
                fetchedAt: fetchedAt
            )
        }
    }

    /// Video ids from `search.list`, in relevance order.
    static func searchVideoIDs(from data: Data) throws -> [String] {
        (try decoder.decode(SearchListResponse.self, from: data).items ?? []).compactMap(\.id.videoId)
    }

    /// Ids present in a `videos.list` response – videos missing from it were deleted or made private.
    static func returnedVideoIDs(from data: Data) throws -> Set<String> {
        Set((try decoder.decode(VideoListResponse.self, from: data).items ?? []).map(\.id))
    }

    static func error(from data: Data, status: Int) -> YouTubeError {
        let reason = (try? decoder.decode(YouTubeErrorResponse.self, from: data))?.error.errors?.first?.reason
        switch (status, reason) {
        case (403, "quotaExceeded"), (403, "dailyLimitExceeded"), (403, "rateLimitExceeded"):
            return .quotaExceeded
        case (400, "keyInvalid"), (403, "forbidden"), (403, "accessNotConfigured"), (403, "ipRefererBlocked"):
            return .invalidKey
        default:
            return .http(status: status, reason: reason)
        }
    }

    /// Parses ISO 8601 durations as used by the API: `PT4M13S`, `PT1H2M`, `P1DT2H`, `PT45S`.
    static func duration(fromISO8601 string: String) -> TimeInterval? {
        guard string.hasPrefix("P") else { return nil }
        var total: TimeInterval = 0
        var number = ""
        var inTime = false
        var sawComponent = false
        for character in string.dropFirst() {
            switch character {
            case "T":
                guard number.isEmpty else { return nil }
                inTime = true
            case "0"..."9", ".":
                number.append(character)
            default:
                guard let value = Double(number) else { return nil }
                let multiplier: TimeInterval
                switch (character, inTime) {
                case ("W", false): multiplier = 7 * 86400
                case ("D", false): multiplier = 86400
                case ("H", true): multiplier = 3600
                case ("M", true): multiplier = 60
                case ("S", true): multiplier = 1
                default: return nil
                }
                total += value * multiplier
                number = ""
                sawComponent = true
            }
        }
        return sawComponent && number.isEmpty ? total : nil
    }
}
