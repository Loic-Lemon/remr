import AppKit
import SwiftUI

/// Settings screen (inline in the main popover, also the ⌘, Settings scene):
/// rebind the app's keyboard shortcuts. Editing is draft-based: each action's
/// row shows block chips (a modifier or a plain key) that can be replaced
/// (click the chip), removed (✕), or appended (+). Changes are NOT applied
/// until Save, which validates everything at once and shows per-row warnings
/// for anything invalid; nothing persists until every draft is valid.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var inheritedColorScheme

    /// Called by the inline "Back" button when Settings is rendered inside the
    /// main popover (MainView). nil in the standalone ⌘, Settings scene.
    var onClose: (() -> Void)? = nil

    /// Draft edits keyed by action; an action absent here keeps its saved combo.
    @State private var drafts: [BindableAction: KeyCombo] = [:]
    /// Per-action errors from the last Save attempt; editing a row clears its error.
    @State private var errors: [BindableAction: String] = [:]
    /// The block currently being captured: `index == nil` appends a new block,
    /// otherwise the block at `index` is replaced.
    @State private var capture: (action: BindableAction, index: Int?)?

    /// The combo a row displays: the draft when one exists, else the saved one.
    private func combo(for action: BindableAction) -> KeyCombo {
        drafts[action] ?? settings.combo(for: action)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Text("Theme changes apply immediately. Shortcut edits are saved when you press Save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Section {
                    Picker("Theme", selection: Binding(
                        get: { settings.appearance },
                        set: { settings.setAppearance($0) }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Appearance")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                } header: {
                    settingsSubheading("Appearance")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(nsImage: StatusIcon.image(symbol: settings.menuBarIconSymbol,
                                                            style: settings.menuBarIconStyle,
                                                            color: settings.menuBarIconColor))
                                .frame(width: 18, height: 18)
                            Text("Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Picker("Icon", selection: Binding(
                            get: { settings.menuBarIconSymbol },
                            set: { settings.setMenuBarIconSymbol($0) }
                        )) {
                            ForEach(MenuBarIconSymbol.allCases) { symbol in
                                Label(symbol.label, systemImage: symbol.systemName).tag(symbol)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Style", selection: Binding(
                            get: { settings.menuBarIconStyle },
                            set: { settings.setMenuBarIconStyle($0) }
                        )) {
                            ForEach(MenuBarIconStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Menu bar icon style")

                        Text("Automatic matches the menu bar (dark icon in light mode, white in dark mode). Accent colour uses your macOS accent. Custom colour lets you pick any colour.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if settings.menuBarIconStyle == .custom {
                            ColorPicker("Colour", selection: Binding(
                                get: { settings.menuBarIconColor },
                                set: { settings.setMenuBarIconColor($0) }
                            ), supportsOpacity: false)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                } header: {
                    settingsSubheading("Menu Bar Icon")
                }

                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(BindableAction.allCases) { action in
                            bindingRow(for: action)
                        }

                        if let error = settings.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background {
                        if capture != nil {
                            KeyRecorder(onElement: commit(_:), onCancel: cancelCapture)
                        }
                    }
                } header: {
                    settingsSubheading("Keyboard")
                }

                HStack {
                    Button("Save") {
                        save()
                    }
                    .liquidGlassButtonStyle(.borderedProminent, prominent: true)
                    .controlSize(.small)
                    .disabled(drafts.isEmpty)

                    Button("Reset to defaults") {
                        drafts = Dictionary(uniqueKeysWithValues: BindableAction.allCases.map {
                            ($0, DefaultBindings.all[$0]!)
                        })
                        errors = [:]
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.callout)
                }
                .padding(16)
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            settingsHeading
        }
        .padding(8)
        // Fill the whole popover pane when inline (MainView); the standalone
        // ⌘, Settings scene gets its system-proposed size, never smaller than
        // the previous fixed frame.
        .frame(minWidth: 360, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep the theme local to this view hierarchy. Unlike
        // preferredColorScheme, this does not reconfigure the presentation or
        // replace the inline Settings view when the picker changes.
        .environment(\.colorScheme, settings.appearance.colorScheme ?? inheritedColorScheme)
        .onDisappear {
            capture = nil
            settings.isCapturing = false
        }
    }

    private var settingsHeading: some View {
        HStack {
            Text("Settings")
                .font(.headline)
            Spacer()
            if let onClose {
                Button {
                    onClose()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .font(.callout.weight(.medium))
                }
                .liquidGlassButtonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Back to reminders")
                .help("Back to reminders")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background { settingsHeaderBackdrop }
        .zIndex(1)
    }

    /// Translucent glass keeps scrolled text from showing through the pinned
    /// labels without painting an opaque panel over the popover surface.
    @ViewBuilder
    private var settingsHeaderBackdrop: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(AppPalette.controlTint), in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
        }
    }

    /// Compact pinned chrome shared by every settings subsection. Keeping the
    /// subsection title separate from the fixed page title prevents overlap.
    private func settingsSubheading(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background { settingsHeaderBackdrop }
            .zIndex(1)
    }

    // MARK: - Binding row

    @ViewBuilder
    private func bindingRow(for action: BindableAction) -> some View {
        let elements = combo(for: action).elements
        let isCapturing = capture?.action == action
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(action.label)
                    .font(.callout)
                Spacer()
                if isCapturing {
                    captureHint
                } else {
                    if elements.isEmpty {
                        Text("None")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
                        elementChip(element, at: index, in: action)
                    }
                    Button {
                        beginCapture(for: action, index: nil)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add a key")
                }
            }
            if let error = errors[action] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var captureHint: some View {
        Text("Press a key… (Esc to cancel)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// One block of the chord: a keycap chip whose click re-captures the block
    /// and whose ✕ removes it.
    private func elementChip(_ element: KeyElement, at index: Int, in action: BindableAction) -> some View {
        HStack(spacing: 2) {
            Button(element.displayString) {
                beginCapture(for: action, index: index)
            }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .monospaced))
            Button {
                removeElement(at: index, in: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .liquidGlassKeycap()
    }

    // MARK: - Capture

    private func beginCapture(for action: BindableAction, index: Int?) {
        capture = (action, index)
        settings.isCapturing = true
    }

    private func cancelCapture() {
        capture = nil
        settings.isCapturing = false
    }

    /// One captured block: replace the target block or append a new one. Drafts
    /// are not validated here — Save does that, so intermediate shapes (e.g. a
    /// modifier with no plain key yet) are fine to experiment with.
    private func commit(_ element: KeyElement) {
        guard let target = capture else { return }
        var elements = combo(for: target.action).elements
        if let index = target.index {
            guard elements.indices.contains(index) else { return }
            elements[index] = element
        } else {
            elements.append(element)
        }
        drafts[target.action] = KeyCombo(elements)
        errors[target.action] = nil
        capture = nil
        settings.isCapturing = false
    }

    private func removeElement(at index: Int, in action: BindableAction) {
        var elements = combo(for: action).elements
        elements.remove(at: index)
        drafts[action] = KeyCombo(elements)
        errors[action] = nil
    }

    // MARK: - Save

    /// Validate every draft at once; if all valid, commit as one change and
    /// return to the main view. Invalid drafts stay editable with per-row
    /// warnings and nothing persists.
    private func save() {
        let result = settings.validate(drafts)
        if result.isEmpty {
            settings.commit(drafts)
            drafts = [:]
            errors = [:]
            onClose?()
        } else {
            errors = result
        }
    }
}

/// Captures the next key press as a single block. Rendered only while
/// `SettingsView.capture` is non-nil. Capture is window-independent: an
/// app-scoped local monitor — registered after MainView's, so it is consulted
/// first — consumes every key while capturing, with no reliance on the
/// settings window ever becoming key.
struct KeyRecorder: NSViewRepresentable {
    var onElement: (KeyElement) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(onElement: onElement, onCancel: onCancel)
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {}
}

final class RecorderView: NSView {
    private let onElement: (KeyElement) -> Void
    private let onCancel: () -> Void
    private var monitor: Any?

    init(onElement: @escaping (KeyElement) -> Void, onCancel: @escaping () -> Void) {
        self.onElement = onElement
        self.onCancel = onCancel
        super.init(frame: .zero)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                self.handleKeyDown(event)
            } else {
                self.handleFlagsChanged(event)
            }
            return nil  // always consume while capturing
        }
    }

    /// Shared key-down handling: Esc cancels, any other key becomes a block.
    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {  // Esc cancels capture
            onCancel()
            return
        }
        if let element = KeyElement(event: event) {
            onElement(element)
        }
    }

    /// Modifier presses arrive as flagsChanged, never keyDown. The event's
    /// flags hold the state AFTER the change, so the changed modifier is
    /// captured only while held (i.e. on press, not on release).
    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 54, 55: if flags.contains(.command) { onElement(.modifier(.command)) }
        case 56, 60: if flags.contains(.shift) { onElement(.modifier(.shift)) }
        case 58, 61: if flags.contains(.option) { onElement(.modifier(.option)) }
        case 59, 62: if flags.contains(.control) { onElement(.modifier(.control)) }
        default: break
        }
    }

    /// Accept first-responder status so the settings panel has a concrete key
    /// target; the responder `keyDown` is a backup path in case the local
    /// monitor doesn't fire in some context (no double-fire: the monitor
    /// consumes events it sees).
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        handleKeyDown(event)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
