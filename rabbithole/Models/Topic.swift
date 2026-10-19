import Foundation

/// A user-facing topic backed by one or more Wikipedia categories. Defined in `TopicCatalog`.
struct Topic: Identifiable, Hashable, Sendable {
    enum Group: CaseIterable, Sendable {
        case world
        case personal

        var title: LocalizedStringResource {
            switch self {
            case .world: "Svět kolem nás"
            case .personal: "Osobní rozvoj a vztahy"
            }
        }
    }

    let id: String
    let name: LocalizedStringResource
    let symbol: String
    let categories: [String]
    var group: Group = .world

    static func == (lhs: Topic, rhs: Topic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
