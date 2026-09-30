import Foundation

nonisolated enum StatsPhase: String, CaseIterable, Identifiable, Sendable {
    case preseason
    case regular
    case postseason

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preseason: "Preseason"
        case .regular: "Regular Season"
        case .postseason: "Postseason"
        }
    }

    var gameTypeID: Int {
        switch self {
        case .preseason: 1
        case .regular: 2
        case .postseason: 3
        }
    }
}

nonisolated struct StatsTeam: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let logoURL: URL?
    let colorHex: String

    var id: String { code }
}

nonisolated struct StatsGame: Identifiable, Hashable, Sendable {
    let id: String
    let day: String
    let gameTypeID: Int
    let state: String
    let status: String
    let awayCode: String
    let homeCode: String
    let awayScore: Int?
    let homeScore: Int?
    let periodType: String?

    var isFinal: Bool {
        let stateUpper = state.uppercased()
        return stateUpper == "FINAL"
            || stateUpper == "OFF"
            || status.lowercased().contains("final")
    }

    var phase: StatsPhase? {
        StatsPhase.allCases.first { $0.gameTypeID == gameTypeID }
    }

    var wentToExtraTime: Bool {
        let value = (periodType ?? "").uppercased()
        return value == "OT" || value == "SO"
    }

    func result(for teamCode: String) -> String? {
        guard isFinal,
              let awayScore,
              let homeScore,
              awayScore != homeScore else {
            return nil
        }

        let team = teamCode.uppercased()
        guard team == awayCode || team == homeCode else { return nil }

        let teamWon = (team == awayCode && awayScore > homeScore)
            || (team == homeCode && homeScore > awayScore)
        let type = (periodType ?? "").uppercased()

        if teamWon {
            if type == "SO" { return "SOW" }
            if type == "OT" { return "OTW" }
            return "W"
        }

        if type == "SO" { return "SOL" }
        if type == "OT" { return "OTL" }
        return "L"
    }
}

nonisolated struct TeamStatsRow: Identifiable, Hashable, Sendable {
    let teamCode: String
    let record: String
    let gp: Int
    let w: Int
    let l: Int
    let pts: Int
    let gf: Int
    let ga: Int
    let gd: Int
    let pointsPercentage: Double
    let winPercentage: Double

    var id: String { teamCode }
}

nonisolated struct GameStatsTable: Sendable {
    let columns: [String]
    let rows: [String: [String: String]]

    func result(teamCode: String, day: String) -> String? {
        rows[teamCode]?[day]
    }
}

nonisolated struct StatsHistoryTable: Sendable {
    let columns: [String]
    let rows: [String: [Double?]]

    func value(teamCode: String, columnIndex: Int) -> Double? {
        guard let row = rows[teamCode],
              row.indices.contains(columnIndex) else {
            return nil
        }
        return row[columnIndex]
    }

    func latestValue(teamCode: String) -> Double? {
        rows[teamCode]?.reversed().compactMap { $0 }.first
    }
}

nonisolated struct RecentForm: Sendable {
    let title: String
    let lines: [String]
}

