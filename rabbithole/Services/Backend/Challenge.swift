import Foundation

/// Row of `public.challenges` – never contains the correct answer (that's `ChallengeSolution`).
nonisolated struct Challenge: Decodable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case multipleChoice = "multiple_choice"
        case open
    }

    enum Source: String, Codable, Sendable {
        case custom, wikidata, generated
    }

    let id: UUID
    let shareID: UUID
    let senderID: UUID
    let recipientID: UUID
    let kind: Kind
    let source: Source
    let question: String
    let options: [String]?
    let answerIndex: Int?
    let answerText: String?
    let answeredBeforeReading: Bool?
    let isCorrect: Bool?
    let createdAt: Date
    let answeredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, source, question, options
        case shareID = "share_id"
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case answerIndex = "answer_index"
        case answerText = "answer_text"
        case answeredBeforeReading = "answered_before_reading"
        case isCorrect = "is_correct"
        case createdAt = "created_at"
        case answeredAt = "answered_at"
    }

    var isAnswered: Bool { answeredAt != nil }

    var answer: String? {
        if let answerIndex, let options, options.indices.contains(answerIndex) { return options[answerIndex] }
        return answerText
    }
}

/// Row of `public.challenge_solutions`; readable by the recipient only after answering.
nonisolated struct ChallengeSolution: Decodable, Hashable, Sendable {
    let correctIndex: Int?
    let expectedAnswer: String?

    enum CodingKeys: String, CodingKey {
        case correctIndex = "correct_index"
        case expectedAnswer = "expected_answer"
    }
}

/// What the sender fills in. Mirrors the server-side validation in `create_challenge`.
nonisolated struct ChallengeDraft: Equatable, Sendable {
    enum Problem: Equatable {
        case questionEmpty, questionTooLong, optionEmpty, optionTooLong, optionsNotDistinct, expectedAnswerTooLong
    }

    static let maxQuestionLength = 200
    static let maxAnswerLength = 80

    var kind: Challenge.Kind = .multipleChoice
    var source: Challenge.Source = .custom
    var question = ""
    var correctAnswer = ""
    var wrongAnswers = ["", ""]
    /// Optional "what I'd say" for open questions, revealed after answering.
    var expectedAnswer = ""

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var problem: Problem? {
        let question = Self.trimmed(question)
        if question.isEmpty { return .questionEmpty }
        if question.count > Self.maxQuestionLength { return .questionTooLong }
        switch kind {
        case .multipleChoice:
            let options = ([correctAnswer] + wrongAnswers).map(Self.trimmed)
            if options.contains(where: \.isEmpty) { return .optionEmpty }
            if options.contains(where: { $0.count > Self.maxAnswerLength }) { return .optionTooLong }
            if Set(options.map { $0.lowercased() }).count != options.count { return .optionsNotDistinct }
        case .open:
            if Self.trimmed(expectedAnswer).count > Self.maxAnswerLength { return .expectedAnswerTooLong }
        }
        return nil
    }

    var isValid: Bool { problem == nil }

    /// Options in random order and where the correct one ended up.
    func shuffledOptions<R: RandomNumberGenerator>(using rng: inout R) -> (options: [String], correctIndex: Int) {
        let correct = Self.trimmed(correctAnswer)
        let options = ([correct] + wrongAnswers.map(Self.trimmed)).shuffled(using: &rng)
        return (options, options.firstIndex(of: correct)!)
    }
}

/// Friendly, never-competitive texts for an answered challenge. Pure – unit tested.
nonisolated struct ChallengeResult: Equatable, Sendable {
    let headline: String
    let detail: String?

    /// - Parameters:
    ///   - viewerIsSender: whether the person looking at it asked the question.
    ///   - otherName: nickname of the other participant.
    init?(challenge: Challenge, solution: ChallengeSolution?, viewerIsSender: Bool, otherName: String) {
        guard challenge.isAnswered, let answer = challenge.answer else { return nil }
        let guessNote = challenge.answeredBeforeReading == true
            ? String(localized: " (tip ještě před čtením)") : ""

        switch challenge.kind {
        case .multipleChoice:
            let correct = solution?.correctIndex.flatMap { index in challenge.options?[safe: index] }
            if challenge.isCorrect == true {
                headline = viewerIsSender
                    ? String(localized: "\(otherName) odpověděl(a) správně\(guessNote)!")
                    : String(localized: "Přesně tak\(guessNote)!")
                detail = answer
            } else if viewerIsSender {
                headline = String(localized: "\(otherName) tipoval(a) „\(answer)“\(guessNote).")
                detail = correct.map { String(localized: "Správně je „\($0)“ – můžete to probrat v chatu.") }
            } else {
                headline = String(localized: "Tentokrát to nevyšlo, ale teď už to víš.")
                detail = correct.map { String(localized: "Správně je „\($0)“.") }
            }
        case .open:
            headline = viewerIsSender
                ? String(localized: "\(otherName) odpověděl(a): „\(answer)“\(guessNote)")
                : String(localized: "Tvoje odpověď: „\(answer)“\(guessNote)")
            if let expected = solution?.expectedAnswer, !expected.isEmpty {
                detail = viewerIsSender
                    ? String(localized: "A co sis myslel(a) ty: „\(expected)“")
                    : String(localized: "A co si myslel(a) \(otherName): „\(expected)“")
            } else {
                detail = nil
            }
        }
    }
}

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
