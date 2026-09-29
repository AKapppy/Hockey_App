import Foundation

nonisolated enum GameStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case live
    case final
    case postponed
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.lowercased() ?? ""
        self = GameStatus(rawValue: raw) ?? .unknown
    }
}
