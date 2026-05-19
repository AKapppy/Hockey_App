from __future__ import annotations

import datetime as dt
import unittest
from unittest.mock import patch

from hockey_app.domain.teams import TEAM_NAMES, TEAM_TO_CONF, TEAM_TO_DIV
from hockey_app.runtime.public_predictions import (
    TeamState,
    _build_sim_inputs,
    _run_monte_carlo,
    _series_key,
)


def _ranked_team_states() -> dict[str, TeamState]:
    points = {
        "CAR": 120,
        "PIT": 100,
        "PHI": 98,
        "WSH": 70,
        "NYR": 69,
        "NJD": 68,
        "NYI": 67,
        "CBJ": 66,
        "BUF": 110,
        "BOS": 105,
        "TBL": 103,
        "MTL": 95,
        "OTT": 94,
        "FLA": 60,
        "TOR": 59,
        "DET": 58,
        "COL": 118,
        "DAL": 104,
        "MIN": 97,
        "UTA": 96,
        "WPG": 80,
        "NSH": 79,
        "STL": 78,
        "CHI": 77,
        "VGK": 106,
        "EDM": 101,
        "ANA": 98,
        "LAK": 93,
        "VAN": 72,
        "CGY": 71,
        "SEA": 70,
        "SJS": 69,
    }
    out: dict[str, TeamState] = {}
    for code in TEAM_NAMES:
        pts = int(points.get(code, 50))
        out[code] = TeamState(
            code=code,
            conference=str(TEAM_TO_CONF.get(code, "")),
            division=str(TEAM_TO_DIV.get(code, "")),
            points=pts,
            rw=pts // 2,
            row=pts // 2,
            wins=pts // 2,
            goals_for=pts + 100,
            goals_against=100,
            goal_diff=pts,
            games_played=82,
            strength=float(pts) / 100.0,
        )
    return out


class PublicPredictionsPlayoffStateTests(unittest.TestCase):
    def test_playoff_games_do_not_count_as_regular_games_or_remaining_placeholders(self) -> None:
        rows = [
            {
                "id": 2025020001,
                "date": dt.date(2026, 4, 10),
                "state": "FINAL",
                "game_type": "2",
                "home": "BOS",
                "away": "TOR",
                "home_score": 4,
                "away_score": 2,
                "status_text": "",
            },
            {
                "id": 2025030111,
                "date": dt.date(2026, 4, 20),
                "state": "FINAL",
                "game_type": "3",
                "home": "CAR",
                "away": "OTT",
                "home_score": 5,
                "away_score": 1,
                "status_text": "",
            },
            {
                "id": 2025030117,
                "date": dt.date(2026, 5, 1),
                "state": "FUT",
                "game_type": "3",
                "home": "CAR",
                "away": "OTT",
                "home_score": 0,
                "away_score": 0,
                "status_text": "",
            },
        ]

        with patch("hockey_app.runtime.public_predictions._load_games_from_xml", return_value=rows):
            teams, remaining, _h2h_points, _h2h_games, started, scores = _build_sim_inputs(
                "2025-2026",
                dt.date(2026, 4, 21),
            )

        self.assertTrue(started)
        self.assertEqual(teams["BOS"].points, 2)
        self.assertEqual(teams["CAR"].points, 0)
        self.assertEqual(remaining, [])
        self.assertEqual(scores[_series_key("CAR", "OTT")]["CAR"], 1)

    def test_completed_playoff_series_locks_advancement_and_elimination(self) -> None:
        teams = _ranked_team_states()
        probs = _run_monte_carlo(
            teams,
            [],
            {},
            {},
            n_sims=40,
            seed=7,
            playoffs_started=True,
            playoff_series_scores={_series_key("CAR", "OTT"): {"CAR": 4, "OTT": 1}},
        )

        self.assertEqual(probs["CAR"]["make_playoffs"], 1.0)
        self.assertEqual(probs["CAR"]["round2"], 1.0)
        self.assertEqual(probs["OTT"]["make_playoffs"], 1.0)
        self.assertEqual(probs["OTT"]["round2"], 0.0)
        self.assertEqual(probs["FLA"]["make_playoffs"], 0.0)
        self.assertEqual(probs["FLA"]["cup"], 0.0)


if __name__ == "__main__":
    unittest.main()
