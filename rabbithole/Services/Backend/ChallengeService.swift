import Foundation
import Supabase

nonisolated enum ChallengeError: LocalizedError, Equatable {
    case notFriends, blocked, disabled, alreadyExists, alreadyAnswered, invalid, failed

    var errorDescription: String? {
        switch self {
        case .notFriends: String(localized: "Výzvu můžeš poslat jen příteli.")
        case .blocked: String(localized: "S tímto uživatelem si výzvy posílat nelze.")
        case .disabled: String(localized: "Tento přítel má výzvy vypnuté.")
        case .alreadyExists: String(localized: "K tomuto článku už výzva je.")
        case .alreadyAnswered: String(localized: "Na výzvu už bylo odpovězeno.")
        case .invalid: String(localized: "Zkontroluj otázku a odpovědi.")
        case .failed: String(localized: "Výzvu se nepodařilo odeslat.")
        }
    }

    /// Maps the error messages raised by `create_challenge` / `answer_challenge`.
    static func from(_ error: Error) -> ChallengeError {
        let message = (error as? PostgrestError)?.message ?? ""
        switch message {
        case "not_friends", "share_not_found", "challenge_not_found": return .notFriends
        case "blocked": return .blocked
        case "challenges_disabled": return .disabled
        case "challenge_exists": return .alreadyExists
        case "already_answered": return .alreadyAnswered
        case "invalid_question", "invalid_options", "invalid_answer": return .invalid
        default: return .failed
        }
    }
}

/// Challenges are written only through RPCs; the correct answer arrives only after answering.
nonisolated struct ChallengeService: Sendable {
    let client: SupabaseClient
    let me: UUID

    private static let columns = """
        id, share_id, sender_id, recipient_id, kind, source, question, options, answer_index, answer_text,
        answered_before_reading, is_correct, created_at, answered_at
        """

    func create(on shareID: UUID, from draft: ChallengeDraft) async throws {
        struct Params: Encodable {
            let p_share_id: UUID
            let p_kind: Challenge.Kind
            let p_question: String
            let p_options: [String]?
            let p_correct_index: Int?
            let p_expected_answer: String?
            let p_source: Challenge.Source
        }
        var rng = SystemRandomNumberGenerator()
        let shuffled = draft.kind == .multipleChoice ? draft.shuffledOptions(using: &rng) : nil
        let expected = draft.expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await client.rpc("create_challenge", params: Params(
                p_share_id: shareID,
                p_kind: draft.kind,
                p_question: draft.question.trimmingCharacters(in: .whitespacesAndNewlines),
                p_options: shuffled?.options,
                p_correct_index: shuffled?.correctIndex,
                p_expected_answer: draft.kind == .open && !expected.isEmpty ? expected : nil,
                p_source: draft.source
            )).execute()
        } catch {
            throw ChallengeError.from(error)
        }
    }

    func challenge(onShare shareID: UUID) async throws -> Challenge? {
        let rows: [Challenge] = try await client.from("challenges")
            .select(Self.columns)
            .eq("share_id", value: shareID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// `nil` for the recipient until they answer (RLS).
    func solution(for challengeID: UUID) async throws -> ChallengeSolution? {
        let rows: [ChallengeSolution] = try await client.from("challenge_solutions")
            .select("correct_index, expected_answer")
            .eq("challenge_id", value: challengeID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func answer(_ challengeID: UUID, optionIndex: Int?, text: String?, beforeReading: Bool) async throws {
        struct Params: Encodable {
            let p_challenge_id: UUID
            let p_answer_index: Int?
            let p_answer_text: String?
            let p_before_reading: Bool
        }
        do {
            try await client.rpc("answer_challenge", params: Params(
                p_challenge_id: challengeID,
                p_answer_index: optionIndex,
                p_answer_text: text?.trimmingCharacters(in: .whitespacesAndNewlines),
                p_before_reading: beforeReading
            )).execute()
        } catch {
            throw ChallengeError.from(error)
        }
    }

    /// Challenge updates for one share while its chat is open.
    func updates(onShare shareID: UUID, channel: RealtimeChannelV2) -> AsyncStream<Challenge> {
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "challenges",
                                             filter: .eq("share_id", value: shareID))
        return AsyncStream { continuation in
            let task = Task {
                for await update in updates {
                    if let challenge = try? update.decodeRecord(as: Challenge.self, decoder: BackendJSON.decoder) {
                        continuation.yield(challenge)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
