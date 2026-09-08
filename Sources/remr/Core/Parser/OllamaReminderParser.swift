import Foundation

struct OllamaReminderResult: Codable, Equatable {
    var title: String
    var description: String
    var deadlineText: String?
}

struct BulkMarkdownItem: Equatable {
    let text: String
    let tags: [String]
}

enum BulkMarkdownParser {
    static func items(from markdown: String) -> [BulkMarkdownItem] {
        var headingStack: [(level: Int, tag: String)] = []
        var current: String?
        var currentTags: [String] { headingStack.map(\.tag) }
        var result: [BulkMarkdownItem] = []

        func appendCurrent() {
            guard let current else { return }
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(BulkMarkdownItem(text: text, tags: currentTags)) }
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = trimmed.range(of: #"^#{1,6}\s+(.+?)\s*$"#, options: .regularExpression) {
                appendCurrent()
                let headingText = String(trimmed[heading])
                let level = headingText.prefix { $0 == "#" }.count
                let value = headingText.drop { $0 == "#" || $0 == " " }.trimmingCharacters(in: .whitespaces)
                while headingStack.last?.level ?? 0 >= level { headingStack.removeLast() }
                headingStack.append((level, Self.slug(String(value))))
                current = nil
            } else if let match = trimmed.range(of: #"^(?:[-*+]\s+|\d+[.)]\s+)(.+)$"#, options: .regularExpression) {
                appendCurrent()
                current = String(trimmed[match]).replacingOccurrences(of: #"^(?:[-*+]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
            } else if current != nil, !trimmed.isEmpty {
                current! += "\n" + trimmed
            }
        }
        appendCurrent()
        return result
    }

    private static func slug(_ value: String) -> String {
        let words = value.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: "-")
    }
}

final class OllamaReminderParser {
    enum ParserError: LocalizedError {
        case invalidResponse
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Ollama returned invalid reminder data."
            case .unavailable(let message): return message
            }
        }
    }

    private struct Request: Encodable {
        let model: String
        let prompt: String
        let stream = false
        let format = "json"
        let options = Options()

        struct Options: Encodable {
            let temperature = 0
        }
    }

    private struct Response: Decodable {
        let response: String
    }

    private let endpoint = URL(string: "http://localhost:11434/api/generate")!
    private let session: URLSession
    private let model: String

    init(model: String = "qwen2.5:3b", session: URLSession = .shared) {
        self.model = model
        self.session = session
    }

    func parse(_ item: BulkMarkdownItem) async throws -> OllamaReminderResult {
        let prompt = """
        Return JSON only with exactly these keys: title, description, deadlineText.
        Clean up the action into a concise reminder title.
        Put research questions and supporting context in description.
        Extract and lightly normalize deadline wording into deadlineText.
        Do not calculate dates. Use null when no deadline is present.
        Do not explain your answer.

        Input:
        \(item.text)
        """
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: model, prompt: prompt))

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ParserError.unavailable("Ollama did not accept the request.")
            }
            let wrapper = try JSONDecoder().decode(Response.self, from: data)
            guard let result = try? JSONDecoder().decode(OllamaReminderResult.self, from: Data(wrapper.response.utf8)) else {
                throw ParserError.invalidResponse
            }
            return result
        } catch let error as ParserError {
            throw error
        } catch {
            throw ParserError.unavailable("Ollama is not reachable. Start Ollama and try again.")
        }
    }

    func parseBulk(_ markdown: String) async throws -> [(item: BulkMarkdownItem, result: OllamaReminderResult)] {
        let process = try await startIfNeeded()
        defer { process?.terminate() }

        var results: [(item: BulkMarkdownItem, result: OllamaReminderResult)] = []
        for item in BulkMarkdownParser.items(from: markdown) {
            results.append((item, try await parse(item)))
        }
        return results
    }

    private func startIfNeeded() async throws -> Process? {
        if await isReachable() { return nil }
        guard let executable = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama"
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ParserError.unavailable("Ollama is not installed or is not running.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        for _ in 0..<30 {
            if await isReachable() { return process }
            try? await Task.sleep(for: .milliseconds(200))
        }
        process.terminate()
        throw ParserError.unavailable("Ollama did not start in time.")
    }

    private func isReachable() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
