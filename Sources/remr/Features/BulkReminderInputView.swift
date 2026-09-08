import SwiftUI

/// Dedicated editor for multiline Markdown reminder imports.
struct BulkReminderInputView: View {
    let onCancel: () -> Void
    let onParse: (String) -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bulk Import")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .liquidGlassButtonStyle(.bordered)
                Button("Interpret") {
                    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !input.isEmpty { onParse(input) }
                }
                .liquidGlassButtonStyle(.borderedProminent, prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            TextEditor(text: $text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste Markdown with headings and reminder items…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                            .padding(.leading, 17)
                            .allowsHitTesting(false)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onCancel)
    }
}
