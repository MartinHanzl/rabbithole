import SwiftUI

/// Long-lived, non-UI dependencies shared across features.
struct AppServices: Sendable {
    let wikipedia: any WikipediaService
    let feedLoader: FeedLoader
    let engine: PersonalizationEngine
    /// `nil` without a YouTube API key – the feed then shows articles only.
    let videoPool: VideoPool?
    let youTube: (any YouTubeService)?

    static let live: AppServices = {
        let client = WikipediaClient(userAgent: AppConfig.userAgent)
        let pool = ArticlePool(service: client, persistence: FilePoolPersistence())
        let youTube = YouTubeConfiguration.apiKey.map { YouTubeClient(apiKey: $0) }
        return AppServices(
            wikipedia: client,
            feedLoader: FeedLoader(service: client, pool: pool),
            engine: PersonalizationEngine(),
            videoPool: youTube.map { VideoPool(service: $0, persistence: FileVideoPoolPersistence()) },
            youTube: youTube
        )
    }()
}

extension EnvironmentValues {
    @Entry var services: AppServices = .live
}
