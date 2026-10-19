import Testing
@testable import rabbithole

/// Deterministic generator for reproducible weighted draws.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct PersonalizationEngineTests {
    private let engine = PersonalizationEngine()
    private let all: Set<String> = ["a", "b", "c", "d"]

    // MARK: Weights

    @Test func signalsAdjustWeight() {
        #expect(engine.updatedWeight(1.0, after: .saved) == 1.3)
        #expect(engine.updatedWeight(1.0, after: .longRead) == 1.2)
        #expect(engine.updatedWeight(1.0, after: .dismissed) == 0.7)
    }

    @Test func weightIsClampedToRange() {
        #expect(engine.updatedWeight(4.9, after: .saved) == 5.0)
        #expect(engine.updatedWeight(0.2, after: .dismissed) == 0.1)

        var weight = 1.0
        for _ in 0..<100 { weight = engine.updatedWeight(weight, after: .dismissed) }
        #expect(weight == 0.1)
    }

    @Test func longReadThreshold() {
        #expect(!engine.isLongRead(duration: 29.9))
        #expect(engine.isLongRead(duration: 30))
    }

    // MARK: Topic selection

    @Test func picksOnlySelectedTopicsOutsideExplorationSlots() {
        var rng = SeededGenerator(seed: 1)
        for card in 1...9 {
            let pick = engine.pickTopic(cardNumber: card, selected: ["a", "b"], all: all, weights: [:], using: &rng)
            #expect(pick?.isExploration == false)
            #expect(["a", "b"].contains(pick?.topicID))
        }
    }

    @Test func everyTenthCardExploresUnselectedTopic() {
        var rng = SeededGenerator(seed: 2)
        for card in [10, 20, 30] {
            let pick = engine.pickTopic(cardNumber: card, selected: ["a", "b"], all: all, weights: [:], using: &rng)
            #expect(pick?.isExploration == true)
            #expect(["c", "d"].contains(pick?.topicID))
        }
    }

    @Test func explorationFallsBackWhenEverythingSelected() {
        var rng = SeededGenerator(seed: 3)
        let pick = engine.pickTopic(cardNumber: 10, selected: all, all: all, weights: [:], using: &rng)
        #expect(pick?.isExploration == false)
        #expect(pick != nil)
    }

    @Test func noSelectedTopicsReturnsNil() {
        var rng = SeededGenerator(seed: 4)
        #expect(engine.pickTopic(cardNumber: 1, selected: [], all: all, weights: [:], using: &rng) == nil)
    }

    @Test func drawsAreProportionalToWeights() {
        var rng = SeededGenerator(seed: 42)
        var counts: [String: Int] = [:]
        let draws = 20_000
        for _ in 0..<draws {
            let id = engine.weightedRandom(["a", "b"], weights: ["a": 3.0, "b": 1.0], using: &rng)!
            counts[id, default: 0] += 1
        }
        let shareA = Double(counts["a", default: 0]) / Double(draws)
        #expect(abs(shareA - 0.75) < 0.02)
    }

    @Test func missingWeightUsesInitialWeight() {
        var rng = SeededGenerator(seed: 7)
        var counts: [String: Int] = [:]
        for _ in 0..<10_000 {
            counts[engine.weightedRandom(["a", "b"], weights: ["a": 1.0], using: &rng)!, default: 0] += 1
        }
        let shareA = Double(counts["a", default: 0]) / 10_000
        #expect(abs(shareA - 0.5) < 0.03)
    }

    @Test func sameSeedGivesSameSequence() {
        var first = SeededGenerator(seed: 9)
        var second = SeededGenerator(seed: 9)
        let weights = ["a": 2.0, "b": 0.5, "c": 1.0]
        let a = (0..<50).map { _ in engine.weightedRandom(["a", "b", "c"], weights: weights, using: &first) }
        let b = (0..<50).map { _ in engine.weightedRandom(["a", "b", "c"], weights: weights, using: &second) }
        #expect(a == b)
    }

    @Test func explorationIntervalIsConfigurable() {
        let engine = PersonalizationEngine(configuration: .init(explorationInterval: 3))
        #expect((1...9).filter(engine.isExplorationSlot) == [3, 6, 9])

        let disabled = PersonalizationEngine(configuration: .init(explorationInterval: 0))
        #expect((1...30).filter(disabled.isExplorationSlot).isEmpty)
    }
}
