import Foundation

nonisolated protocol HockeyDataService: Sendable {
    func fetchSnapshot() async throws -> AppSnapshot
}
