import Foundation

// Raw YouTube Data API v3 responses – only the fields we use.
// https://developers.google.com/youtube/v3/docs

/// `channels.list?part=contentDetails`
nonisolated struct ChannelListResponse: Decodable, Sendable {
    struct Channel: Decodable, Sendable {
        struct ContentDetails: Decodable, Sendable {
            struct RelatedPlaylists: Decodable, Sendable {
                let uploads: String?
            }
            let relatedPlaylists: RelatedPlaylists
        }
        let id: String
        let contentDetails: ContentDetails?
    }
    let items: [Channel]?
}

/// `playlistItems.list?part=contentDetails,status`
nonisolated struct PlaylistItemListResponse: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        struct ContentDetails: Decodable, Sendable {
            let videoId: String
        }
        struct Status: Decodable, Sendable {
            let privacyStatus: String?
        }
        let contentDetails: ContentDetails
        let status: Status?
    }
    let items: [Item]?
    let nextPageToken: String?
}

/// `videos.list?part=snippet,contentDetails,status`
nonisolated struct VideoListResponse: Decodable, Sendable {
    struct Video: Decodable, Sendable {
        struct Snippet: Decodable, Sendable {
            struct Thumbnail: Decodable, Sendable {
                let url: URL
            }
            struct Thumbnails: Decodable, Sendable {
                let medium: Thumbnail?
                let high: Thumbnail?
                let standard: Thumbnail?
            }
            let title: String
            let channelTitle: String
            let thumbnails: Thumbnails?
            let liveBroadcastContent: String?
        }
        struct ContentDetails: Decodable, Sendable {
            struct ContentRating: Decodable, Sendable {
                let ytRating: String?
            }
            let duration: String
            let contentRating: ContentRating?
        }
        struct Status: Decodable, Sendable {
            let uploadStatus: String?
            let privacyStatus: String?
            let embeddable: Bool?
        }
        let id: String
        let snippet: Snippet?
        let contentDetails: ContentDetails?
        let status: Status?
    }
    let items: [Video]?
}

/// Error body, e.g. `{"error":{"code":403,"errors":[{"reason":"quotaExceeded"}]}}`.
nonisolated struct YouTubeErrorResponse: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        struct Detail: Decodable, Sendable {
            let reason: String?
        }
        let code: Int
        let errors: [Detail]?
    }
    let error: Body
}

/// `search.list?part=id&type=video`
nonisolated struct SearchListResponse: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        struct ID: Decodable, Sendable {
            let videoId: String?
        }
        let id: ID
    }
    let items: [Item]?
}
