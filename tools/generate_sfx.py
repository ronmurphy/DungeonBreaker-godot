#!/usr/bin/env python3
"""Generate procedural combat sound effects for Dungeon Break.

Produces .wav files then converts to .ogg via ffmpeg.
Sound categories:
  - slash   (swords, axes, blades, knives)
  - blunt   (clubs, morningstars, spears)
  - magic   (staves, wands, darts)
  - ranged  (bows, crossbows, boomerangs)
  - roar    (enemy/companion unarmed attacks)
  - miss    (dodge/whiff)
  - block_push (sokoban block scraping)
"""

import os
import struct
import subprocess
import wave
import numpy as np

SAMPLE_RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx", "combat")


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def save_wav(filename, samples):
    """Save float32 [-1,1] samples as 16-bit PCM wav."""
    path = os.path.join(OUT_DIR, filename)
    samples = np.clip(samples, -1.0, 1.0)
    int_samples = (samples * 32767).astype(np.int16)
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(int_samples.tobytes())
    return path


def convert_to_ogg(wav_path):
    """Convert wav to ogg, remove wav."""
    ogg_path = wav_path.replace(".wav", ".ogg")
    subprocess.run(
        ["ffmpeg", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "4", ogg_path],
        capture_output=True,
    )
    os.remove(wav_path)
    return ogg_path


def envelope(length, attack=0.01, decay=0.05, sustain_level=0.7, release=0.1):
    """ADSR envelope."""
    n = int(length * SAMPLE_RATE)
    env = np.ones(n)
    a = int(attack * SAMPLE_RATE)
    d = int(decay * SAMPLE_RATE)
    r = int(release * SAMPLE_RATE)
    # Attack
    if a > 0:
        env[:a] = np.linspace(0, 1, a)
    # Decay
    if d > 0 and a + d < n:
        env[a : a + d] = np.linspace(1, sustain_level, d)
    # Sustain
    if a + d < n - r:
        env[a + d : n - r] = sustain_level
    # Release
    if r > 0:
        env[n - r :] = np.linspace(sustain_level, 0, r)
    return env


def noise(length):
    """White noise."""
    return np.random.uniform(-1, 1, int(length * SAMPLE_RATE))


def sine(freq, length):
    t = np.linspace(0, length, int(length * SAMPLE_RATE), endpoint=False)
    return np.sin(2 * np.pi * freq * t)


def saw(freq, length):
    t = np.linspace(0, length, int(length * SAMPLE_RATE), endpoint=False)
    return 2 * (t * freq - np.floor(0.5 + t * freq))


def freq_sweep(f_start, f_end, length):
    """Linear frequency sweep."""
    t = np.linspace(0, length, int(length * SAMPLE_RATE), endpoint=False)
    phase = 2 * np.pi * (f_start * t + (f_end - f_start) / (2 * length) * t * t)
    return np.sin(phase)


# ── Sound generators ─────────────────────────────────────────────────────────


def gen_slash():
    """Sharp metallic slash — high-pass noise burst + quick sine ping."""
    dur = 0.25
    n = noise(dur)
    # High-pass: subtract smoothed version
    kernel = np.ones(20) / 20
    lp = np.convolve(n, kernel, mode="same")
    hp = n - lp
    env = envelope(dur, attack=0.005, decay=0.03, sustain_level=0.3, release=0.08)
    # Add metallic ring
    ring = sine(2400, dur) * 0.3 * envelope(dur, attack=0.005, decay=0.02, sustain_level=0.1, release=0.15)
    return (hp * env * 0.8 + ring) * 0.9


def gen_blunt():
    """Heavy thud — low sine burst + noise impact."""
    dur = 0.3
    thud = sine(80, dur) * envelope(dur, attack=0.005, decay=0.08, sustain_level=0.2, release=0.15)
    impact = noise(dur) * envelope(dur, attack=0.003, decay=0.04, sustain_level=0.05, release=0.05)
    # Low-pass the noise for a muffled feel
    kernel = np.ones(60) / 60
    impact = np.convolve(impact, kernel, mode="same")
    return (thud * 0.9 + impact * 0.5) * 0.85


def gen_magic():
    """Arcane zap — frequency sweep + harmonics."""
    dur = 0.35
    sweep = freq_sweep(800, 200, dur) * 0.5
    shimmer = sine(1200, dur) * 0.2 + sine(1800, dur) * 0.1
    env = envelope(dur, attack=0.01, decay=0.05, sustain_level=0.4, release=0.2)
    sparkle = noise(dur) * envelope(dur, attack=0.005, decay=0.02, sustain_level=0.05, release=0.05) * 0.15
    return (sweep + shimmer + sparkle) * env * 0.8


def gen_ranged():
    """Twang/whoosh — short high tone + noise sweep."""
    dur = 0.3
    twang = sine(600, dur) * envelope(dur, attack=0.003, decay=0.05, sustain_level=0.1, release=0.1) * 0.5
    whoosh = noise(dur)
    # Band-pass: high-pass then low-pass
    kernel_hp = np.ones(10) / 10
    kernel_lp = np.ones(40) / 40
    whoosh = whoosh - np.convolve(whoosh, kernel_lp, mode="same")
    whoosh = np.convolve(whoosh, kernel_hp, mode="same")
    whoosh *= envelope(dur, attack=0.02, decay=0.08, sustain_level=0.3, release=0.1) * 0.6
    return (twang + whoosh) * 0.85


def gen_roar():
    """Low growl/roar — saw waves with vibrato + noise."""
    dur = 0.5
    t = np.linspace(0, dur, int(dur * SAMPLE_RATE), endpoint=False)
    vibrato = np.sin(2 * np.pi * 6 * t) * 15  # 6Hz vibrato, ±15Hz
    base = np.sin(2 * np.pi * (120 + vibrato) * t) * 0.6
    growl = saw(60, dur) * 0.3
    rumble = noise(dur)
    kernel = np.ones(80) / 80
    rumble = np.convolve(rumble, kernel, mode="same") * 0.2
    env = envelope(dur, attack=0.05, decay=0.1, sustain_level=0.6, release=0.2)
    return (base + growl + rumble) * env * 0.8


def gen_miss():
    """Quick whoosh — filtered noise sweep."""
    dur = 0.2
    w = noise(dur)
    # Gentle high-pass
    kernel = np.ones(30) / 30
    w = w - np.convolve(w, kernel, mode="same")
    env = envelope(dur, attack=0.01, decay=0.05, sustain_level=0.15, release=0.08)
    return w * env * 0.5


def gen_block_push():
    """Stone scraping — filtered noise with low rumble."""
    dur = 0.4
    scrape = noise(dur)
    kernel = np.ones(25) / 25
    scrape = np.convolve(scrape, kernel, mode="same")
    rumble = sine(50, dur) * 0.3
    env = envelope(dur, attack=0.05, decay=0.1, sustain_level=0.5, release=0.15)
    return (scrape * 0.6 + rumble) * env * 0.7


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    ensure_dir(OUT_DIR)
    sounds = {
        "slash": gen_slash,
        "blunt": gen_blunt,
        "magic": gen_magic,
        "ranged": gen_ranged,
        "roar": gen_roar,
        "miss": gen_miss,
        "block_push": gen_block_push,
    }
    for name, gen_func in sounds.items():
        samples = gen_func()
        wav_path = save_wav(f"{name}.wav", samples)
        ogg_path = convert_to_ogg(wav_path)
        print(f"  ✓ {name} → {ogg_path}")

    print(f"\nDone! {len(sounds)} combat SFX generated in {OUT_DIR}")


if __name__ == "__main__":
    main()
