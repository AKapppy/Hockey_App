import Foundation

nonisolated enum AppEnvironment {
    static func makeRepository() -> any HockeyRepositoryProtocol {
        let cache = CacheStore(
            filename: AppConfiguration.cacheFilename
        )

        switch AppConfiguration.dataMode {
        case .fixture:
            return HockeyRepository(
                service: FixtureHockeyDataService(),
                cache: cache,
                successfulFetchOrigin: .fixture
            )

        case .live(let baseURL):
            return HockeyRepository(
                service: LiveHockeyDataService(
                    baseURL: baseURL,
                    snapshotPath: AppConfiguration.liveSnapshotPath
                ),
                cache: cache,
                successfulFetchOrigin: .network
            )
        }
    }
}
