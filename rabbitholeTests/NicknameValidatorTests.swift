import Foundation
import Testing
@testable import rabbithole

/// Must stay in sync with the `profiles.nickname` check constraint in the Supabase migration.
struct NicknameValidatorTests {
    @Test(arguments: ["bob", "Alice_99", "jan.novak", "a_b.c", String(repeating: "x", count: 24)])
    func acceptsValidNicknames(_ nickname: String) {
        #expect(NicknameValidator.problem(with: nickname) == nil)
    }

    @Test func trimsWhitespace() {
        #expect(NicknameValidator.problem(with: "  bob  ") == nil)
        #expect(NicknameValidator.normalized("  bob \n") == "bob")
    }

    @Test(arguments: ["", "ab", " ab "])
    func rejectsShortNicknames(_ nickname: String) {
        #expect(NicknameValidator.problem(with: nickname) == .tooShort)
    }

    @Test func rejectsLongNicknames() {
        #expect(NicknameValidator.problem(with: String(repeating: "x", count: 25)) == .tooLong)
    }

    @Test(arguments: ["Pável", "jan novák", "bob!", "a-b-c", "😀😀😀", "ab\u{0301}c"])
    func rejectsCharactersOutsideAllowedSet(_ nickname: String) {
        #expect(NicknameValidator.problem(with: nickname) == .invalidCharacters)
    }
}
