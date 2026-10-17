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
            name: "Isolated demo mode",
            summary: "A separate demo bundle uses fictional in-memory reminders and isolated settings, resetting on launch without accessing Apple Reminders."),
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
            summary: "Creates reminders from a compact rounded glass composer matching Search, with title, notes, parsed fields, and validation."),
        FeatureInventoryItem(
            name: "Raycast Add Reminder",
            summary: "Creates natural-language reminders from Raycast with save confirmation; ⌘Return opens the prefilled remr composer for review."),
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
            summary: "Supports keyboard selection, completion, editing, search, recovery, undo, and focus movement. The main app opens without text focus so P and C work immediately; Space focuses Add a task, and Escape leaves the editor."),
        FeatureInventoryItem(
            name: "Organized settings",
            summary: "Groups preferences into four compact tabs with rounded cards, immediate preference changes, and a persistent shortcut save bar. Replaces the reminder controls while open, clips scrolling controls to the viewport, and discovers microphones off the main thread only in the voice section."),
        FeatureInventoryItem(
            name: "Shortcut customization",
            summary: "Uses ⌥Space to open remr by default with the menu bar icon’s native selection flash, with separate global and in-app shortcut groups, wrapping editable keycaps that stay inside narrow panels, validation, and conflict reporting."),
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
            name: "Notch panel",
            summary: "Opens reminders from the top screen edge with smaller 14-point shoulders, a window-backdrop blur, adaptive native glass on macOS 26, directional light, and a soft black blend into the camera housing."),
        FeatureInventoryItem(
            name: "Search field appearance",
            summary: "Uses compact rounded search and composer fields, subtle focus outlines, and larger toolbar hover targets."),
        FeatureInventoryItem(
            name: "Task composer focus appearance",
            summary: "Keeps the original compact task bar and native text/glass treatment. Focus adds a centered lift and a slowly shifting navy/indigo sky with an oversized, softly blurred moon cropped by the field, clouds and stars that wander smoothly in two dimensions, occasional star twinkles, and a 25% chance of one shooting star per opening; text stays steady, motion pauses when hidden, and Reduce Motion uses a static treatment."),
        FeatureInventoryItem(
            name: "Notch panel motion",
            summary: "Opens in 280 ms with a fixed-size blur and a moving glass rim, reuses warmed content, refreshes after opening, and reveals reminders and native-glass search/tag controls together only when motion finishes; respects Reduce Motion."),
        FeatureInventoryItem(
            name: "Opening animation speed",
            summary: "Chooses Slow, Normal, Fast, or Off for panel presentation; Reduce Motion disables animation."),
        FeatureInventoryItem(
            name: "Notch panel width",
            summary: "Adjusts the top-centred panel from 400 to 900 points with live resizing."),
        FeatureInventoryItem(
            name: "Screen opening haptics",
            summary: "Optionally gives the same gentle trackpad tap when opening screens, navigating pages, or presenting popovers, with one app-wide toggle in Panel settings."),
        FeatureInventoryItem(
            name: "Little sun review nudge",
            summary: "The notch widens into two slim menu-bar wings, with a smiling sun continuously waving and gently spinning back and forth on the left and a review action on the right; click to review, dismiss, or let it retract after 18 seconds without taking keyboard focus."),
        FeatureInventoryItem(
            name: "Random review intervals",
            summary: "Chooses a fresh random delay between configurable bounds (90–180 minutes by default), persists the next check-in, pauses presentation while away or busy, and restarts after opening remr."),
        FeatureInventoryItem(
            name: "Review nudge preview",
            summary: "Settings previews the sun immediately and controls whether nudges are enabled and their minimum/maximum delay."),
        FeatureInventoryItem(
            name: "Pomodoro timer",
            summary: "Runs focus and short-break sessions with adjustable durations and completion controls."),
        FeatureInventoryItem(
            name: "Local AI features",
            summary: "Uses local Ollama models for bulk cleanup, voice cleanup, and cached embedding-based Smart Search."),
        FeatureInventoryItem(
            name: "Voice capture and log",
            summary: "Captures spoken reminders, cleans them locally, and keeps a searchable voice log."),
        FeatureInventoryItem(
            name: "Search query language",
            summary: "Searches reminder text, @lists, #tags, and priority markers, including completed matches."),
        FeatureInventoryItem(
            name: "List visibility picker",
            summary: "Opens immediately with searchable lists, live counts, selection states, Show all, and a Select lists hover tooltip."),
        FeatureInventoryItem(
            name: "Tag filter picker",
            summary: "Provides a searchable tag dropdown with hover and press feedback, a Select tags tooltip, reminder counts, and tag management access."),
        FeatureInventoryItem(
            name: "Archive & recovery",
            summary: "Browses completed and recently deleted reminders with restore and permanent-delete safeguards."),
        FeatureInventoryItem(
            name: "Undo safety net",
            summary: "Reverses the latest completion or deletion for a short window from the toast or keyboard."),
        FeatureInventoryItem(
            name: "Dropdown appearance",
            summary: "Uses rounded glass cards, soft edges and shadows, consistent hover rows, and keyboard navigation for lists, tags, snooze, settings, colors, and action selectors."),
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
            name: "Calendar notch presentation",
            summary: "Opens from the primary display's top edge in 220 ms with a prewarmed, reusable calendar layout and its first paint warmed at launch, growing out of the open reminders panel's silhouette when one is on screen (an 80 ms glass handoff, then the shape expands), and returning by shrinking back into that silhouette before the panel fades in over it; keeps the grid out of reveal updates, settles the native glass at full size, then reveals content and Today. Preserves navigation and respects Reduce Motion."),
        FeatureInventoryItem(
            name: "Calendar shortcut in remr",
            summary: "Press C to switch between browsing reminders and the calendar; holding the key does not repeat, text entry and copy shortcuts stay intact, and the binding can be changed in Settings."),
        FeatureInventoryItem(
            name: "Calendar planning view",
            summary: "Visualizes reminders on month, week, and day views with snooze, drag-to-reschedule, lane-aligned Gantt bars from today to each due date, striped shading for days with no reminders or Gantt bar, a completed toggle, and a double-click detail page with map."),
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
