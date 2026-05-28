import SwiftUI

struct TagPickerSheet: View {
    @EnvironmentObject var tagCatalog: TagCatalog
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onConfirm: (String) -> Void

    @State private var selectedTag: String?
    @State private var newTagText: String = ""
    @State private var showDeleteConfirmation: String?

    init(
        title: String = "Choose a tag",
        initialTag: String? = nil,
        onConfirm: @escaping (String) -> Void
    ) {
        self.title = title
        self.onConfirm = onConfirm
        _selectedTag = State(initialValue: initialTag)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    ForEach(TagCatalog.presetTags, id: \.self) { tag in
                        tagRow(tag, isCustom: false)
                    }
                }

                if !tagCatalog.customTags.isEmpty {
                    Section("Custom") {
                        ForEach(tagCatalog.customTags, id: \.self) { tag in
                            tagRow(tag, isCustom: true)
                        }
                        .onDelete { indexSet in
                            indexSet
                                .map { tagCatalog.customTags[$0] }
                                .forEach { removeCustom($0) }
                        }
                    }
                }

                Section("Add new tag") {
                    HStack {
                        TextField("e.g. Cold plunge", text: $newTagText)
                            .textInputAutocapitalization(.words)
                        Button("Add") {
                            addNewTag()
                        }
                        .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section {
                    Button {
                        confirmUntagged()
                    } label: {
                        Text("Skip — save as Untagged")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        guard let selected = selectedTag else { return }
                        onConfirm(selected)
                        dismiss()
                    }
                    .disabled(selectedTag == nil)
                }
            }
            .alert(
                "Delete tag?",
                isPresented: Binding(
                    get: { showDeleteConfirmation != nil },
                    set: { if !$0 { showDeleteConfirmation = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let tag = showDeleteConfirmation {
                        tagCatalog.removeCustom(tag)
                        if selectedTag?.caseInsensitiveCompare(tag) == .orderedSame {
                            selectedTag = nil
                        }
                    }
                    showDeleteConfirmation = nil
                }
                Button("Cancel", role: .cancel) {
                    showDeleteConfirmation = nil
                }
            } message: {
                if let tag = showDeleteConfirmation {
                    Text("Remove \"\(tag)\" from your custom tags. Saved results keep their existing tag.")
                }
            }
        }
    }

    private func tagRow(_ tag: String, isCustom: Bool) -> some View {
        HStack {
            Button {
                selectedTag = tag
            } label: {
                HStack {
                    Image(systemName: selectedTag?.caseInsensitiveCompare(tag) == .orderedSame
                          ? "largecircle.fill.circle"
                          : "circle")
                        .foregroundStyle(.tint)
                    Text(tag)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCustom {
                Button {
                    showDeleteConfirmation = tag
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func addNewTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let added = tagCatalog.addCustom(trimmed) {
            selectedTag = added
        } else {
            selectedTag = trimmed
        }
        newTagText = ""
    }

    private func removeCustom(_ tag: String) {
        tagCatalog.removeCustom(tag)
        if selectedTag?.caseInsensitiveCompare(tag) == .orderedSame {
            selectedTag = nil
        }
    }

    private func confirmUntagged() {
        onConfirm(ExperimentTagValue.untagged)
        dismiss()
    }
}
