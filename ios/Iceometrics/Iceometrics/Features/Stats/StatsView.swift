import SwiftUI
import Charts
import Foundation

struct StatsView: View {
    @StateObject private var viewModel: StatsViewModel
    @State private var selectedSection: StatsSection = .teamStats
    @State private var selectedTeamCode: String?

    @MainActor
    init(viewModel: StatsViewModel? = nil) {
        _viewModel = StateObject(
            wrappedValue: viewModel ?? StatsViewModel()
        )
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot {
                content(snapshot)
            } else if viewModel.isLoading {
                ProgressView("Loading NHL stats…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Stats unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ContentUnavailableView(
                    "No stats data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("No NHL stats snapshot is available yet.")
                )
            }
        }
        .navigationTitle("Stats")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh stats")
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private func content(_ snapshot: StatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("NHL • \(viewModel.updatedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            statsSectionPicker

            Group {
                switch selectedSection {
                case .teamStats:
                    TeamStatsPanel(
                        snapshot: snapshot,
                        selectedTeamCode: $selectedTeamCode
                    )
                case .gameStats:
                    GameStatsPanel(
                        snapshot: snapshot,
                        selectedTeamCode: $selectedTeamCode
                    )
                case .playerStats:
                    PlayerStatsPanel(
                        snapshot: snapshot,
                        viewModel: viewModel
                    )
                case .goalDifferential:
                    GoalDifferentialPanel(
                        snapshot: snapshot,
                        selectedTeamCode: $selectedTeamCode
                    )
                case .points:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Points")
                            .font(.title2.bold())

                        if let table = snapshot.pointsHistory() {
                            HistoryStatsPanel(
                                title: "Points",
                                table: table,
                                teams: snapshot.teams,
                                selectedTeamCode: $selectedTeamCode,
                                allowNegative: false
                            )
                        } else {
                            ContentUnavailableView(
                                "Points unavailable",
                                systemImage: "chart.xyaxis.line",
                                description: Text("Regular-season points history is not available yet.")
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private var statsSectionPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                statsSectionButtons
            }
            .frame(maxWidth: .infinity, alignment: .center)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    statsSectionButtons
                }
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var statsSectionButtons: some View {
        ForEach(StatsSection.allCases) { section in
            Button {
                selectedSection = section
            } label: {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(
                StatsTabButtonStyle(
                    isSelected: selectedSection == section
                )
            )
        }
    }

}

private enum StatsSection: String, CaseIterable, Identifiable {
    case teamStats
    case gameStats
    case playerStats
    case goalDifferential
    case points

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teamStats: "Team Stats"
        case .gameStats: "Game Stats"
        case .playerStats: "Player Stats"
        case .goalDifferential: "Goal Differential"
        case .points: "Points"
        }
    }
}

private struct StatsTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055),
                in: Capsule()
            )
    }
}

private struct StatsPhasePicker: View {
    @Binding var selection: StatsPhase
    let phases: [StatsPhase]

    var body: some View {
        Picker("Phase", selection: $selection) {
            ForEach(phases) { phase in
                Text(phase.title).tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 520)
    }
}

private struct StatsPanelHeader: View {
    let title: String
    @Binding var selection: StatsPhase
    let phases: [StatsPhase]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)

                StatsPhasePicker(
                    selection: $selection,
                    phases: phases
                )
            }
        } else {
            HStack(spacing: 14) {
                Text(title)
                    .font(.title2.bold())

                StatsPhasePicker(
                    selection: $selection,
                    phases: phases
                )
                .frame(maxWidth: 420)

                Spacer(minLength: 0)
            }
        }
    }
}

