import Foundation
import Testing
@testable import rabbithole

struct ChallengeDraftTests {
    private func draft(_ question: String = "Kolik měsíců má Mars?",
                       correct: String = "Dva", wrong: [String] = ["Jeden", "Žádný"]) -> ChallengeDraft {
        var draft = ChallengeDraft()
        draft.question = question
        draft.correctAnswer = correct
        draft.wrongAnswers = wrong
        return draft
    }

    @Test func validMultipleChoice() {
        #expect(draft().isValid)
    }

    @Test func questionLimits() {
        #expect(draft("   ").problem == .questionEmpty)
        #expect(draft(String(repeating: "x", count: 200)).isValid)
        #expect(draft(String(repeating: "x", count: 201)).problem == .questionTooLong)
    }

    @Test func optionLimits() {
        #expect(draft(wrong: ["Jeden", " "]).problem == .optionEmpty)
        #expect(draft(correct: String(repeating: "x", count: 80)).isValid)
        #expect(draft(correct: String(repeating: "x", count: 81)).problem == .optionTooLong)
    }

    @Test func optionsMustDifferIgnoringCaseAndSpaces() {
        #expect(draft(correct: "Dva", wrong: [" dva ", "Žádný"]).problem == .optionsNotDistinct)
    }

    @Test func openQuestionNeedsNoOptions() {
        var open = ChallengeDraft(kind: .open)
        open.question = "Co tě nejvíc překvapilo?"
        #expect(open.isValid)
        open.expectedAnswer = String(repeating: "x", count: 81)
        #expect(open.problem == .expectedAnswerTooLong)
    }

    @Test func shufflingKeepsTheCorrectAnswerTrackable() {
        var rng = SeededGenerator(seed: 11)
        var positions = Set<Int>()
        for _ in 0..<50 {
            let (options, index) = draft().shuffledOptions(using: &rng)
            #expect(options[index] == "Dva")
            #expect(Set(options) == ["Dva", "Jeden", "Žádný"])
            positions.insert(index)
        }
        #expect(positions == [0, 1, 2], "correct answer should land in every position")
    }
}

struct ChallengeResultTests {
    private let alice = UUID(), bob = UUID()

    private func challenge(kind: Challenge.Kind = .multipleChoice, answerIndex: Int? = 1, answerText: String? = nil,
                           isCorrect: Bool? = false, answered: Bool = true, beforeReading: Bool = false) -> Challenge {
        Challenge(
            id: UUID(), shareID: UUID(), senderID: alice, recipientID: bob, kind: kind, source: .custom,
            question: "Kolik měsíců má Mars?",
            options: kind == .multipleChoice ? ["Dva", "Jeden", "Žádný"] : nil,
            answerIndex: answerIndex, answerText: answerText, answeredBeforeReading: beforeReading,
            isCorrect: isCorrect, createdAt: .now, answeredAt: answered ? .now : nil
        )
    }

    @Test func noResultBeforeAnswering() {
        #expect(ChallengeResult(challenge: challenge(answered: false), solution: nil, viewerIsSender: true, otherName: "bob") == nil)
    }

    @Test func recipientBeforeAnsweringHasNoSolutionToShow() {
        // The app only learns the solution from RLS after answering; an unanswered card has none.
        let pending = challenge(answerIndex: nil, isCorrect: nil, answered: false)
        #expect(pending.answer == nil)
        #expect(ChallengeResult(challenge: pending, solution: ChallengeSolution(correctIndex: 0, expectedAnswer: nil),
                                viewerIsSender: false, otherName: "alice") == nil)
    }

    @Test func correctAnswerTexts() throws {
        let correct = challenge(answerIndex: 0, isCorrect: true)
        let solution = ChallengeSolution(correctIndex: 0, expectedAnswer: nil)
        let forSender = try #require(ChallengeResult(challenge: correct, solution: solution, viewerIsSender: true, otherName: "bob"))
        let forRecipient = try #require(ChallengeResult(challenge: correct, solution: solution, viewerIsSender: false, otherName: "alice"))
        #expect(forSender.headline == "bob odpověděl(a) správně!")
        #expect(forRecipient.headline == "Přesně tak!")
        #expect(forRecipient.detail == "Dva")
    }

    @Test func wrongAnswerIsFriendlyAndRevealsTheCorrectOne() throws {
        let wrong = challenge(answerIndex: 1, isCorrect: false, beforeReading: true)
        let solution = ChallengeSolution(correctIndex: 0, expectedAnswer: nil)
        let forRecipient = try #require(ChallengeResult(challenge: wrong, solution: solution, viewerIsSender: false, otherName: "alice"))
        let forSender = try #require(ChallengeResult(challenge: wrong, solution: solution, viewerIsSender: true, otherName: "bob"))

        #expect(forRecipient.headline == "Tentokrát to nevyšlo, ale teď už to víš.")
        #expect(forRecipient.detail == "Správně je „Dva“.")
        #expect(forSender.headline == "bob tipoval(a) „Jeden“ (tip ještě před čtením).")
        for text in [forRecipient.headline, forSender.headline, forRecipient.detail ?? "", forSender.detail ?? ""] {
            #expect(!text.localizedCaseInsensitiveContains("prohrál"))
            #expect(!text.localizedCaseInsensitiveContains("špatně"))
        }
    }

    @Test func openAnswerShowsBothSides() throws {
        let open = challenge(kind: .open, answerIndex: nil, answerText: "Prstence", isCorrect: nil)
        let solution = ChallengeSolution(correctIndex: nil, expectedAnswer: "Velikost")
        let forSender = try #require(ChallengeResult(challenge: open, solution: solution, viewerIsSender: true, otherName: "bob"))
        let forRecipient = try #require(ChallengeResult(challenge: open, solution: solution, viewerIsSender: false, otherName: "alice"))

        #expect(forSender.headline == "bob odpověděl(a): „Prstence“")
        #expect(forSender.detail == "A co sis myslel(a) ty: „Velikost“")
        #expect(forRecipient.detail == "A co si myslel(a) alice: „Velikost“")
    }

    @Test func decodesChallengeWithoutSolutionFields() throws {
        let json = #"""
        {"id":"bbbbbbbb-0000-0000-0000-000000000001","share_id":"aaaaaaaa-0000-0000-0000-000000000001",
         "sender_id":"11111111-1111-1111-1111-111111111111","recipient_id":"22222222-2222-2222-2222-222222222222",
         "kind":"multiple_choice","source":"custom","question":"Kolik měsíců má Mars?","options":["Dva","Jeden","Žádný"],
         "answer_index":null,"answer_text":null,"answered_before_reading":null,"is_correct":null,
         "created_at":"2026-10-19T09:00:00.123456+00:00","answered_at":null}
        """#
        let decoded = try BackendJSON.decoder.decode(Challenge.self, from: Data(json.utf8))
        #expect(decoded.kind == .multipleChoice)
        #expect(!decoded.isAnswered)
        #expect(decoded.options?.count == 3)
    }
}
