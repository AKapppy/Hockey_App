import Foundation

actor PredictionDataService {
    private let baseURL: URL
    private let season: String
    private let client: APIClient

    init(
        baseURL: URL = URL(string: "https://akapppy.github.io/Hockey_App/")!,
        season: String = "2026-2027",
        client: APIClient = APIClient()
    ) {
        self.baseURL = baseURL
        self.season = season
        self.client = client
    }

    func fetchSnapshot() async throws -> PredictionSnapshot {
        var request = APIRequest(
            path: "seasons/\(season)/data.json"
        )

        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.headers["Cache-Control"] = "no-cache, no-store, max-age=0"
        request.headers["Pragma"] = "no-cache"

        request.queryItems = [
            URLQueryItem(
                name: "predictions_v",
                value: UUID().uuidString
            )
        ]

        let export = try await client.send(
            request,
            baseURL: baseURL,
            as: PredictionExport.self
        )

        return export.makeSnapshot(
            baseURL: baseURL,
            fallbackSeason: season
        )
    }
}

private nonisolated struct PredictionExport: Decodable, Sendable {
    let metadata: Metadata
    let metrics: [Metric]
    let teams: [TeamRow]
    let tables: [String: Table]

    nonisolated struct Metadata: Decodable, Sendable {
        let season: String
        let generatedAt: Date
        let predictions: PredictionStatus?
    }

    nonisolated struct PredictionStatus: Decodable, Sendable {
        let status: String?
        let error: String?
    }

    nonisolated struct Metric: Decodable, Sendable {
        let key: String
        let label: String
        let title: String
    }

    nonisolated struct TeamRow: Decodable, Sendable {
        let code: String
        let name: String
        let division: String?
        let conference: String?
        let logo: String?
        let sortValue: Double?
    }

    nonisolated struct Table: Decodable, Sendable {
        let columns: [String]
        let rows: [String: [Double?]]
    }

    func makeSnapshot(
        baseURL: URL,
        fallbackSeason: String
    ) -> PredictionSnapshot {
        let mappedMetrics = metrics.map {
            PredictionMetric(
                key: $0.key,
                label: $0.label,
                title: $0.title
            )
        }

        let mappedTeams = teams.map { team in
            PredictionTeam(
                code: team.code,
                name: team.name,
                division: team.division ?? "",
                conference: team.conference ?? "",
                logoURL: team.logo.flatMap {
                    URL(string: $0, relativeTo: baseURL)?.absoluteURL
                },
                sortValue: team.sortValue ?? 0
            )
        }

        let mappedTables = tables.mapValues {
            PredictionTable(
                columns: $0.columns,
                rows: $0.rows
            )
        }

        return PredictionSnapshot(
            generatedAt: metadata.generatedAt,
            season: metadata.season.isEmpty ? fallbackSeason : metadata.season,
            status: metadata.predictions?.status ?? "unknown",
            errorMessage: metadata.predictions?.error,
            metrics: mappedMetrics,
            teams: mappedTeams,
            tables: mappedTables
        )
    }
}
