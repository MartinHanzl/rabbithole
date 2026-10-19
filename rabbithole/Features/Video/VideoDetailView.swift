import SwiftData
import SwiftUI

/// Plays a video in the official embedded player.
struct VideoDetailView: View {
    let card: VideoCard
    /// Called when the player can't play the video; the screen closes and the card is skipped.
    var onUnplayable: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSaved = false
    @State private var openedAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                YouTubePlayerView(videoID: card.video.id) { _ in
                    onUnplayable()
                    dismiss()
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    TopicLabel(topicID: card.topicID, isExploration: card.isExploration)
                    Text(card.video.title)
                        .font(.readingTitle(.title2))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(card.video.channelTitle) · \(card.video.formattedDuration)")
                        .foregroundStyle(.secondary)
                    Link(destination: card.video.watchURL) {
                        Label("Otevřít na YouTube", systemImage: "arrow.up.right.square")
                    }
                    Text("Video přehrává oficiální přehrávač YouTube. Platí pro něj podmínky YouTube a zásady ochrany soukromí Google.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: Theme.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: card.video.watchURL) {
                    Label("Sdílet", systemImage: "square.and.arrow.up")
                }
                Button(action: toggleSaved) {
                    Label(isSaved ? "Odebrat z uložených" : "Uložit", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                }
                .sensoryFeedback(.selection, trigger: isSaved)
            }
        }
        .onAppear {
            isSaved = SavedVideosRepository(context: modelContext).savedIDs().contains(card.id)
            openedAt = .now
        }
        .onDisappear(perform: finishWatching)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { openedAt = .now } else { finishWatching() }
        }
    }

    private func toggleSaved() {
        let repository = SavedVideosRepository(context: modelContext)
        if isSaved {
            repository.remove(videoID: card.id)
        } else {
            repository.save(card.video, topicID: card.topicID)
            adjustWeight(.saved)
        }
        isSaved.toggle()
    }

    /// Watching for a while counts like a long read.
    private func finishWatching() {
        guard let openedAt else { return }
        self.openedAt = nil
        if services.engine.isLongRead(duration: Date.now.timeIntervalSince(openedAt)) {
            adjustWeight(.longRead)
        }
    }

    private func adjustWeight(_ signal: PersonalizationEngine.Signal) {
        let topics = TopicPreferencesRepository(context: modelContext)
        let current = topics.weights()[card.topicID] ?? services.engine.configuration.initialWeight
        topics.setWeight(services.engine.updatedWeight(current, after: signal), for: card.topicID)
    }
}
