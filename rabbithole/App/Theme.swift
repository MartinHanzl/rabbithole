import SwiftUI

/// Shared visual constants. Calm, reading-focused look; colors come from the asset catalog
/// and system semantic colors so light/dark mode work automatically.
enum Theme {
    static let spacing: CGFloat = 16
    static let cornerRadius: CGFloat = 20
    static let readingWidth: CGFloat = 640

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let screenBackground = Color(.systemGroupedBackground)
}

extension Font {
    /// Serif headings make the app feel like reading rather than scrolling.
    static func readingTitle(_ style: Font.TextStyle = .title) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }

    static let readingBody = Font.system(.body, design: .serif)
}
