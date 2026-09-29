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

    var nextGame: HockeyGame? {
        if let live = snapshot?.liveGames
            .sorted(by: { $0.startTime < $1.startTime })
            .first {
            return live
        }

        let now = Date()
        return snapshot?.upcomingGames.first(where: {
            $0.startTime >= now
        }) ?? snapshot?.upcomingGames.first
    }

    var availableGameDates: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let days = games.map {
            calendar.startOfDay(for: $0.startTime)
        }

        return Array(Set(days)).sorted()
    }

    func games(
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [HockeyGame] {
        games.filter {
            calendar.isDate($0.startTime, inSameDayAs: date)
        }
    }

    func nearestGameDate(
        to date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let target = calendar.startOfDay(for: date)

        return availableGameDates.min { lhs, rhs in
            abs(lhs.timeIntervalSince(target))
                < abs(rhs.timeIntervalSince(target))
        }
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
