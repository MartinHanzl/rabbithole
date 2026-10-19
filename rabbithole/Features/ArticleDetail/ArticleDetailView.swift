import SwiftUI

/// Full article reader. Placeholder – implemented in the next step.
struct ArticleDetailView: View {
    let article: ArticleSummary
    let topicID: String
    var onFinish: (TimeInterval) -> Void = { _ in }

    var body: some View {
        ScrollView {
            Text(article.extract)
                .padding()
        }
        .navigationTitle(article.title)
    }
}
