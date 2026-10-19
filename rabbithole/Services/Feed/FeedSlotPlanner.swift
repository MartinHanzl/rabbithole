import Foundation

/// Decides what each feed position holds. Pure – unit tested.
///
/// - Every `videoInterval`-th card is a video (default 4, 0 = videos off).
/// - The topic comes from `PersonalizationEngine`, including its exploration slots,
///   so a video can also come from an unselected topic.
/// - When no video is available for a slot, the feed falls back to an article.
nonisolated struct FeedSlotPlanner: Sendable {
    enum Kind: Equatable, Sendable {
        case article
        case video
    }

    struct Slot: Equatable, Sendable {
        let cardNumber: Int
        let kind: Kind
        let pick: PersonalizationEngine.Pick
    }

    static let defaultVideoInterval = 4
    /// Choices offered in Settings; 0 turns videos off.
    static let videoIntervalOptions = [0, 3, 4, 6, 10]

    let engine: PersonalizationEngine
    let videoInterval: Int
    let videosAvailable: Bool

    func kind(forCard cardNumber: Int) -> Kind {
        guard videosAvailable, videoInterval > 0, cardNumber > 0 else { return .article }
        return cardNumber % videoInterval == 0 ? .video : .article
    }

    /// Slots for cards `firstCard ..< firstCard + count`. Cards without a topic are skipped.
    func slots<R: RandomNumberGenerator>(
        from firstCard: Int,
        count: Int,
        selected: Set<String>,
        all: Set<String>,
        weights: [String: Double],
        using rng: inout R
    ) -> [Slot] {
        (firstCard..<firstCard + count).compactMap { cardNumber in
            engine.pickTopic(cardNumber: cardNumber, selected: selected, all: all, weights: weights, using: &rng)
                .map { Slot(cardNumber: cardNumber, kind: kind(forCard: cardNumber), pick: $0) }
        }
    }
}
