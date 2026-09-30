import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var snapshot: AppSnapshot?
    @Published private(set) var origin: SnapshotOrigin?
    @Published private(set) var liveUpdatedAt: Date?
    @Published private var liveGameOverrides: [String: HockeyGame] = [:]

    private let repository: any HockeyRepositoryProtocol
    private let liveScoreService: NHLLiveScoreService
    private var hasLoaded = false

    // Keep the full season indexed once. A five-second live refresh should only
    // touch today's handful of games, not rebuild/sort the entire season.
    private var baseGamesSorted: [HockeyGame] = []
    private var baseGamesByDay: [Date: [HockeyGame]] = [:]
    private var availableGameDatesCache: [Date] = []

    init(
        repository: any HockeyRepositoryProtocol,
        liveScoreService: NHLLiveScoreService = NHLLiveScoreService()
    ) {
        self.repository = repository
        self.liveScoreService = liveScoreService
    }

    var games: [HockeyGame] {
        guard !liveGameOverrides.isEmpty else {
            return baseGamesSorted
        }

        return baseGamesSorted.map { baseGame in
            liveGameOverrides[baseGame.id] ?? baseGame
        }
    }

    var nextGame: HockeyGame? {
        let now = Date()

        if let live = games.first(where: { $0.status == .live }) {
            return live
        }

        return games.first(where: {
            $0.status == .scheduled && $0.startTime >= now
        }) ?? games.first(where: { $0.status == .scheduled })
    }

    var availableGameDates: [Date] {
        availableGameDatesCache
    }

    func games(
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [HockeyGame] {
        let day = calendar.startOfDay(for: date)
        let baseGames = baseGamesByDay[day] ?? []

        guard !liveGameOverrides.isEmpty else {
            return baseGames
        }

        return baseGames.map { baseGame in
            liveGameOverrides[baseGame.id] ?? baseGame
        }
    }

    func nearestGameDate(
        to date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        let target = calendar.startOfDay(for: date)

        return availableGameDatesCache.min { lhs, rhs in
            abs(lhs.timeIntervalSince(target))
                < abs(rhs.timeIntervalSince(target))
        }
    }

    var liveGameCount: Int {
        games.lazy.filter { $0.status == .live }.count
    }

    var upcomingGameCount: Int {
        games.lazy.filter { $0.status == .scheduled }.count
    }

    var completedGameCount: Int {
        games.lazy.filter { $0.status == .final }.count
    }

    var lastUpdatedText: String {
        if let liveUpdatedAt {
            return "Live updated \(liveUpdatedAt.formatted(date: .omitted, time: .shortened))"
        }

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

    func refreshLiveGames() async {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())

        guard let todaysBaseGames = baseGamesByDay[today],
              !todaysBaseGames.isEmpty else {
            return
        }

        do {
            let response = try await liveScoreService.fetchScores(for: Date())
            guard !response.games.isEmpty else { return }

            let liveGamesByID = Dictionary(
                uniqueKeysWithValues: response.games.map {
                    (String($0.id), $0)
                }
            )

            var nextOverrides = liveGameOverrides
            var changed = false

            for baseGame in todaysBaseGames {
                guard let liveGame = liveGamesByID[baseGame.id] else {
                    continue
                }

                let currentGame = nextOverrides[baseGame.id] ?? baseGame
                let updatedGame = NHLLiveScoreOverlayAdapter.applying(
                    liveGame,
                    to: currentGame
                )

                guard updatedGame != currentGame else {
                    continue
                }

                nextOverrides[baseGame.id] = updatedGame
                changed = true
            }

            // If the NHL feed returned the same values as the previous poll,
            // don't publish anything. This avoids needless SwiftUI redraws on
            // five-second polling intervals.
            guard changed else { return }

            liveGameOverrides = nextOverrides
            liveUpdatedAt = Date()
        } catch {
            // The shared snapshot remains usable when the NHL live feed is
            // temporarily unavailable, so live-overlay failures are non-fatal.
        }
    }

    private func load(forceRefresh: Bool) async {
        loadState = .loading

        do {
            let result = try await repository.loadSnapshot(
                forceRefresh: forceRefresh
            )

            rebuildGameIndex(from: result.snapshot)
            liveGameOverrides = [:]
            liveUpdatedAt = nil

            snapshot = result.snapshot
            origin = result.origin

            loadState = result.snapshot.games.isEmpty
                ? .empty
                : .loaded

            await refreshLiveGames()
        } catch {
            loadState = .failed(
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            )
        }
    }

    private func rebuildGameIndex(from snapshot: AppSnapshot) {
        let calendar = Calendar.autoupdatingCurrent
        let sorted = snapshot.games.sorted {
            $0.startTime < $1.startTime
        }

        var grouped: [Date: [HockeyGame]] = [:]
        grouped.reserveCapacity(220)

        for game in sorted {
            let day = calendar.startOfDay(for: game.startTime)
            grouped[day, default: []].append(game)
        }

        baseGamesSorted = sorted
        baseGamesByDay = grouped
        availableGameDatesCache = grouped.keys.sorted()
    }
}
