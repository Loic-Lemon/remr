import EventKit
import SwiftUI

/// Live list visibility picker. Counts include hidden lists and respect the tag filter.
struct ListPickerView: View {
    let counts: [(EKCalendar, Int)]
    let onClose: () -> Void
    @EnvironmentObject private var settings: SettingsStore
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var matchingLists: [(EKCalendar, Int)] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? counts : counts.filter { $0.0.title.localizedCaseInsensitiveContains(query) }
    }

    private var visibleCount: Int {
        counts.filter { !settings.hiddenLists.contains($0.0.calendarIdentifier) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            DropdownHeader(title: "Lists", subtitle: "\(visibleCount) of \(counts.count) shown",
                           actionTitle: "Show all", actionDisabled: visibleCount == counts.count,
                           onAction: {
                               for (calendar, _) in counts {
                                   settings.setListHidden(calendar.calendarIdentifier, false)
                               }
                           }, onClose: onClose)
            DropdownSearchField(placeholder: "Search lists", text: $search, isFocused: $searchFocused)

            ScrollView {
                LazyVStack(spacing: DropdownMetrics.rowSpacing) {
                    if matchingLists.isEmpty {
                        Text(counts.isEmpty ? "No reminder lists found" : "No matching lists")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    } else {
                        ForEach(matchingLists, id: \.0.calendarIdentifier) { calendar, count in
                            row(calendar: calendar, count: count)
                        }
                    }
                }
                .padding(.horizontal, DropdownMetrics.rowInset)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(height: min(260, matchingLists.isEmpty ? 62 : CGFloat(matchingLists.count) * DropdownMetrics.rowStride + 8))

            Divider().opacity(0.45).padding(.horizontal, 12)

            Text("Choose the lists shown in your reminders.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: DropdownMetrics.width)
        .liquidGlassGrouping()
        .onExitCommand(perform: onClose)
    }

    private func row(calendar: EKCalendar, count: Int) -> some View {
        let identifier = calendar.calendarIdentifier
        let visible = !settings.hiddenLists.contains(identifier)
        return Button {
            settings.setListHidden(identifier, visible)
        } label: {
            HStack(spacing: 10) {
                DropdownIcon(systemImage: "list.bullet", color: Color(cgColor: calendar.cgColor))
                Text(calendar.title)
                    .font(.system(size: 12, weight: visible ? .medium : .regular))
                    .foregroundStyle(visible ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                DropdownSelectionMark(selected: visible)
            }
        }
        .buttonStyle(DropdownRowStyle(selected: visible))
        .accessibilityLabel("\(calendar.title), \(count) reminders")
        .accessibilityValue(visible ? "Shown" : "Hidden")
        .accessibilityHint("Toggle list visibility")

    }
}
