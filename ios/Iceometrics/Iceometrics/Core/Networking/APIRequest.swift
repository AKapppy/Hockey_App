import Foundation

nonisolated struct APIRequest {
    let path: String
    var method: HTTPMethod = .get
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy

    func makeURLRequest(baseURL: URL) throws -> URLRequest {
        let targetURL = baseURL.appendingPathComponent(path)

        guard var components = URLComponents(
            url: targetURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw IceometicsError.invalidURL
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw IceometicsError.invalidURL
        }

        var request = URLRequest(
            url: url,
            cachePolicy: cachePolicy,
            timeoutInterval: 30
        )
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}
