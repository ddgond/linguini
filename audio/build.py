#!/usr/bin/env python3
"""Builds Linguini's sounds into godot/audio/ as mono Ogg Vorbis.

    nix develop .#audio -c python3 audio/build.py          # everything
    nix develop .#audio -c python3 audio/build.py bubbles  # just these

Most sounds are synthesized here (seeded, so they rebuild the same). The rain
and the birds are CC0 recordings in audio/sources/ (see CREDITS below), made
mono, levelled and looped. Loops are made seamless by crossfading their tail
into their head; Godot loops them (godot/scripts/sound.gd).
"""

import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "godot" / "audio"
RATE = 44100

CREDITS = """Linguini's sounds

Synthesized by audio/build.py (part of Linguini, GPLv3): card taps, UI clicks,
bubbles, the filter's trickle, the tank's hum, fish swishes and bumps, the PC
fan, the distant city and the breeze.

CC0 recordings (public domain), made mono, levelled and looped:
- rain.ogg: "Rain (loopable)" by Ylmir, CC0.
  https://opengameart.org/content/rain-loopable (file 3.ogg)
- birds.ogg: "Ambient Bird Sounds" by isaiah658, CC0.
  https://opengameart.org/content/ambient-bird-sounds
"""


# --- helpers -------------------------------------------------------------------

def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def noise(seconds, rng):
    return rng.standard_normal(int(seconds * RATE))


def fft_filter(x, low=None, high=None, slope=4.0):
    """Band-limits x smoothly in the frequency domain (fine for loops too)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    gain = np.ones_like(f)
    if low:
        gain *= 1 / (1 + (low / np.maximum(f, 1e-3)) ** slope)
    if high:
        gain *= 1 / (1 + (f / high) ** slope)
    return np.fft.irfft(spec * gain, len(x))


def pink(seconds, rng):
    x = noise(seconds, rng)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    spec /= np.sqrt(np.maximum(f, 20.0))
    return np.fft.irfft(spec, len(x))


def env(n, attack, decay):
    """Attack (s) then exponential decay (time constant, s)."""
    tt = np.arange(n) / RATE
    a = np.clip(tt / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(tt - attack, 0) / decay)


def sweep_sine(seconds, f0, f1, curve=1.0):
    tt = t(seconds)
    f = f0 + (f1 - f0) * (tt / seconds) ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def level(x, rms_db):
    rms = np.sqrt(np.mean(x ** 2))
    return x * (10 ** (rms_db / 20) / max(rms, 1e-9))


def seamless(x, fade_seconds):
    """A loop: the last `fade` seconds crossfade into the first."""
    n = int(fade_seconds * RATE)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    ramp = np.linspace(0, 1, n)
    joined = tail * (1 - ramp) + head * ramp
    return np.concatenate([joined, body[: len(x) - 2 * n]]) if n else x


def mix_at(dst, src, start):
    s = int(start * RATE)
    e = min(len(dst), s + len(src))
    if e > s:
        dst[s:e] += src[: e - s]


def fade_edges(x, ms=4):
    n = int(ms / 1000 * RATE)
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


# --- one-shots -----------------------------------------------------------------

def card_press(rng):
    """A soft tap on laminated card: a papery click over a small thump."""
    n = int(0.12 * RATE)
    click = fft_filter(noise(0.12, rng), 1200, 5000) * env(n, 0.0005, 0.006)
    thump = np.sin(2 * np.pi * 170 * t(0.12)) * env(n, 0.001, 0.035)
    return normalize(click * 0.8 + thump * 0.6, 0.8)


def card_release(rng):
    n = int(0.08 * RATE)
    click = fft_filter(noise(0.08, rng), 2000, 7000) * env(n, 0.0005, 0.004)
    thump = np.sin(2 * np.pi * 240 * t(0.08)) * env(n, 0.001, 0.02)
    return normalize(click * 0.6 + thump * 0.3, 0.45)


def seq_tick(rng):
    n = int(0.06 * RATE)
    blip = np.sin(2 * np.pi * 1450 * t(0.06)) * env(n, 0.001, 0.012)
    click = fft_filter(noise(0.06, rng), 3000, 9000) * env(n, 0.0003, 0.002)
    return normalize(blip * 0.5 + click * 0.4, 0.4)


def ui_click(rng):
    n = int(0.07 * RATE)
    blip = np.sin(2 * np.pi * 2100 * t(0.07)) * env(n, 0.0005, 0.01)
    body = np.sin(2 * np.pi * 620 * t(0.07)) * env(n, 0.001, 0.015)
    return normalize(blip * 0.4 + body * 0.5, 0.5)


def swish(rng, pitch=1.0):
    """A tail beat in water: a soft band of noise sweeping up then down."""
    d = 0.22
    x = noise(d, rng)
    n = len(x)
    out = np.zeros(n)
    # Moving band-pass by crossfading three fixed bands.
    bands = [fft_filter(x, 150 * pitch, 400 * pitch), fft_filter(x, 300 * pitch, 800 * pitch), fft_filter(x, 500 * pitch, 1400 * pitch)]
    s = np.sin(np.pi * np.arange(n) / n)
    out = bands[0] * (1 - s) + bands[1] * s * 0.8 + bands[2] * s ** 3 * 0.5
    return fade_edges(normalize(out * np.sin(np.pi * np.arange(n) / n) ** 1.5, 0.5))


def dart(rng):
    d = 0.45
    x = noise(d, rng)
    n = len(x)
    lo = fft_filter(x, 120, 500)
    hi = fft_filter(x, 500, 2400)
    ramp = np.linspace(0, 1, n)
    shape = np.minimum(ramp / 0.12, 1) * np.exp(-np.maximum(ramp - 0.12, 0) / 0.18)
    out = (lo * (1 - ramp) + hi * ramp * 0.7) * shape
    bubbles = np.zeros(n)
    for _ in range(9):
        mix_at(bubbles, _bubble(rng, rng.uniform(700, 1600), rng.uniform(0.012, 0.03)) * 0.3, rng.uniform(0.1, 0.35))
    return fade_edges(normalize(out + bubbles, 0.8))


def bump(rng):
    """The fish nudging glass or stone: a dull knock with a little ring."""
    n = int(0.25 * RATE)
    knock = sweep_sine(0.25, 150, 80, 0.5) * env(n, 0.001, 0.05)
    ring = np.sin(2 * np.pi * 1850 * t(0.25)) * env(n, 0.0005, 0.03) * 0.12
    return fade_edges(normalize(knock + ring, 0.7))


def _bubble(rng, f0, decay):
    """One bubble: a sine rising in pitch as it forms, decaying fast."""
    d = decay * 5
    n = int(d * RATE)
    return sweep_sine(d, f0, f0 * rng.uniform(1.15, 1.4), 0.6) * env(n, 0.001, decay)


# --- loops ---------------------------------------------------------------------

def bubbles(rng):
    """The air stone: a steady stream of small bubbles over a fizz."""
    d = 9.0
    x = fft_filter(noise(d + 1, rng), 1500, 6000) * 0.05
    tt = 0.0
    while tt < d + 0.8:
        tt += rng.exponential(1 / 32)
        mix_at(x, _bubble(rng, rng.uniform(500, 1900), rng.uniform(0.008, 0.03)) * rng.uniform(0.2, 0.7), tt)
    return level(seamless(x, 1.0), -24)


def trickle(rng):
    """The hang-on filter: water spilling back into the tank."""
    d = 9.0
    base = fft_filter(noise(d + 1, rng), 300, 3500)
    wobble = 0.6 + 0.4 * fft_filter(noise(d + 1, rng), None, 6, 2)
    x = base * wobble / np.max(np.abs(wobble))
    tt = 0.0
    while tt < d + 0.8:
        tt += rng.exponential(1 / 60)
        mix_at(x, _bubble(rng, rng.uniform(300, 1200), rng.uniform(0.006, 0.02)) * rng.uniform(0.3, 1.2), tt)
    return level(seamless(x, 1.0), -22)


def tank_hum(rng):
    """The lamp's ballast and the pump: a low, soft mains hum."""
    d = 6.0
    tt = t(d + 1)
    hum = sum(a * np.sin(2 * np.pi * f * tt) for f, a in ((50, 1.0), (100, 0.6), (150, 0.25), (200, 0.12)))
    buzz = fft_filter(noise(d + 1, rng), 80, 400) * 0.15
    return level(seamless(hum + buzz, 1.0), -30)


