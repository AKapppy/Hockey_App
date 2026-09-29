import Foundation
import Testing
@testable import Iceometrics

struct FixtureDecodingTests {
    @Test
    func appSnapshotDecodes() throws {
        let json = """
        {
          "generatedAt": "2026-09-27T13:30:00Z",
          "source": "Unit test",
          "games": [
            {
              "id": "game-1",
              "startTime": "2026-09-27T17:00:00Z",
              "status": "scheduled",
              "awayTeam": {
                "id": "away",
                "abbreviation": "AWY",
                "name": "Away",
                "logoURL": null
              },
              "homeTeam": {
                "id": "home",
                "abbreviation": "HME",
                "name": "Home",
                "logoURL": null
              },
              "awayScore": null,
              "homeScore": null,
              "venue": "Test Arena"
            }
          ],
          "standings": []
        }
        """

        let data = try #require(json.data(using: .utf8))
        let snapshot = try IceometicsJSON.decoder.decode(
            AppSnapshot.self,
            from: data
        )

        #expect(snapshot.games.count == 1)
        #expect(
            snapshot.games[0].awayTeam.abbreviation == "AWY"
        )
        #expect(snapshot.games[0].status == .scheduled)
    }

    @Test
    func unknownGameStatusDoesNotBreakDecoding() throws {
        let json = #""mystery-status""#
        let data = try #require(json.data(using: .utf8))

        let status = try IceometicsJSON.decoder.decode(
            GameStatus.self,
            from: data
        )

        #expect(status == .unknown)
    }
}
