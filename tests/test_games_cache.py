from __future__ import annotations

import datetime as dt
import shutil
import unittest
import uuid
from zoneinfo import ZoneInfo

from hockey_app.data.xml_cache import _status_time_sort_value, _xml_season_dir, read_games_day_xml, write_games_day_xml
from hockey_app.ui.tabs.games import (
    _game_sort_key,
    _is_effectively_final_game,
    _latest_final_game_day_from_rows,
    _live_status,
    _playoff_round_from_game,
    _playoff_series_wins_from_rows,
    _merge_games_by_id,
    _parse_status_time_local,
    _preserve_cached_game_rows,
    _promote_live_game_row_from_gamecenter,
    _should_hide_completed_playoff_series_game,
)


class GamesCachePreserveTests(unittest.TestCase):
    def test_preserves_missing_cached_league_rows_during_partial_render(self) -> None:
        current = [
            {"id": 326, "league": "PWHL", "awayTeam": {"abbrev": "MTL"}, "homeTeam": {"abbrev": "SEA"}},
        ]
        cached = [
            {"id": 2025030124, "league": "NHL", "awayTeam": {"abbrev": "BUF"}, "homeTeam": {"abbrev": "TBL"}},
            {"id": 326, "league": "PWHL", "awayTeam": {"abbrev": "MTL"}, "homeTeam": {"abbrev": "SEA"}},
        ]

        merged = _preserve_cached_game_rows(current, cached)

        self.assertEqual([g["id"] for g in merged], [326, 2025030124])
        self.assertEqual({str(g.get("league")) for g in merged}, {"PWHL", "NHL"})

    def test_status_text_time_parser_orders_half_hour_before_later_hour(self) -> None:
        tz = ZoneInfo("America/New_York")
        selected_date = dt.date(2026, 4, 25)
        game_1230 = {"statusText": "12:30 PM EDT"}
        game_2pm = {"statusText": "2 PM EDT"}

        t1 = _parse_status_time_local(game_1230, tz, selected_date)
        t2 = _parse_status_time_local(game_2pm, tz, selected_date)

        self.assertIsNotNone(t1)
        self.assertIsNotNone(t2)
        self.assertLess(t1, t2)

    def test_xml_status_sort_value_handles_hour_only_times(self) -> None:
        selected_date = dt.date(2026, 4, 25)

        first = _status_time_sort_value(selected_date, "12:30 PM EDT")
        second = _status_time_sort_value(selected_date, "2 PM EDT")

        self.assertTrue(first)
        self.assertTrue(second)
        self.assertLess(first, second)

    def test_pwhl_sort_key_uses_scheduled_start_not_live_status_text(self) -> None:
        tz = ZoneInfo("America/New_York")
        selected_date = dt.date(2026, 4, 25)
        early_live = {
            "id": 101,
            "league": "PWHL",
            "gameState": "LIVE",
            "startTimeUTC": "2026-04-25T17:00:00Z",
            "statusText": "3RD - 0:41",
            "awayTeam": {"abbrev": "MON"},
            "homeTeam": {"abbrev": "TOR"},
        }
        later_future = {
            "id": 102,
            "league": "PWHL",
            "gameState": "FUT",
            "startTimeUTC": "2026-04-25T19:00:00Z",
            "statusText": "7:00 PM EDT",
            "awayTeam": {"abbrev": "OTT"},
            "homeTeam": {"abbrev": "MIN"},
        }

        self.assertLess(
            _game_sort_key(early_live, tz, selected_date),
            _game_sort_key(later_future, tz, selected_date),
        )

    def test_pwhl_sort_key_does_not_fall_back_to_status_text_when_start_missing(self) -> None:
        tz = ZoneInfo("America/New_York")
        selected_date = dt.date(2026, 4, 25)
        missing_start = {
            "id": 201,
            "league": "PWHL",
            "statusText": "12:30 PM EDT",
            "awayTeam": {"abbrev": "MON"},
            "homeTeam": {"abbrev": "TOR"},
        }
        scheduled = {
            "id": 202,
            "league": "PWHL",
            "startTimeUTC": "2026-04-25T19:00:00Z",
            "statusText": "7:00 PM EDT",
            "awayTeam": {"abbrev": "OTT"},
            "homeTeam": {"abbrev": "MIN"},
        }

        self.assertGreater(
            _game_sort_key(missing_start, tz, selected_date),
            _game_sort_key(scheduled, tz, selected_date),
        )

    def test_merge_games_by_id_prefers_parseable_scheduled_start(self) -> None:
        merged = _merge_games_by_id(
            [
                {
                    "id": 210,
                    "league": "PWHL",
                    "startTimeUTC": "TBD",
                    "statusText": "Final",
                    "awayTeam": {"abbrev": "NY"},
                    "homeTeam": {"abbrev": "BOS"},
                }
            ],
            [
                {
                    "id": 210,
                    "league": "PWHL",
                    "startTimeUTC": "2026-04-25T17:00:00Z",
                    "statusText": "1:00 PM EDT",
                    "awayTeam": {"abbrev": "NY"},
                    "homeTeam": {"abbrev": "BOS"},
                }
            ],
        )

        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].get("startTimeUTC"), "2026-04-25T17:00:00Z")

    def test_xml_round_trip_preserves_live_clock_period_and_shots(self) -> None:
        season = f"test-live-{uuid.uuid4().hex}"
        day = dt.date(2026, 4, 25)
        try:
            write_games_day_xml(
                season=season,
                day=day,
                games=[
                    {
                        "id": 2026020001,
                        "league": "NHL",
                        "gameState": "LIVE",
                        "statusText": "Live",
                        "clock": {"timeRemaining": "12:34"},
                        "periodDescriptor": {"number": 2},
                        "awayTeam": {"abbrev": "BUF", "score": 2, "shotsOnGoal": 22},
                        "homeTeam": {"abbrev": "TBL", "score": 1, "shotsOnGoal": 18},
                    }
                ],
            )

            rows = read_games_day_xml(season=season, day=day)

            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual(row.get("clock"), {"timeRemaining": "12:34"})
            self.assertEqual(row.get("periodDescriptor"), {"number": 2})
            self.assertEqual(row.get("awayTeam", {}).get("shotsOnGoal"), 22)
            self.assertEqual(row.get("homeTeam", {}).get("shotsOnGoal"), 18)
            self.assertEqual(_live_status(row), "2ND - 12:34")
        finally:
            shutil.rmtree(_xml_season_dir(season), ignore_errors=True)

    def test_promotes_live_gamecenter_fields_for_cached_rerender(self) -> None:
        game = {
            "id": 2026020001,
            "gameState": "LIVE",
            "statusText": "Live",
            "awayTeam": {"abbrev": "BUF", "score": 2},
            "homeTeam": {"abbrev": "TBL", "score": 1},
        }
        boxscore = {
            "awayTeam": {"sog": 25},
            "homeTeam": {"shotsOnGoal": 19},
        }
        pbp = {
            "gameState": "LIVE",
            "clock": {"timeRemaining": "8:41"},
            "periodDescriptor": {"number": 3},
            "plays": [],
        }

        out = _promote_live_game_row_from_gamecenter(game, boxscore=boxscore, pbp=pbp)

        self.assertEqual(out.get("awayTeam", {}).get("shotsOnGoal"), 25)
        self.assertEqual(out.get("homeTeam", {}).get("shotsOnGoal"), 19)
        self.assertEqual(out.get("clock"), {"timeRemaining": "8:41"})
        self.assertEqual(out.get("periodDescriptor"), {"number": 3})
        self.assertEqual(_live_status(out), "3RD - 8:41")

    def test_live_gamecenter_promotion_preserves_score_feed_clock(self) -> None:
        game = {
            "id": 2026020001,
            "gameState": "LIVE",
            "statusText": "Live",
            "clock": {"timeRemaining": "5:12"},
            "periodDescriptor": {"number": 2},
            "awayTeam": {"abbrev": "BUF", "score": 2},
            "homeTeam": {"abbrev": "TBL", "score": 1},
        }
        pbp = {
            "gameState": "LIVE",
            "clock": {"timeRemaining": "8:41"},
            "periodDescriptor": {"number": 3},
            "plays": [],
        }

        out = _promote_live_game_row_from_gamecenter(game, pbp=pbp)

        self.assertEqual(out.get("clock"), {"timeRemaining": "5:12"})
        self.assertEqual(out.get("periodDescriptor"), {"number": 2})
        self.assertEqual(_live_status(out), "2ND - 5:12")

    def test_live_gamecenter_promotion_does_not_downgrade_official_final(self) -> None:
        game = {
            "id": 2026020001,
            "gameState": "FINAL",
            "statusText": "Final/OT",
            "awayTeam": {"abbrev": "BUF", "score": 3},
            "homeTeam": {"abbrev": "TBL", "score": 4},
        }
        pbp = {
            "gameState": "LIVE",
            "clock": {"timeRemaining": "0:00"},
            "periodDescriptor": {"number": 4, "periodType": "OT"},
            "plays": [],
        }

        out = _promote_live_game_row_from_gamecenter(game, pbp=pbp)

        self.assertEqual(out.get("gameState"), "FINAL")
        self.assertTrue(_is_effectively_final_game(out))

    def test_final_status_text_wins_before_regulation_override(self) -> None:
        game = {
            "gameState": "LIVE",
            "statusText": "Final/OT",
            "periodDescriptor": {"number": 4, "periodType": "OT"},
            "awayTeam": {"abbrev": "BUF", "score": 3},
            "homeTeam": {"abbrev": "TBL", "score": 4},
        }

        self.assertTrue(_is_effectively_final_game(game))

    def test_completed_playoff_series_hides_unplayed_if_necessary_game(self) -> None:
        game = {
            "id": 2025030126,
            "gameType": 3,
            "gameState": "FUT",
            "awayTeam": {"abbrev": "OTT", "score": 0},
            "homeTeam": {"abbrev": "BOS", "score": 0},
        }

        hide = _should_hide_completed_playoff_series_game(
            game,
            {("BOS", "OTT"): {"BOS": 4, "OTT": 1}},
        )

        self.assertTrue(hide)

    def test_incomplete_playoff_series_keeps_scheduled_game(self) -> None:
        game = {
            "id": 2025030125,
            "gameType": 3,
            "gameState": "FUT",
            "awayTeam": {"abbrev": "OTT", "score": 0},
            "homeTeam": {"abbrev": "BOS", "score": 0},
        }

        hide = _should_hide_completed_playoff_series_game(
            game,
            {("BOS", "OTT"): {"BOS": 3, "OTT": 1}},
        )

        self.assertFalse(hide)

    def test_completed_playoff_series_keeps_actual_final_game(self) -> None:
        game = {
            "id": 2025030125,
            "gameType": 3,
            "gameState": "FINAL",
            "awayTeam": {"abbrev": "OTT", "score": 1},
            "homeTeam": {"abbrev": "BOS", "score": 4},
        }

        hide = _should_hide_completed_playoff_series_game(
            game,
            {("BOS", "OTT"): {"BOS": 4, "OTT": 1}},
        )

        self.assertFalse(hide)

    def test_latest_final_game_day_ignores_future_and_nonfinal_rows(self) -> None:
        rows_by_day = {
            dt.date(2026, 4, 29): [
                {"gameState": "FINAL", "awayTeam": {"score": 2}, "homeTeam": {"score": 1}},
            ],
            dt.date(2026, 5, 1): [
                {"gameState": "FUT", "awayTeam": {"score": 0}, "homeTeam": {"score": 0}},
            ],
            dt.date(2026, 4, 30): [
                {"gameState": "OFF", "awayTeam": {"score": 4}, "homeTeam": {"score": 3}},
            ],
        }

        self.assertEqual(_latest_final_game_day_from_rows(rows_by_day), dt.date(2026, 4, 30))

    def test_playoff_round_is_inferred_from_nhl_game_id(self) -> None:
        self.assertEqual(_playoff_round_from_game({"id": 2025030111, "gameType": 3}), 1)
        self.assertEqual(_playoff_round_from_game({"id": 2025030242, "gameType": 3}), 2)

    def test_playoff_series_wins_are_round_specific(self) -> None:
        rows = [
            {
                "id": 2025030111,
                "gameType": 3,
                "gameState": "FINAL",
                "awayTeam": {"abbrev": "BUF", "score": 4},
                "homeTeam": {"abbrev": "BOS", "score": 3},
            },
            {
                "id": 2025030211,
                "gameType": 3,
                "gameState": "FUT",
                "awayTeam": {"abbrev": "MTL", "score": 0},
                "homeTeam": {"abbrev": "BUF", "score": 0},
            },
            {
                "id": 2025030212,
                "gameType": 3,
                "gameState": "FINAL",
                "awayTeam": {"abbrev": "MTL", "score": 2},
                "homeTeam": {"abbrev": "BUF", "score": 5},
            },
        ]

        round_two = _playoff_series_wins_from_rows(rows, round_no=2)

        self.assertEqual(round_two.get(("BUF", "MTL")), {"MTL": 0, "BUF": 1})
        self.assertNotIn(("BOS", "BUF"), round_two)


if __name__ == "__main__":
    unittest.main()
