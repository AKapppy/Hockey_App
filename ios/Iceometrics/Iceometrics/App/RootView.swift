import SwiftUI

struct RootView: View {
    @ObservedObject var homeViewModel: HomeViewModel

    var body: some View {
        TabView {
            NavigationStack {
                ScoreboardView(viewModel: homeViewModel)
            }
            .tabItem {
                Label("Scoreboard", systemImage: "hockey.puck.fill")
            }

            NavigationStack {
                FeaturePlaceholderView(
                    title: "Stats",
                    systemImage: "chart.bar.xaxis",
                    message: "Team, game, and player stats will live here."
                )
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                FeaturePlaceholderView(
                    title: "Predictions",
                    systemImage: "chart.line.uptrend.xyaxis",
                    message: "MoneyPuck prediction views are coming next."
                )
            }
            .tabItem {
                Label("Predictions", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                FeaturePlaceholderView(
                    title: "Predictions 2",
                    systemImage: "percent",
                    message: "The second predictions workspace will be added here."
                )
            }
            .tabItem {
                Label("Predictions 2", systemImage: "percent")
            }

            NavigationStack {
                FeaturePlaceholderView(
                    title: "Models",
                    systemImage: "function",
                    message: "Playoff picture and model outputs will be added here."
                )
            }
            .tabItem {
                Label("Models", systemImage: "function")
            }

            NavigationStack {
                FeaturePlaceholderView(
                    title: "Labs",
                    systemImage: "flask.fill",
                    message: "Experimental Iceometrics tools will live here."
                )
            }
            .tabItem {
                Label("Labs", systemImage: "flask.fill")
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
