import Foundation

nonisolated enum SnapshotOrigin: String, Equatable, Sendable {
    case fixture = "Fixture"
    case network = "Live"
    case cache = "Cached"
}

nonisolated struct LoadedSnapshot: Sendable {
    let snapshot: AppSnapshot
    let origin: SnapshotOrigin
}
