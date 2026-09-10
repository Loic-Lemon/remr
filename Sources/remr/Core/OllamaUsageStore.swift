import Foundation
import IOKit.ps
import SwiftUI

/// Local-only aggregate usage metrics for Ollama-backed features.
@MainActor
final class OllamaUsageStore: ObservableObject {
    static let shared = OllamaUsageStore()

    @Published private(set) var requestCount: Int
    @Published private(set) var activeSeconds: TimeInterval
    @Published private(set) var batteryRequestCount: Int
    @Published private(set) var errorCount: Int
    @Published private(set) var embeddingCacheHits: Int
    @Published private(set) var embeddingCacheMisses: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        requestCount = defaults.integer(forKey: "remr.ollama.requests")
        activeSeconds = defaults.double(forKey: "remr.ollama.activeSeconds")
        batteryRequestCount = defaults.integer(forKey: "remr.ollama.batteryRequests")
        errorCount = defaults.integer(forKey: "remr.ollama.errors")
        embeddingCacheHits = defaults.integer(forKey: "remr.ollama.embeddingCacheHits")
        embeddingCacheMisses = defaults.integer(forKey: "remr.ollama.embeddingCacheMisses")
    }

    var averageRequestSeconds: TimeInterval {
        requestCount == 0 ? 0 : activeSeconds / Double(requestCount)
    }

    var batteryRequestPercent: Double {
        requestCount == 0 ? 0 : Double(batteryRequestCount) / Double(requestCount) * 100
    }

    var embeddingCacheHitPercent: Double {
        let total = embeddingCacheHits + embeddingCacheMisses
        return total == 0 ? 0 : Double(embeddingCacheHits) / Double(total) * 100
    }

    func recordRequest(duration: TimeInterval, failed: Bool = false) {
        requestCount += 1
        activeSeconds += max(0, duration)
        if Self.isOnBattery { batteryRequestCount += 1 }
        if failed { errorCount += 1 }
        save()
    }

    func recordError() {
        errorCount += 1
        save()
    }

    func recordEmbeddingCache(hits: Int, misses: Int) {
        embeddingCacheHits += max(0, hits)
        embeddingCacheMisses += max(0, misses)
        save()
    }

    func reset() {
        requestCount = 0
        activeSeconds = 0
        batteryRequestCount = 0
        errorCount = 0
        embeddingCacheHits = 0
        embeddingCacheMisses = 0
        save()
    }

    private func save() {
        defaults.set(requestCount, forKey: "remr.ollama.requests")
        defaults.set(activeSeconds, forKey: "remr.ollama.activeSeconds")
        defaults.set(batteryRequestCount, forKey: "remr.ollama.batteryRequests")
        defaults.set(errorCount, forKey: "remr.ollama.errors")
        defaults.set(embeddingCacheHits, forKey: "remr.ollama.embeddingCacheHits")
        defaults.set(embeddingCacheMisses, forKey: "remr.ollama.embeddingCacheMisses")
    }

    private static var isOnBattery: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              let type = description[kIOPSPowerSourceStateKey] as? String else { return false }
        return type == kIOPSBatteryPowerValue
    }
}
