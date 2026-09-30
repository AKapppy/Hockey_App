import Foundation
import Combine

@MainActor
final class StatsViewModel: ObservableObject {
    @Published private(set) var snapshot: StatsSnapshot?
    @Published private(set) var playerStats: [StatsPhase: PlayerStatsSnapshot] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadingPlayerPhases: Set<StatsPhase> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var playerErrorMessage: String?

    private let service: StatsDataService
    private let playerService: PlayerStatsService
    private var hasLoaded = false

    init(
        service: StatsDataService = StatsDataService(),
        playerService: PlayerStatsService = PlayerStatsService()
    ) {
        self.service = service
        self.playerService = playerService
    }

    var updatedText: String {
        guard let generatedAt = snapshot?.generatedAt else {
            return "Not updated yet"
        }
        return "Updated \(generatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    func refresh() async {
        playerStats = [:]
        playerErrorMessage = nil
        await load()
    }

    func loadPlayers(for phase: StatsPhase, force: Bool = false) async {
        guard let snapshot else { return }
        if !force, playerStats[phase] != nil { return }
        if loadingPlayerPhases.contains(phase) { return }

        loadingPlayerPhases.insert(phase)
        playerErrorMessage = nil
        defer { loadingPlayerPhases.remove(phase) }

        do {
            playerStats[phase] = try await playerService.fetch(
                season: snapshot.season,
                phase: phase
            )
        } catch {
            playerErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await service.fetchSnapshot()
            snapshot = loaded
            await loadPlayers(for: loaded.defaultPhase)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
