import Foundation

actor CacheStore {
    private let fileURL: URL

    init(filename: String, baseDirectory: URL? = nil) {
        let directory: URL

        if let baseDirectory {
            directory = baseDirectory
        } else {
            directory = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
        }

        fileURL = directory.appendingPathComponent(filename)
    }

    func save<T: Encodable & Sendable>(_ value: T) throws {
        do {
            let parent = fileURL.deletingLastPathComponent()

            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )

            let data = try IceometicsJSON.encoder.encode(value)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw IceometicsError.cache(error.localizedDescription)
        }
    }

    func load<T: Decodable & Sendable>(_ type: T.Type) throws -> T? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try IceometicsJSON.decoder.decode(type, from: data)
        } catch {
            throw IceometicsError.cache(error.localizedDescription)
        }
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw IceometicsError.cache(error.localizedDescription)
        }
    }
}
