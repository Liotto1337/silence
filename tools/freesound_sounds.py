#!/usr/bin/env python3
"""Builds assets/sounds/ from Freesound recordings (CC0 / CC BY, authors in CREDITS.md).

Downloads each sound's HQ preview once into a cache, then trims, slices multi-hit recordings into
single hits (by the loudness envelope), normalises and writes the files the game loads.

    FREESOUND_KEY=... python3 tools/freesound_sounds.py [--cache DIR] [--only NAME,...] [--out DIR]

Needs ffmpeg and numpy. The API key is read from the environment, never stored.
"""
import argparse
import json
import os
import subprocess
import urllib.request

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")

# breath.wav, breath_recover.wav and goal.wav are not built here: they are the 0.4 recordings.
# Each entry: Freesound id -> what to make of it.
#   "trim": [start, end] seconds of the recording to keep (end None = to the end)
#   "out": one file name, or "slices": [names] to cut that many single hits (loudest first, kept in time order),
#   or "parts": [[name, start, end], ...] for hand-picked sections
#   "max_len": longest slice, "peak": normalise to this dBFS, "fade": fade-out seconds, "speed": playback-rate change,
#   "drive": dB pushed into a soft clipper first (makes short hits with quiet tails as loud as the old sounds)
SPEC = [
    {"id": 48662, "out": "monster_roar.ogg", "trim": [0.0, 3.6], "peak": -1.0, "fade": 0.6},
    {"id": 161413, "slices": ["monster_step_1.wav", "monster_step_2.wav", "monster_step_3.wav", "monster_step_4.wav"], "max_len": 1.0, "peak": -2.0, "fade": 0.4, "drive": 20},
    {"id": 161413, "slices": ["monster_run_1.wav", "monster_run_2.wav", "monster_run_3.wav", "monster_run_4.wav"], "max_len": 0.42, "peak": -2.0, "fade": 0.15, "speed": 1.45, "drive": 20},
    {"id": 119914, "slices": ["step_walk_%d.wav" % i for i in range(1, 7)], "max_len": 0.45, "peak": -6.0, "fade": 0.15, "drive": 6},
    {"id": 459965, "slices": ["step_run_%d.wav" % i for i in range(1, 7)], "max_len": 0.35, "peak": -4.0, "fade": 0.1},
    {"id": 468443, "out": "toy_squeak.wav", "peak": -2.0, "fade": 0.05},
    {"id": 35291, "out": "tv_static.wav", "trim": [0.5, 5.5], "peak": -8.0, "fade": 0.0},
    {"id": 75162, "out": "amb_crow.ogg", "peak": -4.0, "fade": 0.3, "drive": 5},
    {"id": 813115, "out": "amb_crow_once.ogg", "peak": -4.0, "fade": 0.1},
    {"id": 249985, "out": "amb_electric_wave.ogg", "trim": [2.0, 16.0], "peak": -5.0, "fade": 2.0, "fade_in": 1.5},
    {"id": 332668, "out": "impact_thud.wav", "peak": -2.0, "fade": 0.1},
    {"id": 271096, "out": "fan_hum.wav", "peak": -6.0, "fade": 0.0},
    {"id": 329684, "slices": ["ball_bounce_1.wav", "ball_bounce_2.wav", "ball_bounce_3.wav"], "max_len": 0.3, "peak": -3.0, "fade": 0.1, "drive": 3},
    {"id": 133978, "slices": ["plastic_1.wav", "plastic_2.wav"], "max_len": 0.4, "peak": -3.0, "fade": 0.15},
    {"id": 245290, "out": "wood_block.wav", "trim": [0.0, 0.6], "peak": -3.0, "fade": 0.2, "drive": 4},
    {"id": 734580, "out": "car_ratchet.wav", "trim": [0.0, 2.3], "peak": -3.0, "fade": 0.2, "drive": 18},
    {"id": 568757, "out": "vase_hit.wav", "peak": -3.0, "fade": 0.1, "drive": 7},
    {"id": 128257, "out": "vase_break.wav", "peak": -1.0, "fade": 0.2},
    {"id": 167171, "parts": [["drawer_open.wav", 1.26, 2.2], ["drawer_close.wav", 6.74, 7.7]], "peak": -3.0, "fade": 0.2, "fade_in": 0.05, "drive": 4},
    {"id": 386445, "parts": [["cabinet_open.wav", 0.15, 1.5], ["cabinet_close.wav", 2.75, 3.9]], "peak": -3.0, "fade": 0.2},
    {"id": 216878, "out": "door_open.wav", "trim": [0.28, 1.5], "peak": -3.0, "fade": 0.4, "drive": 6},
    {"id": 117614, "out": "door_close.wav", "peak": -3.0, "fade": 0.2},
    {"id": 321087, "out": "door_locked.wav", "peak": -3.0, "fade": 0.1, "drive": 4},
]


