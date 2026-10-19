import SwiftUI

/// Report a user (App Store guideline 1.2). Reports are reviewed by the moderator.
struct ReportUserView: View {
    let profile: PublicProfile
    let onSubmit: (ReportReason, String, Bool) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .inappropriate
    @State private var note = ""
    @State private var alsoBlock = true
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Důvod", selection: $reason) {
                        ForEach(ReportReason.allCases) { reason in
                            Text(reason.title).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Proč hlásíš uživatele \(profile.nickname)?")
                }

                Section("Podrobnosti (nepovinné)") {
                    TextField("Co se stalo?", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Zároveň zablokovat", isOn: $alsoBlock)
                } footer: {
                    Text("Nahlášení posoudíme do 24 hodin. Uživatel se nedozví, kdo ho nahlásil.")
                }
            }
            .navigationTitle("Nahlásit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Odeslat") {
                        isSending = true
                        Task {
                            if await onSubmit(reason, note, alsoBlock) { dismiss() }
                            isSending = false
                        }
                    }
                    .disabled(isSending)
                }
            }
        }
    }
}
