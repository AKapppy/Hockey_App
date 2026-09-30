import Foundation

nonisolated struct PlayerStatLine: Identifiable, Hashable, Sendable {
    let playerID: Int
    let name: String
    let teamCode: String
    let values: [String: Double]

    var id: String {
        playerID > 0 ? String(playerID) : "\(teamCode)-\(name)"
    }

    func value(_ stat: String) -> Double {
        values[stat] ?? 0
    }
}

nonisolated struct PlayerStatsSnapshot: Sendable {
    let phase: StatsPhase
    let skaters: [PlayerStatLine]
    let goalies: [PlayerStatLine]
}

actor PlayerStatsService {
    private let client: APIClient
    private let baseURL: URL

    init(
        client: APIClient = APIClient(),
        baseURL: URL = URL(string: "https://api-web.nhle.com/")!
    ) {
        self.client = client
        self.baseURL = baseURL
    }

    func fetch(
        season: String,
        phase: StatsPhase
    ) async throws -> PlayerStatsSnapshot {
        let seasonID = season.replacingOccurrences(of: "-", with: "")
        let gameType = phase.gameTypeID

        var mutableSkaterRequest = APIRequest(
            path: "v1/skater-stats-leaders/\(seasonID)/\(gameType)"
        )
        mutableSkaterRequest.cachePolicy = .reloadIgnoringLocalCacheData
        mutableSkaterRequest.queryItems = [URLQueryItem(name: "limit", value: "25")]
        mutableSkaterRequest.headers["Cache-Control"] = "no-cache"
        let skaterRequest = mutableSkaterRequest

        var mutableGoalieRequest = APIRequest(
            path: "v1/goalie-stats-leaders/\(seasonID)/\(gameType)"
        )
        mutableGoalieRequest.cachePolicy = .reloadIgnoringLocalCacheData
        mutableGoalieRequest.queryItems = [URLQueryItem(name: "limit", value: "25")]
        mutableGoalieRequest.headers["Cache-Control"] = "no-cache"
        let goalieRequest = mutableGoalieRequest

        async let skaterFetch: NHLLeaderPayload? = try? client.send(
            skaterRequest,
            baseURL: baseURL,
            as: NHLLeaderPayload.self
        )
        async let goalieFetch: NHLLeaderPayload? = try? client.send(
            goalieRequest,
            baseURL: baseURL,
            as: NHLLeaderPayload.self
        )

        let skaterPayload = await skaterFetch
        let goaliePayload = await goalieFetch

        guard skaterPayload != nil || goaliePayload != nil else {
            throw IceometicsError.invalidResponse
        }

        return PlayerStatsSnapshot(
            phase: phase,
            skaters: Self.buildSkaters(skaterPayload),
            goalies: Self.buildGoalies(goaliePayload)
        )
    }

    private static func buildSkaters(_ payload: NHLLeaderPayload?) -> [PlayerStatLine] {
        guard let payload else { return [] }
        var store: [String: MutablePlayerLine] = [:]

        merge(payload.goals, stat: "Goals", rawKey: "goals", into: &store)
        merge(payload.assists, stat: "Assists", rawKey: "assists", into: &store)
        merge(payload.points, stat: "Points", rawKey: "points", into: &store)
        merge(payload.shots, stat: "Shots", rawKey: "shots", into: &store)
        merge(payload.hits, stat: "Hits", rawKey: "hits", into: &store)
        merge(payload.blockedShots, stat: "Blocks", rawKey: "blockedShots", into: &store)
        merge(payload.plusMinus, stat: "+/-", rawKey: "plusMinus", into: &store)
        merge(payload.penaltyMinutes, stat: "PIM", rawKey: "penaltyMinutes", into: &store)

        let keys = ["Goals", "Assists", "Points", "Shots", "Hits", "Blocks", "+/-", "PIM"]
        return store.values.map { line in
            PlayerStatLine(
                playerID: line.playerID,
                name: line.name,
                teamCode: line.teamCode,
                values: Dictionary(uniqueKeysWithValues: keys.map { ($0, line.values[$0] ?? 0) })
            )
        }
    }

    private static func buildGoalies(_ payload: NHLLeaderPayload?) -> [PlayerStatLine] {
        guard let payload else { return [] }
        var store: [String: MutablePlayerLine] = [:]

        merge(payload.wins, stat: "Wins", rawKey: "wins", into: &store)
        merge(payload.losses, stat: "Losses", rawKey: "losses", into: &store)
        merge(payload.otLosses, stat: "OTL", rawKey: "otLosses", into: &store)
        merge(payload.shutouts, stat: "Shutouts", rawKey: "shutouts", into: &store)
        merge(payload.savePct, stat: "Save %", rawKey: "savePct", into: &store, normalizePercent: true)
        merge(payload.savePctg, stat: "Save %", rawKey: "savePctg", into: &store, normalizePercent: true)
        merge(payload.saves, stat: "Saves", rawKey: "saves", into: &store)
        merge(payload.gamesStarted, stat: "Games Started", rawKey: "gamesStarted", into: &store)
        merge(payload.starts, stat: "Games Started", rawKey: "starts", into: &store)
        merge(payload.gamesPlayed, stat: "Games Started", rawKey: "gamesPlayed", into: &store)
        merge(payload.goalsAgainstAverage, stat: "GAA", rawKey: "goalsAgainstAverage", into: &store)
        merge(payload.gaa, stat: "GAA", rawKey: "gaa", into: &store)

        let keys = ["Wins", "Losses", "OTL", "Shutouts", "Save %", "Saves", "Games Started", "Saves / GS", "GAA"]
        return store.values.map { line in
            var values = Dictionary(uniqueKeysWithValues: keys.map { ($0, line.values[$0] ?? 0) })
            let starts = values["Games Started"] ?? 0
            let saves = values["Saves"] ?? 0
            values["Saves / GS"] = starts > 0 ? saves / starts : 0
            return PlayerStatLine(
                playerID: line.playerID,
                name: line.name,
                teamCode: line.teamCode,
                values: values
            )
        }
    }

    private static func merge(
        _ rows: [NHLLeaderRow]?,
        stat: String,
        rawKey: String,
        into store: inout [String: MutablePlayerLine],
        normalizePercent: Bool = false
    ) {
        guard let rows else { return }
        for row in rows {
            let name = row.playerName
            guard !name.isEmpty else { continue }
            var line = store[name] ?? MutablePlayerLine(
                playerID: row.playerID,
                name: name,
                teamCode: row.teamCode,
                values: [:]
            )
            if line.playerID == 0, row.playerID > 0 {
                line.playerID = row.playerID
            }
            if line.teamCode.isEmpty, !row.teamCode.isEmpty {
                line.teamCode = row.teamCode
            }
            var value = row.numericValue(for: rawKey)
            if normalizePercent && value > 1 {
                value /= 100
            }
            line.values[stat] = value
            store[name] = line
        }
    }
}

