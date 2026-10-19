import SwiftUI

/// Feed card for a YouTube video. Shows only the thumbnail – nothing plays in the feed.
struct VideoCardView: View {
    let card: VideoCard
    let isSaved: Bool
    let onToggleSave: () -> Void
    let onNotInterested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: card) {
                VideoThumbnail(video: card.video)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Přehrát video \(card.video.title)"))

            VStack(alignment: .leading, spacing: 12) {
                TopicLabel(topicID: card.topicID, isExploration: card.isExploration)

                Text(card.video.title)
                    .font(.readingTitle(.title3))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle")
                        .accessibilityHidden(true)
                    Text(card.video.channelTitle)
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text(card.video.formattedDuration)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Link(destination: card.video.watchURL) {
                    Label("Otevřít na YouTube", systemImage: "arrow.up.right.square")
                }
                .font(.footnote)
                .tint(.secondary)

                VStack(spacing: 10) {
                    NavigationLink(value: card) {
                        Label("Přehrát", systemImage: "play.fill")
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
            .padding(Theme.spacing + 4)
        }
        .background(Theme.cardBackground)
        .clipShape(.rect(cornerRadius: Theme.cornerRadius))
    }

    @ViewBuilder private var secondaryButtons: some View {
        Button(action: onToggleSave) {
            Label(isSaved ? "Uloženo" : "Uložit", systemImage: isSaved ? "bookmark.fill" : "bookmark")
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

/// 16:9 thumbnail with a play symbol and the duration.
struct VideoThumbnail: View {
    let video: YouTubeVideo

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: video.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
            }
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(video.formattedDuration)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.7), in: .rect(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .padding(8)
            }
            .clipped()
    }
}
