import Foundation

/// Result of parsing one line of natural-language reminder input.
struct ParsedReminder: Equatable {
    /// Title after all tokens stripped, whitespace-collapsed.
    var title: String
    /// Raw text after `@` (no `@`); nil if none.
    var listToken: String?
    /// False → unmatched-list warning + keep-in-title toggle.
    var listMatched: Bool
    /// Absolute due date after rollover; nil if none.
    var dueDate: Date?
    /// False → save as all-day (no hour/minute components).
    var hasTime: Bool
    /// 0 none, 1 high, 5 medium, 9 low.
    var priority: Int
    /// Location phrase stripped from the title; nil if none.
    var locationPhrase: String?
    /// `#tag` tokens (whitespace-delimited, no `#`), in order, deduped.
    var tags: [String] = []
    /// True when the title is empty after parsing.
    var isInvalid: Bool
    /// The original input line.
    var original: String

    init(original: String) {
        self.title = ""
        self.listToken = nil
        self.listMatched = false
        self.dueDate = nil
        self.hasTime = false
        self.priority = 0
        self.locationPhrase = nil
        self.isInvalid = false
        self.original = original
    }
}

/// Pure natural-language reminder parser (no EventKit). List matching takes
/// list titles as an argument so the parser is fully unit-testable.
///
/// Extraction order matters: priority → list → date → location → title.
enum NaturalLanguageParser {

    static func parse(_ line: String, now: Date = Date(), calendar: Calendar = .current, listNames: [String] = []) -> ParsedReminder {
        var result = ParsedReminder(original: line)
        var text = line

        let priority = extractPriority(from: text)
        result.priority = priority.priority
        text = priority.text

        let list = extractList(from: text, listNames: listNames)
        result.listToken = list.token
        result.listMatched = list.matched
        text = list.text

        let tags = extractTags(from: text)
        result.tags = tags
        text = text.split(whereSeparator: { $0.isWhitespace })
            .filter { !($0.hasPrefix("#") && $0.count > 1) }
            .joined(separator: " ")

        let date = extractDate(from: text, now: now, calendar: calendar)
        result.dueDate = date.due
        result.hasTime = date.hasTime
        text = date.text

        let location = extractLocation(from: text)
        result.locationPhrase = location.phrase
        text = location.text

        let title = collapseWhitespace(text)
        result.title = title
        result.isInvalid = title.isEmpty
        return result
    }

