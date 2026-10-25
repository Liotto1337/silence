#!/usr/bin/env python3
"""Cuts the recorded sounds in assets/source/ into game-ready clips in assets/sounds/.

Footstep recordings are split into single steps so the game can play one clip per foot plant
(in sync with the head bob / monster walk cycle). Long sounds are trimmed and faded.

Needs ffmpeg and numpy. Run from the repo root: python3 tools/cut_sounds.py
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SRC = "assets/source"
OUT = "assets/sounds"
SR = 44100


def load(name: str) -> np.ndarray:
    """Decodes a source file to mono float32 at SR."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", os.path.join(SRC, name), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def refine_onset(x: np.ndarray, t: float, search: float = 0.06) -> int:
    """Moves an approximate onset time to the first sample above -30 dB of the local peak."""
    a = max(int((t - search) * SR), 0)
    b = min(int((t + search) * SR), len(x))
    seg = np.abs(x[a:b])
    if len(seg) == 0:
        return int(t * SR)
    thr = seg.max() * 0.03
    idx = int(np.argmax(seg > thr))
    return max(a + idx - int(0.004 * SR), 0)


def clip(x: np.ndarray, start: int, length: float, fade_in: float = 0.004, fade_out: float = 0.1) -> np.ndarray:
    y = x[start:start + int(length * SR)].copy()
    fi = max(int(fade_in * SR), 1)
    fo = max(int(fade_out * SR), 1)
    y[:fi] *= np.linspace(0.0, 1.0, fi)
    y[-fo:] *= np.linspace(1.0, 0.0, fo) ** 2
    return y


def normalize(y: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    peak = np.abs(y).max()
    return y if peak < 1e-6 else y * (10 ** (peak_db / 20.0) / peak)


def tempo(y: np.ndarray, factor: float) -> np.ndarray:
    """Time-stretches without changing pitch (ffmpeg atempo)."""
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "in.wav")
        write_wav(src, y)
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", src, "-filter:a", "atempo=%.3f" % factor, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
            check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def write_wav(path: str, y: np.ndarray) -> None:
    data = (np.clip(y, -1.0, 1.0) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def write_ogg(path: str, y: np.ndarray) -> None:
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, "tmp.wav")
        write_wav(tmp, y)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", path], check=True)


def save(name: str, y: np.ndarray) -> None:
    path = os.path.join(OUT, name)
    (write_ogg if name.endswith(".ogg") else write_wav)(path, y)
    print("%-28s %.2f s" % (name, len(y) / SR))


