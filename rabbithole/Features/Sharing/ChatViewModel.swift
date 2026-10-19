import Foundation
import Observation
import Supabase

@Observable
final class ChatViewModel {
    let shareID: UUID
    let service: SharingService
    let friends: FriendsService
    /// `nil` when the viewer turned challenges off – the card is then hidden.
    let challenges: ChallengeService?

    private(set) var challenge: Challenge?
    private(set) var solution: ChallengeSolution?
    private(set) var isAnswering = false
    var challengeError: String?

    private(set) var thread: ShareThread?
    private(set) var messages: [ChatMessage] = []
    private(set) var hasOlder = false
    private(set) var isLoaded = false
    var draft = ""
    private(set) var isSending = false
    var errorMessage: String?

    init(shareID: UUID, service: SharingService, friends: FriendsService, challenges: ChallengeService? = nil) {
        self.shareID = shareID
        self.service = service
        self.friends = friends
        self.challenges = challenges
    }

    var isChallengeRecipient: Bool { challenge?.recipientID == me }

    var challengeResult: ChallengeResult? {
        guard let challenge else { return nil }
        return ChallengeResult(challenge: challenge, solution: solution, viewerIsSender: challenge.senderID == me,
                               otherName: other?.nickname ?? "")
    }

    var me: UUID { service.me }
    var other: PublicProfile? { thread?.other(than: me) }

    var canSend: Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= SharingService.maxMessageLength && !isSending
    }

    /// Loads the thread, then follows new messages until the task is cancelled (screen closed).
    /// Loads the thread, then follows new messages (and challenge answers) until the screen closes.
    /// One realtime channel per open chat, filtered to this share.
    func run() async {
        await load()
        let (channel, inserts) = service.messageInserts(in: shareID)
        let challengeUpdates = challenges?.updates(onShare: shareID, channel: channel)
        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await message in inserts {
                    self.append([message])
                    try? await self.service.markRead(self.shareID)
                }
            }
            if let challengeUpdates {
                group.addTask { @MainActor in
                    for await updated in challengeUpdates {
                        self.challenge = updated
                        await self.loadSolution()
                    }
                }
            }
        }
        await service.client.removeChannel(channel)
    }

    func answerChallenge(optionIndex: Int?, text: String?, beforeReading: Bool) async {
        guard let challenge, let challenges else { return }
        isAnswering = true
        defer { isAnswering = false }
        do {
            try await challenges.answer(challenge.id, optionIndex: optionIndex, text: text, beforeReading: beforeReading)
            self.challenge = try await challenges.challenge(onShare: shareID)
            await loadSolution()
            challengeError = nil
        } catch {
            challengeError = error.localizedDescription
        }
    }

    func reportChallenge(reason: ReportReason, note: String, alsoBlock: Bool) async -> Bool {
        guard let challenge else { return false }
        do {
            try await friends.report(challengeID: challenge.id, reason: reason, note: note)
            if alsoBlock { try await friends.block(challenge.senderID) }
            return true
        } catch {
            challengeError = String(localized: "Nahlášení se nepodařilo odeslat.")
            return false
        }
    }

    private func loadSolution() async {
        guard let challenge, let challenges else { return }
        // RLS returns nothing to the recipient before they answer.
        solution = try? await challenges.solution(for: challenge.id)
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
            if let challenges {
                challenge = try? await challenges.challenge(onShare: shareID)
                await loadSolution()
            }
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
