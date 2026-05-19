from __future__ import annotations

import os
from pathlib import Path

def base_dir() -> Path:
    """
    Project root: .../hockey_app_folder (the folder that contains /hockey_app).
    """
    return Path(__file__).resolve().parents[2]


def cache_dir() -> Path:
    """
    Central runtime cache location.
    Default:
      - <project>/cache
    Optional overrides:
      - HOCKEY_CACHE_DIR
      - HOCKEY_BASE_DIR/cache
    """
    project = base_dir().resolve()

    override = os.environ.get("HOCKEY_CACHE_DIR", "").strip()
    if override:
        p = Path(override).expanduser()
        p.mkdir(parents=True, exist_ok=True)
        return p

    base_override = os.environ.get("HOCKEY_BASE_DIR", "").strip()
    if base_override:
        p = Path(base_override).expanduser() / "cache"
        p.mkdir(parents=True, exist_ok=True)
        return p

    p = project / "cache"
    p.mkdir(parents=True, exist_ok=True)
    return p


def online_dir() -> Path:
    p = cache_dir() / "online"
    p.mkdir(parents=True, exist_ok=True)
    return p


def sims_dir(season: str) -> Path:
    p = online_dir() / "moneypuck" / str(season) / "simulations"
    p.mkdir(parents=True, exist_ok=True)
    return p


def nhl_dir(season: str) -> Path:
    p = online_dir() / "nhl" / str(season)
    p.mkdir(parents=True, exist_ok=True)
    return p


def pwhl_dir(season: str) -> Path:
    p = online_dir() / "pwhl" / str(season)
    p.mkdir(parents=True, exist_ok=True)
    return p


def espn_dir(season: str) -> Path:
    p = online_dir() / "espn" / str(season)
    p.mkdir(parents=True, exist_ok=True)
    return p


def logos_dir() -> Path:
    (cache_dir() / "logos").mkdir(parents=True, exist_ok=True)
    return cache_dir() / "logos"


def imgs_dir() -> Path:
    (cache_dir() / "images").mkdir(parents=True, exist_ok=True)
    return cache_dir() / "images"
