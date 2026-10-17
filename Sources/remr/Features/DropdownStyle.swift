import AppKit
import SwiftUI

extension View {
    func remrDropdownSurface() -> some View { modifier(DropdownSurface()) }
}

private struct DropdownSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

/// Shared metrics and building blocks for every app-owned dropdown.
enum DropdownMetrics {
    static let width: CGFloat = 272
    static let rowHeight: CGFloat = 36
    static let rowSpacing: CGFloat = 2
    static let rowInset: CGFloat = 7
    static let rowStride = rowHeight + rowSpacing
}

struct DropdownHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var actionDisabled = false
    var onAction: () -> Void = {}
    var onBack: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle, action: onAction)
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(actionDisabled)
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title.lowercased())")
            }
        }
        .padding(12)
    }
}

struct DropdownSearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
            if !text.isEmpty {
                Button { text = ""; isFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .liquidGlassField(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

struct DropdownIcon: View {
    let systemImage: String
    var color: Color = .secondary
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct DropdownSelectionMark: View {
    let selected: Bool
    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.35))
    }
}

struct DropdownChevron: View {
    let isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .rotationEffect(.degrees(isPresented ? 180 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPresented)
    }
}

/// Rounded, full-width rows share their hover, pressed, and selected treatment.
struct DropdownRowStyle: ButtonStyle {
    var selected = false
    var highlighted = false

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected, highlighted: highlighted)
    }

    private struct Row: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        let highlighted: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: DropdownMetrics.rowHeight, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(configuration.isPressed || hovered || highlighted ? 0.24 : 0.13)
                              : Color.primary.opacity(configuration.isPressed ? 0.12 : (hovered || highlighted ? 0.07 : 0)))
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .onHover { hovered = $0 }
        }
    }
}

struct DropdownTriggerStyle: ButtonStyle {
    var isPresented = false
    func makeBody(configuration: Configuration) -> some View {
        Trigger(configuration: configuration, isPresented: isPresented)
    }
    private struct Trigger: View {
        let configuration: ButtonStyle.Configuration
        let isPresented: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .liquidGlassField(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (hovered || isPresented ? 0.06 : 0)))
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovered = $0 }
        }
    }
}

struct DropdownOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var systemImage: String? = nil
    var color: Color? = nil
    var id: Value { value }
}

/// Shared selector for lists, priority, models, microphones, icons, and colors.
struct RemrDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [DropdownOption<Value>]
    var showsTitle = true
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 8) {
            if showsTitle { Text(title).font(.system(size: 12)).foregroundStyle(.secondary) }
            Button { isPresented.toggle() } label: {
                HStack(spacing: 7) {
                    if let option = options.first(where: { $0.value == selection }), let image = option.systemImage {
                        Image(systemName: image).foregroundStyle(option.color ?? .secondary)
                    }
                    Text(options.first(where: { $0.value == selection })?.title ?? "Choose…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    DropdownChevron(isPresented: isPresented)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(DropdownTriggerStyle(isPresented: isPresented))
            .accessibilityLabel(title)
            .accessibilityValue(options.first(where: { $0.value == selection })?.title ?? "Choose")
            .background {
                FastDropdownPresenter(isPresented: isPresented,
                                     content: AnyView(DropdownOptions(title: title, selection: selection,
                                                                     options: options, onSelect: {
                    selection = $0
                    isPresented = false
                }, onDismiss: { isPresented = false })),
                                     onDismiss: { isPresented = false })
            }
        }
    }
}

private struct DropdownOptions<Value: Hashable>: View {
    let title: String
    let selection: Value
    let options: [DropdownOption<Value>]
    let onSelect: (Value) -> Void
    let onDismiss: () -> Void
    @State private var highlighted: Value?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DropdownHeader(title: title, onClose: onDismiss)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DropdownMetrics.rowSpacing) {
                        ForEach(options) { option in
                            Button { onSelect(option.value) } label: {
                                HStack(spacing: 10) {
                                    if let image = option.systemImage {
                                        DropdownIcon(systemImage: image, color: option.color ?? .secondary)
                                    }
                                    Text(option.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    DropdownSelectionMark(selected: option.value == selection)
                                }
                            }
                            .buttonStyle(DropdownRowStyle(selected: option.value == selection,
                                                          highlighted: highlighted == option.value))
                            .id(option.value)
                            .accessibilityAddTraits(option.value == selection ? [.isSelected] : [])
                        }
                    }
                }
                .padding(.horizontal, DropdownMetrics.rowInset)
                .padding(.bottom, 7)
                .frame(height: min(306, CGFloat(options.count) * DropdownMetrics.rowStride + 7))
                .onChange(of: highlighted) { value in
                    if let value { proxy.scrollTo(value) }
                }
                .onAppear { proxy.scrollTo(selection) }
            }
        }
        .frame(width: DropdownMetrics.width)
        .background(DropdownKeyHandler { event in
            switch event.keyCode {
            case 53: onDismiss()
            case 125, 126:
                guard !options.isEmpty else { return false }
                let current = options.firstIndex { $0.value == (highlighted ?? selection) } ?? 0
                let next = min(max(current + (event.keyCode == 125 ? 1 : -1), 0), options.count - 1)
                highlighted = options[next].value
            case 36, 76: onSelect(highlighted ?? selection)
            default: return false
            }
            return true
        })
    }
}

