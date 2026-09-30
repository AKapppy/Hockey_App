import Foundation
import Testing
@testable import Iceometrics

struct NHLGameDetailServiceTests {
    @Test
    func buildsStatTableFromPlayByPlay() throws {
        let game = HockeyGame(
            id: "2026010001",
            startTime: Date(),
            status: .final,
            awayTeam: Team(
                id: "dal",
                abbreviation: "DAL",
                name: "Stars",
                logoURL: nil
            ),
            homeTeam: Team(
                id: "stl",
                abbreviation: "STL",
                name: "Blues",
                logoURL: nil
            ),
            awayScore: 2,
            homeScore: 1,
            venue: nil
        )

        let json = """
        {
          "awayTeam": {"id": 1},
          "homeTeam": {"id": 2},
          "plays": [
            {
              "typeDescKey": "shot-on-goal",
              "periodDescriptor": {"number": 1},
              "details": {"eventOwnerTeamId": 1}
            },
            {
              "typeDescKey": "goal",
              "periodDescriptor": {"number": 1},
              "details": {"eventOwnerTeamId": 2}
            },
            {
              "typeDescKey": "faceoff",
              "periodDescriptor": {"number": 1},
              "details": {"eventOwnerTeamId": 1}
            },
            {
              "typeDescKey": "penalty",
              "periodDescriptor": {"number": 1},
              "details": {"eventOwnerTeamId": 1, "duration": 2}
            }
          ]
        }
        """

        let detail = try NHLGameDetailService.parse(
            data: Data(json.utf8),
            game: game
        )

        #expect(detail.shotsByPeriod.first?.away == 1)
        #expect(detail.shotsByPeriod.first?.home == 1)
        #expect(
            detail.stats.first(where: { $0.label == "Penalty Minutes" })?
                .awayValue == "2"
        )
    }
}
