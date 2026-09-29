import Foundation

nonisolated struct APIClient: Sendable {
    func send<T: Decodable & Sendable>(
        _ request: APIRequest,
        baseURL: URL,
        as type: T.Type
    ) async throws -> T {
        let urlRequest = try request.makeURLRequest(baseURL: baseURL)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw IceometicsError.invalidResponse
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                throw IceometicsError.httpStatus(httpResponse.statusCode)
            }

            do {
                return try IceometicsJSON.decoder.decode(type, from: data)
            } catch {
                throw IceometicsError.decoding(error.localizedDescription)
            }
        } catch let error as IceometicsError {
            throw error
        } catch {
            throw IceometicsError.network(error.localizedDescription)
        }
    }
}
