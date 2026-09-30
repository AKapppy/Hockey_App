import Foundation
import Combine

@MainActor
final class PredictionsViewModel: ObservableObject {
    @Published private(set) var snapshot: PredictionSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: PredictionDataService
    private var hasLoaded = false

    init(service: PredictionDataService = PredictionDataService()) {
        self.service = service
    }

    var metrics: [PredictionMetric] {
        snapshot?.metrics ?? []
    }

    var updatedText: String {
        guard let generatedAt = snapshot?.generatedAt else {
            return "Not updated yet"
        }

        return "Updated \(generatedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var sourceStatusText: String {
        guard let snapshot else {
            return "MoneyPuck"
        }

        switch snapshot.status.lowercased() {
        case "available":
            return "MoneyPuck • Available"
        case "stale":
            return "MoneyPuck • Stale"
        case "unavailable":
            return "MoneyPuck • Unavailable"
        default:
            return "MoneyPuck"
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    func refresh() async {
        await load()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await service.fetchSnapshot()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
