#!/usr/bin/env python3
"""Generates the PS1-style tileable textures in assets/textures/ (64x64, few grey levels, dithered).

The textures are neutral detail maps: the shader multiplies them by each part's colour, so one
"wood" texture serves every wood tone. Run: python3 tools/gen_textures.py
"""
import os

import numpy as np
from PIL import Image

SIZE = 64
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 0.5


def rng(name: str) -> np.random.Generator:
    return np.random.default_rng(sum(ord(c) * (i + 1) for i, c in enumerate(name)))


def tile_noise(r: np.random.Generator, cell: int) -> np.ndarray:
    """Tileable value noise: random grid of `cell` px, bilinearly upsampled with wrap-around."""
    n = SIZE // cell
    g = r.random((n, n))
    ys, xs = np.mgrid[0:SIZE, 0:SIZE] / cell
    x0, y0 = xs.astype(int) % n, ys.astype(int) % n
    x1, y1 = (x0 + 1) % n, (y0 + 1) % n
    fx, fy = xs - np.floor(xs), ys - np.floor(ys)
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    return (g[y0, x0] * (1 - fx) + g[y0, x1] * fx) * (1 - fy) + (g[y1, x0] * (1 - fx) + g[y1, x1] * fx) * fy


def finish(name: str, v: np.ndarray, levels: int = 6, lo: float = 0.3, hi: float = 1.0, gain: float = 1.7) -> None:
    """Stretches contrast, maps v to [lo, hi], dithers with a 4x4 Bayer matrix, quantizes and saves."""
    v = np.clip((v - v.mean()) * gain + 0.68, 0.0, 1.0)
    v = lo + v * (hi - lo)
    bayer = np.tile(BAYER, (SIZE // 4, SIZE // 4))
    q = np.clip(np.round(v * (levels - 1) + bayer * 0.9), 0, levels - 1) / (levels - 1)
    # Slightly warm shadows / cool highlights keeps the grey from looking dead.
    rgb = np.stack([q, q * 0.985 + 0.004, q * 0.96 + 0.01], axis=-1)
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name + ".png"))


def wood() -> None:
    """Floor planks: 4 boards across, staggered seams, grain streaks, a few knots."""
    r = rng("wood")
    v = np.zeros((SIZE, SIZE))
    plank_w = SIZE // 4
    for p in range(4):
        x0 = p * plank_w
        base = 0.55 + 0.25 * r.random()
        grain = tile_noise(r, 4)[:, x0:x0 + plank_w]
        streak = np.sin((np.arange(plank_w)[None, :] + r.random() * 9) * 0.9 + grain * 5.0) * 0.5 + 0.5
        v[:, x0:x0 + plank_w] = base + (streak - 0.5) * 0.28 + (grain - 0.5) * 0.25
        v[:, x0] = 0.12  # seam between boards
        seam_y = int(r.integers(8, SIZE - 8))
        v[seam_y, x0:x0 + plank_w] = 0.15  # butt joint
        ky, kx = int(r.integers(6, SIZE - 6)), x0 + int(r.integers(4, plank_w - 4))
        if p % 2 == 0:
            yy, xx = np.ogrid[0:SIZE, 0:SIZE]
            v[((yy - ky) ** 2 + ((xx - kx) * 1.6) ** 2) < 5] -= 0.3
    finish("wood", v)


def wood_dark() -> None:
    """Furniture: vertical grain without plank seams."""
    r = rng("wood_dark")
    grain = tile_noise(r, 4)
    fine = tile_noise(r, 2)
    streak = np.sin(np.arange(SIZE)[None, :] * 1.3 + grain * 6.0) * 0.5 + 0.5
    v = 0.62 + (streak - 0.5) * 0.35 + (fine - 0.5) * 0.18
    v[:, ::32] -= 0.12
    finish("wood_dark", v, levels=5)


