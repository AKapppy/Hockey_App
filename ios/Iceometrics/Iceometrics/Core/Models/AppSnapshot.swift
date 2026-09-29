import Foundation

nonisolated struct AppSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let source: String
    let games: [HockeyGame]
    let standings: [Standing]

    var liveGames: [HockeyGame] {
        games.filter { $0.status == .live }
    }

    var upcomingGames: [HockeyGame] {
        games
            .filter { $0.status == .scheduled }
            .sorted { $0.startTime < $1.startTime }
    }

    var completedGames: [HockeyGame] {
        games
            .filter { $0.status == .final }
            .sorted { $0.startTime > $1.startTime }
    }
}
