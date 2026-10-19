import Foundation

enum AppConfig {
    /// Contact for Wikimedia's User-Agent policy (https://meta.wikimedia.org/wiki/User-Agent_policy).
    /// TODO: replace with a real address before release.
    static let contactEmail = "CONTACT_EMAIL@example.com"

    /// Show a 6-digit code field after sending the sign-in email. Requires custom SMTP on
    /// Supabase (free tier can't change templates otherwise) – see supabase/config.toml.
    static let emailSignInUsesCode = false

    static let minimumSelectedTopics = 3
    static let defaultBreakInterval = 20

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var userAgent: String {
        "Rabbithole/\(appVersion) (iOS; \(contactEmail))"
    }
}

/// Keys for lightweight settings kept in `UserDefaults` / `@AppStorage`.
enum SettingsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let breakInterval = "breakInterval"
    /// Bumped whenever topic selection changes so the feed reloads.
    static let topicsVersion = "topicsVersion"
}
