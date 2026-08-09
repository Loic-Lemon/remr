import CoreLocation
import Foundation

/// Forward-geocodes location phrases for reminder location alarms.
/// Successes are cached; failures are retried on the next call.
final class LocationGeocoder: @unchecked Sendable {
    static let shared = LocationGeocoder()

    private var cache: [String: CLLocation] = [:]
    private var inFlight: [String: Task<CLLocation?, Never>] = [:]

    func geocode(_ phrase: String) async -> CLLocation? {
        if let cached = cache[phrase] { return cached }
        if let existing = inFlight[phrase] { return await existing.value }
        let task = Task { () -> CLLocation? in
            guard let first = try? await CLGeocoder().geocodeAddressString(phrase).first,
                  let location = first.location else { return nil }
            return location
        }
        inFlight[phrase] = task
        let result = await task.value
        inFlight[phrase] = nil
        if let result { cache[phrase] = result }
        return result
    }
}
