import Foundation

nonisolated struct Standing: Codable, Identifiable, Hashable, Sendable {
    var id: String { team.id }

    let team: Team
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let overtimeLosses: Int
    let points: Int
}
