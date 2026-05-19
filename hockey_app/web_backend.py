from __future__ import annotations

import logging
import os
from functools import lru_cache
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from hockey_app.web_update import WebUpdateManager, manager_from_env


def _setup_logging() -> None:
    level = os.environ.get("HOCKEY_WEB_LOG_LEVEL", "INFO").upper()
    logging.basicConfig(level=getattr(logging, level, logging.INFO), format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@lru_cache(maxsize=1)
def _manager() -> WebUpdateManager:
    return manager_from_env()


def _allowed_origins() -> list[str]:
    raw = os.environ.get("HOCKEY_WEB_ALLOWED_ORIGINS", "*").strip()
    if not raw or raw == "*":
        return ["*"]
    return [part.strip() for part in raw.split(",") if part.strip()]


def create_app() -> FastAPI:
    _setup_logging()
    app = FastAPI(title="Hockey App Web Backend")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=_allowed_origins(),
        allow_credentials=False,
        allow_methods=["GET", "OPTIONS"],
        allow_headers=["*"],
    )

    @app.get("/api/health")
    def health() -> dict[str, Any]:
        mgr = _manager()
        return {
            "ok": True,
            "dataPath": str(mgr.data_json_path),
            "hasData": mgr.data_json_path.exists(),
        }

    @app.get("/api/data")
    def data(request: Request, force: bool = Query(False)) -> JSONResponse:
        mgr = _manager()
        host = request.client.host if request.client else "unknown"
        result = mgr.refresh_if_needed(trigger=host, force=force)
        payload = mgr.read_payload()
        status_code = 200 if payload is not None else 503
        return JSONResponse(
            {
                "ok": bool(result.ok and payload is not None),
                "update": result.to_dict(),
                "data": payload,
            },
            status_code=status_code,
            headers={"Cache-Control": "no-store"},
        )

    static_dir = Path(os.environ.get("HOCKEY_WEB_STATIC_DIR") or "docs")
    if static_dir.exists():
        app.mount("/", StaticFiles(directory=static_dir, html=True), name="static")

    return app


app = create_app()
