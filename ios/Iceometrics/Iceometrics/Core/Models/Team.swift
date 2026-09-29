import Foundation

nonisolated struct Team: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let abbreviation: String
    let name: String
    let logoURL: URL?
}
