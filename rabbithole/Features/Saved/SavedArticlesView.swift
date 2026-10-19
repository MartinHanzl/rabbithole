import SwiftData
import SwiftUI

struct SavedArticlesView: View {
    @Query(sort: \SavedArticle.savedAt, order: .reverse) private var articles: [SavedArticle]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if articles.isEmpty {
                    ContentUnavailableView {
                        Label("Zatím nic uloženého", systemImage: "bookmark")
                    } description: {
                        Text("Články, které si ve feedu uložíš, najdeš tady – i bez připojení.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Uložené")
            .navigationDestination(for: SavedArticle.self) { saved in
                ArticleDetailScreen(article: saved.summary, topicID: saved.topicID)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(articles) { article in
                NavigationLink(value: article) {
                    SavedArticleRow(article: article)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        remove(article)
                    } label: {
                        Label("Odebrat", systemImage: "trash")
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { articles[$0] }.forEach(remove)
            }
        }
        .toolbar { EditButton() }
    }

    private func remove(_ article: SavedArticle) {
        SavedArticlesRepository(context: modelContext).remove(pageID: article.pageID)
    }
}

private struct SavedArticleRow: View {
    let article: SavedArticle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TopicLabel(topicID: article.topicID)
                Text(article.title)
                    .font(.readingTitle(.headline))
                Text(article.extract)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let url = article.thumbnailURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }
}
