import SwiftData
import SwiftUI

/// Shown once after the first sign-in: choose a nickname and decide what friends may see.
struct ProfileSetupView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var modelContext

    @State private var nickname = ""
    @State private var shareSaved = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var problem: NicknameValidator.Problem? {
        NicknameValidator.problem(with: nickname)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Přezdívka", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                } header: {
                    Text("Jak tě najdou přátelé")
                } footer: {
                    Text(hint)
                        .foregroundStyle(problem == nil || nickname.isEmpty ? Color.secondary : Color.red)
                }

                Section {
                    Toggle("Ukazovat přátelům, co si ukládám", isOn: $shareSaved)
                } footer: {
                    Text("Přátelé pak uvidí tvoje uložené články v záložce Od přátel. Můžeš to kdykoli změnit v nastavení.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Text("Dokončit")
                            if isSaving {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(problem != nil || isSaving)

                    Button("Odhlásit se", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("Tvůj profil")
        }
        .interactiveDismissDisabled()
    }

    private var hint: LocalizedStringKey {
        switch problem {
        case .invalidCharacters: "Jen písmena bez diakritiky, číslice, podtržítko a tečka."
        case .tooLong: "Nejvýš 24 znaků."
        case .tooShort, nil: "3–24 znaků: písmena bez diakritiky, číslice, _ a tečka."
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let topics = TopicPreferencesRepository(context: modelContext).selectedTopicIDs()
        Task {
            defer { isSaving = false }
            do {
                try await auth.createProfile(nickname: nickname, shareSavedWithFriends: shareSaved, topicIDs: topics)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
