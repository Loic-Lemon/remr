import SwiftUI

/// Popover shown from the (i) button: how to add, search, and manage reminders.
struct GuideView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RemrPopoverHeader(
                systemImage: "info.circle.fill",
                title: "How to use remr",
                subtitle: "A quick reference for reminders, search, and keyboard controls.",
                onClose: onClose
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GuideSection(title: "Add", footer: "Enter: title → description → create. Shift+Enter: new line in the description.") {
                        GuideRow(example: "tomorrow at 5pm", explanation: "Due tomorrow at 5 PM")
                        GuideRow(example: "@home", explanation: "Put it in the Home list")
                        GuideRow(example: "@the office", explanation: "Also adds a location reminder")
                        GuideRow(example: "high priority", explanation: "Flag as high priority")
                        GuideRow(example: "at the office", explanation: "Adds a location reminder")
                        GuideRow(example: "in 2 days", explanation: "Relative due date")
                        GuideRow(example: "later", explanation: "Due by end of today")
                        GuideRow(example: "@list / #tag", explanation: "Live completion for lists and tags; Enter or Tab accepts")
                        GuideRow(example: "#groceries", explanation: "Tags it (colored chip, right-click to recolor)")
                        GuideRow(example: "Live parse preview", explanation: "Chips and warnings update as you type; nothing is saved yet")
                        GuideRow(example: "Multiline paste", explanation: "Preview each reminder row, then choose which to create")
                        GuideRow(example: "Create Selected", explanation: "Create only checked bulk rows; retry failed rows individually")
                        GuideRow(example: "Description", explanation: "A box appears as you type")
                        GuideRow(example: "Parser warning", explanation: "Unknown lists are shown without blocking a valid reminder")
                    }
                    GuideSection(title: "Keyboard") {
                        GuideRow(example: "⌥⌘R", explanation: "Open remr from anywhere (editable in Settings)")
                        GuideRow(example: "⌥⌘N", explanation: "Quick add from anywhere (editable in Settings)")
                        GuideRow(example: "Tab", explanation: "Next field: title → notes → search → list")
                        GuideRow(example: "Enter", explanation: "Complete (restore, expand a tab)")
                        GuideRow(example: "⌘⏎", explanation: "Open in Reminders")
                        GuideRow(example: "E", explanation: "Edit the selected reminder")
                        GuideRow(example: "S", explanation: "Snooze the selected reminder")
                        GuideRow(example: "⌘Z", explanation: "Undo the latest completion or deletion")
                        GuideRow(example: "1 hour · Later today", explanation: "Quick snooze presets")
                        GuideRow(example: "Tomorrow morning/evening", explanation: "Quick snooze presets")
                        GuideRow(example: "Next Monday", explanation: "Snooze until next Monday at 9 AM")
                        GuideRow(example: "Pick date/time", explanation: "Choose a custom snooze date or time")
                        GuideRow(example: "Clear due date", explanation: "Remove the due date without changing other fields")
                        GuideRow(example: "⌫", explanation: "Delete (permanent deletion asks for confirmation)")
                        GuideRow(example: "Archive icon / ←", explanation: "Open Recently Completed / Deleted")
                        GuideRow(example: "⌘F", explanation: "Search")
                        GuideRow(example: "Esc", explanation: "Step back: clear selection, then close")
                        GuideRow(example: "Space", explanation: "Scroll")
                        GuideRow(example: "Gear icon", explanation: "Customize these shortcuts in Settings")
                    }
                    GuideSection(title: "Search") {
                        GuideRow(example: "@list", explanation: "Only that list")
                        GuideRow(example: "#tag", explanation: "Titles or notes tagged with it")
                        GuideRow(example: "tag icon ▾", explanation: "Dropdown with a search box — pick a tag to filter")
                        GuideRow(example: "!!", explanation: "High priority only")
                        GuideRow(example: "text", explanation: "Matches title or notes")
                        GuideRow(example: "Click a #tag chip", explanation: "Show only reminders with it — sticks until you change it")
                    }
                    GuideSection(title: "Manage") {
                        GuideRow(example: "Tick the circle", explanation: "Mark complete (Undo is available for five seconds)")
                        GuideRow(example: "Click a row", explanation: "Selects it; double-click to edit in place")
                        GuideRow(example: "Sections", explanation: "Overdue · Today · This Week · Next Week · This Month · Next Month · Future")
                        GuideRow(example: "Right-click a row", explanation: "Complete, edit, snooze, open, or delete")
                        GuideRow(example: "Move to List", explanation: "Move the reminder without opening Reminders")
                        GuideRow(example: "Duplicate", explanation: "Create an incomplete copy with the same details")
                        GuideRow(example: "Copy Title", explanation: "Copy the title to the clipboard")
                        GuideRow(example: "Tag manager", explanation: "Rename, recolor, or remove tags across reminders")
                        GuideRow(example: "Delete a row", explanation: "It lands in Recently Deleted — restore or undo it")
                        GuideRow(example: "Inline editor", explanation: "Edit title, notes, date, list, priority, location, or tags")
                        GuideRow(example: "Save / Cancel", explanation: "Save inline changes or discard them without writing")
                        GuideRow(example: "Undo toast", explanation: "Its button or ⌘Z reverses the latest completion or deletion")
                        GuideRow(example: "Delete Forever", explanation: "Recently Deleted only; confirmation is required and it cannot be undone")
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 340, height: 430)
        .liquidGlassGrouping()
    }
}

private struct GuideSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background { sectionHeadingBackdrop }
            content
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    /// Heading strips sit BEHIND small caption text, and Liquid Glass lensing
    /// renders text caught in its sampling region blurry. These headings use
    /// plain vibrancy on macOS 26 too: sharp text, still a subtle separation
    /// from scrolled content. (Text inside a glass view — fields, chips — is
    /// composited on top of the glass and stays sharp.)
    private var sectionHeadingBackdrop: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.ultraThinMaterial)
    }
}

private struct GuideRow: View {
    let example: String
    let explanation: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(example)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 140, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .liquidGlassField(in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
