from __future__ import annotations

import datetime as dt
from pathlib import Path

import pandas as pd

from hockey_app.domain.colors import build_team_color_map
from hockey_app.config import TEAM_NAMES, canon_team_code, division_columns_for_codes
from hockey_app.data.paths import imgs_dir, sims_dir
from hockey_app.data.xml_cache import read_predictions_tables_xml, write_predictions_tables_xml
from hockey_app.runtime import logos as logosvc
from hockey_app.runtime import pipeline as pipesvc
from hockey_app.runtime.public_predictions import terminal_snapshot_for_season
from hockey_app.services.simulations import append_terminal_outcome
from hockey_app.runtime.prof import StartupProfiler
from hockey_app.runtime.settings import default_settings
from hockey_app.runtime.storage import ensure_dir_writable
from hockey_app.runtime.types import RuntimeSettings


_settings: RuntimeSettings = default_settings()

SEASON = _settings["season"]
START_DATE = _settings["start_date"]
END_DATE = _settings["end_date"]
from hockey_app.config import MONEYPUCK_END_DATE, MONEYPUCK_START_DATE
from hockey_app.domain.seasons import season_date_ranges

def _prediction_ui_end() -> dt.date:
    terminal = season_date_ranges(SEASON)["terminal_predictions"][0]
    return terminal if terminal < dt.date.today() else min(dt.date.today(), MONEYPUCK_END_DATE)

URL_SIMULATIONS = _settings["url_simulations"]
HEADERS = dict(_settings["headers"])
URL_LOGOS_BASE = _settings["url_logos_base"]

METRICS: dict[str, str] = dict(_settings["metrics"])
TAB_ORDER = list(_settings["tab_order"])
TAB_LABELS: dict[str, str] = dict(_settings["tab_labels"])
TAB_TITLES: dict[str, str] = dict(_settings["tab_titles"])

DARK_WINDOW_BG = _settings["dark_window_bg"]
DARK_CANVAS_BG = _settings["dark_canvas_bg"]
DARK_HILITE = _settings["dark_hilite"]

BASE = Path(__file__).resolve().parents[2]
ICLOUD_AVAILABLE = False
SIMS_DIR = sims_dir(SEASON)
# NHL logos are project-local so all machines use the same source files.
LOGOS_DIR = Path(__file__).resolve().parents[1] / "assets" / "nhl_logos"
LOGOS_DIR.mkdir(parents=True, exist_ok=True)
IMAGES_DIR = imgs_dir()


date_from_filename = pipesvc.date_from_filename
date_range = pipesvc.date_range
md_label = pipesvc.md_label


def download_missing_simulations(
    start_date: dt.date,
    end_date: dt.date,
    sims_dir: Path,
    index_url: str = URL_SIMULATIONS,
) -> list[str]:
    return pipesvc.download_missing_simulations(
        start_date=start_date,
        end_date=end_date,
        sims_dir=sims_dir,
        headers=HEADERS,
        ensure_dir_writable=ensure_dir_writable,
        index_url=index_url,
    )


def compile_probability_tables(
    sims_dir: Path,
    start_date: dt.date,
    end_date: dt.date,
) -> dict[str, pd.DataFrame]:
    return pipesvc.compile_probability_tables(
        sims_dir=sims_dir,
        start_date=start_date,
        end_date=end_date,
        metrics=METRICS,
        canon_team_code=canon_team_code,
    )


def _empty_probability_tables(start_date: dt.date, end_date: dt.date) -> dict[str, pd.DataFrame]:
    if end_date < start_date:
        end_date = start_date
    cols = [
        f"{(start_date + dt.timedelta(days=i)).month}/{(start_date + dt.timedelta(days=i)).day}"
        for i in range((end_date - start_date).days + 1)
    ] or [f"{start_date.month}/{start_date.day}"]
    codes = sorted(TEAM_NAMES.keys())
    return {
        metric_key: pd.DataFrame(
            {col: [float("nan") for _ in codes] for col in cols},
            index=codes,
            dtype="float64",
        )
        for metric_key in TAB_ORDER
    }


def logo_url(team_code: str) -> str:
    return logosvc.logo_url(team_code=team_code, canon_team_code=canon_team_code, url_base=URL_LOGOS_BASE)


