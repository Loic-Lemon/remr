import AppKit
import SwiftUI

/// Tag-filter control beside Search. The picker is hosted in an AppKit
/// NSPopover rather than an in-window overlay: it cannot be clipped by the
/// 400pt popover, closes correctly on outside clicks, and opens without the
/// default popover animation.
struct TagFilterMenu: View {
    let allTags: [String]
    /// Reminder count per tag (lowercased), shown beside each row so the
    /// filter decision is informed. Not passed as part of `allTags` because
    /// the list and its counts come from different store queries.
    let tagCounts: [String: Int]
    @Binding var isPresented: Bool
    var onManage: () -> Void = {}
    @ObservedObject private var filterStore = FilterStore.shared
    @ObservedObject private var tagStore = TagStore.shared


    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filterStore.tag == nil ? "tag" : "tag.fill")
                    .font(.system(size: 12, weight: .medium))
                Text(filterStore.tag.map { "#\($0)" } ?? "Tags")
                    .lineLimit(1)
                Image(systemName: isPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(filterStore.tag.map { tagStore.color(for: $0) } ?? Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 30)
            .liquidGlassCapsule()
        }
        .buttonStyle(.plain)
        .help(filterStore.tag.map { "Filtered by #\($0) — click to change" } ?? "Filter by tag")
        .background {
            TagPopoverPresenter(
                isPresented: isPresented,
                content: AnyView(
                    TagPickerContent(
                        allTags: allTags,
                        tagCounts: tagCounts,
                        onSelect: { tag in
                            filterStore.toggle(tag)
                            isPresented = false
                        },
                        onManage: {
                            isPresented = false
                            onManage()
                        },
                        onDismiss: { isPresented = false }
                    )
                    .environmentObject(SettingsStore.shared)
                ),
                onDismiss: { isPresented = false }
            )
        }
        .onChange(of: filterStore.tag) { _ in
            if isPresented { isPresented = false }
        }
    }
}

/// A keyboard-navigable row in the picker: the clear-filter row, a tag, or
/// the footer. `nil` = nothing highlighted yet.
private enum PickerHighlight: Equatable {
    case all
    case tag(String)
    case manage
}

/// The actual picker content hosted by the native popover window.
private struct TagPickerContent: View {
    let allTags: [String]
    let tagCounts: [String: Int]
    let onSelect: (String) -> Void
    let onManage: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject private var settings: SettingsStore

    @ObservedObject private var filterStore = FilterStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @State private var search = ""
    @State private var highlighted: PickerHighlight?
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private var activeTag: String? { filterStore.tag }

