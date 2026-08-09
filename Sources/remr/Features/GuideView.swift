import SwiftUI

/// Popover shown from the (i) button: how to add, search, and manage reminders.
struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("How to use remr")
                    .font(.headline)
                GuideSection(title: "Add", footer: "Enter: title → description → create. Shift+Enter: new line in the description.") {
                    GuideRow(example: "tomorrow at 5pm", explanation: "Due tomorrow at 5 PM")
                    GuideRow(example: "@home", explanation: "Put it in the Home list")
                    GuideRow(example: "high priority", explanation: "Flag as high priority")
                    GuideRow(example: "at the office", explanation: "Adds a location reminder")
                    GuideRow(example: "in 2 days", explanation: "Relative due date")
                    GuideRow(example: "later", explanation: "Due by end of today")
                    GuideRow(example: "Tab", explanation: "Autocomplete dates & priority keywords")
                    GuideRow(example: "#groceries", explanation: "Tags it (colored chip, right-click to recolor)")
                    GuideRow(example: "Description", explanation: "A box appears as you type")
                }
                GuideSection(title: "Search") {
                    GuideRow(example: "@list", explanation: "Only that list")
                    GuideRow(example: "#tag", explanation: "Titles or notes containing it")
                    GuideRow(example: "!!", explanation: "High priority only")
                    GuideRow(example: "text", explanation: "Matches title or notes")
                }
                GuideSection(title: "Manage") {
                    GuideRow(example: "Tick the circle", explanation: "Mark complete")
                    GuideRow(example: "Swipe left", explanation: "Delete the reminder")
                    GuideRow(example: "Click a row", explanation: "Open it in Reminders")
                    GuideRow(example: "Right-click a row", explanation: "More options: complete, open, delete")
                    GuideRow(example: "Delete a row", explanation: "It lands in Recently Deleted — restore it there")
                }
            }
            .padding(16)
        }
        .frame(width: 340, height: 430)
        .preferredColorScheme(.light)
    }
}

private struct GuideSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct GuideRow: View {
    let example: String
    let explanation: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(example)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 140, alignment: .leading)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
