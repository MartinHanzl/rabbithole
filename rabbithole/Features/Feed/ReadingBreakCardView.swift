import SwiftUI

/// Gentle nudge shown every N cards – the app shouldn't be addictive at all costs.
struct ReadingBreakCardView: View {
    let count: Int
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Čas na malou pauzu?")
                .font(.readingTitle(.title2))
                .multilineTextAlignment(.center)

            Text("Dnes už víš o \(count) věcí víc. Možná je dobrá chvíle se protáhnout, nebo o něčem z toho říct někomu dalšímu.")
                .font(.readingBody)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Pokračovat ve čtení", action: onContinue)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: Theme.cornerRadius))
    }
}
