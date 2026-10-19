import SwiftUI

/// Chat about one shared article.
struct ChatView: View {
    @State var viewModel: ChatViewModel
    @State private var reporting: ChatMessage?
    @State private var confirmsBlock = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let thread = viewModel.thread {
                        ArticleHeader(thread: thread)
                            .padding(.bottom, 8)
                    }
                    if viewModel.hasOlder {
                        Button("Načíst starší zprávy") {
                            Task { await viewModel.loadOlder() }
                        }
                        .font(.footnote)
                    }
                    if viewModel.isLoaded, viewModel.messages.isEmpty {
                        Text("Zatím tu nejsou žádné zprávy.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, isMine: message.authorID == viewModel.me)
                            .id(message.id)
                            .contextMenu { menu(for: message) }
                    }
                }
                .padding()
                .frame(maxWidth: Theme.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .background(Theme.screenBackground)
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(viewModel.other?.nickname ?? String(localized: "Konverzace"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Zablokovat", systemImage: "hand.raised", role: .destructive) { confirmsBlock = true }
                } label: {
                    Label("Další možnosti", systemImage: "ellipsis.circle")
                }
            }
        }
        .task { await viewModel.run() }
        .sheet(item: $reporting) { message in
            ReportUserView(profile: viewModel.other ?? PublicProfile(id: message.authorID, nickname: "?", avatarPath: nil)) { reason, note, alsoBlock in
                await viewModel.report(message, reason: reason, note: note, alsoBlock: alsoBlock)
            }
        }
        .confirmationDialog("Zablokovat uživatele?", isPresented: $confirmsBlock, titleVisibility: .visible) {
            Button("Zablokovat", role: .destructive) { Task { await viewModel.blockOther() } }
        } message: {
            Text("Přestanete být přáteli a nebude ti moct psát.")
        }
    }

    @ViewBuilder private func menu(for message: ChatMessage) -> some View {
        Button("Kopírovat", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.body }
        if message.authorID == viewModel.me {
            Button("Smazat", systemImage: "trash", role: .destructive) {
                Task { await viewModel.delete(message) }
            }
        } else {
            Button("Nahlásit zprávu", systemImage: "flag") { reporting = message }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Napiš zprávu", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($composerFocused)
                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Odeslat")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct ArticleHeader: View {
    let thread: ShareThread

    var body: some View {
        NavigationLink {
            ArticleDetailScreen(article: thread.article, topicID: "")
        } label: {
            HStack(spacing: 12) {
                if let url = thread.thumbnailURL {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.title)
                        .font(.readingTitle(.headline))
                        .multilineTextAlignment(.leading)
                    Label("Číst článek", systemImage: "book")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.cardBackground, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMine ? Color.accentColor.opacity(0.18) : Theme.cardBackground,
                                in: .rect(cornerRadius: 16))
                Text(message.createdAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }
}
