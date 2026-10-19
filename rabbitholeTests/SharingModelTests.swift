import Foundation
import Testing
@testable import rabbithole

struct SharingModelTests {
    private let me = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let friend = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func threadJSON(lastAuthor: UUID?, lastAt: String, readAt: String?) -> Data {
        let messages = lastAuthor.map {
            #"[{"author_id":"\#($0.uuidString)","body":"Ahoj","created_at":"\#(lastAt)"}]"#
        } ?? "[]"
        let reads = readAt.map { #"[{"last_read_at":"\#($0)"}]"# } ?? "[]"
        return Data("""
        {"id":"aaaaaaaa-0000-0000-0000-000000000001","sender_id":"\(me.uuidString)","recipient_id":"\(friend.uuidString)",
         "page_id":771,"title":"Mars (planeta)","thumbnail_url":null,
         "created_at":"2026-10-19T09:00:00+00:00","last_activity_at":"2026-10-19T09:30:00.613558+00:00",
         "sender":{"id":"\(me.uuidString)","nickname":"alice","avatar_path":null},
         "recipient":{"id":"\(friend.uuidString)","nickname":"bob","avatar_path":null},
         "messages":\(messages),"share_reads":\(reads)}
        """.utf8)
    }

    private func decode(_ data: Data) throws -> ShareThread {
        try BackendJSON.decoder.decode(ShareThread.self, from: data)
    }

    @Test func decodesThreadWithEmbeds() throws {
        let thread = try decode(threadJSON(lastAuthor: friend, lastAt: "2026-10-19T09:30:00.613558+00:00", readAt: nil))
        #expect(thread.title == "Mars (planeta)")
        #expect(thread.other(than: me)?.nickname == "bob")
        #expect(thread.other(than: friend)?.nickname == "alice")
        #expect(thread.lastMessage?.body == "Ahoj")
        #expect(thread.article.articleURL.absoluteString == "https://cs.wikipedia.org/wiki/Mars_(planeta)")
    }

    @Test func unreadWhenFriendWroteAfterMyLastRead() throws {
        let thread = try decode(threadJSON(lastAuthor: friend, lastAt: "2026-10-19T10:00:00+00:00",
                                           readAt: "2026-10-19T09:00:00+00:00"))
        #expect(thread.isUnread(for: me))
    }

    @Test func readWhenILookedAfterTheLastMessage() throws {
        let thread = try decode(threadJSON(lastAuthor: friend, lastAt: "2026-10-19T09:00:00+00:00",
                                           readAt: "2026-10-19T10:00:00+00:00"))
        #expect(!thread.isUnread(for: me))
    }

    @Test func myOwnLastMessageIsNeverUnread() throws {
        let thread = try decode(threadJSON(lastAuthor: me, lastAt: "2026-10-19T10:00:00+00:00", readAt: nil))
        #expect(!thread.isUnread(for: me))
    }

    @Test func neverOpenedThreadWithMessageIsUnread() throws {
        #expect(try decode(threadJSON(lastAuthor: friend, lastAt: "2026-10-19T10:00:00+00:00", readAt: nil)).isUnread(for: me))
        #expect(!(try decode(threadJSON(lastAuthor: nil, lastAt: "", readAt: nil)).isUnread(for: me)))
    }

    @Test(arguments: [
        "2026-10-19T09:33:32.613558+00:00",
        "2026-10-19T09:33:32+00:00",
        "2026-10-19 09:33:32.613558+00",
        "2026-10-19T09:33:32Z",
    ])
    func parsesPostgresTimestamps(_ string: String) throws {
        let date = try #require(BackendJSON.parseDate(string))
        #expect(abs(date.timeIntervalSince1970 - 1_792_402_412) < 1)
    }

    @Test func decodesFriendActivity() throws {
        let json = #"""
        [{"kind":"shared","friend_id":"22222222-2222-2222-2222-222222222222","nickname":"bob","avatar_path":null,
          "page_id":797,"title":"Planeta","thumbnail_url":null,"occurred_at":"2026-10-19T09:00:00+00:00",
          "share_id":"aaaaaaaa-0000-0000-0000-000000000001"},
         {"kind":"saved","friend_id":"22222222-2222-2222-2222-222222222222","nickname":"bob","avatar_path":null,
          "page_id":771,"title":"Mars","thumbnail_url":null,"occurred_at":"2026-10-19T08:00:00+00:00","share_id":null}]
        """#
        let items = try BackendJSON.decoder.decode([FriendActivity].self, from: Data(json.utf8))
        #expect(items.map(\.kind) == [.shared, .saved])
        #expect(items[0].shareID != nil && items[1].shareID == nil)
        #expect(Set(items.map(\.id)).count == 2)
    }
}
