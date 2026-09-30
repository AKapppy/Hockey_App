import Foundation

nonisolated struct NHLLiveScoreService: Sendable {
    private let baseURL = URL(string: "https://api-web.nhle.com/")!

    func fetchScores(for date: Date) async throws -> NHLLiveScoreResponse {
        let dateKey = Self.dateKey(for: date)
        let url = baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("score")
            .appendingPathComponent(dateKey)

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw IceometicsError.invalidResponse
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                throw IceometicsError.httpStatus(httpResponse.statusCode)
            }

            do {
                return try JSONDecoder().decode(
                    NHLLiveScoreResponse.self,
                    from: data
                )
            } catch {
                throw IceometicsError.decoding(error.localizedDescription)
            }
        } catch let error as IceometicsError {
            throw error
        } catch {
            throw IceometicsError.network(error.localizedDescription)
        }
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

nonisolated struct NHLLiveScoreResponse: Decodable, Sendable {
    let games: [NHLLiveGame]
}

nonisolated struct NHLLiveGame: Decodable, Sendable {
    let id: Int
    let gameState: String
    let period: Int?
    let periodDescriptor: NHLLivePeriodDescriptor?
    let clock: NHLLiveClock?
    let awayTeam: NHLLiveTeam
    let homeTeam: NHLLiveTeam

    var status: GameStatus {
        switch gameState.uppercased() {
        case "FUT", "PRE":
            return .scheduled
        case "LIVE", "CRIT":
            return .live
        case "FINAL", "OFF":
            return .final
        case "POSTPONED", "PPD":
            return .postponed
        default:
            return .unknown
        }
    }
}

nonisolated struct NHLLiveTeam: Decodable, Sendable {
    let abbrev: String?
    let score: Int?
    let sog: Int?
}

nonisolated struct NHLLiveClock: Decodable, Sendable {
    let timeRemaining: String?
    let inIntermission: Bool?
}

nonisolated struct NHLLivePeriodDescriptor: Decodable, Sendable {
    let number: Int?
    let periodType: String?
}

nonisolated enum NHLLiveScoreOverlayAdapter {
    static func applying(
        _ liveGame: NHLLiveGame,
        to game: HockeyGame
    ) -> HockeyGame {
        do {
            let encoded = try IceometicsJSON.encoder.encode(game)
            guard var object = try JSONSerialization.jsonObject(
                with: encoded
            ) as? [String: Any] else {
                return game
            }

            object["status"] = liveGame.status.rawValue

            if let awayScore = liveGame.awayTeam.score {
                object["awayScore"] = awayScore
            }
            if let homeScore = liveGame.homeTeam.score {
                object["homeScore"] = homeScore
            }

            // Keep both names here intentionally. The current scorecard model
            // uses awayShots/homeShots; alternate names are harmless if an older
            // HockeyGame shape is being decoded because JSONDecoder ignores them.
            if let awayShots = liveGame.awayTeam.sog {
                object["awayShots"] = awayShots
                object["awayShotsOnGoal"] = awayShots
            }
            if let homeShots = liveGame.homeTeam.sog {
                object["homeShots"] = homeShots
                object["homeShotsOnGoal"] = homeShots
            }

            if let period = liveGame.periodDescriptor?.number ?? liveGame.period {
                object["periodNumber"] = period
            }
            if let periodType = liveGame.periodDescriptor?.periodType,
               !periodType.isEmpty {
                object["periodType"] = periodType
            }
            if let timeRemaining = liveGame.clock?.timeRemaining {
                object["timeRemaining"] = timeRemaining
            }
            if let inIntermission = liveGame.clock?.inIntermission {
                object["isIntermission"] = inIntermission
            }

            let updated = try JSONSerialization.data(withJSONObject: object)
            return try IceometicsJSON.decoder.decode(
                HockeyGame.self,
                from: updated
            )
        } catch {
            return game
        }
    }
}
