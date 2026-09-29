import Foundation

nonisolated struct LiveHockeyDataService: HockeyDataService {
    private let client: APIClient
    private let baseURL: URL
    private let snapshotPath: String

    init(
        client: APIClient = APIClient(),
        baseURL: URL,
        snapshotPath: String
    ) {
        self.client = client
        self.baseURL = baseURL
        self.snapshotPath = snapshotPath
    }

    func fetchSnapshot() async throws -> AppSnapshot {
        try await client.send(
            APIRequest(path: snapshotPath),
            baseURL: baseURL,
            as: AppSnapshot.self
        )
    }
}
