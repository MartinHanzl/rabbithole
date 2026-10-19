import Foundation
import SwiftData

/// Reads and writes `TopicPreference` rows. Ensures every catalog topic has a row.
final class TopicPreferencesRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// All preferences keyed by topic id, creating missing rows for new catalog topics.
    func allPreferences() -> [String: TopicPreference] {
        let existing = (try? context.fetch(FetchDescriptor<TopicPreference>())) ?? []
        var byID = Dictionary(existing.map { ($0.topicID, $0) }, uniquingKeysWith: { first, _ in first })
        for topic in TopicCatalog.all where byID[topic.id] == nil {
            let preference = TopicPreference(topicID: topic.id, isSelected: false)
            context.insert(preference)
            byID[topic.id] = preference
        }
        return byID
    }

    func selectedTopicIDs() -> Set<String> {
        Set(allPreferences().values.filter(\.isSelected).map(\.topicID))
    }

    func setSelected(_ topicIDs: Set<String>) {
        for (id, preference) in allPreferences() {
            preference.isSelected = topicIDs.contains(id)
        }
        try? context.save()
    }

    func weights() -> [String: Double] {
        allPreferences().mapValues(\.weight)
    }

    func resetWeights() {
        for preference in allPreferences().values {
            preference.weight = 1.0
        }
        try? context.save()
    }

    func setWeight(_ weight: Double, for topicID: String) {
        allPreferences()[topicID]?.weight = weight
        try? context.save()
    }
}
