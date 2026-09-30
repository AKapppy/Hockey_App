import SwiftUI

struct PredictionPieChartView: View {
    let snapshot: PredictionSnapshot
    @State private var selectedColumnIndex: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let metricOrder = [
        "madeplayoffs",
        "round2",
        "round3",
        "round4",
        "woncup",
    ]

    init(snapshot: PredictionSnapshot) {
        self.snapshot = snapshot
        let count = snapshot.tables["madeplayoffs"]?.columns.count
            ?? snapshot.tables.values.first?.columns.count
            ?? 0
        _selectedColumnIndex = State(initialValue: max(0, count - 1))
    }

    private var columns: [String] {
        snapshot.tables["madeplayoffs"]?.columns
            ?? snapshot.tables.values.first?.columns
            ?? []
    }

    private var activeMetrics: [PredictionMetric] {
        metricOrder.compactMap { key in
            guard snapshot.tables[key] != nil else { return nil }
            return snapshot.metrics.first { $0.key == key }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            dateStepper

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(
                    x: proxy.size.width / 2,
                    y: proxy.size.height / 2
                )
                let outerRadius = max(40, side * 0.46)
                let innerRadius = outerRadius * 0.23

                ZStack {
                    Canvas { context, _ in
                        drawRings(
                            context: &context,
                            center: center,
                            outerRadius: outerRadius,
                            innerRadius: innerRadius
                        )
                    }

                    ForEach(outerRingSlices) { slice in
                        let ringWidth = activeMetrics.isEmpty
                            ? (outerRadius - innerRadius)
                            : (outerRadius - innerRadius) / CGFloat(activeMetrics.count)
                        let outerRingInner = max(innerRadius, outerRadius - ringWidth + 2)
                        let radius = outerRingInner
                            + 0.62 * (outerRadius - outerRingInner)
                        let radians = slice.midAngle * .pi / 180
                        let x = center.x + radius * cos(radians)
                        let y = center.y + radius * sin(radians)
                        let arcLength = CGFloat(slice.extent * .pi / 180) * radius
                        let logoSize = min(
                            horizontalSizeClass == .compact ? 27 : 34,
                            max(15, arcLength * 0.68)
                        )

                        if arcLength >= 15 {
                            PredictionPieLogo(team: slice.team)
                                .frame(width: logoSize, height: logoSize)
                                .position(x: x, y: y)
                                .help(
                                    "\(slice.team.name) — \(slice.value.formatted(.percent.precision(.fractionLength(1))))"
                                )
                        }
                    }

                    AsyncImage(url: snapshot.cupURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        default:
                            Image(systemName: "trophy.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(
                        width: innerRadius * 0.9,
                        height: innerRadius * 1.45
                    )
                    .position(x: center.x, y: center.y)
                }
            }
            .frame(height: horizontalSizeClass == .compact ? 310 : 430)

            Text("Outer → inner: Playoffs · Round 2 · Conf. Finals · Cup Final · Win Cup")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: snapshot.generatedAt) { _, _ in
            selectedColumnIndex = max(0, columns.count - 1)
        }
    }

    private var dateStepper: some View {
        HStack(spacing: 16) {
            Button {
                selectedColumnIndex = max(0, selectedColumnIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(selectedColumnIndex <= 0)

            VStack(spacing: 2) {
                Text("Probability Rings")
                    .font(.headline)
                Text(displayDate(selectedColumn))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 150)

            Button {
                selectedColumnIndex = min(
                    max(0, columns.count - 1),
                    selectedColumnIndex + 1
                )
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(columns.isEmpty || selectedColumnIndex >= columns.count - 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedColumn: String {
        guard columns.indices.contains(selectedColumnIndex) else { return "" }
        return columns[selectedColumnIndex]
    }

    private var orderedTeams: [PredictionTeam] {
        let lookup = Dictionary(uniqueKeysWithValues: snapshot.teams.map { ($0.code, $0) })
        let order = [
            "NYR", "CAR", "CBJ", "NJD", "NYI", "PHI", "PIT", "WSH",
            "BOS", "BUF", "DET", "FLA", "MTL", "OTT", "TBL", "TOR",
            "ANA", "CGY", "EDM", "LAK", "SEA", "SJS", "VAN", "VGK",
            "CHI", "COL", "DAL", "MIN", "NSH", "STL", "WPG", "UTA",
        ]
        let ordered = order.compactMap { lookup[$0] }
        let used = Set(ordered.map(\.code))
        return ordered + snapshot.teams
            .filter { !used.contains($0.code) }
            .sorted { $0.name < $1.name }
    }

    private var outerRingSlices: [PredictionRingSlice] {
        slices(for: "madeplayoffs")
    }

    private func slices(for metricKey: String) -> [PredictionRingSlice] {
        guard let table = snapshot.tables[metricKey],
              table.columns.indices.contains(selectedColumnIndex) else {
            return []
        }

        let values: [(PredictionTeam, Double)] = orderedTeams.compactMap { team in
            guard let value = table.value(
                teamCode: team.code,
                columnIndex: selectedColumnIndex
            ), value > 0 else {
                return nil
            }
            return (team, value)
        }

        let total = values.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }

        var start = -90.0
        return values.map { team, value in
            let extent = 360.0 * value / total
            let slice = PredictionRingSlice(
                team: team,
                value: value,
                startAngle: start,
                extent: extent
            )
            start += extent
            return slice
        }
    }

    private func drawRings(
        context: inout GraphicsContext,
        center: CGPoint,
        outerRadius: CGFloat,
        innerRadius: CGFloat
    ) {
        guard !activeMetrics.isEmpty else { return }
        let ringWidth = (outerRadius - innerRadius) / CGFloat(activeMetrics.count)
        let gap: CGFloat = 2

        for (metricIndex, metric) in activeMetrics.enumerated() {
            let ringOuter = outerRadius - CGFloat(metricIndex) * ringWidth
            let ringInner = max(innerRadius, ringOuter - ringWidth + gap)

            for slice in slices(for: metric.key) {
                let path = annularSector(
                    center: center,
                    innerRadius: ringInner,
                    outerRadius: ringOuter,
                    startDegrees: slice.startAngle,
                    endDegrees: slice.startAngle + slice.extent
                )
                let base = Color(hex: slice.team.colorHex)
                let tint = 0.92 - Double(metricIndex) * 0.08
                context.fill(path, with: .color(base.opacity(max(0.56, tint))))
            }
        }
    }

    private func annularSector(
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startDegrees: Double,
        endDegrees: Double
    ) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(endDegrees),
            endAngle: .degrees(startDegrees),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func displayDate(_ raw: String) -> String {
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              let startYear = Int(snapshot.season.prefix(4)) else {
            return raw
        }

        let year = month >= 7 ? startYear : startYear + 1
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day

        guard let date = components.date else { return raw }
        return date.formatted(
            .dateTime
                .day()
                .month(.abbreviated)
                .year()
                .locale(Locale(identifier: "en_GB"))
        )
    }
}

private struct PredictionRingSlice: Identifiable {
    let team: PredictionTeam
    let value: Double
    let startAngle: Double
    let extent: Double

    var id: String { team.code }
    var midAngle: Double { startAngle + extent / 2 }
}

private struct PredictionPieLogo: View {
    let team: PredictionTeam

    var body: some View {
        AsyncImage(url: team.logoURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Image(systemName: "hockey.puck.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
