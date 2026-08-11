import EventKit
import Foundation

struct SearchQuery: Equatable {
    /// `@tokens`, lowercased, no `@`.
    var listTokens: [String] = []
    /// `!!` present.
    var priorityHigh: Bool = false
    /// `#tokens`, lowercased, no `#`.
    var tags: [String] = []
    /// Remaining plain tokens, lowercased.
    var words: [String] = []
}

enum SearchParser {
    /// Whitespace-tokenize: `@X` → list, `!!` → priorityHigh, `#X` → tag, else word.
    static func parse(_ input: String) -> SearchQuery {
        var query = SearchQuery()
        for raw in input.split(whereSeparator: { $0.isWhitespace }) {
            let token = String(raw)
            if token.hasPrefix("@"), token.count > 1 {
                query.listTokens.append(String(token.dropFirst()).lowercased())
            } else if token == "!!" {
                query.priorityHigh = true
            } else if token.hasPrefix("#"), token.count > 1 {
                query.tags.append(String(token.dropFirst()).lowercased())
            } else {
                query.words.append(token.lowercased())
            }
        }
        return query
    }

    /// All conditions are ANDed. Empty query matches everything.
    static func matches(_ reminder: EKReminder, query: SearchQuery, calendarTitles: [String: String]) -> Bool {
        let calendarTitle = reminder.calendar.flatMap { calendarTitles[$0.calendarIdentifier] }
        return matches(query: query, calendarTitle: calendarTitle,
                       priority: reminder.priority, title: reminder.title, notes: reminder.notes)
    }

    /// Pure form used by unit tests (and by the EKReminder overload above).
    static func matches(query: SearchQuery, calendarTitle: String?, priority: Int, title: String, notes: String?) -> Bool {
        for token in query.listTokens {
            guard let calendarTitle, calendarTitle.lowercased().contains(token) else { return false }
        }
        if query.priorityHigh && priority != 1 { return false }
        let text = (title + " " + (notes ?? "")).lowercased()
        for tag in query.tags where !NaturalLanguageParser.containsTag(tag, in: title + " " + (notes ?? "")) { return false }
        for word in query.words where !text.contains(word) { return false }
        return true
    }
}
