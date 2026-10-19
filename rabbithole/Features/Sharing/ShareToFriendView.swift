import SwiftUI

/// "Poslat příteli": pick one friend, add an optional message.
struct ShareToFriendView: View {
    let article: ArticleSummary
    let sharing: SharingService
    let friends: FriendsService

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
                        .disabled(selected == nil || isSending || message.count > SharingService.maxMessageLength)
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

    private func send() {
        guard let selected else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await sharing.share(article, with: selected.id, message: message)
                dismiss()
            } catch {
                errorMessage = String(localized: "Článek se nepodařilo poslat.")
            }
        }
    }
}
