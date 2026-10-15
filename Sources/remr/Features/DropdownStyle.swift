import AppKit
import SwiftUI

extension View {
    func remrDropdownSurface() -> some View { modifier(DropdownSurface()) }
}

private struct DropdownSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: shape)
            } else if #available(macOS 26.0, *) {
                content.glassEffect(.regular.tint(Color.primary.opacity(0.025)), in: shape)
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
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
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
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(DropdownTriggerStyle(isPresented: isPresented))
            .accessibilityLabel(title)
            .accessibilityValue(options.first(where: { $0.value == selection })?.title ?? "Choose")
            .background {
                FastPopoverPresenter(isPresented: isPresented,
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(options) { option in
                            Button { onSelect(option.value) } label: {
                                HStack(spacing: 9) {
                                    if let image = option.systemImage {
                                        Image(systemName: image)
                                            .foregroundStyle(option.color ?? .secondary)
                                            .frame(width: 16)
                                    }
                                    Text(option.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .opacity(option.value == selection ? 1 : 0)
                                }
                            }
                            .buttonStyle(DropdownRowStyle(selected: option.value == selection,
                                                          highlighted: highlighted == option.value))
                            .id(option.value)
                            .accessibilityAddTraits(option.value == selection ? [.isSelected] : [])
                        }
                    }
                }
                .frame(height: min(306, CGFloat(options.count) * 34))
                .onChange(of: highlighted) { value in
                    if let value { proxy.scrollTo(value) }
                }
                .onAppear { proxy.scrollTo(selection) }
            }
        }
        .padding(7)
        .frame(width: 272)
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

/// Scope arrow/Return/Escape handling to this card's window.
private struct DropdownKeyHandler: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator = context.coordinator] event in
            guard let coordinator, let window = coordinator.view?.window, event.window === window else { return event }
            return coordinator.onKey?(event) == true ? nil : event
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.onKey = onKey }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
    final class Coordinator {
        weak var view: NSView?
        var onKey: ((NSEvent) -> Bool)?
        var monitor: Any?
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
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
                FastPopoverPresenter(isPresented: isPresented,
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !path.isEmpty {
                    Button { path.removeLast(); highlighted = nil } label: {
                        Image(systemName: "chevron.left").frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                Text(currentTitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(currentActions.enumerated()), id: \.offset) { index, item in
                            Button { activate(index) } label: {
                                HStack(spacing: 9) {
                                    if let image = item.systemImage {
                                        Image(systemName: image).frame(width: 16).foregroundStyle(.secondary)
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
                .frame(height: min(340, CGFloat(currentActions.count) * 34))
                .onChange(of: highlighted) { if let index = $0 { proxy.scrollTo(index) } }
                .onChange(of: path) { _ in proxy.scrollTo(0) }
            }
        }
        .padding(7)
        .frame(width: 252)
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
