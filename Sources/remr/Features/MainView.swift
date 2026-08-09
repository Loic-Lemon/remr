import EventKit
import SwiftUI

enum ReminderSection: String, CaseIterable {
    case overdue = "OVERDUE"
    case today = "TODAY"
    case later = "LATER"
}

/// The single-page popover: add a reminder on top, search below it,
/// and the unified reminder list beneath that.
struct MainView: View {
    @EnvironmentObject var store: ReminderStore
    @State private var searchText = ""
    @State private var showGuide = false
    @State private var completedToast: String?
    @State private var toastTask: Task<Void, Never>?
    /// Both tabs collapse until clicked ("should not show by default").
    @State private var showRecentlyCompleted = false
    @State private var showRecentlyDeleted = false

    /// All incomplete reminders, chronological (store's sort: due asc, nil last, title).
    private var allItems: [EKReminder] {
        store.allReminders.filter { !$0.isCompleted }
    }

    private var filteredItems: [EKReminder] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allItems }
        let query = SearchParser.parse(trimmed)
        let titles = Dictionary(uniqueKeysWithValues: store.reminderCalendars().map { ($0.calendarIdentifier, $0.title) })
        return allItems.filter { SearchParser.matches($0, query: query, calendarTitles: titles) }
    }

    /// Items not in overdue or today — belongs in LATER.
    private var laterItems: [EKReminder] {
        let overdueIDs = Set(store.overdue.map(\.calendarItemIdentifier))
        let todayIDs = Set(store.today.map(\.calendarItemIdentifier))
        return allItems.filter { !overdueIDs.contains($0.calendarItemIdentifier) && !todayIDs.contains($0.calendarItemIdentifier) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sections: [(ReminderSection, [EKReminder])] {
        ReminderSection.allCases.compactMap { section in
            let items: [EKReminder]
            switch section {
            case .overdue: items = store.overdue
            case .today: items = store.today
            case .later: items = laterItems
            }
            return items.isEmpty ? nil : (section, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NewReminderView()
            searchRow
            Divider()
            listArea
        }
    }

    /// Search field (gray rounded capsule) + the (i) guide button.
    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(AppPalette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(AppPalette.fieldStroke, lineWidth: 1))

            Button {
                showGuide = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("How to use remr")
            .popover(isPresented: $showGuide, arrowEdge: .bottom) {
                GuideView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var listArea: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredItems.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text(searchText.isEmpty ? "All caught up" : "No reminders match")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else if isSearching {
                        ForEach(filteredItems, id: \.calendarItemIdentifier) { reminder in
                            ReminderRowView(reminder: reminder) { completed in
                                showCompletedToast(completed.title)
                            }
                            Divider()
                                .padding(.leading, 12)
                        }
                    } else {
                        ForEach(sections, id: \.0) { section, items in
                            Text(section.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            ForEach(items, id: \.calendarItemIdentifier) { reminder in
                                ReminderRowView(reminder: reminder) { completed in
                                    showCompletedToast(completed.title)
                                }
                            }
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                    // Both tabs live outside the empty-state branch so they
                    // pop up even when nothing else is in the list.
                    if !isSearching {
                        if !store.completedReminders.isEmpty {
                            recentlyCompletedTab
                        }
                        if !store.recentlyDeleted.isEmpty {
                            recentlyDeletedTab
                        }
                    }
                }
            }
            if let completedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(completedToast)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(AppPalette.surface))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: completedToast)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Collapsed-by-default tab header shared by both recovery lists.
    private func tabHeader(_ title: String, count: Int, isOpen: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption.bold())
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Completed reminders, newest first, capped at the 5 most recent.
    private var recentlyCompletedTab: some View {
        VStack(spacing: 0) {
            tabHeader("Recently Completed", count: store.completedReminders.count,
                      isOpen: showRecentlyCompleted) {
                showRecentlyCompleted.toggle()
            }
            if showRecentlyCompleted {
                ForEach(store.completedReminders.prefix(5), id: \.calendarItemIdentifier) { reminder in
                    ReminderRowView(reminder: reminder) { completed in
                        showCompletedToast(completed.title)
                    }
                }
                Divider()
                    .padding(.leading, 12)
            }
        }
    }

    /// Shadow-copied deletions, newest first, capped at the 5 most recent.
    private var recentlyDeletedTab: some View {
        VStack(spacing: 0) {
            tabHeader("Recently Deleted", count: store.recentlyDeleted.count,
                      isOpen: showRecentlyDeleted) {
                showRecentlyDeleted.toggle()
            }
            if showRecentlyDeleted {
                ForEach(store.recentlyDeleted.prefix(5)) { deleted in
                    DeletedReminderRow(deleted: deleted)
                }
                Divider()
                    .padding(.leading, 12)
            }
        }
    }

    private func showCompletedToast(_ title: String) {
        completedToast = "Completed \"\(title)\" today"
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            completedToast = nil
        }
    }
}
