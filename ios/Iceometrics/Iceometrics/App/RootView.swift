import SwiftUI

struct RootView: View {
    @ObservedObject var homeViewModel: HomeViewModel

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(viewModel: homeViewModel)
            }
            .tabItem {
                Label("Overview", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                GamesView(viewModel: homeViewModel)
            }
            .tabItem {
                Label("Games", systemImage: "hockey.puck.fill")
            }
        }
    }
}

#Preview {
    RootView(
        homeViewModel: HomeViewModel(
            repository: PreviewRepository()
        )
    )
}

private actor PreviewRepository: HockeyRepositoryProtocol {
    func loadSnapshot(forceRefresh: Bool) async throws -> LoadedSnapshot {
        LoadedSnapshot(
            snapshot: SampleData.snapshot,
            origin: .fixture
        )
    }
}
