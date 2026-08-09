import AppKit

/// Provider for the "Create Reminders" macOS Service (NSMessage
/// `remindersFromText`, matching the method name).
final class ServiceHandler: NSObject {
    static let shared = ServiceHandler()

    @objc func remindersFromText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { @MainActor in
            AppDelegate.instance?.showBulkPreview(text: text)
        }
    }
}
