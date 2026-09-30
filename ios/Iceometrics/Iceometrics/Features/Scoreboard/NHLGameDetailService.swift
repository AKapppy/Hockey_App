import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated struct NHLPeriodShots: Identifiable, Sendable, Equatable {
    let period: Int
    let label: String
    let away: Int
    let home: Int

    var id: Int { period }
}

nonisolated struct NHLGameStatLine: Identifiable, Sendable, Equatable {
    let label: String
    let awayValue: String
    let homeValue: String

    var id: String { label }
}

nonisolated struct NHLGameDetail: Sendable, Equatable {
    let shotsByPeriod: [NHLPeriodShots]
    let stats: [NHLGameStatLine]
}

nonisolated enum NHLGameDetailError: LocalizedError, Sendable {
    case invalidGameID
    case invalidResponse
    case httpStatus(Int)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidGameID:
            "Game details are not available for this game."
        case .invalidResponse:
            "The NHL returned an invalid game-detail response."
        case .httpStatus(let code):
            "The NHL returned HTTP \(code) for this game."
        case .invalidData:
            "Iceometrics could not read the game statistics."
        }
    }
}

nonisolated struct NHLGameDetailService: Sendable {
    func fetchDetail(for game: HockeyGame) async throws -> NHLGameDetail {
        guard Int(game.id) != nil,
              let url = URL(
                string: "https://api-web.nhle.com/v1/gamecenter/\(game.id)/play-by-play"
              ) else {
            throw NHLGameDetailError.invalidGameID
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NHLGameDetailError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw NHLGameDetailError.httpStatus(http.statusCode)
        }

        return try Self.parse(data: data, game: game)
    }

    static func parse(
        data: Data,
        game: HockeyGame
    ) throws -> NHLGameDetail {
        guard let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw NHLGameDetailError.invalidData
        }

        let awayTeam = root["awayTeam"] as? [String: Any] ?? [:]
        let homeTeam = root["homeTeam"] as? [String: Any] ?? [:]
        let awayID = integer(awayTeam["id"])
        let homeID = integer(homeTeam["id"])
        let plays = root["plays"] as? [[String: Any]] ?? []

        var shotsByPeriod: [Int: (away: Int, home: Int)] = [:]
        var awayStats = TeamEventStats()
        var homeStats = TeamEventStats()

        for play in plays {
            let type = string(play["typeDescKey"]).lowercased()
            guard !type.isEmpty else { continue }

            let details = play["details"] as? [String: Any] ?? [:]
            let descriptor = play["periodDescriptor"] as? [String: Any] ?? [:]
            let period = integer(descriptor["number"])
            let ownerID = integer(details["eventOwnerTeamId"])

            let side: TeamSide?
            if ownerID > 0, ownerID == awayID {
                side = .away
            } else if ownerID > 0, ownerID == homeID {
                side = .home
            } else {
                side = nil
            }

            if period > 0,
               (type == "shot-on-goal" || type == "goal"),
               let side {
                var bucket = shotsByPeriod[period] ?? (away: 0, home: 0)
                switch side {
                case .away:
                    bucket.away += 1
                case .home:
                    bucket.home += 1
                }
                shotsByPeriod[period] = bucket
            }

            guard let side else { continue }
            switch side {
            case .away:
                awayStats.apply(type: type, details: details)
            case .home:
                homeStats.apply(type: type, details: details)
            }
        }

        let periods = shotsByPeriod.keys.sorted().map { period in
            let bucket = shotsByPeriod[period] ?? (away: 0, home: 0)
            return NHLPeriodShots(
                period: period,
                label: periodLabel(period),
                away: bucket.away,
                home: bucket.home
            )
        }

        let awayShots = periods.reduce(0) { $0 + $1.away }
        let homeShots = periods.reduce(0) { $0 + $1.home }
        let faceoffTotal = awayStats.faceoffWins + homeStats.faceoffWins

        let awayFaceoff = faceoffTotal > 0
            ? percent(Double(awayStats.faceoffWins) / Double(faceoffTotal))
            : "—"
        let homeFaceoff = faceoffTotal > 0
            ? percent(Double(homeStats.faceoffWins) / Double(faceoffTotal))
            : "—"

        let stats = [
            NHLGameStatLine(
                label: "Shots On Goal",
                awayValue: String(awayShots),
                homeValue: String(homeShots)
            ),
            NHLGameStatLine(
                label: "Face-off %",
                awayValue: awayFaceoff,
                homeValue: homeFaceoff
            ),
            NHLGameStatLine(
                label: "Penalty Minutes",
                awayValue: String(awayStats.penaltyMinutes),
                homeValue: String(homeStats.penaltyMinutes)
            ),
            NHLGameStatLine(
                label: "Hits",
                awayValue: String(awayStats.hits),
                homeValue: String(homeStats.hits)
            ),
            NHLGameStatLine(
                label: "Blocked Shots",
                awayValue: String(awayStats.blockedShots),
                homeValue: String(homeStats.blockedShots)
            ),
            NHLGameStatLine(
                label: "Giveaways",
                awayValue: String(awayStats.giveaways),
                homeValue: String(homeStats.giveaways)
            ),
            NHLGameStatLine(
                label: "Takeaways",
                awayValue: String(awayStats.takeaways),
                homeValue: String(homeStats.takeaways)
            )
        ]

        return NHLGameDetail(
            shotsByPeriod: periods,
            stats: stats
        )
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        return ""
    }

    private static func periodLabel(_ period: Int) -> String {
        switch period {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        case 4: "OT"
        default: "P\(period)"
        }
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(
            .percent.precision(.fractionLength(1))
        )
    }
}

private nonisolated enum TeamSide: Sendable {
    case away
    case home
}

private nonisolated struct TeamEventStats: Sendable {
    var faceoffWins = 0
    var hits = 0
    var blockedShots = 0
    var giveaways = 0
    var takeaways = 0
    var penaltyMinutes = 0

    mutating func apply(
        type: String,
        details: [String: Any]
    ) {
        switch type {
        case "faceoff":
            faceoffWins += 1
        case "hit":
            hits += 1
        case "blocked-shot":
            blockedShots += 1
        case "giveaway":
            giveaways += 1
        case "takeaway":
            takeaways += 1
        case "penalty":
            penaltyMinutes += Self.integer(
                details["duration"] ?? details["durationMinutes"]
            )
        default:
            break
        }
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }
}
