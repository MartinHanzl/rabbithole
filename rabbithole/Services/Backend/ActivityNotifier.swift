import BackgroundTasks
import Foundation
import Supabase
import UserNotifications

/// Something new from a friend, for a local notification or the tab badge.
nonisolated struct ActivityNotice: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case challenge(question: String)
        case message(articleTitle: String)
    }

    let id: UUID
    let shareID: UUID
    let from: String
    let kind: Kind
    let createdAt: Date

    /// Message bodies stay out of notifications (lock screen privacy); challenges show the question.
    var title: String {
        switch kind {
        case .challenge: String(localized: "\(from) tě vyzývá")
        case .message: String(localized: "Nová zpráva od \(from)")
        }
    }

    var body: String {
        switch kind {
        case .challenge(let question): question
        case .message(let title): String(localized: "K článku „\(title)“")
        }
    }
}

/// Free replacement for push notifications (APNs needs a paid Apple Developer account):
/// iOS wakes the app now and then (Background App Refresh); it asks Supabase what's new since the
/// last check and posts local notifications. Delivery can be delayed by hours and isn't guaranteed.
nonisolated struct ActivityNotifier: Sendable {
    static let refreshTaskID = "webpulse.rabbithole.refresh"
    private static let lastCheckKey = "activityLastCheck"

    let client: SupabaseClient
    let me: UUID
    let includeChallenges: Bool

    func notices(since: Date) async throws -> [ActivityNotice] {
        struct MessageRow: Decodable {
            struct Author: Decodable { let nickname: String }
            struct Share: Decodable { let title: String }
            let id: UUID
            let share_id: UUID
            let created_at: Date
            let author: Author?
            let share: Share?
        }
        struct ChallengeRow: Decodable {
            struct Sender: Decodable { let nickname: String }
            let id: UUID
            let share_id: UUID
            let question: String
            let created_at: Date
            let sender: Sender?
        }
        let iso = ISO8601DateFormatter().string(from: since)

        let messages: [MessageRow] = try await client.from("messages")
            .select("id, share_id, created_at, author:profiles!messages_author_id_fkey(nickname), share:shares(title)")
            .neq("author_id", value: me)
            .gt("created_at", value: iso)
            .order("created_at", ascending: false)
            .limit(10)
            .execute()
            .value
        var notices = messages.map {
            ActivityNotice(id: $0.id, shareID: $0.share_id, from: $0.author?.nickname ?? "?",
                           kind: .message(articleTitle: $0.share?.title ?? ""), createdAt: $0.created_at)
        }

        if includeChallenges {
            let challenges: [ChallengeRow] = try await client.from("challenges")
                .select("id, share_id, question, created_at, sender:profiles!challenges_sender_id_fkey(nickname)")
                .eq("recipient_id", value: me)
                .is("answered_at", value: nil)
                .gt("created_at", value: iso)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value
            notices += challenges.map {
                ActivityNotice(id: $0.id, shareID: $0.share_id, from: $0.sender?.nickname ?? "?",
                               kind: .challenge(question: $0.question), createdAt: $0.created_at)
            }
        }
        return Self.coalesced(notices)
    }

    /// One notification per conversation: the newest item, challenges before plain messages.
    static func coalesced(_ notices: [ActivityNotice]) -> [ActivityNotice] {
        var byShare: [UUID: ActivityNotice] = [:]
        for notice in notices.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let existing = byShare[notice.shareID] else {
                byShare[notice.shareID] = notice
                continue
            }
            if case .message = existing.kind, case .challenge = notice.kind {
                byShare[notice.shareID] = notice
            }
        }
        return byShare.values.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Background refresh

    /// Entry point of the background task: check, notify, remember the time, reschedule.
    static func runBackgroundCheck() async {
        scheduleNextRefresh()
        guard let client = BackendClient.shared,
              let session = try? await client.auth.session else { return }
        let defaults = UserDefaults.standard
        let since = defaults.object(forKey: lastCheckKey) as? Date ?? Date.now.addingTimeInterval(-24 * 3600)
        let accepts = (try? await acceptsChallenges(client: client, me: session.user.id)) ?? true
        let notifier = ActivityNotifier(client: client, me: session.user.id, includeChallenges: accepts)
        guard let notices = try? await notifier.notices(since: since) else { return }
        defaults.set(Date.now, forKey: lastCheckKey)

        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        for notice in notices.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            content.threadIdentifier = notice.shareID.uuidString
            content.userInfo = ["shareID": notice.shareID.uuidString]
            try? await center.add(UNNotificationRequest(identifier: notice.id.uuidString, content: content, trigger: nil))
        }
    }

    /// Marks everything up to now as seen, e.g. when the user opens the app.
    static func markChecked() {
        UserDefaults.standard.set(Date.now, forKey: lastCheckKey)
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date.now.addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private static func acceptsChallenges(client: SupabaseClient, me: UUID) async throws -> Bool {
        struct Row: Decodable { let accepts_challenges: Bool }
        let rows: [Row] = try await client.from("profiles").select("accepts_challenges").eq("id", value: me)
            .limit(1).execute().value
        return rows.first?.accepts_challenges ?? true
    }
}
