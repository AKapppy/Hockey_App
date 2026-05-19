from __future__ import annotations

import math
from pathlib import Path
import tkinter as tk
from typing import Any, Callable, TypeAlias

from hockey_app.domain.colors import _hex_to_rgb

try:
    from PIL import Image, ImageTk  # type: ignore

    PIL_OK = True
except Exception:
    Image = None
    ImageTk = None
    PIL_OK = False

TkImg: TypeAlias = Any
RawImg: TypeAlias = Any


def _apply_dim_rgba(img: RawImg, dim_amt: float) -> RawImg:
    if not PIL_OK:
        return img
    amt = max(0.0, min(1.0, float(dim_amt)))
    if amt >= 0.999:
        return img
    try:
        out = img.copy()
        alpha = out.getchannel("A")
        alpha = alpha.point(lambda px: int(round(float(px) * amt)))
        out.putalpha(alpha)
        return out
    except Exception:
        return img


def _visible_area_height_scale(
    area_factor: float,
    aspect_ratio: float | None = None,
    *,
    target_area_factor: float = 0.95,
    min_scale: float = 0.72,
    max_scale: float = 1.18,
) -> float:
    del aspect_ratio
    area_factor = max(0.001, float(area_factor))
    target = max(0.001, float(target_area_factor))
    scale = math.sqrt(target / area_factor)
    return max(float(min_scale), min(float(max_scale), scale))


def _geometric_area_factor_rgba(
    img: RawImg,
    *,
    alpha_threshold: int = 8,
) -> float | None:
    if not PIL_OK:
        return None
    try:
        w, h = img.size
        if w <= 0 or h <= 0:
            return None
        threshold = max(0, min(254, int(alpha_threshold)))
        alpha = img.getchannel("A")
        mask = alpha.point(lambda px: 255 if int(px) > threshold else 0)
        bbox = mask.getbbox()
        if bbox is None:
            return None
        left, top, right, bottom = bbox
        footprint_w = max(1, int(right) - int(left))
        footprint_h = max(1, int(bottom) - int(top))
        return float(footprint_w * footprint_h) / float(h * h)
    except Exception:
        return None


def _crop_transparent_padding_rgba(img: RawImg, *, alpha_threshold: int = 8) -> RawImg:
    if not PIL_OK:
        return img
    try:
        threshold = max(0, min(254, int(alpha_threshold)))
        alpha = img.getchannel("A")
        mask = alpha.point(lambda px: 255 if int(px) > threshold else 0)
        bbox = mask.getbbox()
        if bbox is None:
            return img
        return img.crop(bbox)
    except Exception:
        return img


class LogoBank:
    """
    Loads original PNGs once and returns resized Tk images on demand.
    Uses Pillow if available; otherwise falls back to tk.PhotoImage subsample.
    Also exposes raw aspect ratios so we can size logos without overlap.
    """

    def __init__(
        self,
        root: tk.Tk,
        bg_hex: str,
        *,
        canon_team_code: Callable[[str], str],
        ensure_logo_cached: Callable[[str], None],
        logo_path: Callable[[str], Path],
    ):
        self.root = root
        self.bg_hex = bg_hex
        self._canon_team_code = canon_team_code
        self._ensure_logo_cached = ensure_logo_cached
        self._logo_path = logo_path

        self._raw: dict[str, RawImg] = {}
        self._tk_cache: dict[tuple[str, int, bool, int, bool, int], TkImg] = {}
        self._ar_cache: dict[str, float] = {}
        self._geometric_area_cache: dict[str, float] = {}

    def _load_code_if_needed(self, code: str) -> bool:
        code = self._canon_team_code(code)
        if code in self._raw:
            return True
        self._ensure_logo_cached(code)
        p = self._logo_path(code)
        if not p.exists():
            return False
        if PIL_OK:
            try:
                img = Image.open(str(p)).convert("RGBA")  # type: ignore
                img = _crop_transparent_padding_rgba(img)
                self._raw[code] = img
                return True
            except Exception:
                return False
        try:
            img = tk.PhotoImage(master=self.root, file=str(p))
            self._raw[code] = img
            return True
        except Exception:
            return False

    def load_codes(self, codes: list[str]) -> None:
        for c in codes:
            code = self._canon_team_code(c)
            self._load_code_if_needed(code)

    def _get_bg_rgba(self, size: tuple[int, int]):
        r, g, b = _hex_to_rgb(self.bg_hex)
        return Image.new("RGBA", size, (r, g, b, 255))  # type: ignore

    def aspect_ratio(self, code: str) -> float | None:
        code = self._canon_team_code(code)
        if code in self._ar_cache:
            return self._ar_cache[code]
        if not self._load_code_if_needed(code):
            return None
        raw = self._raw.get(code)
        if raw is None:
            return None
        try:
            if PIL_OK:
                w, h = raw.size
            else:
                w, h = raw.width(), raw.height()
            if h <= 0:
                return None
            ar = float(w) / float(h)
            self._ar_cache[code] = ar
            return ar
        except Exception:
            return None

    def geometric_area_factor(self, code: str) -> float | None:
        code = self._canon_team_code(code)
        if code in self._geometric_area_cache:
            return self._geometric_area_cache[code]
        if not PIL_OK:
            return None
        if not self._load_code_if_needed(code):
            return None
        raw = self._raw.get(code)
        if raw is None:
            return None
        area_factor = _geometric_area_factor_rgba(raw)
        if area_factor is not None:
            self._geometric_area_cache[code] = area_factor
            return area_factor
        return None

    def normalized_height(
        self,
        code: str,
        height: int,
        *,
        target_area_factor: float = 0.95,
    ) -> int:
        h = int(max(1, height))
        area_factor = self.geometric_area_factor(code)
        if area_factor is None:
            return h
        scale = _visible_area_height_scale(
            area_factor,
            target_area_factor=target_area_factor,
        )
        return int(max(1, round(float(h) * scale)))

    def get(
        self,
        code: str,
        height: int,
        dim: bool = False,
        dim_amt: float = 0.55,
        normalize_area: bool = False,
        target_area_factor: float = 0.95,
    ) -> TkImg | None:
        code = self._canon_team_code(code)
        h = (
            self.normalized_height(code, height, target_area_factor=target_area_factor)
            if normalize_area
            else int(max(1, height))
        )
        dim_key = int(round(float(dim_amt) * 100))
        target_key = int(round(float(target_area_factor) * 100))
        key = (code, h, bool(dim), dim_key, bool(normalize_area), target_key)
        if key in self._tk_cache:
            return self._tk_cache[key]

        if not self._load_code_if_needed(code):
            return None
        raw = self._raw.get(code)
        if raw is None:
            return None

        if PIL_OK:
            try:
                w0, h0 = raw.size
                if h0 <= 0:
                    return None
                scale = float(h) / float(h0)
                w = max(1, int(round(w0 * scale)))
                try:
                    resample = Image.Resampling.LANCZOS  # type: ignore
                except Exception:
                    resample = Image.LANCZOS  # type: ignore
                out = raw.resize((w, h), resample=resample)
                if dim:
                    out = _apply_dim_rgba(out, dim_amt)

                tkimg = ImageTk.PhotoImage(out)  # type: ignore
                self._tk_cache[key] = tkimg
                return tkimg
            except Exception:
                return None

        try:
            h0 = raw.height()
            if h0 <= 0:
                return None
            if h0 > h:
                factor = max(1, int(math.ceil(h0 / h)))
                out = raw.subsample(factor)
            else:
                out = raw
            self._tk_cache[key] = out
            return out
        except Exception:
            return None
