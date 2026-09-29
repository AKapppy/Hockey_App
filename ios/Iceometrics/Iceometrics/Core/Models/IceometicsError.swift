import Foundation

nonisolated enum IceometicsError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case decoding(String)
    case noData
    case network(String)
    case cache(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Iceometics could not build the requested URL."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let code):
            return "The server returned HTTP \(code)."
        case .decoding(let message):
            return "Iceometics could not understand the returned data. \(message)"
        case .noData:
            return "No hockey data is available."
        case .network(let message):
            return "Network request failed. \(message)"
        case .cache(let message):
            return "The local cache could not be read or written. \(message)"
        }
    }
}
