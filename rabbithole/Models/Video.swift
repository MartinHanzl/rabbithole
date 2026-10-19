import Foundation

/// A YouTube video shown on a feed card. Holds only what the card needs (YouTube API
/// Developer Policies: store the minimum and refresh it – see `YouTubeConfiguration.maxDataAge`).
nonisolated struct YouTubeVideo: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let channelTitle: String
    let duration: TimeInterval
    let thumbnailURL: URL?
    /// When this metadata was fetched from the API.
    let fetchedAt: Date

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }

    var formattedDuration: String {
        let total = Int(duration.rounded())
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
