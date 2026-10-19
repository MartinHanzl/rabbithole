import Foundation
import Observation
import Supabase

@Observable
final class ChatViewModel {
    let shareID: UUID
    let service: SharingService
    let friends: FriendsService

    private(set) var thread: ShareThread?
    private(set) var messages: [ChatMessage] = []
    private(set) var hasOlder = false
    private(set) var isLoaded = false
    var draft = ""
    private(set) var isSending = false
    var errorMessage: String?

    init(shareID: UUID, service: SharingService, friends: FriendsService) {
        self.shareID = shareID
        self.service = service
        self.friends = friends
    }

    var me: UUID { service.me }
    var other: PublicProfile? { thread?.other(than: me) }

    var canSend: Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= SharingService.maxMessageLength && !isSending
    }

    /// Loads the thread, then follows new messages until the task is cancelled (screen closed).
    func run() async {
        await load()
        let (channel, inserts) = service.messageInserts(in: shareID)
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        for await message in inserts {
            append([message])
            try? await service.markRead(shareID)
        }
        await service.client.removeChannel(channel)
    }

    func load() async {
        do {
            async let thread = service.thread(id: shareID)
            async let latest = service.messages(in: shareID)
            self.thread = try await thread
            let page = try await latest
            messages = page
            hasOlder = page.count == SharingService.messagePageSize
            errorMessage = nil
            try? await service.markRead(shareID)
        } catch {
            errorMessage = String(localized: "Konverzaci se nepodařilo načíst.")
        }
        isLoaded = true
    }

    func loadOlder() async {
        guard let oldest = messages.first?.createdAt else { return }
        guard let page = try? await service.messages(in: shareID, before: oldest) else { return }
        hasOlder = page.count == SharingService.messagePageSize
        messages = page + messages
    }

    func send() async {
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await service.send(draft, in: shareID)
            draft = ""
            errorMessage = nil
            // Realtime usually delivers it too; fetching keeps the chat right if it doesn't.
            append(try await service.messages(in: shareID))
        } catch {
            errorMessage = String(localized: "Zprávu se nepodařilo odeslat. Možná už nejste přátelé.")
        }
    }

    func delete(_ message: ChatMessage) async {
        do {
            try await service.deleteMessage(message.id)
            messages.removeAll { $0.id == message.id }
        } catch {
            errorMessage = String(localized: "Zprávu se nepodařilo smazat.")
        }
    }

    func report(_ message: ChatMessage, reason: ReportReason, note: String, alsoBlock: Bool) async -> Bool {
        do {
            try await friends.report(messageID: message.id, reason: reason, note: note)
            if alsoBlock { try await friends.block(message.authorID) }
            return true
        } catch {
            errorMessage = String(localized: "Nahlášení se nepodařilo odeslat.")
            return false
        }
    }

    func blockOther() async {
        guard let other else { return }
        do {
            try await friends.block(other.id)
            errorMessage = String(localized: "Uživatel je zablokovaný. Do konverzace už nelze psát.")
        } catch {
            errorMessage = String(localized: "Zablokování se nepovedlo.")
        }
    }

    private func append(_ new: [ChatMessage]) {
        let known = Set(messages.map(\.id))
        messages += new.filter { !known.contains($0.id) }
        messages.sort { $0.createdAt < $1.createdAt }
    }
}