    static func parseBulk(_ text: String, now: Date = Date(), calendar: Calendar = .current, listNames: [String] = []) -> [ParsedReminder] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { parse($0, now: now, calendar: calendar, listNames: listNames) }
    }

    // MARK: - Pass 1: Priority

    private static let priorityPhraseRegex = try! NSRegularExpression(
        pattern: #"\b(high|p1|medium|p2|low|p3)\s+priority\b"#,
        options: [.caseInsensitive])
    private static let priorityBareRegex = try! NSRegularExpression(
        pattern: #"\b(high|p1|medium|p2|low|p3)\b"#,
        options: [.caseInsensitive])

    private static func extractPriority(from input: String) -> (priority: Int, text: String) {
        var text = input
        if let range = text.range(of: #"^(!{1,2})\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
            return (1, text)
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        if let res = priorityPhraseRegex.firstMatch(in: text, options: [], range: fullRange) {
            let level = nsText.substring(with: res.range(at: 1))
            text.removeSubrange(nsRangeToRange(res.range, in: text))
            return (priorityForLevel(level), text)
        }
        if let res = priorityBareRegex.firstMatch(in: text, options: [], range: fullRange) {
            let level = nsText.substring(with: res.range)
            text.removeSubrange(nsRangeToRange(res.range, in: text))
            return (priorityForLevel(level), text)
        }
        return (0, text)
    }

    private static func priorityForLevel(_ level: String) -> Int {
        switch level.lowercased() {
        case "high", "p1": return 1
        case "medium", "p2": return 5
        default: return 9
        }
    }

    // MARK: - Pass 2: List

    private static let listRegex = try! NSRegularExpression(pattern: #"@([^\s@]+)"#)

    private static func extractList(from input: String, listNames: [String]) -> (token: String?, matched: Bool, text: String) {
        var text = input
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let res = listRegex.firstMatch(in: text, options: [], range: fullRange) else {
            return (nil, false, text)
        }
        let firstWord = nsText.substring(with: res.range(at: 1))

        // Candidate 2 = capture + " " + the word immediately following.
        var candidate2: String?
        var stripEnd = res.range.location + res.range.length
        let afterNS = nsText.substring(from: stripEnd)
        if let nextWord = afterNS.range(of: #"^\s+\S+"#, options: .regularExpression) {
            let secondWord = String(afterNS[nextWord]).trimmingCharacters(in: .whitespaces)
            candidate2 = firstWord + " " + secondWord
            stripEnd += afterNS.distance(from: afterNS.startIndex, to: nextWord.upperBound)
        }

        let token: String
        let matched: Bool
        let stripLength: Int
        if let c2 = candidate2, listToken(c2, matches: listNames) {
            token = c2
            matched = true
            stripLength = stripEnd - res.range.location
        } else if listToken(firstWord, matches: listNames) {
            token = firstWord
            matched = true
            stripLength = res.range.length
        } else {
            token = firstWord
            matched = false
            stripLength = res.range.length
        }

        let stripRange = NSRange(location: res.range.location, length: stripLength)
        text.removeSubrange(nsRangeToRange(stripRange, in: text))
        return (token, matched, text)
    }

    private static func listToken(_ token: String, matches listNames: [String]) -> Bool {
        let normalized = normalize(token)
        guard !normalized.isEmpty else { return false }
        if listNames.contains(where: { normalize($0) == normalized }) { return true }
        return listNames.contains(where: { normalize($0).contains(normalized) })
    }

    // MARK: - Pass 3: Tags

    /// Whitespace-delimited `#tag` tokens (no `#`), deduped — mirrors
    /// SearchParser's tag rule so typing and searching stay consistent.
    static func extractTags(from input: String) -> [String] {
        var seen = Set<String>()
        return input.split(whereSeparator: { $0.isWhitespace })
            .filter { $0.hasPrefix("#") && $0.count > 1 }
            .map { String($0.dropFirst()) }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    // MARK: - Pass 4: Date

    private static let dateDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let endOfDayRegex = try! NSRegularExpression(
        pattern: #"\b(end of (the )?day|eod|later(\s+today)?)\b"#,
        options: [.caseInsensitive])
    private static let inUnitsRegex = try! NSRegularExpression(
        pattern: #"\bin\s+(an?|half an?|\d+)\s+(minute|minutes|hour|hours|day|days|week|weeks)\b"#,
        options: [.caseInsensitive])
    private static let hasTimeRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2}(:\d{2})?\s*(a\.?m\.?|p\.?m\.?)|noon|midnight|tonight|tonite|morning|afternoon|evening|o'clock|\d{1,2}:\d{2})\b"#,
        options: [.caseInsensitive])
    private static let dateWordRegex = try! NSRegularExpression(
        pattern: #"\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|yesterday|next|this|january|february|march|april|may|june|july|august|september|october|november|december|in\s+\d+\s+(minute|minutes|hour|hours|day|days|week|weeks))\b"#,
        options: [.caseInsensitive])
    private static let dateConnectors: Set<String> = ["at", "by", "on", "before"]

    private static func extractDate(from input: String, now: Date, calendar: Calendar) -> (due: Date?, hasTime: Bool, text: String) {
        let text = input
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var matches: [(range: NSRange, date: Date, isKeyword: Bool)] = []
        dateDetector.enumerateMatches(in: text, options: [], range: fullRange) { res, _, _ in
            guard let res, let date = res.date else { return }
            matches.append((res.range, date, false))
        }

        // Keyword layer fills gaps the detector misses. Fires only where no
        // detector match overlaps (e.g. "in 2 days" is detector-covered).
        var keywordMatches: [(range: NSRange, date: Date, isEOD: Bool)] = []
        endOfDayRegex.enumerateMatches(in: text, options: [], range: fullRange) { res, _, _ in
            guard let res else { return }
            let startOfDay = calendar.startOfDay(for: now)
            if let eod = calendar.date(byAdding: .hour, value: 17, to: startOfDay) {
                keywordMatches.append((res.range, eod, true))
            }
        }
        inUnitsRegex.enumerateMatches(in: text, options: [], range: fullRange) { res, _, _ in
            guard let res else { return }
            let amountStr = nsText.substring(with: res.range(at: 1)).lowercased()
            let unitStr = nsText.substring(with: res.range(at: 2)).lowercased()
            let amount: Double
            if amountStr.contains("half") { amount = 0.5 }
            else if let n = Int(amountStr) { amount = Double(n) }
            else { amount = 1 }
            let unitSeconds: Double
            if unitStr.hasPrefix("minute") { unitSeconds = 60 }
            else if unitStr.hasPrefix("hour") { unitSeconds = 3600 }
            else if unitStr.hasPrefix("day") { unitSeconds = 86400 }
            else { unitSeconds = 604_800 }  // week
            keywordMatches.append((res.range, now.addingTimeInterval(amount * unitSeconds), false))
        }
        // End-of-day keywords are authoritative: "later today" must mean 17:00
        // today, not the detector's guess at the phrase. Drop detector matches
        // that overlap an eod keyword, then add keywords that don't collide
        // with what remains.
        let eodRanges = keywordMatches.filter(\.isEOD).map(\.range)
        if !eodRanges.isEmpty {
            matches.removeAll { m in eodRanges.contains(where: { rangesOverlap($0, m.range) }) }
        }
        let detectorRanges = matches.map(\.range)
        for kw in keywordMatches where !detectorRanges.contains(where: { rangesOverlap($0, kw.range) }) {
            matches.append((kw.range, kw.date, true))
        }

        // First match in document order = due date.
        let ordered = matches.sorted { $0.range.location < $1.range.location }
        var due: Date?
        var hasTime = false
        if let first = ordered.first {
            let sub = nsText.substring(with: first.range)
            var date = first.date
            var time: Bool
            if first.isKeyword {
                time = true
            } else {
                time = hasTimeRegex.firstMatch(in: sub, options: [],
                                               range: NSRange(location: 0, length: (sub as NSString).length)) != nil
            }
            // Past-time rollover: bare clock time already past → next day.
            if time && !containsDateWord(sub) && date < now {
                date = date.addingTimeInterval(86_400)
            }
            due = date
            hasTime = time
        }

        // Strip every match's range (plus a preceding at/by/on/before
        // connector when the detector left it out). Descending order keeps
        // earlier indices valid.
        var stripped = text
        for m in matches.sorted(by: { $0.range.location > $1.range.location }) {
            let start = nsRangeToRange(m.range, in: stripped).lowerBound
            let end = stripped.index(start, offsetBy: m.range.length)
            let stripStart = connectorStripStart(in: stripped, rangeStart: start, connectors: dateConnectors)
            stripped.removeSubrange(stripStart..<end)
        }
        return (due, hasTime, stripped)
    }

    private static func containsDateWord(_ s: String) -> Bool {
        dateWordRegex.firstMatch(in: s, options: [],
                                 range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    private static func rangesOverlap(_ a: NSRange, _ b: NSRange) -> Bool {
        a.location < b.location + b.length && b.location < a.location + a.length
    }

    // MARK: - Pass 4: Location

    private static let addressDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
    private static let trailingAtRegex = try! NSRegularExpression(
        pattern: #"(?:^|\s)(at)\s+(.+)$"#,
        options: [.caseInsensitive])
    private static let placeConnectors: Set<String> = ["at", "near"]

    private static func extractLocation(from input: String) -> (phrase: String?, text: String) {
        var text = input
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let res = addressDetector.firstMatch(in: text, options: [], range: fullRange) {
            let phrase = nsText.substring(with: res.range)
            let start = nsRangeToRange(res.range, in: text).lowerBound
            let end = text.index(start, offsetBy: res.range.length)
            let stripStart = connectorStripStart(in: text, rangeStart: start, connectors: placeConnectors)
            text.removeSubrange(stripStart..<end)
            return (phrase, text)
        }

        if let res = trailingAtRegex.firstMatch(in: text, options: [], range: fullRange) {
            let raw = nsText.substring(with: res.range(at: 2))
            let phrase = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
            if phrase.count >= 3, phrase.rangeOfCharacter(from: .letters) != nil {
                text.removeSubrange(nsRangeToRange(res.range, in: text))
                return (phrase, text)
            }
        }
        return (nil, text)
    }

    // MARK: - Helpers

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func nsRangeToRange(_ ns: NSRange, in s: String) -> Range<String.Index> {
        let start = s.index(s.startIndex, offsetBy: ns.location)
        let end = s.index(start, offsetBy: ns.length)
        return start..<end
    }

    /// If the word immediately before `rangeStart` is one of `connectors`,
    /// return its start index (so the connector + whitespace are stripped too);
    /// otherwise return `rangeStart` unchanged.
    private static func connectorStripStart(in text: String, rangeStart: String.Index, connectors: Set<String>) -> String.Index {
        var wordEnd = rangeStart
        while wordEnd > text.startIndex {
            let prev = text.index(before: wordEnd)
            if text[prev].isWhitespace { wordEnd = prev } else { break }
        }
        var wordStart = wordEnd
        while wordStart > text.startIndex {
            let prev = text.index(before: wordStart)
            if !text[prev].isWhitespace { wordStart = prev } else { break }
        }
        let word = String(text[wordStart..<wordEnd])
        return connectors.contains(word.lowercased()) ? wordStart : rangeStart
    }
}
