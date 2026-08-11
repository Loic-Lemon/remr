import Foundation

/// The active tag filter, persisted so it stays as the default across
/// launches. One tag at a time; nil means no filter. Follows TagStore's
/// shared-singleton pattern. Tags are stored lowercased without the `#`,
/// matching `NaturalLanguageParser.extractTags` output.
@MainActor
final class FilterStore: ObservableObject {
    static let shared = FilterStore()

    /// The tag the list is filtered to (lowercased, no `#`); nil = show all.
    @Published private(set) var tag: String? {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let key = "remr.tagFilter"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.string(forKey: key), !saved.isEmpty {
            tag = saved
        }
    }

    /// Set the filter. Passing the same tag toggles it off (clicking the
    /// active chip clears the filter).
    func toggle(_ newTag: String) {
        let normalized = newTag.lowercased()
        tag = (tag == normalized) ? nil : normalized
    }

    func clear() {
        tag = nil
    }

    private func persist() {
        defaults.set(tag, forKey: key)
    }
}
