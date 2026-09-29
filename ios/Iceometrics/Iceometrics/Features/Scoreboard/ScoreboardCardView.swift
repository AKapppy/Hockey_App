import SwiftUI

struct ScoreboardCardView: View {
    let game: HockeyGame

    var body: some View {
        VStack(spacing: 14) {
            cardHeader

            TeamScoreRow(
                team: game.awayTeam,
                score: game.awayScore,
                showScore: showsScore
            )

            HStack(spacing: 10) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)

                Text("at")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }

            TeamScoreRow(
                team: game.homeTeam,
                score: game.homeScore,
                showScore: showsScore
            )

            if let venue = game.venue,
               !venue.isEmpty {
                Label(venue, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private var cardHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryStatusText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()

                if let secondaryStatusText {
                    Text(secondaryStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(statusBadgeText)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
    }

    private var showsScore: Bool {
        game.status == .live || game.status == .final
    }

    private var primaryStatusText: String {
        switch game.status {
        case .scheduled:
            game.startTime.formatted(date: .omitted, time: .shortened)
        case .live:
            "Live"
        case .final:
            "Final"
        case .postponed:
            "Postponed"
        case .unknown:
            game.startTime.formatted(date: .omitted, time: .shortened)
        }
    }

    private var secondaryStatusText: String? {
        switch game.status {
        case .scheduled:
            return "Scheduled"
        case .live:
            return "Game in progress"
        case .final:
            return nil
        case .postponed:
            return "Start time subject to change"
        case .unknown:
            return "Status unavailable"
        }
    }

    private var statusBadgeText: String {
        switch game.status {
        case .scheduled:
            "Upcoming"
        case .live:
            "Live"
        case .final:
            "Final"
        case .postponed:
            "PPD"
        case .unknown:
            "Game"
        }
    }
}

private struct TeamScoreRow: View {
    let team: Team
    let score: Int?
    let showScore: Bool

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

            Spacer(minLength: 12)

            if showScore {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}

private struct TeamLogoView: View {
    let team: Team

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
        .frame(width: 48, height: 48)
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
