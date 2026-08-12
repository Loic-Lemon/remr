import CoreLocation
import Foundation

/// A resolved location phrase: coordinates plus the display title to show in
/// the reminder list ("the office", or a reverse-geocoded place name for
/// "here"-style phrases).
struct GeocodedLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let title: String
}

/// Resolves location phrases for reminder location alarms.
///
/// Phrases are resolved relative to the user's current location whenever
/// possible: the geocode is region-biased around the fix and the nearest
/// result wins, so "the office" means *your* office instead of a random
/// match anywhere in the world. "here"-family phrases pin the reminder to
/// the current location directly.
///
/// Privacy model:
/// - Location access is requested lazily — only when a reminder with a
///   location phrase is being saved, never at launch.
/// - One-shot fixes only (`requestLocation()`); no continuous tracking, no
///   background updates, coarse accuracy (hundreds of meters).
/// - Raw location is never persisted or logged. The only coordinates that
///   leave this object are the ones written into the reminder's alert — the
///   feature itself.
/// - Without permission the geocoder degrades to the previous global,
///   unanchored lookup instead of failing.
///
/// Successes are cached (anchored results with a short TTL, since they
/// depend on where the user is); failures are retried on the next call.
@MainActor
final class LocationGeocoder: NSObject {
    static let shared = LocationGeocoder()

    // MARK: - Configuration

    /// How far around the user's fix the region-biased lookup searches.
    private static let anchorRadius: CLLocationDistance = 3_000 // meters
    private static let locationTimeout: TimeInterval = 10
    /// Anchored results stay valid this long; the user may have moved.
    private static let anchoredTTL: TimeInterval = 60 * 60 // 1 hour
    /// Phrases that mean "where I am right now".
    private static let herePhrases: Set<String> = [
        "here", "right here", "my location", "my current location",
        "current location", "where i am",
    ]

    // MARK: - State

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<Void, Never>?
    /// True once the system permission prompt has been shown this run — a
    /// pending/ignored prompt must never block or re-prompt on every save.
    private var hasRequestedAuth = false
    /// One shared in-flight fix/authorization per save wave, so concurrent
    /// saves (bulk create) never issue overlapping requests or fight over
    /// the continuation slots.
    private var locationTask: Task<CLLocation?, Never>?
    private var authTask: Task<Void, Never>?

    private struct Timestamped {
        let value: GeocodedLocation
        let date: Date
    }
    private var globalCache: [String: GeocodedLocation] = [:]
    private var anchoredCache: [String: Timestamped] = [:]
    private var inFlight: [String: Task<GeocodedLocation?, Never>] = [:]

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Geocoding

    /// Resolves `phrase` to coordinates, preferring results near the user's
    /// current location. "here"-family phrases pin to the current location
    /// directly. Returns nil only when nothing can be resolved.
    func geocode(_ phrase: String) async -> GeocodedLocation? {
        let key = Self.normalizedPhrase(phrase)
        if Self.herePhrases.contains(key) {
            return await hereLocation()
        }

        let anchor = await currentLocation()
        if let anchor {
            return await geocodeNear(key, anchor: anchor)
        }
        // No location permission: previous unanchored behavior.
        return await geocodeGlobally(key)
    }

