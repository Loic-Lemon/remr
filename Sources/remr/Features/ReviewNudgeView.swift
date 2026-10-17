import SwiftUI

/// All artwork is vector-based, so the little face stays sharp on every display.
struct ReviewSunView: View {
    var waveAngle: Double = -12
    var rayAngle: Double = 0
    var sunAngle: Double = 0

    private let ink = Color(red: 0.34, green: 0.18, blue: 0.04)

    var body: some View {
        ZStack {
            ZStack {
                ForEach(0..<10, id: \.self) { index in
                    Capsule()
                        .fill(Color(red: 1, green: 0.72, blue: 0.20))
                        .frame(width: 3, height: 6)
                        .offset(y: -25)
                        .rotationEffect(.degrees(Double(index) * 36 + rayAngle))
                }
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.87, blue: 0.44),
                                                  Color(red: 1, green: 0.65, blue: 0.17)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 37, height: 37)
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.75))
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Capsule().fill(ink).frame(width: 3, height: 4.5)
                        .offset(x: side * 6.5, y: -3.5)
                    Ellipse().fill(Color(red: 1, green: 0.39, blue: 0.25).opacity(0.44))
                        .frame(width: 5.5, height: 3).offset(x: side * 11, y: 3)
                }
                Path { path in
                    path.move(to: CGPoint(x: 22, y: 31))
                    path.addQuadCurve(to: CGPoint(x: 34, y: 31),
                                      control: CGPoint(x: 28, y: 40))
                }
                .stroke(ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 56, height: 56)
            }
            .frame(width: 56, height: 56)
            .rotationEffect(.degrees(sunAngle))
            .offset(x: -9)

            Image(systemName: "hand.wave.fill")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color(red: 1, green: 0.79, blue: 0.34))
                .rotationEffect(.degrees(waveAngle), anchor: .bottom)
                .offset(x: 25, y: 1)
        }
        .frame(width: 76, height: 62)
        .accessibilityHidden(true)
    }
}

/// Fixed-height wings leave the camera housing clear and stay inside the menu bar.
struct ReviewNudgeCard: View {
    let housingWidth: CGFloat
    let wingWidth: CGFloat
    let height: CGFloat
    var expansion: CGFloat = 1
    var waveAngle: Double = -12
    var rayAngle: Double = 0
    var sunAngle: Double = 0
    var quickAddShortcut: String = ""
    var onReview: () -> Void = {}
    var onDismiss: () -> Void = {}

    private var width: CGFloat { housingWidth + wingWidth * 2 }
    private var silhouette: NotchPanelShape {
        NotchPanelShape(bottomRadius: 11, topShoulder: 6)
    }

    var body: some View {
        ZStack {
            silhouette
                .fill(.black)
                .frame(width: housingWidth + wingWidth * 2 * expansion, height: height)

            HStack(spacing: 0) {
                Button(action: onReview) {
                    HStack(spacing: 6) {
                        ReviewSunView(waveAngle: waveAngle, rayAngle: rayAngle, sunAngle: sunAngle)
                            .scaleEffect(min(0.42, (height - 6) / 62))
                            .frame(width: 32, height: min(26, height - 6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("A little check-in?")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .fixedSize()
                            if !quickAddShortcut.isEmpty {
                                Text(quickAddShortcut)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Review your reminders")
                .accessibilityHint(quickAddShortcut.isEmpty ? "" : "New note shortcut: \(quickAddShortcut)")
                .help("Open remr to review your reminders")
                .offset(x: wingWidth * (1 - expansion))
                .frame(width: wingWidth, height: height)
                .clipped()

                // The physical notch covers this space. Keep every control outside it.
                Color.clear.frame(width: housingWidth, height: height)
                    .allowsHitTesting(false)

                HStack(spacing: 4) {
                    Button(action: onReview) {
                        Text("Review reminders")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .fixedSize()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open remr to review your reminders")

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 20, height: height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss this check-in")
                    .help("Dismiss this check-in")
                }
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .offset(x: -wingWidth * (1 - expansion))
                .frame(width: wingWidth, height: height)
                .clipped()
            }
            .opacity(expansion)
            .allowsHitTesting(expansion == 1)
            .accessibilityHidden(expansion == 0)
        }
        .frame(width: width, height: height)
        .mask {
            silhouette.frame(width: housingWidth + wingWidth * 2 * expansion, height: height)
        }
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
final class ReviewNudgePresentation: ObservableObject {
    @Published var expanded = false
}

struct ReviewNudgeView: View {
    let housingWidth: CGFloat
    let wingWidth: CGFloat
    let height: CGFloat
    @ObservedObject var presentation: ReviewNudgePresentation
    @ObservedObject var settings: SettingsStore
    let onReview: () -> Void
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waving = false
    @State private var turning = false

    var body: some View {
        ReviewNudgeCard(housingWidth: housingWidth, wingWidth: wingWidth, height: height,
                        expansion: presentation.expanded ? 1 : 0,
                        waveAngle: waving ? 16 : -12, rayAngle: turning ? 24 : 0,
                        sunAngle: reduceMotion ? 0 : (turning ? 12 : -8),
                        quickAddShortcut: settings.combo(for: .quickAdd).displayString,
                        onReview: onReview, onDismiss: onDismiss)
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                        presentation.expanded = true
                    }
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.32).repeatForever(autoreverses: true).delay(0.18)) {
                        waving = true
                    }
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.18)) {
                        turning = true
                    }
                }
            }
    }
}
