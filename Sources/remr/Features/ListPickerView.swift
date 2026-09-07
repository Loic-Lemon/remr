import EventKit
import SwiftUI

/// List (category) visibility picker opened from the main list's toolbar.
/// Each row toggles one reminder list in the main list; the list updates live
/// behind the popover while it stays open, so hiding several lists at once is
/// a single flow. Counts come from the current (tag-filtered) pool and are
/// independent of visibility, so a hidden list still shows what it holds.
struct ListPickerView: View {
    /// Per-list incomplete counts in calendar order.
    let counts: [(EKCalendar, Int)]
    let onClose: () -> Void
    @EnvironmentObject private var settings: SettingsStore
    @State private var hoveredListID: String?

    var body: some View {
        VStack(spacing: 0) {
            RemrPopoverHeader(
                systemImage: "rectangle.3.group.fill",
                title: "Lists",
                subtitle: "Choose which reminder lists to show or hide.",
                onClose: onClose
            )

            Divider()

            if counts.isEmpty {
                Text("No reminder lists found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(counts, id: \.0.calendarIdentifier) { calendar, count in
                            row(calendar: calendar, count: count)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
                .scrollIndicators(.hidden)
            }

            Divider()

            HStack {
                Text("Hidden lists still count toward the menu bar badge")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 264)
        .liquidGlassGrouping()
    }

    private func row(calendar: EKCalendar, count: Int) -> some View {
        let identifier = calendar.calendarIdentifier
        let visible = !settings.hiddenLists.contains(identifier)
        return Button {
            settings.setListHidden(identifier, visible)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 10, height: 10)
                Text(calendar.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(visible ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if visible {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 12)
                } else {
                    Color.clear.frame(width: 12)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                if hoveredListID == identifier {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppPalette.controlTint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(visible ? "Hide" : "Show") \(calendar.title) list")
        .onHover { hovering in
            hoveredListID = hovering ? identifier : (hoveredListID == identifier ? nil : hoveredListID)
        }
    }
}
