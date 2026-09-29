import Foundation

nonisolated enum AppDataMode: Sendable {
    case fixture
    case sharedWebSnapshot(baseURL: URL, season: String)
    case live(baseURL: URL)
}

nonisolated enum AppConfiguration {
    static let dataMode: AppDataMode = .sharedWebSnapshot(
        baseURL: URL(string: "https://akapppy.github.io/Hockey_App/")!,
        season: "2026-2027"
    )

    static let liveSnapshotPath = "v1/snapshot"
    static let cacheFilename = "iceometrics-shared-scoreboard-v1.json"
}
