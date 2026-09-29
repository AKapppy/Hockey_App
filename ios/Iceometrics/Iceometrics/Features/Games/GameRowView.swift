import SwiftUI

struct GameRowView: View {
    let game: HockeyGame

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(game.awayTeam.abbreviation)
                    .font(.headline)

                Text("at")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(game.homeTeam.abbreviation)
                    .font(.headline)

                Spacer()

                if let awayScore = game.awayScore,
                   let homeScore = game.homeScore {
                    Text("\(awayScore) – \(homeScore)")
                        .font(.headline)
                        .monospacedDigit()
                }
            }

            HStack {
                Text(game.startTime.iceometicsShortDateTime)

                if let venue = game.venue,
                   !venue.isEmpty {
                    Text("•")
                    Text(venue)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch game.status {
        case .scheduled:
            "Scheduled"
        case .live:
            "Live"
        case .final:
            "Final"
        case .postponed:
            "Postponed"
        case .unknown:
            "Status unavailable"
        }
    }
}
