import SwiftUI

/// Grid of selectable topic tiles, used in onboarding and settings.
struct TopicPickerGrid: View {
    @Binding var selection: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(TopicCatalog.all) { topic in
                TopicTile(topic: topic, isSelected: selection.contains(topic.id)) {
                    if selection.contains(topic.id) {
                        selection.remove(topic.id)
                    } else {
                        selection.insert(topic.id)
                    }
                }
            }
        }
    }
}

private struct TopicTile: View {
    let topic: Topic
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: topic.symbol)
                        .font(.title2)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
                Text(topic.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Theme.cardBackground, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
