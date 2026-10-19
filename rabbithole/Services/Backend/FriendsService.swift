import Foundation
import Supabase

/// Nickname and avatar of another user – what `search_profiles` and embeds return.
nonisolated struct PublicProfile: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let nickname: String
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case avatarPath = "avatar_path"
    }
}

/// Row of `public.friendships` with both participants embedded.
nonisolated struct Friendship: Decodable, Hashable, Identifiable, Sendable {
    enum Status: String, Decodable, Sendable {
        case pending, accepted
    }

    let id: UUID
    let requesterID: UUID
    let addresseeID: UUID
    let status: Status
    let createdAt: Date
    /// `nil` when RLS hides the profile (e.g. after a block).
    let requester: PublicProfile?
    let addressee: PublicProfile?

    enum CodingKeys: String, CodingKey {
        case id, status, requester, addressee
        case requesterID = "requester_id"
        case addresseeID = "addressee_id"
        case createdAt = "created_at"
    }

    func other(than me: UUID) -> PublicProfile? {
        requesterID == me ? addressee : requester
    }
}

nonisolated struct BlockedUser: Decodable, Hashable, Identifiable, Sendable {
    let blockedID: UUID
    let createdAt: Date
    let blocked: PublicProfile?

    var id: UUID { blockedID }

    enum CodingKeys: String, CodingKey {
        case blocked
        case blockedID = "blocked_id"
        case createdAt = "created_at"
    }
}

nonisolated enum ReportReason: String, CaseIterable, Codable, Sendable, Identifiable {
    case spam, harassment, inappropriate, impersonation, other

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .spam: "Spam"
        case .harassment: "Obtěžování nebo šikana"
        case .inappropriate: "Nevhodný obsah"
        case .impersonation: "Vydává se za někoho jiného"
        case .other: "Jiný důvod"
        }
    }
}

/// Friends, blocking and reporting. All access control lives in RLS; this only shapes requests.
nonisolated struct FriendsService: Sendable {
    let client: SupabaseClient
    let me: UUID

    private static let friendshipColumns = """
        id, requester_id, addressee_id, status, created_at,
        requester:profiles!friendships_requester_id_fkey(id, nickname, avatar_path),
        addressee:profiles!friendships_addressee_id_fkey(id, nickname, avatar_path)
        """

    func search(_ query: String) async throws -> [PublicProfile] {
        try await client.rpc("search_profiles", params: ["query": query]).execute().value
    }

    func friendships() async throws -> [Friendship] {
        try await client.from("friendships")
            .select(Self.friendshipColumns)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func sendRequest(to userID: UUID) async throws {
        struct Row: Encodable {
            let requester_id: UUID
            let addressee_id: UUID
        }
        try await client.from("friendships").insert(Row(requester_id: me, addressee_id: userID)).execute()
    }

    func accept(_ friendship: Friendship) async throws {
        try await client.from("friendships")
            .update(["status": Friendship.Status.accepted.rawValue])
            .eq("id", value: friendship.id)
            .execute()
    }

    /// Declines or cancels a request, or ends a friendship.
    func remove(_ friendship: Friendship) async throws {
        try await client.from("friendships").delete().eq("id", value: friendship.id).execute()
    }

    func blockedUsers() async throws -> [BlockedUser] {
        try await client.from("blocks")
            .select("blocked_id, created_at, blocked:profiles!blocks_blocked_id_fkey(id, nickname, avatar_path)")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Blocking also ends the friendship and pending requests (database trigger).
    func block(_ userID: UUID) async throws {
        struct Row: Encodable {
            let blocker_id: UUID
            let blocked_id: UUID
        }
        try await client.from("blocks").upsert(Row(blocker_id: me, blocked_id: userID), ignoreDuplicates: true).execute()
    }

    func unblock(_ userID: UUID) async throws {
        try await client.from("blocks").delete().eq("blocker_id", value: me).eq("blocked_id", value: userID).execute()
    }

    func report(userID: UUID? = nil, messageID: UUID? = nil, reason: ReportReason, note: String) async throws {
        struct Row: Encodable {
            let reporter_id: UUID
            let reported_user_id: UUID?
            let message_id: UUID?
            let reason: ReportReason
            let note: String?
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.from("reports").insert(Row(
            reporter_id: me, reported_user_id: userID, message_id: messageID,
            reason: reason, note: trimmed.isEmpty ? nil : String(trimmed.prefix(1000))
        )).execute()
    }
}
