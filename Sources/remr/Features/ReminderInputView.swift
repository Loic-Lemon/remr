import AppKit
import SwiftUI

/// NSTextView that submits on plain Return and inserts a newline on Shift+Return.
/// While the keyword-suggestion dropdown is active, keyboard routing switches
/// to navigation (arrows), acceptance (Return/Tab), and dismissal (Escape).
final class EnterSubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    /// If set, any Return (plain or Shift) calls this instead of submitting
    /// or inserting a newline — used by the single-line title field.
    var onMoveDown: (() -> Void)?
    /// True for the single-line title field: plain Return moves to the next
    /// field (via `onMoveDown`) instead of submitting. Multi-line fields
    /// (notes) keep this false so plain Return submits and Shift+Return
    /// inserts a newline. Dispatch keys off this flag, NOT off `onMoveDown`
    /// being non-nil — the wiring always assigns that closure (as a no-op
    /// when the field has no move-down action), so closure nil-ness would
    /// dead-key Return in the notes field.
    var movesDownOnReturn = false
    /// Test hook; nil at runtime, set by tests to simulate Shift.
    var modifierFlagsOverride: NSEvent.ModifierFlags?
    /// Last focusRequest applied; the representable bumps it to grab focus.
    var appliedFocusRequest = 0
    /// Handed focus back if this view stole it on appearance (notes field).
    var onAppearInWindow: (() -> Void)?
    /// Suggestion dropdown is showing: arrows navigate, Return/Tab accept,
    /// Escape dismisses.
    var dropdownActive = false
    var onNavigate: ((_ up: Bool) -> Void)?
    var onDismiss: (() -> Void)?
    /// Tab with no dropdown advances focus to the next field.
    var onFocusForward: (() -> Void)?
    /// Shift+Tab moves focus to the previous field.
    var onFocusBack: (() -> Void)?
    /// Escape with no dropdown steps back (clear selection / close popover).
    var onEscape: (() -> Void)?
    /// Reports first-responder transitions (drives dropdown visibility).
    var onFocusChange: ((Bool) -> Void)?
    /// Last external replace-token request applied (accepting a suggestion).
    var appliedReplaceTokenRequest = 0

    private var effectiveModifiers: NSEvent.ModifierFlags {
        modifierFlagsOverride ?? NSEvent.modifierFlags
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false) }
        return ok
    }

    override func insertNewline(_ sender: Any?) {
        if movesDownOnReturn {
            onMoveDown?()
        } else if effectiveModifiers.contains(.shift) {
            super.insertNewline(sender)
        } else {
            onSubmit?()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, window.firstResponder === self else { return }
                self.onAppearInWindow?()
            }
        }
    }

    // MARK: - Suggestion dropdown keyboard routing

    override func insertTab(_ sender: Any?) {
        if dropdownActive {
            onMoveDown?()  // Tab accepts the highlighted suggestion
        } else {
            onFocusForward?()  // advance focus; no tab character is inserted
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if let onFocusBack {
            onFocusBack()
        } else {
            super.insertBacktab(sender)
        }
    }

    override func moveUp(_ sender: Any?) {
        if dropdownActive {
            onNavigate?(true)
        } else {
            super.moveUp(sender)
        }
    }

    override func moveDown(_ sender: Any?) {
        if dropdownActive {
            onNavigate?(false)
        } else {
            super.moveDown(sender)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if dropdownActive {
            onDismiss?()
        } else {
            onEscape?()
        }
    }

    // MARK: - Token access and replacement

    /// The partial word the caret is inside (bounded by whitespace).
    func currentToken() -> String {
        (string as NSString).substring(with: currentTokenRange)
    }

    private var currentTokenRange: NSRange {
        let text = string as NSString
        let caret = selectedRange().location
        guard caret != NSNotFound else { return NSRange(location: 0, length: 0) }
        var start = caret
        while start > 0 {
            let scalar = UnicodeScalar(text.character(at: start - 1))
            guard let scalar, !CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
            start -= 1
        }
        return NSRange(location: start, length: caret - start)
    }

    /// Replace the token under the caret and place the caret after it
    /// (used to accept a suggestion).
    func replaceCurrentToken(with replacement: String) {
        let range = currentTokenRange
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }
}

/// Borderless multi-line input backed by NSTextView: Enter submits,
/// Shift+Enter inserts a newline, text/placeholder alignment is exact.
/// The title field additionally feeds a keyword-suggestion dropdown.
struct ReminderInputView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void = {}
    /// When text is cleared externally (post-save), pull focus back to this field.
    var refocusOnClear = false
    /// If set, any Return moves to another field instead of submitting.
    var onMoveDown: (() -> Void)? = nil
    /// Bump to move focus to this field (e.g. Enter in the title jumps to notes).
    var focusRequest = 0
    /// Called if this field steals first responder on appearance (used by the
    /// notes field to hand focus back to the title).
    var onAppearInWindow: (() -> Void)? = nil
    /// Reports the token at the caret after edits and selection changes.
    var onTokenChange: ((String) -> Void)? = nil
    /// Reports first-responder transitions (drives dropdown visibility).
    var onFocusChange: ((Bool) -> Void)? = nil
    /// Suggestion dropdown state, routed into the keyboard handling.
    var dropdownActive = false
    var onNavigate: ((_ up: Bool) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    /// Tab with no dropdown advances focus to the next field.
    var onFocusForward: (() -> Void)? = nil
    /// Shift+Tab moves focus to the previous field.
    var onFocusBack: (() -> Void)? = nil
    /// Escape with no dropdown steps back (clear selection / close popover).
    var onEscape: (() -> Void)? = nil
    /// Bump to replace the token under the caret (accept a suggestion).
    var replaceTokenRequest = 0
    var replaceTokenWith = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = EnterSubmitTextView()
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.onSubmit = { context.coordinator.parent.onSubmit() }
        textView.onMoveDown = { context.coordinator.parent.onMoveDown?() }
        textView.movesDownOnReturn = context.coordinator.parent.onMoveDown != nil
        textView.onAppearInWindow = { context.coordinator.parent.onAppearInWindow?() }
        textView.onNavigate = { context.coordinator.parent.onNavigate?($0) }
        textView.onDismiss = { context.coordinator.parent.onDismiss?() }
        textView.onFocusForward = { context.coordinator.parent.onFocusForward?() }
        textView.onFocusBack = { context.coordinator.parent.onFocusBack?() }
        textView.onEscape = { context.coordinator.parent.onEscape?() }
        textView.onFocusChange = { context.coordinator.parent.onFocusChange?($0) }
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? EnterSubmitTextView else { return }
        // Dispatch keys off movesDownOnReturn (not closure nil-ness), so the
        // notes field's no-op onMoveDown closure can never dead-key Return.
        textView.movesDownOnReturn = context.coordinator.parent.onMoveDown != nil
        textView.dropdownActive = dropdownActive
        if textView.appliedReplaceTokenRequest != replaceTokenRequest {
            textView.appliedReplaceTokenRequest = replaceTokenRequest
            let replacement = replaceTokenWith
            // Applying inside updateNSView would call textDidChange →
            // binding write, which SwiftUI drops mid-update, and the string
            // sync below would then revert the replacement. Defer to the
            // next runloop tick, where the binding write propagates.
            DispatchQueue.main.async { [weak textView] in
                textView?.replaceCurrentToken(with: replacement)
            }
        }
        if textView.appliedFocusRequest != focusRequest {
            textView.appliedFocusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        // Only apply external clears (e.g. `input = ""` after save);
        // never reset the caret mid-typing.
        if textView.string != text {
            textView.string = text
            if refocusOnClear {
                // The notes field may vanish with the clear; pull focus back
                // to this field once the hierarchy settles.
                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReminderInputView

        init(_ parent: ReminderInputView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            (textView as? EnterSubmitTextView).map { parent.onTokenChange?($0.currentToken()) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? EnterSubmitTextView else { return }
            parent.onTokenChange?(textView.currentToken())
        }
    }
}
