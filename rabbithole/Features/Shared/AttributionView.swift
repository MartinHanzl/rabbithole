import SwiftUI

/// Required CC BY-SA attribution: source article, text license and the image's license page.
struct AttributionView: View {
    let articleURL: URL
    let imageLicenseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { sourceParts(separated: true) }
                VStack(alignment: .leading, spacing: 2) { sourceParts(separated: false) }
            }
            if let imageLicenseURL {
                Link(destination: imageLicenseURL) {
                    Label("Obrázek: autor a licence", systemImage: "photo")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .tint(.secondary)
    }

    @ViewBuilder private func sourceParts(separated: Bool) -> some View {
        Text("Zdroj:")
        Link("Wikipedie", destination: articleURL)
            .underline()
        if separated {
            Text(verbatim: "·")
                .accessibilityHidden(true)
        }
        Link("Licence CC BY-SA 4.0", destination: WikipediaURLs.license)
            .underline()
    }
}

/// Small capsule with the topic name; marks articles from outside the user's topics.
struct TopicLabel: View {
    let topicID: String
    var isExploration = false

    var body: some View {
        if let topic = TopicCatalog.topic(id: topicID) {
            HStack(spacing: 6) {
                Label {
                    Text(topic.name)
                } icon: {
                    Image(systemName: topic.symbol)
                }
                if isExploration {
                    Text("· Mimo tvá témata")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12), in: .capsule)
            .foregroundStyle(Color.accentColor)
        }
    }
}

/// Lead image loading a sharp variant first and falling back to the small thumbnail.
struct ArticleImage: View {
    let article: ArticleSummary
    var height: CGFloat = 220

    var body: some View {
        if let large = article.largeThumbnailURL {
            AsyncImage(url: large) { phase in
                switch phase {
                case .success(let image):
                    styled(image)
                case .failure:
                    AsyncImage(url: article.thumbnailURL) { image in
                        styled(image)
                    } placeholder: {
                        placeholder
                    }
                default:
                    placeholder
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
        }
    }

    private func styled(_ image: Image) -> some View {
        image.resizable().scaledToFill()
    }

    private var placeholder: some View {
        Rectangle().fill(.quaternary)
    }
}