/// Register menu keys on the floating window without taking key focus.
struct DropdownKeyHandler: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> HandlerView { HandlerView() }
    func updateNSView(_ view: HandlerView, context: Context) {
        view.onKey = onKey
        (view.window as? FastDropdownPresenter.MenuPanel)?.onKey = onKey
    }
    static func dismantleNSView(_ view: HandlerView, coordinator: Void) {
        (view.window as? FastDropdownPresenter.MenuPanel)?.onKey = nil
    }
    final class HandlerView: NSView {
        var onKey: ((NSEvent) -> Bool)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            (window as? FastDropdownPresenter.MenuPanel)?.onKey = onKey
        }
    }
}

struct DropdownAction {
    let title: String
    var systemImage: String? = nil
    var destructive = false
    var children: [DropdownAction] = []
    var action: () -> Void = {}
}

/// Action dropdowns use the same rows and card as selection dropdowns.
struct RemrActionMenu<Label: View>: View {
    let title: String
    let actions: [DropdownAction]
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: { label() }
            .buttonStyle(DropdownTriggerStyle(isPresented: isPresented))
            .accessibilityLabel(title)
            .background {
                FastDropdownPresenter(isPresented: isPresented,
                                     content: AnyView(DropdownActions(title: title, actions: actions,
                                                                     onDismiss: { isPresented = false })),
                                     onDismiss: { isPresented = false })
            }
    }
}

private struct DropdownActions: View {
    let title: String
    let actions: [DropdownAction]
    let onDismiss: () -> Void
    @State private var path: [Int] = []
    @State private var highlighted: Int?
    private var currentActions: [DropdownAction] {
        path.reduce(actions) { rows, index in rows[index].children }
    }
    private var currentTitle: String {
        var rows = actions
        var result = title
        for index in path {
            result = rows[index].title
            rows = rows[index].children
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DropdownHeader(title: currentTitle,
                           onBack: path.isEmpty ? nil : { path.removeLast(); highlighted = nil },
                           onClose: onDismiss)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DropdownMetrics.rowSpacing) {
                        ForEach(Array(currentActions.enumerated()), id: \.offset) { index, item in
                            Button { activate(index) } label: {
                                HStack(spacing: 10) {
                                    if let image = item.systemImage {
                                        DropdownIcon(systemImage: image, color: item.destructive ? .red : .secondary)
                                    }
                                    Text(item.title).frame(maxWidth: .infinity, alignment: .leading)
                                    if !item.children.isEmpty {
                                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                }
                                .foregroundStyle(item.destructive ? Color.red : Color.primary)
                            }
                            .buttonStyle(DropdownRowStyle(highlighted: highlighted == index))
                            .id(index)
                        }
                    }
                }
                .padding(.horizontal, DropdownMetrics.rowInset)
                .padding(.bottom, 7)
                .frame(height: min(340, CGFloat(currentActions.count) * DropdownMetrics.rowStride + 7))
                .onChange(of: highlighted) { if let index = $0 { proxy.scrollTo(index) } }
                .onChange(of: path) { _ in proxy.scrollTo(0) }
            }
        }
        .frame(width: DropdownMetrics.width)
        .background(DropdownKeyHandler { event in
            switch event.keyCode {
            case 53: onDismiss()
            case 123:
                guard !path.isEmpty else { return false }
                path.removeLast(); highlighted = nil
            case 125, 126:
                guard !currentActions.isEmpty else { return false }
                highlighted = min(max((highlighted ?? (event.keyCode == 125 ? -1 : currentActions.count))
                                       + (event.keyCode == 125 ? 1 : -1), 0), currentActions.count - 1)
            case 36, 76, 124:
                guard let highlighted else { return false }
                if event.keyCode == 124 && currentActions[highlighted].children.isEmpty { return false }
                activate(highlighted)
            default: return false
            }
            return true
        })
    }

    private func activate(_ index: Int) {
        let item = currentActions[index]
        if item.children.isEmpty {
            onDismiss()
            item.action()
        } else {
            path.append(index)
            highlighted = nil
        }
    }
}
