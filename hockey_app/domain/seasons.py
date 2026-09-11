"""Canonical season dates and schedule-derived league rules."""
from __future__ import annotations

import collections
import csv
import datetime as dt
import json
import os
import re

BOUNDS = {
    "2025-2026": {"preseason": "2025-09-20", "regular": "2025-10-07", "regular_end": "2026-04-16"},
    "2026-2027": {"preseason": "2026-09-19", "regular": "2026-09-29", "regular_end": "2027-04-10"},
}
LENGTHS = {("NHL", "2025-2026"): 82, ("NHL", "2026-2027"): 84, ("PWHL", "2025-2026"): 30}


def normalize_season(value):
    match = re.fullmatch(r"(\d{4})[-–]?(\d{2}|\d{4})", str(value or "").strip())
    if not match:
        return None
    year = int(match[1]); end = int(match[2]) if len(match[2]) == 4 else year // 100 * 100 + int(match[2])
    return f"{year}-{end}" if end == year + 1 else None


def _metadata_path():
    from hockey_app.data.paths import cache_dir
    return cache_dir() / "meta" / "season_metadata.json"


def season_metadata():
    """Read the sole writable store, importing useful legacy JSON in memory."""
    records = {key: {"season": key, **value, "leagues": {}} for key, value in BOUNDS.items()}
    from hockey_app.data.paths import cache_dir
    for path in (cache_dir() / "meta" / "published_seasons.json", _metadata_path()):
        if not path.exists():
            continue
        try:
            stored = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError, TypeError):
            continue
        for key, value in stored.items():
            norm = normalize_season(key)
            if not norm or not isinstance(value, dict):
                continue
            base = records.setdefault(norm, {"season": norm, "leagues": {}})
            leagues = {**base.get("leagues", {}), **value.get("leagues", {})}
            base.update(value); base["leagues"] = leagues
    # Read-only migration for older installations. New writes only use the JSON store.
    csv_path = cache_dir() / "season_dates.csv"
    if csv_path.exists():
        try:
            with csv_path.open(encoding="utf-8", newline="") as stream:
                for row in csv.DictReader(stream):
                    key = normalize_season(row.get("season"))
                    if not key: continue
                    record = records.setdefault(key, {"season": key, "leagues": {}})
                    if row.get("start_date"): record.setdefault("preseason", row["start_date"])
                    regular_start = row.get("regular_season_start")
                    if regular_start and regular_start != row.get("start_date"):
                        record.setdefault("regular", regular_start)
                    if row.get("regular_season_end"): record.setdefault("regular_end", row["regular_season_end"])
                    if row.get("playoffs_start"): record.setdefault("postseason_start", row["playoffs_start"])
        except (OSError, csv.Error):
            pass
    return records


def published_seasons():
    return season_metadata()


