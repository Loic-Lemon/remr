import SwiftUI

/// One shadow-copied deletion in the Recently Deleted tab.
struct DeletedReminderRow: View {
    @EnvironmentObject var store: ReminderStore
    let deleted: DeletedReminder
    /// Keyboard/mouse-selection highlight (same glass treatment as the main list rows).
    var isSelected: Bool = false
    var onRestored: (() -> Void)? = nil
    var onDeletedForever: (() -> Void)? = nil
    @State private var restoreError: String?
    @State private var confirmDeleteForever = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deleted.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore") {
                    Task { @MainActor in
                        do {
                            try await store.restore(deleted)
                            restoreError = nil
                            onRestored?()
                        } catch {
                            restoreError = error.localizedDescription
                        }
                    }
                }
                .liquidGlassButtonStyle(.bordered)
                .controlSize(.small)
                Button {
                    confirmDeleteForever = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete forever")
            }
            if let restoreError {
                Text(restoreError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowSelectionHighlight(selected: isSelected, hovered: isHovered)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .confirmationDialog("Delete Forever?", isPresented: $confirmDeleteForever,
                            titleVisibility: .visible) {
            Button("Delete Forever", role: .destructive) {
                store.deleteForever(deleted)
                onDeletedForever?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var meta: String {
        var parts = ["Deleted \(deleted.deletedAt.formatted(date: .abbreviated, time: .shortened))"]
        if let cal = deleted.calendarIdentifier.flatMap({ id in
            store.reminderCalendars().first { $0.calendarIdentifier == id }
        }) {
            parts.append(cal.title)
        }
        return parts.joined(separator: " · ")
    }
}
