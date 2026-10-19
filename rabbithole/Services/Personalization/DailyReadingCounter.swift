import Foundation

/// Counts cards read today and decides when to suggest a break. Resets at midnight.
nonisolated struct DailyReadingCounter: Codable, Equatable, Sendable {
    private(set) var day: Date
    private(set) var count: Int

    init(day: Date = .distantPast, count: Int = 0) {
        self.day = day
        self.count = count
    }

    /// Registers one read card and returns today's total.
    @discardableResult
    mutating func register(at date: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: date)
        if today != day {
            day = today
            count = 0
        }
        count += 1
        return count
    }

    func todayCount(at date: Date, calendar: Calendar = .current) -> Int {
        calendar.startOfDay(for: date) == day ? count : 0
    }

    /// `true` after every `interval`-th card (20, 40, …). `interval <= 0` disables breaks.
    static func shouldSuggestBreak(afterCount count: Int, interval: Int) -> Bool {
        interval > 0 && count > 0 && count % interval == 0
    }
}

/// Persists the counter in `UserDefaults`.
struct DailyReadingCounterStore {
    private let defaults: UserDefaults
    private let key = "dailyReadingCounter"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DailyReadingCounter {
        guard let data = defaults.data(forKey: key),
              let counter = try? JSONDecoder().decode(DailyReadingCounter.self, from: data) else {
            return DailyReadingCounter()
        }
        return counter
    }

    func save(_ counter: DailyReadingCounter) {
        defaults.set(try? JSONEncoder().encode(counter), forKey: key)
    }
}