def download(sid: int, cache: str, key: str) -> str:
    path = os.path.join(cache, f"{sid}.ogg")
    if not os.path.exists(path):
        req = urllib.request.Request(f"https://freesound.org/apiv2/sounds/{sid}/?fields=previews", headers={"Authorization": "Token " + key})
        url = json.load(urllib.request.urlopen(req))["previews"]["preview-hq-ogg"]
        with open(path, "wb") as f:
            f.write(urllib.request.urlopen(url).read())
    return path


def decode(path: str, speed: float = 1.0) -> np.ndarray:
    af = ["-af", f"asetrate={int(RATE * speed)},aresample={RATE}"] if speed != 1.0 else []
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, *af, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def envelope(x: np.ndarray, win: float = 0.01) -> np.ndarray:
    n = max(1, int(win * RATE))
    frames = len(x) // n
    return np.sqrt((x[:frames * n].reshape(frames, n) ** 2).mean(axis=1)), n


def slices(x: np.ndarray, count: int, max_len: float) -> list[np.ndarray]:
    """Single hits: onsets where the envelope jumps over a threshold, at least 0.12 s apart."""
    env, n = envelope(x)
    thr = env.max() * 0.25
    onsets = []
    above = False
    for i, v in enumerate(env):
        if v > thr and not above and (not onsets or i - onsets[-1] > 0.12 * RATE / n):
            onsets.append(i)
        above = v > thr * 0.6
    peaks = [(env[o:o + int(0.1 * RATE / n)].max(), o) for o in onsets]
    # Loudest hits first, but never two within one slice length (a double hit is one event).
    chosen = []
    for _, o in sorted(peaks, reverse=True):
        if len(chosen) < count and all(abs(o - c) * n > max_len * RATE * 0.8 for c in chosen):
            chosen.append(o)
    chosen.sort()
    out = []
    for o in chosen:
        start = max(0, o * n - int(0.01 * RATE))
        later = [p for p in chosen if p > o]
        end = min(len(x), start + int(max_len * RATE), later[0] * n - int(0.01 * RATE) if later else len(x))
        out.append(x[start:end])
    while len(out) < count:  # not enough hits: reuse with a tiny pitch-free variation in level
        out.append(out[len(out) % max(1, len(out))] * 0.9)
    return out


def finish(x: np.ndarray, peak_db: float, fade: float, fade_in: float = 0.005, drive: float = 0.0) -> np.ndarray:
    x = x - x.mean()
    if drive > 0.0:
        x = np.tanh(x / (np.abs(x).max() or 1.0) * 10 ** (drive / 20.0))
    peak = np.abs(x).max() or 1.0
    x = x * (10 ** (peak_db / 20.0) / peak)
    fi = min(len(x), int(fade_in * RATE))
    if fi > 0:
        x[:fi] *= np.linspace(0.0, 1.0, fi)
    fo = min(len(x), int(fade * RATE))
    if fo > 0:
        x[-fo:] *= np.linspace(1.0, 0.0, fo) ** 2
    return x


def write(x: np.ndarray, name: str, out_dir: str) -> None:
    path = os.path.join(out_dir, name)
    codec = ["-c:a", "libvorbis", "-q:a", "5"] if name.endswith(".ogg") else ["-c:a", "pcm_s16le"]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-", *codec, path], input=x.astype(np.float32).tobytes(), check=True)
    print(f"{name}: {len(x) / RATE:.2f} s")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(os.path.expanduser("~"), ".cache", "silence-freesound"))
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()
    key = os.environ["FREESOUND_KEY"]
    os.makedirs(a.cache, exist_ok=True)
    only = set(filter(None, a.only.split(",")))
    for spec in SPEC:
        names = spec.get("slices") or [p[0] for p in spec.get("parts", [])] or [spec["out"]]
        if only and not only.intersection(names):
            continue
        x = decode(download(spec["id"], a.cache, key), spec.get("speed", 1.0))
        if "trim" in spec:
            t0, t1 = spec["trim"]
            x = x[int(t0 * RATE):int(t1 * RATE) if t1 else None]
        if "parts" in spec:
            parts = [x[int(t0 * RATE):int(t1 * RATE)] for _, t0, t1 in spec["parts"]]
        elif "slices" in spec:
            parts = slices(x, len(names), spec["max_len"])
        else:
            parts = [x]
        for name, part in zip(names, parts):
            write(finish(part, spec["peak"], spec["fade"], spec.get("fade_in", 0.005), spec.get("drive", 0.0)), name, a.out)


if __name__ == "__main__":
    main()
