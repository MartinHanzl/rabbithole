import Foundation

/// YouTube channels per topic – the video counterpart of `TopicCatalog`.
///
/// - Keys are topic ids from `TopicCatalog`.
/// - A channel is either `.handle("@kanal")` (as shown on youtube.com/@kanal)
///   or `.id("UC…")` (24 characters, from the channel URL or "Share channel → Copy channel ID").
///   `.id` is cheaper: ids are resolved in one request per 50 channels, handles one by one.
/// - Topics without channels simply get articles in video slots.
/// - Only public, embeddable, non-live videos within `durationRange` are shown.
enum VideoChannelCatalog {
    static let channelsByTopic: [String: [YouTubeChannelRef]] = [
        "space": [
            // .handle("@nazevkanalu"),
        ],
        "history": [
            // .id("UCxxxxxxxxxxxxxxxxxxxxxx"),
        ],
        "biology": [],
        "technology": [],
        "art": [],
        "geography": [],
        "psychology": [],
        "philosophy": [],
        "music": [],
        "sport": [],
        "language": [],
        "curiosities": [],
        // Osobní rozvoj a vztahy – Wikipedia coverage is thin, channels help most here.
        "accounting": [],
        "emotional-stability": [],
        "relational-intelligence": [],
        "relationships": [],
        "family": [],
        "sales": [],
        "negotiation": [],
        "leadership": [],
        "communication": [],
        "character": [],
        "motivation": [],
        "productivity": [],
        "health": [],
        "fun": [],
        "dreaming": [],
    ]

    /// At least a minute, no upper limit (long lectures are welcome).
    /// Raise the minimum to e.g. `181` to skip YouTube Shorts (they can be up to 3 minutes).
    static let durationRange: ClosedRange<TimeInterval> = 60...TimeInterval.infinity

    static func channels(for topicID: String) -> [YouTubeChannelRef] {
        channelsByTopic[topicID] ?? []
    }
}

nonisolated enum YouTubeChannelRef: Hashable, Codable, Sendable {
    case id(String)
    case handle(String)
}
