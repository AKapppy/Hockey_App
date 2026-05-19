from __future__ import annotations

import errno
import importlib
import sys
import time


def _import_runtime_app() -> object:
    """Import canonical runtime module."""
    return importlib.import_module("hockey_app.runtime.app")


def _is_deadlock_error(exc: Exception) -> bool:
    if isinstance(exc, OSError) and exc.errno == errno.EDEADLK:
        return True
    return "Resource deadlock avoided" in str(exc)


def main() -> None:
    """Entry point: delegate to the canonical cached runtime launcher."""

    mp = _import_runtime_app()
    max_retries = 5
    for i in range(max_retries + 1):
        try:
            mp.main()  # type: ignore[attr-defined]
            return
        except Exception as e:
            if _is_deadlock_error(e) and i < max_retries:
                time.sleep(0.15 * (i + 1))
                continue
            print(f"ERROR: app failed to launch: {e}")
            return


if __name__ == "__main__":
    # Support running as: python hockey_app/app.py
    # Ensure the *project root* (parent of the package) is on sys.path
    # so absolute imports like `import hockey_app` work.
    from pathlib import Path

    project_root = str(Path(__file__).resolve().parents[1])
    if project_root not in sys.path:
        sys.path.insert(0, project_root)
    main()
