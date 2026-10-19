import Foundation
import Testing
@testable import rabbithole

/// Fixtures `yt_*.json` are hand-written from the YouTube Data API v3 reference
/// (no API key was available when they were made). Replace with captured responses when possible.
struct YouTubeParserTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func parsesUploadsPlaylists() throws {
        let playlists = try YouTubeParser.uploadsPlaylists(from: Fixtures.data("yt_channels"))
        #expect(playlists == [
            "UCaaaaaaaaaaaaaaaaaaaaaa": "UUaaaaaaaaaaaaaaaaaaaaaa",
            "UCbbbbbbbbbbbbbbbbbbbbbb": "UUbbbbbbbbbbbbbbbbbbbbbb",
        ])
    }

    @Test func unknownChannelGivesNoItems() throws {
        let json = #"{"kind":"youtube#channelListResponse","pageInfo":{"totalResults":0,"resultsPerPage":5}}"#
        #expect(try YouTubeParser.uploadsPlaylists(from: Data(json.utf8)).isEmpty)
    }

    @Test func parsesPlaylistPageSkippingPrivateItems() throws {
        let page = try YouTubeParser.playlistPage(from: Fixtures.data("yt_playlistitems"))
        #expect(page.videoIDs == ["vid00000001", "vid00000003"])
        #expect(page.nextPage == "EAAaBlBUOkNESQ")
    }

    @Test func keepsOnlyPlayableVideos() throws {
        let videos = try YouTubeParser.playableVideos(from: Fixtures.data("yt_videos"), fetchedAt: now)

        #expect(videos.map(\.id) == ["vid00000001", "vid00000010"])
        let mars = try #require(videos.first)
        #expect(mars.title == "Proč je Mars červený?")
        #expect(mars.channelTitle == "Vědecký kanál")
        #expect(mars.duration == 501)
        #expect(mars.formattedDuration == "8:21")
        #expect(mars.thumbnailURL?.absoluteString == "https://i.ytimg.com/vi/vid00000001/hqdefault.jpg")
        #expect(mars.watchURL.absoluteString == "https://www.youtube.com/watch?v=vid00000001")
        #expect(mars.fetchedAt == now)
    }

    @Test func durationRangeIsConfigurable() throws {
        let videos = try YouTubeParser.playableVideos(
            from: Fixtures.data("yt_videos"), durationRange: 30...4000, fetchedAt: now
        )
        #expect(videos.map(\.id) == ["vid00000001", "vid00000004", "vid00000005", "vid00000010"])
    }

    @Test func returnedIDsIncludeUnplayableVideos() throws {
        let ids = try YouTubeParser.returnedVideoIDs(from: Fixtures.data("yt_videos"))
        #expect(ids.count == 9)
        #expect(ids.contains("vid00000003"))
    }

    @Test func mapsQuotaError() throws {
        #expect(YouTubeParser.error(from: try Fixtures.data("yt_error_quota"), status: 403) == .quotaExceeded)
    }

    @Test func mapsInvalidKeyAndUnknownErrors() {
        let keyInvalid = #"{"error":{"code":400,"errors":[{"reason":"keyInvalid"}]}}"#
        #expect(YouTubeParser.error(from: Data(keyInvalid.utf8), status: 400) == .invalidKey)
        #expect(YouTubeParser.error(from: Data("oops".utf8), status: 500) == .http(status: 500, reason: nil))
    }

    @Test(arguments: [
        ("PT8M21S", 501.0), ("PT45S", 45), ("PT1H2M", 3720), ("PT1H0M5S", 3605),
        ("P1DT2H", 93600), ("PT0S", 0), ("P0D", 0), ("PT1.5S", 1.5),
    ])
    func parsesDurations(input: String, seconds: Double) {
        #expect(YouTubeParser.duration(fromISO8601: input) == seconds)
    }

    @Test(arguments: ["", "8M21S", "PT", "PT5", "PTM", "PT5X", "P5H"])
    func rejectsInvalidDurations(input: String) {
        #expect(YouTubeParser.duration(fromISO8601: input) == nil)
    }

    @Test func formatsLongDurations() {
        let video = YouTubeVideo(id: "x", title: "", channelTitle: "", duration: 3725, thumbnailURL: nil, fetchedAt: now)
        #expect(video.formattedDuration == "1:02:05")
    }
}
