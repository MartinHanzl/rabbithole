import SwiftUI

/// "Účet" section of Settings. Hidden when the app is built without a backend.
struct AccountSection: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @State private var showsSignIn = false
    @State private var errorMessage: String?
    @State private var confirmsDeletion = false
    @State private var isDeleting = false

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
                                let local = SavedArticlesRepository(context: modelContext).all().map { ($0.summary, $0.savedAt) }
                                try await auth.setShareSavedWithFriends(value, localSaved: local)
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
                if let service = auth.friendsService {
                    NavigationLink("Blokovaní uživatelé") {
                        BlockedUsersView(service: service)
                    }
                }
                NavigationLink("Zásady ochrany osobních údajů") {
                    PrivacyPolicyView()
                }
                signOutButton
                Button(role: .destructive) {
                    confirmsDeletion = true
                } label: {
                    HStack {
                        Text("Smazat účet")
                        if isDeleting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting)
            } header: {
                Text("Účet")
            }
            .alert("Smazat účet?", isPresented: $confirmsDeletion) {
                Button("Smazat natrvalo", role: .destructive, action: deleteAccount)
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text("Ze serveru se smaže tvůj profil, přátelé, sdílené články i všechny tvoje zprávy. Nejde to vrátit. Témata a uložené články v tomto zařízení zůstanou.")
            }
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await auth.deleteAccount()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var signOutButton: some View {
        Button("Odhlásit se", role: .destructive) {
            Task { await auth.signOut() }
        }
    }
}
