#!/usr/bin/env python3
"""Procedurally generates the alpha's placeholder sound effects into assets/sounds/.

Only the sounds that have no recording yet: monster growl, TV static, impact thud,
vent fan hum and exhausted breathing. Recorded sounds are cut by tools/cut_sounds.py.
Run: python3 tools/gen_sounds.py
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")
rng = np.random.default_rng(1337)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def lowpass(x, cutoff):
    # One-pole low-pass filter.
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env_adsr(n, a, d, s, r):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False),
        np.linspace(1, s, d_n, endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, r_n),
    ])
    return e[:n] if len(e) >= n else np.pad(e, (0, n - len(e)))


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    data = (x / m * peak * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, f"{len(x) / SR:.2f}s")


def saw(phase):
    return 2.0 * (phase % 1.0) - 1.0


def roar(dur=2.8, base=62.0):
    t = t_axis(dur)
    vib = 1.0 + 0.06 * np.sin(2 * np.pi * 5.5 * t) + 0.04 * rng.standard_normal(len(t)).cumsum() / np.sqrt(len(t))
    sweep = 1.0 + 0.35 * np.sin(np.pi * t / dur)
    phase = np.cumsum(base * vib * sweep) / SR
    tone = saw(phase) + 0.6 * saw(phase * 1.5) + 0.4 * saw(phase * 2.01)
    rasp = lowpass(rng.standard_normal(len(t)), 900.0) * (0.6 + 0.4 * np.sin(2 * np.pi * base * 0.5 * t))
    x = lowpass(tone * 0.7 + rasp * 1.4, 1400.0)
    x = np.tanh(x * 2.5)
    return x * env_adsr(len(t), 0.25, 0.4, 0.8, 0.9)


def tv_static(dur=2.0):
    n = int(SR * dur)
    x = highpass(rng.standard_normal(n), 400.0)
    hum = 0.15 * np.sin(2 * np.pi * 60.0 * np.arange(n) / SR)
    x = x + hum
    # Crossfade the ends so the loop is seamless.
    fade = int(0.05 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    return x[:-fade]


def thump(dur, freq, noise_cut, decay):
    t = t_axis(dur)
    body = np.sin(2 * np.pi * freq * t * (1.0 - 0.4 * t / dur))
    click = lowpass(rng.standard_normal(len(t)), noise_cut)
    return (body * 0.8 + click * 0.9) * np.exp(-t / decay)


def fan_hum(dur=2.0):
    n = int(SR * dur)
    t = np.arange(n) / SR
    # 120 Hz and harmonics fit whole cycles into 2 s, so the loop is seamless.
    x = np.sin(2 * np.pi * 120 * t) + 0.4 * np.sin(2 * np.pi * 240 * t) + 0.2 * np.sin(2 * np.pi * 30 * t)
    wind = lowpass(rng.standard_normal(n), 600.0) * 1.5
    x = x * (0.7 + 0.3 * np.sin(2 * np.pi * 4.0 * t)) + wind
    fade = int(0.1 * SR)
    wind_fix = x.copy()
    wind_fix[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    return wind_fix[:-fade]


def breath(dur=1.8):
    n = int(SR * dur)
    t = np.arange(n) / SR
    noise = lowpass(highpass(rng.standard_normal(n), 300.0), 2200.0)
    inhale = np.exp(-((t - 0.35) / 0.18) ** 2)
    exhale = 1.3 * np.exp(-((t - 1.05) / 0.25) ** 2)
    return noise * (inhale + exhale)


def main():
    save("monster_growl.wav", roar(1.1, 80.0))
    save("tv_static.wav", tv_static(), 0.6)
    save("impact_thud.wav", thump(0.3, 140.0, 2500.0, 0.06), 0.9)
    save("fan_hum.wav", fan_hum(), 0.5)
    save("breath.wav", breath(), 0.5)


if __name__ == "__main__":
    main()
