import Foundation
import Testing
@testable import rabbithole

struct FriendshipGroupsTests {
    private let me = UUID()
    private func profile(_ name: String) -> PublicProfile {
        PublicProfile(id: UUID(), nickname: name, avatarPath: nil)
    }
    private func friendship(from requester: UUID, to addressee: UUID, _ status: Friendship.Status,
                            requesterProfile: PublicProfile?, addresseeProfile: PublicProfile?) -> Friendship {
        Friendship(id: UUID(), requesterID: requester, addresseeID: addressee, status: status,
                   createdAt: .now, requester: requesterProfile, addressee: addresseeProfile)
    }

    @Test func splitsByDirectionAndStatus() {
        let mine = profile("ja")
        let bob = profile("bob"), cyril = profile("cyril"), dana = profile("dana")
        let groups = FriendshipGroups(friendships: [
            friendship(from: me, to: bob.id, .accepted, requesterProfile: mine, addresseeProfile: bob),
            friendship(from: me, to: cyril.id, .pending, requesterProfile: mine, addresseeProfile: cyril),
            friendship(from: dana.id, to: me, .pending, requesterProfile: dana, addresseeProfile: mine),
        ], me: me)

        #expect(groups.friends.map(\.profile) == [bob])
        #expect(groups.outgoing.map(\.profile) == [cyril])
        #expect(groups.incoming.map(\.profile) == [dana])
        #expect(groups.relation(to: bob.id) == .friend)
        #expect(groups.relation(to: cyril.id) == .outgoing)
        #expect(groups.relation(to: dana.id) == .incoming)
        #expect(groups.relation(to: UUID()) == .none)
    }

    @Test func friendWhoRequestedMeIsStillAFriend() {
        let eva = profile("eva")
        let groups = FriendshipGroups(friendships: [
            friendship(from: eva.id, to: me, .accepted, requesterProfile: eva, addresseeProfile: nil),
        ], me: me)
        #expect(groups.friends.map(\.profile) == [eva])
    }

    @Test func skipsRowsWithHiddenProfile() {
        let groups = FriendshipGroups(friendships: [
            friendship(from: me, to: UUID(), .accepted, requesterProfile: nil, addresseeProfile: nil),
        ], me: me)
        #expect(groups.friends.isEmpty)
    }

    @Test func friendsSortedByNicknameCaseInsensitively() {
        let names = ["zuzana", "Adam", "bara"]
        let rows = names.map { name in
            let p = profile(name)
            return friendship(from: me, to: p.id, .accepted, requesterProfile: nil, addresseeProfile: p)
        }
        #expect(FriendshipGroups(friendships: rows, me: me).friends.map(\.profile.nickname) == ["Adam", "bara", "zuzana"])
    }
}
