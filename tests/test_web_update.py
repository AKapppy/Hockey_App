from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from hockey_app.web_update import WebUpdateManager


class WebUpdateManagerTests(unittest.TestCase):
    def test_refresh_reuses_export_and_cache_window_skips_repeat(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            calls: list[Path] = []

            def fake_export_web(**kwargs):
                calls.append(kwargs["out_dir"])
                payload = {
                    "metadata": {"generatedAt": "2026-05-19T12:00:00+00:00"},
                    "metrics": [],
                    "teams": [],
                    "tables": {},
                }
                (out_dir / "data.json").write_text(json.dumps(payload), encoding="utf-8")
                (out_dir / "data.js").write_text("window.HOCKEY_APP_DATA = {};\n", encoding="utf-8")
                return out_dir / "data.js"

            manager = WebUpdateManager(
                out_dir=out_dir,
                season="2025-2026",
                min_interval_s=3600,
            )
            with patch("hockey_app.web_update.export_web", side_effect=fake_export_web):
                first = manager.refresh_if_needed(force=True)
                second = manager.refresh_if_needed()

            self.assertTrue(first.ok)
            self.assertTrue(first.refreshed)
            self.assertTrue(second.ok)
            self.assertTrue(second.skipped)
            self.assertEqual(calls, [out_dir])

    def test_failed_refresh_returns_error_without_deleting_existing_data(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            existing = {"metadata": {}, "metrics": [], "teams": [], "tables": {"madeplayoffs": {}}}
            (out_dir / "data.json").write_text(json.dumps(existing), encoding="utf-8")
            manager = WebUpdateManager(
                out_dir=out_dir,
                season="2025-2026",
                min_interval_s=0,
            )

            with patch("hockey_app.web_update.LOG.exception") as log_exception, patch(
                "hockey_app.web_update.export_web",
                side_effect=RuntimeError("boom"),
            ):
                result = manager.refresh_if_needed(force=True)

            self.assertFalse(result.ok)
            self.assertIn("boom", result.error or "")
            self.assertEqual(manager.read_payload(), existing)
            log_exception.assert_called_once()

    def test_system_exit_refresh_failure_is_reported_not_raised(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            manager = WebUpdateManager(
                out_dir=out_dir,
                season="2025-2026",
                min_interval_s=0,
            )

            with patch("hockey_app.web_update.LOG.exception"), patch(
                "hockey_app.web_update.export_web",
                side_effect=SystemExit("no data"),
            ):
                result = manager.refresh_if_needed(force=True)

            self.assertFalse(result.ok)
            self.assertIn("no data", result.error or "")


if __name__ == "__main__":
    unittest.main()
