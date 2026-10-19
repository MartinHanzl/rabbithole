import SwiftUI

/// "Poslat příteli": pick one friend, add an optional message and challenge.
struct ShareToFriendView: View {
    let article: ArticleSummary
    let sharing: SharingService
    let friends: FriendsService
    /// `nil` when the sender turned challenges off.
    var challenges: ChallengeService?
    var suggestionsProvider: (() async -> [ChallengeDraft])?

    @State private var challengeEnabled = false
    @State private var draft = ChallengeDraft()
    @State private var suggestions: [ChallengeDraft] = []
    @State private var isLoadingSuggestions = false
    /// Set once the article is shared, so a failed challenge can be retried without re-sharing.
    @State private var createdShareID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var friendList: [PublicProfile] = []
    @State private var selected: PublicProfile?
    @State private var message = ""
    @State private var isLoaded = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(article.title)
                        .font(.readingTitle(.headline))
                }

                Section("Komu") {
                    if isLoaded, friendList.isEmpty {
                        Text("Zatím nemáš přátele. Přidej si je v záložce Od přátel.")
                            .foregroundStyle(.secondary)
                    } else if !isLoaded {
                        ProgressView()
                    }
                    ForEach(friendList) { friend in
                        Button {
                            selected = friend
                        } label: {
                            HStack {
                                ProfileLabel(profile: friend)
                                Spacer()
                                if selected == friend {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == friend ? .isSelected : [])
                    }
                }

                if canChallenge {
                    ChallengeComposer(isEnabled: $challengeEnabled, draft: $draft,
                                      suggestions: suggestions, isLoadingSuggestions: isLoadingSuggestions)
                        .onChange(of: challengeEnabled) { _, enabled in
                            if enabled { Task { await loadSuggestions() } }
                        }
                } else if challenges != nil, selected?.acceptsChallenges == false {
                    Section {
                        Text("\(selected?.nickname ?? "") má výzvy vypnuté.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Proč by se mu to mohlo líbit? (nepovinné)", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    if message.count > SharingService.maxMessageLength {
                        Text("Zpráva je příliš dlouhá.").foregroundStyle(.red)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Poslat příteli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Odeslat", action: send)
                        .disabled(selected == nil || isSending || message.count > SharingService.maxMessageLength
                                  || (canChallenge && challengeEnabled && !draft.isValid))
                }
            }
            .task { await loadFriends() }
        }
    }

    private func loadFriends() async {
        let rows = (try? await friends.friendships()) ?? []
        friendList = FriendshipGroups(friendships: rows, me: friends.me).friends.map(\.profile)
        isLoaded = true
    }

    private var canChallenge: Bool {
        challenges != nil && selected != nil && selected?.acceptsChallenges != false
    }

    private func loadSuggestions() async {
        guard suggestions.isEmpty, let suggestionsProvider else { return }
        isLoadingSuggestions = true
        suggestions = await suggestionsProvider()
        isLoadingSuggestions = false
    }

    private func send() {
        guard let selected else { return }
        isSending = true
        Task {
            defer { isSending = false }
            let shareID: UUID
            if let createdShareID {
                shareID = createdShareID
            } else {
                do {
                    shareID = try await sharing.share(article, with: selected.id, message: message)
                    createdShareID = shareID
                } catch {
                    errorMessage = String(localized: "Článek se nepodařilo poslat.")
                    return
                }
            }
            if canChallenge, challengeEnabled, let challenges {
                var challenge = draft
                if !suggestions.contains(challenge) { challenge.source = .custom }
                do {
                    try await challenges.create(on: shareID, from: challenge)
                } catch {
                    errorMessage = String(localized: "Článek odešel, ale výzva ne: \(error.localizedDescription) Uprav ji a zkus to znovu.")
                    return
                }
            }
            dismiss()
        }
    }
}
