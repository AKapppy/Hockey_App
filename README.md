# Hockey App

[Launch the web app](https://akapppy.github.io/hockey_app/)

Desktop hockey dashboard app (Tkinter) with:
- Predictions (MoneyPuck simulation tables + charts)
- Stats: Games + Points (with cache-first NHL data loading)

It also includes a static web version in `docs/` for GitHub Pages.

## Run

### Option A: Double-click (macOS)

1. Install dependencies (see below).
2. Double-click `run.command`.

### Option B: Terminal

From the project folder:

```bash
python3 -m hockey_app
```

## Web Version

The web app lives in `docs/` and can still run as a static GitHub Pages site. Static hosting cannot run Python or write refreshed files when a visitor opens the page, so GitHub Pages alone cannot perform a per-visit data update.

Open the hosted version:

```text
https://akapppy.github.io/hockey_app/
```

Build or refresh the static data from local cached MoneyPuck CSVs:

```bash
python3 -m hockey_app.tools.export_web --out docs
```

Download missing MoneyPuck simulation CSVs first, then rebuild:

```bash
python3 -m hockey_app.tools.export_web --out docs --refresh
```

The GitHub Pages workflow also runs this refresh/export hourly. GitHub Pages is static hosting, so a page view cannot itself update repository data; the scheduled workflow is the automatic update path.

Open `docs/index.html` directly, or serve the folder locally:

```bash
python3 -m http.server 8000 --directory docs
```

Then visit:

```text
http://localhost:8000
```

### Live Web Updates With a Backend

For per-visitor refreshes, deploy the Python backend instead of relying on GitHub Pages alone:

```bash
uvicorn hockey_app.web_backend:app --host 0.0.0.0 --port 8000
```

Then visit:

```text
http://localhost:8000
```

When the page loads, `docs/app.js` calls `/api/data`. The backend uses `hockey_app.tools.export_web(..., refresh=True)`, so it reuses the same MoneyPuck simulation download/compile path and the desktop XML-backed refresh/export logic before returning the refreshed `data.json` payload.

If the static GitHub Pages frontend should call a separately hosted backend, set `docs/config.js`:

```js
window.HOCKEY_APP_CONFIG = {
  apiBase: "https://your-backend.example.com",
  dataEndpoint: "",
};
```

Backend environment variables:

```text
HOCKEY_WEB_DATA_DIR=/persistent/path/docs-data
HOCKEY_CACHE_DIR=/persistent/path/cache
HOCKEY_WEB_STATIC_DIR=docs
HOCKEY_WEB_REFRESH_SECONDS=900
HOCKEY_WEB_ALLOWED_ORIGINS=https://akapppy.github.io
```

`HOCKEY_WEB_DATA_DIR` and `HOCKEY_CACHE_DIR` should point at persistent storage in production. If the host has only ephemeral or read-only filesystems, the backend can serve the current bundled data but cannot truthfully persist refreshed files across restarts. In that case, keep using the scheduled GitHub Actions export or deploy the backend on a platform with a persistent volume.

### GitHub Pages

This repo includes `.github/workflows/pages.yml`, which builds the static web app and publishes it with GitHub Pages on pushes to `main`, on an hourly schedule, or by manual workflow dispatch.

After pushing to GitHub:

1. Open the repository settings.
2. Go to **Pages**.
3. Set the source to **GitHub Actions**.
4. Run the **Publish Web App** workflow, or push to `main`.

The checked-in `docs/` folder can also be used as a Pages source if you prefer the simpler `main` branch `/docs` setup.

## Cache Doctor

Inspect cache for legacy/redundant paths:

```bash
python3 -m hockey_app cache doctor
```

Clean known-safe legacy artifacts:

```bash
python3 -m hockey_app cache doctor --clean
```

## Architecture (Current)

Canonical runtime and UI modules:
- `hockey_app/runtime/app.py`: app runtime entry module used by `hockey_app.app`
- `hockey_app/runtime/`: runtime settings, storage/path picking, pipeline wrappers, logo fetch helpers
- `hockey_app/ui/app_window.py`: top-level UI assembly/orchestration
- `hockey_app/ui/notebook_scaffold.py`: notebook/page/tab scaffold builders
- `hockey_app/ui/predictions_mount.py`: predictions tab mounting
- `hockey_app/ui/stats_mount.py`: stats tab mounting
- `hockey_app/ui/renderers/`: chart/table renderers
- `hockey_app/ui/tabs/`: concrete tab hosts/components (`games_host.py`, `points.py`, `stats_games.py`)
- `hockey_app/domain/`: team/color domain data/helpers
- `hockey_app/services/simulations.py`: MoneyPuck CSV pipeline functions

Deprecated compatibility aliases have been removed. `python3 -m hockey_app` now uses only canonical module paths.

## Install dependencies

From the project folder:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

## Sanity Checks

Compile check:

```bash
python3 -m compileall -q hockey_app
```

Smoke tests:

```bash
python3 -m unittest discover -s tests -v
```

Optional startup profiling:

```bash
HOCKEY_PROFILE_STARTUP=1 python3 -m hockey_app
```

This prints stage timings for pipeline + UI startup.

## Data location

The app reads/writes a folder named **`MoneyPuck Data`** in a default base location picked by the code (prefers iCloud Drive if present). The terminal output shows the exact path it is using each run.
