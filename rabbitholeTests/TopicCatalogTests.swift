import Testing
@testable import rabbithole

struct TopicCatalogTests {
    @Test func idsAreUnique() {
        let ids = TopicCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyTopicHasCategoriesWithoutPrefix() {
        for topic in TopicCatalog.all {
            #expect(!topic.categories.isEmpty, "\(topic.id) has no categories")
            #expect(topic.categories.allSatisfy { !$0.hasPrefix("Kategorie:") })
        }
    }

    @Test func bothGroupsArePopulated() {
        #expect(TopicCatalog.all.filter { $0.group == .world }.count == 12)
        #expect(TopicCatalog.all.filter { $0.group == .personal }.count == 15)
    }

    @Test func videoCatalogCoversExactlyTheCatalogTopics() {
        #expect(Set(VideoChannelCatalog.channelsByTopic.keys) == Set(TopicCatalog.all.map(\.id)))
    }

    @Test func topicsDifferInCategories() {
        let sets = TopicCatalog.all.map { Set($0.categories) }
        #expect(Set(sets).count == sets.count, "two topics would produce the same feed")
    }
}