private struct TeamStatsPanel: View {
    let snapshot: StatsSnapshot
    @Binding var selectedTeamCode: String?
    @State private var phase: StatsPhase = .preseason
    @State private var sortKey: TeamSortKey = .team
    @State private var descending = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty ? [.preseason] : snapshot.availablePhases
    }

    private var rows: [TeamStatsRow] {
        let source = snapshot.teamStats(for: phase)
        return source.sorted { lhs, rhs in
            descending
                ? isOrderedBefore(rhs, lhs)
                : isOrderedBefore(lhs, rhs)
        }
    }

    private func isOrderedBefore(
        _ lhs: TeamStatsRow,
        _ rhs: TeamStatsRow
    ) -> Bool {
        switch sortKey {
        case .team:
            return lhs.teamCode < rhs.teamCode
        case .record:
            let left = (lhs.pts, lhs.winPercentage, lhs.gd, lhs.gf)
            let right = (rhs.pts, rhs.winPercentage, rhs.gd, rhs.gf)
            return left == right ? lhs.teamCode < rhs.teamCode : left < right
        case .gp:
            return lhs.gp == rhs.gp ? lhs.teamCode < rhs.teamCode : lhs.gp < rhs.gp
        case .w:
            return lhs.w == rhs.w ? lhs.teamCode < rhs.teamCode : lhs.w < rhs.w
        case .l:
            return lhs.l == rhs.l ? lhs.teamCode < rhs.teamCode : lhs.l < rhs.l
        case .pts:
            return lhs.pts == rhs.pts ? lhs.teamCode < rhs.teamCode : lhs.pts < rhs.pts
        case .gf:
            return lhs.gf == rhs.gf ? lhs.teamCode < rhs.teamCode : lhs.gf < rhs.gf
        case .ga:
            return lhs.ga == rhs.ga ? lhs.teamCode < rhs.teamCode : lhs.ga < rhs.ga
        case .gd:
            return lhs.gd == rhs.gd ? lhs.teamCode < rhs.teamCode : lhs.gd < rhs.gd
        case .pointsPercentage:
            return lhs.pointsPercentage == rhs.pointsPercentage
                ? lhs.teamCode < rhs.teamCode
                : lhs.pointsPercentage < rhs.pointsPercentage
        case .winPercentage:
            return lhs.winPercentage == rhs.winPercentage
                ? lhs.teamCode < rhs.teamCode
                : lhs.winPercentage < rhs.winPercentage
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            teamHeader

            TeamStatsTable(
                snapshot: snapshot,
                rows: rows,
                sortKey: sortKey,
                descending: descending,
                selectedTeamCode: $selectedTeamCode,
                onSort: sort
            )
        }
        .onAppear { normalizePhase() }
        .onChange(of: snapshot.generatedAt) { _, _ in normalizePhase() }
    }

    @ViewBuilder
    private var teamHeader: some View {
        let form = selectedTeamCode.flatMap {
            snapshot.recentForm(teamCode: $0)
        }

        if horizontalSizeClass == .compact {
            VStack(spacing: 8) {
                StatsPanelHeader(
                    title: "Team Stats",
                    selection: $phase,
                    phases: phases
                )

                if let form {
                    RecentFormCard(form: form)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                HStack(spacing: 14) {
                    Text("Team Stats")
                        .font(.title2.bold())

                    StatsPhasePicker(
                        selection: $phase,
                        phases: phases
                    )
                    .frame(maxWidth: 420)
                }

                Spacer(minLength: 18)

                if let form {
                    RecentFormCard(form: form)
                        .frame(maxWidth: 430, alignment: .trailing)
                }
            }
        }
    }

    private func normalizePhase() {
        if !phases.contains(phase) {
            phase = snapshot.defaultPhase
        }
    }

    private func sort(_ key: TeamSortKey) {
        if sortKey == key {
            descending.toggle()
        } else {
            sortKey = key
            descending = key != .team
        }
    }
}

private enum TeamSortKey: String, CaseIterable {
    case team
    case record
    case gp
    case w
    case l
    case pts
    case gf
    case ga
    case gd
    case pointsPercentage
    case winPercentage

    var label: String {
        switch self {
        case .team: "Team"
        case .record: "RECORD"
        case .gp: "GP"
        case .w: "W"
        case .l: "L"
        case .pts: "PTS"
        case .gf: "GF"
        case .ga: "GA"
        case .gd: "GD"
        case .pointsPercentage: "P%"
        case .winPercentage: "W%"
        }
    }
}

private struct TeamStatsTable: View {
    let snapshot: StatsSnapshot
    let rows: [TeamStatsRow]
    let sortKey: TeamSortKey
    let descending: Bool
    @Binding var selectedTeamCode: String?
    let onSort: (TeamSortKey) -> Void

