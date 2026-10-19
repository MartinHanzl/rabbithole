import Foundation
import Supabase

/// A shared article between two friends; its messages form the chat.
nonisolated struct ShareThread: Decodable, Hashable, Identifiable, Sendable {
    struct LastMessage: Decodable, Hashable, Sendable {
        let authorID: UUID
        let body: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case body
            case authorID = "author_id"
            case createdAt = "created_at"
        }
    }

    struct ReadState: Decodable, Hashable, Sendable {
        let lastReadAt: Date
        enum CodingKeys: String, CodingKey { case lastReadAt = "last_read_at" }
    }

    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let pageID: Int
    let title: String
    let thumbnailURL: URL?
    let createdAt: Date
    let lastActivityAt: Date
    let sender: PublicProfile?
    let recipient: PublicProfile?
    /// Latest message only (embedded with limit 1).
    let messages: [LastMessage]
    /// My read state only – RLS returns just the caller's row.
    let reads: [ReadState]

    enum CodingKeys: String, CodingKey {
        case id, title, sender, recipient, messages
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case pageID = "page_id"
        case thumbnailURL = "thumbnail_url"
        case createdAt = "created_at"
        case lastActivityAt = "last_activity_at"
        case reads = "share_reads"
    }

    func other(than me: UUID) -> PublicProfile? {
        senderID == me ? recipient : sender
    }

    var lastMessage: LastMessage? { messages.first }

    /// Unread when the latest message is from the other person and newer than my last read.
    func isUnread(for me: UUID) -> Bool {
        guard let last = lastMessage, last.authorID != me else { return false }
        guard let read = reads.first?.lastReadAt else { return true }
        return last.createdAt > read
    }

    var article: ArticleSummary {
        ArticleSummary(
            pageID: pageID, title: title, extract: "", description: nil, type: .standard,
            articleURL: WikipediaURLs.article(title: title), thumbnailURL: thumbnailURL,
            imageFileTitle: nil
        )
    }
}

nonisolated struct ChatMessage: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let shareID: UUID
    let authorID: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case shareID = "share_id"
        case authorID = "author_id"
        case createdAt = "created_at"
    }
}

/// Row of `friend_activity`: an article a friend saved (opt-in) or shared with me.
nonisolated struct FriendActivity: Decodable, Hashable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case saved, shared
    }

    let kind: Kind
    let friendID: UUID
    let nickname: String
    let pageID: Int
    let title: String
    let thumbnailURL: URL?
    let occurredAt: Date
    let shareID: UUID?

    var id: String { "\(kind.rawValue)-\(friendID)-\(pageID)-\(shareID?.uuidString ?? "")" }

    enum CodingKeys: String, CodingKey {
        case kind, nickname, title
        case friendID = "friend_id"
        case pageID = "page_id"
        case thumbnailURL = "thumbnail_url"
        case occurredAt = "occurred_at"
        case shareID = "share_id"
    }

    var article: ArticleSummary {
        ArticleSummary(
            pageID: pageID, title: title, extract: "", description: nil, type: .standard,
            articleURL: WikipediaURLs.article(title: title), thumbnailURL: thumbnailURL,
            imageFileTitle: nil
        )
    }
}

