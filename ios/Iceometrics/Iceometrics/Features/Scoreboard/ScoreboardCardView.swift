import SwiftUI

struct ScoreboardCardView: View {
    let game: HockeyGame
    let prediction: MoneyPuckGamePrediction?

    init(
        game: HockeyGame,
        prediction: MoneyPuckGamePrediction? = nil
    ) {
        self.game = game
        self.prediction = prediction
    }

    var body: some View {
        VStack(spacing: 14) {
            TeamScoreRow(
                team: game.awayTeam,
                score: game.awayScore,
                shots: game.awayShots,
                gameStatus: game.status,
                winProbability: displayedProbability(
                    prediction?.awayWinProbability
                )
            )

            HStack(spacing: 10) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)

                Text("@")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }

            TeamScoreRow(
                team: game.homeTeam,
                score: game.homeScore,
                shots: game.homeShots,
                gameStatus: game.status,
                winProbability: displayedProbability(
                    prediction?.homeWinProbability
                )
            )

            HStack(alignment: .center, spacing: 12) {
                if let venue = game.venue,
                   !venue.isEmpty {
                    Label(venue, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Venue TBD")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                Text(statusBadgeText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(18)
        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusBadgeText: String {
        switch game.status {
        case .scheduled:
            game.startTime.formatted(date: .omitted, time: .shortened)
        case .live:
            liveBadgeText
        case .final:
            "FINAL"
        case .postponed:
            "PPD"
        case .unknown:
            game.startTime.formatted(date: .omitted, time: .shortened)
        }
    }

    private var liveBadgeText: String {
        if game.isIntermission == true {
            if let periodLabel {
                return "\(periodLabel) Int"
            }
            return "Int"
        }

        let clock = game.timeRemaining?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let periodLabel,
           let clock,
           !clock.isEmpty {
            return "\(periodLabel) · \(clock)"
        }

        if let periodLabel {
            return periodLabel
        }

        if let clock, !clock.isEmpty {
            return clock
        }

        return "LIVE"
    }

    private var periodLabel: String? {
        let type = game.periodType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if type == "OT" {
            return "OT"
        }
        if type == "SO" {
            return "SO"
        }

        guard let period = game.periodNumber, period > 0 else {
            return nil
        }

        switch period {
        case 1:
            return "1st"
        case 2:
            return "2nd"
        case 3:
            return "3rd"
        default:
            return "\(period)th"
        }
    }

    private func displayedProbability(_ value: Double?) -> Double? {
        switch game.status {
        case .scheduled, .live:
            return value
        case .final, .postponed, .unknown:
            return nil
        }
    }
}

private struct TeamScoreRow: View {
    let team: Team
    let score: Int?
    let shots: Int?
    let gameStatus: GameStatus
    let winProbability: Double?

    var body: some View {
        HStack(spacing: 13) {
            TeamLogoView(team: team)

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(team.abbreviation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            switch gameStatus {
            case .scheduled:
                probabilityView
            case .live:
                probabilityView
                shotsView
                scoreView
            case .final:
                shotsView
                scoreView
            case .postponed, .unknown:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var probabilityView: some View {
        if let winProbability {
            Text(
                winProbability,
                format: .percent.precision(.fractionLength(1))
            )
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityLabel("MoneyPuck win probability")
        }
    }

    private var shotsView: some View {
        VStack(spacing: 1) {
            Text("SOG")
                .font(.caption2.weight(.semibold))
            Text(shots.map(String.init) ?? "–")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .frame(minWidth: 32)
    }

    private var scoreView: some View {
        Text(score.map(String.init) ?? "–")
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .monospacedDigit()
            .frame(minWidth: 28, alignment: .trailing)
    }
}

struct TeamLogoView: View {
    let team: Team
    var size: CGFloat = 48

    var body: some View {
        AsyncImage(url: team.logoURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .empty:
                ProgressView()
                    .controlSize(.small)
            case .failure:
                fallback
            @unknown default:
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(.quaternary)

            Text(team.abbreviation.prefix(3))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}
