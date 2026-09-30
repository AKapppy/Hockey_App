import Foundation

nonisolated struct SharedWebHockeyDataService: HockeyDataService {
    private let client: APIClient
    private let baseURL: URL
    private let season: String

    init(
        client: APIClient = APIClient(),
        baseURL: URL,
        season: String
    ) {
        self.client = client
        self.baseURL = baseURL
        self.season = season
    }

    func fetchSnapshot() async throws -> AppSnapshot {
        var request = APIRequest(
            path: "seasons/\(season)/data.json"
        )
        request.queryItems = [
            URLQueryItem(
                name: "_refresh",
                value: UUID().uuidString
            )
        ]

        let payload = try await client.send(
            request,
            baseURL: baseURL,
            as: SharedWebExport.self
        )

        return SharedWebSnapshotAdapter.makeSnapshot(
            from: payload,
            baseURL: baseURL
        )
    }
}

nonisolated struct SharedWebExport: Decodable, Sendable {
    let metadata: SharedWebMetadata
    let desktop: SharedWebDesktop
}

nonisolated struct SharedWebMetadata: Decodable, Sendable {
    let season: String
    let generatedAt: Date
    let source: String
}

nonisolated struct SharedWebDesktop: Decodable, Sendable {
    let scoreboard: SharedWebScoreboard
}

nonisolated struct SharedWebScoreboard: Decodable, Sendable {
    let days: [String: [SharedWebGame]]
}

nonisolated struct SharedWebGameID: Decodable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = String(value)
        } else {
            self.value = ""
        }
    }
}

nonisolated struct SharedWebGame: Decodable, Sendable {
    let id: SharedWebGameID
    let league: String
    let gameTypeId: Int?
    let state: String
    let status: String
    let startUtc: String
    let clock: SharedWebClock?
    let periodDescriptor: SharedWebPeriodDescriptor?
    let venue: SharedWebVenue?
    let away: SharedWebTeam
    let home: SharedWebTeam
}

nonisolated struct SharedWebClock: Decodable, Sendable {
    let timeRemaining: String?
    let inIntermission: Bool?
}

nonisolated struct SharedWebPeriodDescriptor: Decodable, Sendable {
    let number: Int?
    let periodType: String?
}

nonisolated struct SharedWebTeam: Decodable, Sendable {
    let code: String
    let name: String
    let score: Int?
    let shots: Int?
}

nonisolated struct SharedWebVenue: Decodable, Sendable {
    let name: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            name = nil
            return
        }

        if let value = try? container.decode(String.self) {
            name = value.isEmpty ? nil : value
            return
        }

        if let value = try? container.decode([String: String].self) {
            let candidate = value["default"] ?? value["name"]
            name = candidate?.isEmpty == false ? candidate : nil
            return
        }

        name = nil
    }
}

nonisolated enum SharedWebSnapshotAdapter {
    static func makeSnapshot(
        from payload: SharedWebExport,
        baseURL: URL
    ) -> AppSnapshot {
        let games = payload.desktop.scoreboard.days
            .sorted { $0.key < $1.key }
            .flatMap(\.value)
            .filter { $0.league.uppercased() == "NHL" }
            .compactMap { makeGame(from: $0, baseURL: baseURL) }
            .sorted { $0.startTime < $1.startTime }

        return AppSnapshot(
            generatedAt: payload.metadata.generatedAt,
            source: "Shared \(payload.metadata.season) snapshot • \(payload.metadata.source)",
            games: games,
            standings: []
        )
    }

    private static func makeGame(
        from game: SharedWebGame,
        baseURL: URL
    ) -> HockeyGame? {
        guard let startTime = parseDate(game.startUtc) else {
            return nil
        }

        let awayCode = game.away.code.uppercased()
        let homeCode = game.home.code.uppercased()

        guard !awayCode.isEmpty, !homeCode.isEmpty else {
            return nil
        }

        let id = game.id.value.isEmpty
            ? "\(awayCode)-\(homeCode)-\(game.startUtc)"
            : game.id.value

        return HockeyGame(
            id: id,
            startTime: startTime,
            status: status(for: game),
            awayTeam: makeTeam(
                code: awayCode,
                name: game.away.name,
                baseURL: baseURL
            ),
            homeTeam: makeTeam(
                code: homeCode,
                name: game.home.name,
                baseURL: baseURL
            ),
            awayScore: game.away.score,
            homeScore: game.home.score,
            venue: game.venue?.name,
            gameTypeId: game.gameTypeId,
            awayShots: game.away.shots,
            homeShots: game.home.shots,
            periodNumber: game.periodDescriptor?.number,
            periodType: game.periodDescriptor?.periodType,
            timeRemaining: game.clock?.timeRemaining,
            isIntermission: game.clock?.inIntermission
        )
    }

    private static func makeTeam(
        code: String,
        name: String,
        baseURL: URL
    ) -> Team {
        let logoURL = baseURL
            .appendingPathComponent("assets")
            .appendingPathComponent("nhl_logos")
            .appendingPathComponent("\(code).png")

        return Team(
            id: code.lowercased(),
            abbreviation: code,
            name: name.isEmpty ? code : name,
            logoURL: logoURL
        )
    }

    private static func status(for game: SharedWebGame) -> GameStatus {
        switch game.state.uppercased() {
        case "FUT", "PRE":
            return .scheduled
        case "LIVE", "CRIT":
            return .live
        case "FINAL", "OFF":
            return .final
        case "POSTPONED", "PPD":
            return .postponed
        default:
            let status = game.status.lowercased()
            if status.contains("postpon") {
                return .postponed
            }
            if status.contains("final") {
                return .final
            }
            return .unknown
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter.date(from: value)
    }
}
