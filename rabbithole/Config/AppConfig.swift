import Foundation

enum AppConfig {
    /// Contact for Wikimedia's User-Agent policy (https://meta.wikimedia.org/wiki/User-Agent_policy).
    /// TODO: replace with a real address before release.
    static let contactEmail = "CONTACT_EMAIL@example.com"

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
}
