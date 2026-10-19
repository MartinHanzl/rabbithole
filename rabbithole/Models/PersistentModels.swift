import Foundation
import SwiftData

/// Per-topic user preference: whether it's selected and its personalization weight.
@Model
final class TopicPreference {
    @Attribute(.unique) var topicID: String
    var isSelected: Bool
    var weight: Double

    init(topicID: String, isSelected: Bool, weight: Double = 1.0) {
        self.topicID = topicID
        self.isSelected = isSelected
        self.weight = weight
    }
}

/// An article already shown in the feed, so it isn't shown again.
@Model
final class SeenArticle {
    @Attribute(.unique) var pageID: Int
    var seenAt: Date

    init(pageID: Int, seenAt: Date = .now) {
        self.pageID = pageID
        self.seenAt = seenAt
    }
}

/// A saved article snapshot – readable offline from the Saved tab.
@Model
final class SavedArticle {
    @Attribute(.unique) var pageID: Int
    var title: String
    var extract: String
    var topicID: String
    var articleURL: URL
    var thumbnailURL: URL?
    var imageFileTitle: String?
    var savedAt: Date

    init(pageID: Int, title: String, extract: String, topicID: String, articleURL: URL,
         thumbnailURL: URL?, imageFileTitle: String?, savedAt: Date = .now) {
        self.pageID = pageID
        self.title = title
        self.extract = extract
        self.topicID = topicID
        self.articleURL = articleURL
        self.thumbnailURL = thumbnailURL
        self.imageFileTitle = imageFileTitle
        self.savedAt = savedAt
    }
}

/// A video already shown in the feed. Only the YouTube video id is kept.
@Model
final class SeenVideo {
    @Attribute(.unique) var videoID: String
    var seenAt: Date

    init(videoID: String, seenAt: Date = .now) {
        self.videoID = videoID
        self.seenAt = seenAt
    }
}

/// A saved video. Metadata must be refreshed from the API within 30 days
/// (YouTube API Developer Policies) – see `SavedVideosRepository.refreshStale`.
@Model
final class SavedVideo {
    @Attribute(.unique) var videoID: String
    var title: String
    var channelTitle: String
    var duration: TimeInterval
    var thumbnailURL: URL?
    var topicID: String
    var savedAt: Date
    var metadataFetchedAt: Date

    init(video: YouTubeVideo, topicID: String, savedAt: Date = .now) {
        videoID = video.id
        title = video.title
        channelTitle = video.channelTitle
        duration = video.duration
        thumbnailURL = video.thumbnailURL
        self.topicID = topicID
        self.savedAt = savedAt
        metadataFetchedAt = video.fetchedAt
    }

    var video: YouTubeVideo {
        YouTubeVideo(id: videoID, title: title, channelTitle: channelTitle, duration: duration,
                     thumbnailURL: thumbnailURL, fetchedAt: metadataFetchedAt)
    }
}

enum PersistentSchema {
    static let models: [any PersistentModel.Type] = [
        TopicPreference.self,
        SeenArticle.self,
        SavedArticle.self,
        SeenVideo.self,
        SavedVideo.self,
    ]
}
