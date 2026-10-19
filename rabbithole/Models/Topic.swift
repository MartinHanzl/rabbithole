import Foundation

/// A user-facing topic backed by one or more Wikipedia categories. Defined in `TopicCatalog`.
struct Topic: Identifiable, Hashable, Sendable {
    let id: String
    let name: LocalizedStringResource
    let symbol: String
    let categories: [String]

    static func == (lhs: Topic, rhs: Topic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
