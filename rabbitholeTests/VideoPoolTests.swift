import Foundation
import Testing
@testable import rabbithole

nonisolated final class FakeYouTubeService: YouTubeService, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var playlists: [YouTubeChannelRef: String] = [:]
    /// playlist id → pages of video ids
    var pages: [String: [[String]]] = [:]
    var videos: [String: YouTubeVideo] = [:]
    var error: Error?

    var calls: [String] { lock.withLock { _calls } }
    private func record(_ call: String) { lock.withLock { _calls.append(call) } }

    func uploadsPlaylists(for channels: [YouTubeChannelRef]) async throws -> [YouTubeChannelRef: String] {
        record("channels")
        if let error { throw error }
        return playlists.filter { channels.contains($0.key) }
    }

    func playlistPage(_ playlistID: String, page: String?) async throws -> YouTubePlaylistPage {
        record("playlist:\(playlistID):\(page ?? "first")")
        if let error { throw error }
        let all = pages[playlistID] ?? []
        let index = page.flatMap(Int.init) ?? 0
        guard index < all.count else { return .init(videoIDs: [], nextPage: nil) }
        return .init(videoIDs: all[index], nextPage: index + 1 < all.count ? String(index + 1) : nil)
    }

    var searchIDs: [String] = []
    func searchVideoIDs(_ query: String) async throws -> [String] {
        record("search:\(query)")
        if let error { throw error }
        return searchIDs
    }

    func videos(ids: [String]) async throws -> (playable: [YouTubeVideo], returned: Set<String>) {
        record("videos:\(ids.count)")
        if let error { throw error }
        return (ids.compactMap { videos[$0] }, Set(ids.filter { videos[$0] != nil }))
    }
}

nonisolated final class InMemoryVideoPoolPersistence: VideoPoolPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [String: VideoPoolState] = [:]
    func load(topicID: String) -> VideoPoolState? { lock.withLock { states[topicID] } }
    func save(_ state: VideoPoolState, topicID: String) { lock.withLock { states[topicID] = state } }
}

nonisolated final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date { lock.withLock { _now } }
    func advance(_ interval: TimeInterval) { lock.withLock { _now += interval } }
}

struct VideoPoolTests {
    private let channel = YouTubeChannelRef.handle("@kanal")
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func video(_ id: String, fetchedAt: Date) -> YouTubeVideo {
        YouTubeVideo(id: id, title: id, channelTitle: "Kanál", duration: 300, thumbnailURL: nil, fetchedAt: fetchedAt)
    }

    private func makeService(ids: [[String]], fetchedAt: Date) -> FakeYouTubeService {
        let service = FakeYouTubeService()
        service.playlists = [channel: "UU1"]
        service.pages = ["UU1": ids]
        for id in ids.flatMap({ $0 }) { service.videos[id] = video(id, fetchedAt: fetchedAt) }
        return service
    }

    private func makePool(_ service: FakeYouTubeService, clock: TestClock,
                          persistence: InMemoryVideoPoolPersistence = .init(),
                          channels: [YouTubeChannelRef]? = nil) -> VideoPool {
        let list = channels ?? [channel]
        return VideoPool(service: service, persistence: persistence, channels: { _ in list }, now: { clock.now })
    }

    @Test func topicWithoutChannelsMakesNoRequests() async throws {
        let service = FakeYouTubeService()
        let pool = makePool(service, clock: TestClock(start), channels: [])

        #expect(try await pool.randomCandidate(for: "space", excluding: []) == nil)
        #expect(service.calls.isEmpty)
    }

    @Test func firstCallResolvesUploadsAndFetchesFirstPage() async throws {
        let service = makeService(ids: [["a", "b", "c", "d", "e", "f"]], fetchedAt: start)
        let pool = makePool(service, clock: TestClock(start))

        let candidate = try await pool.randomCandidate(for: "space", excluding: [])

        #expect(candidate != nil)
        #expect(service.calls == ["channels", "playlist:UU1:first", "videos:6"])
    }

    @Test func reusesCacheWithinRefreshInterval() async throws {
        let clock = TestClock(start)
        let service = makeService(ids: [["a", "b", "c", "d", "e", "f"]], fetchedAt: start)
        let pool = makePool(service, clock: clock)

        _ = try await pool.randomCandidate(for: "space", excluding: [])
        clock.advance(23 * 3600)
        _ = try await pool.randomCandidate(for: "space", excluding: [])

        #expect(service.calls.filter { $0 == "channels" }.count == 1)
    }

