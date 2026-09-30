import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated struct MoneyPuckGamePrediction: Sendable, Equatable {
    let awayWinProbability: Double
    let homeWinProbability: Double
}

nonisolated struct MoneyPuckPredictionService: Sendable {
    private static let predictionsURL = URL(
        string: "https://moneypuck.com/moneypuck/predictions/"
    )!

    func fetchPredictions(
        for date: Date,
        games: [HockeyGame]
    ) async throws -> [String: MoneyPuckGamePrediction] {
        guard !games.isEmpty else { return [:] }

        for url in Self.predictionURLs(for: date) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    + "AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("text/html,*/*", forHTTPHeaderField: "Accept")
            request.setValue(
                "https://moneypuck.com/",
                forHTTPHeaderField: "Referer"
            )

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      200..<300 ~= http.statusCode,
                      let html = String(data: data, encoding: .utf8),
                      !html.isEmpty else {
                    continue
                }

                let predictions = Self.parsePredictions(
                    html: html,
                    games: games
                )
                if !predictions.isEmpty {
                    return predictions
                }
            } catch {
                continue
            }
        }

        return [:]
    }

    static func parsePredictions(
        html: String,
        games: [HockeyGame]
    ) -> [String: MoneyPuckGamePrediction] {
        let rows = regexMatches(
            pattern: #"(?is)<tr[^>]*>.*?</tr>"#,
            in: html
        )

        let candidateRows = rows.isEmpty ? [html] : rows
        var output: [String: MoneyPuckGamePrediction] = [:]

        for game in games {
            guard let row = candidateRows.first(where: {
                rowContainsGame($0, game: game)
            }),
            let prediction = prediction(
                from: row,
                game: game
            ) else {
                continue
            }

            output[game.id] = prediction
        }

        return output
    }

    private static func prediction(
        from htmlRow: String,
        game: HockeyGame
    ) -> MoneyPuckGamePrediction? {
        let plain = normalized(stripHTML(htmlRow))
        let percentRegex = try? NSRegularExpression(
            pattern: #"(\d{1,3}(?:\.\d+)?)\s*%"#
        )
        let fullRange = NSRange(plain.startIndex..., in: plain)
        let matches = percentRegex?.matches(
            in: plain,
            range: fullRange
        ) ?? []

        var percentages: [(position: Int, value: Double)] = []
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let valueRange = Range(match.range(at: 1), in: plain),
                  let value = Double(plain[valueRange]),
                  0...100 ~= value else {
                continue
            }

            percentages.append(
                (position: match.range.location, value: value / 100.0)
            )
        }

        guard percentages.count >= 2,
              let awayPosition = teamPosition(
                game.awayTeam,
                in: plain
              ),
              let homePosition = teamPosition(
                game.homeTeam,
                in: plain
              ) else {
            return nil
        }

        var available = percentages
        guard let away = popNearest(
            to: awayPosition,
            from: &available
        ),
        let home = popNearest(
            to: homePosition,
            from: &available
        ) else {
            return nil
        }

        return MoneyPuckGamePrediction(
            awayWinProbability: away,
            homeWinProbability: home
        )
    }

    private static func rowContainsGame(
        _ htmlRow: String,
        game: HockeyGame
    ) -> Bool {
        let plain = normalized(stripHTML(htmlRow))
        return teamPosition(game.awayTeam, in: plain) != nil
            && teamPosition(game.homeTeam, in: plain) != nil
    }

    private static func teamPosition(
        _ team: Team,
        in normalizedRow: String
    ) -> Int? {
        for alias in aliases(for: team) {
            let needle = normalized(alias)
            guard !needle.isEmpty,
                  let range = normalizedRow.range(of: needle) else {
                continue
            }

            return normalizedRow.distance(
                from: normalizedRow.startIndex,
                to: range.lowerBound
            )
        }

        return nil
    }

    private static func popNearest(
        to position: Int,
        from values: inout [(position: Int, value: Double)]
    ) -> Double? {
        guard let index = values.indices.min(by: {
            abs(values[$0].position - position)
                < abs(values[$1].position - position)
        }) else {
            return nil
        }

        return values.remove(at: index).value
    }

    private static func aliases(for team: Team) -> [String] {
        var values = [team.name, team.abbreviation]
        if let fullName = fullTeamNames[team.abbreviation.uppercased()] {
            values.append(fullName)
        }
        return values
            .map { normalized($0) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    private static func stripHTML(_ value: String) -> String {
        var text = value
        text = replacing(
            pattern: #"(?is)<(script|style).*?>.*?</\1>"#,
            in: text,
            with: " "
        )
        text = replacing(
            pattern: #"(?is)<br\s*/?>"#,
            in: text,
            with: " "
        )
        text = replacing(
            pattern: #"(?is)<[^>]+>"#,
            in: text,
            with: " "
        )

        return text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func normalized(_ value: String) -> String {
        let upper = value.uppercased()
        let scalars = upper.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "%"
                || scalar == "." {
                return Character(String(scalar))
            }
            return " "
        }

        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func regexMatches(
        pattern: String,
        in value: String
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap {
            guard let matchRange = Range($0.range, in: value) else {
                return nil
            }
            return String(value[matchRange])
        }
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: replacement
        )
    }

    private static func predictionURLs(for date: Date) -> [URL] {
        let iso = dateString(for: date, format: "yyyy-MM-dd")
        let compact = dateString(for: date, format: "yyyyMMdd")
        let values = [iso, compact]

        var urls: [URL] = values.compactMap { value in
            guard var components = URLComponents(
                url: predictionsURL,
                resolvingAgainstBaseURL: false
            ) else {
                return nil
            }

            components.queryItems = [
                URLQueryItem(name: "date", value: value)
            ]
            return components.url
        }
        urls.append(predictionsURL)
        return urls
    }

    private static func dateString(
        for date: Date,
        format: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static let fullTeamNames: [String: String] = [
        "ANA": "Anaheim Ducks",
        "BOS": "Boston Bruins",
        "BUF": "Buffalo Sabres",
        "CAR": "Carolina Hurricanes",
        "CBJ": "Columbus Blue Jackets",
        "CGY": "Calgary Flames",
        "CHI": "Chicago Blackhawks",
        "COL": "Colorado Avalanche",
        "DAL": "Dallas Stars",
        "DET": "Detroit Red Wings",
        "EDM": "Edmonton Oilers",
        "FLA": "Florida Panthers",
        "LAK": "Los Angeles Kings",
        "MIN": "Minnesota Wild",
        "MTL": "Montreal Canadiens",
        "NJD": "New Jersey Devils",
        "NSH": "Nashville Predators",
        "NYI": "New York Islanders",
        "NYR": "New York Rangers",
        "OTT": "Ottawa Senators",
        "PHI": "Philadelphia Flyers",
        "PIT": "Pittsburgh Penguins",
        "SEA": "Seattle Kraken",
        "SJS": "San Jose Sharks",
        "STL": "St. Louis Blues",
        "TBL": "Tampa Bay Lightning",
        "TOR": "Toronto Maple Leafs",
        "UTA": "Utah Mammoth",
        "VAN": "Vancouver Canucks",
        "VGK": "Vegas Golden Knights",
        "WPG": "Winnipeg Jets",
        "WSH": "Washington Capitals"
    ]
}
