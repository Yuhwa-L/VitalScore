import Foundation
import Combine

final class ExperimentManager: ObservableObject {
    @Published var current: ExperimentTag?
    @Published var customLabel: String?

    private let storage: LocalStorageManager

    init(storage: LocalStorageManager) {
        self.storage = storage
        let (tag, label) = storage.loadSelectedExperiment()
        self.current = tag
        self.customLabel = label
    }

    func select(_ tag: ExperimentTag, customLabel: String? = nil) {
        current = tag
        self.customLabel = tag == .custom ? customLabel : nil
        storage.saveSelectedExperiment(tag, customLabel: self.customLabel)
    }

    func clear() {
        current = nil
        customLabel = nil
        storage.saveSelectedExperiment(nil, customLabel: nil)
    }

    var displayName: String {
        guard let tag = current else { return "None" }
        if tag == .custom, let label = customLabel, !label.isEmpty {
            return label
        }
        return tag.displayName
    }
}
