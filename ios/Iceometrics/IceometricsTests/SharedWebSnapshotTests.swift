import Foundation
import Testing
@testable import Iceometrics

struct SharedWebSnapshotTests {
    @Test
    func mapsPublishedScoreboardIntoAppSnapshot() throws {
        let json = """
        {
          "metadata": {
            "season": "2026-2027",
            "generatedAt": "2026-09-29T12:00:00Z",
            "source": "NHL / PWHL / ESPN; optional MoneyPuck predictions"
          },
          "desktop": {
            "scoreboard": {
              "days": {
                "2026-09-29": [
                  {
                    "id": 2026010042,
                    "league": "NHL",
                    "state": "FUT",
                    "status": "",
                    "startUtc": "2026-09-29T23:00:00Z",
                    "venue": {"default": "Madison Square Garden"},
                    "away": {
                      "code": "NJD",
                      "name": "New Jersey Devils",
                      "score": null
                    },
                    "home": {
                      "code": "NYR",
                      "name": "New York Rangers",
                      "score": null
                    }
                  }
                ]
              }
            }
          }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let payload = try IceometicsJSON.decoder.decode(
            SharedWebExport.self,
            from: data
        )

        let snapshot = SharedWebSnapshotAdapter.makeSnapshot(
            from: payload,
            baseURL: URL(string: "https://example.com/")!
        )

        let game = try #require(snapshot.games.first)
        #expect(snapshot.games.count == 1)
        #expect(game.id == "2026010042")
        #expect(game.status == .scheduled)
        #expect(game.awayTeam.abbreviation == "NJD")
        #expect(game.homeTeam.abbreviation == "NYR")
        #expect(game.venue == "Madison Square Garden")
        #expect(game.homeTeam.logoURL?.lastPathComponent == "NYR.png")
    }
    @Test
    func preservesLiveClockAndIntermissionState() throws {
        let json = """
        {
          "metadata": {
            "season": "2026-2027",
            "generatedAt": "2026-09-29T12:00:00Z",
            "source": "NHL"
          },
          "desktop": {
            "scoreboard": {
              "days": {
                "2026-09-29": [
                  {
                    "id": 2026010043,
                    "league": "NHL",
                    "state": "LIVE",
                    "status": "",
                    "startUtc": "2026-09-29T23:00:00Z",
                    "clock": {
                      "timeRemaining": "08:42",
                      "inIntermission": true
                    },
                    "periodDescriptor": {
                      "number": 2,
                      "periodType": "REG"
                    },
                    "venue": {"default": "Madison Square Garden"},
                    "away": {
                      "code": "NJD",
                      "name": "New Jersey Devils",
                      "score": 1
                    },
                    "home": {
                      "code": "NYR",
                      "name": "New York Rangers",
                      "score": 2
                    }
                  }
                ]
              }
            }
          }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let payload = try IceometicsJSON.decoder.decode(
            SharedWebExport.self,
            from: data
        )
        let snapshot = SharedWebSnapshotAdapter.makeSnapshot(
            from: payload,
            baseURL: URL(string: "https://example.com/")!
        )

        let game = try #require(snapshot.games.first)
        #expect(game.status == .live)
        #expect(game.periodNumber == 2)
        #expect(game.periodType == "REG")
        #expect(game.timeRemaining == "08:42")
        #expect(game.isIntermission == true)
    }

}
