from __future__ import annotations

import datetime as dt
import json
import logging
import shutil
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from hockey_app.tools.export_web import _default_season, export_web

LOG = logging.getLogger(__name__)


def _utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _parse_date(value: str | None) -> dt.date | None:
    if not value:
        return None
    return dt.date.fromisoformat(value)


@dataclass(frozen=True)
class UpdateResult:
    ok: bool
    refreshed: bool
    skipped: bool
    message: str
    started_at: str
    finished_at: str
    data_path: str
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class FileUpdateLock:
    """Small cross-process lock based on atomic directory creation."""

    def __init__(self, lock_dir: Path, *, timeout_s: float = 120.0, stale_after_s: float = 900.0) -> None:
        self.lock_dir = lock_dir
        self.timeout_s = max(0.0, float(timeout_s))
        self.stale_after_s = max(1.0, float(stale_after_s))
        self.acquired = False

    def __enter__(self) -> "FileUpdateLock":
        deadline = time.monotonic() + self.timeout_s
        self.lock_dir.parent.mkdir(parents=True, exist_ok=True)
        while True:
            try:
                self.lock_dir.mkdir()
                (self.lock_dir / "created_at").write_text(_utc_now().isoformat(timespec="seconds"), encoding="utf-8")
                self.acquired = True
                return self
            except FileExistsError:
                self._remove_if_stale()
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"Timed out waiting for update lock at {self.lock_dir}")
                time.sleep(0.25)

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        if self.acquired:
            shutil.rmtree(self.lock_dir, ignore_errors=True)
            self.acquired = False

    def _remove_if_stale(self) -> None:
        try:
            age = time.time() - self.lock_dir.stat().st_mtime
        except FileNotFoundError:
            return
        except Exception:
            return
        if age > self.stale_after_s:
            LOG.warning("Removing stale web data update lock at %s", self.lock_dir)
            shutil.rmtree(self.lock_dir, ignore_errors=True)


class WebUpdateManager:
    def __init__(
        self,
        *,
        out_dir: Path,
        season: str | None = None,
        start: dt.date | None = None,
        end: dt.date | None = None,
        min_interval_s: float = 900.0,
        lock_timeout_s: float = 120.0,
        stale_lock_s: float = 900.0,
    ) -> None:
        self.out_dir = out_dir
        self.season = season or _default_season()
        self.start = start
        self.end = end
        self.min_interval_s = max(0.0, float(min_interval_s))
        self.lock_timeout_s = max(0.0, float(lock_timeout_s))
        self.stale_lock_s = max(1.0, float(stale_lock_s))

    @property
    def data_json_path(self) -> Path:
        return self.out_dir / "data.json"

    @property
    def data_js_path(self) -> Path:
        return self.out_dir / "data.js"

    @property
    def lock_dir(self) -> Path:
        return self.out_dir / ".web-data-update.lock"

    def read_payload(self) -> dict[str, Any] | None:
        try:
            raw = json.loads(self.data_json_path.read_text(encoding="utf-8"))
        except Exception:
            return None
        return raw if isinstance(raw, dict) else None

    def refresh_if_needed(self, *, trigger: str = "web visitor", force: bool = False) -> UpdateResult:
        started = _utc_now()
        LOG.info("Web visitor triggered data update check: trigger=%s out_dir=%s", trigger, self.out_dir)

        if not force and self._data_is_fresh():
            return self._result(
                ok=True,
                refreshed=False,
                skipped=True,
                message="Cached web data is still fresh.",
                started=started,
            )

        try:
            with FileUpdateLock(self.lock_dir, timeout_s=self.lock_timeout_s, stale_after_s=self.stale_lock_s):
                if not force and self._data_is_fresh():
                    return self._result(
                        ok=True,
                        refreshed=False,
                        skipped=True,
                        message="Another visitor already refreshed the data.",
                        started=started,
                    )

                LOG.info(
                    "Web data pull started: season=%s start=%s end=%s out_dir=%s",
                    self.season,
                    self.start,
                    self.end,
                    self.out_dir,
                )
                data_path = export_web(
                    out_dir=self.out_dir,
                    season=self.season,
                    start=self.start,
                    end=self.end,
                    refresh=True,
                )
                LOG.info("Web data files updated: %s and %s", self.data_json_path, data_path)
                return self._result(
                    ok=True,
                    refreshed=True,
                    skipped=False,
                    message="Web data refreshed.",
                    started=started,
                )
        except SystemExit as exc:
            LOG.exception("Web data update failed")
            return self._result(
                ok=False,
                refreshed=False,
                skipped=False,
                message="Web data update failed; serving the last available data if present.",
                started=started,
                error=str(exc),
            )
        except Exception as exc:
            LOG.exception("Web data update failed")
            return self._result(
                ok=False,
                refreshed=False,
                skipped=False,
                message="Web data update failed; serving the last available data if present.",
                started=started,
                error=str(exc),
            )

    def _data_is_fresh(self) -> bool:
        try:
            age = time.time() - self.data_json_path.stat().st_mtime
        except Exception:
            return False
        return age < self.min_interval_s

    def _result(
        self,
        *,
        ok: bool,
        refreshed: bool,
        skipped: bool,
        message: str,
        started: dt.datetime,
        error: str | None = None,
    ) -> UpdateResult:
        return UpdateResult(
            ok=ok,
            refreshed=refreshed,
            skipped=skipped,
            message=message,
            started_at=started.isoformat(timespec="seconds"),
            finished_at=_utc_now().isoformat(timespec="seconds"),
            data_path=str(self.data_json_path),
            error=error,
        )


def manager_from_env() -> WebUpdateManager:
    import os

    out_dir = Path(os.environ.get("HOCKEY_WEB_DATA_DIR") or os.environ.get("HOCKEY_WEB_OUT_DIR") or "docs")
    return WebUpdateManager(
        out_dir=out_dir,
        season=os.environ.get("HOCKEY_WEB_SEASON") or None,
        start=_parse_date(os.environ.get("HOCKEY_WEB_START")),
        end=_parse_date(os.environ.get("HOCKEY_WEB_END")),
        min_interval_s=float(os.environ.get("HOCKEY_WEB_REFRESH_SECONDS", "900")),
        lock_timeout_s=float(os.environ.get("HOCKEY_WEB_LOCK_TIMEOUT_SECONDS", "120")),
        stale_lock_s=float(os.environ.get("HOCKEY_WEB_STALE_LOCK_SECONDS", "900")),
    )
