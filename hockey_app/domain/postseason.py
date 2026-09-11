"""Reusable facts derived from final NHL postseason games."""
from __future__ import annotations
import datetime as dt
from typing import Any
from hockey_app.domain.seasons import nhl_game_type

METRICS = ("make_playoffs", "round2", "round3", "finals", "cup")
COMPLETED_OUTCOMES = {
    "2023-2024": {
        "playoffs": "FLA BOS TOR TBL NYR WSH CAR NYI DAL VGK WPG COL VAN NSH EDM LAK".split(),
        "round2": "FLA BOS NYR CAR DAL COL VAN EDM".split(), "round3": "NYR FLA DAL EDM".split(),
        "finals": "FLA EDM".split(), "cup": ["FLA"]},
    "2024-2025": {
        "playoffs": "TOR OTT TBL FLA WSH MTL CAR NJD WPG STL DAL COL VGK MIN LAK EDM".split(),
        "round2": "TOR FLA WSH CAR WPG DAL VGK EDM".split(), "round3": "CAR FLA DAL EDM".split(),
        "finals": "FLA EDM".split(), "cup": ["FLA"]},
}

def game_date(row):
    value = row.get("date") or row.get("gameDate")
    if isinstance(value, dt.date): return value
    try: return dt.date.fromisoformat(str(value)[:10])
    except (TypeError, ValueError): return None

def team_code(row, side):
    value = row.get(side) or row.get(f"{side}Team") or {}
    return str(value.get("abbrev") or value.get("code") or "").upper() if isinstance(value, dict) else str(value).upper()

def playoff_round(row):
    try:
        explicit = int(row.get("playoff_round") or row.get("playoffRound") or 0)
        if explicit: return explicit
    except (TypeError, ValueError): pass
    gid = str(row.get("id") or row.get("gameId") or "")
    if len(gid) == 10 and gid.isdigit() and gid[4:6] == "03":
        n = int(gid[-4:]); return 1 if n < 200 else 2 if n < 300 else 3 if n < 400 else 4
    return 0

def played_postseason_games(rows, through=None):
    out = []
    for row in rows or []:
        if not isinstance(row, dict): continue
        day = game_date(row)
        state = str(row.get("state") or row.get("gameState") or "").upper()
        if not day or (through and day > through) or state not in {"FINAL", "OFF"}: continue
        if nhl_game_type(row) == 3 or playoff_round(row): out.append(row)
    return out

def actual_last_played_postseason_game(rows):
    return max((game_date(r) for r in played_postseason_games(rows)), default=None)

def postseason_participants(rows):
    return {team_code(r, s) for r in played_postseason_games(rows) for s in ("away", "home") if team_code(r, s)}

def observed_outcome_bounds(rows, through):
    played = played_postseason_games(rows, through=through)
    participants = postseason_participants(played)
    bounds = {c: {"make_playoffs": 1.0} for c in participants}
    series = {}
    for row in played:
        away, home, rnd = team_code(row, "away"), team_code(row, "home"), playoff_round(row)
        if not away or not home or not rnd: continue
        away_obj, home_obj = row.get("awayTeam") or {}, row.get("homeTeam") or {}
        a = int(away_obj.get("score") or row.get("away_score") or 0) if isinstance(away_obj, dict) else int(row.get("away_score") or 0)
        h = int(home_obj.get("score") or row.get("home_score") or 0) if isinstance(home_obj, dict) else int(row.get("home_score") or 0)
        winner = away if a > h else home
        bucket = series.setdefault((rnd, tuple(sorted((away, home)))), {away: 0, home: 0})
        bucket[winner] = bucket.get(winner, 0) + 1
    advance = {1: "round2", 2: "round3", 3: "finals", 4: "cup"}
    for (rnd, matchup), wins in series.items():
        if max(wins.values(), default=0) < 4: continue
        winner = max(wins, key=wins.get); loser = matchup[0] if matchup[1] == winner else matchup[1]
        bounds.setdefault(winner, {})[advance[rnd]] = 1.0
        for metric in METRICS[rnd:]: bounds.setdefault(loser, {})[metric] = 0.0
    return bounds

def condition_probabilities(probabilities, rows, through):
    out = {c: dict(v) for c, v in probabilities.items()}
    bounds = observed_outcome_bounds(rows, through)
    participants = postseason_participants(played_postseason_games(rows, through=through))
    if len(participants) >= 16:
        for code in out: out[code]["make_playoffs"] = 1.0 if code in participants else 0.0
    for code, fixed in bounds.items():
        if code in out: out[code].update(fixed)
    return out

def terminal_outcomes(rows, active_teams):
    last = actual_last_played_postseason_game(rows)
    bounds = observed_outcome_bounds(rows, last) if last else {}
    return {c: {m: float(bounds.get(c, {}).get(m, 0.0)) for m in METRICS} for c in active_teams}

def completed_outcomes_for_season(season, active_teams):
    facts = COMPLETED_OUTCOMES.get(str(season), {})
    if not facts: return {}
    mapping = {"make_playoffs": "playoffs", "round2": "round2", "round3": "round3", "finals": "finals", "cup": "cup"}
    return {c: {metric: float(c in facts[source]) for metric, source in mapping.items()} for c in active_teams}
