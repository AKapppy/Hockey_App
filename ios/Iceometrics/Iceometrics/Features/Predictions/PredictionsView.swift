import SwiftUI

struct PredictionsView: View {
    @StateObject private var viewModel: PredictionsViewModel
    @State private var selectedPredictionTab = "pie"
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @MainActor
    init(viewModel: PredictionsViewModel? = nil) {
        _viewModel = StateObject(
            wrappedValue: viewModel ?? PredictionsViewModel()
        )
    }

    var body: some View {
        Group {
            if let snapshot = viewModel.snapshot,
               snapshot.hasData {
                predictionContent(snapshot)
            } else if viewModel.isLoading {
                ProgressView("Loading MoneyPuck predictions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Predictions unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ContentUnavailableView(
                    "No prediction data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("No MoneyPuck simulation tables are available yet.")
                )
            }
        }
        .navigationTitle("Predictions")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh predictions")
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            selectFirstAvailableMetricIfNeeded()
        }
        .onChange(of: viewModel.snapshot?.generatedAt) { _, _ in
            selectFirstAvailableMetricIfNeeded()
        }
    }

    @ViewBuilder
    private func predictionContent(_ snapshot: PredictionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            predictionHeader(snapshot)
            predictionTabPicker(snapshot.metrics)

            if selectedPredictionTab == "pie" {
                PredictionPieChartView(snapshot: snapshot)
            } else if let table = snapshot.tables[selectedPredictionTab] {
                PredictionSpreadsheet(
                    table: table,
                    teams: sortedTeams(
                        snapshot.teams,
                        table: table
                    ),
                    season: snapshot.season,
                    compact: horizontalSizeClass == .compact
                )
            } else {
                ContentUnavailableView(
                    "Metric unavailable",
                    systemImage: "tablecells",
                    description: Text("This MoneyPuck table was not included in the latest export.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private func predictionHeader(_ snapshot: PredictionSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    selectedPredictionTab == "pie"
                        ? "MoneyPuck Predictions"
                        : (selectedMetric?.title ?? "MoneyPuck Predictions")
                )
                .font(.title2.bold())

                Text("\(viewModel.sourceStatusText) • \(viewModel.updatedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func predictionTabPicker(_ metrics: [PredictionMetric]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                predictionTabButtons(metrics)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    predictionTabButtons(metrics)
                }
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func predictionTabButtons(_ metrics: [PredictionMetric]) -> some View {
        Button {
            selectedPredictionTab = "pie"
        } label: {
            Text("Pie Chart")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(
            PredictionMetricButtonStyle(
                isSelected: selectedPredictionTab == "pie"
            )
        )

        ForEach(metrics) { metric in
            Button {
                selectedPredictionTab = metric.key
            } label: {
                Text(metric.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(
                PredictionMetricButtonStyle(
                    isSelected: selectedPredictionTab == metric.key
                )
            )
        }
    }

    private var selectedMetric: PredictionMetric? {
        viewModel.metrics.first { $0.key == selectedPredictionTab }
    }

    private func sortedTeams(
        _ teams: [PredictionTeam],
        table: PredictionTable
    ) -> [PredictionTeam] {
        teams.sorted { lhs, rhs in
            let left = table.latestValue(teamCode: lhs.code) ?? -1
            let right = table.latestValue(teamCode: rhs.code) ?? -1

            if left == right {
                return lhs.name < rhs.name
            }

            return left > right
        }
    }

    private func selectFirstAvailableMetricIfNeeded() {
        guard let snapshot = viewModel.snapshot else { return }

        if selectedPredictionTab == "pie" {
            return
        }

        if snapshot.tables[selectedPredictionTab] != nil {
            return
        }

        if let first = snapshot.metrics.first(where: {
            snapshot.tables[$0.key] != nil
        }) {
            selectedPredictionTab = first.key
        } else {
            selectedPredictionTab = "pie"
        }
    }
}

private struct PredictionMetricButtonStyle: ButtonStyle {
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

private struct PredictionSpreadsheet: View {
    let table: PredictionTable
    let teams: [PredictionTeam]
    let season: String
    let compact: Bool

    private let rowHeight: CGFloat = 42

    private var teamColumnWidth: CGFloat {
        compact ? 142 : 210
    }

    private var dateColumnWidth: CGFloat {
        compact ? 68 : 82
    }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                fixedTeamColumn

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(table.columns.indices, id: \.self) { columnIndex in
                            predictionDateColumn(columnIndex)
                        }
                    }
                }
            }
            .background(.background)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func predictionDateColumn(
        _ columnIndex: Int
    ) -> some View {
        let isLatest = columnIndex == table.columns.count - 1

        return LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(teams) { team in
                    probabilityCell(
                        table.value(
                            teamCode: team.code,
                            columnIndex: columnIndex
                        ),
                        isLatest: isLatest
                    )
                }
            } header: {
                dateHeader(
                    table.columns[columnIndex],
                    isLatest: isLatest
                )
                .zIndex(2)
            }
        }
        .frame(width: dateColumnWidth)
    }

    private var fixedTeamColumn: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(teams) { team in
                    HStack(spacing: 9) {
                        PredictionTeamLogo(team: team)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(compact ? team.code : team.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if !compact {
                                Text(team.code)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(
                        width: teamColumnWidth,
                        height: rowHeight,
                        alignment: .leading
                    )
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.025))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(height: 1)
                    }
                }
            } header: {
                Text("Team")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: teamColumnWidth,
                        height: rowHeight,
                        alignment: .leading
                    )
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.055))
                    .background(.background)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(height: 1)
                    }
                    .zIndex(2)
            }
        }
        .zIndex(3)
    }

    private func dateHeader(
        _ raw: String,
        isLatest: Bool
    ) -> some View {
        Text(displayDate(raw))
            .font(.caption.weight(isLatest ? .bold : .semibold))
            .foregroundStyle(isLatest ? .primary : .secondary)
            .frame(
                width: dateColumnWidth,
                height: rowHeight
            )
            .background(
                isLatest
                    ? Color.accentColor.opacity(0.10)
                    : Color.primary.opacity(0.055)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }
    }

    private func probabilityCell(
        _ value: Double?,
        isLatest: Bool
    ) -> some View {
        let clamped = min(max(value ?? 0, 0), 1)

        return Text(
            value.map {
                $0.formatted(
                    .percent.precision(.fractionLength(1))
                )
            } ?? ""
        )
        .font(
            .system(.caption, design: .monospaced)
            .weight(isLatest ? .bold : .medium)
        )
        .foregroundStyle(value == nil ? .tertiary : .primary)
        .frame(
            width: dateColumnWidth,
            height: rowHeight
        )
        .background(
            Color.accentColor.opacity(
                value == nil
                    ? 0
                    : 0.025 + (clamped * (isLatest ? 0.18 : 0.11))
            )
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.quaternary)
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
    }

    private func displayDate(_ raw: String) -> String {
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              let startYear = Int(season.prefix(4)) else {
            return raw
        }

        let year = month >= 7 ? startYear : startYear + 1
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day

        guard let date = components.date else {
            return raw
        }

        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .locale(Locale(identifier: "en_GB"))
        )
    }
}

private struct PredictionTeamLogo: View {
    let team: PredictionTeam

    var body: some View {
        AsyncImage(url: team.logoURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                Image(systemName: "hockey.puck.fill")
                    .foregroundStyle(.secondary)
            case .empty:
                ProgressView()
                    .controlSize(.mini)
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: 28, height: 28)
    }
    
}

#Preview {
    NavigationStack {
        PredictionsView()
    }
}