private nonisolated struct MutablePlayerLine: Sendable {
    var playerID: Int
    var name: String
    var teamCode: String
    var values: [String: Double]
}

private nonisolated struct NHLLeaderPayload: Decodable, Sendable {
    let goals: [NHLLeaderRow]?
    let assists: [NHLLeaderRow]?
    let points: [NHLLeaderRow]?
    let shots: [NHLLeaderRow]?
    let hits: [NHLLeaderRow]?
    let blockedShots: [NHLLeaderRow]?
    let plusMinus: [NHLLeaderRow]?
    let penaltyMinutes: [NHLLeaderRow]?
    let wins: [NHLLeaderRow]?
    let losses: [NHLLeaderRow]?
    let otLosses: [NHLLeaderRow]?
    let shutouts: [NHLLeaderRow]?
    let savePct: [NHLLeaderRow]?
    let savePctg: [NHLLeaderRow]?
    let saves: [NHLLeaderRow]?
    let gamesStarted: [NHLLeaderRow]?
    let starts: [NHLLeaderRow]?
    let gamesPlayed: [NHLLeaderRow]?
    let goalsAgainstAverage: [NHLLeaderRow]?
    let gaa: [NHLLeaderRow]?
}

private nonisolated struct NHLLeaderRow: Decodable, Sendable {
    let playerId: Int?
    let id: Int?
    let firstName: FlexibleText?
    let lastName: FlexibleText?
    let fullName: FlexibleText?
    let name: FlexibleText?
    let playerNameValue: FlexibleText?
    let teamAbbrev: FlexibleTeamCode?
    let teamCodeField: FlexibleTeamCode?
    let team: FlexibleTeamCode?
    let value: Double?
    let statValue: Double?
    let leaderValue: Double?
    let total: Double?
    let goals: Double?
    let assists: Double?
    let points: Double?
    let shots: Double?
    let hits: Double?
    let blockedShots: Double?
    let plusMinus: Double?
    let penaltyMinutes: Double?
    let wins: Double?
    let losses: Double?
    let otLosses: Double?
    let shutouts: Double?
    let savePct: Double?
    let savePctg: Double?
    let saves: Double?
    let gamesStarted: Double?
    let starts: Double?
    let gamesPlayed: Double?
    let goalsAgainstAverage: Double?
    let gaa: Double?

    enum CodingKeys: String, CodingKey {
        case playerId
        case id
        case firstName
        case lastName
        case fullName
        case name
        case playerNameValue = "playerName"
        case teamAbbrev
        case teamCodeField = "teamCode"
        case team
        case value
        case statValue
        case leaderValue
        case total
        case goals
        case assists
        case points
        case shots
        case hits
        case blockedShots
        case plusMinus
        case penaltyMinutes
        case wins
        case losses
        case otLosses
        case shutouts
        case savePct
        case savePctg
        case saves
        case gamesStarted
        case starts
        case gamesPlayed
        case goalsAgainstAverage
        case gaa
    }

    var playerID: Int { playerId ?? id ?? 0 }

    var playerName: String {
        let combined = [firstName?.value, lastName?.value]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !combined.isEmpty { return combined }
        return fullName?.value
            ?? name?.value
            ?? playerNameValue?.value
            ?? ""
    }

    var teamCodeValue: String {
        teamAbbrev?.value ?? teamCodeField?.value ?? team?.value ?? ""
    }

    var teamCode: String { teamCodeValue.uppercased() }

    func numericValue(for key: String) -> Double {
        let direct: Double?
        switch key {
        case "goals": direct = goals
        case "assists": direct = assists
        case "points": direct = points
        case "shots": direct = shots
        case "hits": direct = hits
        case "blockedShots": direct = blockedShots
        case "plusMinus": direct = plusMinus
        case "penaltyMinutes": direct = penaltyMinutes
        case "wins": direct = wins
        case "losses": direct = losses
        case "otLosses": direct = otLosses
        case "shutouts": direct = shutouts
        case "savePct": direct = savePct
        case "savePctg": direct = savePctg
        case "saves": direct = saves
        case "gamesStarted": direct = gamesStarted
        case "starts": direct = starts
        case "gamesPlayed": direct = gamesPlayed
        case "goalsAgainstAverage": direct = goalsAgainstAverage
        case "gaa": direct = gaa
        default: direct = nil
        }
        return direct ?? value ?? statValue ?? leaderValue ?? total ?? 0
    }
}

private nonisolated struct FlexibleText: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let values = try? container.decode([String: String].self) {
            value = values["default"]
                ?? values["name"]
                ?? values.values.first
                ?? ""
            return
        }
        value = ""
    }
}

private nonisolated struct FlexibleTeamCode: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let values = try? container.decode([String].self) {
            value = values.first ?? ""
            return
        }
        value = ""
    }
}
