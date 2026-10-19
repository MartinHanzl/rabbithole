import Foundation

/// Local, explainable personalization. Pure logic – no I/O, randomness is injected.
///
/// - Each topic has a weight (default 1.0). Signals nudge it up or down, clamped to a range.
/// - The next card's topic is drawn at random proportionally to the weights of selected topics.
/// - Every `explorationInterval`-th card comes from a topic the user hasn't selected.
nonisolated struct PersonalizationEngine: Sendable {
    struct Configuration: Sendable {
        var initialWeight = 1.0
        var weightRange: ClosedRange<Double> = 0.1...5.0
        var savedDelta = 0.3
        var longReadDelta = 0.2
        var dismissedDelta = -0.3
        var explorationInterval = 10
        /// Time in the article detail that counts as a "long read".
        var longReadThreshold: TimeInterval = 30
    }

    enum Signal: Sendable {
        case saved
        case longRead
        case dismissed
    }

    struct Pick: Equatable, Sendable {
        let topicID: String
        let isExploration: Bool
    }

    let configuration: Configuration

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    func updatedWeight(_ weight: Double, after signal: Signal) -> Double {
        let delta = switch signal {
        case .saved: configuration.savedDelta
        case .longRead: configuration.longReadDelta
        case .dismissed: configuration.dismissedDelta
        }
        return min(max(weight + delta, configuration.weightRange.lowerBound), configuration.weightRange.upperBound)
    }

    func isLongRead(duration: TimeInterval) -> Bool {
        duration >= configuration.longReadThreshold
    }

    func isExplorationSlot(cardNumber: Int) -> Bool {
        configuration.explorationInterval > 0 && cardNumber > 0 && cardNumber % configuration.explorationInterval == 0
    }

    /// Chooses the topic for the card at 1-based `cardNumber`.
    ///
    /// - Parameters:
    ///   - weights: Weight per topic id; missing topics use `initialWeight`.
    ///   - selected: Topics the user picked. Must not be empty for a non-exploration pick.
    ///   - all: Every known topic id (selected + unselected).
    func pickTopic<R: RandomNumberGenerator>(
        cardNumber: Int,
        selected: Set<String>,
        all: Set<String>,
        weights: [String: Double],
        using rng: inout R
    ) -> Pick? {
        let unselected = all.subtracting(selected)
        if isExplorationSlot(cardNumber: cardNumber), !unselected.isEmpty,
           let topicID = weightedRandom(unselected, weights: weights, using: &rng) {
            return Pick(topicID: topicID, isExploration: true)
        }
        return weightedRandom(selected, weights: weights, using: &rng)
            .map { Pick(topicID: $0, isExploration: false) }
    }

    /// Picks one id with probability proportional to its weight. Iterates in sorted order
    /// so results are reproducible with a seeded generator.
    func weightedRandom<R: RandomNumberGenerator>(
        _ ids: Set<String>,
        weights: [String: Double],
        using rng: inout R
    ) -> String? {
        let ordered = ids.sorted()
        let effective = ordered.map { max(weights[$0] ?? configuration.initialWeight, 0) }
        let total = effective.reduce(0, +)
        guard total > 0 else { return ordered.randomElement(using: &rng) }

        var threshold = Double.random(in: 0..<total, using: &rng)
        for (id, weight) in zip(ordered, effective) {
            if threshold < weight { return id }
            threshold -= weight
        }
        return ordered.last
    }
}
