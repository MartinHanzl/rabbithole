import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.breakInterval) private var breakInterval = AppConfig.defaultBreakInterval
    @AppStorage(SettingsKey.topicsVersion) private var topicsVersion = 0
    @AppStorage(SettingsKey.videoInterval) private var videoInterval = FeedSlotPlanner.defaultVideoInterval
    @State private var confirmation: Confirmation?

    private enum Confirmation: Identifiable {
        case resetWeights, forgetSeen
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Form {
                AccountSection()

                Section {
                    NavigationLink {
                        TopicSettingsView()
                    } label: {
                        Label("Moje témata", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    Stepper(value: $breakInterval, in: 0...100, step: 5) {
                        if breakInterval == 0 {
                            Text("Pauzu nepřipomínat")
                        } else {
                            Text("Pauza po \(breakInterval) článcích")
                        }
                    }
                } header: {
                    Text("Čtení")
                } footer: {
                    Text("Po daném počtu přečtených článků ti nabídneme krátkou pauzu.")
                }

                Section {
                    Picker("Videa ve feedu", selection: $videoInterval) {
                        ForEach(FeedSlotPlanner.videoIntervalOptions, id: \.self) { interval in
                            if interval == 0 {
                                Text("Vypnuto").tag(interval)
                            } else {
                                Text("Každá \(interval). karta").tag(interval)
                            }
                        }
                    }
                } header: {
                    Text("Videa")
                } footer: {
                    if YouTubeConfiguration.isAvailable {
                        Text("Krátká naučná videa z vybraných kanálů YouTube. Nikdy se nespouštějí sama.")
                    } else {
                        Text("Videa nejsou v této verzi aplikace k dispozici (chybí klíč k YouTube API).")
                    }
                }

                Section {
                    Button("Obnovit doporučování") { confirmation = .resetWeights }
                    Button("Zapomenout zobrazené články") { confirmation = .forgetSeen }
                } header: {
                    Text("Personalizace")
                } footer: {
                    Text("Doporučování probíhá jen v tomto zařízení. Ukládání a delší čtení zvyšují váhu tématu, „Nezajímá mě“ ji snižuje. Zhruba každý desátý článek je z tématu, které nemáš vybrané.")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("O aplikaci a licence", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Nastavení")
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                titleVisibility: .visible,
                presenting: confirmation
            ) { action in
                Button(action == .resetWeights ? "Obnovit" : "Zapomenout", role: .destructive) {
                    perform(action)
                }
            }
        }
    }

    private var confirmationTitle: LocalizedStringKey {
        switch confirmation {
        case .resetWeights: "Všechna témata budou mít znovu stejnou váhu."
        case .forgetSeen, nil: "Ve feedu se mohou znovu objevit články, které už jsi viděl/a."
        }
    }

    private func perform(_ action: Confirmation) {
        switch action {
        case .resetWeights:
            TopicPreferencesRepository(context: modelContext).resetWeights()
        case .forgetSeen:
            SeenArticlesRepository(context: modelContext).removeAll()
            SeenVideosRepository(context: modelContext).removeAll()
        }
        topicsVersion += 1
    }
}

struct TopicSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.topicsVersion) private var topicsVersion = 0
    @State private var selection: Set<String> = []
    @State private var initialSelection: Set<String> = []

    private var remaining: Int { max(0, AppConfig.minimumSelectedTopics - selection.count) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Vyber aspoň tři témata.")
                    .foregroundStyle(.secondary)
                TopicPickerGrid(selection: $selection)
            }
            .padding()
            .frame(maxWidth: Theme.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.screenBackground)
        .navigationTitle("Moje témata")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Uložit") {
                    TopicPreferencesRepository(context: modelContext).setSelected(selection)
                    topicsVersion += 1
                    dismiss()
                }
                .disabled(remaining > 0 || selection == initialSelection)
            }
        }
        .onAppear {
            let current = TopicPreferencesRepository(context: modelContext).selectedTopicIDs()
            selection = current
            initialSelection = current
        }
    }
}
