import SwiftUI

/// The fixed snooze actions shown for a reminder.
///
/// This view is deliberately limited to presentation and callback emission. It
/// does not calculate dates or access EventKit; the caller owns those concerns.
struct SnoozeMenu: View {
    let onChoice: (SnoozeChoice) -> Void
    let onCustom: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            snoozeButton("1 hour", systemImage: "clock") {
                onChoice(.oneHour)
            }
            snoozeButton("Later today", systemImage: "sun.max") {
                onChoice(.laterToday)
            }
            snoozeButton("Tomorrow morning", systemImage: "sunrise") {
                onChoice(.tomorrowMorning)
            }
            snoozeButton("Tomorrow evening", systemImage: "sunset") {
                onChoice(.tomorrowEvening)
            }
            snoozeButton("Next Monday", systemImage: "calendar") {
                onChoice(.nextMonday)
            }

            Divider()
                .padding(.vertical, 4)

            snoozeButton("Pick date/time", systemImage: "calendar.badge.clock") {
                onCustom()
            }
            snoozeButton("Clear due date", systemImage: "xmark.circle") {
                onClear()
            }
        }
        .padding(8)
        .frame(width: 190)
        .liquidGlassField(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Snooze options")
    }

    private func snoozeButton(_ title: String,
                              systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .accessibilityLabel(title)
    }
}
