from __future__ import annotations

import datetime as dt
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from hockey_app.data.cache import DiskCache
from hockey_app.data.nhl_api import NHLApi
from hockey_app.domain.seasons import season_date_ranges, season_rule, supported_seasons
from hockey_app.domain.teams import nhl_team_identity, nhl_team_names
from hockey_app.runtime.public_predictions import TeamState, RemainingGame, _estimate_team_strengths, _regular_game_probs
from hockey_app.services.simulations import compile_probability_tables, date_from_filename
from hockey_app.services.baselines import previous_regular_season_baseline
from hockey_app.tools.backtest_public_model import score_predictions
from hockey_app.runtime.public_predictions import PUBLIC_MODEL_PARAMS, PUBLIC_MODEL_VERSION
from hockey_app.domain.postseason import actual_last_played_postseason_game, condition_probabilities, terminal_outcomes
from hockey_app.services.simulations import append_terminal_outcome
from hockey_app.ui.tabs.team_stats import _postseason_team_codes
from hockey_app.ui.tabs.points import _extend_frozen_regular_values
import pandas as pd


class ThirdPassTests(unittest.TestCase):
    def test_switching_never_shrinks_supported_choices(self):
        expected = ["2026-2027", "2025-2026", "2024-2025", "2023-2024"]
        for selected in expected:
            with patch.dict("os.environ", {"HOCKEY_SEASON": selected}):
                self.assertEqual(supported_seasons(today=dt.date(2026, 9, 11)), expected)

    def test_completed_historical_ranges_are_deterministic(self):
        expected = {
            "2023-2024": (dt.date(2023, 9, 23), dt.date(2024, 6, 24), dt.date(2024, 4, 18)),
            "2024-2025": (dt.date(2024, 9, 21), dt.date(2025, 6, 17), dt.date(2025, 4, 17)),
        }
        with tempfile.TemporaryDirectory() as td, patch.dict("os.environ", {"HOCKEY_CACHE_DIR": td}):
            api = NHLApi(DiskCache(Path(td)))
            for season, (start, end, reg_end) in expected.items():
                ranges = season_date_ranges(season, observed_on=dt.date(2026, 1, 1))
                self.assertEqual(ranges["schedule"], (start, end))
                probe = dt.date(int(season[-4:]), 1, 15)
                bounds = api.get_season_boundaries(probe)
                self.assertEqual(bounds.last_scheduled_game, end)
                self.assertEqual(bounds.regular_end, reg_end)
                self.assertEqual(season_rule("NHL", season)["total_games"], 1312)

    def test_historical_nhl_identity(self):
        self.assertEqual(nhl_team_identity("2023-2024", "ARI")["displayName"], "Arizona Coyotes")
        self.assertNotIn("UTA", nhl_team_names("2023-2024"))
        self.assertEqual(nhl_team_identity("2024-2025", "UTA")["displayName"], "Utah Hockey Club")
        self.assertEqual(nhl_team_identity("2025-2026", "UTA")["displayName"], "Utah Mammoth")
        self.assertTrue((Path(__file__).parents[1] / "hockey_app/assets/nhl_logos/ARI.png").exists())

    def test_previous_regular_season_baseline_fields(self):
        row = {"teamAbbrev": {"default": "BOS"}, "leagueSequence": 1, "conferenceSequence": 1,
               "divisionSequence": 1, "points": 120, "pointPctg": .732}
        with tempfile.TemporaryDirectory() as td, patch.dict("os.environ", {"HOCKEY_CACHE_DIR": td}), \
             patch("hockey_app.services.baselines.NHLApi.standings", return_value={"standings": [row]}):
            result = previous_regular_season_baseline("2026-2027")
            self.assertEqual(result["prior_season"], "2025-2026")
            self.assertEqual(result["teams"]["BOS"]["overall_rank"], 1)
            self.assertEqual(result["teams"]["BOS"]["point_percentage"], .732)

    def test_moneypuck_filename_variants_scenario_and_no_backfill(self):
        self.assertEqual(date_from_filename("x_20260704.csv"), dt.date(2026, 7, 4))
        self.assertEqual(date_from_filename("x_2026-07-05.csv"), dt.date(2026, 7, 5))
        with tempfile.TemporaryDirectory() as td:
            Path(td, "sim_20260704.csv").write_text("scenario,teamCode,madePlayoffs\nALL,BOS,0.6\n", encoding="utf-8")
            tables = compile_probability_tables(Path(td), dt.date(2026, 7, 1), dt.date(2026, 7, 6),
                metrics={"madeplayoffs": "madePlayoffs"}, canon_team_code=lambda c: c)
            row = tables["madeplayoffs"].loc["BOS"]
            self.assertTrue(row.iloc[:3].isna().all())
            self.assertTrue((row.iloc[3:] == 0.6).all())

    def test_prediction_prior_fades_and_future_date_has_no_decay(self):
        teams = {"BOS": TeamState("BOS", "East", "Atlantic", prior_strength=1.0),
                 "NYR": TeamState("NYR", "East", "Metro", prior_strength=-1.0)}
        _estimate_team_strengths(teams)
        self.assertEqual(teams["BOS"].strength, 1.0)
        near = _regular_game_probs(RemainingGame(1, dt.date.today(), "BOS", "NYR", 0), teams)[0]
        far = _regular_game_probs(RemainingGame(2, dt.date.today() + dt.timedelta(days=100), "BOS", "NYR", 100), teams)[0]
        self.assertEqual(near, far)
        teams["BOS"].games_played = 24; teams["BOS"].points = 24
        teams["NYR"].games_played = 24; teams["NYR"].points = 24
        _estimate_team_strengths(teams)
        self.assertAlmostEqual(teams["BOS"].strength, 0.5, places=6)

    def test_trained_model_version_and_scoring(self):
        self.assertEqual(PUBLIC_MODEL_VERSION, "nhl-elo-prior-v7")
        self.assertEqual(PUBLIC_MODEL_PARAMS["k"], 12.0)
        report = score_predictions([(0.8, 1), (0.2, 0)])
        self.assertAlmostEqual(report["brier"], .04)
        self.assertGreater(report["log_loss"], 0)

    def test_2025_26_actual_end_and_prediction_calendar(self):
        ranges = season_date_ranges("2025-2026", observed_on=dt.date(2026, 9, 1))
        self.assertEqual(ranges["schedule"][1], dt.date(2026, 6, 14))
        self.assertEqual(ranges["terminal_predictions"][0], dt.date(2026, 6, 15))
        self.assertEqual(ranges["moneypuck"], (dt.date(2025, 9, 1), dt.date(2026, 6, 30)))

    def test_actual_last_game_ignores_unused_conditional_game(self):
        rows = [{"id": "2025030411", "gameType": 3, "gameDate": "2026-06-14", "gameState": "FINAL",
                 "awayTeam": {"abbrev": "EDM", "score": 1}, "homeTeam": {"abbrev": "FLA", "score": 4}},
                {"id": "2025030417", "gameType": 3, "gameDate": "2026-06-17", "gameState": "FUT",
                 "awayTeam": {"abbrev": "FLA"}, "homeTeam": {"abbrev": "EDM"}}]
        self.assertEqual(actual_last_played_postseason_game(rows), dt.date(2026, 6, 14))

    def test_terminal_outcomes_and_provider_snapshot_are_binary(self):
        rows = []
        for rnd, loser, winner in ((1, "A", "B"), (2, "B", "C"), (3, "C", "D"), (4, "D", "E")):
            for game in range(4):
                rows.append({"id": f"2025030{rnd}{game+1}", "gameType": 3, "playoff_round": rnd,
                             "date": dt.date(2026, 4 + rnd // 2, 1 + game), "state": "FINAL",
                             "away": loser, "home": winner, "away_score": 1, "home_score": 2})
        outcomes = terminal_outcomes(rows, ["A", "B", "C", "D", "E", "X"])
        self.assertTrue(all(value in {0.0, 1.0} for team in outcomes.values() for value in team.values()))
        self.assertEqual(outcomes["E"]["cup"], 1.0)
        base = {key: pd.DataFrame({"6/14": [.4]}, index=["A"]) for key in ("madeplayoffs", "round2", "round3", "round4", "woncup")}
        append_terminal_outcome(base, dt.date(2026, 6, 15), outcomes)
        self.assertTrue(all(set(frame["6/15"].dropna()).issubset({0.0, 1.0}) for frame in base.values()))
        self.assertTrue(all(frame.attrs["column_sources"]["6/15"] == "final_result" for frame in base.values()))

    def test_completed_seasons_have_binary_terminal_fallbacks(self):
        from hockey_app.runtime.public_predictions import terminal_snapshot_for_season
        with tempfile.TemporaryDirectory() as td, patch.dict("os.environ", {"HOCKEY_CACHE_DIR": td}):
            for season, expected in (("2023-2024", dt.date(2024, 6, 25)), ("2024-2025", dt.date(2025, 6, 18))):
                day, outcomes = terminal_snapshot_for_season(season)
                self.assertEqual(day, expected)
                self.assertEqual(sum(v["make_playoffs"] for v in outcomes.values()), 16)
                self.assertEqual(sum(v["cup"] for v in outcomes.values()), 1)
                self.assertTrue(all(x in {0.0, 1.0} for values in outcomes.values() for x in values.values()))

    def test_postseason_team_stats_keep_all_participants(self):
        active = [f"T{i:02d}" for i in range(20)]
        games = [{"awayTeam": {"abbrev": active[i]}, "homeTeam": {"abbrev": active[i+1]}}
                 for i in range(0, 16, 2)]
        participants = _postseason_team_codes("NHL", games, active)
        self.assertEqual(len(participants), 16)
        self.assertNotIn("T19", participants)

    def test_regular_points_freeze_through_postseason_timeline(self):
        frame = pd.DataFrame({"4/17": [100.0]}, index=["BOS"])
        out = _extend_frozen_regular_values(frame, dt.date(2025, 4, 17), dt.date(2025, 6, 17))
        self.assertEqual(out.columns[-1], "6/17")
        self.assertEqual(out.iloc[0, -1], 100.0)
        self.assertEqual(out.attrs["postseason_semantics"], "frozen_regular_season_value")


if __name__ == "__main__":
    unittest.main()
