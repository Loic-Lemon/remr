import Foundation

/// Random choices belong to a window presentation, never to an animation frame.
/// Deterministic samples keep movement continuous through typing and refocusing.
struct ComposerNightSession: Equatable {
    let seed: UInt64

    static let preview = ComposerNightSession(seed: 42)
    static func random() -> Self { Self(seed: UInt64.random(in: .min ... .max)) }

    /// Bounded, independent motion on both axes. Combining different periods
    /// produces gentle wandering rather than synchronized horizontal swings.
    func drift(channel: Int, time: TimeInterval, amplitude: CGSize, rate: Double = 1) -> CGPoint {
        let base = channel * 12 + 100
        func wave(_ offset: Int) -> Double {
            let phase = sample(base + offset) * .pi * 2
            let speed = (0.10 + sample(base + offset + 4) * 0.13) * rate
            return sin(time * speed + phase)
        }
        return CGPoint(x: (wave(0) * 0.68 + wave(1) * 0.32) * amplitude.width,
                       y: (wave(2) * 0.68 + wave(3) * 0.32) * amplitude.height)
    }

    /// A few stars gently brighten during irregular, separated windows.
    /// The sine-squared envelope joins the steady brightness with zero slope.
    func starBrightness(index: Int, time: TimeInterval) -> Double {
        let base = 0.58 + sample(index + 400) * 0.15
        guard sample(index + 430) < 0.65 else { return base }
        let interval = 9 + sample(index + 460) * 7
        let shifted = max(0, time) + sample(index + 490) * interval
        let cycle = Int(shifted / interval)
        let local = shifted.truncatingRemainder(dividingBy: interval)
        let key = index * 1009 + cycle * 31 + 2000
        guard sample(key) < 0.75 else { return base }
        let duration = 2 + sample(key + 1) * 1.4
        let start = 1 + sample(key + 2) * (interval - duration - 2)
        let progress = (local - start) / duration
        guard progress > 0, progress < 1 else { return base }
        return base + 0.25 * pow(sin(progress * .pi), 2)
    }

    /// One optional event per presentation. It is not a repeating timer.
    var shootingStar: ShootingStar? {
        guard sample(1) < 0.25 else { return nil }
        let goesRight = sample(2) < 0.5
        let startX = goesRight ? 0.47 + sample(3) * 0.08 : 0.76 + sample(3) * 0.06
        let travel = 0.16 + sample(4) * 0.08
        return ShootingStar(delay: 1.0 + sample(5) * 2.5,
                            duration: 0.9 + sample(6) * 0.4,
                            start: CGPoint(x: startX, y: 0.16 + sample(7) * 0.20),
                            end: CGPoint(x: startX + (goesRight ? travel : -travel),
                                         y: 0.50 + sample(8) * 0.20))
    }

    struct ShootingStar: Equatable {
        let delay: TimeInterval
        let duration: TimeInterval
        let start: CGPoint
        let end: CGPoint

        func progress(at time: TimeInterval) -> Double? {
            let value = (time - delay) / duration
            return value > 0 && value < 1 ? value : nil
        }
    }

    // SplitMix64 supplies independent stable samples without mutable RNG state.
    private func sample(_ channel: Int) -> Double {
        var value = seed &+ (UInt64(truncatingIfNeeded: channel) &* 0x9E3779B97F4A7C15)
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }
}
