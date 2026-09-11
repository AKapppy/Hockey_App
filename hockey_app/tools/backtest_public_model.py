"""Chronological Elo tuning for Predictions 2 using official NHL results."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

import requests

from hockey_app.domain.teams import nhl_team_names


def score_predictions(samples: list[tuple[float, int]]) -> dict[str, Any]:
    if not samples:
        return {"games": 0, "brier": None, "log_loss": None, "accuracy": None, "calibration": []}
    clipped = [(min(.999999, max(.000001, p)), y) for p, y in samples]
    buckets: dict[int, list[int]] = {}
    for p, y in clipped:
        buckets.setdefault(min(9, int(p * 10)), []).append(y)
    return {
        "games": len(clipped),
        "brier": sum((p-y)**2 for p, y in clipped) / len(clipped),
        "log_loss": -sum(y*math.log(p)+(1-y)*math.log(1-p) for p, y in clipped) / len(clipped),
        "accuracy": sum((p >= .5) == bool(y) for p, y in clipped) / len(clipped),
        "calibration": [{"bucket": f"{b/10:.1f}-{(b+1)/10:.1f}", "n": len(ys), "actual": sum(ys)/len(ys)} for b, ys in sorted(buckets.items())],
    }


def walk_forward_elo(games: list[dict[str, Any]], *, k: float, home_advantage: float,
                     carry: float = .65, initial: dict[str, float] | None = None) -> tuple[dict[str, Any], dict[str, float]]:
    ratings = {code: 1500.0 + carry * (value - 1500.0) for code, value in (initial or {}).items()}
    samples: list[tuple[float, int]] = []
    for game in sorted(games, key=lambda g: (g["date"], g["id"])):
        home, away = game["home"], game["away"]
        rh, ra = ratings.get(home, 1500.0), ratings.get(away, 1500.0)
        p = 1.0 / (1.0 + 10.0 ** (-(rh + home_advantage - ra) / 400.0))
        y = 1 if game["home_score"] > game["away_score"] else 0
        samples.append((p, y))
        margin = abs(game["home_score"] - game["away_score"])
        delta = k * math.log1p(max(1, margin)) * (y - p)
        ratings[home], ratings[away] = rh + delta, ra - delta
    return score_predictions(samples), ratings


def frozen_previous_rating_baseline(games: list[dict[str, Any]], ratings: dict[str, float], *, home_advantage: float) -> dict[str, Any]:
    samples = []
    for game in games:
        rh, ra = ratings.get(game["home"], 1500.0), ratings.get(game["away"], 1500.0)
        p = 1.0 / (1.0 + 10.0 ** (-(rh + home_advantage - ra) / 400.0))
        samples.append((p, 1 if game["home_score"] > game["away_score"] else 0))
    return score_predictions(samples)


def _download_season(season: str) -> list[dict[str, Any]]:
    compact = season.replace("-", "")
    seen: dict[int, dict[str, Any]] = {}
    headers = {"User-Agent": "hockey_app Predictions2 trainer/1.0"}
    for code in nhl_team_names(season):
        response = requests.get(f"https://api-web.nhle.com/v1/club-schedule-season/{code}/{compact}", headers=headers, timeout=30)
        response.raise_for_status()
        for row in response.json().get("games", []):
            if int(row.get("gameType") or 0) != 2 or str(row.get("gameState") or "").upper() not in {"FINAL", "OFF"}:
                continue
            home, away = row.get("homeTeam") or {}, row.get("awayTeam") or {}
            seen[int(row["id"])] = {"id": int(row["id"]), "date": row["gameDate"],
                "home": str(home.get("abbrev")), "away": str(away.get("abbrev")),
                "home_score": int(home.get("score") or 0), "away_score": int(away.get("score") or 0)}
    return list(seen.values())


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seasons", nargs="+", default=["2023-2024", "2024-2025", "2025-2026"])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    datasets = {season: _download_season(season) for season in args.seasons}
    best = None
    for k in (12.0, 16.0, 20.0, 24.0, 28.0):
        for home in (20.0, 30.0, 40.0, 50.0, 60.0):
            ratings: dict[str, float] = {}; reports = []
            for season in args.seasons:
                report, ratings = walk_forward_elo(datasets[season], k=k, home_advantage=home, initial=ratings)
                reports.append({"season": season, **report})
            objective = sum(float(r["log_loss"]) for r in reports) / len(reports)
            candidate = {"model_version": "nhl-elo-prior-v7", "k": k, "home_advantage_elo": home,
                         "prior_carry": .65, "seasons": args.seasons, "reports": reports, "mean_log_loss": objective}
            if best is None or objective < best[0]: best = (objective, candidate)
    baseline = {season: score_predictions([(0.54, 1 if g["home_score"] > g["away_score"] else 0) for g in games]) for season, games in datasets.items()}
    previous_baseline = {}; prior_ratings = {}
    for season in args.seasons:
        previous_baseline[season] = frozen_previous_rating_baseline(datasets[season], prior_ratings, home_advantage=best[1]["home_advantage_elo"])
        _report, prior_ratings = walk_forward_elo(datasets[season], k=best[1]["k"], home_advantage=best[1]["home_advantage_elo"], initial=prior_ratings)
    result = {**best[1], "baseline_home_54": baseline, "baseline_previous_season_ratings": previous_baseline}
    print(json.dumps(result, indent=2))
    if args.output: args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
