import SwiftUI

/// Sign-in sheet. Accounts are optional – the feed works without one.
///
/// Sign in with Apple needs a paid Apple Developer Program membership; add it here once
/// available (App Store guideline 4.8 requires it alongside Google sign-in).
struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Účet potřebuješ jen pro přátele a sdílení článků. Feed a uložené články fungují i bez něj.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        run { try await auth.signInWithGoogle() }
                    } label: {
                        Label("Pokračovat přes Google", systemImage: "g.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isWorking)
                }

                Section {
                    if let sentTo {
                        Text("Poslali jsme e-mail na \(sentTo). Klepni v něm na odkaz – otevře se aplikace a budeš přihlášený.")
                        if AppConfig.emailSignInUsesCode {
                            TextField("Kód z e-mailu", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Button("Přihlásit kódem") {
                                run { try await auth.verifyEmailCode(email: sentTo, code: code) }
                            }
                            .disabled(code.count < 6 || isWorking)
                        }
                        Button("Použít jiný e-mail") {
                            self.sentTo = nil
                            code = ""
                        }
                    } else {
                        TextField("E-mail", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Poslat přihlašovací e-mail") {
                            let address = email
                            run {
                                try await auth.sendEmailSignIn(to: address)
                                sentTo = address.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .disabled(!email.contains("@") || isWorking)
                    }
                } header: {
                    Text("Nebo e-mailem")
                } footer: {
                    Text("Bez hesla – stačí odkaz z e-mailu.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    NavigationLink("Zásady ochrany osobních údajů") {
                        PrivacyPolicyView()
                    }
                }
            }
            .navigationTitle("Přihlášení")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
                if isWorking {
                    ToolbarItem(placement: .confirmationAction) { ProgressView() }
                }
            }
            .onChange(of: auth.state) { _, state in
                switch state {
                case .signedIn, .needsProfile: dismiss()
                default: break
                }
            }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
