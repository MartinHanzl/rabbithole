import Foundation
import Testing
@testable import rabbithole

struct ActivityNotifierTests {
    private let shareA = UUID(), shareB = UUID()

    private func notice(_ share: UUID, _ kind: ActivityNotice.Kind, minutesAgo: Double) -> ActivityNotice {
        ActivityNotice(id: UUID(), shareID: share, from: "jana", kind: kind, createdAt: .now - minutesAgo * 60)
    }

    @Test func onePerConversationPreferringChallenges() {
        let notices = ActivityNotifier.coalesced([
            notice(shareA, .message(articleTitle: "Mars"), minutesAgo: 1),
            notice(shareA, .challenge(question: "Kolik měsíců má Mars?"), minutesAgo: 5),
            notice(shareB, .message(articleTitle: "Planeta"), minutesAgo: 2),
            notice(shareB, .message(articleTitle: "Planeta"), minutesAgo: 10),
        ])
        #expect(notices.count == 2)
        #expect(notices.first { $0.shareID == shareA }?.kind == .challenge(question: "Kolik měsíců má Mars?"))
        #expect(notices.first { $0.shareID == shareB }.map { Int(Date.now.timeIntervalSince($0.createdAt) / 60) } == 2)
    }

    @Test func notificationTextsKeepMessagesPrivate() {
        let message = notice(shareA, .message(articleTitle: "Mars"), minutesAgo: 0)
        #expect(message.title == "Nová zpráva od jana")
        #expect(message.body == "K článku „Mars“")
        let challenge = notice(shareA, .challenge(question: "Kolik měsíců má Mars?"), minutesAgo: 0)
        #expect(challenge.title == "jana tě vyzývá")
        #expect(challenge.body == "Kolik měsíců má Mars?")
    }
}
