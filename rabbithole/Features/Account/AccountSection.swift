import SwiftUI

/// "Účet" section of Settings. Hidden when the app is built without a backend.
struct AccountSection: View {
    @Environment(AuthService.self) private var auth
    @State private var showsSignIn = false
    @State private var errorMessage: String?

    var body: some View {
        switch auth.state {
        case .unavailable:
            EmptyView()
        case .loading:
            Section("Účet") {
                ProgressView()
            }
        case .signedOut:
            Section {
                Button("Přihlásit se") { showsSignIn = true }
            } header: {
                Text("Účet")
            } footer: {
                Text("S účtem můžeš přidávat přátele a posílat si články.")
            }
            .sheet(isPresented: $showsSignIn) { SignInView() }
        case .needsProfile:
            Section("Účet") {
                Text("Dokonči nastavení profilu.")
            }
        case .profileUnavailable:
            Section("Účet") {
                Text("Profil se nepodařilo načíst.")
                    .foregroundStyle(.secondary)
                Button("Zkusit znovu") {
                    Task { await auth.retryLoadingProfile() }
                }
                signOutButton
            }
        case .signedIn(let profile):
            Section {
                LabeledContent("Přezdívka", value: profile.nickname)
                Toggle("Ukazovat přátelům, co si ukládám", isOn: Binding(
                    get: { profile.shareSavedWithFriends },
                    set: { value in
                        Task {
                            do {
                                try await auth.setShareSavedWithFriends(value)
                                errorMessage = nil
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                ))
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
                NavigationLink("Zásady ochrany osobních údajů") {
                    PrivacyPolicyView()
                }
                signOutButton
            } header: {
                Text("Účet")
            }
        }
    }

    private var signOutButton: some View {
        Button("Odhlásit se", role: .destructive) {
            Task { await auth.signOut() }
        }
    }
}