def logo_path(team_code: str) -> Path:
    return logosvc.logo_path(team_code=team_code, canon_team_code=canon_team_code, logos_dir=LOGOS_DIR)


def ensure_logo_cached(team_code: str) -> None:
    logosvc.ensure_logo_cached(
        team_code=team_code,
        canon_team_code=canon_team_code,
        logos_dir=LOGOS_DIR,
        url_base=URL_LOGOS_BASE,
        headers=HEADERS,
    )


def launch_predictions_ui(
    tables: dict[str, pd.DataFrame],
    *,
    predictions_tables_stale: bool = False,
) -> None:
    from hockey_app.ui.app_window import launch_predictions_ui_window

    def _refresh_predictions_tables() -> dict[str, pd.DataFrame]:
        prediction_end = min(dt.date.today(), MONEYPUCK_END_DATE)
        errs = download_missing_simulations(MONEYPUCK_START_DATE, prediction_end, SIMS_DIR)
        if errs:
            print("ERRORS occurred during background simulation download:")
            for msg in errs:
                print(f"- {msg}")
        fresh_tables = compile_probability_tables(SIMS_DIR, MONEYPUCK_START_DATE, prediction_end)
        terminal_day, outcomes = terminal_snapshot_for_season(SEASON)
        fresh_tables = append_terminal_outcome(fresh_tables, terminal_day, outcomes)
        ui_end = _prediction_ui_end()
        keep = max(1, (ui_end - MONEYPUCK_START_DATE).days + 1)
        fresh_tables = {key: frame.iloc[:, :keep] for key, frame in fresh_tables.items()}
        try:
            write_predictions_tables_xml(
                season=SEASON,
                start=MONEYPUCK_START_DATE,
                end=ui_end,
                tables=fresh_tables,
            )
        except Exception:
            pass
        return fresh_tables

    launch_predictions_ui_window(
        tables,
        season=SEASON,
        start_date=MONEYPUCK_START_DATE,
        images_dir=IMAGES_DIR,
        tab_order=TAB_ORDER,
        tab_labels=TAB_LABELS,
        tab_titles=TAB_TITLES,
        team_names=TEAM_NAMES,
        dark_window_bg=DARK_WINDOW_BG,
        dark_canvas_bg=DARK_CANVAS_BG,
        dark_hilite=DARK_HILITE,
        canon_team_code=canon_team_code,
        division_columns_for_codes=division_columns_for_codes,
        build_team_color_map=build_team_color_map,
        ensure_logo_cached=ensure_logo_cached,
        logo_path=logo_path,
        predictions_tables_stale=predictions_tables_stale,
        refresh_predictions_tables=_refresh_predictions_tables if predictions_tables_stale else None,
    )


def main() -> None:
    print("Starting process...")
    prof = StartupProfiler()

    try:
        ensure_dir_writable(SIMS_DIR)
    except Exception as e:
        print(f"ERROR: {e}")
        return
    prof.mark("ensure_dir_writable")

    tables = read_predictions_tables_xml(season=SEASON, metrics=TAB_ORDER)
    prediction_end = _prediction_ui_end()
    expected_last_col = f"{prediction_end.month}/{prediction_end.day}"
    has_complete_xml = bool(tables) and all(
        k in tables and not tables[k].empty and len(tables[k].columns) > 0 and str(tables[k].columns[-1]) == expected_last_col
        for k in TAB_ORDER
    )
    terminal_required = season_date_ranges(SEASON)["terminal_predictions"][0] < dt.date.today()
    if has_complete_xml and terminal_required:
        has_complete_xml = all(
            set(pd.to_numeric(tables[k].iloc[:, -1], errors="coerce").dropna().tolist()).issubset({0.0, 1.0})
            for k in TAB_ORDER
        )

    if not has_complete_xml and not tables:
        tables = _empty_probability_tables(MONEYPUCK_START_DATE, prediction_end)
        prof.mark("prepare_prediction_placeholders")
    else:
        prof.mark("load_predictions_tables_xml")

    try:
        launch_predictions_ui(tables, predictions_tables_stale=not has_complete_xml)
    except Exception as e:
        print(f"ERROR: failed to launch UI: {e}")
        return
    prof.mark("launch_predictions_ui")
    prof.emit()

    print("Done.")


if __name__ == "__main__":
    main()
