import Foundation
import Testing
@testable import Iceometics

@MainActor
struct HomeViewModelTests {
    @Test
    func loadsSnapshot() async {
        let game = HockeyGame(
            id: "test-game",
            startTime: .now,
            status: .scheduled,
            awayTeam: Team(
                id: "a",
                abbreviation: "AAA",
                name: "Away",
                logoURL: nil
            ),
            homeTeam: Team(
                id: "h",
                abbreviation: "HHH",
                name: "Home",
                logoURL: nil
            ),
            awayScore: nil,
            homeScore: nil,
            venue: nil
        )

        let repository = MockRepository(
            result: LoadedSnapshot(
                snapshot: AppSnapshot(
                    generatedAt: .now,
                    source: "Test",
                    games: [game]
                ),
                origin: .fixture
            )
        )

        let viewModel = HomeViewModel(
            repository: repository
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.loadState == .loaded)
        #expect(viewModel.games.count == 1)
        #expect(viewModel.origin == .fixture)
    }
}

private actor MockRepository: HockeyRepositoryProtocol {
    let result: LoadedSnapshot

    init(result: LoadedSnapshot) {
        self.result = result
    }

    func loadSnapshot(
        forceRefresh: Bool
    ) async throws -> LoadedSnapshot {
        result
    }
}
