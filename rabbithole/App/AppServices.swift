import SwiftUI

/// Long-lived, non-UI dependencies shared across features.
struct AppServices: Sendable {
    let wikipedia: any WikipediaService
    let feedLoader: FeedLoader
    let engine: PersonalizationEngine

    static let live: AppServices = {
        let client = WikipediaClient(userAgent: AppConfig.userAgent)
        let pool = ArticlePool(service: client, persistence: FilePoolPersistence())
        return AppServices(
            wikipedia: client,
            feedLoader: FeedLoader(service: client, pool: pool),
            engine: PersonalizationEngine()
        )
    }()
}

extension EnvironmentValues {
    @Entry var services: AppServices = .live
}
