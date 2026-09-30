import Foundation

nonisolated struct HockeyGame: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let startTime: Date
    let status: GameStatus
    let awayTeam: Team
    let homeTeam: Team
    let awayScore: Int?
    let homeScore: Int?
    let venue: String?
    let periodNumber: Int?
    let periodType: String?
    let timeRemaining: String?
    let isIntermission: Bool?

    init(
        id: String,
        startTime: Date,
        status: GameStatus,
        awayTeam: Team,
        homeTeam: Team,
        awayScore: Int?,
        homeScore: Int?,
        venue: String?,
        periodNumber: Int? = nil,
        periodType: String? = nil,
        timeRemaining: String? = nil,
        isIntermission: Bool? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.status = status
        self.awayTeam = awayTeam
        self.homeTeam = homeTeam
        self.awayScore = awayScore
        self.homeScore = homeScore
        self.venue = venue
        self.periodNumber = periodNumber
        self.periodType = periodType
        self.timeRemaining = timeRemaining
        self.isIntermission = isIntermission
    }
}
