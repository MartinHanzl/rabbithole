import AuthenticationServices
import Foundation
import Observation
import Supabase

/// Account state for the whole app. Social features appear only in `.signedIn`.
@Observable
final class AuthService {
    enum State: Equatable {
        /// Built without `Secrets.xcconfig` – accounts are hidden entirely.
        case unavailable
        case loading
        case signedOut
        /// Signed in, but no profile yet (first sign-in) – nickname must be chosen.
        case needsProfile(userID: UUID)
        case signedIn(Profile)
        /// Signed in, but the profile couldn't be loaded (e.g. offline).
        case profileUnavailable(userID: UUID)
    }

    enum AuthError: LocalizedError, Equatable {
        case nicknameTaken
        case offline
        case failed

        var errorDescription: String? {
            switch self {
            case .nicknameTaken: String(localized: "Tahle přezdívka už je obsazená.")
            case .offline: String(localized: "Nejsi připojený k internetu.")
            case .failed: String(localized: "Něco se nepovedlo. Zkus to prosím znovu.")
            }
        }
    }

    private(set) var state: State
    private let client: SupabaseClient?

    init(client: SupabaseClient? = BackendClient.shared) {
        self.client = client
        state = client == nil ? .unavailable : .loading
    }

    var profile: Profile? {
        if case .signedIn(let profile) = state { profile } else { nil }
    }

    /// Friends API for the signed-in user with a profile.
    var friendsService: FriendsService? {
        guard let client, let profile else { return nil }
        return FriendsService(client: client, me: profile.id)
    }

    /// Sharing and chat API for the signed-in user with a profile.
    var sharingService: SharingService? {
        guard let client, let profile else { return nil }
        return SharingService(client: client, me: profile.id)
    }

    /// Challenges API; `nil` when signed out or when the user turned challenges off.
    var challengeService: ChallengeService? {
        guard let client, let profile, profile.acceptsChallenges else { return nil }
        return ChallengeService(client: client, me: profile.id)
    }

    func setAcceptsChallenges(_ value: Bool) async throws {
        guard let client, var profile else { return }
        do {
            try await client.from("profiles")
                .update(["accepts_challenges": value])
                .eq("id", value: profile.id)
                .execute()
        } catch {
            throw Self.map(error)
        }
        profile.acceptsChallenges = value
        state = .signedIn(profile)
    }

    /// Unread conversations (first page) plus unanswered challenges – for the tab badge.
    func activityBadgeCount() async -> Int {
        guard let sharing = sharingService else { return 0 }
        let unread = ((try? await sharing.threads(page: 0)) ?? []).filter { $0.isUnread(for: sharing.me) }
        var pendingChallenges = 0
        if let client, challengeService != nil {
            struct Row: Decodable { let share_id: UUID }
            let rows: [Row] = (try? await client.from("challenges").select("share_id")
                .eq("recipient_id", value: sharing.me).is("answered_at", value: nil)
                .limit(50).execute().value) ?? []
            // A challenge in an already unread thread counts once.
            let unreadIDs = Set(unread.map(\.id))
            pendingChallenges = rows.filter { !unreadIDs.contains($0.share_id) }.count
        }
        return unread.count + pendingChallenges
    }

    /// Mirrors local saves to the server while the user lets friends see them.
    func observeSavedArticleChanges() async {
        for await notification in NotificationCenter.default.notifications(named: .savedArticleChanged) {
            guard let change = notification.object as? SavedArticleChange,
                  let sharing = sharingService, profile?.shareSavedWithFriends == true else { continue }
            switch change {
            case .saved(let article, let savedAt): try? await sharing.upsertSaved(article, savedAt: savedAt)
            case .removed(let pageID): try? await sharing.removeSaved(pageID: pageID)
            }
        }
    }

    private var userID: UUID? {
        switch state {
        case .needsProfile(let id), .profileUnavailable(let id): id
        case .signedIn(let profile): profile.id
        default: nil
        }
    }

