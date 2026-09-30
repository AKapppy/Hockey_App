import Foundation

actor StatsDataService {
    private let baseURL: URL
    private let season: String
    private let client: APIClient

    init(
        baseURL: URL = URL(string: "https://akapppy.github.io/Hockey_App/")!,
        season: String = "2026-2027",
        client: APIClient = APIClient()
    ) {
        self.baseURL = baseURL
        self.season = season
        self.client = client
    }

    func fetchSnapshot() async throws -> StatsSnapshot {
        var request = APIRequest(path: "seasons/\(season)/data.json")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.headers["Cache-Control"] = "no-cache, no-store, max-age=0"
        request.headers["Pragma"] = "no-cache"
        request.queryItems = [
            URLQueryItem(name: "stats_v", value: UUID().uuidString)
        ]

        let export = try await client.send(
            request,
            baseURL: baseURL,
            as: StatsExport.self
        )

        return export.makeSnapshot(
            baseURL: baseURL,
            fallbackSeason: season
        )
    }
}

private nonisolated struct StatsExport: Decodable, Sendable {
    let metadata: Metadata
    let teams: [TeamRow]
    let desktop: Desktop

    nonisolated struct Metadata: Decodable, Sendable {
        let season: String
        let generatedAt: Date
    }

    nonisolated struct TeamRow: Decodable, Sendable {
        let code: String
        let name: String
        let logo: String?
        let color: String?
    }

    nonisolated struct Desktop: Decodable, Sendable {
        let scoreboard: SharedWebScoreboard
    }

    func makeSnapshot(
        baseURL: URL,
        fallbackSeason: String
    ) -> StatsSnapshot {
        let mappedTeams = teams.map { team in
            StatsTeam(
                code: team.code.uppercased(),
                name: team.name,
                logoURL: team.logo.flatMap {
                    URL(string: $0, relativeTo: baseURL)?.absoluteURL
                },
                colorHex: team.color ?? ""
            )
        }

        let mappedGames = desktop.scoreboard.days
            .flatMap { day, games in
                games.compactMap { game -> StatsGame? in
                    guard game.league.uppercased() == "NHL" else { return nil }
                    let away = game.away.code.uppercased()
                    let home = game.home.code.uppercased()
                    guard !away.isEmpty, !home.isEmpty else { return nil }

                    let id = game.id.value.isEmpty
                        ? "\(day)-\(away)-\(home)"
                        : game.id.value
                    let gameType = game.gameTypeId
                        ?? Self.gameTypeFromID(game.id.value)
                        ?? 0

                    return StatsGame(
                        id: id,
                        day: day,
                        gameTypeID: gameType,
                        state: game.state,
                        status: game.status,
                        awayCode: away,
                        homeCode: home,
                        awayScore: game.away.score,
                        homeScore: game.home.score,
                        periodType: game.periodDescriptor?.periodType
                    )
                }
            }
            .sorted { ($0.day, $0.id) < ($1.day, $1.id) }

        return StatsSnapshot(
            generatedAt: metadata.generatedAt,
            season: metadata.season.isEmpty ? fallbackSeason : metadata.season,
            teams: mappedTeams,
            games: mappedGames
        )
    }

    private static func gameTypeFromID(_ raw: String) -> Int? {
        guard raw.count >= 6 else { return nil }
        let start = raw.index(raw.startIndex, offsetBy: 4)
        let end = raw.index(start, offsetBy: 2)
        return Int(raw[start..<end])
    }
}
