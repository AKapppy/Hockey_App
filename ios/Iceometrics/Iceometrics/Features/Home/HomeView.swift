import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 130))
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "hockey.puck.fill")
                            .font(.system(size: 34))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Iceometics")
                                .font(.title.bold())

                            Text("Hockey, measured.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text(viewModel.lastUpdatedText)
                        .font(.subheadline)

                    Text(viewModel.sourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DataStatusView(
                        state: viewModel.loadState,
                        origin: viewModel.origin
                    )
                }
                .padding(.vertical, 6)
            }

            Section("Snapshot") {
                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(
                        title: "Live",
                        value: "\(viewModel.liveGameCount)",
                        systemImage: "dot.radiowaves.left.and.right"
                    )

                    MetricCard(
                        title: "Upcoming",
                        value: "\(viewModel.upcomingGameCount)",
                        systemImage: "calendar"
                    )

                    MetricCard(
                        title: "Completed",
                        value: "\(viewModel.completedGameCount)",
                        systemImage: "checkmark.circle"
                    )
                }
                .padding(.vertical, 4)
            }

            if let first = viewModel.nextGame {
                Section("Next on the board") {
                    GameRowView(game: first)
                }
            }
        }
        .navigationTitle("Overview")
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.loadState == .loading,
               viewModel.snapshot == nil {
                ProgressView("Loading Iceometics…")
            }
        }
    }
}
