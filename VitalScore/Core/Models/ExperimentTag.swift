import Foundation

enum ExperimentTag: String, CaseIterable, Codable, Identifiable {
    case gym
    case alcohol
    case noAlcohol
    case magnesium
    case lessCaffeine
    case sleepSchedule
    case morningSunlight
    case exercise
    case meditation
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gym: return "Gym"
        case .alcohol: return "Alcohol"
        case .noAlcohol: return "No Alcohol"
        case .magnesium: return "Magnesium"
        case .lessCaffeine: return "Less Caffeine"
        case .sleepSchedule: return "Sleep Schedule"
        case .morningSunlight: return "Morning"
        case .exercise: return "Exercise"
        case .meditation: return "Meditation"
        case .custom: return "Custom"
        }
    }
}

struct CustomExperimentTag: Codable, Equatable {
    let label: String
}

enum ExperimentTagValue {
    static let allTagsLabel = "All Tags"
    static let untagged = "Untagged"

    static func normalized(_ tag: String?) -> String {
        let trimmed = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? untagged : trimmed
    }

    static func matches(_ tag: String?, filter: String?) -> Bool {
        guard let filter else { return true }
        return normalized(tag).caseInsensitiveCompare(normalized(filter)) == .orderedSame
    }
}
