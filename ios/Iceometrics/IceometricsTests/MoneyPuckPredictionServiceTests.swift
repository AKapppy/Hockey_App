import Foundation
import Testing
@testable import Iceometrics

struct MoneyPuckPredictionServiceTests {
    @Test
    func parsesPredictionForScheduledMatchup() {
        let game = HockeyGame(
            id: "2026010042",
            startTime: Date(),
            status: .scheduled,
            awayTeam: Team(
                id: "nyr",
                abbreviation: "NYR",
                name: "Rangers",
                logoURL: nil
            ),
            homeTeam: Team(
                id: "bos",
                abbreviation: "BOS",
                name: "Bruins",
                logoURL: nil
            ),
            awayScore: nil,
            homeScore: nil,
            venue: nil
        )

        let html = """
        <table>
          <tr>
            <td>46.0%</td>
            <td>NEW YORK RANGERS</td>
            <td>08:00 PM ET</td>
            <td>BOSTON BRUINS</td>
            <td>54.0%</td>
          </tr>
        </table>
        """

        let result = MoneyPuckPredictionService.parsePredictions(
            html: html,
            games: [game]
        )

        #expect(result[game.id]?.awayWinProbability == 0.46)
        #expect(result[game.id]?.homeWinProbability == 0.54)
    }
}
