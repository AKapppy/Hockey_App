import Foundation

nonisolated enum SampleData {
    static let rangers = Team(
        id: "nyr",
        abbreviation: "NYR",
        name: "New York Rangers",
        logoURL: nil
    )

    static let devils = Team(
        id: "njd",
        abbreviation: "NJD",
        name: "New Jersey Devils",
        logoURL: nil
    )

    static let snapshot = AppSnapshot(
        generatedAt: .now,
        source: "Bundled Iceometics starter data — not live",
        games: [
            HockeyGame(
                id: "fixture-001",
                startTime: .now.addingTimeInterval(3600),
                status: .scheduled,
                awayTeam: rangers,
                homeTeam: devils,
                awayScore: nil,
                homeScore: nil,
                venue: "Starter Fixture Arena"
            )
        ],
        standings: [
            Standing(
                team: rangers,
                gamesPlayed: 1,
                wins: 1,
                losses: 0,
                overtimeLosses: 0,
                points: 2
            )
        ]
    )
}
