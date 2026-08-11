import AppKit
import SwiftUI

/// Tag-filter control beside Search. The picker is hosted in an AppKit
/// NSPopover rather than an in-window overlay: it cannot be clipped by the
/// 400pt popover, closes correctly on outside clicks, and opens without the
/// default popover animation.
struct TagFilterMenu: View {
    let allTags: [String]
    @Binding var isPresented: Bool
    var onManage: () -> Void = {}
    @ObservedObject private var filterStore = FilterStore.shared
    @ObservedObject private var tagStore = TagStore.shared


    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: filterStore.tag == nil ? "tag" : "tag.fill")
                    .font(.system(size: 11, weight: .medium))
                Text(filterStore.tag.map { "#\($0)" } ?? "Tags")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: isPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(filterStore.tag.map { tagStore.color(for: $0) } ?? Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
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
                        onSelect: { tag in
                            filterStore.toggle(tag)
                            isPresented = false
                        },
                        onManage: {
                            isPresented = false
                            onManage()
                        }
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

/// The actual picker content hosted by the native popover window.
private struct TagPickerContent: View {
    let allTags: [String]
    let onSelect: (String) -> Void
    let onManage: () -> Void
    @EnvironmentObject private var settings: SettingsStore

    @ObservedObject private var filterStore = FilterStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var matchingTags: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allTags }
        return allTags.filter { $0.localizedCaseInsensitiveContains(query) }
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
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear tag search")
                }
                Button(action: onManage) {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Manage tags")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidGlassField(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    if matchingTags.isEmpty {
                        Text(allTags.isEmpty ? "No tags yet — add #tag to a reminder" : "No matching tags")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                    }
                    ForEach(matchingTags, id: \.self) { tag in
                        Button {
                            onSelect(tag)
                        } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(tagStore.color(for: tag))
                                    .frame(width: 8, height: 8)
                                Text("#\(tag)")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if tag == filterStore.tag {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background {
                                if tag == filterStore.tag {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.12))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 240, height: 290)
        .onAppear {
            DispatchQueue.main.async {
                searchFocused = true
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
                    hosting.rootView = content
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
            popover.contentViewController = NSHostingController(rootView: content)
            return popover
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
