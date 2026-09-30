import SwiftUI

struct GameDetailView: View {
    let game: HockeyGame

    @State private var detail: NHLGameDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                scoreHeader

                if isLoading {
                    ProgressView("Loading game statistics…")
                        .padding(.vertical, 40)
                } else if let detail {
                    shotsSection(detail)
                    statsSection(detail)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Game Statistics Unavailable",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text(errorMessage)
                    )
                    .padding(.vertical, 30)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .navigationTitle(
            "\(game.awayTeam.abbreviation) @ \(game.homeTeam.abbreviation)"
        )
        .task {
            await loadDetail()
        }
    }

    private var scoreHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                teamHeader(
                    team: game.awayTeam,
                    score: game.awayScore
                )

                Text("@")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                teamHeader(
                    team: game.homeTeam,
                    score: game.homeScore
                )
            }

            Text("FINAL")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())

            if let venue = game.venue, !venue.isEmpty {
                Label(venue, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        score: Int?
    ) -> some View {
        VStack(spacing: 7) {
            TeamLogoView(team: team, size: 62)

            Text(team.abbreviation)
                .font(.headline)

            Text(score.map(String.init) ?? "–")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func shotsSection(_ detail: NHLGameDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shots On Goal")
                .font(.title3.bold())

            VStack(spacing: 0) {
                statHeader

                ForEach(detail.shotsByPeriod) { row in
                    Divider()
                    threeColumnRow(
                        away: String(row.away),
                        label: row.label,
                        home: String(row.home),
                        emphasize: false
                    )
                }

                Divider()
                threeColumnRow(
                    away: String(detail.shotsByPeriod.reduce(0) { $0 + $1.away }),
                    label: "Total",
                    home: String(detail.shotsByPeriod.reduce(0) { $0 + $1.home }),
                    emphasize: true
                )
            }
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private func statsSection(_ detail: NHLGameDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Stats")
                .font(.title3.bold())

            VStack(spacing: 0) {
                statHeader

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
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
    }

    private var statHeader: some View {
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

    private func threeColumnRow(
        away: String,
        label: String,
        home: String,
        emphasize: Bool
    ) -> some View {
        HStack {
            Text(away)
                .frame(maxWidth: .infinity)
                .monospacedDigit()

            Text(label)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)

            Text(home)
                .frame(maxWidth: .infinity)
                .monospacedDigit()
        }
        .font(emphasize ? .body.bold() : .body)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
