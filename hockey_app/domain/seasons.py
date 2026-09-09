"""Shared season selection and rules; unknown rules remain unknown.

Published bounds supplied by a caller override the bundled regression baseline.
The July fallback identifies a season year, not a claimed opening date.
"""
import datetime as dt
import os
import json
import re
from dataclasses import dataclass

BOUNDS = {
    "2025-2026": {"preseason": "2025-09-20", "regular": "2025-10-07", "regular_end": "2026-04-16"},
    "2026-2027": {"preseason": "2026-09-19", "regular": "2026-09-29", "regular_end": "2027-04-10"},
}
LENGTHS = {("NHL", "2025-2026"): 82, ("NHL", "2026-2027"): 84, ("PWHL", "2025-2026"): 30}

def published_seasons():
    """Use provider-derived local metadata before bundled regression bounds."""
    from hockey_app.data.paths import cache_dir
    records = dict(BOUNDS)
    path = cache_dir() / "meta" / "published_seasons.json"
    if path.exists():
        try:
            for season, record in json.loads(path.read_text()).items():
                if normalize_season(season) and isinstance(record, dict):
                    records[season] = record
        except (OSError, ValueError, TypeError):
            pass
    return records


def normalize_season(value):
    m = re.fullmatch(r"(\d{4})[-–]?(\d{2}|\d{4})", str(value or "").strip())
    if not m:
        return None
    year = int(m[1])
    end = int(m[2]) if len(m[2]) == 4 else year // 100 * 100 + int(m[2])
    return f"{year}-{end}" if end == year + 1 else None

@dataclass(frozen=True)
class SeasonSelection:
    season: str
    phase: str
    source: str
    historical: bool = False
    active_season: str | None = None
    upcoming_season: str | None = None

def resolve_season(today=None, *, selected=None, metadata=None, use_env=True):
    day = today or dt.date.today()
    explicit = selected or (os.environ.get("HOCKEY_SEASON") if use_env else None)
    season = normalize_season(explicit)
    if explicit and not season:
        raise ValueError(f"Invalid hockey season: {explicit}")
    records = {**published_seasons(), **(metadata or {})}
    active = None
    upcoming = None
    for key, record in sorted(records.items()):
        opening = record.get("preseason") or record.get("regular")
        closing = record.get("postseason_end") or f"{int(key[:4]) + 1}-06-30"
        if opening and closing and opening <= day.isoformat() <= closing:
            active = key
        if opening and opening > day.isoformat() and upcoming is None:
            upcoming = key
    if not season:
        year = day.year if day.month >= 7 else day.year - 1
        season = active or (upcoming if upcoming and int(upcoming[:4]) == year else f"{year}-{year + 1}")
    bounds = records.get(season, {})
    pre = dt.date.fromisoformat(bounds["preseason"]) if bounds.get("preseason") else None
    reg = dt.date.fromisoformat(bounds["regular"]) if bounds.get("regular") else None
    end = dt.date.fromisoformat(bounds["regular_end"]) if bounds.get("regular_end") else None
    phase = "unpublished"
    if pre and day < pre:
        phase = "upcoming"
    elif reg and day < reg:
        phase = "preseason" if pre and day >= pre else "upcoming"
    elif reg and day >= reg:
        phase = "postseason" if end and day > end else "regular"
    historical = int(season[:4]) < (day.year if day.month >= 7 else day.year - 1)
    return SeasonSelection(season, phase, "override" if explicit else ("metadata" if season in (metadata or {}) else "published baseline" if bounds else "season-year fallback"), historical, active, upcoming)

def season_start(season):
    season = normalize_season(season)
    if not season:
        raise ValueError("Invalid season")
    value = published_seasons().get(season, {}).get("preseason")
    return dt.date.fromisoformat(value) if value else dt.date(int(season[:4]), 7, 1)

def games_per_team(league, season, *, schedule=None, complete=False):
    if complete and schedule:
        from collections import Counter
        counts = Counter()
        seen = set()
        for game in schedule:
            if nhl_game_type(game) != 2 and str(league).upper() == "NHL":
                continue
            identity = str(game.get("id"))
            if identity in seen:
                raise ValueError("Duplicate schedule ID")
            seen.add(identity)
            for side in ("homeTeam", "awayTeam"):
                counts[game[side]["abbrev"]] += 1
        expected = 32 if str(league).upper() == "NHL" else (12 if normalize_season(season) == "2026-2027" else 8)
        if len(counts) != expected or len(set(counts.values())) != 1:
            raise ValueError("Incomplete or unbalanced schedule")
        return next(iter(counts.values()))
    return LENGTHS.get((str(league).upper(), normalize_season(season)))

def nhl_game_type(game):
    aliases = {"1": 1, "PR": 1, "PRE": 1, "2": 2, "R": 2, "3": 3, "P": 3, "PO": 3, "PLAYOFFS": 3}
    for field in ("gameType", "gameTypeId", "gameTypeCode"):
        value = str(game.get(field) or "").upper()
        if value in aliases:
            return aliases[value]
    gid = str(game.get("id") or game.get("gameId") or "")
    if len(gid) == 10 and gid.isdigit() and gid[4:6] in {"01", "02", "03"}:
        return int(gid[4:6])
    return None


def selected_nhl_games():
    """Length for the selected desktop season; never borrow an adjacent season."""
    value = games_per_team("NHL", resolve_season().season)
    if value is None:
        raise ValueError("NHL season length unavailable")
    return value
