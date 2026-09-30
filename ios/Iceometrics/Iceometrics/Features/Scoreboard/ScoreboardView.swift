import SwiftUI

struct ScoreboardView: View {
    @ObservedObject var viewModel: HomeViewModel

    @State private var selectedDate = Date()
    @State private var showingCalendar = false
    @State private var selectedInitialDate = false
    @State private var moneyPuckPredictions: [String: MoneyPuckGamePrediction] = [:]
    @State private var selectedGame: HockeyGame?

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
                            Button {
                                selectedGame = game
                            } label: {
                                ScoreboardCardView(
                                    game: game,
                                    prediction: moneyPuckPredictions[game.id]
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Open game details")
                        }
                    }
                }

                HStack(spacing: 8) {
                    DataStatusView(
                        state: viewModel.loadState,
                        origin: viewModel.origin
                    )

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(viewModel.lastUpdatedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                        await loadMoneyPuckPredictions()
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

            if calendar.isDateInToday(selectedDate) {
                await viewModel.refresh()
                await loadMoneyPuckPredictions()
            }
        }
        .task(id: pollingDateKey) {
            await runAdaptiveLivePolling()
        }
        .task(id: selectedDatePredictionKey) {
            await loadMoneyPuckPredictions()
        }
        .task(id: livePredictionRefreshKey) {
            guard gamesForSelectedDate.contains(where: { $0.status == .live }) else {
                return
            }

            while !Task.isCancelled {
                await loadMoneyPuckPredictions()
                do {
                    try await Task.sleep(for: .seconds(20))
                } catch {
                    return
                }
            }
        }
        .onChange(of: viewModel.snapshot?.generatedAt) { _, _ in
            selectInitialDateIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
            await loadMoneyPuckPredictions()
        }
        .popover(isPresented: $showingCalendar) {
            ScoreboardCalendarPicker(
                selectedDate: $selectedDate,
                availableRange: availableRange
            )
        }
        .sheet(item: $selectedGame) { game in
            #if os(iOS)
            NavigationStack {
                GameDetailView(
                    game: game,
                    prediction: moneyPuckPredictions[game.id],
                    allGames: viewModel.games
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #else
            NavigationStack {
                GameDetailView(
                    game: game,
                    prediction: moneyPuckPredictions[game.id],
                    allGames: viewModel.games
                )
            }
            .frame(
                minWidth: 720,
                idealWidth: 860,
                minHeight: 620,
                idealHeight: 780
            )
            #endif
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
                    ViewThatFits(in: .horizontal) {
                        dateHeaderText(
                            format: "EEEE d MMMM yyyy",
                            fixedWidth: true
                        )
                        dateHeaderText(
                            format: "EEE d MMMM yyyy",
                            fixedWidth: true
                        )
                        dateHeaderText(
                            format: "EEE d MMM yyyy",
                            fixedWidth: false
                        )
                    }
                    .frame(maxWidth: .infinity)

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

    private var pollingDateKey: String {
        "poll-\(selectedDatePredictionKey)"
    }

    @ViewBuilder
    private func dateHeaderText(
        format: String,
        fixedWidth: Bool
    ) -> some View {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = calendar
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format

        return Text(formatter.string(from: selectedDate))
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(fixedWidth ? 1.0 : 0.75)
            .fixedSize(horizontal: fixedWidth, vertical: false)
    }

    private var selectedDatePredictionKey: String {
        let parts = calendar.dateComponents(
            [.year, .month, .day],
            from: selectedDate
        )
        let dateKey = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
        let snapshotKey = viewModel.snapshot?.generatedAt.timeIntervalSince1970 ?? 0
        return "\(dateKey)-\(snapshotKey)"
    }

    private var livePredictionRefreshKey: String {
        let liveIDs = gamesForSelectedDate
            .filter { $0.status == .live }
            .map(\.id)
            .sorted()
            .joined(separator: ",")
        return "\(selectedDatePredictionKey)-\(liveIDs)"
    }

    private func loadMoneyPuckPredictions() async {
        let games = gamesForSelectedDate.filter {
            $0.status == .scheduled || $0.status == .live
        }
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
    private enum LiveRefreshCadence {
        case fiveSeconds
        case thirtySeconds
        case nextMinute
        case nextTenMinutes
        case nextHour
        case stopped
    }

    private func runAdaptiveLivePolling() async {
        guard calendar.isDateInToday(selectedDate) else {
            return
        }

        while !Task.isCancelled {
            let now = Date()

            let cadence = liveRefreshCadence(
                for: gamesForSelectedDate,
                now: now
            )

            guard let delay = delayForCadence(
                cadence,
                from: now
            ) else {
                return
            }

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  calendar.isDateInToday(selectedDate) else {
                return
            }

            await viewModel.refreshLiveGames()

            // Don't hammer the pregame MoneyPuck predictions page every five
            // seconds during live play. Live MoneyPuck game probabilities are
            // handled separately.
            switch cadence {
            case .fiveSeconds, .thirtySeconds:
                break

            case .nextMinute,
                 .nextTenMinutes,
                 .nextHour:
                await loadMoneyPuckPredictions()

            case .stopped:
                return
            }
        }
    }

    private func liveRefreshCadence(
        for games: [HockeyGame],
        now: Date
    ) -> LiveRefreshCadence {
        guard calendar.isDateInToday(selectedDate) else {
            return .stopped
        }

        // True off-day.
        guard !games.isEmpty else {
            return .nextHour
        }

        let liveGames = games.filter {
            $0.status == .live
        }

        // A game counts as actively playing only after the puck has actually
        // dropped. This avoids treating "1st · 20:00" as active play.
        let activelyPlayingGames = liveGames.filter { game in
            hasPuckDropped(in: game) &&
            game.isIntermission != true
        }

        // If even one game is actively being played, use the fastest cadence.
        if !activelyPlayingGames.isEmpty {
            return .fiveSeconds
        }

        // Games that have genuinely started, but are currently between periods.
        let startedLiveGames = liveGames.filter {
            hasPuckDropped(in: $0)
        }

        if !startedLiveGames.isEmpty,
           startedLiveGames.allSatisfy({ $0.isIntermission == true }) {
            return .thirtySeconds
        }

        // Scheduled time has arrived/passed, but NHL has not shown an actual
        // puck drop yet. Check on each minute boundary.
        let waitingForPuckDrop = games.contains { game in
            let hasNotDropped =
                game.status == .scheduled ||
                (game.status == .live && !hasPuckDropped(in: game))

            return hasNotDropped &&
                game.startTime <= now
        }

        if waitingForPuckDrop {
            return .nextMinute
        }

        // Find the next game that has not begun.
        let nextGameStart = games
            .filter { game in
                game.status == .scheduled ||
                (game.status == .live && !hasPuckDropped(in: game))
            }
            .map(\.startTime)
            .filter { $0 > now }
            .min()

        if let nextGameStart {
            let timeUntilGame = nextGameStart.timeIntervalSince(now)

            // Within one hour of scheduled start, check every ten minutes.
            if timeUntilGame <= 60 * 60 {
                return .nextTenMinutes
            }

            // Game is still more than an hour away.
            return .nextHour
        }

        // Everything for today is final/postponed, so there is nothing left
        // that needs live polling.
        let dayIsFinished = games.allSatisfy { game in
            game.status == .final ||
            game.status == .postponed
        }

        if dayIsFinished {
            return .stopped
        }

        return .nextHour
    }

    private func hasPuckDropped(
        in game: HockeyGame
    ) -> Bool {
        guard game.status == .live else {
            return false
        }

        // If we're in an intermission, the game obviously started already.
        if game.isIntermission == true {
            return true
        }

        guard let period = game.periodNumber else {
            return false
        }

        // Any period after the first means play has unquestionably started.
        if period > 1 {
            return true
        }

        guard period == 1,
              let remainingSeconds = clockSeconds(
                from: game.timeRemaining
              ) else {
            return false
        }

        // NHL can mark a game live before the opening faceoff while the
        // scoreboard still reads 20:00. Only switch to five-second polling
        // once the first-period clock actually moves.
        return remainingSeconds < 20 * 60
    }

    private func clockSeconds(
        from clock: String?
    ) -> Int? {
        guard let clock else {
            return nil
        }

        let parts = clock
            .split(separator: ":")
            .compactMap { Int($0) }

        guard parts.count == 2 else {
            return nil
        }

        return (parts[0] * 60) + parts[1]
    }

    private func delayForCadence(
        _ cadence: LiveRefreshCadence,
        from now: Date
    ) -> TimeInterval? {
        switch cadence {
        case .fiveSeconds:
            return 5

        case .thirtySeconds:
            return 30

        case .nextMinute:
            return delayUntilNextMinute(from: now)

        case .nextTenMinutes:
            return delayUntilNextTenMinuteBoundary(from: now)

        case .nextHour:
            return delayUntilNextHour(from: now)

        case .stopped:
            return nil
        }
    }

    private func delayUntilNextMinute(
        from date: Date
    ) -> TimeInterval {
        let second = calendar.component(
            .second,
            from: date
        )

        return TimeInterval(
            max(1, 60 - second)
        )
    }

    private func delayUntilNextTenMinuteBoundary(
        from date: Date
    ) -> TimeInterval {
        let minute = calendar.component(
            .minute,
            from: date
        )

        let second = calendar.component(
            .second,
            from: date
        )

        let minutesIntoBlock = minute % 10
        let minutesRemaining = 9 - minutesIntoBlock

        return TimeInterval(
            max(
                1,
                (minutesRemaining * 60) +
                (60 - second)
            )
        )
    }

    private func delayUntilNextHour(
        from date: Date
    ) -> TimeInterval {
        let minute = calendar.component(
            .minute,
            from: date
        )

        let second = calendar.component(
            .second,
            from: date
        )

        return TimeInterval(
            max(
                1,
                ((59 - minute) * 60) +
                (60 - second)
            )
        )
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
