import Foundation
import Observation

/// Splits friendship rows into what the Friends screen shows. Pure – unit tested.
nonisolated struct FriendshipGroups: Equatable, Sendable {
    struct Entry: Hashable, Identifiable, Sendable {
        let friendship: Friendship
        let profile: PublicProfile
        var id: UUID { friendship.id }
    }

    enum Relation: Equatable, Sendable {
        case none, friend, outgoing, incoming
    }

    var incoming: [Entry] = []
    var outgoing: [Entry] = []
    var friends: [Entry] = []

    init(friendships: [Friendship] = [], me: UUID) {
        for friendship in friendships {
            // A hidden profile (blocked) can't be shown or acted on meaningfully.
            guard let profile = friendship.other(than: me) else { continue }
            let entry = Entry(friendship: friendship, profile: profile)
            switch (friendship.status, friendship.requesterID == me) {
            case (.accepted, _): friends.append(entry)
            case (.pending, true): outgoing.append(entry)
            case (.pending, false): incoming.append(entry)
            }
        }
        friends.sort { $0.profile.nickname.localizedCaseInsensitiveCompare($1.profile.nickname) == .orderedAscending }
    }

    func relation(to userID: UUID) -> Relation {
        if friends.contains(where: { $0.profile.id == userID }) { return .friend }
        if outgoing.contains(where: { $0.profile.id == userID }) { return .outgoing }
        if incoming.contains(where: { $0.profile.id == userID }) { return .incoming }
        return .none
    }

    func entry(for userID: UUID) -> Entry? {
        (incoming + outgoing + friends).first { $0.profile.id == userID }
    }
}

@Observable
final class FriendsViewModel {
    enum Phase: Equatable {
        case loading, loaded, failed
    }

    private(set) var phase: Phase = .loading
    private(set) var groups: FriendshipGroups
    private(set) var searchResults: [PublicProfile] = []
    private(set) var isSearching = false
    var errorMessage: String?

    let service: FriendsService

    init(service: FriendsService) {
        self.service = service
        groups = FriendshipGroups(me: service.me)
    }

    var pendingIncomingCount: Int { groups.incoming.count }

    func load() async {
        do {
            groups = FriendshipGroups(friendships: try await service.friendships(), me: service.me)
            phase = .loaded
        } catch {
            if phase != .loaded { phase = .failed }
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        // Debounce typing; a newer query cancels this task.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searchResults = (try? await service.search(trimmed)) ?? []
    }

    func sendRequest(to profile: PublicProfile) async {
        await perform { try await self.service.sendRequest(to: profile.id) }
    }

    func accept(_ entry: FriendshipGroups.Entry) async {
        await perform { try await self.service.accept(entry.friendship) }
    }

    func remove(_ entry: FriendshipGroups.Entry) async {
        await perform { try await self.service.remove(entry.friendship) }
    }

    func block(_ profile: PublicProfile) async {
        await perform { try await self.service.block(profile.id) }
        searchResults.removeAll { $0.id == profile.id }
    }

    func report(_ profile: PublicProfile, reason: ReportReason, note: String, alsoBlock: Bool) async -> Bool {
        do {
            try await service.report(userID: profile.id, reason: reason, note: note)
        } catch {
            errorMessage = String(localized: "Nahlášení se nepodařilo odeslat.")
            return false
        }
        if alsoBlock { await block(profile) }
        return true
    }

    private func perform(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Akce se nepovedla. Zkontroluj připojení a zkus to znovu.")
        }
        await load()
    }
}
