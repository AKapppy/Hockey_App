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


if __name__ == "__main__":
    unittest.main()
