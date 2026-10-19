import Foundation

/// Row of `public.profiles`.
nonisolated struct Profile: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var nickname: String
    var avatarPath: String?
    var shareSavedWithFriends: Bool
    var acceptsChallenges: Bool = true

    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case avatarPath = "avatar_path"
        case shareSavedWithFriends = "share_saved_with_friends"
        case acceptsChallenges = "accepts_challenges"
    }
}

/// Mirrors the `profiles.nickname` check constraint so users get feedback before the request.
nonisolated enum NicknameValidator {
    enum Problem: Equatable {
        case tooShort
        case tooLong
        case invalidCharacters
    }

    static let lengthRange = 3...24
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")

    static func normalized(_ nickname: String) -> String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func problem(with nickname: String) -> Problem? {
        let value = normalized(nickname)
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) { return .invalidCharacters }
        if value.count < lengthRange.lowerBound { return .tooShort }
        if value.count > lengthRange.upperBound { return .tooLong }
        return nil
    }
}
