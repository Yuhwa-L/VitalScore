import Foundation
import Combine

final class TagCatalog: ObservableObject {
    @Published private(set) var customTags: [String]

    private let storage: LocalStorageManager

    static let presetTags: [String] = [
        "Gym",
        "Alcohol",
        "No Alcohol",
        "Magnesium",
        "Less Caffeine",
        "Sleep Schedule",
        "Morning",
        "Exercise",
        "Meditation"
    ]

    init(storage: LocalStorageManager) {
        self.storage = storage
        self.customTags = storage.loadCustomTags()
    }

    var allTags: [String] {
        Self.presetTags + customTags
    }

    func isPreset(_ tag: String) -> Bool {
        Self.presetTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    func isCustom(_ tag: String) -> Bool {
        customTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    @discardableResult
    func addCustom(_ rawTag: String) -> String? {
        let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if allTags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return trimmed
        }
        var updated = customTags
        updated.append(trimmed)
        customTags = updated
        storage.saveCustomTags(updated)
        return trimmed
    }

    func removeCustom(_ tag: String) {
        let updated = customTags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
        guard updated.count != customTags.count else { return }
        customTags = updated
        storage.saveCustomTags(updated)
    }
}
