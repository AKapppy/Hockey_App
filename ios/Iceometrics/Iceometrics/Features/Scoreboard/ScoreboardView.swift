import SwiftUI

struct ScoreboardView: View {
    @ObservedObject var viewModel: HomeViewModel

    @State private var selectedDate = Date()
    @State private var showingCalendar = false
    @State private var selectedInitialDate = false
    @State private var moneyPuckPredictions: [String: MoneyPuckGamePrediction] = [:]

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 16)
    ]

    private var gamesForSelectedDate: [HockeyGame] {
        viewModel.games(on: selectedDate, calendar: calendar)
    }

    private var availableRange: ClosedRange<Date> {
        guard let first = viewModel.availableGameDates.first,
              let last = viewModel.availableGameDates.last else {
            let day = calendar.startOfDay(for: selectedDate)
            return day...day
        }

        return first...last
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                dateHeader

                HStack(alignment: .firstTextBaseline) {
                    Text("NHL")
                        .font(.headline)

                    Spacer()

                    if !gamesForSelectedDate.isEmpty {
                        Text(gameCountText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if gamesForSelectedDate.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(gamesForSelectedDate) { game in
                            if game.status == .final {
                                NavigationLink {
                                    GameDetailView(game: game)
                                } label: {
                                    ScoreboardCardView(
                                        game: game,
                                        prediction: moneyPuckPredictions[game.id]
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                ScoreboardCardView(
                                    game: game,
                                    prediction: moneyPuckPredictions[game.id]
                                )
                            }
                        }
                    }
                }

                DataStatusView(
                    state: viewModel.loadState,
                    origin: viewModel.origin
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("Scoreboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.loadState == .loading)
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            selectInitialDateIfNeeded()
        }
        .task(id: selectedDatePredictionKey) {
            await loadMoneyPuckPredictions()
        }
        .onChange(of: viewModel.snapshot?.generatedAt) { _, _ in
            selectInitialDateIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .popover(isPresented: $showingCalendar) {
            ScoreboardCalendarPicker(
                selectedDate: $selectedDate,
                availableRange: availableRange
            )
        }
    }

    private var dateHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button {
                    moveDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDay(by: -1))
                .accessibilityLabel("Previous day")

                VStack(spacing: 3) {
                    Text(
                        selectedDate.formatted(
                            .dateTime
                                .weekday(.wide)
                                .month(.wide)
                                .day()
                                .year()
                        )
                    )
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)

                    if calendar.isDateInToday(selectedDate) {
                        Text("Today")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                Button {
                    moveDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDay(by: 1))
                .accessibilityLabel("Next day")
            }

            HStack(spacing: 10) {
                Button {
                    showingCalendar = true
                } label: {
                    Label("Choose Date", systemImage: "calendar")
                }
                .buttonStyle(.bordered)

                if !calendar.isDateInToday(selectedDate),
                   isTodayInsideSchedule {
                    Button("Today") {
                        selectedDate = calendar.startOfDay(for: Date())
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Games",
            systemImage: "hockey.puck",
            description: Text("There are no NHL games scheduled for this date.")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var gameCountText: String {
        let count = gamesForSelectedDate.count
        return "\(count) \(count == 1 ? "game" : "games")"
    }

    private var isTodayInsideSchedule: Bool {
        let today = calendar.startOfDay(for: Date())
        return availableRange.contains(today)
    }

    private func moveDay(by amount: Int) {
        guard let date = calendar.date(
            byAdding: .day,
            value: amount,
            to: selectedDate
        ) else { return }

        selectedDate = calendar.startOfDay(for: date)
    }

    private func canMoveDay(by amount: Int) -> Bool {
        guard let date = calendar.date(
            byAdding: .day,
            value: amount,
            to: selectedDate
        ) else { return false }

        return availableRange.contains(calendar.startOfDay(for: date))
    }

    private var selectedDatePredictionKey: String {
        let parts = calendar.dateComponents(
            [.year, .month, .day],
            from: selectedDate
        )
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    private func loadMoneyPuckPredictions() async {
        let games = gamesForSelectedDate.filter { $0.status == .scheduled }
        guard !games.isEmpty else {
            moneyPuckPredictions = [:]
            return
        }

        do {
            moneyPuckPredictions = try await MoneyPuckPredictionService()
                .fetchPredictions(
                    for: selectedDate,
                    games: games
                )
        } catch {
            moneyPuckPredictions = [:]
        }
    }

    private func selectInitialDateIfNeeded() {
        guard !selectedInitialDate,
              let nearest = viewModel.nearestGameDate(
                to: Date(),
                calendar: calendar
              ) else { return }

        selectedDate = nearest
        selectedInitialDate = true
    }
}

private struct ScoreboardCalendarPicker: View {
    @Binding var selectedDate: Date
    let availableRange: ClosedRange<Date>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a Date")
                .font(.headline)

            DatePicker(
                "Game date",
                selection: $selectedDate,
                in: availableRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
