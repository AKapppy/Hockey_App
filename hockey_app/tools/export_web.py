from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import re
from pathlib import Path
from typing import Any

import pandas as pd

from hockey_app.data.paths import espn_dir, pwhl_dir, sims_dir
from hockey_app.data.cache import DiskCache
from hockey_app.data.espn_api import ESPNApi
from hockey_app.data.nhl_api import NHLApi
from hockey_app.data.pwhl_api import PWHLApi
from hockey_app.data.paths import nhl_dir
from hockey_app.data.xml_cache import (
    read_game_stats_xml,
    read_games_day_xml,
    read_player_stats_xml,
    read_table_xml,
    read_team_stats_xml,
    write_games_day_xml,
    write_table_xml,
)
from hockey_app.domain.colors import build_team_color_map, theme_adjusted_line_color
from hockey_app.domain.teams import TEAM_NAMES, TEAM_TO_CONF, TEAM_TO_DIV, canon_team_code
from hockey_app.services.simulations import (
    compile_probability_tables,
    date_from_filename,
    download_missing_simulations,
)
from hockey_app.ui.tabs.models_data import (
    points_snapshot,
    regular_season_reference_day,
    standings_tiebreak_snapshot,
)
from hockey_app.ui.tabs.models_playoff_math import (
    live_playoff_series_probabilities,
    series_probability_table,
    team_strength_snapshot,
)
from hockey_app.ui.tabs.models_playoff_picture import (
    _bracket_snapshot,
    _pick_bracket_winner,
    _series_score_snapshot,
    _sorted_codes,
    _wildcard_columns_snapshot,
    playoff_status_map,
)

METRICS: dict[str, str] = {
    "madeplayoffs": "madePlayoffs",
    "round2": "round2",
    "round3": "round3",
    "round4": "round4",
    "woncup": "wonCup",
}

METRIC_LABELS: dict[str, str] = {
    "madeplayoffs": "Make Playoffs",
    "round2": "Make Round 2",
    "round3": "Make Conference Final",
    "round4": "Make Cup Final",
    "woncup": "Win Cup",
}

METRIC_TITLES: dict[str, str] = {
    "madeplayoffs": "Playoff Race",
    "round2": "Round 2",
    "round3": "Conference Final",
    "round4": "Cup Final",
    "woncup": "Stanley Cup",
}

HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; HockeyAppWebExporter/1.0)"}
URL_SIMULATIONS = "https://moneypuck.com/moneypuck/simulations/"
DATA_SCRIPT_RE = re.compile(r'<script\s+src="data\.js(?:\?v=[^"]*)?"></script>')


def _default_season(today: dt.date | None = None) -> str:
    d = today or dt.date.today()
    y0 = d.year if d.month >= 10 else d.year - 1
    return f"{y0}-{y0 + 1}"


def _season_start(season: str) -> dt.date:
    try:
        y0 = int(str(season).split("-", 1)[0])
    except Exception:
        y0 = dt.date.today().year
    return dt.date(y0, 10, 1)


def _parse_date(value: str | None) -> dt.date | None:
    if not value:
        return None
    return dt.date.fromisoformat(value)


def _csv_dates(path: Path) -> list[dt.date]:
    dates: list[dt.date] = []
    for csv_path in sorted(path.glob("*.csv")):
        file_date = date_from_filename(csv_path.name)
        if file_date is not None:
            dates.append(file_date)
    return sorted(set(dates))


