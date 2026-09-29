import Foundation

nonisolated enum AppDataMode: Sendable {
    case fixture
    case live(baseURL: URL)
}

nonisolated enum AppConfiguration {
    static let dataMode: AppDataMode = .fixture
    static let liveSnapshotPath = "v1/snapshot"
    static let cacheFilename = "iceometics-app-snapshot.json"
}
