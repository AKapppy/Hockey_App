import Foundation

nonisolated struct PredictionSnapshot: Sendable {
    let generatedAt: Date
    let season: String
    let status: String
    let errorMessage: String?
    let metrics: [PredictionMetric]
    let teams: [PredictionTeam]
    let tables: [String: PredictionTable]
    let cupURL: URL?

    var hasData: Bool {
        tables.values.contains { !$0.columns.isEmpty && !$0.rows.isEmpty }
    }
}

nonisolated struct PredictionMetric: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    let title: String

    var id: String { key }
}

nonisolated struct PredictionTeam: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let division: String
    let conference: String
    let logoURL: URL?
    let colorHex: String
    let sortValue: Double

    var id: String { code }
}

nonisolated struct PredictionTable: Sendable {
    let columns: [String]
    let rows: [String: [Double?]]

    func value(teamCode: String, columnIndex: Int) -> Double? {
        guard columnIndex >= 0,
              let row = rows[teamCode],
              columnIndex < row.count else {
            return nil
        }

        return row[columnIndex]
    }

    func latestValue(teamCode: String) -> Double? {
        rows[teamCode]?.reversed().compactMap { $0 }.first
    }
}