    private var matchingTags: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allTags }
        return allTags.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Highlightable rows in list order: the "All tags" row, then matches.
    private var rowTags: [String?] {
        [nil] + matchingTags.map(Optional.some)
    }

    private func rowID(_ highlight: PickerHighlight) -> String {
        switch highlight {
        case .all: return "row:all"
        case .tag(let tag): return "row:tag:\(tag)"
        case .manage: return "footer"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tags", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button {
                        search = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear tag search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .liquidGlassField(in: Capsule())
            .padding(8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        allTagsRow
                            .id(rowID(.all))

                        if allTags.isEmpty {
                            Text("No tags yet — add #tag to a reminder")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                        } else if matchingTags.isEmpty {
                            Text("No matching tags")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                        } else {
                            ForEach(matchingTags, id: \.self) { tag in
                                tagRow(tag)
                                    .id(rowID(.tag(tag)))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
                .scrollIndicators(.hidden)
                .onChange(of: highlighted) { _ in
                    guard let highlighted else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(rowID(highlighted), anchor: .center)
                    }
                }
            }

            Divider()

            Button(action: onManage) {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Manage Tags")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    if highlighted == .manage {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppPalette.controlTint)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .help("Manage tags")
            .onHover { hovering in
                highlighted = hovering ? .manage : (highlighted == .manage ? nil : highlighted)
            }
        }
        .frame(width: 252, height: 300)
        .liquidGlassGrouping()
        .onAppear {
            DispatchQueue.main.async {
                searchFocused = true
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: search) { _ in
            highlighted = nil
        }
    }

    /// Clear-filter row, checked when no tag filter is active.
    private var allTagsRow: some View {
        Button {
            filterStore.clear()
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 11, height: 11)
                Text("All tags")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if activeTag == nil {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                if highlighted == .all {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppPalette.controlTint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All tags — clear filter")
        .onHover { hovering in
            highlighted = hovering ? .all : (highlighted == .all ? nil : highlighted)
        }
    }

    /// One tag row: color dot, name, matching reminder count, active check.
    private func tagRow(_ tag: String) -> some View {
        Button {
            onSelect(tag)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(tagStore.color(for: tag))
                    .frame(width: 9, height: 9)
                Text("#\(tag)")
                    .font(.caption)
                    .fontWeight(tag == activeTag ? .medium : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count = tagCounts[tag], count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                if tag == activeTag {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowFill(for: tag))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("#\(tag)")
        .onHover { hovering in
            highlighted = hovering ? .tag(tag) : (highlighted == .tag(tag) ? nil : highlighted)
        }
    }

    private func rowFill(for tag: String) -> Color {
        if tag == activeTag {
            return Color.accentColor.opacity(0.12)
        }
        if highlighted == .tag(tag) {
            return AppPalette.controlTint
        }
        return .clear
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        // Local monitor mirrors MainView's: the popover's events arrive in
        // its own window, so MainView's monitor passes them through untouched.
        // All mutable state here is reference-backed (@State/ObservedObject),
        // so the captured struct copy always reads current values; the monitor
        // is removed on disappear, breaking the dispatcher → closure cycle.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            switch event.keyCode {
            case 53: // Esc — clear the search first, then close.
                if !search.isEmpty {
                    search = ""
                    searchFocused = true
                } else {
                    onDismiss()
                }
                return nil
            case 36, 76: // Return / keypad Enter
                activateHighlight()
                return nil
            case 125: // Down
                moveHighlight(+1)
                return nil
            case 126: // Up
                moveHighlight(-1)
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func moveHighlight(_ delta: Int) {
        let rows = rowTags
        guard !rows.isEmpty else { return }
        let current: Int
        switch highlighted {
        case .tag(let tag): current = rows.firstIndex(of: tag) ?? 0
        case .all: current = 0
        case .manage: current = rows.count
        case nil: current = delta > 0 ? -1 : 0
        }
        let next = min(max(current + delta, 0), rows.count)
        highlighted = next == rows.count ? .manage : (rows[next].map(PickerHighlight.tag) ?? .all)
    }

    private func activateHighlight() {
        switch highlighted {
        case .all:
            filterStore.clear()
            onDismiss()
        case .tag(let tag):
            onSelect(tag)
        case .manage:
            onManage()
        case nil:
            if let first = matchingTags.first {
                onSelect(first)
            }
        }
    }
}

/// Presents SwiftUI content in an unanimated, transient native popover.
private struct TagPopoverPresenter: NSViewRepresentable {
    let isPresented: Bool
    let content: AnyView
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchor = nsView
        context.coordinator.onDismiss = onDismiss
        context.coordinator.update(isPresented: isPresented, content: content)
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        weak var anchor: NSView?
        var onDismiss: () -> Void
        private var popover: NSPopover?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func update(isPresented: Bool, content: AnyView) {
            if isPresented {
                let popover = self.popover ?? makePopover(content: content)
                self.popover = popover
                if let hosting = popover.contentViewController as? NSHostingController<AnyView> {
                    hosting.rootView = appearanceAwareContent(content)
                }
                Task { @MainActor [weak popover] in
                    popover?.contentViewController?.view.window?.appearance = SettingsStore.shared.appearance.nsAppearance
                }

                guard !popover.isShown, let anchor, !anchor.bounds.isEmpty else { return }
                DispatchQueue.main.async { [weak popover, weak anchor] in
                    guard let popover, let anchor,
                          !popover.isShown, !anchor.bounds.isEmpty else { return }
                    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
                    Task { @MainActor [weak popover] in
                        popover?.contentViewController?.view.window?.appearance = SettingsStore.shared.appearance.nsAppearance
                    }
                }
            } else if self.popover?.isShown == true {
                self.popover?.performClose(nil)
            }
        }

        private func makePopover(content: AnyView) -> NSPopover {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            popover.contentViewController = NSHostingController(rootView: appearanceAwareContent(content))
            return popover
        }

        private func appearanceAwareContent(_ content: AnyView) -> AnyView {
            let settings = MainActor.assumeIsolated { SettingsStore.shared }
            return AnyView(content.remrAppearance(using: settings))
        }

        func popoverDidClose(_ notification: Notification) {
            // NSPopover closes before the anchor button receives its click.
            // Do not reset the binding for an anchor click, or the button's
            // toggle would immediately reopen the popover. Outside clicks
            // still clear the binding normally.
            guard !isCurrentEventOnAnchor() else { return }
            onDismiss()
        }

        private func isCurrentEventOnAnchor() -> Bool {
            guard let anchor, let event = NSApp.currentEvent,
                  event.window === anchor.window else { return false }
            let point = anchor.convert(event.locationInWindow, from: nil)
            return anchor.bounds.contains(point)
        }

        deinit {
            popover?.close()
        }
    }
}
