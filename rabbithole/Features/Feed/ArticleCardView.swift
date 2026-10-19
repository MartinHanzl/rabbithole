import SwiftUI

struct ArticleCardView: View {
    let card: FeedCard
    let isSaved: Bool
    let onToggleSave: () -> Void
    let onNotInterested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArticleImage(article: card.article)

            VStack(alignment: .leading, spacing: 14) {
                TopicLabel(topicID: card.topicID, isExploration: card.isExploration)

                Text(card.article.title)
                    .font(.readingTitle(.title2))
                    .fixedSize(horizontal: false, vertical: true)

                Text(card.article.extract)
                    .font(.readingBody)
                    .lineSpacing(4)
                    .lineLimit(8)
                    .foregroundStyle(.primary.opacity(0.85))

                AttributionView(articleURL: card.article.articleURL, imageLicenseURL: card.article.imageLicenseURL)

                actions
            }
            .padding(Theme.spacing + 4)
        }
        .background(Theme.cardBackground)
        .clipShape(.rect(cornerRadius: Theme.cornerRadius))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            NavigationLink(value: card) {
                Label("Číst dál", systemImage: "book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { secondaryButtons }
                VStack(spacing: 10) { secondaryButtons }
            }
        }
    }

    @ViewBuilder private var secondaryButtons: some View {
        Button(action: onToggleSave) {
            Label(
                isSaved ? "Uloženo" : "Uložit",
                systemImage: isSaved ? "bookmark.fill" : "bookmark"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .sensoryFeedback(.selection, trigger: isSaved)

        Button(action: onNotInterested) {
            Label("Nezajímá mě", systemImage: "hand.thumbsdown")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }
}
