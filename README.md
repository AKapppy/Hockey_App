# Hockey App

[Launch the web app](https://akapppy.github.io/Hockey_App/)

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
https://akapppy.github.io/Hockey_App/
```

Build or refresh the static data from local cached MoneyPuck CSVs:

```bash
python3 -m hockey_app.tools.export_web --out docs
```

Download missing MoneyPuck simulation CSVs first, then rebuild:

```bash
python3 -m hockey_app.tools.export_web --out docs --refresh
```

The GitHub Pages workflow runs this refresh/export hourly and deploys the generated `docs/` artifact directly. Generated `data.js`, `data.json`, and season payloads are intentionally not tracked. GitHub Pages is static hosting, so a browser page view cannot itself update data; the scheduled/manual workflow is the automatic update path.

On a fresh clone, run the exporter before opening the web app. Then open `docs/index.html` directly, or serve the folder locally:

```bash
python3 -m http.server 8000 --directory docs
```

Then visit:

```text
http://localhost:8000
```

### GitHub Pages

This repo includes `.github/workflows/pages.yml`, which builds the static web app and publishes it with GitHub Pages on pushes to `main`, on an hourly schedule, or by manual workflow dispatch.

After pushing to GitHub:

1. Open the repository settings.
2. Go to **Pages**.
3. Set the source to **GitHub Actions**.
4. Run the **Publish Web App** workflow, or push to `main`.

The workflow-generated Pages artifact is the supported deployment path.

## Cache Doctor

Inspect cache for legacy/redundant paths:

```bash
python3 -m hockey_app cache doctor
```

Clean known-safe legacy artifacts:

```bash
python3 -m hockey_app cache doctor --clean
```

## Static payload layout

The generated `data.js` is the scoreboard bootstrap. Full stats, predictions, and models remain in `data.json`, and historical seasons are loaded only when selected. A later performance pass can split the full payload into separate Stats, Predictions, and Models files; this correctness pass keeps the existing frontend contract stable.

Magic/Tragic values are planning estimates based on the available standings and tiebreak data. They are not official or mathematically exhaustive clinch and elimination determinations.

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