    /// Follows auth events for the app's lifetime. Call once from the root view's `.task`.
    func observeAuthChanges() async {
        guard let client else { return }
        for await (event, session) in client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .userUpdated, .tokenRefreshed:
                guard let session else {
                    state = .signedOut
                    continue
                }
                // An expired stored session is refreshed automatically; wait for that event.
                if session.isExpired { continue }
                if event == .tokenRefreshed, userID == session.user.id, case .signedIn = state { continue }
                await loadProfile(userID: session.user.id)
            case .signedOut, .userDeleted:
                state = .signedOut
            default:
                break
            }
        }
    }

    // MARK: Sign-in

    func signInWithGoogle() async throws {
        guard let client else { return }
        do {
            try await client.auth.signInWithOAuth(provider: .google, redirectTo: BackendConfiguration.authRedirectURL)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            throw Self.map(error)
        }
    }

    /// Sends a sign-in email. With the default Supabase template it contains a link that opens
    /// the app via `rabbithole://auth-callback`; with custom SMTP templates also a 6-digit code.
    func sendEmailSignIn(to email: String) async throws {
        guard let client else { return }
        do {
            try await client.auth.signInWithOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                redirectTo: BackendConfiguration.authRedirectURL,
                shouldCreateUser: true
            )
        } catch {
            throw Self.map(error)
        }
    }

    func verifyEmailCode(email: String, code: String) async throws {
        guard let client else { return }
        do {
            try await client.auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                token: code.trimmingCharacters(in: .whitespacesAndNewlines),
                type: .email
            )
        } catch {
            throw Self.map(error)
        }
    }

    /// Handles the email-link and OAuth callbacks (`rabbithole://auth-callback…`).
    func handle(url: URL) async {
        guard let client, url.scheme == BackendConfiguration.authRedirectURL.scheme else { return }
        _ = try? await client.auth.session(from: url)
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut(scope: .local)
        state = .signedOut
    }

    /// Permanently deletes the account and all its server data (Edge Function `delete-account`).
    /// Local data – topics, saved articles, reading history – stays on the device.
    func deleteAccount() async throws {
        guard let client else { return }
        do {
            try await client.functions.invoke("delete-account")
        } catch {
            throw Self.map(error)
        }
        // The session belongs to a deleted user now; drop it locally.
        try? await client.auth.signOut(scope: .local)
        state = .signedOut
    }

    // MARK: Profile

    func retryLoadingProfile() async {
        guard let userID else { return }
        await loadProfile(userID: userID)
    }

    func createProfile(nickname: String, shareSavedWithFriends: Bool, topicIDs: Set<String>,
                       localSaved: [(ArticleSummary, Date)] = []) async throws {
        guard let client, let userID else { return }
        let profile = Profile(
            id: userID,
            nickname: NicknameValidator.normalized(nickname),
            avatarPath: nil,
            shareSavedWithFriends: shareSavedWithFriends
        )
        do {
            try await client.from("profiles").insert(profile).execute()
        } catch {
            throw Self.map(error)
        }
        state = .signedIn(profile)
        try? await syncTopics(topicIDs)
        if shareSavedWithFriends, let sharing = sharingService {
            for (article, savedAt) in localSaved {
                try? await sharing.upsertSaved(article, savedAt: savedAt)
            }
        }
    }

    /// Turning sharing on uploads `localSaved`; turning it off deletes the server copies.
    func setShareSavedWithFriends(_ value: Bool, localSaved: [(ArticleSummary, Date)] = []) async throws {
        guard let client, var profile else { return }
        do {
            try await client.from("profiles")
                .update(["share_saved_with_friends": value])
                .eq("id", value: profile.id)
                .execute()
        } catch {
            throw Self.map(error)
        }
        profile.shareSavedWithFriends = value
        state = .signedIn(profile)
        guard let sharing = sharingService else { return }
        if value {
            for (article, savedAt) in localSaved {
                try? await sharing.upsertSaved(article, savedAt: savedAt)
            }
        } else {
            try? await sharing.removeAllSaved()
        }
    }

    /// Replaces the account's topics with the locally selected ones.
    func syncTopics(_ topicIDs: Set<String>) async throws {
        guard let client, let profile else { return }
        struct Row: Encodable {
            let user_id: UUID
            let topic_id: String
        }
        try await client.from("user_topics").delete().eq("user_id", value: profile.id).execute()
        let rows = topicIDs.sorted().map { Row(user_id: profile.id, topic_id: $0) }
        if !rows.isEmpty {
            try await client.from("user_topics").insert(rows).execute()
        }
    }

    private func loadProfile(userID: UUID) async {
        guard let client else { return }
        do {
            let rows: [Profile] = try await client.from("profiles")
                .select("id, nickname, avatar_path, share_saved_with_friends, accepts_challenges")
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value
            state = rows.first.map(State.signedIn) ?? .needsProfile(userID: userID)
        } catch {
            state = .profileUnavailable(userID: userID)
        }
    }

    private static func map(_ error: Error) -> AuthError {
        if let error = error as? PostgrestError, error.code == "23505" { return .nicknameTaken }
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
            return .offline
        }
        return .failed
    }
}
