import Foundation

enum ExperimentTag: String, CaseIterable, Codable, Identifiable {
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
        case .noAlcohol: return "No Alcohol"
        case .magnesium: return "Magnesium"
        case .lessCaffeine: return "Less Caffeine"
        case .sleepSchedule: return "Sleep Schedule"
        case .morningSunlight: return "Morning Sunlight"
        case .exercise: return "Exercise"
        case .meditation: return "Meditation"
        case .custom: return "Custom"
        }
    }
}

struct CustomExperimentTag: Codable, Equatable {
    let label: String
}