    @Test func refreshesAfterADay() async throws {
        let clock = TestClock(start)
        let service = makeService(ids: [["a", "b", "c", "d", "e", "f"]], fetchedAt: start)
        let pool = makePool(service, clock: clock)

        _ = try await pool.randomCandidate(for: "space", excluding: [])
        clock.advance(25 * 3600)
        _ = try await pool.randomCandidate(for: "space", excluding: [])

        #expect(service.calls.filter { $0 == "channels" }.count == 2)
    }

    @Test func servesCachedVideosWhenRefreshFailsWithinDataAge() async throws {
        let clock = TestClock(start)
        let service = makeService(ids: [["a", "b", "c", "d", "e", "f"]], fetchedAt: start)
        let pool = makePool(service, clock: clock)
        _ = try await pool.randomCandidate(for: "space", excluding: [])

        clock.advance(2 * 24 * 3600)
        service.error = YouTubeError.offline

        #expect(try await pool.randomCandidate(for: "space", excluding: []) != nil)
    }

    @Test func dropsMetadataOlderThanThirtyDaysEvenWhenOffline() async throws {
        let clock = TestClock(start)
        let persistence = InMemoryVideoPoolPersistence()
        let service = makeService(ids: [["a", "b", "c", "d", "e", "f"]], fetchedAt: start)
        _ = try await makePool(service, clock: clock, persistence: persistence).randomCandidate(for: "space", excluding: [])

        clock.advance(31 * 24 * 3600)
        service.error = YouTubeError.offline
        let pool = makePool(service, clock: clock, persistence: persistence)

        await #expect(throws: YouTubeError.offline) {
            try await pool.randomCandidate(for: "space", excluding: [])
        }
        #expect(persistence.load(topicID: "space")?.videos.isEmpty == true)
    }

    @Test func excludesSeenAndRejectedVideos() async throws {
        let service = makeService(ids: [["a", "b", "c"]], fetchedAt: start)
        let pool = makePool(service, clock: TestClock(start))

        _ = try await pool.randomCandidate(for: "space", excluding: [])
        await pool.reject(videoID: "c", topicID: "space")

        #expect(try await pool.randomCandidate(for: "space", excluding: ["a"])?.id == "b")
        #expect(try await pool.randomCandidate(for: "space", excluding: ["a", "b"]) == nil)
    }

    @Test func fetchesOlderPageWhenRunningLow() async throws {
        let service = makeService(ids: [["a", "b"], ["c", "d"]], fetchedAt: start)
        let pool = makePool(service, clock: TestClock(start))

        let candidate = try await pool.randomCandidate(for: "space", excluding: ["a", "b"])

        #expect(["c", "d"].contains(candidate?.id))
        #expect(service.calls.contains("playlist:UU1:1"))
    }

    @Test func rebuildsWhenChannelsChange() async throws {
        let clock = TestClock(start)
        let persistence = InMemoryVideoPoolPersistence()
        let service = makeService(ids: [["a", "b", "c", "d", "e", "f"]], fetchedAt: start)
        _ = try await makePool(service, clock: clock, persistence: persistence).randomCandidate(for: "space", excluding: [])

        let other = YouTubeChannelRef.id("UC2")
        service.playlists[other] = "UU2"
        service.pages["UU2"] = [["x", "y", "z", "q", "w"]]
        for id in ["x", "y", "z", "q", "w"] { service.videos[id] = video(id, fetchedAt: start) }
        let candidate = try await makePool(service, clock: clock, persistence: persistence, channels: [other])
            .randomCandidate(for: "space", excluding: [])

        #expect(["x", "y", "z", "q", "w"].contains(candidate?.id))
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let service = makeService(ids: [["a", "b", "c", "d", "e", "f"]], fetchedAt: start)
        let pool = makePool(service, clock: TestClock(start))

        async let first = pool.randomCandidate(for: "space", excluding: [])
        async let second = pool.randomCandidate(for: "space", excluding: [])
        _ = try await (first, second)

        #expect(service.calls.filter { $0 == "channels" }.count == 1)
    }
}
