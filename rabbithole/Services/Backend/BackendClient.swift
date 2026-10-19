import Foundation
import Supabase

/// Supabase connection settings read from Info.plist (filled from `Config/Secrets.xcconfig`).
nonisolated struct BackendConfiguration: Sendable {
    let url: URL
    let publishableKey: String

    /// `nil` when the project was built without `Secrets.xcconfig` – social features are then hidden.
    static let current: BackendConfiguration? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let urlString = info["SupabaseURL"] as? String,
              let url = URL(string: urlString), url.scheme == "https",
              let key = info["SupabasePublishableKey"] as? String,
              key.hasPrefix("sb_publishable_") else {
            return nil
        }
        return BackendConfiguration(url: url, publishableKey: key)
    }()

    static let authRedirectURL = URL(string: "rabbithole://auth-callback")!
}

enum BackendClient {
    /// Shared client; `nil` without configuration.
    static let shared: SupabaseClient? = BackendConfiguration.current.map {
        SupabaseClient(
            supabaseURL: $0.url,
            supabaseKey: $0.publishableKey,
            options: SupabaseClientOptions(auth: .init(redirectToURL: BackendConfiguration.authRedirectURL))
        )
    }
}
