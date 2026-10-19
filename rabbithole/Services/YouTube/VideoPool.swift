import Foundation

/// Cached videos of one topic's channels.
nonisolated struct VideoPoolState: Codable, Sendable, Equatable {
    var channels: [YouTubeChannelRef]
    /// Uploads playlist id → token of the next, not yet fetched page.
    var nextPages: [String: String] = [:]
    var videos: [YouTubeVideo] = []
    var rejectedIDs: Set<String> = []
    var refreshedAt: Date
}

nonisolated protocol VideoPoolPersistence: Sendable {
    func load(topicID: String) -> VideoPoolState?
    func save(_ state: VideoPoolState, topicID: String)
}

nonisolated struct FileVideoPoolPersistence: VideoPoolPersistence {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "VideoPools")
    }

    func load(topicID: String) -> VideoPoolState? {
        guard let data = try? Data(contentsOf: url(for: topicID)) else { return nil }
        return try? JSONDecoder().decode(VideoPoolState.self, from: data)
    }

    func save(_ state: VideoPoolState, topicID: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url(for: topicID), options: .atomic)
    }

    private func url(for topicID: String) -> URL {
        directory.appending(path: "\(topicID).json")
    }
}

/// Hands out random playable videos per topic, keeping YouTube API usage and stored data small:
/// - one refresh per topic per `refreshInterval` (≈ 3 quota units per channel),
/// - metadata older than `maxDataAge` is dropped even when a refresh fails,
/// - older playlist pages are fetched only when the cached videos run out.
actor VideoPool {
    private let service: any YouTubeService
    private let persistence: any VideoPoolPersistence
    private let channels: @Sendable (String) -> [YouTubeChannelRef]
    private let now: @Sendable () -> Date
    private let minimumAvailable = 5

    private var states: [String: VideoPoolState] = [:]
    private var refreshes: [String: Task<VideoPoolState, Error>] = [:]

    init(
        service: any YouTubeService,
        persistence: any VideoPoolPersistence,
        channels: @escaping @Sendable (String) -> [YouTubeChannelRef] = { VideoChannelCatalog.channels(for: $0) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.service = service
        self.persistence = persistence
        self.channels = channels
        self.now = now
    }

    /// `nil` when the topic has no channels or no unseen playable video.
    func randomCandidate(for topicID: String, excluding excluded: Set<String>) async throws -> YouTubeVideo? {
        let channels = channels(topicID)
        guard !channels.isEmpty else { return nil }

        var state = try await currentState(topicID: topicID, channels: channels)
        if available(in: state, excluding: excluded).count < minimumAvailable,
           let (playlist, page) = state.nextPages.randomElement() {
            state = try await fetchMore(topicID: topicID, playlist: playlist, page: page, into: state)
        }
        return available(in: state, excluding: excluded).randomElement()
    }

    /// Remembers a video that failed to play so it isn't offered again.
    func reject(videoID: String, topicID: String) {
        guard var state = states[topicID] else { return }
        state.rejectedIDs.insert(videoID)
        state.videos.removeAll { $0.id == videoID }
        store(state, topicID: topicID)
    }

    private func available(in state: VideoPoolState, excluding excluded: Set<String>) -> [YouTubeVideo] {
        state.videos.filter { !excluded.contains($0.id) && !state.rejectedIDs.contains($0.id) }
    }

    private func currentState(topicID: String, channels: [YouTubeChannelRef]) async throws -> VideoPoolState {
        if var state = states[topicID] ?? persistence.load(topicID: topicID), state.channels == channels {
            state.videos.removeAll { now().timeIntervalSince($0.fetchedAt) > YouTubeConfiguration.maxDataAge }
            states[topicID] = state
            if now().timeIntervalSince(state.refreshedAt) < YouTubeConfiguration.refreshInterval {
                return state
            }
            do {
                return try await refresh(topicID: topicID, channels: channels, previous: state)
            } catch {
                // Serve what's still within the data-age limit; drop it entirely otherwise.
                store(state, topicID: topicID)
                if state.videos.isEmpty { throw error }
                return state
            }
        }
        return try await refresh(topicID: topicID, channels: channels, previous: nil)
    }

    /// Concurrent callers for the same topic share one refresh.
    private func refresh(topicID: String, channels: [YouTubeChannelRef], previous: VideoPoolState?) async throws -> VideoPoolState {
        if let running = refreshes[topicID] {
            return try await running.value
        }
        let service = service
        let timestamp = now()
        let task = Task<VideoPoolState, Error> {
            let playlists = try await service.uploadsPlaylists(for: channels)
            var state = VideoPoolState(channels: channels, refreshedAt: timestamp)
            state.rejectedIDs = previous?.rejectedIDs ?? []
            var ids: [String] = []
            for playlist in Set(playlists.values).sorted() {
                let page = try await service.playlistPage(playlist, page: nil)
                ids += page.videoIDs
                state.nextPages[playlist] = page.nextPage
            }
            state.videos = try await service.videos(ids: ids.filter { !state.rejectedIDs.contains($0) }).playable
            return state
        }
        refreshes[topicID] = task
        defer { refreshes[topicID] = nil }
        let state = try await task.value
        store(state, topicID: topicID)
        return state
    }

    private func fetchMore(topicID: String, playlist: String, page: String, into state: VideoPoolState) async throws -> VideoPoolState {
        var state = state
        let next = try await service.playlistPage(playlist, page: page)
        state.nextPages[playlist] = next.nextPage
        let known = Set(state.videos.map(\.id)).union(state.rejectedIDs)
        let newIDs = next.videoIDs.filter { !known.contains($0) }
        if !newIDs.isEmpty {
            state.videos += try await service.videos(ids: newIDs).playable
        }
        // Merge with anything another caller stored meanwhile.
        if let current = states[topicID], current.refreshedAt == state.refreshedAt {
            let currentIDs = Set(current.videos.map(\.id))
            state.videos = current.videos + state.videos.filter { !currentIDs.contains($0.id) }
            state.rejectedIDs.formUnion(current.rejectedIDs)
        }
        store(state, topicID: topicID)
        return state
    }

    private func store(_ state: VideoPoolState, topicID: String) {
        states[topicID] = state
        persistence.save(state, topicID: topicID)
    }
}
