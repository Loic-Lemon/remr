import SwiftUI

/// A separate section below the disclosure header. Closed panels are removed,
/// including their control layers, rather than left mounted behind a clip.
struct PomodoroPanelSection: View {
    var isPresented: Bool
    var timer: PomodoroTimerStore
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isPresented {
                PomodoroTimerView(timer: timer)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(HeightReader(onChange: onHeightChange))
                    .compositingGroup()
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity))
                    .zIndex(1)
            }
        }
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
    }
}

struct PomodoroTimerView: View {
    @ObservedObject var timer: PomodoroTimerStore

    private var progress: Double {
        guard timer.currentDuration > 0 else { return 0 }
        return min(1, max(0, 1 - timer.remaining / timer.currentDuration))
    }

    private var phaseColor: Color {
        timer.phase == .focus ? .orange : .mint
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(phaseColor.opacity(0.12), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(phaseColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(timer.formattedRemaining)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.identity)
                        Text(timer.isRunning ? "in progress" : "paused")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(timer.phase.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(phaseColor)
                        Spacer(minLength: 4)
                        Text("Cycle \(timer.completedFocusSessions + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button(timer.isRunning ? "Pause" : "Start") {
                            timer.isRunning ? timer.pause() : timer.start()
                        }
                        .buttonStyle(PomodoroActionButtonStyle(prominent: true))

                        Button("Reset") { timer.reset() }
                            .buttonStyle(PomodoroActionButtonStyle())

                        Button { timer.skip() } label: {
                            Image(systemName: "forward.fill")
                        }
                        .buttonStyle(PomodoroActionButtonStyle())
                        .help("Skip phase")
                        .accessibilityLabel("Skip phase")
                    }
                    .controlSize(.small)
                }
            }

            Divider()
            HStack(spacing: 16) {
                durationRow("Focus", phase: .focus)
                durationRow("Break", phase: .shortBreak)
            }
        }
        .padding(14)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func durationRow(_ title: String, phase: PomodoroPhase) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 5) {
                Button {
                    timer.setDuration(timer.duration(for: phase) - 1, for: phase)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .help("Decrease \(title.lowercased()) duration")

                Text("\(timer.duration(for: phase))m")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 30)
                Button {
                    timer.setDuration(timer.duration(for: phase) + 1, for: phase)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(phaseColor)
                .frame(width: 18, height: 18)
                .help("Increase \(title.lowercased()) duration")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// Draw the moving panel's actions in SwiftUI. Native glass buttons export
/// separate effect layers to the window, escaping clips and adding glass
/// morphing work during the reveal. These buttons move with the whole card.
private struct PomodoroActionButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.primary.opacity(0.08))
            }
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PomodoroCompletionView: View {
    let phase: PomodoroPhase
    let nextPhase: PomodoroPhase
    let onStartNext: () -> Void
    let onDismiss: () -> Void

    private var color: Color {
        phase == .focus ? .orange : .mint
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: phase == .focus ? "sparkles" : "cup.and.saucer.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(color)
                .padding(12)
                .background(color.opacity(0.14), in: Circle())
            Text("\(phase.title) complete")
                .font(.title3.weight(.bold))
            HStack(spacing: 10) {
                Button("Start \(nextPhase.title.lowercased())", action: onStartNext)
                    .liquidGlassButtonStyle(.borderedProminent, prominent: true)
                    .controlSize(.small)
                Button("Dismiss", action: onDismiss)
                    .liquidGlassButtonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(color.opacity(0.25), lineWidth: 1)
                }
        }
        .padding(8)
        .remrAppearance(using: SettingsStore.shared)
    }
}
