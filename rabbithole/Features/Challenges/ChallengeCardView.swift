import SwiftUI

/// The challenge inside a chat: question, answering (now or after reading), friendly result.
struct ChallengeCardView: View {
    let viewModel: ChatViewModel
    let article: ArticleSummary?

    @State private var mode: Mode = .choosing
    @State private var openAnswer = ""
    @State private var reporting = false

    private enum Mode {
        case choosing
        case answering(beforeReading: Bool)
    }

    var body: some View {
        if let challenge = viewModel.challenge {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Výzva", systemImage: "questionmark.bubble")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    if viewModel.isChallengeRecipient {
                        Menu {
                            Button("Nahlásit výzvu", systemImage: "flag") { reporting = true }
                        } label: {
                            Image(systemName: "ellipsis").padding(4)
                        }
                        .accessibilityLabel("Možnosti výzvy")
                    }
                }

                Text(challenge.question)
                    .font(.readingTitle(.headline))
                    .fixedSize(horizontal: false, vertical: true)

                content(for: challenge)

                if let error = viewModel.challengeError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 16))
            .sheet(isPresented: $reporting) {
                ReportUserView(profile: viewModel.other ?? PublicProfile(id: challenge.senderID, nickname: "?", avatarPath: nil)) {
                    reason, note, alsoBlock in
                    await viewModel.reportChallenge(reason: reason, note: note, alsoBlock: alsoBlock)
                }
            }
        }
    }

    @ViewBuilder private func content(for challenge: Challenge) -> some View {
        if let result = viewModel.challengeResult {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.headline).font(.body.weight(.medium))
                if let detail = result.detail {
                    Text(detail).foregroundStyle(.secondary)
                }
                Text("Napiš k tomu něco do chatu ↓")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        } else if !viewModel.isChallengeRecipient {
            Text("Čeká se, až \(viewModel.other?.nickname ?? "") odpoví.")
                .foregroundStyle(.secondary)
        } else {
            switch mode {
            case .choosing:
                ViewThatFits(in: .horizontal) {
                    HStack { choiceButtons }
                    VStack(alignment: .leading) { choiceButtons }
                }
            case .answering(let beforeReading):
                answerControls(for: challenge, beforeReading: beforeReading)
            }
        }
    }

    @ViewBuilder private var choiceButtons: some View {
        Button("Tipnout si hned") { mode = .answering(beforeReading: true) }
            .buttonStyle(.borderedProminent)
        if let article {
            NavigationLink {
                ArticleDetailScreen(article: article, topicID: "")
                    .onAppear { mode = .answering(beforeReading: false) }
            } label: {
                Text("Nejdřív si přečíst článek")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private func answerControls(for challenge: Challenge, beforeReading: Bool) -> some View {
        switch challenge.kind {
        case .multipleChoice:
            VStack(spacing: 8) {
                ForEach(Array((challenge.options ?? []).enumerated()), id: \.offset) { index, option in
                    Button {
                        Task { await viewModel.answerChallenge(optionIndex: index, text: nil, beforeReading: beforeReading) }
                    } label: {
                        Text(option).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isAnswering)
                }
            }
        case .open:
            HStack {
                TextField("Tvoje odpověď", text: $openAnswer)
                    .textFieldStyle(.roundedBorder)
                Button("Odpovědět") {
                    Task { await viewModel.answerChallenge(optionIndex: nil, text: openAnswer, beforeReading: beforeReading) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(openAnswer.trimmingCharacters(in: .whitespaces).isEmpty
                          || openAnswer.count > ChallengeDraft.maxAnswerLength || viewModel.isAnswering)
            }
        }
    }
}
