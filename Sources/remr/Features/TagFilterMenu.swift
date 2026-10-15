import AppKit
import SwiftUI

/// Tag-filter control beside Search. The picker is hosted in an AppKit
/// NSPopover shared with the other toolbar pickers: it cannot be clipped by
/// the main surface, owns outside-click dismissal, and opens immediately.
struct TagFilterMenu: View {
    let allTags: [String]
    /// Reminder count per tag (lowercased), shown beside each row so the
    /// filter decision is informed. Not passed as part of `allTags` because
    /// the list and its counts come from different store queries.
    let tagCounts: [String: Int]
    @Binding var isPresented: Bool
    var onManage: () -> Void = {}
    var isDimmed = false
    @State private var isHovered = false
    @ObservedObject private var filterStore = FilterStore.shared
    @ObservedObject private var tagStore = TagStore.shared


    private var controlColor: Color {
        filterStore.tag.map { tagStore.color(for: $0) }
            ?? (isHovered || isPresented ? .primary : .secondary)
    }

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
            .foregroundStyle(controlColor)
        }
        .buttonStyle(DropdownTriggerStyle(isPresented: isPresented))
        .opacity(isDimmed ? 0.45 : 1)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Select tags")
        .overlay(alignment: .bottom) {
            if isHovered && !isPresented {
                Text("Select tags")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(AppPalette.controlStroke, lineWidth: 0.5))
                    .fixedSize()
                    .offset(y: 23)
                    .allowsHitTesting(false)
            }
        }
        .help(filterStore.tag.map { "Filtered by #\($0) — click to change" } ?? "Filter by tag")
        .background {
            FastPopoverPresenter(
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
    @State private var keyboardScrollTarget: PickerHighlight?
    @State private var keyMonitor: Any?
    @State private var pickerWindow: NSWindow?
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
            .liquidGlassField(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .onChange(of: keyboardScrollTarget) { target in
                    guard let target else { return }
                    proxy.scrollTo(rowID(target))
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
            }
            .buttonStyle(DropdownRowStyle(highlighted: highlighted == .manage))
            .padding(7)
            .help("Manage tags")
            .onHover { hovering in
                highlighted = hovering ? .manage : (highlighted == .manage ? nil : highlighted)
            }
        }
        .frame(width: 252, height: 300)
        .liquidGlassGrouping()
        .background(PickerWindowProbe { pickerWindow = $0 })
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
            keyboardScrollTarget = nil
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
        }
        .buttonStyle(DropdownRowStyle(selected: activeTag == nil, highlighted: highlighted == .all))
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
        }
        .buttonStyle(DropdownRowStyle(selected: tag == activeTag, highlighted: highlighted == .tag(tag)))
        .accessibilityLabel("#\(tag)")
        .onHover { hovering in
            highlighted = hovering ? .tag(tag) : (highlighted == .tag(tag) ? nil : highlighted)
        }
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
            guard let pickerWindow, event.window === pickerWindow else { return event }
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
        keyboardScrollTarget = highlighted
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

/// Tracks the picker window so its keyboard monitor cannot intercept other views.
private struct PickerWindowProbe: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.onWindow = onWindow
    }

    final class Probe: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onWindow?(self.window)
            }
        }
    }
}