def carpet() -> None:
    r = rng("carpet")
    v = 0.7 + (r.random((SIZE, SIZE)) - 0.5) * 0.5 + (tile_noise(r, 8) - 0.5) * 0.35
    finish("carpet", v, levels=6)


def tile() -> None:
    """Bathroom / kitchen tiles: 4x4 grid, grout lines, per-tile brightness and a stain."""
    r = rng("tile")
    v = np.zeros((SIZE, SIZE))
    cell = SIZE // 4
    for ty in range(4):
        for tx in range(4):
            v[ty * cell:(ty + 1) * cell, tx * cell:(tx + 1) * cell] = 0.78 + r.random() * 0.2
    v += (tile_noise(r, 8) - 0.5) * 0.2
    v[::cell, :] = 0.25
    v[:, ::cell] = 0.25
    v[1::cell, :] -= 0.1
    v[:, 1::cell] -= 0.1
    finish("tile", v, levels=6, lo=0.25)


def wallpaper() -> None:
    """Faded striped wallpaper with a small repeating diamond."""
    r = rng("wallpaper")
    x = np.arange(SIZE)[None, :]
    v = np.where((x // 8) % 2 == 0, 0.86, 0.78) * np.ones((SIZE, SIZE))
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    d = np.abs((xx % 16) - 7.5) + np.abs((yy % 16) - 7.5)
    v[(d < 3) & ((xx // 8) % 2 == 1)] -= 0.18
    v += (tile_noise(r, 8) - 0.5) * 0.18 + (r.random((SIZE, SIZE)) - 0.5) * 0.06
    finish("wallpaper", v, levels=6, lo=0.45, gain=0.9)


def plaster() -> None:
    """Ceiling: blotchy plaster with hairline cracks."""
    r = rng("plaster")
    v = 0.85 + (tile_noise(r, 16) - 0.5) * 0.3 + (tile_noise(r, 4) - 0.5) * 0.15
    y, x = int(r.integers(0, SIZE)), 0
    for _ in range(SIZE):
        v[y % SIZE, x % SIZE] -= 0.35
        x += 1
        y += int(r.integers(-1, 2))
    finish("plaster", v, levels=5, lo=0.5, gain=0.9)


def fabric() -> None:
    """Blankets, sofa, rugs: diagonal weave."""
    r = rng("fabric")
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    weave = ((xx + yy) % 4 < 2).astype(float) * 0.3 + ((xx - yy) % 8 < 4).astype(float) * 0.15
    v = 0.55 + weave + (tile_noise(r, 8) - 0.5) * 0.2
    finish("fabric", v, levels=6, lo=0.3)


def metal() -> None:
    """Vents, fridge, ducts: brushed streaks and rust blotches."""
    r = rng("metal")
    streak = np.repeat(r.random((SIZE, 1)), SIZE, axis=1)
    v = 0.7 + (streak - 0.5) * 0.25 + (tile_noise(r, 8) - 0.5) * 0.2
    rust = tile_noise(r, 16)
    v[rust > 0.68] -= 0.3
    v[::16, :] -= 0.15
    finish("metal", v, levels=5, lo=0.35, gain=1.0)


def grain() -> None:
    """Default for anything untextured: fine dirt so flat colours never read as plastic."""
    r = rng("grain")
    v = 0.78 + (r.random((SIZE, SIZE)) - 0.5) * 0.3 + (tile_noise(r, 8) - 0.5) * 0.25
    finish("grain", v, levels=6, lo=0.3)


def concrete() -> None:
    r = rng("concrete")
    v = 0.7 + (tile_noise(r, 4) - 0.5) * 0.35 + (r.random((SIZE, SIZE)) - 0.5) * 0.15
    pits = r.random((SIZE, SIZE)) > 0.97
    v[pits] -= 0.3
    finish("concrete", v, levels=5, lo=0.3)


if __name__ == "__main__":
    for fn in (wood, wood_dark, carpet, tile, wallpaper, plaster, fabric, metal, grain, concrete):
        fn()
    print("textures written to", os.path.abspath(OUT))
