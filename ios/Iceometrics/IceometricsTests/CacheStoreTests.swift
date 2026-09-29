import Foundation
import Testing
@testable import Iceometrics

struct CacheStoreTests {
    @Test
    func cacheRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let cache = CacheStore(
            filename: "snapshot.json",
            baseDirectory: directory
        )

        let snapshot = AppSnapshot(
            generatedAt: Date(
                timeIntervalSince1970: 1_700_000_000
            ),
            source: "Cache test",
            games: [],
            standings: []
        )

        try await cache.save(snapshot)
        let loaded = try await cache.load(AppSnapshot.self)

        #expect(loaded == snapshot)

        try await cache.clear()
    }
}
