import SwiftUI

/// "Od přátel" tab: what friends saved or shared, plus the way to manage friends.
struct FromFriendsView: View {
    @Environment(AuthService.self) private var auth
    @State private var showsSignIn = false

    var body: some View {
        NavigationStack {
            Group {
                if let service = auth.friendsService {
                    SignedInContent(service: service)
                } else {
                    ContentUnavailableView {
                        Label("Od přátel", systemImage: "person.2")
                    } description: {
                        Text("Přihlas se, přidej si přátele a posílejte si zajímavé články.")
                    } actions: {
                        Button("Přihlásit se") { showsSignIn = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Od přátel")
            .background(Theme.screenBackground)
        }
        .sheet(isPresented: $showsSignIn) { SignInView() }
    }
}

private struct SignedInContent: View {
    @State private var friends: FriendsViewModel

    init(service: FriendsService) {
        _friends = State(initialValue: FriendsViewModel(service: service))
    }

    var body: some View {
        ContentUnavailableView {
            Label("Zatím tu nic není", systemImage: "tray")
        } description: {
            Text("Tady uvidíš články, které ti přátelé pošlou nebo si uloží.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    FriendsView(viewModel: friends)
                } label: {
                    Label("Přátelé", systemImage: "person.2")
                }
                .badge(friends.pendingIncomingCount)
            }
        }
        .task { await friends.load() }
    }
}