def _ensure_writable(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    probe = path / ".write-test"
    probe.write_text("ok", encoding="utf-8")
    probe.unlink(missing_ok=True)


def _frame_to_rows(df: pd.DataFrame) -> dict[str, list[float | None]]:
    rows: dict[str, list[float | None]] = {}
    for team_code, row in df.iterrows():
        values: list[float | None] = []
        for value in row.tolist():
            if pd.isna(value):
                values.append(None)
            else:
                values.append(round(float(value), 4))
        rows[str(team_code)] = values
    return rows


def _df_payload(df: pd.DataFrame | None) -> dict[str, Any] | None:
    if not isinstance(df, pd.DataFrame) or df.empty:
        return None
    return {
        "columns": [str(col) for col in df.columns],
        "rows": _frame_to_rows(df),
    }


def _dates_for_df_columns(start: dt.date, end: dt.date, columns: list[str]) -> list[dt.date]:
    by_label: dict[str, dt.date] = {}
    for day in _date_range(start, end):
        by_label.setdefault(f"{day.month}/{day.day}", day)
    out: list[dt.date] = []
    for idx, col in enumerate(columns):
        fallback = start + dt.timedelta(days=idx)
        out.append(by_label.get(str(col), fallback if fallback <= end else end))
    return out


def _jsonable(value: Any) -> Any:
    if isinstance(value, (dt.date, dt.datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(_jsonable(k)): _jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_jsonable(v) for v in value]
    if isinstance(value, tuple):
        return [_jsonable(v) for v in value]
    if isinstance(value, float):
        if pd.isna(value):
            return None
        return round(float(value), 6)
    return value


def _series_scores_json(series_scores: dict[tuple[str, str], dict[str, int]]) -> dict[str, dict[str, int]]:
    return {
        "|".join(sorted((str(a), str(b)))): {str(code): int(total) for code, total in wins.items()}
        for (a, b), wins in sorted(series_scores.items())
    }


def _round_pairs(teams: list[str], count: int = 4) -> list[list[str]]:
    seeded = [str(teams[idx]) if idx < len(teams) else "" for idx in range(count * 2)]
    return [[seeded[idx], seeded[idx + 1]] for idx in range(0, len(seeded), 2)]


def _desktop_bracket_export(
    teams: list[str],
    *,
    pts: dict[str, float],
    series_scores: dict[tuple[str, str], dict[str, int]],
    team_strength: dict[str, float],
    live_series_probs: dict[tuple[str, str], dict[str, Any]],
) -> dict[str, Any]:
    round1 = _round_pairs(teams)
    r1_winners = [
        _pick_bracket_winner(a, b, pts, series_scores, team_strength, live_series_probs)
        for a, b in round1
    ]
    round2 = [[r1_winners[0], r1_winners[1]], [r1_winners[2], r1_winners[3]]]
    r2_winners = [
        _pick_bracket_winner(a, b, pts, series_scores, team_strength, live_series_probs)
        for a, b in round2
    ]
    final = [r2_winners[0], r2_winners[1]]
    champion = _pick_bracket_winner(final[0], final[1], pts, series_scores, team_strength, live_series_probs)
    return {
        "round1": round1,
        "round2": round2,
        "final": final,
        "champion": champion,
    }


def _series_table_export(
    a: str,
    b: str,
    *,
    team_strength: dict[str, float],
    series_scores: dict[tuple[str, str], dict[str, int]],
    live_series_probs: dict[tuple[str, str], dict[str, Any]],
) -> dict[str, Any] | None:
    if not a or not b:
        return None
    return _jsonable(
        series_probability_table(
            a,
            b,
            team_strength=team_strength,
            series_scores=series_scores,
            live_series_probs=live_series_probs,
        )
    )


def _pairwise_probability_export(
    teams: list[str],
    *,
    team_strength: dict[str, float],
    series_scores: dict[tuple[str, str], dict[str, int]],
    live_series_probs: dict[tuple[str, str], dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[str]]:
    rows: list[dict[str, Any]] = []
    winners: list[str] = []
    for idx in range(0, len(teams), 2):
        a = teams[idx] if idx < len(teams) else ""
        b = teams[idx + 1] if idx + 1 < len(teams) else ""
        row = _series_table_export(
            a,
            b,
            team_strength=team_strength,
            series_scores=series_scores,
            live_series_probs=live_series_probs,
        )
        if row is None:
            continue
        rows.append(row)
        winners.append(str(row.get("winner") or ""))
    return rows, winners


def _playoff_probability_rounds_export(
    west_r1: list[str],
    east_r1: list[str],
    *,
    team_strength: dict[str, float],
    series_scores: dict[tuple[str, str], dict[str, int]],
    live_series_probs: dict[tuple[str, str], dict[str, Any]],
) -> list[dict[str, Any]]:
    rounds: list[dict[str, Any]] = []
    r1_w, w_winners = _pairwise_probability_export(
        west_r1,
        team_strength=team_strength,
        series_scores=series_scores,
        live_series_probs=live_series_probs,
    )
    r1_e, e_winners = _pairwise_probability_export(
        east_r1,
        team_strength=team_strength,
        series_scores=series_scores,
        live_series_probs=live_series_probs,
    )
    if r1_w or r1_e:
        rounds.append({"title": "Round 1", "series": r1_w + r1_e})
    r2_w, w2 = _pairwise_probability_export(
        w_winners,
        team_strength=team_strength,
        series_scores=series_scores,
        live_series_probs=live_series_probs,
    )
    r2_e, e2 = _pairwise_probability_export(
        e_winners,
        team_strength=team_strength,
        series_scores=series_scores,
        live_series_probs=live_series_probs,
    )
    if r2_w or r2_e:
        rounds.append({"title": "Round 2", "series": r2_w + r2_e})
    cf_w, w3 = _pairwise_probability_export(
        w2,
        team_strength=team_strength,
        series_scores=series_scores,
        live_series_probs=live_series_probs,
    )
    cf_e, e3 = _pairwise_probability_export(
        e2,
        team_strength=team_strength,
        series_scores=series_scores,
        live_series_probs=live_series_probs,
    )
    if cf_w or cf_e:
        rounds.append({"title": "Conference Finals", "series": cf_w + cf_e})
    cup, _w4 = _pairwise_probability_export(
        w3 + e3,
        team_strength=team_strength,
        series_scores=series_scores,
        live_series_probs=live_series_probs,
    )
    if cup:
        rounds.append({"title": "Stanley Cup Final", "series": cup})
    return rounds


def _export_playoff_models(
    *,
    points_df: pd.DataFrame | None,
    start: dt.date,
    end: dt.date,
    league: str = "NHL",
) -> dict[str, Any]:
    if points_df is None or points_df.empty:
        return {
            "playoffPicture": {"columns": [], "snapshots": []},
            "playoffWinProbabilities": {"columns": [], "snapshots": []},
        }

    columns = [str(col) for col in points_df.columns]
    picture_snapshots: list[dict[str, Any] | None] = []
    probability_snapshots: list[dict[str, Any] | None] = []
    column_dates = _dates_for_df_columns(start, end, columns)
    latest_idx = len(column_dates) - 1
    for idx, day in enumerate(column_dates):
        # Keep Actions refreshes fast: the desktop-backed tabs need the current
        # matchup/probability source of truth, while older slider dates can use
        # the lightweight web fallback.
        if idx != latest_idx:
            picture_snapshots.append(None)
            probability_snapshots.append(None)
            continue
        seed_day = regular_season_reference_day(day, league=league)
        pts = points_snapshot(points_df, seed_day)
        if not pts:
            picture_snapshots.append(None)
            probability_snapshots.append(None)
            continue
        standings = standings_tiebreak_snapshot(seed_day) if str(league or "NHL").upper() == "NHL" else {}
        bracket_seed = _bracket_snapshot(pts, standings)
        series_scores = _series_score_snapshot(day, league=league)
        team_strength = team_strength_snapshot(day, league=league)
        live_series_probs = live_playoff_series_probabilities(day, league=league)
        status = playoff_status_map(day, pts, standings, league=league, series_scores=series_scores)
        west_r1 = [str(code) for code in bracket_seed.get("West_R1", []) if str(code or "").strip()]
        east_r1 = [str(code) for code in bracket_seed.get("East_R1", []) if str(code or "").strip()]
        west_bracket = _desktop_bracket_export(
            west_r1,
            pts=pts,
            series_scores=series_scores,
            team_strength=team_strength,
            live_series_probs=live_series_probs,
        )
        east_bracket = _desktop_bracket_export(
            east_r1,
            pts=pts,
            series_scores=series_scores,
            team_strength=team_strength,
            live_series_probs=live_series_probs,
        )
        picture_snapshots.append(
            {
                "day": day.isoformat(),
                "seedDay": seed_day.isoformat(),
                "mode": "NHL (Divisional)",
                "points": {str(code): round(float(value), 4) for code, value in pts.items()},
                "standings": {
                    "league": _sorted_codes(list(pts.keys()), pts, standings, scope="league"),
                    "columns": _wildcard_columns_snapshot(pts, standings),
                    "status": status,
                },
                "seriesScores": _series_scores_json(series_scores),
                "brackets": {
                    "west": west_bracket,
                    "east": east_bracket,
                },
                "cup": {
                    "final": [west_bracket.get("champion", ""), east_bracket.get("champion", "")],
                    "champion": _pick_bracket_winner(
                        str(west_bracket.get("champion") or ""),
                        str(east_bracket.get("champion") or ""),
                        pts,
                        series_scores,
                        team_strength,
                        live_series_probs,
                    ),
                },
            }
        )
        probability_snapshots.append(
            {
                "day": day.isoformat(),
                "seedDay": seed_day.isoformat(),
                "rounds": _playoff_probability_rounds_export(
                    west_r1,
                    east_r1,
                    team_strength=team_strength,
                    series_scores=series_scores,
                    live_series_probs=live_series_probs,
                ),
            }
        )

    return {
        "playoffPicture": {
            "columns": columns,
            "snapshots": picture_snapshots,
        },
        "playoffWinProbabilities": {
            "columns": columns,
            "snapshots": probability_snapshots,
        },
    }


def _latest_value(table: dict[str, list[float | None]], team_code: str) -> float:
    values = table.get(team_code, [])
    for value in reversed(values):
        if value is not None:
            return float(value)
    return 0.0


def _date_range(start: dt.date, end: dt.date) -> list[dt.date]:
    if end < start:
        return []
    return [start + dt.timedelta(days=i) for i in range((end - start).days + 1)]


def _is_final_state(value: Any) -> bool:
    text = str(value or "").upper().strip()
    return text in {"FINAL", "OFF"} or text.startswith("FINAL")


def _is_regular_nhl_game(game: dict[str, Any]) -> bool:
    game_type = str(
        game.get("gameType")
        or game.get("gameTypeId")
        or game.get("game_type")
        or game.get("game_type_id")
        or ""
    ).upper().strip()
    gid = str(game.get("id") or game.get("gameId") or "")
    if game_type:
        return game_type in {"2", "R", "REG", "REGULAR"}
    return not (len(gid) >= 6 and gid[4:6] == "03")


def _team_code(team_obj: dict[str, Any]) -> str:
    if not isinstance(team_obj, dict):
        return ""
    raw = team_obj.get("abbrev") or team_obj.get("abbreviation") or team_obj.get("teamAbbrev") or ""
    return canon_team_code(str(raw).upper().strip())


def _score_value(team_obj: dict[str, Any]) -> int:
    try:
        return int(float(team_obj.get("score") if isinstance(team_obj, dict) else 0))
    except Exception:
        return 0


def _game_identity(game: dict[str, Any]) -> tuple[str, str, str, str]:
    gid = str(game.get("id") or game.get("gameId") or "").strip()
    away = _team_code(game.get("awayTeam") if isinstance(game.get("awayTeam"), dict) else {})
    home = _team_code(game.get("homeTeam") if isinstance(game.get("homeTeam"), dict) else {})
    league = str(game.get("league") or "NHL").upper().strip()
    if gid and gid != "0":
        return (league, gid, "", "")
    return (league, "", away, home)


def _merge_game_rows(*row_groups: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[tuple[str, str, str, str], dict[str, Any]] = {}
    order: list[tuple[str, str, str, str]] = []
    for rows in row_groups:
        for row in rows:
            if not isinstance(row, dict):
                continue
            key = _game_identity(row)
            if key not in merged:
                merged[key] = dict(row)
                order.append(key)
                continue
            cur = dict(merged[key])
            for k, v in row.items():
                if v in (None, "", [], {}):
                    continue
                if isinstance(v, dict) and isinstance(cur.get(k), dict):
                    child = dict(cur[k])
                    for ck, cv in v.items():
                        if cv not in (None, "", [], {}):
                            child[ck] = cv
                    cur[k] = child
                else:
                    cur[k] = v
            merged[key] = cur
    return [merged[key] for key in order]


def _build_score_tables_from_games(days: list[tuple[dt.date, list[dict[str, Any]]]]) -> tuple[pd.DataFrame, pd.DataFrame]:
    codes = sorted(TEAM_NAMES.keys())
    points = {code: 0 for code in codes}
    goal_diff = {code: 0 for code in codes}
    points_cols: dict[str, list[int]] = {}
    gd_cols: dict[str, list[int]] = {}

    for day, games in days:
        for game in games:
            if not isinstance(game, dict) or not _is_regular_nhl_game(game):
                continue
            if not _is_final_state(game.get("gameState") or game.get("gameStatus") or game.get("state")):
                continue
            away = game.get("awayTeam") if isinstance(game.get("awayTeam"), dict) else {}
            home = game.get("homeTeam") if isinstance(game.get("homeTeam"), dict) else {}
            away_code = _team_code(away)
            home_code = _team_code(home)
            if away_code not in points or home_code not in points:
                continue
            away_score = _score_value(away)
            home_score = _score_value(home)
            if away_score == home_score:
                continue
            went_extra = "OT" in str(game.get("statusText") or "").upper() or "SO" in str(game.get("statusText") or "").upper()
            if home_score > away_score:
                points[home_code] += 2
                points[away_code] += 1 if went_extra else 0
            else:
                points[away_code] += 2
                points[home_code] += 1 if went_extra else 0
            goal_diff[home_code] += home_score - away_score
            goal_diff[away_code] += away_score - home_score

        col = f"{day.month}/{day.day}"
        points_cols[col] = [points[code] for code in codes]
        gd_cols[col] = [goal_diff[code] for code in codes]

    return (
        pd.DataFrame(points_cols, index=codes, dtype="float64"),
        pd.DataFrame(gd_cols, index=codes, dtype="float64"),
    )


def _espn_external_games(api: ESPNApi, day: dt.date) -> list[dict[str, Any]]:
    from hockey_app.ui.tabs.games import _convert_espn_events, _split_all_hockey_espn_events

    # The desktop app uses ESPN as a supplemental source for Olympics/IIHF and
    # occasional PWHL fallback rows. Avoid probing ESPN for every NHL day in
    # GitHub Actions; PWHL has its own source, and prior non-NHL web rows are
    # preserved below when ESPN has no current rows.
    if not (
        (day.month == 1 and day.day >= 25)
        or day.month == 2
        or (day.month == 3 and day.day <= 5)
        or abs((day - dt.date.today()).days) <= 3
    ):
        return []

    out: list[dict[str, Any]] = []
    try:
        payload = api.scoreboard_all_hockey(day, allow_network=True, force_network=(day >= dt.date.today()))
        if isinstance(payload, dict):
            olympics, pwhl = _split_all_hockey_espn_events(payload)
            out.extend(olympics)
            out.extend(pwhl)
    except Exception:
        # This aggregate endpoint is not consistently available. The explicit
        # league probes below are the reliable path and should decide the result.
        pass

    # ESPN all-hockey can miss lower-profile leagues. Probe the known slugs used
    # by the desktop Games tab and merge whichever ones are live.
    probes = (
        ("olympics", "Olympics", True),
        ("olympics-hockey", "Olympics", True),
        ("olympic-hockey", "Olympics", True),
        ("pwhl", "PWHL", False),
        ("pro-womens-hockey-league", "PWHL", False),
        ("professional-womens-hockey-league", "PWHL", False),
    )
    for slug, label, include_round in probes:
        try:
            probe_payload = api.scoreboard("hockey", slug, day, allow_network=True, force_network=(day >= dt.date.today()))
        except Exception:
            continue
        if isinstance(probe_payload, dict):
            out.extend(_convert_espn_events(probe_payload, league_label=label, include_round_text=include_round))
    return _merge_game_rows(out)


def _refresh_desktop_xml_data(*, season: str, start: dt.date, end: dt.date) -> None:
    api = NHLApi(DiskCache(nhl_dir(season)))
    pwhl_api = PWHLApi(DiskCache(pwhl_dir(season)))
    espn_api = ESPNApi(DiskCache(espn_dir(season)))
    fetched_days: list[tuple[dt.date, list[dict[str, Any]]]] = []
    for day in _date_range(start, end):
        existing = read_games_day_xml(season=season, day=day)
        try:
            payload = api.score(day, force_network=(day >= dt.date.today()))
        except Exception:
            payload = {}
        nhl_games = [g for g in list(payload.get("games") or []) if isinstance(g, dict)]
        prepared_nhl: list[dict[str, Any]] = []
        if nhl_games:
            for game in nhl_games:
                cur = dict(game)
                cur["league"] = "NHL"
                prepared_nhl.append(cur)

        pwhl_games: list[dict[str, Any]] = []
        try:
            pwhl_games = pwhl_api.get_games_for_date(day, allow_network=True, force_network=(day >= dt.date.today()))
        except Exception as exc:
            print(f"WARNING: PWHL refresh failed for {day.isoformat()}: {exc}")

        external_games: list[dict[str, Any]] = []
        try:
            external_games = _espn_external_games(espn_api, day)
        except Exception as exc:
            print(f"WARNING: ESPN hockey refresh failed for {day.isoformat()}: {exc}")

        games = _merge_game_rows(prepared_nhl, pwhl_games, external_games, existing)
        if games:
            prepared: list[dict[str, Any]] = []
            for game in games:
                cur = dict(game)
                cur["league"] = cur.get("league") or "NHL"
                prepared.append(cur)
            write_games_day_xml(season=season, day=day, games=prepared)
        fetched_days.append((day, prepared_nhl))

    if not fetched_days:
        return
    points_df, goal_diff_df = _build_score_tables_from_games(fetched_days)
    write_table_xml(
        season=season,
        lump="points_history",
        league="NHL",
        start=start,
        end=end,
        df=points_df,
        phase="Regular Season",
    )
    write_table_xml(
        season=season,
        lump="goal_differential",
        league="NHL",
        start=start,
        end=end,
        df=goal_diff_df,
        phase="Regular Season",
    )


def _export_games(season: str, start: dt.date, end: dt.date) -> dict[str, Any]:
    days: dict[str, list[dict[str, Any]]] = {}
    latest_day = ""
    for day in _date_range(start, end):
        rows = read_games_day_xml(season=season, day=day)
        if not rows:
            continue
        slim_rows: list[dict[str, Any]] = []
        for game in rows:
            away = game.get("awayTeam") if isinstance(game.get("awayTeam"), dict) else {}
            home = game.get("homeTeam") if isinstance(game.get("homeTeam"), dict) else {}
            clock = game.get("clock") if isinstance(game.get("clock"), dict) else {}
            period = game.get("periodDescriptor") if isinstance(game.get("periodDescriptor"), dict) else {}
            slim_rows.append(
                {
                    "id": game.get("id"),
                    "gameType": str(
                        game.get("gameType")
                        or game.get("gameTypeId")
                        or game.get("game_type")
                        or game.get("game_type_id")
                        or ""
                    ),
                    "gameTypeId": game.get("gameTypeId") or game.get("gameType"),
                    "gameTypeCode": game.get("gameTypeCode") or "",
                    "playoffRound": game.get("playoffRound") or game.get("round"),
                    "league": game.get("league") or "NHL",
                    "state": str(game.get("gameState") or "").upper(),
                    "status": game.get("statusText") or "",
                    "clock": {
                        "timeRemaining": clock.get("timeRemaining") or clock.get("time") or "",
                        "inIntermission": bool(clock.get("inIntermission")),
                    },
                    "periodDescriptor": {
                        "number": period.get("number"),
                        "periodType": period.get("periodType") or "",
                    },
                    "stage": game.get("displayStage") or "",
                    "division": game.get("olympicsDivision") or "",
                    "startUtc": game.get("startTimeUTC") or "",
                    "away": {
                        "code": str(away.get("abbrev") or "").upper(),
                        "name": ((away.get("name") or {}).get("default") if isinstance(away.get("name"), dict) else away.get("name")) or "",
                        "score": away.get("score"),
                        "shots": away.get("shotsOnGoal"),
                    },
                    "home": {
                        "code": str(home.get("abbrev") or "").upper(),
                        "name": ((home.get("name") or {}).get("default") if isinstance(home.get("name"), dict) else home.get("name")) or "",
                        "score": home.get("score"),
                        "shots": home.get("shotsOnGoal"),
                    },
                }
            )
        iso = day.isoformat()
        days[iso] = slim_rows
        latest_day = iso
    return {"days": days, "latestDay": latest_day}


def _export_team_stats(season: str, league: str) -> dict[str, Any] | None:
    payload = read_team_stats_xml(season=season, league=league)
    if not isinstance(payload, dict):
        return None
    out: dict[str, Any] = {}
    for phase, blob in payload.items():
        if not isinstance(blob, dict):
            continue
        dates = [d for d in blob.get("dates", []) if isinstance(d, dt.date)]
        rows_by_date = blob.get("rows_by_date", {})
        phase_rows: dict[str, Any] = {}
        for day in sorted(dates):
            rows = rows_by_date.get(day, []) if isinstance(rows_by_date, dict) else []
            phase_rows[day.isoformat()] = _jsonable(rows)
        out[str(phase)] = {
            "dates": [d.isoformat() for d in sorted(dates)],
            "rowsByDate": phase_rows,
        }
    return out or None


def _export_desktop_data(season: str, start: dt.date, end: dt.date) -> dict[str, Any]:
    league = "NHL"
    points_df = read_table_xml(season=season, lump="points_history", league=league)
    goal_diff_df = read_table_xml(season=season, lump="goal_differential", league=league)
    points = _df_payload(points_df)
    goal_diff = _df_payload(goal_diff_df)
    playoff_models = _export_playoff_models(points_df=points_df, start=start, end=end, league=league)
    return {
        "league": league,
        "scoreboard": _export_games(season, start, end),
        "stats": {
            "teamStats": _export_team_stats(season, league),
            "gameStats": _jsonable(read_game_stats_xml(season=season, league=league)),
            "playerStats": _jsonable(read_player_stats_xml(season=season, league=league)),
            "points": points,
            "goalDifferential": goal_diff,
        },
        "models": {
            "points": points,
            "teamStats": _export_team_stats(season, league),
            "gameStats": _jsonable(read_game_stats_xml(season=season, league=league)),
            "playoffPicture": playoff_models["playoffPicture"],
            "playoffWinProbabilities": playoff_models["playoffWinProbabilities"],
        },
    }


def _has_desktop_data(payload: dict[str, Any]) -> bool:
    desktop = payload.get("desktop")
    if not isinstance(desktop, dict):
        return False
    stats = desktop.get("stats")
    scoreboard = desktop.get("scoreboard")
    return bool(
        isinstance(stats, dict)
        and (
            stats.get("teamStats")
            or stats.get("gameStats")
            or stats.get("playerStats")
            or stats.get("points")
            or stats.get("goalDifferential")
        )
    ) or bool(isinstance(scoreboard, dict) and scoreboard.get("days"))


def _web_game_identity(game: dict[str, Any]) -> tuple[str, str, str, str]:
    league = str(game.get("league") or "NHL").upper().strip()
    gid = str(game.get("id") or "").strip()
    away = game.get("away") if isinstance(game.get("away"), dict) else {}
    home = game.get("home") if isinstance(game.get("home"), dict) else {}
    away_code = str(away.get("code") or "").upper().strip()
    home_code = str(home.get("code") or "").upper().strip()
    if gid and gid != "0":
        return (league, gid, "", "")
    return (league, "", away_code, home_code)


def _preserve_existing_external_web_games(payload: dict[str, Any], existing: dict[str, Any] | None) -> None:
    if not existing:
        return
    target_scoreboard = (payload.get("desktop") or {}).get("scoreboard")
    source_scoreboard = (existing.get("desktop") or {}).get("scoreboard")
    if not isinstance(target_scoreboard, dict) or not isinstance(source_scoreboard, dict):
        return
    target_days = target_scoreboard.setdefault("days", {})
    source_days = source_scoreboard.get("days") or {}
    if not isinstance(target_days, dict) or not isinstance(source_days, dict):
        return

    for day, source_games in source_days.items():
        if not isinstance(source_games, list):
            continue
        target_games = target_days.setdefault(str(day), [])
        if not isinstance(target_games, list):
            continue
        seen = {
            _web_game_identity(game)
            for game in target_games
            if isinstance(game, dict)
        }
        for game in source_games:
            if not isinstance(game, dict):
                continue
            league = str(game.get("league") or "").upper()
            if league == "NHL":
                continue
            key = _web_game_identity(game)
            if key in seen:
                continue
            target_games.append(game)
            seen.add(key)

    populated = sorted(
        day
        for day, games in target_days.items()
        if isinstance(games, list) and games
    )
    if populated:
        target_scoreboard["latestDay"] = populated[-1]


def _read_existing_payload(out_dir: Path) -> dict[str, Any] | None:
    path = out_dir / "data.json"
    if not path.exists():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        return raw if isinstance(raw, dict) else None
    except Exception:
        return None


def _copy_logo_assets(out_dir: Path) -> None:
    assets_src = Path(__file__).resolve().parents[1] / "assets"
    for folder_name in ("nhl_logos", "pwhl_logos", "iihf_logos"):
        src = assets_src / folder_name
        dst = out_dir / "assets" / folder_name
        dst.mkdir(parents=True, exist_ok=True)
        if not src.exists():
            continue
        for png in sorted(src.glob("*.png")):
            shutil.copy2(png, dst / png.name)
    cup_src = assets_src / "stanley_cup.png"
    if cup_src.exists():
        (out_dir / "assets").mkdir(parents=True, exist_ok=True)
        shutil.copy2(cup_src, out_dir / "assets" / "stanley_cup.png")


def _write_data_version(out_dir: Path, generated_at: str) -> str:
    version = re.sub(r"[^0-9A-Za-z]+", "", generated_at) or dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S")
    (out_dir / "data-version.json").write_text(
        json.dumps({"version": version, "generatedAt": generated_at}, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    index_path = out_dir / "index.html"
    if index_path.exists():
        html = index_path.read_text(encoding="utf-8")
        replacement = f'<script src="data.js?v={version}"></script>'
        if DATA_SCRIPT_RE.search(html):
            html = DATA_SCRIPT_RE.sub(replacement, html)
        else:
            html = html.replace('<script src="app.js"></script>', f'{replacement}\n    <script src="app.js"></script>')
        index_path.write_text(html, encoding="utf-8")
    return version


def build_payload(
    *,
    season: str,
    start: dt.date,
    end: dt.date,
    simulations_dir: Path,
) -> dict[str, Any]:
    tables = compile_probability_tables(
        simulations_dir,
        start,
        end,
        metrics=METRICS,
        canon_team_code=canon_team_code,
    )
    if not tables or all(df.empty for df in tables.values()):
        raise SystemExit(f"No simulation data found in {simulations_dir}")

    table_payload: dict[str, dict[str, Any]] = {}
    all_codes: set[str] = set()
    for metric, df in tables.items():
        all_codes.update(str(code) for code in df.index)
        table_payload[metric] = {
            "columns": [str(col) for col in df.columns],
            "rows": _frame_to_rows(df),
        }

    colors = build_team_color_map(all_codes)
    made_playoffs = table_payload.get("madeplayoffs", {}).get("rows", {})
    team_rows = []
    for code in sorted(all_codes):
        base = colors.get(code, "#888888")
        team_rows.append(
            {
                "code": code,
                "name": TEAM_NAMES.get(code, code),
                "division": TEAM_TO_DIV.get(code, ""),
                "conference": TEAM_TO_CONF.get(code, ""),
                "color": theme_adjusted_line_color(code, base),
                "logo": f"assets/nhl_logos/{code}.png",
                "sortValue": round(_latest_value(made_playoffs, code), 4),
            }
        )
    team_rows.sort(key=lambda team: (-float(team["sortValue"]), str(team["name"])))

    # Desktop-backed tabs should export the same current cache range the desktop
    # app can render, not just the span covered by simulation CSVs.
    desktop_start = _season_start(season)
    desktop_end = max(end, dt.date.today())

    return {
        "metadata": {
            "season": season,
            "startDate": start.isoformat(),
            "endDate": end.isoformat(),
            "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "source": "MoneyPuck simulations",
        },
        "metrics": [
            {"key": key, "label": METRIC_LABELS[key], "title": METRIC_TITLES[key]}
            for key in METRICS
        ],
        "teams": team_rows,
        "tables": table_payload,
        "desktop": _export_desktop_data(season, desktop_start, desktop_end),
    }


def export_web(
    *,
    out_dir: Path,
    season: str,
    start: dt.date | None,
    end: dt.date | None,
    refresh: bool,
) -> Path:
    simulations_dir = sims_dir(season)
    if refresh:
        refresh_start = start or _season_start(season)
        refresh_end = end or dt.date.today()
        errors = download_missing_simulations(
            refresh_start,
            refresh_end,
            simulations_dir,
            headers=HEADERS,
            ensure_dir_writable=_ensure_writable,
            index_url=URL_SIMULATIONS,
        )
        if errors:
            joined = "\n".join(f"- {msg}" for msg in errors)
            raise SystemExit(f"Failed to refresh simulations:\n{joined}")
        _refresh_desktop_xml_data(
            season=season,
            start=_season_start(season),
            end=refresh_end,
        )

    dates = _csv_dates(simulations_dir)
    if not dates:
        raise SystemExit(
            f"No cached simulations found in {simulations_dir}. "
            "Run again with --refresh to download them."
        )

    export_start = start or dates[0]
    export_end = end or dates[-1]
    payload = build_payload(
        season=season,
        start=export_start,
        end=export_end,
        simulations_dir=simulations_dir,
    )
    existing = _read_existing_payload(out_dir)
    if existing and not _has_desktop_data(payload) and _has_desktop_data(existing):
        payload["desktop"] = existing["desktop"]
    else:
        _preserve_existing_external_web_games(payload, existing)

    out_dir.mkdir(parents=True, exist_ok=True)
    _copy_logo_assets(out_dir)
    data_json = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    (out_dir / "data.json").write_text(data_json + "\n", encoding="utf-8")
    (out_dir / "data.js").write_text(
        "window.HOCKEY_APP_DATA = " + data_json + ";\n",
        encoding="utf-8",
    )
    _write_data_version(out_dir, str(payload.get("metadata", {}).get("generatedAt") or ""))
    return out_dir / "data.js"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Export the static GitHub Pages web app data.")
    parser.add_argument("--out", default="docs", help="Output directory for static web files.")
    parser.add_argument("--season", default=_default_season(), help="Season key, for example 2025-2026.")
    parser.add_argument("--start", help="Optional export start date, YYYY-MM-DD.")
    parser.add_argument("--end", help="Optional export end date, YYYY-MM-DD.")
    parser.add_argument("--refresh", action="store_true", help="Download missing simulation CSVs first.")
    args = parser.parse_args(argv)

    data_path = export_web(
        out_dir=Path(args.out),
        season=str(args.season),
        start=_parse_date(args.start),
        end=_parse_date(args.end),
        refresh=bool(args.refresh),
    )
    print(f"Wrote {data_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
