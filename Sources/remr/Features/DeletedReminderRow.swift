import SwiftUI

/// One shadow-copied deletion in the Recently Deleted tab.
struct DeletedReminderRow: View {
    @EnvironmentObject var store: ReminderStore
    let deleted: DeletedReminder
    /// Keyboard-selection highlight (accent fill, same as the suggestion dropdown).
    var isSelected: Bool = false
    var onRestored: (() -> Void)? = nil
    var onDeletedForever: (() -> Void)? = nil
    @State private var restoreError: String?
    @State private var confirmDeleteForever = false

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
                .buttonStyle(.bordered)
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
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
        .contentShape(Rectangle())
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