def update_season_metadata(season, *, dates=None, league=None, rule=None, source=None):
    key = normalize_season(season)
    if not key:
        raise ValueError(f"Invalid season: {season}")
    records = season_metadata(); record = records.setdefault(key, {"season": key, "leagues": {}})
    for field in ("preseason", "regular", "regular_end", "postseason_start", "postseason_end"):
        if dates and dates.get(field):
            record[field] = str(dates[field])
    if league and rule is not None:
        record.setdefault("leagues", {})[str(league).upper()] = dict(rule)
    record["source"] = source or record.get("source") or "local migration"
    record["updated_at"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    path = _metadata_path(); path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(records, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return record


def nhl_game_type(game):
    aliases = {"1": 1, "PR": 1, "PRE": 1, "2": 2, "R": 2, "REG": 2, "3": 3, "P": 3, "PO": 3, "PLAYOFFS": 3}
    for field in ("gameType", "gameTypeId", "gameTypeCode", "game_type", "game_type_id"):
        value = str(game.get(field) or "").upper()
        if value in aliases: return aliases[value]
    gid = str(game.get("id") or game.get("gameId") or "")
    return int(gid[4:6]) if len(gid) == 10 and gid.isdigit() and gid[4:6] in {"01", "02", "03"} else None


def derive_schedule_rule(league, season, schedule, *, complete=False, source="official schedule"):
    """Validate and persist the observed structure of a complete regular schedule."""
    league = str(league).upper(); season = normalize_season(season)
    if not season or not complete: return None
    seen = set(); regular = []; totals, homes, aways = (collections.Counter() for _ in range(3))
    for index, game in enumerate(schedule or []):
        if not isinstance(game, dict) or (league == "NHL" and nhl_game_type(game) != 2): continue
        gid = str(game.get("id") or game.get("gameId") or "").strip()
        identity = gid or (str(game.get("date") or ""), str(game.get("startTimeUTC") or ""), index)
        if identity in seen: raise ValueError("Duplicate official schedule game")
        seen.add(identity)
        home = game.get("homeTeam") or game.get("home") or {}; away = game.get("awayTeam") or game.get("away") or {}
        hc = str(home.get("abbrev") or home.get("code") or "").upper(); ac = str(away.get("abbrev") or away.get("code") or "").upper()
        if not hc or not ac or hc == ac: raise ValueError("Invalid official schedule opponents")
        regular.append(game); totals.update((hc, ac)); homes[hc] += 1; aways[ac] += 1
    if not regular or len(set(totals.values())) != 1: raise ValueError("Incomplete or unbalanced official schedule")
    games = next(iter(totals.values())); known = LENGTHS.get((league, season))
    if known is not None and known != games: raise ValueError(f"Official schedule conflicts with known {league} rule")
    teams = sorted(totals)
    rule = {"games_per_team": games, "team_count": len(teams), "total_games": len(regular), "teams": teams,
            "home_games": dict(sorted(homes.items())), "away_games": dict(sorted(aways.items())),
            "home_away_balanced": all(homes[t] == aways[t] for t in teams), "schedule_complete": True,
            "source": source, "updated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
    update_season_metadata(season, league=league, rule=rule, source=source)
    return rule


def season_rule(league, season):
    key = normalize_season(season)
    if not key: return None
    rule = season_metadata().get(key, {}).get("leagues", {}).get(str(league).upper())
    if rule: return rule
    known = LENGTHS.get((str(league).upper(), key))
    return {"games_per_team": known, "schedule_complete": False, "source": "bundled historical rule"} if known is not None else None


def games_per_team(league, season, *, schedule=None, complete=False):
    if schedule is not None and complete:
        rule = derive_schedule_rule(league, season, schedule, complete=True)
        return rule["games_per_team"] if rule else None
    rule = season_rule(league, season)
    return rule.get("games_per_team") if rule else None


class SeasonSelection:
    def __init__(self, season, phase, source, historical=False, active_season=None, upcoming_season=None):
        self.season, self.phase, self.source = season, phase, source
        self.historical, self.active_season, self.upcoming_season = historical, active_season, upcoming_season


def resolve_season(today=None, *, selected=None, metadata=None, use_env=True):
    day = today or dt.date.today(); explicit = selected or (os.environ.get("HOCKEY_SEASON") if use_env else None)
    season = normalize_season(explicit)
    if explicit and not season: raise ValueError(f"Invalid hockey season: {explicit}")
    records = {**season_metadata(), **(metadata or {})}; active = upcoming = None
    for key, record in sorted(records.items()):
        opening = record.get("preseason") or record.get("regular"); closing = record.get("postseason_end") or f"{int(key[:4]) + 1}-06-30"
        if opening and opening <= day.isoformat() <= closing: active = key
        if opening and opening > day.isoformat() and upcoming is None: upcoming = key
    if not season:
        year = day.year if day.month >= 7 else day.year - 1
        season = active or (upcoming if upcoming and int(upcoming[:4]) == year else f"{year}-{year + 1}")
    bounds = records.get(season, {}); pre = dt.date.fromisoformat(bounds["preseason"]) if bounds.get("preseason") else None
    reg = dt.date.fromisoformat(bounds["regular"]) if bounds.get("regular") else None; end = dt.date.fromisoformat(bounds["regular_end"]) if bounds.get("regular_end") else None
    phase = "upcoming" if pre and day < pre else "preseason" if reg and day < reg and pre and day >= pre else "postseason" if end and day > end else "regular" if reg and day >= reg else "unpublished"
    historical = int(season[:4]) < (day.year if day.month >= 7 else day.year - 1)
    source = "override" if explicit else "metadata" if season in (metadata or {}) else "canonical metadata" if bounds else "season-year fallback"
    return SeasonSelection(season, phase, source, historical, active, upcoming)


def season_start(season):
    key = normalize_season(season)
    if not key: raise ValueError("Invalid season")
    value = season_metadata().get(key, {}).get("preseason")
    return dt.date.fromisoformat(value) if value else dt.date(int(key[:4]), 7, 1)


def selected_nhl_games():
    value = games_per_team("NHL", resolve_season().season)
    if value is None: raise ValueError("NHL season length unavailable")
    return value
