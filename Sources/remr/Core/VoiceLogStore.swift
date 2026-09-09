import Foundation
import SwiftUI

struct VoiceLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let transcript: String
    let cleaned: String

    init(id: UUID = UUID(), createdAt: Date = Date(), transcript: String, cleaned: String) {
        self.id = id
        self.createdAt = createdAt
        self.transcript = transcript
        self.cleaned = cleaned
    }
}

@MainActor
final class VoiceLogStore: ObservableObject {
    static let shared = VoiceLogStore()

    @Published private(set) var entries: [VoiceLogEntry]
    private let defaults = UserDefaults.standard
    private let key = "remr.voiceLog"

    init() {
        guard let data = UserDefaults.standard.data(forKey: "remr.voiceLog"),
              let saved = try? JSONDecoder().decode([VoiceLogEntry].self, from: data) else {
            entries = []
            return
        }
        entries = saved.sorted { $0.createdAt > $1.createdAt }
    }

    func append(transcript: String, cleaned: String) {
        entries.insert(VoiceLogEntry(transcript: transcript, cleaned: cleaned), at: 0)
        save()
    }

    func delete(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

struct VoiceLogView: View {
    @ObservedObject var store: VoiceLogStore
    let onClose: () -> Void
    let onAdd: (String) -> Void
    @State private var selection = Set<UUID>()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Log").font(.title3.weight(.semibold))
                    Text("Review before adding reminders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(.bordered)
            }
            .padding(16)
            .zIndex(1)

            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No voice entries")
                    Text("Recorded voice notes will collect here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.entries, selection: $selection) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(Self.dateFormatter.string(from: entry.createdAt))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !entry.transcript.isEmpty {
                                Text("Transcribed")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(entry.cleaned)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        if entry.transcript != entry.cleaned {
                            DisclosureGroup("Original transcript") {
                                Text(entry.transcript)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Add to reminders") { onAdd(entry.cleaned) }
                        Button("Delete", role: .destructive) { store.delete(ids: [entry.id]) }
                    }
                }
                .listStyle(.inset)
                // Prevent list rows and the native scroller from painting into
                // the fixed header/footer while scrolling.
                .clipped()
            }

            HStack {
                Button("Delete Selected", role: .destructive) {
                    store.delete(ids: selection)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button("Add Selected to Reminders") {
                    let text = store.entries.filter { selection.contains($0.id) }
                        .map(\.cleaned).joined(separator: "\n")
                    guard !text.isEmpty else { return }
                    onAdd(text)
                }
                .disabled(selection.isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassPane(in: RoundedRectangle(cornerRadius: 16))
    }
}
