import SwiftUI

struct GameDetailView: View {
    let game: HockeyGame
    let prediction: MoneyPuckGamePrediction?
    let allGames: [HockeyGame]

    @Environment(\.dismiss) private var dismiss

    @State private var detail: NHLGameDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let missing = NHLGameDetailService.missingText

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                scoreHeader

                if isLoading {
                    ProgressView("Loading game information…")
                        .padding(.vertical, 24)
                }

                if let detail {
                    goaliesSection(detail)
                    goalScorersSection(detail)
                    shotsSection(detail)
                    statsSection(detail)
                    scratchesSection(detail)
                    leadersSection(detail)
                    specialTeamsSection(detail)
                    penaltiesSection(detail)
                } else if !isLoading {
                    missingDetailSection
                }

                seasonSeriesSection

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .navigationTitle(
            "\(game.awayTeam.abbreviation) @ \(game.homeTeam.abbreviation)"
        )
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .accessibilityLabel("Close game details")
            }
        }
        .task {
            await loadDetail()
        }
    }

    private var scoreHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                teamHeader(
                    team: game.awayTeam,
                    score: game.awayScore,
                    probability: prediction?.awayWinProbability
                )

                Text("@")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                teamHeader(
                    team: game.homeTeam,
                    score: game.homeScore,
                    probability: prediction?.homeWinProbability
                )
            }

            HStack(spacing: 12) {
                if let venue = game.venue, !venue.isEmpty {
                    Label(venue, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(missing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(statusBadgeText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func teamHeader(
        team: Team,
        score: Int?,
        probability: Double?
    ) -> some View {
        VStack(spacing: 7) {
            TeamLogoView(team: team, size: 62)

            Text(team.abbreviation)
                .font(.headline)

            if game.status == .live || game.status == .final {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else if let probability {
                Text(
                    probability,
                    format: .percent.precision(.fractionLength(1))
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func goaliesSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Goalies") {
            twoTeamHeader
            Divider()
            threeColumnRow(
                away: goalieText(detail.awayGoalie),
                label: "Starter",
                home: goalieText(detail.homeGoalie),
                emphasize: false
            )
        }
    }

    private func goalScorersSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Goal Scorers") {
            if detail.goalScorers.isEmpty {
                missingRow
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detail.goalScorers.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(row.team)
                                .font(.caption.weight(.bold))
                                .frame(width: 42, alignment: .leading)
                            Text(row.player)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(row.period) · \(row.time)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private func shotsSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Shots On Goal") {
            if detail.shotsByPeriod.isEmpty {
                missingRow
            } else {
                VStack(spacing: 0) {
                    twoTeamHeader

                    ForEach(detail.shotsByPeriod) { row in
                        Divider()
                        threeColumnRow(
                            away: String(row.away),
                            label: row.label,
                            home: String(row.home),
                            emphasize: false
                        )
                    }

                    if detail.shotsByPeriod.first?.period != 0 {
                        Divider()
                        threeColumnRow(
                            away: String(
                                detail.shotsByPeriod.reduce(0) { $0 + $1.away }
                            ),
                            label: "Total",
                            home: String(
                                detail.shotsByPeriod.reduce(0) { $0 + $1.home }
                            ),
                            emphasize: true
                        )
                    }
                }
            }
        }
    }

    private func statsSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Game Stats") {
            VStack(spacing: 0) {
                twoTeamHeader

                ForEach(detail.stats) { row in
                    Divider()
                    threeColumnRow(
                        away: row.awayValue,
                        label: row.label,
                        home: row.homeValue,
                        emphasize: false
                    )
                }
            }
        }
    }

    private func scratchesSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Scratched Players") {
            VStack(spacing: 0) {
                twoTeamHeader
                Divider()
                HStack(alignment: .top, spacing: 18) {
                    textList(detail.awayScratches)
                    Divider()
                    textList(detail.homeScratches)
                }
                .padding(12)
            }
        }
    }

    private func leadersSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Team Leaders") {
            VStack(spacing: 0) {
                twoTeamHeader
                Divider()
                leaderRow(
                    label: "Goals",
                    away: detail.awayLeaders.goals,
                    home: detail.homeLeaders.goals
                )
                Divider()
                leaderRow(
                    label: "Assists",
                    away: detail.awayLeaders.assists,
                    home: detail.homeLeaders.assists
                )
                Divider()
                leaderRow(
                    label: "Points",
                    away: detail.awayLeaders.points,
                    home: detail.homeLeaders.points
                )
            }
        }
    }

    private func specialTeamsSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Special Teams Context") {
            VStack(spacing: 10) {
                Text(detail.specialTeams.state ?? missing)
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                threeColumnRow(
                    away: numberOrMissing(detail.specialTeams.awayPenaltiesTaken),
                    label: "Penalties Taken",
                    home: numberOrMissing(detail.specialTeams.homePenaltiesTaken),
                    emphasize: false
                )

                Divider()

                threeColumnRow(
                    away: numberOrMissing(detail.specialTeams.awayPenaltiesDrawn),
                    label: "Penalties Drawn",
                    home: numberOrMissing(detail.specialTeams.homePenaltiesDrawn),
                    emphasize: false
                )
            }
        }
    }

    private func penaltiesSection(_ detail: NHLGameDetail) -> some View {
        detailCard(title: "Penalty Summary") {
            if detail.penalties.isEmpty {
                missingRow
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detail.penalties.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(row.team)
                                .font(.caption.weight(.bold))
                                .frame(width: 42, alignment: .leading)
                            Text(row.description)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(row.period) · \(row.time)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private var seasonSeriesSection: some View {
        detailCard(title: "Season Series · \(gameTypeTitle)") {
            if seasonSeriesGames.isEmpty {
                missingRow
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(seasonSeriesGames.enumerated()), id: \.element.id) { index, seriesGame in
                        if index > 0 { Divider() }
                        HStack(spacing: 10) {
                            Text(
                                seriesGame.startTime.formatted(
                                    .dateTime.month(.abbreviated).day()
                                )
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)

                            Text(
                                "\(seriesGame.awayTeam.abbreviation) @ \(seriesGame.homeTeam.abbreviation)"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(seriesResultText(seriesGame))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
            }
        }
    }

    private var missingDetailSection: some View {
        detailCard(title: "Game Information") {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text(missing)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(14)
        }
    }

    private var twoTeamHeader: some View {
        HStack {
            Text(game.awayTeam.abbreviation)
                .frame(maxWidth: .infinity)

            Text("STAT")
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)

            Text(game.homeTeam.abbreviation)
                .frame(maxWidth: .infinity)
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func detailCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())

            content()
                .frame(maxWidth: .infinity)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }

    private var missingRow: some View {
        Text(missing)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(14)
    }

    private func textList(_ values: [String]) -> some View {
        Text(values.isEmpty ? missing : values.joined(separator: "\n"))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .foregroundStyle(values.isEmpty ? .secondary : .primary)
    }

    private func leaderRow(
        label: String,
        away: String?,
        home: String?
    ) -> some View {
        threeColumnRow(
            away: away ?? missing,
            label: label,
            home: home ?? missing,
            emphasize: false
        )
    }

    private func threeColumnRow(
        away: String,
        label: String,
        home: String,
        emphasize: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(away)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            Text(label)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(home)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .font(emphasize ? .body.bold() : .body)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func goalieText(_ slot: NHLGoalieSlot?) -> String {
        guard let slot else { return missing }
        return "\(slot.label): \(slot.name)"
    }

    private func numberOrMissing(_ value: Int?) -> String {
        value.map(String.init) ?? missing
    }

    private var seasonSeriesGames: [HockeyGame] {
        let targetTeams = Set([
            game.awayTeam.abbreviation.uppercased(),
            game.homeTeam.abbreviation.uppercased()
        ])
        let targetType = game.gameTypeId

        return allGames
            .filter { candidate in
                let candidateTeams = Set([
                    candidate.awayTeam.abbreviation.uppercased(),
                    candidate.homeTeam.abbreviation.uppercased()
                ])
                return candidateTeams == targetTeams
                    && candidate.gameTypeId == targetType
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private var gameTypeTitle: String {
        switch game.gameTypeId {
        case 1: "Preseason"
        case 2: "Regular Season"
        case 3: "Postseason"
        default: "Same Game Type"
        }
    }

    private func seriesResultText(_ game: HockeyGame) -> String {
        switch game.status {
        case .final, .live:
            if let away = game.awayScore, let home = game.homeScore {
                return "\(away)–\(home)"
            }
            return missing
        case .scheduled, .unknown:
            return game.startTime.formatted(date: .omitted, time: .shortened)
        case .postponed:
            return "PPD"
        }
    }

    private var statusBadgeText: String {
        switch game.status {
        case .scheduled:
            game.startTime.formatted(date: .omitted, time: .shortened)
        case .live:
            if game.isIntermission == true {
                return "\(periodLabel ?? "") Int"
                    .trimmingCharacters(in: .whitespaces)
            }
            if let periodLabel,
               let time = game.timeRemaining,
               !time.isEmpty {
                return "\(periodLabel) · \(time)"
            }
            return periodLabel ?? "LIVE"
        case .final:
            return "FINAL"
        case .postponed:
            return "PPD"
        case .unknown:
            game.startTime.formatted(date: .omitted, time: .shortened)
        }
        return ""
    }

    private var periodLabel: String? {
        if game.periodType?.uppercased() == "OT" { return "OT" }
        if game.periodType?.uppercased() == "SO" { return "SO" }
        guard let period = game.periodNumber, period > 0 else { return nil }
        switch period {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(period)th"
        }
        return ""
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            detail = try await NHLGameDetailService().fetchDetail(for: game)
        } catch {
            detail = nil
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }

        isLoading = false
    }
}