/// Sharing articles, the per-article chat and the "From friends" feed.
/// Lists are paginated; realtime is used only for the chat that is open.
nonisolated struct SharingService: Sendable {
    let client: SupabaseClient
    let me: UUID

    static let pageSize = 20
    static let messagePageSize = 50
    static let maxMessageLength = 1000

    private static let threadColumns = """
        id, sender_id, recipient_id, page_id, title, thumbnail_url, created_at, last_activity_at,
        sender:profiles!shares_sender_id_fkey(id, nickname, avatar_path),
        recipient:profiles!shares_recipient_id_fkey(id, nickname, avatar_path),
        messages(author_id, body, created_at),
        share_reads(last_read_at)
        """

    /// Creates the share and, if given, its first message.
    @discardableResult
    func share(_ article: ArticleSummary, with friendID: UUID, message: String) async throws -> UUID {
        struct Row: Encodable {
            let sender_id: UUID
            let recipient_id: UUID
            let page_id: Int
            let title: String
            let thumbnail_url: URL?
        }
        struct Created: Decodable { let id: UUID }
        let created: Created = try await client.from("shares")
            .insert(Row(sender_id: me, recipient_id: friendID, page_id: article.pageID,
                        title: String(article.title.prefix(300)), thumbnail_url: article.thumbnailURL))
            .select("id")
            .single()
            .execute()
            .value
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            try await send(text, in: created.id)
        }
        return created.id
    }

    /// Conversations, most recently active first.
    func threads(page: Int) async throws -> [ShareThread] {
        let from = page * Self.pageSize
        return try await client.from("shares")
            .select(Self.threadColumns)
            .order("last_activity_at", ascending: false)
            .order("created_at", ascending: false, referencedTable: "messages")
            .limit(1, referencedTable: "messages")
            .range(from: from, to: from + Self.pageSize - 1)
            .execute()
            .value
    }

    func thread(id: UUID) async throws -> ShareThread {
        try await client.from("shares")
            .select(Self.threadColumns)
            .eq("id", value: id)
            .order("created_at", ascending: false, referencedTable: "messages")
            .limit(1, referencedTable: "messages")
            .single()
            .execute()
            .value
    }

    /// Messages oldest first; `before` pages back in time.
    func messages(in shareID: UUID, before: Date? = nil) async throws -> [ChatMessage] {
        var query = client.from("messages")
            .select("id, share_id, author_id, body, created_at")
            .eq("share_id", value: shareID)
        if let before {
            query = query.lt("created_at", value: before)
        }
        let newestFirst: [ChatMessage] = try await query
            .order("created_at", ascending: false)
            .limit(Self.messagePageSize)
            .execute()
            .value
        return newestFirst.reversed()
    }

    func send(_ body: String, in shareID: UUID) async throws {
        struct Row: Encodable {
            let share_id: UUID
            let author_id: UUID
            let body: String
        }
        let text = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxMessageLength))
        guard !text.isEmpty else { return }
        try await client.from("messages").insert(Row(share_id: shareID, author_id: me, body: text)).execute()
    }

    func deleteMessage(_ id: UUID) async throws {
        try await client.from("messages").delete().eq("id", value: id).execute()
    }

    func markRead(_ shareID: UUID) async throws {
        struct Row: Encodable {
            let share_id: UUID
            let user_id: UUID
            let last_read_at: Date
        }
        try await client.from("share_reads")
            .upsert(Row(share_id: shareID, user_id: me, last_read_at: .now), onConflict: "share_id,user_id")
            .execute()
    }

    func activity(page: Int) async throws -> [FriendActivity] {
        let from = page * Self.pageSize
        return try await client.from("friend_activity")
            .select()
            .order("occurred_at", ascending: false)
            .range(from: from, to: from + Self.pageSize - 1)
            .execute()
            .value
    }

    /// New messages in one thread while its chat is open.
    func messageInserts(in shareID: UUID) -> (channel: RealtimeChannelV2, stream: AsyncStream<ChatMessage>) {
        let channel = client.channel("share-\(shareID.uuidString)")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages",
                                             filter: .eq("share_id", value: shareID))
        let stream = AsyncStream<ChatMessage> { continuation in
            let task = Task {
                for await insert in inserts {
                    if let message = try? insert.decodeRecord(as: ChatMessage.self, decoder: BackendJSON.decoder) {
                        continuation.yield(message)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (channel, stream)
    }

    // MARK: Saved articles visible to friends (opt-in)

    func upsertSaved(_ article: ArticleSummary, savedAt: Date) async throws {
        struct Row: Encodable {
            let user_id: UUID
            let page_id: Int
            let title: String
            let thumbnail_url: URL?
            let saved_at: Date
        }
        try await client.from("saved_articles")
            .upsert(Row(user_id: me, page_id: article.pageID, title: String(article.title.prefix(300)),
                        thumbnail_url: article.thumbnailURL, saved_at: savedAt),
                    onConflict: "user_id,page_id", ignoreDuplicates: true)
            .execute()
    }

    func removeSaved(pageID: Int) async throws {
        try await client.from("saved_articles").delete().eq("user_id", value: me).eq("page_id", value: pageID).execute()
    }

    func removeAllSaved() async throws {
        try await client.from("saved_articles").delete().eq("user_id", value: me).execute()
    }
}

/// Decoding for realtime payloads (Postgres timestamps with fractional seconds and offset).
nonisolated enum BackendJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(string)"))
        }
        return decoder
    }()

    static func parseDate(_ string: String) -> Date? {
        let normalized = string.replacingOccurrences(of: " ", with: "T")
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime],
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: normalized) { return date }
        }
        return nil
    }
}
