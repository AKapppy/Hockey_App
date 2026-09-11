"""Previous regular-season standings used only as a preseason ordering prior."""
from __future__ import annotations

import datetime as dt
from typing import Any

from hockey_app.data.cache import DiskCache
from hockey_app.data.nhl_api import NHLApi
from hockey_app.data.paths import nhl_dir
from hockey_app.domain.seasons import normalize_season, season_metadata
from hockey_app.domain.teams import canon_team_code_for_season


def previous_regular_season_baseline(selected_season: str, *, allow_network: bool = True) -> dict[str, Any]:
    selected = normalize_season(selected_season)
    if not selected:
        return {}
    start = int(selected[:4])
    previous = f"{start - 1}-{start}"
    record = season_metadata().get(previous, {})
    end_raw = record.get("regular_end")
    if not end_raw:
        return {}
    standings_day = dt.date.fromisoformat(str(end_raw))
    cache = DiskCache(nhl_dir(previous))
    key = f"baseline/regular_final/{previous}"
    saved = cache.get_json(key, ttl_s=None)
    if isinstance(saved, dict) and saved.get("teams"):
        return saved
    if not allow_network:
        return {}
    try:
        payload = NHLApi(cache).standings(standings_day, force_network=False)
    except Exception:
        return {}
    rows = payload.get("standings") if isinstance(payload, dict) else []
    teams: dict[str, dict[str, Any]] = {}
    for row in rows if isinstance(rows, list) else []:
        abbr = row.get("teamAbbrev") if isinstance(row, dict) else None
        raw = abbr.get("default") if isinstance(abbr, dict) else abbr
        code = canon_team_code_for_season(str(raw or ""), selected)
        if not code:
            continue
        teams[code] = {
            "overall_rank": int(row.get("leagueSequence") or 999),
            "conference_rank": int(row.get("conferenceSequence") or 999),
            "division_rank": int(row.get("divisionSequence") or 999),
            "points": int(row.get("points") or 0),
            "point_percentage": float(row.get("pointPctg") or row.get("pointPercentage") or 0.0),
        }
    result = {"prior_season": previous, "standings_date": standings_day.isoformat(),
              "provider": "NHL standings", "source": f"/v1/standings/{standings_day.isoformat()}", "teams": teams}
    if teams:
        cache.set_json(key, result)
    return result


def preseason_strength_prior(selected_season: str, *, allow_network: bool = True) -> dict[str, float]:
    teams = previous_regular_season_baseline(selected_season, allow_network=allow_network).get("teams", {})
    if not teams:
        return {}
    ranks = {code: float(info.get("overall_rank") or 999) for code, info in teams.items()}
    n = max(1.0, float(len(ranks) - 1))
    return {code: ((len(ranks) - rank) / n - 0.5) * 1.4 for code, rank in ranks.items()}
