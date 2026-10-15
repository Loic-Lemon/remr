import AppKit
import SwiftUI

/// Categorized settings, shared by the main popover and the ⌘, Settings scene.
/// Preferences apply immediately; keyboard shortcut editing is draft-based. Each action's
/// row shows block chips (a modifier or a plain key) that can be replaced
/// (click the chip), removed (✕), or appended (+). Changes are NOT applied
/// until Save, which validates everything at once and shows per-row warnings
/// for anything invalid; nothing persists until every draft is valid.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore

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
    // Device discovery can wake Core Audio. Never do it in a View initializer:
    // SwiftUI may construct this value repeatedly, even on unrelated updates.
    @State private var voiceInputDevices: [VoiceInputDevice] = []
    @State private var loadingVoiceDevices = false
    @State private var loadedVoiceDevices = false
    @State private var ollamaModels: [OllamaModelInfo] = []
    @State private var ollamaEmbeddingModels: [OllamaModelInfo] = []
    @State private var ollamaModelError: String?
    @State private var ollamaEmbeddingModelError: String?
    @State private var showOllamaRecommendations = false
    @ObservedObject private var ollamaUsage = OllamaUsageStore.shared

    private func loadOllamaModels() {
        guard settings.ollamaEnabled else {
            ollamaModels = []
            ollamaEmbeddingModels = []
            ollamaModelError = nil
            ollamaEmbeddingModelError = nil
            return
        }
        Task {
            do {
                let models = try await OllamaReminderParser().availableModels()
                ollamaModels = models.filter { !$0.isEmbedding }
                ollamaEmbeddingModels = models.filter(\.isEmbedding)
                ollamaModelError = models.isEmpty ? "No Ollama models found." : nil
                ollamaEmbeddingModelError = ollamaEmbeddingModels.isEmpty ?
                    "No embedding models found. Install nomic-embed-text with Ollama." : nil
            } catch {
                ollamaModels = []
                ollamaEmbeddingModels = []
                ollamaModelError = error.localizedDescription
                ollamaEmbeddingModelError = error.localizedDescription
            }
        }
    }

    /// The combo a row displays: the draft when one exists, else the saved one.
    private func combo(for action: BindableAction) -> KeyCombo {
        drafts[action] ?? settings.combo(for: action)
    }

    // The same compact navigation works in the menu bar and Settings window.
    enum Category: String, CaseIterable, Identifiable {
        case appearance = "Appearance"
        case workspace = "Workspace"
        case intelligence = "Intelligence"
        case shortcuts = "Shortcuts"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .appearance: return "paintpalette"
            case .workspace: return "rectangle.grid.1x2"
            case .intelligence: return "sparkles"
            case .shortcuts: return "keyboard"
            }
        }

        var summary: String {
            switch self {
            case .appearance: return "Theme and menu bar"
            case .workspace: return "Panel, reminders, and focus"
            case .intelligence: return "Local models and voice input"
            case .shortcuts: return "Global and in-app keyboard controls"
            }
        }
    }

    @State private var category: Category = .appearance

    var body: some View {
        VStack(spacing: 0) {
            settingsHeading
            categoryPicker
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    categoryContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .id(category)
            .scrollIndicators(.hidden)
            .clipped()

            if category == .shortcuts {
                shortcutActions
            } else {
                settingsFooter
            }
        }
        .padding(8)
        .frame(minWidth: 360, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .remrAppearance(using: settings)
        .background {
            if capture != nil {
                KeyRecorder(onElement: commit(_:), onCancel: cancelCapture)
            }
        }
        .onChange(of: category) { _ in
            cancelCapture()
            showOllamaRecommendations = false
        }
        .onDisappear {
            cancelCapture()
            showOllamaRecommendations = false
        }
        // No GlassEffectContainer here: the window root already provides one
        // (ContentView's surface), and a nested container re-samples every
        // glass element on top of it — expensive while the pane scrolls.
    }

    private var settingsHeading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(category.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Label("Back", systemImage: "chevron.backward")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .liquidGlassButtonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Back to reminders")
                .help("Back to reminders")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            ForEach(Category.allCases) { item in
                Button {
                    category = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(height: 17)
                        Text(item.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(category == item ? Color.accentColor : .secondary)
                    .background {
                        if category == item {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        }
                    }
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if item == .shortcuts && !drafts.isEmpty {
                            Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                                .padding(7)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.rawValue)
                .accessibilityAddTraits(category == item ? [.isSelected] : [])
                .accessibilityValue(item == .shortcuts && !drafts.isEmpty ? "Unsaved changes" : "")
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch category {
        case .appearance:
            themeSettings
            menuBarSettings
        case .workspace:
            panelSettings
            reminderSettings
            focusSettings
            reviewNudgeSettings
        case .intelligence:
            localModelSettings
            voiceSettings
            modelUsageSettings
        case .shortcuts:
            settingsDescription("Click a keycap to replace it, × to remove it, or + to add a key. Only shortcuts need saving.")
            keyboardSettings("From anywhere", symbol: "globe", actions: [
                .togglePopover, .quickAdd, .openCalendar, .voiceVerify, .voiceLog
            ])
            keyboardSettings("Inside remr", symbol: "keyboard", actions:
                BindableAction.allCases.filter { ![.togglePopover, .quickAdd, .openCalendar, .voiceVerify, .voiceLog].contains($0) })
        }
    }

    private func settingsCard<Content: View>(_ title: String, symbol: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func settingsDescription(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var themeSettings: some View {
        settingsCard("Theme", symbol: "circle.lefthalf.filled") {
            Picker("Theme", selection: Binding(
                get: { settings.appearance },
                set: { settings.setAppearance($0) }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Appearance")
            settingsDescription("Follows you across every remr window. Changes apply immediately.")
        }
    }

    private var menuBarSettings: some View {
        settingsCard("Menu bar icon", symbol: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(nsImage: StatusIcon.image(symbol: settings.menuBarIconSymbol,
                                                    style: settings.menuBarIconStyle,
                                                    color: settings.menuBarIconColor,
                                                    badge: settings.menuBarIconBadge,
                                                    count: settings.menuBarIconBadge == .none ? 0 : 3))
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your menu bar").font(.callout.weight(.medium))
                        Text(settings.menuBarIconBadge == .none ? "Live preview" : "Live preview · sample count: 3")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                RemrDropdown(title: "Icon", selection: Binding(
                    get: { settings.menuBarIconSymbol },
                    set: { settings.setMenuBarIconSymbol($0) }
                ), options: MenuBarIconSymbol.allCases.map {
                    DropdownOption(value: $0, title: $0.label, systemImage: $0.systemName)
                })

                Text("Colour style")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Style", selection: Binding(
                    get: { settings.menuBarIconStyle },
                    set: { settings.setMenuBarIconStyle($0) }
                )) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style == .automatic ? "Automatic" : style == .accent ? "Accent" : "Custom").tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Menu bar icon style")

                Text("Reminder badge")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Badge", selection: Binding(
                    get: { settings.menuBarIconBadge },
                    set: { settings.setMenuBarIconBadge($0) }
                )) {
                    ForEach(MenuBarIconBadge.allCases) { badge in
                        Text(badge.label).tag(badge)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Menu bar icon badge")

                Text("Automatic follows the menu bar. Accent uses your macOS colour; Custom lets you choose. Badges count incomplete reminders overdue or due today.")
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
        }
    }

    private var panelSettings: some View {
        settingsCard("Panel", symbol: "macwindow") {
            VStack(alignment: .leading, spacing: 10) {
                settingsToggle("Open from the notch", isOn: Binding(
                    get: { settings.notchPopover },
                    set: { settings.setNotchPopover($0) }
                ))
                .toggleStyle(.switch)
                .accessibilityLabel("Open from the notch")
                Text("Unfold a glass panel from the top centre of your main display. Turn off to open below the menu bar icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.notchPopover {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Panel width")
                            Spacer()
                            Text("\(Int(settings.notchPanelWidth)) pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(value: Binding(
                            get: { settings.notchPanelWidth },
                            set: { settings.setNotchPanelWidth($0) }
                        ), in: SettingsStore.notchPanelWidthRange, step: 20)
                        .accessibilityLabel("Panel width")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        settingsToggle("Trackpad haptic on open", isOn: Binding(
                            get: { settings.notchHapticEnabled },
                            set: { settings.setNotchHapticEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .accessibilityLabel("Trackpad haptic on open")
                        Text("A gentle tap when the panel opens, on a compatible trackpad.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var reminderSettings: some View {
        settingsCard("Reminders", symbol: "checklist") {
            VStack(alignment: .leading, spacing: 8) {
                settingsToggle("Compact items", isOn: Binding(
                    get: { settings.compactItems },
                    set: { settings.setCompactItems($0) }
                ))
                settingsDescription("Closer spacing and streamlined details fit more reminders in your list.")
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                settingsToggle("Show week calendar", isOn: Binding(
                    get: { settings.showBottomCalendar },
                    set: { settings.setShowBottomCalendar($0) }
                ))
                settingsDescription("Keep this week in view below your reminders, with daily counts for active and completed items.")
            }
        }
        .toggleStyle(.switch)
    }

    private var focusSettings: some View {
        settingsCard("Focus timer", symbol: "timer") {
            VStack(alignment: .leading, spacing: 10) {
                settingsToggle("Enable Pomodoro timer", isOn: Binding(
                    get: { settings.pomodoroEnabled },
                    set: { settings.setPomodoroEnabled($0) }
                ))
                .toggleStyle(.switch)
                .accessibilityLabel("Enable Pomodoro timer")
                Text("Add a focus timer to your workspace, with time remaining in the menu bar and a floating panel when sessions finish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reviewNudgeSettings: some View {
        settingsCard("Review nudges", symbol: "sun.max") {
            VStack(alignment: .leading, spacing: 12) {
                settingsToggle("Little sun check-ins", isOn: Binding(
                    get: { settings.reviewNudgesEnabled },
                    set: { settings.setReviewNudgesEnabled($0) }
                ))
                .toggleStyle(.switch)
                Text("A little sun waves from the notch when it's time to check your reminders. Click it to open remr.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.reviewNudgesEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("At least")
                            Spacer()
                            Text(ReviewNudgeTiming.label(minutes: settings.reviewNudgeMinimumMinutes))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: Binding(get: { settings.reviewNudgeMinimumMinutes },
                                              set: { settings.setReviewNudgeMinimumMinutes($0) }),
                               in: ReviewNudgeTiming.allowedMinutes, step: 15)
                            .accessibilityLabel("Minimum time between review nudges")
                        HStack {
                            Text("At most")
                            Spacer()
                            Text(ReviewNudgeTiming.label(minutes: settings.reviewNudgeMaximumMinutes))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: Binding(get: { settings.reviewNudgeMaximumMinutes },
                                              set: { settings.setReviewNudgeMaximumMinutes($0) }),
                               in: ReviewNudgeTiming.allowedMinutes, step: 15)
                            .accessibilityLabel("Maximum time between review nudges")
                    }
                    .font(.caption)
                    Text("Each check-in picks a random delay in this range. Pauses while you're away or using remr. Opening the main panel restarts the interval; Quick Add doesn't.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Preview the little sun") { AppDelegate.instance?.previewReviewNudge() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var localModelSettings: some View {
        settingsCard("Local model", symbol: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                settingsToggle("Enable local model features", isOn: Binding(
                    get: { settings.ollamaEnabled },
                    set: { settings.setOllamaEnabled($0) }
                ))
                .toggleStyle(.switch)
                .accessibilityLabel("Enable local model features")
                Text("Uses Ollama on this Mac for bulk import, voice cleanup, and Smart Search. Requests stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                RemrDropdown(title: "Model", selection: Binding(
                    get: { settings.ollamaModel },
                    set: { settings.setOllamaModel($0) }
                ), options: ollamaModels.isEmpty
                    ? [DropdownOption(value: settings.ollamaModel, title: settings.ollamaModel)]
                    : ollamaModels.map {
                        DropdownOption(value: $0.name, title: $0.summary.isEmpty ? $0.name : "\($0.name) — \($0.summary)")
                    })
                .disabled(!settings.ollamaEnabled || ollamaModels.isEmpty)

                RemrDropdown(title: "Embedding model", selection: Binding(
                    get: { settings.ollamaEmbeddingModel },
                    set: { settings.setOllamaEmbeddingModel($0) }
                ), options: ollamaEmbeddingModels.isEmpty
                    ? [DropdownOption(value: settings.ollamaEmbeddingModel, title: settings.ollamaEmbeddingModel)]
                    : ollamaEmbeddingModels.map {
                        DropdownOption(value: $0.name, title: $0.summary.isEmpty ? $0.name : "\($0.name) — \($0.summary)")
                    })
                .disabled(!settings.ollamaEnabled || ollamaEmbeddingModels.isEmpty)
                .help("Embedding model used by Smart Search")

                HStack(spacing: 12) {
                    Button("Refresh models") {
                        loadOllamaModels()
                    }
                    Button("Recommended models & setup") {
                        showOllamaRecommendations = true
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.caption)
                .remrPopover(isPresented: $showOllamaRecommendations, arrowEdge: .bottom) {
                    OllamaRecommendationsView()
                }
                if let ollamaModelError {
                    Text(ollamaModelError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let ollamaEmbeddingModelError {
                    Text(ollamaEmbeddingModelError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear { loadOllamaModels() }
        .onChange(of: settings.ollamaEnabled) { _ in loadOllamaModels() }
    }

    private var microphoneOptions: [DropdownOption<String>] {
        var options = [DropdownOption(value: "", title: "System default", systemImage: "mic")]
        if let savedID = settings.voiceInputDeviceID, !savedID.isEmpty,
           !voiceInputDevices.contains(where: { $0.id == savedID }) {
            options.append(DropdownOption(value: savedID,
                                          title: !loadedVoiceDevices || loadingVoiceDevices
                                            ? "Loading saved microphone…" : "Saved microphone unavailable"))
        }
        options += voiceInputDevices.map { DropdownOption(value: $0.id, title: $0.name, systemImage: "mic") }
        return options
    }

    private var voiceSettings: some View {
        settingsCard("Voice dictation", symbol: "waveform") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Voice dictation stays on-device", systemImage: "lock.shield")
                    .font(.callout.weight(.medium))
                RemrDropdown(title: "Microphone", selection: Binding(
                    get: { settings.voiceInputDeviceID ?? "" },
                    set: { settings.setVoiceInputDeviceID($0.isEmpty ? nil : $0) }
                ), options: microphoneOptions)
                Button(loadingVoiceDevices ? "Finding microphones…" : "Refresh microphones") {
                    Task { await refreshVoiceDevices() }
                }
                .disabled(loadingVoiceDevices)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.caption)
                if loadedVoiceDevices, !loadingVoiceDevices,
                   let savedID = settings.voiceInputDeviceID, !savedID.isEmpty,
                   !voiceInputDevices.contains(where: { $0.id == savedID }) {
                    Text("Saved microphone not found — recordings fall back to System default until you pick another.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Voice dictation requires Apple on-device speech recognition. If your Mac or language does not support it, remr stops instead of sending audio to a remote service. Audio is never saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear {
                if !loadedVoiceDevices {
                    Task { await refreshVoiceDevices() }
                }
            }
        }
    }

    @MainActor
    private func refreshVoiceDevices() async {
        guard !loadingVoiceDevices else { return }
        loadingVoiceDevices = true
        defer { loadingVoiceDevices = false }
        let devices = await Task.detached(priority: .utility) {
            VoiceInputDevices.available()
        }.value
        voiceInputDevices = devices
        loadedVoiceDevices = true
    }

    private var modelUsageSettings: some View {
        settingsCard("Local model usage", symbol: "chart.bar.xaxis") {
            HStack(spacing: 0) {
                usageMetric("Requests", value: "\(ollamaUsage.requestCount)")
                Spacer(minLength: 8)
                usageMetric("Average", value: String(format: "%.1fs", ollamaUsage.averageRequestSeconds))
                Spacer(minLength: 8)
                usageMetric("Active", value: String(format: "%.1f min", ollamaUsage.activeSeconds / 60))
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                usageRow("On battery", value: String(format: "%.0f%%", ollamaUsage.batteryRequestPercent))
                usageRow("Embedding cache hits", value: String(format: "%.0f%%", ollamaUsage.embeddingCacheHitPercent))
                usageRow("Errors", value: "\(ollamaUsage.errorCount)")
            }
            Button("Reset usage statistics") { ollamaUsage.reset() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.caption)
            settingsDescription("Statistics stay on this Mac.")
        }
    }

    private func usageMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func usageRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func keyboardSettings(_ title: String, symbol: String, actions: [BindableAction]) -> some View {
        settingsCard(title, symbol: symbol) {
            // Plain VStack: a lazy stack nested inside the pane's lazy stack
            // mounts and unmounts rows while scrolling, which hitches.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(actions) { action in
                    bindingRow(for: action)
                    if action != actions.last {
                        Divider().opacity(0.6)
                    }
                }
            }
        }
    }

    private var settingsFooter: some View {
        Text("Changes apply immediately")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private var shortcutActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Button("Reset to defaults") {
                    cancelCapture()
                    drafts = Dictionary(uniqueKeysWithValues: BindableAction.allCases.map {
                        ($0, DefaultBindings.all[$0]!)
                    })
                    errors = [:]
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.callout)
                Spacer()
                Button("Save", action: save)
                    .liquidGlassButtonStyle(.borderedProminent, prominent: true)
                    .controlSize(.small)
                    .disabled(drafts.isEmpty)
            }
            if !drafts.isEmpty {
                Text(errors.isEmpty ? "You have unsaved shortcut changes." : "Resolve the highlighted shortcuts, then save again.")
                    .font(.caption)
                    .foregroundStyle(errors.isEmpty ? Color.secondary : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = settings.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Binding row

    @ViewBuilder
    private func bindingRow(for action: BindableAction) -> some View {
        let elements = combo(for: action).elements
        let isCapturing = capture?.action == action
        VStack(alignment: .leading, spacing: 8) {
            Text(action.label)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if isCapturing {
                captureHint
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ShortcutFlowLayout(spacing: 6) {
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
                    .accessibilityLabel("Add a key to \(action.label)")
                }
            }
            if let error = errors[action] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(action.label)
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
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityLabel("Replace \(element.displayString) in \(action.label)")
            Button {
                removeElement(at: index, in: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove")
            .accessibilityLabel("Remove \(element.displayString) from \(action.label)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .liquidGlassKeycap(refractive: false)
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
        cancelCapture()
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

private struct OllamaRecommendationsView: View {
    private struct Recommendation: Identifiable {
        let id: String
        let name: String
        let summary: String
        let install: String
        let url: URL
    }

    private let processingRecommendations = [
        Recommendation(id: "qwen2.5:3b", name: "qwen2.5:3b",
                       summary: "Balanced quality and speed for bulk import and voice cleanup.",
                       install: "ollama pull qwen2.5:3b",
                       url: URL(string: "https://ollama.com/library/qwen2.5:3b")!),
        Recommendation(id: "qwen2.5:1.5b", name: "qwen2.5:1.5b",
                       summary: "Fastest and lightest option for bulk import and voice cleanup.",
                       install: "ollama pull qwen2.5:1.5b",
                       url: URL(string: "https://ollama.com/library/qwen2.5:1.5b")!),
        Recommendation(id: "llama3.2:3b", name: "llama3.2:3b",
                       summary: "Good general quality for local text processing.",
                       install: "ollama pull llama3.2:3b",
                       url: URL(string: "https://ollama.com/library/llama3.2:3b")!)
    ]

    private let embeddingRecommendations = [
        Recommendation(id: "nomic-embed-text", name: "nomic-embed-text",
                       summary: "Small, local embedding model for fast semantic Smart Search.",
                       install: "ollama pull nomic-embed-text",
                       url: URL(string: "https://ollama.com/library/nomic-embed-text")!)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended Ollama models")
                .font(.headline)
            Text("Processing models are used for Bulk Markdown import and voice cleanup. Embedding models are used only for Smart Search.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Processing models")
                .font(.subheadline.weight(.semibold))
            ForEach(processingRecommendations) { model in
                VStack(alignment: .leading, spacing: 4) {
                    Link(model.name, destination: model.url)
                        .font(.callout.weight(.semibold))
                    Text(model.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.install)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Text("Embedding models")
                .font(.subheadline.weight(.semibold))
            ForEach(embeddingRecommendations) { model in
                VStack(alignment: .leading, spacing: 4) {
                    Link(model.name, destination: model.url)
                        .font(.callout.weight(.semibold))
                    Text(model.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.install)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Text("Install Ollama from ollama.com, then run one of the commands above. Use Refresh models after installation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 330)
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
