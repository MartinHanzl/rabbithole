import Foundation
import SwiftData
import Testing
@testable import rabbithole

struct FeedSlotPlannerTests {
    private let engine = PersonalizationEngine()

    @Test func everyFourthCardIsAVideoByDefault() {
        let planner = FeedSlotPlanner(engine: engine, videoInterval: FeedSlotPlanner.defaultVideoInterval, videosAvailable: true)
        let videoCards = (1...40).filter { planner.kind(forCard: $0) == .video }
        #expect(videoCards == [4, 8, 12, 16, 20, 24, 28, 32, 36, 40])
    }

    @Test(arguments: [3, 6, 10])
    func intervalIsConfigurable(interval: Int) {
        let planner = FeedSlotPlanner(engine: engine, videoInterval: interval, videosAvailable: true)
        let videos = (1...60).filter { planner.kind(forCard: $0) == .video }
        #expect(videos.count == 60 / interval)
        #expect(videos.allSatisfy { $0 % interval == 0 })
    }

    @Test func zeroIntervalTurnsVideosOff() {
        let planner = FeedSlotPlanner(engine: engine, videoInterval: 0, videosAvailable: true)
        #expect((1...100).allSatisfy { planner.kind(forCard: $0) == .article })
    }

    @Test func noVideosWithoutYouTube() {
        let planner = FeedSlotPlanner(engine: engine, videoInterval: 4, videosAvailable: false)
        #expect((1...100).allSatisfy { planner.kind(forCard: $0) == .article })
    }

    @Test func slotsCombineKindWithExplorationTopic() {
        let planner = FeedSlotPlanner(engine: engine, videoInterval: 4, videosAvailable: true)
        var rng = SeededGenerator(seed: 5)
        let slots = planner.slots(from: 1, count: 20, selected: ["a"], all: ["a", "b"], weights: [:], using: &rng)

        #expect(slots.map(\.cardNumber) == Array(1...20))
        let card20 = slots[19]
        #expect(card20.kind == .video)
        #expect(card20.pick == .init(topicID: "b", isExploration: true))
        #expect(slots[9].pick.isExploration && slots[9].kind == .article)
    }
}

/// Mixing in the real FeedViewModel with in-memory SwiftData and fake Wikipedia/YouTube.
struct FeedViewModelMixingTests {
    private func makeViewModel(videoInterval: Int, videosForTopics: Bool = true) throws -> (FeedViewModel, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(PersistentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let topics = TopicPreferencesRepository(context: context)
        topics.setSelected(Set(TopicCatalog.all.map(\.id)))

        let wikipedia = FakeWikipediaService()
        wikipedia.generatedArticlesPerCategory = 50
        let articlePool = ArticlePool(service: wikipedia, persistence: InMemoryPoolPersistence())

        let youTube = FakeYouTubeService()
        let channel = YouTubeChannelRef.id("UC1")
        youTube.playlists = [channel: "UU1"]
        let ids = (1...200).map { "video\($0)" }
        youTube.pages = ["UU1": [ids]]
        for id in ids {
            youTube.videos[id] = YouTubeVideo(id: id, title: id, channelTitle: "Kanál", duration: 300,
                                              thumbnailURL: nil, fetchedAt: .now)
        }
        let videoPool = VideoPool(
            service: youTube, persistence: InMemoryVideoPoolPersistence(),
            channels: { _ in videosForTopics ? [channel] : [] }
        )

        let services = AppServices(
            wikipedia: wikipedia,
            feedLoader: FeedLoader(service: wikipedia, pool: articlePool),
            engine: PersonalizationEngine(),
            videoPool: videoPool,
            youTube: youTube,
            search: SearchService(wikipedia: wikipedia, youTube: youTube, client: nil, cacheURL: nil)
        )
        let defaults = UserDefaults(suiteName: "FeedViewModelMixingTests-\(UUID())")!
        let viewModel = FeedViewModel(
            services: services,
            topics: topics,
            seen: SeenArticlesRepository(context: context),
            saved: SavedArticlesRepository(context: context),
            seenVideos: SeenVideosRepository(context: context),
            savedVideos: SavedVideosRepository(context: context),
            counterStore: DailyReadingCounterStore(defaults: defaults),
            breakInterval: { 0 },
            videoInterval: { videoInterval }
        )
        return (viewModel, container)
    }

    private func kinds(_ items: [FeedItem]) -> String {
        items.map { item -> String in
            switch item {
            case .article: "a"
            case .video: "v"
            case .readingBreak: "b"
            }
        }.joined()
    }

    @Test func feedFollowsConfiguredRatioInOrder() async throws {
        let (viewModel, container) = try makeViewModel(videoInterval: 4)
        await viewModel.start()
        await viewModel.loadMore()
        await viewModel.loadMore()
        _ = container

        #expect(viewModel.phase == .loaded)
        #expect(kinds(viewModel.items).hasPrefix("aaavaaavaaavaaa"))
    }

    @Test func videosOffGivesOnlyArticles() async throws {
        let (viewModel, container) = try makeViewModel(videoInterval: 0)
        await viewModel.start()
        await viewModel.loadMore()
        _ = container

        #expect(!viewModel.items.isEmpty)
        #expect(!kinds(viewModel.items).contains("v"))
    }

    @Test func videoSlotFallsBackToArticleWithoutChannels() async throws {
        let (viewModel, container) = try makeViewModel(videoInterval: 2, videosForTopics: false)
        await viewModel.start()
        _ = container

        #expect(kinds(viewModel.items) == "aaaaa")
    }

    @Test func unplayableVideoIsRemovedQuietly() async throws {
        let (viewModel, container) = try makeViewModel(videoInterval: 4)
        await viewModel.start()
        _ = container
        guard case .video(let card)? = viewModel.items.first(where: { if case .video = $0 { true } else { false } }) else {
            Issue.record("expected a video card")
            return
        }

        viewModel.videoUnplayable(card)

        #expect(!viewModel.items.contains(.video(card)))
    }

    @Test func notInterestedLowersWeightAndRemovesVideo() async throws {
        let (viewModel, container) = try makeViewModel(videoInterval: 4)
        await viewModel.start()
        guard let item = viewModel.items.first(where: { if case .video = $0 { true } else { false } }),
              let topicID = item.topicID else {
            Issue.record("expected a video card")
            return
        }

        viewModel.notInterested(item)

        let weight = TopicPreferencesRepository(context: container.mainContext).weights()[topicID]
        #expect(weight == 0.7)
        #expect(!viewModel.items.contains(item))
    }
}