def fan(rng):
    """The streamer's PC under the desk: soft airflow and a faint blade tone."""
    d = 10.0
    air = fft_filter(pink(d + 1, rng), 60, 900)
    blade = 0.05 * np.sin(2 * np.pi * 118 * t(d + 1))
    return level(seamless(air + blade, 1.0), -30)


def city(rng):
    """The distant city at night: a low rumble with the odd car passing."""
    d = 24.0
    x = fft_filter(pink(d + 2, rng), 30, 280) * 1.0
    for start in np.cumsum(rng.uniform(3.0, 7.0, 8)):
        if start > d:
            break
        length = rng.uniform(3.5, 6.0)
        car = fft_filter(noise(length, rng), 150, rng.uniform(700, 1200))
        shape = np.sin(np.pi * np.arange(len(car)) / len(car)) ** 3
        mix_at(x, car * shape * rng.uniform(0.3, 0.6), start)
    return level(seamless(x, 2.0), -32)


def breeze(rng):
    """Golden hour: a faint breeze swelling and settling."""
    d = 20.0
    x = pink(d + 2, rng)
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * np.arange(len(x)) / RATE / 7.3) * np.sin(2 * np.pi * np.arange(len(x)) / RATE / 3.1 + 1)
    x = fft_filter(x, 200, 1600) * (0.3 + 0.7 * swell ** 2)
    return level(seamless(x, 2.0), -34)


# --- CC0 recordings --------------------------------------------------------------

def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def rain(rng):
    x = decode(HERE / "sources" / "rain-ylmir.ogg")
    return level(seamless(x, 1.5), -24)


def birds(rng):
    x = decode(HERE / "sources" / "birds-isaiah658.ogg")
    x = fft_filter(x, 250, None, 2)  # drop the camera mic's rumble
    return level(seamless(x, 2.0), -30)


# --- output --------------------------------------------------------------------

SOUNDS = {
    "card_press": card_press, "card_release": card_release, "seq_tick": seq_tick, "ui_click": ui_click,
    "swish_1": lambda r: swish(r, 0.9), "swish_2": lambda r: swish(r, 1.0), "swish_3": lambda r: swish(r, 1.12),
    "dart": dart, "bump": bump,
    "bubbles": bubbles, "trickle": trickle, "tank_hum": tank_hum,
    "fan": fan, "city": city, "breeze": breeze, "rain": rain, "birds": birds,
}


def write_ogg(name, x):
    x = np.clip(x, -1, 1)
    pcm = (x * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "x.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "5",
                        "-map_metadata", "-1", str(OUT / f"{name}.ogg")], check=True)


def main(names):
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (name, fn) in enumerate(SOUNDS.items()):
        if names and name not in names:
            continue
        x = fn(np.random.default_rng(1000 + i))
        write_ogg(name, x)
        print(f"  {name}.ogg  {len(x) / RATE:.2f} s")
    (OUT / "CREDITS.txt").write_text(CREDITS)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
