import SwiftUI

/// A compact editor for a custom snooze date.
///
/// The picker owns only temporary control state. Date calculation and the
/// EventKit mutation remain with the caller. A disabled due date is emitted as
/// `(nil, false)`; otherwise the selected date and timed/all-day choice are
/// passed to `onSave`.
struct SnoozeDatePickerView: View {
    let onCancel: () -> Void
    let onSave: (Date?, Bool) -> Void

    @State private var dateEnabled: Bool
    @State private var date: Date
    @State private var hasTime: Bool

    init(initialDate: Date?,
         initialHasTime: Bool,
         onCancel: @escaping () -> Void,
         onSave: @escaping (Date?, Bool) -> Void) {
        self.onCancel = onCancel
        self.onSave = onSave
        _dateEnabled = State(initialValue: initialDate != nil)
        _date = State(initialValue: initialDate ?? Date())
        _hasTime = State(initialValue: initialHasTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snooze")
                .font(.headline)

            Toggle("Due date", isOn: $dateEnabled)

            if dateEnabled {
                DatePicker("Date", selection: $date, displayedComponents: displayedDateComponents)
                    .datePickerStyle(.field)

                Picker("Schedule", selection: $hasTime) {
                    Text("All day").tag(false)
                    Text("Timed").tag(true)
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .liquidGlassButtonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                if dateEnabled {
                    Button("Clear due date") {
                        onSave(nil, false)
                    }
                    .liquidGlassButtonStyle(.bordered)
                }

                Button("Save") {
                    onSave(dateEnabled ? date : nil, dateEnabled && hasTime)
                }
                .liquidGlassButtonStyle(.borderedProminent, prominent: true)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 310)
        .liquidGlassField(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Custom snooze date")
    }

    private var displayedDateComponents: DatePickerComponents {
        hasTime ? [.date, .hourAndMinute] : [.date]
    }
}
