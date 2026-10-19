import SwiftUI

struct FriendsView: View {
    @State var viewModel: FriendsViewModel
    @State private var query = ""
    @State private var reporting: PublicProfile?
    @State private var confirmingBlock: PublicProfile?

    var body: some View {
        List {
            if let message = viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                searchSection
            } else {
                relationshipSections
            }
        }
        .navigationTitle("Přátelé")
        .searchable(text: $query, prompt: "Hledat podle přezdívky")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task(id: query) { await viewModel.search(query) }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $reporting) { profile in
            ReportUserView(profile: profile) { reason, note, alsoBlock in
                await viewModel.report(profile, reason: reason, note: note, alsoBlock: alsoBlock)
            }
        }
        .confirmationDialog(
            "Zablokovat uživatele?",
            isPresented: Binding(get: { confirmingBlock != nil }, set: { if !$0 { confirmingBlock = nil } }),
            titleVisibility: .visible,
            presenting: confirmingBlock
        ) { profile in
            Button("Zablokovat \(profile.nickname)", role: .destructive) {
                Task { await viewModel.block(profile) }
            }
        } message: { _ in
            Text("Přestanete být přáteli, nebude ti moct psát ani tě najít. Odblokovat ho můžeš v nastavení.")
        }
    }

    // MARK: Sections

    @ViewBuilder private var searchSection: some View {
        Section {
            if viewModel.searchResults.isEmpty {
                Text(viewModel.isSearching ? "Hledám…" : "Nikoho jsme nenašli.")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.searchResults) { profile in
                HStack {
                    ProfileLabel(profile: profile)
                    Spacer()
                    searchAction(for: profile)
                }
                .contextMenu { safetyMenu(for: profile) }
            }
        } header: {
            Text("Výsledky hledání")
        }
    }

    @ViewBuilder private func searchAction(for profile: PublicProfile) -> some View {
        switch viewModel.groups.relation(to: profile.id) {
        case .friend:
            Text("Přítel").foregroundStyle(.secondary)
        case .outgoing:
            Text("Žádost odeslána").foregroundStyle(.secondary)
        case .incoming:
            if let entry = viewModel.groups.entry(for: profile.id) {
                Button("Přijmout") { Task { await viewModel.accept(entry) } }
                    .buttonStyle(.borderedProminent)
            }
        case .none:
            Button("Přidat") { Task { await viewModel.sendRequest(to: profile) } }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var relationshipSections: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .failed:
            ContentUnavailableView {
                Label("Přátele se nepodařilo načíst", systemImage: "wifi.slash")
            } actions: {
                Button("Zkusit znovu") { Task { await viewModel.load() } }
            }
        case .loaded:
            if !viewModel.groups.incoming.isEmpty {
                Section("Žádosti o přátelství") {
                    ForEach(viewModel.groups.incoming) { entry in
                        HStack {
                            ProfileLabel(profile: entry.profile)
                            Spacer()
                            Button {
                                Task { await viewModel.remove(entry) }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Odmítnout")
                            Button {
                                Task { await viewModel.accept(entry) }
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Přijmout")
                        }
                        .contextMenu { safetyMenu(for: entry.profile) }
                    }
                }
            }

            Section {
                if viewModel.groups.friends.isEmpty {
                    Text("Zatím tu nikdo není. Najdi přátele podle přezdívky v poli nahoře.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.groups.friends) { entry in
                    ProfileLabel(profile: entry.profile)
                        .swipeActions {
                            Button("Odebrat", role: .destructive) {
                                Task { await viewModel.remove(entry) }
                            }
                        }
                        .contextMenu {
                            Button("Odebrat z přátel", systemImage: "person.badge.minus") {
                                Task { await viewModel.remove(entry) }
                            }
                            safetyMenu(for: entry.profile)
                        }
                }
            } header: {
                Text("Přátelé")
            }

            if !viewModel.groups.outgoing.isEmpty {
                Section("Odeslané žádosti") {
                    ForEach(viewModel.groups.outgoing) { entry in
                        HStack {
                            ProfileLabel(profile: entry.profile)
                            Spacer()
                            Button("Zrušit") { Task { await viewModel.remove(entry) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func safetyMenu(for profile: PublicProfile) -> some View {
        Button("Nahlásit", systemImage: "flag") { reporting = profile }
        Button("Zablokovat", systemImage: "hand.raised", role: .destructive) { confirmingBlock = profile }
    }
}

/// Avatar (initial for now) and nickname.
struct ProfileLabel: View {
    let profile: PublicProfile

    var body: some View {
        HStack(spacing: 12) {
            Text(String(profile.nickname.prefix(1)).uppercased())
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.15), in: .circle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(profile.nickname)
        }
    }
}
