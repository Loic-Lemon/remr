import EventKit
import Foundation

enum ReminderLocationDraft: Equatable {
    case none
    case unresolved(String)
    case resolved(DeletedLocation)
}

struct ReminderDraft: Identifiable, Equatable {
    let id: UUID
    var rawInput: String?
    var title: String
    var notes: String
    var dueDate: Date?
    var hasTime: Bool
    var priority: Int
    var calendarIdentifier: String?
    var calendarTitle: String?
    var location: ReminderLocationDraft
    var tags: [String]
    var diagnostics: [ParserDiagnostic]

    init(id: UUID = UUID(),
         rawInput: String? = nil,
         title: String,
         notes: String = "",
         dueDate: Date? = nil,
         hasTime: Bool = false,
         priority: Int = 0,
         calendarIdentifier: String? = nil,
         calendarTitle: String? = nil,
         location: ReminderLocationDraft = .none,
         tags: [String] = [],
         diagnostics: [ParserDiagnostic] = []) {
        self.id = id
        self.rawInput = rawInput
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priority = priority
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.location = location
        self.tags = tags
        self.diagnostics = diagnostics
    }

    static func fromParsed(_ parsed: ParsedReminder,
                           notes: String,
                           calendar: EKCalendar?) -> ReminderDraft {
        ReminderDraft(
            rawInput: parsed.original,
            title: parsed.title,
            notes: notes,
            dueDate: parsed.dueDate,
            hasTime: parsed.hasTime,
            priority: parsed.priority,
            calendarIdentifier: calendar?.calendarIdentifier,
            calendarTitle: calendar?.title,
            location: parsed.locationPhrase.map(ReminderLocationDraft.unresolved) ?? .none,
            tags: normalizedTags(parsed.tags),
            diagnostics: parsed.diagnostics
        )
    }

    static func fromReminder(_ reminder: EKReminder) -> ReminderDraft {
        let title = reminder.title ?? ""
        let notes = reminder.notes ?? ""
        let tags = normalizedTags(NaturalLanguageParser.extractTags(from: [title, notes].joined(separator: "\n")))
        let editableTitle = removingMetadataTags(from: title, tags: tags)
        let editableNotes = removingTrailingTagLines(from: notes)
        let components = reminder.dueDateComponents
        let location: ReminderLocationDraft
        if let structured = reminder.alarms?.compactMap({ $0.structuredLocation }).first {
            let coordinate = structured.geoLocation?.coordinate
            location = .resolved(DeletedLocation(
                title: structured.title ?? "",
                latitude: coordinate?.latitude ?? 0,
                longitude: coordinate?.longitude ?? 0,
                radius: structured.radius
            ))
        } else {
            location = .none
        }

        return ReminderDraft(
            title: editableTitle,
            notes: editableNotes,
            dueDate: components.flatMap { Calendar.current.date(from: $0) },
            hasTime: components?.hour != nil,
            priority: reminder.priority,
            calendarIdentifier: reminder.calendar?.calendarIdentifier,
            calendarTitle: reminder.calendar?.title,
            location: location,
            tags: tags,
            diagnostics: []
        )
    }

    static func fromDeleted(_ deleted: DeletedReminder) -> ReminderDraft {
        let title = deleted.title
        let notes = deleted.notes ?? ""
        let tags = normalizedTags(NaturalLanguageParser.extractTags(from: [title, notes].joined(separator: "\n")))
        return ReminderDraft(
            id: deleted.id,
            title: removingMetadataTags(from: title, tags: tags),
            notes: removingTrailingTagLines(from: notes),
            dueDate: deleted.dueDate,
            hasTime: !deleted.isAllDay,
            priority: deleted.priority,
            calendarIdentifier: deleted.calendarIdentifier,
            location: deleted.location.map(ReminderLocationDraft.resolved) ?? .none,
            tags: tags,
            diagnostics: []
        )
    }

    /// Notes representation used when writing a reminder. Tags are stored as
    /// one metadata line so a draft can be opened, edited, and saved without
    /// changing the ordinary notes body.
    var persistedNotes: String? {
        let body = Self.removingTrailingTagLines(from: notes)
        let normalized = Self.normalizedTags(tags)
        let tagLine = normalized.map { "#\($0)" }.joined(separator: " ")
        let bodyIsEmpty = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let result: String
        if normalized.isEmpty {
            result = bodyIsEmpty ? "" : body
        } else if bodyIsEmpty {
            result = tagLine
        } else {
            result = body + "\n" + tagLine
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Tag and notes codec

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let punctuation = CharacterSet(charactersIn: ",.;:!?")
        for rawTag in tags {
            var tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if tag.first == "#" {
                tag.removeFirst()
            }
            tag = tag.trimmingCharacters(in: punctuation)
            guard !tag.isEmpty, !tag.contains(where: { $0.isWhitespace }) else { continue }
            let key = tag.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    private static func removingMetadataTags(from title: String, tags: [String]) -> String {
        let known = Set(tags.map { $0.lowercased() })
        return title
            .split(whereSeparator: { $0.isWhitespace })
            .filter { token in
                guard let first = token.first, first == "#", token.count > 1 else { return true }
                let extracted = NaturalLanguageParser.extractTags(from: String(token))
                return !extracted.contains { known.contains($0.lowercased()) }
            }
            .map(String.init)
            .joined(separator: " ")
    }

    private static func isTagOnlyLine(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy { token in
            guard token.first == "#", token.count > 1 else { return false }
            let rawTag = String(token.dropFirst())
            let extracted = NaturalLanguageParser.extractTags(from: String(token))
            // Canonical lines are emitted by persistedNotes as plain #tag
            // tokens. A punctuation-bearing legacy line is ordinary notes,
            // even though the parser can recognize its metadata token.
            return extracted.count == 1 && extracted[0] == rawTag
        }
    }

    private static func removingTrailingTagLines(from notes: String) -> String {
        var lines = notes.components(separatedBy: "\n")
        while let index = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              isTagOnlyLine(lines[index]) {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }
}