    /// Region-biased lookup: search around the anchor and keep the nearest
    /// result. An empty region search falls back to the global pass.
    private func geocodeNear(_ key: String, anchor: CLLocation) async -> GeocodedLocation? {
        if let cached = anchoredCache[key], cached.date.timeIntervalSinceNow > -Self.anchoredTTL {
            return cached.value
        }
        if let existing = inFlight[key] { return await existing.value }
        let task = Task { () -> GeocodedLocation? in
            let region = CLCircularRegion(center: anchor.coordinate,
                                          radius: Self.anchorRadius,
                                          identifier: "remr-anchor")
            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.geocodeAddressString(key, in: region),
               let nearest = Self.nearestPlacemark(placemarks, to: anchor),
               let coordinate = nearest.location?.coordinate {
                return GeocodedLocation(latitude: coordinate.latitude,
                                        longitude: coordinate.longitude,
                                        title: key)
            }
            return await rawGlobalGeocode(key)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { anchoredCache[key] = Timestamped(value: result, date: Date()) }
        return result
    }

    /// Unanchored lookup — the fallback path when no location permission.
    private func geocodeGlobally(_ key: String) async -> GeocodedLocation? {
        if let cached = globalCache[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }
        let task = Task { () -> GeocodedLocation? in
            await rawGlobalGeocode(key)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { globalCache[key] = result }
        return result
    }

    /// No dedupe, no cache — safe to call from inside a deduplicated task
    /// (the anchored path's fallback) without deadlocking on `inFlight`.
    private func rawGlobalGeocode(_ key: String) async -> GeocodedLocation? {
        guard let first = try? await CLGeocoder().geocodeAddressString(key).first,
              let coordinate = first.location?.coordinate else { return nil }
        return GeocodedLocation(latitude: coordinate.latitude,
                                longitude: coordinate.longitude,
                                title: key)
    }

    /// "here"-family phrase: pin to the current location, reverse-geocoded
    /// for a human-readable title.
    private func hereLocation() async -> GeocodedLocation? {
        guard let fix = await currentLocation() else { return nil }
        let title = await reverseGeocodeTitle(for: fix)
        return GeocodedLocation(latitude: fix.coordinate.latitude,
                                longitude: fix.coordinate.longitude,
                                title: title)
    }

    private func reverseGeocodeTitle(for location: CLLocation) async -> String {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let pm = placemarks?.first else { return "My location" }
        if let name = pm.name, !name.isEmpty { return name }
        if let locality = pm.locality {
            if let area = pm.administrativeArea, !area.isEmpty { return "\(locality), \(area)" }
            return locality
        }
        return "My location"
    }

    // MARK: - Current location

    private var isAuthorized: Bool {
        // macOS only ever grants "always"; there is no when-in-use state.
        manager.authorizationStatus == .authorizedAlways
    }

    /// One shared one-shot fix per save wave. Requests permission lazily when
    /// the status is undetermined; returns nil when denied or unavailable.
    private func currentLocation() async -> CLLocation? {
        if !isAuthorized {
            // Prompt at most once per run; afterwards degrade silently to the
            // global lookup so saves are never held up by the dialog.
            guard manager.authorizationStatus == .notDetermined, !hasRequestedAuth else { return nil }
            hasRequestedAuth = true
            await ensureAuthorized()
            guard isAuthorized else { return nil }
        }
        if let task = locationTask { return await task.value }
        let task = Task { () -> CLLocation? in
            await requestLocationFix()
        }
        locationTask = task
        let result = await task.value
        locationTask = nil
        return result
    }

    private func ensureAuthorized() async {
        if let task = authTask {
            await task.value
            return
        }
        let task = Task { () -> Void in
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                authContinuation = cont
                manager.requestWhenInUseAuthorization()
                // The prompt can go unanswered; don't hang the save forever.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.locationTimeout) {
                    if let pending = self.authContinuation {
                        pending.resume()
                        self.authContinuation = nil
                    }
                }
            }
        }
        authTask = task
        await task.value
        authTask = nil
    }

    private func requestLocationFix() async -> CLLocation? {
        await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            locationContinuation = cont
            manager.requestLocation()
            // A fix can stall (Location Services disabled, no GPS); the
            // caller falls back to the global geocode instead of waiting.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.locationTimeout) {
                if let pending = self.locationContinuation {
                    pending.resume(returning: nil)
                    self.locationContinuation = nil
                }
            }
        }
    }

    // MARK: - Helpers

    private static func normalizedPhrase(_ phrase: String) -> String {
        phrase.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
    }

    private static func nearestPlacemark(_ placemarks: [CLPlacemark], to location: CLLocation) -> CLPlacemark? {
        placemarks
            .compactMap { placemark in placemark.location.map { (placemark, $0) } }
            .min { $0.1.distance(from: location) < $1.1.distance(from: location) }?
            .0
    }
}

extension LocationGeocoder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authContinuation?.resume()
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let location = locations.last ?? locations.first
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
