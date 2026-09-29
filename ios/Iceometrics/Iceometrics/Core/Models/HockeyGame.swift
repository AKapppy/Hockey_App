import Foundation

nonisolated struct HockeyGame: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let startTime: Date
    let status: GameStatus
    let awayTeam: Team
    let homeTeam: Team
    let awayScore: Int?
    let homeScore: Int?
    let venue: String?
}
