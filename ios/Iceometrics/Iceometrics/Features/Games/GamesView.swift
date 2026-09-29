import SwiftUI

struct GamesView: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        Group {
            if viewModel.games.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "hockey.puck",
                    description: Text(
                        "No games are present in the current snapshot."
                    )
                )
            } else {
                List(viewModel.games) { game in
                    GameRowView(game: game)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle("Games")
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}
