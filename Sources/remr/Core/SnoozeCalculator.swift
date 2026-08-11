import Foundation

enum SnoozeChoice: Equatable {
    case oneHour
    case laterToday
    case tomorrowMorning
    case tomorrowEvening
    case nextMonday
}

enum SnoozeCalculator {
    static func date(for choice: SnoozeChoice,
                     now: Date,
                     calendar: Calendar) -> (date: Date, hasTime: Bool)? {
        switch choice {
        case .oneHour:
            return (now.addingTimeInterval(60 * 60), true)

        case .laterToday:
            return dateAt(hour: 17, on: calendar.startOfDay(for: now), calendar: calendar)
                .map { ($0, true) }

        case .tomorrowMorning:
            return tomorrow(now: now, calendar: calendar)
                .flatMap { dateAt(hour: 9, on: $0, calendar: calendar) }
                .map { ($0, true) }

        case .tomorrowEvening:
            return tomorrow(now: now, calendar: calendar)
                .flatMap { dateAt(hour: 18, on: $0, calendar: calendar) }
                .map { ($0, true) }

        case .nextMonday:
            guard let nextMonday = nextMonday(after: now, calendar: calendar),
                  let date = dateAt(hour: 9, on: nextMonday, calendar: calendar) else {
                return nil
            }
            return (date, true)
        }
    }

    private static func tomorrow(now: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    }

    private static func dateAt(hour: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    private static func nextMonday(after now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let monday = 2 // Gregorian weekday numbering: Sunday = 1, Monday = 2.
        var daysUntilMonday = (monday - weekday + 7) % 7
        if daysUntilMonday == 0 {
            daysUntilMonday = 7
        }
        return calendar.date(byAdding: .day, value: daysUntilMonday, to: today)
    }
}
