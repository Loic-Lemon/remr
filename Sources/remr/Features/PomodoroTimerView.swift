import SwiftUI

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
        VStack(spacing: 16) {
            HStack {
                Text(timer.phase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Cycle \(timer.completedFocusSessions + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlassCapsule()
            }

            ZStack {
                Circle()
                    .stroke(phaseColor.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(phaseColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: progress)
                VStack(spacing: 2) {
                    Text(format(timer.remaining))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(timer.isRunning ? "in progress" : "paused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 132, height: 132)

            HStack(spacing: 10) {
                Button(timer.isRunning ? "Pause" : "Start") {
                    timer.isRunning ? timer.pause() : timer.start()
                }
                .liquidGlassButtonStyle(.borderedProminent, prominent: true)
                .controlSize(.small)

                Button("Reset") { timer.reset() }
                    .liquidGlassButtonStyle(.bordered)
                    .controlSize(.small)

                Button {
                    timer.skip()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .liquidGlassButtonStyle(.bordered)
                .controlSize(.small)
                .help("Skip phase")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Durations")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    durationRow("Focus", phase: .focus)
                    Divider()
                        .frame(height: 34)
                    durationRow("Short break", phase: .shortBreak)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassPane(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func durationRow(_ title: String, phase: PomodoroPhase) -> some View {
        VStack(spacing: 6) {
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

                Text("\(timer.duration(for: phase))")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 24)
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

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
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