def main() -> None:
    os.makedirs(OUT, exist_ok=True)

    # Player walking: heel + toe of one step, ~0.36 s.
    x = load("zvuk_-_shagov.mp3")
    for i, t in enumerate([0.16, 0.85, 1.56, 2.25, 2.95, 7.66]):
        save("step_walk_%d.wav" % (i + 1), normalize(clip(x, refine_onset(x, t), 0.36, fade_out=0.12), -3.0))

    # Player running: one footfall every ~0.3 s in the recording.
    x = load("wova-zvuki-shagi-beg-po-betonnomu-polu.mp3")
    for i, t in enumerate([0.05, 0.99, 3.18, 4.96, 6.17, 8.59]):
        save("step_run_%d.wav" % (i + 1), normalize(clip(x, refine_onset(x, t), 0.26, fade_out=0.08), -2.0))

    # Monster: a heavy heel-toe stomp with a short tail for walking; the same stomps
    # time-compressed (deep pitch kept) and cut short for running, so steps don't smear.
    x = load("wova-zvuki-shagi-shagi-giganta-monstra-titana.mp3")
    for i, t in enumerate([0.87, 3.18, 4.97, 11.89]):
        start = refine_onset(x, t)
        save("monster_step_%d.wav" % (i + 1), normalize(clip(x, start, 1.0, fade_out=0.4), -1.0))
        fast = tempo(x[start:start + int(0.9 * SR)], 1.45)
        save("monster_run_%d.wav" % (i + 1), normalize(clip(fast, 0, 0.42, fade_out=0.14), -1.0))

    # Squeaky toy (the duck).
    x = load("the-sound-of-a-rubber-dog-toy.mp3")
    save("toy_squeak.wav", normalize(clip(x, refine_onset(x, 0.1), 0.42, fade_out=0.08), -1.0))

    # Monster provocation roar (hunt start): first 3.6 s of the 6.6 s scream, long fade.
    x = load("vyfvfya.mp3")
    save("monster_roar.ogg", normalize(clip(x, refine_onset(x, 0.37), 3.6, fade_out=1.1), -1.0))

    # Random night ambience.
    x = load("electric-wave-strange-horror-film-and-television-animation-background-sound-material.mp3")
    save("amb_electric_wave.ogg", normalize(clip(x, int(1.9 * SR), 9.5, fade_in=0.6, fade_out=2.5), -3.0))
    x = load("the-muffled-sound-of-a-crow-croaking-from-a-horror-movie.mp3")
    save("amb_crow.ogg", normalize(clip(x, 0, 2.15, fade_out=0.15), -3.0))
    save("amb_crow_once.ogg", normalize(clip(x, 0, 0.72, fade_out=0.15), -3.0))

    # Objective done: only the first of the three frog croaks.
    x = load("3-positive-and-optimistic-frog-sounds-to-get-the-sound-of-game-props.mp3")
    save("goal.wav", normalize(clip(x, refine_onset(x, 0.96), 0.85, fade_out=0.3), -3.0))

    # Prop impacts: one event per file, so the clip can play on every contact.
    x = load("the-sound-of-a-bouncing-plastic-ball-and-ball.mp3")
    for i, t in enumerate([0.63, 1.24, 1.74]):
        save("ball_bounce_%d.wav" % (i + 1), normalize(clip(x, refine_onset(x, t), 0.45, fade_out=0.15), -1.0))
    for i, name in enumerate(["пластик.mp3", "пластик2.mp3"]):
        x = load(name)
        save("plastic_%d.wav" % (i + 1), normalize(clip(x, refine_onset(x, 0.0), 0.7, fade_out=0.15), -1.0))
    x = load("clockwork-toy-sound-ratchet.mp3")
    save("car_ratchet.wav", normalize(clip(x, 0, 2.3, fade_out=0.2), -1.0))
    x = load("wood-block-movement-on-wood-floor_04.mp3")
    save("wood_block.wav", normalize(clip(x, refine_onset(x, 0.05), 0.6, fade_out=0.15), -1.0))
    x = load("не разбилась.mp3")
    save("vase_hit.wav", normalize(clip(x, refine_onset(x, 0.0), 1.5, fade_out=0.5), -1.0))
    x = load("разбилась.mp3")
    save("vase_break.wav", normalize(clip(x, refine_onset(x, 0.0), 0.6, fade_out=0.2), -1.0))

    # Furniture: the recordings hold the opening and the closing, split into two clips.
    x = load("desk-drawer-wooden-opened-closed.mp3")
    save("drawer_open.wav", normalize(clip(x, refine_onset(x, 0.8), 0.9, fade_out=0.2), -2.0))
    save("drawer_close.wav", normalize(clip(x, refine_onset(x, 3.65), 1.15, fade_out=0.3), -2.0))
    x = load("cabinet-door-small-cabinet-door-opens-and-closes.mp3")
    save("cabinet_open.wav", normalize(clip(x, refine_onset(x, 0.35), 0.75, fade_out=0.2), -2.0))
    save("cabinet_close.wav", normalize(clip(x, refine_onset(x, 3.6), 0.85, fade_out=0.25), -2.0))
    x = load("sounds-of-wooden-doors-assembly.mp3")
    save("door_open.wav", normalize(clip(x, refine_onset(x, 0.09), 0.8, fade_out=0.2), -2.0))
    save("door_close.wav", normalize(clip(x, refine_onset(x, 3.23), 0.65, fade_out=0.2), -2.0))
    # Locked door: a 1.35 s stretch of handle rattling out of the 8 s take.
    x = load("закрытая дверь.mp3")
    save("door_locked.wav", normalize(clip(x, int(1.0 * SR), 1.35, fade_in=0.03, fade_out=0.25), -2.0))

    # Out of breath: two breaths loop while exhausted, the shivering breath plays once on recovery.
    x = load("female-breathes-with-a-light-shiver-at-the-end.mp3")
    save("breath.wav", normalize(clip(x, 0, 3.55, fade_in=0.05, fade_out=0.3), -3.0))
    save("breath_recover.wav", normalize(clip(x, int(3.55 * SR), 2.35, fade_in=0.05, fade_out=0.4), -3.0))


if __name__ == "__main__":
    main()
