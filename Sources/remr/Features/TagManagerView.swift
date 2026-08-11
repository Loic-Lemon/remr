import SwiftUI

/// Manage tag colors and apply tag renames/removals across remr's reminders.
struct TagManagerView: View {
    @EnvironmentObject private var store: ReminderStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tagStore = TagStore.shared
    @ObservedObject private var filterStore = FilterStore.shared

    @State private var editingTag: String?
    @State private var renameText = ""
    @State private var pendingDelete: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var tags: [String] {
        store.allTags().filter { $0 != NaturalLanguageParser.ongoingTag }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Tags")
                        .font(.headline)
                    Text("Rename or remove tags from every reminder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close tag manager")
                .help("Close tag manager")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if tags.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No tags yet")
                        .font(.headline)
                    Text("Add #tag to a reminder to manage it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            tagRow(tag)
                        }
                    }
                    .padding(10)
                }
                .scrollIndicators(.hidden)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 340, height: 390)
        .disabled(isWorking)
        .confirmationDialog(
            "Remove #\(pendingDelete ?? "")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from reminders", role: .destructive) {
                guard let tag = pendingDelete else { return }
                pendingDelete = nil
                remove(tag)
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This removes the tag from every reminder that uses it.")
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tagStore.color(for: tag))
                .frame(width: 10, height: 10)

            if editingTag == tag {
                TextField("Tag name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { rename(tag) }

                Button {
                    rename(tag)
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.plain)
                .help("Save rename")

                Button {
                    cancelRename()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Cancel rename")
            } else {
                Text("#\(tag)")
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 4)

                colorMenu(for: tag)

                Button {
                    beginRename(tag)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Rename #\(tag)")

                Button {
                    pendingDelete = tag
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove #\(tag) from reminders")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func colorMenu(for tag: String) -> some View {
        Menu {
            ForEach(Array(TagStore.palette.enumerated()), id: \.offset) { index, nsColor in
                Button {
                    tagStore.setColor(for: tag, paletteIndex: index)
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(nsColor: nsColor))
                            .frame(width: 10, height: 10)
                        Text(TagStore.colorName(index))
                    }
                }
            }
        } label: {
            Circle()
                .fill(tagStore.color(for: tag))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Change #\(tag) color")
    }

    private func beginRename(_ tag: String) {
        errorMessage = nil
        editingTag = tag
        renameText = tag
    }

    private func cancelRename() {
        editingTag = nil
        renameText = ""
        errorMessage = nil
    }

    private func normalizedName(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "#" {
            value.removeFirst()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              !value.contains(where: { $0.isWhitespace }),
              !value.contains("#") else { return nil }
        return value
    }

    private func rename(_ oldTag: String) {
        guard let newTag = normalizedName(renameText) else {
            errorMessage = "Use one non-empty tag name without spaces."
            return
        }
        guard newTag != oldTag else {
            cancelRename()
            return
        }
        guard !tags.contains(where: { $0 != oldTag && $0.caseInsensitiveCompare(newTag) == .orderedSame }) else {
            errorMessage = "#\(newTag) already exists."
            return
        }

        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try store.renameTag(oldTag, to: newTag)
                tagStore.renameTag(oldTag, to: newTag)
                if filterStore.tag == oldTag {
                    filterStore.clear()
                    filterStore.toggle(newTag)
                }
                editingTag = nil
                renameText = ""
                isWorking = false
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func remove(_ tag: String) {
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try store.removeTag(tag)
                tagStore.removeTag(tag)
                if filterStore.tag == tag {
                    filterStore.clear()
                }
                isWorking = false
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
