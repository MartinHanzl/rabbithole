import SwiftUI

/// Optional challenge section of "Poslat příteli": own question with options, or an open one.
struct ChallengeComposer: View {
    @Binding var isEnabled: Bool
    @Binding var draft: ChallengeDraft
    /// Ready-made questions for this article (may be empty).
    var suggestions: [ChallengeDraft] = []
    var isLoadingSuggestions = false

    var body: some View {
        Section {
            Toggle("Přidat výzvu", isOn: $isEnabled)
            if isEnabled {
                if isLoadingSuggestions {
                    HStack { ProgressView(); Text("Hledám hotové otázky…").foregroundStyle(.secondary) }
                } else if !suggestions.isEmpty {
                    Menu {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button(suggestion.question) { draft = suggestion }
                        }
                    } label: {
                        Label("Vybrat hotovou otázku", systemImage: "lightbulb")
                    }
                }

                Picker("Typ", selection: $draft.kind) {
                    Text("S možnostmi").tag(Challenge.Kind.multipleChoice)
                    Text("Otevřená").tag(Challenge.Kind.open)
                }
                .pickerStyle(.segmented)

                TextField("Otázka", text: $draft.question, axis: .vertical)
                    .lineLimit(2...4)

                switch draft.kind {
                case .multipleChoice:
                    TextField("Správná odpověď", text: $draft.correctAnswer)
                    TextField("Špatná odpověď", text: $draft.wrongAnswers[0])
                    TextField("Další špatná odpověď", text: $draft.wrongAnswers[1])
                case .open:
                    TextField("Co bys odpověděl(a) ty? (nepovinné)", text: $draft.expectedAnswer)
                }
            }
        } header: {
            Text("Výzva")
        } footer: {
            if isEnabled {
                Text(footer)
                    .foregroundStyle(draft.problem == nil || draft.problem == .questionEmpty ? Color.secondary : Color.red)
            } else {
                Text("Polož příteli otázku k článku. Odpovědět může hned, nebo až si článek přečte.")
            }
        }
    }

    private var footer: LocalizedStringKey {
        switch draft.problem {
        case .questionTooLong: "Otázka může mít nejvýš 200 znaků."
        case .optionEmpty: "Vyplň všechny tři odpovědi."
        case .optionTooLong, .expectedAnswerTooLong: "Odpověď může mít nejvýš 80 znaků."
        case .optionsNotDistinct: "Odpovědi se musí lišit."
        case .questionEmpty, nil:
            "Otázka \(draft.question.count)/200. Možnosti se příteli zamíchají."
        }
    }
}