nonisolated struct StatsSnapshot: Sendable {
    let generatedAt: Date
    let season: String
    let teams: [StatsTeam]
    let games: [StatsGame]

    var availablePhases: [StatsPhase] {
        let today = Self.hockeyTodayString()
        return StatsPhase.allCases.filter { phase in
            games.contains {
                $0.gameTypeID == phase.gameTypeID && $0.day <= today
            }
        }
    }

    var defaultPhase: StatsPhase {
        if availablePhases.contains(.postseason) { return .postseason }
        if availablePhases.contains(.regular) { return .regular }
        return .preseason
    }

    func teamStats(for phase: StatsPhase) -> [TeamStatsRow] {
        var accumulators = Dictionary(
            uniqueKeysWithValues: teams.map {
                ($0.code, TeamAccumulator())
            }
        )

        let phaseGames = games
            .filter { $0.gameTypeID == phase.gameTypeID && $0.isFinal }
            .sorted { ($0.day, $0.id) < ($1.day, $1.id) }

        for game in phaseGames {
            guard let awayScore = game.awayScore,
                  let homeScore = game.homeScore,
                  awayScore != homeScore,
                  accumulators[game.awayCode] != nil,
                  accumulators[game.homeCode] != nil else {
                continue
            }

            accumulators[game.awayCode]?.gp += 1
            accumulators[game.homeCode]?.gp += 1
            accumulators[game.awayCode]?.gf += awayScore
            accumulators[game.awayCode]?.ga += homeScore
            accumulators[game.homeCode]?.gf += homeScore
            accumulators[game.homeCode]?.ga += awayScore

            let awayWon = awayScore > homeScore
            let winner = awayWon ? game.awayCode : game.homeCode
            let loser = awayWon ? game.homeCode : game.awayCode
            let endType = (game.periodType ?? "").uppercased()

            switch endType {
            case "SO":
                accumulators[winner]?.shootoutWins += 1
                accumulators[loser]?.shootoutLosses += 1
                accumulators[winner]?.pts += 2
                accumulators[loser]?.pts += 1
            case "OT":
                accumulators[winner]?.overtimeWins += 1
                accumulators[loser]?.overtimeLosses += 1
                accumulators[winner]?.pts += 2
                accumulators[loser]?.pts += 1
            default:
                accumulators[winner]?.regulationWins += 1
                accumulators[loser]?.regulationLosses += 1
                accumulators[winner]?.pts += 2
            }
        }

        return teams.map { team in
            let value = accumulators[team.code] ?? TeamAccumulator()
            let wins = value.regulationWins + value.overtimeWins + value.shootoutWins
            let losses = value.regulationLosses + value.overtimeLosses + value.shootoutLosses
            let otShootoutLosses = value.overtimeLosses + value.shootoutLosses
            let pointsPercentage = value.gp > 0
                ? Double(value.pts) / (Double(value.gp) * 2.0)
                : 0
            let winPercentage = value.gp > 0
                ? Double(wins) / Double(value.gp)
                : 0

            return TeamStatsRow(
                teamCode: team.code,
                record: "\(wins)-\(losses)-\(otShootoutLosses)—\(value.pts)",
                gp: value.gp,
                w: wins,
                l: losses,
                pts: value.pts,
                gf: value.gf,
                ga: value.ga,
                gd: value.gf - value.ga,
                pointsPercentage: pointsPercentage,
                winPercentage: winPercentage
            )
        }
    }

    func gameStats(for phase: StatsPhase) -> GameStatsTable? {
        guard let bounds = phaseDayBounds(phase) else { return nil }
        let columns = Self.days(from: bounds.start, through: bounds.end)
        var rows = Dictionary(
            uniqueKeysWithValues: teams.map { ($0.code, [String: String]()) }
        )

        for game in games where game.gameTypeID == phase.gameTypeID && game.isFinal {
            guard columns.contains(game.day) else { continue }
            if let away = game.result(for: game.awayCode) {
                rows[game.awayCode]?[game.day] = away
            }
            if let home = game.result(for: game.homeCode) {
                rows[game.homeCode]?[game.day] = home
            }
        }

        if phase == .postseason {
            rows = rows.filter { _, results in !results.isEmpty }
        }

        return GameStatsTable(columns: columns, rows: rows)
    }

    func pointsHistory() -> StatsHistoryTable? {
        history(for: .regular, kind: .points)
    }

    func goalDifferentialHistory(for phase: StatsPhase) -> StatsHistoryTable? {
        history(for: phase, kind: .goalDifferential)
    }

    func recentForm(teamCode: String) -> RecentForm? {
        let code = teamCode.uppercased()
        let logs = games
            .filter {
                $0.isFinal && ($0.awayCode == code || $0.homeCode == code)
            }
            .sorted { ($0.day, $0.id) < ($1.day, $1.id) }
            .compactMap { game -> FormGame? in
                guard let away = game.awayScore,
                      let home = game.homeScore,
                      away != home else {
                    return nil
                }
                let isHome = game.homeCode == code
                let gf = isHome ? home : away
                let ga = isHome ? away : home
                let won = gf > ga
                let result = won ? "W" : (game.wentToExtraTime ? "OTL" : "L")
                return FormGame(
                    day: game.day,
                    home: isHome,
                    gf: gf,
                    ga: ga,
                    gd: gf - ga,
                    result: result
                )
            }

        guard !logs.isEmpty else { return nil }

        let last5 = Array(logs.suffix(5))
        let last10 = Array(logs.suffix(10))
        let home = logs.filter(\.home)
        let road = logs.filter { !$0.home }
        let r5 = Self.formRecord(last5)
        let r10 = Self.formRecord(last10)
        let rh = Self.formRecord(home)
        let rr = Self.formRecord(road)
        let gf5 = last5.reduce(0) { $0 + $1.gf }
        let ga5 = last5.reduce(0) { $0 + $1.ga }
        let gf10 = last10.reduce(0) { $0 + $1.gf }
        let ga10 = last10.reduce(0) { $0 + $1.ga }
        let trend = last5.map(\.gd)
        let trendText = trend.map { value in
            value == 0 ? "0" : String(format: "%+d", value)
        }.joined(separator: ", ")
        let trendNet = trend.reduce(0, +)

        return RecentForm(
            title: "Recent Form - \(code)",
            lines: [
                "L5: \(r5.w)-\(r5.l)-\(r5.otl) (\(gf5)-\(ga5))",
                "L10: \(r10.w)-\(r10.l)-\(r10.otl) (\(gf10)-\(ga10))",
                "Home: \(rh.w)-\(rh.l)-\(rh.otl) | Away: \(rr.w)-\(rr.l)-\(rr.otl)",
                "GD Trend: \(trendText) (Net \(String(format: "%+d", trendNet)))"
            ]
        )
    }

    func team(for code: String) -> StatsTeam? {
        teams.first { $0.code == code }
    }

    private func history(
        for phase: StatsPhase,
        kind: HistoryKind
    ) -> StatsHistoryTable? {
        guard let bounds = phaseDayBounds(phase) else { return nil }
        let days = Self.days(from: bounds.start, through: bounds.end)
        guard !days.isEmpty else { return nil }

        var totals = Dictionary(uniqueKeysWithValues: teams.map { ($0.code, 0) })
        var rows = Dictionary(uniqueKeysWithValues: teams.map { ($0.code, [Double?]()) })
        let byDay = Dictionary(grouping: games.filter {
            $0.gameTypeID == phase.gameTypeID && $0.isFinal
        }, by: \.day)

        for day in days {
            for game in byDay[day] ?? [] {
                guard let awayScore = game.awayScore,
                      let homeScore = game.homeScore,
                      awayScore != homeScore else {
                    continue
                }

                switch kind {
                case .points:
                    let awayWon = awayScore > homeScore
                    let winner = awayWon ? game.awayCode : game.homeCode
                    let loser = awayWon ? game.homeCode : game.awayCode
                    totals[winner, default: 0] += 2
                    if game.wentToExtraTime {
                        totals[loser, default: 0] += 1
                    }
                case .goalDifferential:
                    totals[game.awayCode, default: 0] += awayScore - homeScore
                    totals[game.homeCode, default: 0] += homeScore - awayScore
                }
            }

            for team in teams {
                rows[team.code, default: []].append(Double(totals[team.code, default: 0]))
            }
        }

        let labels = days.map(Self.shortLabel)
        if phase == .postseason && kind == .goalDifferential {
            rows = rows.filter { _, values in
                values.compactMap { $0 }.contains { abs($0) > 0.000_001 }
            }
        }

        return StatsHistoryTable(columns: labels, rows: rows)
    }

    private func phaseDayBounds(_ phase: StatsPhase) -> (start: String, end: String)? {
        let phaseGames = games.filter { $0.gameTypeID == phase.gameTypeID }
        guard let first = phaseGames.map(\.day).min(),
              let last = phaseGames.map(\.day).max() else {
            return nil
        }

        let today = Self.hockeyTodayString()
        if today < first {
            return (first, first)
        }

        return (first, min(today, last))
    }

    private static func formRecord(_ rows: [FormGame]) -> (w: Int, l: Int, otl: Int) {
        var w = 0
        var l = 0
        var otl = 0
        for row in rows {
            switch row.result {
            case "W": w += 1
            case "OTL": otl += 1
            case "L": l += 1
            default: break
            }
        }
        return (w, l, otl)
    }

    private static func hockeyTodayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func days(from start: String, through end: String) -> [String] {
        guard let startDate = parseDay(start),
              let endDate = parseDay(end),
              startDate <= endDate else {
            return []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        var current = startDate
        var out: [String] = []

        while current <= endDate {
            out.append(dayString(current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }
        return out
    }

    private static func parseDay(_ raw: String) -> Date? {
        let pieces = raw.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar.date(
            from: DateComponents(
                year: pieces[0],
                month: pieces[1],
                day: pieces[2]
            )
        )
    }

    private static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            values.year ?? 0,
            values.month ?? 0,
            values.day ?? 0
        )
    }

    private static func shortLabel(_ day: String) -> String {
        let values = day.split(separator: "-")
        guard values.count == 3,
              let month = Int(values[1]),
              let day = Int(values[2]) else {
            return day
        }
        return "\(month)/\(day)"
    }
}

private nonisolated enum HistoryKind: Sendable {
    case points
    case goalDifferential
}

private nonisolated struct TeamAccumulator: Sendable {
    var gp = 0
    var regulationWins = 0
    var overtimeWins = 0
    var shootoutWins = 0
    var regulationLosses = 0
    var overtimeLosses = 0
    var shootoutLosses = 0
    var pts = 0
    var gf = 0
    var ga = 0
}

private nonisolated struct FormGame: Sendable {
    let day: String
    let home: Bool
    let gf: Int
    let ga: Int
    let gd: Int
    let result: String
}
