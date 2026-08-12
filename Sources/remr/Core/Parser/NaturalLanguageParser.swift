import Foundation

/// Result of parsing one line of natural-language reminder input.
struct ParsedReminder: Equatable {
    /// Title after all tokens stripped, whitespace-collapsed.
    var title: String
    /// Matched list name (no `@`); nil when no list matched. An unmatched
    /// `@phrase` is handled by the location pass or stays in the title.
    var listToken: String?
    /// True iff `listToken` matched a real list.
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
    /// Parser warnings and validation diagnostics for the final title.
    var diagnostics: [ParserDiagnostic] = []
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
        self.diagnostics = []
        self.isInvalid = false
        self.original = original
    }
}

/// Pure natural-language reminder parser (no EventKit). List matching takes
/// list titles as an argument so the parser is fully unit-testable.
///
/// Extraction order matters: priority → list → tags → date → location → title.
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
        if result.isInvalid {
            result.diagnostics.append(.emptyTitle)
        }
        if let candidate = list.unmatchedCandidate,
           containsUnmatchedListCandidate(candidate, in: title) {
            result.diagnostics.append(.unmatchedList(candidate))
        }
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
        pattern: #"(?<![#@])\b(high|p1|medium|p2|low|p3)\s+priority\b"#,
        options: [.caseInsensitive])
    // Bare token must be standalone: line start or whitespace before, and
    // whitespace/line end after. This keeps "low-fat" intact ("low" is
    // followed by "-", not a boundary) while "buy high quality milk" still
    // strips "high". The lookbehind also keeps "@p1" from matching.
    private static let priorityBareRegex = try! NSRegularExpression(
        pattern: #"(?<![#@])(?:^|\s)(high|p1|medium|p2|low|p3)(?=\s|$)"#,
        options: [.caseInsensitive])

    private static func extractPriority(from input: String) -> (priority: Int, text: String) {
        var text = input
        var priority = 0
        // Leading "!!" wins over any later priority word, but does not return
        // early: the token itself must still be stripped from the title.
        if let range = text.range(of: #"^(!{1,2})\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
            priority = 1
        }
        if let res = priorityPhraseRegex.firstMatch(in: text, options: [],
                                                    range: NSRange(location: 0, length: (text as NSString).length)) {
            let level = (text as NSString).substring(with: res.range(at: 1))
            text.removeSubrange(nsRangeToRange(res.range, in: text))
            if priority == 0 { priority = priorityForLevel(level) }
        }
        if let res = priorityBareRegex.firstMatch(in: text, options: [],
                                                  range: NSRange(location: 0, length: (text as NSString).length)) {
            let level = (text as NSString).substring(with: res.range(at: 1))
            text.removeSubrange(nsRangeToRange(res.range, in: text))
            if priority == 0 { priority = priorityForLevel(level) }
        }
        return (priority, text)
    }

    private static func priorityForLevel(_ level: String) -> Int {
        switch level.lowercased() {
        case "high", "p1": return 1
        case "medium", "p2": return 5
        default: return 9
        }
    }

    // MARK: - Pass 2: List

    private static let listRegex = try! NSRegularExpression(pattern: #"(?:^|\s)@([^\s@]+)"#)

    private static func extractList(from input: String, listNames: [String]) -> (token: String?, matched: Bool, unmatchedCandidate: String?, text: String) {
        var text = input
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let res = listRegex.firstMatch(in: text, options: [], range: fullRange) else {
            return (nil, false, nil, text)
        }
        let firstWord = nsText.substring(with: res.range(at: 1))

        // Candidate 2 = capture + " " + the word immediately following.
        var candidate2: String?
        var stripEnd = res.range.location + res.range.length
        let afterNS = nsText.substring(from: stripEnd)
        if let nextWord = afterNS.range(of: #"^\s+\S+"#, options: .regularExpression) {
            let secondWord = String(afterNS[nextWord]).trimmingCharacters(in: .whitespaces)
            candidate2 = firstWord + " " + secondWord
            // stripEnd is a UTF-16 offset into nsText, but
            // afterNS.distance(from:to:) counts Characters — the two diverge
            // when the line contains non-BMP characters (emoji). Count UTF-16
            // units of the prefix instead.
            stripEnd += afterNS[afterNS.startIndex..<nextWord.upperBound].utf16.count
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
            // Unmatched @token: leave the @ phrase in the text so the location
            // pass can treat it as a location ("buy milk @the office"). A line
            // that is only "@phrase" keeps the old unmatched-list shape
            // ("@unknown list task" stays a title) — see extractLocation.
            return (nil, false, firstWord, text)
        }

        let stripRange = NSRange(location: res.range.location, length: stripLength)
        text.removeSubrange(nsRangeToRange(stripRange, in: text))
        return (token, matched, nil, text)
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
            .map { String($0.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?")) }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// True iff `input` carries the `#tag` token (exact, case-insensitive) —
    /// the tag-filter rule. Deliberately not a substring match: the chips the
    /// filter is set from come from `extractTags`, so filtering must agree
    /// with what a chip represents.
    static func containsTag(_ tag: String, in input: String) -> Bool {
        extractTags(from: input).contains { $0.lowercased() == tag.lowercased() }
    }

    /// Canonical visible tag used to mark a reminder as ongoing.
    static let ongoingTag = "ongoing"

    /// True when either title or notes contains the exact ongoing tag token.
    static func isOngoing(title: String?, notes: String?) -> Bool {
        let text = [title, notes].compactMap { $0 }.joined(separator: "\n")
        return containsTag(ongoingTag, in: text)
    }

    /// Removes exact tag tokens from `input`, preserving all other text and
    /// line breaks. Tag punctuation follows the same grammar as
    /// ``extractTags(from:)``.
    static func removingTag(_ tag: String, from input: String) -> String {
        let normalizedTag = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        let punctuation = CharacterSet(charactersIn: ",.;:!?")
        guard !normalizedTag.isEmpty else { return input }

        var lines: [String] = []
        for originalLine in input.components(separatedBy: "\n") {
            var line = originalLine
            var ranges: [Range<String.Index>] = []
            var tokenStart: String.Index?

            func inspectToken(through tokenEnd: String.Index) {
                guard let tokenStart else { return }
                let token = String(line[tokenStart..<tokenEnd])
                guard token.hasPrefix("#"), token.count > 1 else { return }
                let name = String(token.dropFirst()).trimmingCharacters(in: punctuation)
                guard name.caseInsensitiveCompare(normalizedTag) == .orderedSame else { return }

                var removalEnd = tokenEnd
                while removalEnd < line.endIndex, line[removalEnd].isWhitespace {
                    removalEnd = line.index(after: removalEnd)
                }
                ranges.append(tokenStart..<removalEnd)
            }

            for index in line.indices {
                if line[index].isWhitespace {
                    if tokenStart != nil {
                        inspectToken(through: index)
                    }
                    tokenStart = nil
                } else if tokenStart == nil {
                    tokenStart = index
                }
            }
            if tokenStart != nil {
                inspectToken(through: line.endIndex)
            }

            for range in ranges.reversed() {
                line.removeSubrange(range)
            }
            if !ranges.isEmpty {
                line = line.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
    /// Replaces exact whitespace-delimited tag tokens while preserving
    /// punctuation and line breaks.
    static func replacingTag(_ tag: String, with replacement: String, in input: String) -> String {
        let old = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        let new = replacement.hasPrefix("#") ? String(replacement.dropFirst()) : replacement
        guard !old.isEmpty, !new.isEmpty, !new.contains(where: { $0.isWhitespace }) else { return input }
        let pattern = #"(^|\s)#"# + NSRegularExpression.escapedPattern(for: old) + #"(?=\s|$|[,.;:!?])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return input }
        let safeReplacement = new
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
        let range = NSRange(location: 0, length: (input as NSString).length)
        return regex.stringByReplacingMatches(in: input,
                                              options: [],
                                              range: range,
                                              withTemplate: "$1#\(safeReplacement)")
    }


    // MARK: - Pass 4: Date

    private static let dateDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let endOfDayRegex = try! NSRegularExpression(
        pattern: #"\b(end of (the )?day|eod|later(\s+today)?)\b"#,
        options: [.caseInsensitive])
    private static let inUnitsRegex = try! NSRegularExpression(
        pattern: #"\bin\s+(an?|half an?|\d+)\s+(minute|minutes|hour|hours|day|days|week|weeks)\b"#,
        options: [.caseInsensitive])
    private static let weekQualifierRegex = try! NSRegularExpression(
        pattern: #"\b(next|this)\s+week\b"#,
        options: [.caseInsensitive])
    private static let hasTimeRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2}(:\d{2})?\s*(a\.?m\.?|p\.?m\.?)|noon|midnight|tonight|tonite|night|morning|afternoon|evening|o'clock|\d{1,2}:\d{2})\b"#,
        options: [.caseInsensitive])
    private static let dateWordRegex = try! NSRegularExpression(
        pattern: #"\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|yesterday|tonight|tonite|next|this|january|february|march|april|may|june|july|august|september|october|november|december|in\s+\d+\s+(minute|minutes|hour|hours|day|days|week|weeks))\b"#,
        options: [.caseInsensitive])
    private static let dateConnectors: Set<String> = ["at", "by", "on", "before"]

    /// One date span found in the line (detector or keyword layer).
    private struct DateMatch {
        var range: NSRange
        var date: Date
        var isKeyword: Bool
        var hasTime: Bool
        var isEOD: Bool = false   // keyword-layer end-of-day: authoritative over detector
        /// Bare clock time (detector match or noon/midnight keyword): may roll
        /// to tomorrow when already past. Keyword dates computed from `now`
        /// (eod/later, in-units, week qualifiers) never roll.
        var rollsOverPast: Bool = false
    }

    private static func extractDate(from input: String, now: Date, calendar: Calendar) -> (due: Date?, hasTime: Bool, text: String) {
        let text = input
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        var matches: [DateMatch] = []
        dateDetector.enumerateMatches(in: text, options: [], range: fullRange) { res, _, _ in
            guard let res, let date = res.date else { return }
            // NSDataDetector resolves relative phrases ("tomorrow", "friday",
            // "5pm", "in 2 days") against the wall clock, which would make
            // `parse(line, now:)` non-deterministic under a pinned `now`.
            // Re-resolve those phrases from `now`; absolute matches keep the
            // detector's clock-independent result.
            let phrase = nsText.substring(with: res.range)
            let rebased = rebaseRelativeDate(phrase, detectorDate: date, now: now, calendar: calendar)
            matches.append(DateMatch(range: res.range, date: rebased ?? date, isKeyword: false, hasTime: hasTimeRegex.firstMatch(in: phrase, options: [],
                                                                                                                                      range: NSRange(location: 0, length: (phrase as NSString).length)) != nil,
                                     rollsOverPast: true))
        }

        // Keyword layer fills gaps the detector misses. Fires only where no
        // detector match overlaps (e.g. "in 2 days" is detector-covered).
        var keywordMatches: [DateMatch] = []
        endOfDayRegex.enumerateMatches(in: text, options: [], range: fullRange) { res, _, _ in
            guard let res else { return }
            let startOfDay = calendar.startOfDay(for: now)
            if let eod = calendar.date(byAdding: .hour, value: 17, to: startOfDay) {
                keywordMatches.append(DateMatch(range: res.range, date: eod, isKeyword: true, hasTime: true, isEOD: true))
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
            // minutes/hours → exact now + offset (timed); days/weeks → noon of
            // the target day (all-day), mirroring the rebase path so "in a
            // week" agrees with "in 1 week". Non-integral week/day amounts
            // truncate via Int(amount) — pre-existing rebase behavior.
            let isTimeUnit = unitSeconds < 86_400
            let date: Date
            if isTimeUnit {
                date = now.addingTimeInterval(amount * unitSeconds)
            } else {
                let days = Int(amount) * (unitStr.hasPrefix("week") ? 7 : 1)
                let start = calendar.startOfDay(for: now)
                let target = calendar.date(byAdding: .day, value: days, to: start) ?? start
                date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: target) ?? target
            }
            keywordMatches.append(DateMatch(range: res.range, date: date, isKeyword: true, hasTime: isTimeUnit))
        }
        weekQualifierRegex.enumerateMatches(in: text, options: [], range: fullRange) { res, _, _ in
            guard let res else { return }
            let phrase = nsText.substring(with: res.range).lowercased()
            let startOfDay = calendar.startOfDay(for: now)
            let target: Date
            if phrase.hasPrefix("next") {
                // "next week" → exactly 7 days from today (matches "in 1 week").
                target = calendar.date(byAdding: .day, value: 7, to: startOfDay) ?? startOfDay
            } else {
                // "this week" → last day of the current week (locale-aware).
                let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? startOfDay
                target = calendar.date(byAdding: .day, value: -1, to: weekEnd) ?? startOfDay
            }
            let date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: target) ?? target
            keywordMatches.append(DateMatch(range: res.range, date: date, isKeyword: true, hasTime: false))
        }
        // Noon/midnight fill the gap the detector misses ("call noon" while
        // "call at noon" works). The overlap rule below drops these when the
        // detector covered the word ("at noon" → detector wins).
        let clockWordRegex = try! NSRegularExpression(
            pattern: #"\b(noon|midnight)\b"#, options: [.caseInsensitive])
        clockWordRegex.enumerateMatches(in: text, options: [], range: fullRange) { res, _, _ in
            guard let res else { return }
            let word = nsText.substring(with: res.range).lowercased()
            let target = calendar.startOfDay(for: now)
            if let d = calendar.date(bySettingHour: word == "noon" ? 12 : 0, minute: 0, second: 0, of: target) {
                keywordMatches.append(DateMatch(range: res.range, date: d, isKeyword: true, hasTime: true, rollsOverPast: true))
            }
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
            matches.append(kw)
        }

        // First match in document order = due date.
        let ordered = matches.sorted { $0.range.location < $1.range.location }
        var due: Date?
        var hasTime = false
        if let first = ordered.first {
            func carriesTime(_ m: DateMatch) -> Bool { m.hasTime }
            func carriesDateWord(_ m: DateMatch) -> Bool {
                containsDateWord(nsText.substring(with: m.range))
            }
            var date = first.date
            var sub = nsText.substring(with: first.range)
            var time = carriesTime(first)
            // NSDataDetector can split "friday by 5pm" into a date-only "friday"
            // match and a bare-time "5pm" match. When exactly one match is a bare
            // clock time (time, no date word) and another is date-only (date word,
            // no time), merge: day from the date match, clock from the time match.
            let bareTimeMatches = ordered.filter { carriesTime($0) && !carriesDateWord($0) }
            let dateOnlyMatches = ordered.filter { !carriesTime($0) && carriesDateWord($0) }
            if bareTimeMatches.count == 1, let bare = bareTimeMatches.first,
               let dateMatch = dateOnlyMatches.first {
                let comps = calendar.dateComponents([.hour, .minute, .second], from: bare.date)
                let merged = calendar.date(bySettingHour: comps.hour ?? 12, minute: comps.minute ?? 0,
                                           second: comps.second ?? 0, of: calendar.startOfDay(for: dateMatch.date))
                date = merged ?? date
                sub = nsText.substring(with: dateMatch.range)
                time = true
            }
            // Past-time rollover: bare clock time already past → next day.
            // Calendar-day arithmetic: adding 86_400s crosses a DST transition
            // to the wrong wall-clock hour (03:00 → 04:00 on spring-forward).
            // Only bare clock times roll — detector matches ("5pm") and
            // noon/midnight keywords ("call midnight" at 12:47 → tomorrow
            // 00:00, per the README). Keyword dates computed from `now`
            // (eod/later = explicit today 17:00, in-units, week qualifiers)
            // never roll, so "buy milk later" at 18:00 stays today 17:00.
            if first.rollsOverPast && time && !containsDateWord(sub) && date < now {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            }
            due = date
            hasTime = time
        }

        // Strip every match's range (plus a preceding at/by/on/before
        // connector when the detector left it out). Descending order keeps
        // earlier indices valid.
        var stripped = text
        for m in matches.sorted(by: { $0.range.location > $1.range.location }) {
            let range = nsRangeToRange(m.range, in: stripped)
            let stripStart = connectorStripStart(in: stripped, rangeStart: range.lowerBound, connectors: dateConnectors)
            var stripEnd = range.upperBound
            // Swallow sentence punctuation left dangling by the removal
            // ("buy milk tomorrow," → "buy milk").
            while stripEnd < stripped.endIndex, ",.;:!?".contains(stripped[stripEnd]) {
                stripEnd = stripped.index(after: stripEnd)
            }
            stripped.removeSubrange(stripStart..<stripEnd)
        }
        return (due, hasTime, stripped)
    }

    private static func containsDateWord(_ s: String) -> Bool {
        dateWordRegex.firstMatch(in: s, options: [],
                                 range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    // MARK: - Deterministic relative dates

    private static let monthNameRegex = try! NSRegularExpression(
        pattern: #"\b(january|february|march|april|may|june|july|august|september|october|november|december)\b"#,
        options: [.caseInsensitive])

    /// Calendar.weekday values (1 = Sunday … 7 = Saturday), keyed by name.
    private static let weekdayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]

    /// Re-resolve a detector match whose phrase is relative ("tomorrow",
    /// "friday", "at 5pm", "in 2 days", "tonight") from `now`, because
    /// NSDataDetector anchored it to the wall clock. Returns nil when the
    /// phrase is absolute (month name or year) — the detector's result is
    /// clock-independent there — or when the phrase isn't one we resolve.
    /// The detector's time-of-day is preserved (date-only phrases resolve to
    /// noon, matching NSDataDetector's convention).
    static func rebaseRelativeDate(_ phrase: String, detectorDate: Date, now: Date, calendar: Calendar) -> Date? {
        let s = phrase.lowercased()
        let fullRange = NSRange(location: 0, length: (s as NSString).length)
        // Absolute date (month/day or year): detector's result is stable.
        if monthNameRegex.firstMatch(in: s, options: [], range: fullRange) != nil
            || s.range(of: #"\d{4}"#, options: .regularExpression) != nil {
            return nil
        }

        let day = calendar.startOfDay(for: now)

        // "in N minutes/hours" → exact now + offset (same as the keyword
        // layer); "in N days/weeks" → noon of now + N (detector convention).
        // The "in N units" phrase may appear anywhere in the detector match
        // ("at 5pm in 2 days"), not just at the start.
        if let m = inUnitsRegex.firstMatch(in: s, options: [], range: fullRange) {
            let amountStr = (s as NSString).substring(with: m.range(at: 1)).lowercased()
            let unitStr = (s as NSString).substring(with: m.range(at: 2)).lowercased()
            let amount: Double
            if amountStr.contains("half") { amount = 0.5 }
            else if let n = Double(amountStr) { amount = n }
            else { amount = 1 }
            let unitSeconds: Double
            if unitStr.hasPrefix("minute") { unitSeconds = 60 }
            else if unitStr.hasPrefix("hour") { unitSeconds = 3600 }
            else if unitStr.hasPrefix("day") { unitSeconds = 86_400 }
            else { unitSeconds = 604_800 }  // week
            if unitSeconds < 86_400 {
                return now.addingTimeInterval(amount * unitSeconds)
            }
            // Calendar-day arithmetic; weeks = 7 days. (Previously the unit was
            // ignored: "in 2 weeks" landed 2 days out.)
            let days = Int(amount) * (unitStr.hasPrefix("week") ? 7 : 1)
            guard let target = calendar.date(byAdding: .day, value: days, to: day) else { return nil }
            // Preserve the detector's time-of-day: "in 2 days at 5pm" is a
            // timed due date at 17:00, not noon. Date-only phrases resolve to
            // noon (NSDataDetector's convention), which the detectorDate keeps.
            let time = calendar.dateComponents([.hour, .minute, .second], from: detectorDate)
            return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0,
                                 second: time.second ?? 0, of: target)
        }

        var targetDay: Date?
        // "day after tomorrow" contains "tomorrow", so the compound phrases
        // must precede the bare-word branches.
        if s.contains("day after tomorrow") {
            targetDay = calendar.date(byAdding: .day, value: 2, to: day)
        } else if s.contains("day before yesterday") {
            targetDay = calendar.date(byAdding: .day, value: -2, to: day)
        } else if s.contains("tomorrow") {
            targetDay = calendar.date(byAdding: .day, value: 1, to: day)
        } else if s.contains("yesterday") {
            targetDay = calendar.date(byAdding: .day, value: -1, to: day)
        } else if s.contains("today") {
            targetDay = day
        } else if let weekday = weekdayNames.first(where: { s.contains($0.key) })?.value {
            // Next occurrence at-or-after today — NSDataDetector's rule for a
            // bare weekday ("friday" → this week's friday). A "next" qualifier
            // shifts the result a full week out, so "next tuesday" from a
            // Sunday is the tuesday after the coming one (matches what the
            // detector returns for its phrase, whose range includes "next").
            let today = calendar.component(.weekday, from: day)
            var delta = weekday - today
            if delta < 0 { delta += 7 }
            if s.contains("next") { delta += 7 }
            targetDay = calendar.date(byAdding: .day, value: delta, to: day)
        } else if hasTimeRegex.firstMatch(in: s, options: [], range: fullRange) != nil {
            // Bare clock time ("at 5pm", "tonight", "noon") → now's day.
            targetDay = day
        }

        guard let targetDay else { return nil }
        let time = calendar.dateComponents([.hour, .minute, .second], from: detectorDate)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0,
                             second: time.second ?? 0, of: targetDay)
    }

    private static func rangesOverlap(_ a: NSRange, _ b: NSRange) -> Bool {
        a.location < b.location + b.length && b.location < a.location + a.length
    }

    // MARK: - Pass 4: Location

    private static let addressDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
    private static let trailingAtRegex = try! NSRegularExpression(
        pattern: #"(?:^|\s)(at)\s+(.+)$"#,
        options: [.caseInsensitive])
    /// `&phrase` — the explicit location prefix ("buy milk &the office").
    private static let trailingAmpRegex = try! NSRegularExpression(
        pattern: #"(?:^|\s)&\s*(.+)$"#,
        options: [.caseInsensitive])
    private static let placeConnectors: Set<String> = ["at", "near"]
    /// Words that begin a new clause after a location phrase, ending it:
    /// "at home i need to do this" → location "home", title "i need to do this".
    /// Case-insensitive, whole-word. Deliberately excludes "my" (here-phrase
    /// "my location") and "and"/"or" (handled separately — they can join
    /// place names like "5th and Main").
    private static let locationStopWords: Set<String> = [
        "i", "i'm", "i've", "i'll", "i'd", "you", "we", "they", "he", "she", "it",
        "and", "or", "but", "then", "so", "also", "because", "after", "before",
        "when", "while", "please", "thanks", "ok", "okay", "to", "for", "with", "me",
    ]
    /// Clause connectors that can instead join place names ("Oak and Pine"):
    /// only a boundary when the next word is not capitalized.
    private static let placeJoiningConnectors: Set<String> = ["and", "or"]

    private static func extractLocation(from input: String) -> (phrase: String?, text: String) {
        var text = input
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let res = addressDetector.firstMatch(in: text, options: [], range: fullRange) {
            let phrase = nsText.substring(with: res.range)
            let range = nsRangeToRange(res.range, in: text)
            let stripStart = connectorStripStart(in: text, rangeStart: range.lowerBound, connectors: placeConnectors)
            text.removeSubrange(stripStart..<range.upperBound)
            return (phrase, text)
        }

        // "&phrase" — the explicit, unambiguous location prefix. Runs before
        // the natural-language "at" so "&" is never swallowed by it.
        if let phrase = Self.extractPrefixedLocation(from: &text, prefix: trailingAmpRegex, rawCapture: 1) {
            return (phrase, text)
        }

        // Natural-language "at phrase".
        if let phrase = Self.extractPrefixedLocation(from: &text, prefix: trailingAtRegex, rawCapture: 2) {
            return (phrase, text)
        }
        return (nil, text)
    }

    /// Strips "<prefix>phrase" from the end of the line and returns the
    /// phrase, or nil when the match isn't a valid location. Prefixes: "&"
    /// (explicit) and "at" (natural language). A quoted phrase (`&"the office
    /// and grill"`) is taken verbatim — no clause-boundary scanning — so a
    /// place that contains words like "and"/"with" can be named exactly.
    private static func extractPrefixedLocation(from text: inout String,
                                                prefix: NSRegularExpression,
                                                rawCapture: Int) -> String? {
        let nsText = text as NSString
        guard let res = prefix.firstMatch(in: text, options: [],
                                          range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }
        let rawRange = nsRangeToRange(res.range(at: rawCapture), in: text)
        let raw = String(text[rawRange])
        let stripEnd: String.Index
        let phrase: String
        if raw.first == "\"", let closeQuote = raw.dropFirst().firstIndex(of: "\"") {
            // Quoted: the whole span between the quotes is the location.
            let content = raw[raw.index(after: raw.startIndex)..<closeQuote]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            phrase = content
            stripEnd = text.index(rawRange.lowerBound,
                                  offsetBy: raw.distance(from: raw.startIndex, to: closeQuote) + 1)
        } else {
            // Unquoted: truncate at the first clause boundary.
            let phraseEnd = Self.locationPhraseEnd(in: raw)
            phrase = String(raw[..<phraseEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
            guard phrase.count >= 3, phrase.rangeOfCharacter(from: .letters) != nil else { return nil }
            stripEnd = Self.stripEndIndex(raw: raw,
                                          phraseEnd: phraseEnd,
                                          rawStart: rawRange.lowerBound,
                                          in: text)
        }
        let stripStart = nsRangeToRange(res.range(at: 0), in: text).lowerBound
        text.removeSubrange(stripStart..<stripEnd)
        return phrase
    }

    // MARK: - Helpers

    /// The end of the location phrase inside `raw` (the text after "at"/"&"):
    /// the first clause-starting word or sentence punctuation, so a location
    /// in the middle of a sentence ("at home i need to do this") doesn't
    /// swallow the rest of the line. Returns `raw.endIndex` when the whole
    /// remainder is the phrase.
    private static func locationPhraseEnd(in raw: String) -> String.Index {
        let words = raw.split(whereSeparator: { $0.isWhitespace })
        for (index, word) in words.enumerated() {
            let lower = word.lowercased()
            let isStop = Self.locationStopWords.contains(lower)
            if isStop, Self.placeJoiningConnectors.contains(lower),
               index + 1 < words.count,
               words[index + 1].first?.isUppercase == true {
                // "5th and Main" / "Oak and Pine" — proper-noun continuation,
                // part of the place, not a new clause.
                continue
            }
            if isStop { return word.startIndex }
            // Sentence punctuation ends the phrase. A period is deliberately
            // not a boundary: it usually marks an abbreviation in places
            // ("St.", "Ave.") — sentence periods mid-line are rare here.
            // A standalone dash ("--", "—") separates the location from the
            // rest of the sentence ("at home -- i need to do this").
            let hasPunctuation = word.contains(where: { ",;:!?–—".contains($0) })
                || (!word.isEmpty && word.allSatisfy { $0 == "-" })
            if hasPunctuation { return word.startIndex }
        }
        return raw.endIndex
    }

    /// End of the strip range: the phrase up to `phraseEnd`, excluding
    /// inter-word whitespace before a boundary token, so "at home -- x"
    /// strips "at home" and keeps the space before the "--".
    private static func stripEndIndex(raw: String,
                                      phraseEnd: String.Index,
                                      rawStart: String.Index,
                                      in text: String) -> String.Index {
        var offset = raw.distance(from: raw.startIndex, to: phraseEnd)
        while offset > 0,
              raw[raw.index(raw.startIndex, offsetBy: offset - 1)].isWhitespace {
            offset -= 1
        }
        return text.index(rawStart, offsetBy: offset)
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
    private static func containsUnmatchedListCandidate(_ candidate: String, in title: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: candidate)
        let pattern = #"(?:^|\s)@"# + escaped + #"(?=\s|$|[.,;:!?])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(location: 0, length: (title as NSString).length)
        return regex.firstMatch(in: title, options: [], range: range) != nil
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// NSRange offsets are UTF-16 code units; String.index(offsetBy:) counts
    /// Characters (grapheme clusters). `Range(_:in:)` converts correctly even
    /// for emoji/CJK. A nil result (a range splitting a grapheme) degrades to
    /// an empty range, which makes every removeSubrange a safe no-op.
    private static func nsRangeToRange(_ ns: NSRange, in s: String) -> Range<String.Index> {
        Range(ns, in: s) ?? s.startIndex..<s.startIndex
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