    private let rowHeight: CGFloat = 40
    private let teamWidth: CGFloat = 112

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                fixedTeamColumn

                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        statColumn(.record, width: 110) { $0.record }
                        statColumn(.gp) { String($0.gp) }
                        statColumn(.w) { String($0.w) }
                        statColumn(.l, inverse: true) { String($0.l) }
                        statColumn(.pts) { String($0.pts) }
                        statColumn(.gf) { String($0.gf) }
                        statColumn(.ga, inverse: true) { String($0.ga) }
                        statColumn(.gd) { String($0.gd) }
                        statColumn(.pointsPercentage) {
                            $0.pointsPercentage.formatted(.percent.precision(.fractionLength(1)))
                        }
                        statColumn(.winPercentage) {
                            $0.winPercentage.formatted(.percent.precision(.fractionLength(1)))
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var fixedTeamColumn: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(rows) { row in
                    Button {
                        selectedTeamCode = row.teamCode
                    } label: {
                        HStack(spacing: 6) {
                            StatsTeamLogo(
                                team: snapshot.team(for: row.teamCode),
                                size: 24
                            )
                            Text(row.teamCode)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(width: teamWidth, height: rowHeight)
                        .background(
                            selectedTeamCode == row.teamCode
                                ? Color.accentColor.opacity(0.12)
                                : Color.primary.opacity(0.025)
                        )
                        .overlay(alignment: .bottom) {
                            tableHorizontalHairline
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                header(.team, width: teamWidth)
                    .zIndex(2)
            }
        }
        .background(.background)
        .zIndex(3)
    }

    private func header(_ key: TeamSortKey, width: CGFloat = 68) -> some View {
        Button {
            onSort(key)
        } label: {
            HStack(spacing: 3) {
                Text(key.label)
                if sortKey == key {
                    Image(systemName: descending ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: width, height: rowHeight)
            .background(Color.primary.opacity(0.055))
            .background(.background)
            .overlay(alignment: .leading) {
                tableVerticalHairline
            }
            .overlay(alignment: .bottom) {
                tableHorizontalHairline
            }
        }
        .buttonStyle(.plain)
    }

    private func statColumn(
        _ key: TeamSortKey,
        width: CGFloat = 68,
        inverse: Bool = false,
        text: @escaping (TeamStatsRow) -> String
    ) -> some View {
        let values = rows.map { numericValue($0, key: key) }.compactMap { $0 }
        let low = values.min() ?? 0
        let high = values.max() ?? low

        return LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(rows) { row in
                    let value = numericValue(row, key: key)
                    Text(text(row))
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .frame(width: width, height: rowHeight)
                        .background(
                            heatColor(
                                value: value,
                                low: low,
                                high: high,
                                inverse: inverse
                            )
                        )
                        .overlay(alignment: .leading) {
                            tableVerticalHairline
                        }
                        .overlay(alignment: .bottom) {
                            tableHorizontalHairline
                        }
                }
            } header: {
                header(key, width: width)
                    .zIndex(2)
            }
        }
    }

    private func numericValue(_ row: TeamStatsRow, key: TeamSortKey) -> Double? {
        switch key {
        case .team, .record: nil
        case .gp: Double(row.gp)
        case .w: Double(row.w)
        case .l: Double(row.l)
        case .pts: Double(row.pts)
        case .gf: Double(row.gf)
        case .ga: Double(row.ga)
        case .gd: Double(row.gd)
        case .pointsPercentage: row.pointsPercentage
        case .winPercentage: row.winPercentage
        }
    }

    private func heatColor(
        value: Double?,
        low: Double,
        high: Double,
        inverse: Bool
    ) -> Color {
        guard let value, high > low else {
            return Color.primary.opacity(0.018)
        }
        var rank = (value - low) / (high - low)
        if inverse { rank = 1 - rank }
        return Color.accentColor.opacity(0.025 + (0.14 * rank))
    }
}

private struct RecentFormCard: View {
    let form: RecentForm

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(form.title)
                .font(.subheadline.bold())
            ForEach(form.lines, id: \.self) { line in
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct GameStatsPanel: View {
    let snapshot: StatsSnapshot
    @Binding var selectedTeamCode: String?
    @State private var phase: StatsPhase = .preseason

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty ? [.preseason] : snapshot.availablePhases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatsPanelHeader(
                title: "Game Stats",
                selection: $phase,
                phases: phases
            )

            if let table = snapshot.gameStats(for: phase) {
                GameStatsTableView(
                    snapshot: snapshot,
                    table: table,
                    selectedTeamCode: $selectedTeamCode
                )
            } else {
                ContentUnavailableView(
                    "Game stats unavailable",
                    systemImage: "calendar",
                    description: Text("There are no games in this phase yet.")
                )
            }
        }
        .onAppear { normalizePhase() }
        .onChange(of: snapshot.generatedAt) { _, _ in normalizePhase() }
    }

    private func normalizePhase() {
        if !phases.contains(phase) {
            phase = snapshot.defaultPhase
        }
    }
}

private struct GameStatsTableView: View {
    let snapshot: StatsSnapshot
    let table: GameStatsTable
    @Binding var selectedTeamCode: String?

    private let rowHeight: CGFloat = 40
    private let teamWidth: CGFloat = 112
    private let dateWidth: CGFloat = 68

    private var teams: [StatsTeam] {
        snapshot.teams
            .filter { table.rows[$0.code] != nil }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                fixedTeamColumn

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(table.columns, id: \.self) { day in
                            dateColumn(day)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var fixedTeamColumn: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(teams) { team in
                    Button {
                        selectedTeamCode = team.code
                    } label: {
                        HStack(spacing: 6) {
                            StatsTeamLogo(team: team, size: 24)
                            Text(team.code)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(width: teamWidth, height: rowHeight)
                        .background(
                            selectedTeamCode == team.code
                                ? Color.accentColor.opacity(0.12)
                                : Color.primary.opacity(0.025)
                        )
                        .overlay(alignment: .bottom) {
                            tableHorizontalHairline
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Team")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: teamWidth, height: rowHeight)
                    .background(Color.primary.opacity(0.055))
                    .background(.background)
                    .overlay(alignment: .bottom) {
                        tableHorizontalHairline
                    }
                    .zIndex(2)
            }
        }
        .background(.background)
        .zIndex(3)
    }

    private func dateColumn(_ day: String) -> some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(teams) { team in
                    let result = table.result(teamCode: team.code, day: day) ?? ""
                    Text(result)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .frame(width: dateWidth, height: rowHeight)
                        .background(resultColor(result))
                        .overlay(alignment: .leading) {
                            tableVerticalHairline
                        }
                        .overlay(alignment: .bottom) {
                            tableHorizontalHairline
                        }
                }
            } header: {
                Text(displayDay(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: dateWidth, height: rowHeight)
                    .background(Color.primary.opacity(0.055))
                    .background(.background)
                    .overlay(alignment: .leading) {
                        tableVerticalHairline
                    }
                    .overlay(alignment: .bottom) {
                        tableHorizontalHairline
                    }
                    .zIndex(2)
            }
        }
    }

    private func resultColor(_ result: String) -> Color {
        let rank: Double
        switch result {
        case "W": rank = 1.0
        case "OTW": rank = 0.84
        case "SOW": rank = 0.70
        case "SOL": rank = 0.52
        case "OTL": rank = 0.36
        case "L": rank = 0.18
        default: return Color.primary.opacity(0.015)
        }
        return Color.accentColor.opacity(0.035 + rank * 0.16)
    }
}

private struct PlayerStatsPanel: View {
    let snapshot: StatsSnapshot
    @ObservedObject var viewModel: StatsViewModel
    @State private var phase: StatsPhase = .preseason
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty ? [snapshot.defaultPhase] : snapshot.availablePhases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatsPanelHeader(
                title: "Player Stats",
                selection: $phase,
                phases: phases
            )

            if viewModel.loadingPlayerPhases.contains(phase) {
                ProgressView("Loading player leaders…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = viewModel.playerStats[phase],
                      !data.skaters.isEmpty || !data.goalies.isEmpty {
                if horizontalSizeClass == .compact {
                    ScrollView(.vertical) {
                        VStack(spacing: 14) {
                            PlayerCategoryPanel(
                                title: "Skaters",
                                players: data.skaters,
                                options: ["All", "Goals", "Assists", "Points", "Hits", "Blocks", "+/-", "PIM"],
                                allStats: ["Goals", "Assists", "Points"],
                                snapshot: snapshot
                            )
                            PlayerCategoryPanel(
                                title: "Goalies",
                                players: data.goalies,
                                options: ["All", "Wins", "Save %", "Shutouts", "Saves / GS", "GAA"],
                                allStats: ["Wins", "Save %", "Shutouts"],
                                snapshot: snapshot
                            )
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        PlayerCategoryPanel(
                            title: "Skaters",
                            players: data.skaters,
                            options: ["All", "Goals", "Assists", "Points", "Hits", "Blocks", "+/-", "PIM"],
                            allStats: ["Goals", "Assists", "Points"],
                            snapshot: snapshot
                        )
                        PlayerCategoryPanel(
                            title: "Goalies",
                            players: data.goalies,
                            options: ["All", "Wins", "Save %", "Shutouts", "Saves / GS", "GAA"],
                            allStats: ["Wins", "Save %", "Shutouts"],
                            snapshot: snapshot
                        )
                    }
                }
            } else if let message = viewModel.playerErrorMessage {
                ContentUnavailableView(
                    "Player stats unavailable",
                    systemImage: "person.crop.rectangle.stack",
                    description: Text(message)
                )
            } else {
                ContentUnavailableView(
                    "No player stats",
                    systemImage: "person.crop.rectangle.stack",
                    description: Text("No NHL player leaders are available for this phase yet.")
                )
            }
        }
        .onAppear {
            phase = phases.contains(snapshot.defaultPhase)
                ? snapshot.defaultPhase
                : (phases.first ?? .regular)
            Task { await viewModel.loadPlayers(for: phase) }
        }
        .onChange(of: phase) { _, newPhase in
            Task { await viewModel.loadPlayers(for: newPhase) }
        }
    }
}

private struct PlayerCategoryPanel: View {
    let title: String
    let players: [PlayerStatLine]
    let options: [String]
    let allStats: [String]
    let snapshot: StatsSnapshot
    @State private var selectedStat = "All"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                Picker("Stat", selection: $selectedStat) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
            }

            if selectedStat == "All" {
                ForEach(allStats, id: \.self) { stat in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(stat)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(topPlayers(for: stat, limit: 3)) { player in
                                    PlayerLeaderCard(
                                        player: player,
                                        stat: stat,
                                        snapshot: snapshot
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(topPlayers(for: selectedStat, limit: 25)) { player in
                        PlayerLeaderRow(
                            player: player,
                            stat: selectedStat,
                            snapshot: snapshot
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func topPlayers(for stat: String, limit: Int) -> [PlayerStatLine] {
        Array(
            players.sorted {
                if $0.value(stat) == $1.value(stat) {
                    return $0.name < $1.name
                }
                return $0.value(stat) > $1.value(stat)
            }.prefix(limit)
        )
    }
}

private struct PlayerLeaderCard: View {
    let player: PlayerStatLine
    let stat: String
    let snapshot: StatsSnapshot

    var body: some View {
        VStack(spacing: 6) {
            PlayerPortrait(player: player, snapshot: snapshot, size: 78)
            Text(player.name)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 116)
            Text(formatPlayerValue(player.value(stat), stat: stat))
                .font(.title3.bold())
        }
        .padding(10)
        .frame(width: 132)
        .frame(minHeight: 150)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PlayerLeaderRow: View {
    let player: PlayerStatLine
    let stat: String
    let snapshot: StatsSnapshot

    var body: some View {
        HStack(spacing: 10) {
            PlayerPortrait(player: player, snapshot: snapshot, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline.weight(.semibold))
                Text(player.teamCode)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatPlayerValue(player.value(stat), stat: stat))
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
        }
        .padding(.vertical, 7)
    }
}

private struct PlayerPortrait: View {
    let player: PlayerStatLine
    let snapshot: StatsSnapshot
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: headshotURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.crop.square")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.18)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))

            StatsTeamLogo(team: snapshot.team(for: player.teamCode), size: size * 0.36)
                .padding(2)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var headshotURL: URL? {
        guard player.playerID > 0, !player.teamCode.isEmpty else { return nil }
        let seasonID = snapshot.season.replacingOccurrences(of: "-", with: "")
        return URL(
            string: "https://assets.nhle.com/mugs/nhl/\(seasonID)/\(player.teamCode)/\(player.playerID).png"
        )
    }
}

private func formatPlayerValue(_ value: Double, stat: String) -> String {
    switch stat {
    case "Save %":
        return String(format: "%.3f", value)
    case "Saves / GS", "GAA":
        return String(format: "%.2f", value)
    default:
        return String(Int(value.rounded()))
    }
}

private struct GoalDifferentialPanel: View {
    let snapshot: StatsSnapshot
    @Binding var selectedTeamCode: String?
    @State private var phase: StatsPhase = .preseason

    private var phases: [StatsPhase] {
        snapshot.availablePhases.isEmpty ? [snapshot.defaultPhase] : snapshot.availablePhases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatsPanelHeader(
                title: "Goal Differential",
                selection: $phase,
                phases: phases
            )

            if let table = snapshot.goalDifferentialHistory(for: phase) {
                HistoryStatsPanel(
                    title: "Goal Differential",
                    table: table,
                    teams: snapshot.teams,
                    selectedTeamCode: $selectedTeamCode,
                    allowNegative: true
                )
            } else {
                ContentUnavailableView(
                    "Goal differential unavailable",
                    systemImage: "chart.xyaxis.line",
                    description: Text("There are no games in this phase yet.")
                )
            }
        }
        .onAppear {
            phase = phases.contains(snapshot.defaultPhase)
                ? snapshot.defaultPhase
                : (phases.first ?? .regular)
        }
    }
}

private struct HistoryStatsPanel: View {
    let title: String
    let table: StatsHistoryTable
    let teams: [StatsTeam]
    @Binding var selectedTeamCode: String?
    let allowNegative: Bool

    private let rowHeight: CGFloat = 38
    private let teamWidth: CGFloat = 112
    private let dateWidth: CGFloat = 64

    private var visibleTeams: [StatsTeam] {
        teams
            .filter { table.rows[$0.code] != nil }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            allTeamsChart
            historyTable
        }
    }

    private var allTeamsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedTeamCode,
               let selected = visibleTeams.first(where: { $0.code == selectedTeamCode }) {
                HStack(spacing: 8) {
                    StatsTeamLogo(team: selected, size: 26)
                    Text("\(selected.name) — \(title)")
                        .font(.headline)
                }
            } else {
                Text("All Teams — \(title)")
                    .font(.headline)
            }

            Chart {
                ForEach(visibleTeams) { team in
                    let values = table.rows[team.code] ?? []
                    ForEach(Array(values.enumerated()), id: \.offset) { item in
                        if let value = item.element {
                            LineMark(
                                x: .value(
                                    "Date",
                                    displayHistoryDate(table.columns[item.offset])
                                ),
                                y: .value(title, value)
                            )
                            .foregroundStyle(by: .value("Team", team.code))
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: lineWidth(for: team),
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .opacity(lineOpacity(for: team))

                            if selectedTeamCode == team.code {
                                PointMark(
                                    x: .value(
                                        "Date",
                                        displayHistoryDate(table.columns[item.offset])
                                    ),
                                    y: .value(title, value)
                                )
                                .foregroundStyle(by: .value("Team", team.code))
                                .symbolSize(18)
                            }
                        }
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: visibleTeams.map(\.code),
                range: visibleTeams.map { Color(hex: $0.colorHex) }
            )
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: 220)
        }
        .padding(12)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var historyTable: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                fixedTeamColumn

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(table.columns.indices, id: \.self) { index in
                            historyDateColumn(index)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var fixedTeamColumn: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(visibleTeams) { team in
                    Button {
                        selectedTeamCode = selectedTeamCode == team.code
                            ? nil
                            : team.code
                    } label: {
                        HStack(spacing: 6) {
                            StatsTeamLogo(team: team, size: 22)
                            Text(team.code)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(width: teamWidth, height: rowHeight)
                        .background(
                            selectedTeamCode == team.code
                                ? Color(hex: team.colorHex).opacity(0.16)
                                : Color.primary.opacity(0.025)
                        )
                        .overlay(alignment: .bottom) {
                            tableHorizontalHairline
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Team")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: teamWidth, height: rowHeight)
                    .background(Color.primary.opacity(0.055))
                    .background(.background)
                    .overlay(alignment: .bottom) {
                        tableHorizontalHairline
                    }
                    .zIndex(2)
            }
        }
        .background(.background)
        .zIndex(3)
    }

    private func historyDateColumn(_ index: Int) -> some View {
        let bounds = columnBounds(index)

        return LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(visibleTeams) { team in
                    let value = table.value(
                        teamCode: team.code,
                        columnIndex: index
                    )
                    Text(formatHistoryValue(value))
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .frame(width: dateWidth, height: rowHeight)
                        .background(
                            historyHeatColor(
                                value: value,
                                low: bounds.low,
                                high: bounds.high
                            )
                        )
                        .overlay(alignment: .leading) {
                            tableVerticalHairline
                        }
                        .overlay(alignment: .bottom) {
                            tableHorizontalHairline
                        }
                }
            } header: {
                Text(displayHistoryDate(table.columns[index]))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: dateWidth, height: rowHeight)
                    .background(Color.primary.opacity(0.055))
                    .background(.background)
                    .overlay(alignment: .leading) {
                        tableVerticalHairline
                    }
                    .overlay(alignment: .bottom) {
                        tableHorizontalHairline
                    }
                    .zIndex(2)
            }
        }
    }

    private func lineWidth(for team: StatsTeam) -> CGFloat {
        guard let selectedTeamCode else { return 1.6 }
        return selectedTeamCode == team.code ? 3.6 : 1.0
    }

    private func lineOpacity(for team: StatsTeam) -> Double {
        guard let selectedTeamCode else { return 0.88 }
        return selectedTeamCode == team.code ? 1.0 : 0.22
    }

    private func columnBounds(_ index: Int) -> (low: Double, high: Double) {
        let values = visibleTeams.compactMap {
            table.value(teamCode: $0.code, columnIndex: index)
        }
        return (values.min() ?? 0, values.max() ?? 0)
    }

    private func historyHeatColor(
        value: Double?,
        low: Double,
        high: Double
    ) -> Color {
        guard let value else { return Color.clear }
        if high <= low { return Color.accentColor.opacity(0.07) }
        let rank = (value - low) / (high - low)
        let base = allowNegative && value < 0 ? 0.025 : 0.04
        return Color.accentColor.opacity(base + rank * 0.16)
    }

    private func formatHistoryValue(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(Int(value.rounded()))
    }
}

private struct StatsTeamLogo: View {
    let team: StatsTeam?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: team?.logoURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Image(systemName: "hockey.puck.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

private func displayDay(_ raw: String) -> String {
    let parts = raw.split(separator: "-")
    guard parts.count == 3,
          let month = Int(parts[1]),
          let day = Int(parts[2]) else {
        return raw
    }
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.year = Int(parts[0])
    components.month = month
    components.day = day
    guard let date = components.date else { return raw }
    return date.formatted(
        .dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_GB"))
    )
}

private func displayHistoryDate(_ raw: String) -> String {
    let pieces = raw.split(separator: "/")
    guard pieces.count == 2,
          let month = Int(pieces[0]),
          let day = Int(pieces[1]) else {
        return raw
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_GB")
    guard let date = calendar.date(
        from: DateComponents(year: 2000, month: month, day: day)
    ) else {
        return raw
    }

    return date.formatted(
        .dateTime
            .day()
            .month(.abbreviated)
            .locale(Locale(identifier: "en_GB"))
    )
}

private var tableVerticalHairline: some View {
    Rectangle()
        .fill(.quaternary)
        .frame(width: 1)
}

private var tableHorizontalHairline: some View {
    Rectangle()
        .fill(.quaternary)
        .frame(height: 1)
}

#Preview {
    NavigationStack {
        StatsView()
    }
}
