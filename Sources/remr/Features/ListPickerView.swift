import EventKit
import SwiftUI

/// Live list visibility picker. Counts include hidden lists and respect the tag filter.
struct ListPickerView: View {
    let counts: [(EKCalendar, Int)]
    let onClose: () -> Void
    @EnvironmentObject private var settings: SettingsStore
    @State private var search = ""

    private var matchingLists: [(EKCalendar, Int)] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? counts : counts.filter { $0.0.title.localizedCaseInsensitiveContains(query) }
    }

    private var visibleCount: Int {
        counts.filter { !settings.hiddenLists.contains($0.0.calendarIdentifier) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lists")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(visibleCount) of \(counts.count) shown")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show all") {
                    for (calendar, _) in counts {
                        settings.setListHidden(calendar.calendarIdentifier, false)
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(visibleCount == counts.count)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close lists")
            }
            .padding(12)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search lists", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear list search")
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .liquidGlassField(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
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
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
            }
            .frame(height: min(260, matchingLists.isEmpty ? 62 : CGFloat(matchingLists.count) * 38 + 8))

            Text("Choose the lists shown in your reminders.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 272)
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
                Image(systemName: "list.bullet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(cgColor: calendar.cgColor))
                    .frame(width: 24, height: 24)
                    .background(Color(cgColor: calendar.cgColor).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(calendar.title)
                    .font(.system(size: 12, weight: visible ? .medium : .regular))
                    .foregroundStyle(visible ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                Image(systemName: visible ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(visible ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .frame(height: 36)
        }
        .buttonStyle(DropdownRowStyle(selected: visible))
        .accessibilityLabel("\(calendar.title), \(count) reminders")
        .accessibilityValue(visible ? "Shown" : "Hidden")
        .accessibilityHint("Toggle list visibility")

    }
}
