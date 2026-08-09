import SwiftUI

/// One shadow-copied deletion in the Recently Deleted tab.
struct DeletedReminderRow: View {
    @EnvironmentObject var store: ReminderStore
    let deleted: DeletedReminder

    var body: some View {
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
                Task { await store.restore(deleted) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                store.deleteForever(deleted)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete forever")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
