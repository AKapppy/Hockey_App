import Foundation

nonisolated protocol HockeyRepositoryProtocol: Sendable {
    func loadSnapshot(forceRefresh: Bool) async throws -> LoadedSnapshot
}

actor HockeyRepository: HockeyRepositoryProtocol {
    private let service: any HockeyDataService
    private let cache: CacheStore
    private let successfulFetchOrigin: SnapshotOrigin

    init(
        service: any HockeyDataService,
        cache: CacheStore,
        successfulFetchOrigin: SnapshotOrigin
    ) {
        self.service = service
        self.cache = cache
        self.successfulFetchOrigin = successfulFetchOrigin
    }

    func loadSnapshot(forceRefresh: Bool) async throws -> LoadedSnapshot {
        if !forceRefresh,
           let cached = try? await cache.load(AppSnapshot.self) {
            return LoadedSnapshot(snapshot: cached, origin: .cache)
        }

        do {
            let fresh = try await service.fetchSnapshot()
            try? await cache.save(fresh)

            return LoadedSnapshot(
                snapshot: fresh,
                origin: successfulFetchOrigin
            )
        } catch {
            if let cached = try? await cache.load(AppSnapshot.self) {
                return LoadedSnapshot(snapshot: cached, origin: .cache)
            }

            throw error
        }
    }
}
