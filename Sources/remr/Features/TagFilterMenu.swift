import AppKit
import SwiftUI

/// Tag-filter control beside Search. The picker is hosted in an AppKit
/// floating menu shared with the other dropdowns: it cannot be clipped by
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
                DropdownChevron(isPresented: isPresented)
            }
            .font(.system(size: 12, weight: .medium))
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
            FastDropdownPresenter(
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

/// The searchable tag menu, using the same layout as the list picker.
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
            DropdownHeader(title: "Tags",
                           subtitle: activeTag.map { "Filtered by #\($0)" } ?? "\(allTags.count) tags available",
                           onClose: onDismiss)
            DropdownSearchField(placeholder: "Search tags", text: $search, isFocused: $searchFocused)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DropdownMetrics.rowSpacing) {
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
                    .padding(.horizontal, DropdownMetrics.rowInset)
                    .padding(.vertical, 4)
                }
                .frame(height: min(260, CGFloat(matchingTags.count + 1) * DropdownMetrics.rowStride
                                   + (matchingTags.isEmpty ? 62 : 8)))
                .scrollIndicators(.hidden)
                .onChange(of: keyboardScrollTarget) { target in
                    guard let target else { return }
                    proxy.scrollTo(rowID(target))
                }
            }

            Divider().opacity(0.45).padding(.horizontal, 12)

            Button(action: onManage) {
                HStack(spacing: 10) {
                    DropdownIcon(systemImage: "gearshape")
                    Text("Manage Tags")
                        .font(.system(size: 12, weight: .medium))
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
        .frame(width: DropdownMetrics.width)
        .liquidGlassGrouping()
        .background(DropdownKeyHandler(onKey: handleKey))
        .onAppear {
            DispatchQueue.main.async {
                searchFocused = true
            }
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
            HStack(spacing: 10) {
                DropdownIcon(systemImage: "tag")
                Text("All tags")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                DropdownSelectionMark(selected: activeTag == nil)
            }
        }
        .buttonStyle(DropdownRowStyle(selected: activeTag == nil, highlighted: highlighted == .all))
        .accessibilityLabel("All tags — clear filter")
        .onHover { hovering in
            highlighted = hovering ? .all : (highlighted == .all ? nil : highlighted)
        }
    }

    /// One tag row: tinted icon, name, matching reminder count, selection mark.
    private func tagRow(_ tag: String) -> some View {
        Button {
            onSelect(tag)
        } label: {
            HStack(spacing: 10) {
                DropdownIcon(systemImage: "tag.fill", color: tagStore.color(for: tag))
                Text("#\(tag)")
                    .font(.system(size: 12))
                    .fontWeight(tag == activeTag ? .medium : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count = tagCounts[tag], count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                DropdownSelectionMark(selected: tag == activeTag)
            }
        }
        .buttonStyle(DropdownRowStyle(selected: tag == activeTag, highlighted: highlighted == .tag(tag)))
        .accessibilityLabel("#\(tag)")
        .onHover { hovering in
            highlighted = hovering ? .tag(tag) : (highlighted == .tag(tag) ? nil : highlighted)
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape clears the search before closing the menu.
            if !search.isEmpty {
                search = ""
                searchFocused = true
            } else {
                onDismiss()
            }
        case 36, 76:
            activateHighlight()
        case 125:
            moveHighlight(+1)
        case 126:
            moveHighlight(-1)
        default:
            return false
        }
        return true
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
