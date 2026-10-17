import AppKit
import EventKit
import Foundation

/// Selected by the dedicated demo bundle, or explicitly with --demo for checks.
/// Never infer demo mode from a preference that could accidentally be toggled off.
enum DemoEnvironment {
    static let isEnabled = Bundle.main.bundleIdentifier == "com.local.remr.demo"
        || ProcessInfo.processInfo.arguments.contains("--demo")

    static let defaults: UserDefaults = {
        guard isEnabled else { return .standard }
        let domain = "com.local.remr.demo.preferences"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defaults.register(defaults: [
            "remr.notchPopover": true,
            "remr.reviewNudgesEnabled": false,
            "remr.ollamaEnabled": false,
        ])
        return defaults
    }()
}

/// These are genuine EventKit value objects, but are never saved to EventKit.
/// Their generated identifiers keep selection, editing and calendar drag/drop real.
final class DemoReminderData {
    let calendars: [EKCalendar]
    var reminders: [EKReminder] = []

    init(eventStore: EKEventStore, now: Date = Date()) {
        calendars = zip(["Work", "Personal", "Errands"],
                        [NSColor.systemBlue, .systemPurple, .systemOrange]).map { title, color in
            let list = EKCalendar(for: .reminder, eventStore: eventStore)
            list.title = title
            list.cgColor = color.cgColor
            return list
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let seeds: [(String, Int, Int?, Int, String)] = [
            ("Review website sketches", 0, 10, 0, "Compare the two homepage concepts.\n#design"),
            ("Pick up coffee beans", 0, 17, 2, "#shopping"),
            ("Prepare project outline", 1, 14, 0, "Outline goals and milestones.\n#planning"),
            ("Book a weekend walk", 2, nil, 1, "Choose a new trail.\n#weekend"),
            ("Share design feedback", 3, 11, 0, "#design"),
            ("Water the plants", 5, nil, 1, "#home"),
            ("Explore ideas for the next project", 9, nil, 0, "#planning"),
        ]
        for (title, day, hour, list, notes) in seeds {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = title
            reminder.calendar = calendars[list]
            reminder.notes = notes
            let date = calendar.date(byAdding: .day, value: day, to: today)!
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            if let hour { components.hour = hour; components.minute = 0 }
            reminder.dueDateComponents = components
            reminders.append(reminder)
        }
        let completed = EKReminder(eventStore: eventStore)
        completed.title = "Collect project inspiration"
        completed.calendar = calendars[0]
        completed.isCompleted = true
        completed.completionDate = now.addingTimeInterval(-3600)
        reminders.append(completed)
    }
}
