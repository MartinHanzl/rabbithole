import Foundation
import Observation

@Observable
final class OnboardingViewModel {
    var selection: Set<String> = []

    private let repository: TopicPreferencesRepository

    init(repository: TopicPreferencesRepository) {
        self.repository = repository
    }

    var remaining: Int {
        max(0, AppConfig.minimumSelectedTopics - selection.count)
    }

    var canContinue: Bool { remaining == 0 }

    func finish() {
        guard canContinue else { return }
        repository.setSelected(selection)
    }
}
