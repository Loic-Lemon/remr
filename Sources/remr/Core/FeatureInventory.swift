import SwiftUI

enum FeatureInventoryStatus: String, CaseIterable, Identifiable {
    case implemented
    case inProgress
    case planned
    case idea

    var id: Self { self }

    var label: String {
        switch self {
        case .implemented: return "Implemented"
        case .inProgress: return "In progress"
        case .planned: return "Planned"
        case .idea: return "Idea"
        }
    }

    var systemImage: String {
        switch self {
        case .implemented: return "checkmark.circle.fill"
        case .inProgress: return "circle.dotted"
        case .planned: return "circle"
        case .idea: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .implemented: return .green
        case .inProgress: return .orange
        case .planned: return .secondary
        case .idea: return .purple
        }
    }
}

struct FeatureInventoryItem: Identifiable {
    let id: String
    let name: String
    let summary: String
    let status: FeatureInventoryStatus

    init(name: String, summary: String, status: FeatureInventoryStatus = .implemented) {
        self.id = name
        self.name = name
        self.summary = summary
        self.status = status
    }
}

/// The single source of truth for the feature table shown from Settings.
/// Keep this list synchronized with every shipped feature and tracked idea.
enum FeatureInventory {
    static let all: [FeatureInventoryItem] = [
        FeatureInventoryItem(
            name: "Reminders permission",
            summary: "Requests and tracks Reminders access, including denied and not-determined states."),
        FeatureInventoryItem(
            name: "EventKit sync",
            summary: "Refreshes reminders, completed items, deleted snapshots, counts, and sync status."),
        FeatureInventoryItem(
            name: "Natural-language dates & times",
            summary: "Understands tomorrow, relative dates, clock times, all-day values, and passed-time rollover."),
        FeatureInventoryItem(
            name: "List & priority parsing",
            summary: "Recognizes @lists and priority phrases or tokens and maps them to reminder fields."),
        FeatureInventoryItem(
            name: "Tag parsing",
            summary: "Extracts #tags and preserves them through creation, editing, search, and filtering."),
        FeatureInventoryItem(
            name: "Location parsing & geocoding",
            summary: "Handles & locations, anchored here/my location, and one-shot resolution when a reminder is saved."),
        FeatureInventoryItem(
            name: "Single reminder creation",
            summary: "Creates reminders from the in-app composer with title, notes, parsed fields, and validation."),
        FeatureInventoryItem(
            name: "Quick Add",
            summary: "Opens a focused reminder composer from anywhere with a global shortcut."),
        FeatureInventoryItem(
            name: "Inline reminder editing",
            summary: "Edits title, notes, due date, time, list, priority, location, and tags in place."),
        FeatureInventoryItem(
            name: "Bulk preview",
            summary: "Parses multiline input into a reviewable list of reminder drafts before writing anything."),
        FeatureInventoryItem(
            name: "Bulk selective creation",
            summary: "Creates selected rows independently and supports per-row edits, failures, and retries."),
        FeatureInventoryItem(
            name: "Tag manager",
            summary: "Renames, recolors, and removes tags across reminders from one management view."),
        FeatureInventoryItem(
            name: "Snooze presets",
            summary: "Provides one-hour, later-today, tomorrow, next-Monday, and weekend snooze actions."),
        FeatureInventoryItem(
            name: "Custom snooze date/time",
            summary: "Selects a custom date, toggles timed or all-day behavior, and clears an existing due date."),
        FeatureInventoryItem(
            name: "Keyboard navigation",
            summary: "Supports keyboard selection, completion, editing, search, recovery, undo, and focus movement."),
        FeatureInventoryItem(
            name: "Shortcut customization",
            summary: "Rebinds in-app actions and both global shortcuts with validation and conflict reporting."),
        FeatureInventoryItem(
            name: "Appearance modes",
            summary: "Supports Light, Dark, and Follow System with live application to every window and popover."),
        FeatureInventoryItem(
            name: "Menu bar icon customization",
            summary: "Chooses the symbol, automatic/accent/custom color, and optional overdue or due-today badge."),
        FeatureInventoryItem(
            name: "Live parse preview",
            summary: "Shows parsed fields, colored chips, and non-blocking diagnostics while typing."),
        FeatureInventoryItem(
            name: "Reminder popover",
            summary: "Provides the menu bar list, sections, selection, completion, context actions, and sync footer."),
        FeatureInventoryItem(
            name: "Search query language",
            summary: "Searches reminder text, @lists, #tags, and priority markers, including completed matches."),
        FeatureInventoryItem(
            name: "Tag filter picker",
            summary: "Provides a searchable tag dropdown, reminder counts, active-tag chips, and tag management access."),
        FeatureInventoryItem(
            name: "Archive & recovery",
            summary: "Browses completed and recently deleted reminders with restore and permanent-delete safeguards."),
        FeatureInventoryItem(
            name: "Undo safety net",
            summary: "Reverses the latest completion or deletion for a short window from the toast or keyboard."),
        FeatureInventoryItem(
            name: "Fast popovers",
            summary: "Uses immediate native popovers with controlled fades for guide, recovery, and tag surfaces."),
        FeatureInventoryItem(
            name: "Liquid Glass surfaces",
            summary: "Uses native macOS 26 glass with appearance-aware fallback materials on older macOS versions."),
        FeatureInventoryItem(
            name: "Ongoing reminders",
            summary: "Marks incomplete reminders as ongoing and keeps them in a dedicated pinned section."),
        FeatureInventoryItem(
            name: "macOS Services integration",
            summary: "Creates reminders from selected text in other apps through the system Services menu."),
        FeatureInventoryItem(
            name: "Feature inventory",
            summary: "Tracks shipped functionality and ideas from the bottom of Settings."),
        FeatureInventoryItem(
            name: "Smart lists & saved filters",
            summary: "Idea: save reusable combinations of search, tag, priority, and date filters.",
            status: .idea),
        FeatureInventoryItem(
            name: "Calendar planning view",
            summary: "Visualizes reminders on month, week, and day views with snooze, drag-to-reschedule, a completed toggle, and a double-click detail page with map."),
        FeatureInventoryItem(
            name: "Recurring reminder editor",
            summary: "Idea: create and edit recurrence rules directly instead of only displaying recurrence summaries.",
            status: .idea),
        FeatureInventoryItem(
            name: "Continuous task workflows",
            summary: "Idea: expand ongoing reminders into richer continuous or recurring task workflows.",
            status: .idea),
        FeatureInventoryItem(
            name: "Notification nudges",
            summary: "Idea: offer optional local notifications for reminders approaching their due time.",
            status: .idea)
    ]

    static var implementedCount: Int {
        all.filter { $0.status == .implemented }.count
    }

    static var ideaCount: Int {
        all.filter { $0.status == .idea }.count
    }
}
