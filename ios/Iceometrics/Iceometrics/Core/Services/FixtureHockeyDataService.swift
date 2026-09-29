import Foundation

nonisolated struct FixtureHockeyDataService: HockeyDataService {
    func fetchSnapshot() async throws -> AppSnapshot {
        SampleData.snapshot
    }
}
