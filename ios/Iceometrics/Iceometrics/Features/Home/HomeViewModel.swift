import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var snapshot: AppSnapshot?
    @Published private(set) var origin: SnapshotOrigin?

    private let repository: any HockeyRepositoryProtocol
    private var hasLoaded = false

    init(repository: any HockeyRepositoryProtocol) {
        self.repository = repository
    }

    var games: [HockeyGame] {
        snapshot?.games.sorted {
            $0.startTime < $1.startTime
        } ?? []
    }

    var liveGameCount: Int {
        snapshot?.liveGames.count ?? 0
    }

    var upcomingGameCount: Int {
        snapshot?.upcomingGames.count ?? 0
    }

    var completedGameCount: Int {
        snapshot?.completedGames.count ?? 0
    }

    var lastUpdatedText: String {
        guard let generatedAt = snapshot?.generatedAt else {
            return "Not updated yet"
        }

        return "Updated \(generatedAt.iceometicsShortDateTime)"
    }

    var sourceText: String {
        snapshot?.source ?? "No source loaded"
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load(forceRefresh: false)
    }

    func refresh() async {
        await load(forceRefresh: true)
    }

    private func load(forceRefresh: Bool) async {
        loadState = .loading

        do {
            let result = try await repository.loadSnapshot(
                forceRefresh: forceRefresh
            )

            snapshot = result.snapshot
            origin = result.origin

            loadState = result.snapshot.games.isEmpty
                ? .empty
                : .loaded
        } catch {
            loadState = .failed(
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            )
        }
    }
}
