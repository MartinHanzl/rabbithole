import SwiftUI

struct BlockedUsersView: View {
    let service: FriendsService

    @State private var blocked: [BlockedUser] = []
    @State private var isLoaded = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if isLoaded, blocked.isEmpty {
                Text("Nikoho neblokuješ.")
                    .foregroundStyle(.secondary)
            }
            ForEach(blocked) { user in
                HStack {
                    if let profile = user.blocked {
                        ProfileLabel(profile: profile)
                    } else {
                        Text("Smazaný uživatel").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Odblokovat") {
                        Task { await unblock(user) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Blokovaní uživatelé")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            blocked = try await service.blockedUsers()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Seznam se nepodařilo načíst.")
        }
        isLoaded = true
    }

    private func unblock(_ user: BlockedUser) async {
        do {
            try await service.unblock(user.blockedID)
            await load()
        } catch {
            errorMessage = String(localized: "Odblokování se nepovedlo.")
        }
    }
}
