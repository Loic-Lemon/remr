import AppKit
import EventKit
import SwiftUI

/// Dedicated surface for completed and deleted reminders. Keeping recovery out
/// of the active list makes the primary list easier to scan while preserving
/// the same mutation and undo behavior as the main view.
struct RecoveryPopoverView: View {
    @EnvironmentObject private var store: ReminderStore
    let onClose: () -> Void

    let onToggleCompletion: (EKReminder, @escaping () -> Void) -> Void
    let onDelete: (EKReminder) -> Void
    let onEdit: (EKReminder) -> Void
    let onDuplicate: (EKReminder) -> Void
    let onMoveToList: (EKReminder, String?) -> Void
    let onCopyTitle: (EKReminder) -> Void
    let onRestored: (DeletedReminder) -> Void
    let onDeletedForever: (DeletedReminder) -> Void

    @State private var selectedTab: RecoveryTab = .completed
    @State private var selectedCompletedID: String?
    var body: some View {
        VStack(spacing: 0) {
            RemrPopoverHeader(
                systemImage: "archivebox.fill",
                title: "Recovery",
                subtitle: "Restore or manage recently completed and deleted reminders.",
                onClose: onClose
            )

            Divider()

            Picker("", selection: $selectedTab) {
                Text("Completed \(store.completedReminders.count)")
                    .tag(RecoveryTab.completed)
                Text("Deleted \(store.recentlyDeleted.count)")
                    .tag(RecoveryTab.deleted)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(4)
            .liquidGlassField(in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                switch selectedTab {
                case .completed:
                    completedContent
                case .deleted:
                    deletedContent
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 340, height: 430)
        .liquidGlassGrouping()
    }

    @ViewBuilder
    private var completedContent: some View {
        if store.completedReminders.isEmpty {
            emptyState(title: "No recently completed reminders", systemImage: "checkmark.circle")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(store.completedReminders.prefix(5), id: \.calendarItemIdentifier) { reminder in
                    ReminderRowView(
                        reminder: reminder,
                        isSelected: selectedCompletedID == reminder.calendarItemIdentifier,
                        onSelect: { selectedCompletedID = reminder.calendarItemIdentifier },
                        onOpen: { store.openInReminders(reminder) },
                        onToggleCompletion: onToggleCompletion,
                        onDelete: onDelete,
                        onEdit: onEdit,
                        onSnooze: { _ in },
                        onDuplicate: onDuplicate,
                        onMoveToList: onMoveToList,
                        onCopyTitle: onCopyTitle
                    )
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .opacity
                                                .combined(with: .scale(scale: 0.97))
                                                .combined(with: .offset(y: -4))))
                    Divider()
                        .padding(.leading, 12)
                }
                if store.completedReminders.count > 5 {
                    moreItemsHint(count: store.completedReminders.count - 5)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: store.completedReminders.count)
        }
    }

    @ViewBuilder
    private var deletedContent: some View {
        if store.recentlyDeleted.isEmpty {
            emptyState(title: "No recently deleted reminders", systemImage: "trash")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(store.recentlyDeleted.prefix(5)) { deleted in
                    DeletedReminderRow(
                        deleted: deleted,
                        onRestored: { onRestored(deleted) },
                        onDeletedForever: { onDeletedForever(deleted) }
                    )
                }
                if store.recentlyDeleted.count > 5 {
                    moreItemsHint(count: store.recentlyDeleted.count - 5)
                }
            }
        }
    }

    private func emptyState(title: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }

    private func moreItemsHint(count: Int) -> some View {
        Text("Showing 5 · \(count) more in Reminders")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

