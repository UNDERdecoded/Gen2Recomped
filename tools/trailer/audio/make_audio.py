#!/usr/bin/env python3
"""Procedural music and sound effects for the "Play Together" trailer.

Everything here is synthesised from scratch (wavetable oscillators, filtered
noise, FFT reverb). No samples, no downloads, no borrowed melodies: the chord
loop, hook, riff and arpeggio patterns are original to this file.

    python tools/trailer/audio/make_audio.py <outdir>

writes 48 kHz / 16-bit stereo WAVs:
    music.wav   ~102 s, 120 BPM (see README.md for the section map)
    chime.wav whoosh.wav whoosh_rev.wav riser.wav hit.wav blip.wav
    blip2.wav slam.wav swish_short.wav

Needs Python 3 + numpy. Deterministic (fixed seeds).
"""
import math
import os
import sys
import time
import wave

import numpy as np

SR = 48000
BPM = 120.0
BEAT = 60.0 / BPM          # 0.5 s
BAR = 4 * BEAT             # 2.0 s
TOTAL = 102.0              # music length in seconds
N = int(TOTAL * SR)

MUSIC_PEAK_DB = -1.0
MUSIC_LUFS = -14.0
SFX_PEAK_DB = -3.0


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def s2n(sec):
    return int(round(sec * SR))


def bt(beat):
    return beat * BEAT


def db(x):
    return 20.0 * math.log10(max(x, 1e-12))


# --------------------------------------------------------------------------
# Oscillators (band-limited wavetables, looked up with a running phase)
# --------------------------------------------------------------------------
TBL_N = 4096
_tables = {}


def _table(shape, f, cutoff, maxh):
    nh = int(max(1, min(maxh, TBL_N // 2 - 1, (SR * 0.45) / max(f, 1.0))))
    cr = None if cutoff is None else round(math.log2(max(cutoff, 1.0) / f) * 4) / 4
    key = (shape, nh, cr)
    t = _tables.get(key)
    if t is not None:
        return t
    k = np.arange(1, nh + 1, dtype=np.float64)
    if shape == "saw":
        a = 1.0 / k
    elif shape == "square":
        a = np.where(k % 2 == 1, 1.0 / k, 0.0)
    elif shape.startswith("pulse"):
        d = float(shape[5:]) / 100.0
        a = np.sin(np.pi * k * d) / k
    elif shape == "tri":
        a = np.where(k % 2 == 1, ((-1.0) ** ((k - 1) / 2)) / (k * k), 0.0)
    elif shape == "sine":
        a = np.where(k == 1, 1.0, 0.0)
    else:
        raise ValueError(shape)
    if cr is not None:
        a = a / np.sqrt(1.0 + (k / (2.0 ** cr)) ** 4)
    spec = np.zeros(TBL_N // 2 + 1, dtype=np.complex128)
    spec[1:nh + 1] = -1j * a * TBL_N / 2.0
    tbl = np.fft.irfft(spec, n=TBL_N)
    tbl /= max(np.max(np.abs(tbl)), 1e-9)
    tbl = np.concatenate([tbl, tbl[:1]])
    _tables[key] = tbl
    return tbl


def osc(shape, freq, n, cutoff=None, phase0=0.0, maxh=200):
    """freq: scalar Hz or per-sample array. Returns n samples."""
    if np.isscalar(freq):
        fref = float(freq)
        ph = phase0 + np.arange(n) * (fref / SR)
    else:
        freq = np.asarray(freq, dtype=np.float64)[:n]
        fref = float(np.max(freq))
        ph = phase0 + np.concatenate(([0.0], np.cumsum(freq[:-1]))) / SR
    tbl = _table(shape, fref, cutoff, maxh)
    ph = (ph % 1.0) * TBL_N
    i = ph.astype(np.int64)
    fr = ph - i
    return tbl[i] * (1.0 - fr) + tbl[i + 1] * fr


def env_adsr(on_sec, a, d, s, r):
    """Attack/decay/sustain, exponential release of r seconds after on_sec."""
    n_on = max(1, s2n(on_sec))
    n = n_on + s2n(r)
    t = np.arange(n) / SR
    a = max(a, 1e-4)
    e = np.where(t < a, t / a, s + (1.0 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    off = e[n_on - 1]
    rel = t >= on_sec
    e[rel] = off * np.exp(-(t[rel] - on_sec) * 6.9 / max(r, 1e-3))
    return e


# --------------------------------------------------------------------------
# Filters
# --------------------------------------------------------------------------
def g_lp(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def g_hp(f, fc, order=2):
    x = (np.maximum(f, 1e-6) / fc) ** order
    return x / np.sqrt(1.0 + x * x)


def g_bp(f, fc, width_oct):
    lf = np.log2(np.maximum(f, 1.0) / fc)
    return np.exp(-0.5 * (lf / width_oct) ** 2)


def fft_filter(x, gfn):
    n = x.shape[-1]
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * gfn(f), n=n, axis=-1)


def tv_filter(x, gfn, nfft=2048):
    """Time-varying filter by STFT overlap-add. gfn(t[:,None], f[None,:])."""
    if x.ndim == 2:
        return np.stack([tv_filter(c, gfn, nfft) for c in x])
    hop = nfft // 4
    n = len(x)
    pad = np.concatenate([np.zeros(nfft), x, np.zeros(nfft + hop)])
    w = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(nfft) / nfft)
    starts = np.arange(0, len(pad) - nfft, hop)
    freqs = np.fft.rfftfreq(nfft, 1.0 / SR)
    out = np.zeros(len(pad))
    view = np.lib.stride_tricks.sliding_window_view(pad, nfft)
    for c0 in range(0, len(starts), 512):
        st = starts[c0:c0 + 512]
        fr = view[st] * w
        X = np.fft.rfft(fr, axis=1)
        tc = (st + nfft / 2 - nfft) / SR
        Y = np.fft.irfft(X * gfn(tc[:, None], freqs[None, :]), n=nfft, axis=1) * w
        for j, s in enumerate(st):
            out[s:s + nfft] += Y[j]
    return out[nfft:nfft + n] / 1.5


def noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


def make_ir(dur, rt60, seed, lp=7000.0, predelay=0.02):
    n = s2n(dur)
    t = np.arange(n) / SR
    ir = noise(n, seed) * np.exp(-t * 6.9 / rt60)
    ir = fft_filter(ir, lambda f: g_lp(f, lp, 1) * g_hp(f, 180.0, 1))
    ir[: s2n(0.004)] *= np.linspace(0, 1, s2n(0.004))
    ir = np.concatenate([np.zeros(s2n(predelay)), ir])
    return ir / np.sqrt(np.sum(ir * ir))


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    nf = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, nf) * np.fft.rfft(ir, nf), nf)
    return y[: len(x)]


def reverb(mono, dur=2.4, rt60=2.0, seed=7, lp=7000.0):
    """Mono in, decorrelated stereo out."""
    return np.stack([convolve(mono, make_ir(dur, rt60, seed, lp)),
                     convolve(mono, make_ir(dur, rt60, seed + 1, lp))])


# --------------------------------------------------------------------------
# Mixing helpers
# --------------------------------------------------------------------------
def pan_gains(pan):
    a = (pan + 1.0) * math.pi / 4.0
    return math.cos(a) * math.sqrt(2.0), math.sin(a) * math.sqrt(2.0)


def add(bus, t, sig, pan=0.0, gain=1.0):
    s = s2n(t)
    if s >= bus.shape[1]:
        return
    if s < 0:
        sig = sig[..., -s:]
        s = 0
    if sig.ndim == 1:
        gl, gr = pan_gains(pan)
        sig = np.stack([sig * gl, sig * gr])
    e = min(bus.shape[1], s + sig.shape[1])
    bus[:, s:e] += sig[:, : e - s] * gain


def delay_pingpong(x, d_sec, fb, taps=5):
    """Mono in -> stereo ping-pong echoes only (wet)."""
    out = np.zeros((2, len(x)))
    d = s2n(d_sec)
    for k in range(1, taps + 1):
        sh = d * k
        if sh >= len(x):
            break
        out[(k + 1) % 2, sh:] += x[: len(x) - sh] * (fb ** (k - 1))
    return out


def peak_normalise(x, peak_db):
    return x * (10 ** (peak_db / 20.0) / max(np.max(np.abs(x)), 1e-9))


# --------------------------------------------------------------------------
# Loudness (BS.1770 K-weighting at 48 kHz, gated) and a look-ahead limiter
# --------------------------------------------------------------------------
_K1 = ([1.53512485958697, -2.69169618940638, 1.19839281085285],
       [1.0, -1.69065929318241, 0.73248077421585])
_K2 = ([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621])


def lufs(x):
    n = x.shape[1]
    z = np.exp(-2j * np.pi * np.fft.rfftfreq(n, 1.0 / SR) / SR)

    def H(c):
        b, a = c
        return (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)

    y = np.fft.irfft(np.fft.rfft(x, axis=1) * np.abs(H(_K1) * H(_K2)), n=n, axis=1)
    B, S = s2n(0.4), s2n(0.1)
    cs = np.concatenate([np.zeros((2, 1)), np.cumsum(y * y, axis=1)], axis=1)
    st = np.arange(0, n - B + 1, S)
    zb = ((cs[:, st + B] - cs[:, st]) / B).sum(axis=0)
    lb = -0.691 + 10 * np.log10(np.maximum(zb, 1e-20))
    g = zb[lb > -70]
    if len(g) == 0:
        return -99.0
    rel = -0.691 + 10 * np.log10(np.mean(g)) - 10
    g2 = zb[(lb > -70) & (lb > rel)]
    return -0.691 + 10 * np.log10(np.mean(g2))


def _sliding_min(x, half):
    k = 2 * half + 1
    n = len(x)
    p = np.concatenate([np.ones(half), x, np.ones(half + k)])
    nb = len(p) // k
    p = p[: nb * k].reshape(nb, k)
    pre = np.minimum.accumulate(p, axis=1).ravel()
    suf = np.minimum.accumulate(p[:, ::-1], axis=1)[:, ::-1].ravel()
    i = np.arange(n)
    return np.minimum(suf[i], pre[i + k - 1])


def _box(x, half):
    k = 2 * half + 1
    cs = np.concatenate([[0.0], np.cumsum(np.concatenate([np.full(half, x[0]), x, np.full(half, x[-1])]))])
    return (cs[k:] - cs[:-k]) / k


def limit(x, ceiling_db, hold=0.012):
    """Gain never lets |x| exceed the ceiling (min-hold then box smoothing)."""
    c = 10 ** (ceiling_db / 20.0)
    need = np.minimum(1.0, c / np.maximum(np.max(np.abs(x), axis=0), 1e-12))
    h = s2n(hold)
    g = _box(_sliding_min(need, h), h)
    return np.clip(x * g, -c, c)


# --------------------------------------------------------------------------
# Drum one-shots
# --------------------------------------------------------------------------
def drum_kit():
    kit = {}
    n = s2n(0.5)
    t = np.arange(n) / SR
    f = 46 + 120 * np.exp(-t / 0.035) + 30 * np.exp(-t / 0.006)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR)
    amp = np.where(t < 0.06, 1.0, np.exp(-(t - 0.06) / 0.16))
    click = fft_filter(noise(n, 11), lambda fr: g_hp(fr, 2500)) * np.exp(-t / 0.004) * 0.35
    k = np.tanh(1.6 * body * amp) + click
    k[-s2n(0.02):] *= np.linspace(1, 0, s2n(0.02))
    kit["kick"] = k / np.max(np.abs(k))

    n = s2n(0.35)
    t = np.arange(n) / SR
    tone = (np.sin(2 * np.pi * 186 * t) + 0.5 * np.sin(2 * np.pi * 332 * t)) * np.exp(-t / 0.05)
    nz = fft_filter(noise(n, 12), lambda fr: g_bp(fr, 4200, 1.3) + 0.3 * g_hp(fr, 7000)) * np.exp(-t / 0.13)
    s = 0.7 * tone + 1.4 * nz / np.max(np.abs(nz))
    kit["snare"] = s / np.max(np.abs(s))

    n = s2n(0.4)
    t = np.arange(n) / SR
    burst = np.zeros(n)
    for i, d in enumerate((0.0, 0.011, 0.022)):
        m = t >= d
        burst[m] += np.exp(-(t[m] - d) / 0.005) * (0.8 + 0.1 * i)
    m = t >= 0.03
    burst[m] += 0.6 * np.exp(-(t[m] - 0.03) / 0.11)
    cl = fft_filter(noise(n, 13), lambda fr: g_bp(fr, 1600, 0.9)) * burst
    kit["clap"] = cl / np.max(np.abs(cl))

    def metal(n, seed):
        tt = np.arange(n) / SR
        m = sum(np.sign(np.sin(2 * np.pi * fq * tt + p))
                for fq, p in zip((205.3, 304.4, 369.6, 522.7, 540.0, 800.0),
                                 np.random.default_rng(seed).uniform(0, 6, 6)))
        return m / 6.0

    for name, dur, tau, seed in (("hat", 0.12, 0.022, 14), ("ohat", 0.6, 0.18, 15)):
        n = s2n(dur)
        t = np.arange(n) / SR
        h = 0.6 * noise(n, seed) + metal(n, seed)
        h = fft_filter(h, lambda fr: g_hp(fr, 7500, 3) * g_lp(fr, 15000, 1)) * np.exp(-t / tau)
        kit[name] = h / np.max(np.abs(h))

    n = s2n(2.8)
    t = np.arange(n) / SR
    cr = noise(n, 16) + 0.8 * metal(n, 17)
    cr = fft_filter(cr, lambda fr: g_hp(fr, 4000, 2) * g_lp(fr, 16000, 1))
    cr *= np.exp(-t / 0.9) * np.minimum(1.0, t / 0.002)
    kit["crash"] = cr / np.max(np.abs(cr))

    n = s2n(0.4)
    t = np.arange(n) / SR
    for name, f0 in (("tom_hi", 210.0), ("tom_lo", 140.0)):
        f = f0 * (0.65 + 0.35 * np.exp(-t / 0.06))
        tm = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.14)
        tm += 0.15 * fft_filter(noise(n, 18), lambda fr: g_bp(fr, 3000, 1)) * np.exp(-t / 0.02)
        kit[name] = tm / np.max(np.abs(tm))

    n = s2n(0.12)
    t = np.arange(n) / SR
    sh = fft_filter(noise(n, 19), lambda fr: g_bp(fr, 9000, 0.6)) * np.sin(np.pi * np.minimum(t / 0.09, 1.0)) ** 2
    kit["shaker"] = sh / np.max(np.abs(sh))
    return kit


# --------------------------------------------------------------------------
# Shared sound designs (used by music and SFX)
# --------------------------------------------------------------------------
def noise_riser(dur, f0, f1, seed, curve=2.0, width=0.6, stereo=True):
    n = s2n(dur)
    x = np.stack([noise(n, seed), noise(n, seed + 100)]) if stereo else noise(n, seed)

    def gfn(t, f):
        u = np.clip(t / dur, 0, 1)
        fc = f0 * (f1 / f0) ** (u ** curve)
        return g_bp(f, fc, width) + 0.15 * g_hp(f, fc * 1.5)
    y = tv_filter(x, gfn)
    t = np.arange(n) / SR
    u = t / dur
    trem = 1.0 - 0.35 * (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(4 + 20 * u ** 2) / SR))
    amp = (u ** 2) * trem
    amp[-s2n(0.015):] *= np.linspace(1, 0, s2n(0.015))
    return y * amp / np.max(np.abs(y))


def pitch_riser(dur, m0, m1):
    n = s2n(dur)
    t = np.arange(n) / SR
    u = t / dur
    out = np.zeros((2, n))
    for det, pan in ((-0.12, -0.6), (0.0, 0.0), (0.12, 0.6)):
        f = mtof(m0 + det) * 2 ** ((m1 - m0) / 12.0 * u ** 1.6)
        v = osc("saw", f, n, cutoff=4000)
        gl, gr = pan_gains(pan)
        out[0] += v * gl
        out[1] += v * gr
    out *= (u ** 2.2)
    out[:, -s2n(0.015):] *= np.linspace(1, 0, s2n(0.015))
    return out / np.max(np.abs(out))


def boom(dur, f_hi=75.0, f_lo=32.0, tau=0.8, seed=21):
    n = s2n(dur)
    t = np.arange(n) / SR
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.09)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / tau)
    thump = np.sin(2 * np.pi * np.cumsum(120 * (0.6 + 0.4 * np.exp(-t / 0.03))) / SR) * np.exp(-t / 0.08)
    crack = fft_filter(noise(n, seed), lambda fr: g_lp(fr, 3500, 1) * g_hp(fr, 200)) * np.exp(-t / 0.035)
    x = np.tanh(1.8 * (sub + 0.5 * thump)) + 0.5 * crack / np.max(np.abs(crack))
    x[-s2n(0.05):] *= np.linspace(1, 0, s2n(0.05))
    return x


# --------------------------------------------------------------------------
# Composition
# --------------------------------------------------------------------------
# chord name -> (bass root midi, pad voicing). The loop is i - VI - III - VII
# in A minor; the second lift transposes everything up a whole tone (B minor),
# pivoting through F# major.
CHORDS = {
    "Am": (33, [57, 60, 64, 69]),
    "F": (29, [53, 57, 60, 65]),
    "C": (36, [55, 60, 64, 67]),
    "G": (31, [55, 59, 62, 67]),
    "F#": (30, [54, 58, 61, 66]),
}
LOOP = ["Am", "F", "C", "G"]


def build_bars():
    bars = []                                   # (chord, transpose)
    bars += [(c, 0) for c in LOOP * 2]          # 0-7   intro / build
    bars += [("F", 0), ("G", 0)]                # 8-9   build end
    bars += [(c, 0) for c in LOOP * 2]          # 10-17 drop
    bars += [("F", 0), ("G", 0)]                # 18-19
    bars += [("G", 0)]                          # 20    breakdown
    bars += [(c, 0) for c in LOOP * 3]          # 21-32 groove
    bars += [("F#", 0)]                         # 33    pivot
    bars += [(c, 2) for c in LOOP * 3]          # 34-45 lift (B minor)
    bars += [("F#", 0)]                         # 46    riser
    bars += [("Am", 2)] * 4                     # 47-50 final Bm
    return bars


BARS = build_bars()

# Lead hook (original). (beat in bar, length in beats, midi)
HOOK = [
    [(0, .5, 76), (.5, .5, 81), (1, .5, 79), (1.5, .75, 76), (2.25, .25, 74), (2.5, .5, 76), (3, 1, 72)],
    [(0, .5, 72), (.5, .5, 74), (1, .5, 76), (1.5, .5, 77), (2, .75, 76), (2.75, .25, 72), (3, 1, 69)],
    [(0, .5, 67), (.5, .5, 72), (1, .5, 76), (1.5, .75, 79), (2.25, .25, 81), (2.5, .5, 79), (3, 1, 76)],
    [(0, .5, 74), (.5, .5, 79), (1, .5, 83), (1.5, .5, 81), (2, .5, 79), (2.5, .5, 74), (3, .5, 71), (3.5, .5, 74)],
]
HOOK_END_ALT = [(0, .5, 74), (.5, .5, 79), (1, .5, 83), (1.5, .5, 81), (2, .5, 79), (2.5, .5, 81), (3, .5, 83), (3.5, .5, 84)]
TAG = [  # bars 18-19 answer phrase
    [(0, 1.5, 84), (1.5, .5, 83), (2, 1, 81), (3, 1, 79)],
    [(0, 2, 83), (2, 1, 86), (3, .5, 84), (3.5, .5, 83)],
]
RIFF = [  # chip counter-melody for the groove
    [(0, .5, 76), (.75, .25, 79), (1, .5, 81), (1.5, .5, 79), (2.5, .25, 76), (2.75, .25, 74), (3, 1, 76)],
    [(0, .5, 77), (.75, .25, 76), (1, .5, 72), (1.5, .5, 74), (2.5, .25, 77), (2.75, .25, 79), (3, 1, 81)],
    [(0, .5, 79), (.75, .25, 76), (1, .5, 72), (1.5, .5, 76), (2.5, .25, 79), (2.75, .25, 84), (3, 1, 83)],
    [(0, .5, 83), (.75, .25, 79), (1, .5, 74), (1.5, .5, 79), (2, .5, 81), (2.5, .5, 83), (3, .5, 86), (3.5, .5, 84)],
]
A_MINOR = [9, 11, 0, 2, 4, 5, 7]


def third_below(m):
    pc = m % 12
    if pc not in A_MINOR:
        return m - 3
    i = A_MINOR.index(pc)
    j = (i - 2) % 7
    d = (pc - A_MINOR[j]) % 12
    return m - d


def phrase(bar0, bars_notes, transpose=0, octave=0):
    ev = []
    for bi, notes in enumerate(bars_notes):
        for b, l, m in notes:
            ev.append(((bar0 + bi) * 4 + b, l, m + transpose + 12 * octave))
    return ev


def hook_events(bar0, alt=False, transpose=0):
    bars = HOOK[:3] + [HOOK_END_ALT if alt else HOOK[3]]
    return phrase(bar0, bars, transpose)


def render_music(log=print):
    rng = np.random.default_rng(1234)
    kit = drum_kit()
    buses = {k: np.zeros((2, N)) for k in
             ("kick", "drums", "bass", "pad", "arp", "lead", "chip", "stab", "fx", "send")}

    # ---------------- pads ----------------
    for bi, (ch, tr) in enumerate(BARS):
        t0 = bi * BAR
        if t0 >= 94.0 and bi > 47:
            continue
        final = bi == 47
        length = (TOTAL - 94.0 - 1.0) if final else BAR
        notes = CHORDS[ch][1] + ([CHORDS[ch][1][0] - 12 + 14] if final else [])
        for m in notes:
            m += tr
            e = env_adsr(length, 0.25 if not final else 0.01, 1.5, 0.8, 0.9 if not final else 1.5)
            for det, pan in ((-0.09, -0.75), (0.0, 0.0), (0.09, 0.75)):
                v = osc("saw", mtof(m + det), len(e), cutoff=2600, phase0=rng.uniform(), maxh=60) * e
                add(buses["pad"], t0, v, pan, 0.11)
    log("  pads")

    # ---------------- arpeggio ----------------
    pat = [0, 2, 4, 6, 1, 3, 5, 7, 4, 2, 6, 4, 7, 5, 3, 1]
    for bi, (ch, tr) in enumerate(BARS[:46]):
        if bi == 33:
            continue
        tones = sorted(CHORDS[ch][1])
        tones = [x + tr + 12 for x in tones] + [x + tr + 24 for x in tones]
        for s in range(16):
            beat = bi * 4 + s * 0.25
            if beat >= 182:
                break
            m = tones[pat[s]]
            e = env_adsr(0.11, 0.003, 0.07, 0.25, 0.08)
            v = osc("pulse25", mtof(m), len(e), cutoff=3200) * e
            vel = 0.75 + 0.25 * (s % 4 == 0)
            add(buses["arp"], bt(beat), v, 0.25 if s % 2 else -0.25, 0.14 * vel)
            if 34 <= bi <= 45:  # extra high chip layer in the lift
                v2 = osc("pulse12", mtof(m + 12), len(e), cutoff=6000) * e
                add(buses["chip"], bt(beat + 0.125 if s % 2 else beat), v2, -0.6 if s % 2 else 0.6, 0.05)
    log("  arp")

    # ---------------- bass ----------------
    def bass_note(t, m, dur, cutoff, gain):
        e = env_adsr(dur, 0.004, 0.16, 0.45, 0.05)
        n = len(e)
        v = osc("saw", mtof(m), n, cutoff=cutoff) * e
        sub_m = m if m < 40 else m - 12
        v += 0.9 * osc("sine", mtof(sub_m), n) * env_adsr(dur, 0.004, 0.4, 0.8, 0.05)
        add(buses["bass"], t, np.tanh(1.3 * v), 0.0, gain)

    for bi, (ch, tr) in enumerate(BARS):
        if bi < 8 or bi == 20 or bi >= 47:
            continue
        root = CHORDS[ch][0] + tr
        for e8 in range(8):
            beat = bi * 4 + e8 * 0.5
            if beat >= 182:
                break
            if bi < 10:  # build: filtered root 8ths
                bass_note(bt(beat), root, 0.2, 350 + 120 * (bi - 8) + 40 * e8, 0.6)
            else:
                m = root + (12 if e8 % 2 else 0)
                bass_note(bt(beat), m, 0.21, 1100 if bi >= 34 else 900, 0.62)
    # final held bass
    e = env_adsr(5.0, 0.004, 1.2, 0.5, 1.5)
    v = osc("saw", mtof(35), len(e), cutoff=500) * e + 1.0 * osc("sine", mtof(35), len(e)) * e
    add(buses["bass"], 94.0, np.tanh(1.3 * v), 0.0, 0.7)
    log("  bass")

    # ---------------- lead, chip riff, stabs ----------------
    def lead_note(beat, length, m, gain, layer="lead", shape="saw", octave_layer=False):
        dur = bt(length) * (0.92 if length < 1 else 0.97)
        e = env_adsr(dur, 0.006, 0.25, 0.75, 0.12)
        n = len(e)
        t = np.arange(n) / SR
        vib = 1.0 + (0.0045 * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.18) / 0.2, 0, 1)
                     if length >= 0.75 else 0.0)
        f = mtof(m) * vib
        if shape == "saw":
            for det, pan in ((-0.1, -0.35), (0.0, 0.0), (0.1, 0.35)):
                add(buses[layer], bt(beat), osc("saw", f * 2 ** (det / 12), n, cutoff=5200,
                                                 phase0=rng.uniform()) * e, pan, gain * 0.5)
            add(buses[layer], bt(beat), osc("square", f / 2, n, cutoff=2400) * e, 0.0, gain * 0.25)
        else:
            add(buses[layer], bt(beat), osc(shape, f, n, cutoff=4500) * e, 0.0, gain * 0.6)
        if octave_layer:
            add(buses["chip"], bt(beat), osc("pulse25", f * 2, n, cutoff=7000) * e, 0.0, gain * 0.22)

    lead_ev = []   # (beat, len, midi, gain, layer, shape, octave, harmony)
    for b, l, m in hook_events(10):
        lead_ev.append((b, l, m, 1.0, "lead", "saw", False, False))
    for b, l, m in hook_events(14, alt=True):
        lead_ev.append((b, l, m, 1.0, "lead", "saw", False, True))
    for b, l, m in phrase(18, TAG):
        lead_ev.append((b, l, m, 0.9, "lead", "saw", False, False))
    for rep in (21, 25):
        for b, l, m in phrase(rep, RIFF):
            lead_ev.append((b, l, m, 0.75, "chip", "pulse12", False, False))
    for b, l, m in hook_events(25, transpose=-12):
        lead_ev.append((b, l, m, 0.7, "lead", "square", False, False))
    for b, l, m in hook_events(29, alt=True):
        lead_ev.append((b, l, m, 1.0, "lead", "saw", False, True))
    lead_ev.append((132, 2, 85, 0.9, "lead", "saw", False, False))
    lead_ev.append((134, 1, 82, 0.8, "lead", "saw", False, False))
    lead_ev.append((135, 1, 85, 0.8, "lead", "saw", False, False))
    for bar0, alt in ((34, False), (38, True), (42, False)):
        for b, l, m in hook_events(bar0, alt=alt):
            if b >= 182:
                continue
            lead_ev.append((b, l, m + 2, 1.05, "lead", "saw", True, True))
    for b, l, m, g, layer, shape, octv, harm in lead_ev:
        lead_note(b, l, m, g, layer, shape, octv)
        if harm:
            hm = third_below(m - 2) + 2 if b >= 136 else third_below(m)
            lead_note(b, l, hm, g * 0.45, layer, shape, False)
    log("  lead")

    for bi, (ch, tr) in enumerate(BARS):
        if not (29 <= bi <= 32 or 34 <= bi <= 45):
            continue
        for k in range(4):
            beat = bi * 4 + k + 0.5
            if beat >= 182:
                break
            for i, m in enumerate(CHORDS[ch][1]):
                e = env_adsr(0.12, 0.003, 0.09, 0.2, 0.1)
                v = osc("saw", mtof(m + tr + 12), len(e), cutoff=3500, phase0=rng.uniform()) * e
                add(buses["stab"], bt(beat), v, (-0.5, -0.15, 0.15, 0.5)[i], 0.07)
    log("  stabs")

    # ---------------- drums ----------------
    kicks = []
    D = buses["drums"]

    def hit(name, beat, gain, pan=0.0, bus=None):
        add(buses[bus] if bus else D, bt(beat), kit[name], pan, gain)

    def full_bar(bi, hats16=True, extra=False):
        for k in range(4):
            b = bi * 4 + k
            kicks.append(b)
            if k in (1, 3):
                hit("snare", b, 0.55)
                hit("clap", b, 0.32, 0.1)
            hit("ohat", b + 0.5, 0.11, 0.3)
            if hats16:
                for s in range(4):
                    hit("hat", b + s * 0.25, (0.16 if s == 2 else 0.09), -0.3)
            else:
                hit("hat", b, 0.1, -0.3)
            if extra:
                hit("shaker", b + 0.25, 0.08, 0.6)
                hit("shaker", b + 0.75, 0.06, -0.6)

    def roll(b0, b1, v0, v1):
        b = b0
        while b < b1 - 1e-9:
            u = (b - b0) / (b1 - b0)
            step = 0.25 if u < 0.5 else 0.125
            hit("snare", b, (v0 + (v1 - v0) * u) * 0.55, 0.0)
            b += step

    # build 11-20 s: hats from beat 22, kick from beat 24, claps from bar 8
    for k in range(22, 36):
        u = (k - 22) / 14
        hit("hat", k + 0.5, 0.05 + 0.08 * u, -0.3)
        hit("hat", k, 0.03 + 0.05 * u, 0.3)
    for k in range(24, 38):
        kicks.append(k)
    for k in (33, 35):
        hit("clap", k, 0.3, 0.1)
    roll(36, 40, 0.25, 1.0)
    for bi in range(10, 20):
        full_bar(bi)
    for s in range(4):
        hit("snare", 79 + s * 0.25, 0.3 + 0.1 * s)
    for bi in range(21, 33):
        full_bar(bi, hats16=bi >= 25, extra=bi >= 29)
    kicks += [132, 133]
    roll(132, 136, 0.3, 1.0)
    for bi in range(34, 46):
        full_bar(bi, extra=True)
    kicks[:] = [k for k in kicks if k < 182]
    roll(182, 188, 0.2, 1.0)
    for b0 in (71, 119, 151):  # tom fills on the last beat before a phrase
        for s, nm in enumerate(("tom_hi", "tom_hi", "tom_lo", "tom_lo")):
            hit(nm, b0 + s * 0.25, 0.4, (-0.4, -0.2, 0.2, 0.4)[s])
    for b in kicks:
        hit("kick", b, 0.95, 0.0, "kick")
    for b in (40, 84, 100, 116, 136, 152, 168):
        hit("crash", b, 0.42, 0.25)
    log("  drums")

    # ---------------- fx: risers, impacts, reverse crashes ----------------
    for t0, dur, gn, gp in ((16.0, 4.0, 0.32, 0.10), (66.0, 2.0, 0.32, 0.10), (91.0, 3.0, 0.75, 0.30)):
        add(buses["fx"], t0, noise_riser(dur, 250, 9000, int(t0)), gain=gn)
        add(buses["fx"], t0, pitch_riser(dur, 45, 69), gain=gp)
    rc = kit["crash"][: s2n(1.5)][::-1]
    for t_end in (20.0, 42.0, 68.0):
        add(buses["fx"], t_end - len(rc) / SR, rc, -0.2, 0.28)
    add(buses["kick"], 20.0, boom(2.0), 0.0, 0.55)
    add(buses["kick"], 68.0, boom(1.5), 0.0, 0.35)
    # final hit at 94 s
    add(buses["kick"], 94.0, boom(6.0, tau=1.6), 0.0, 0.9)
    add(buses["kick"], 94.0, kit["kick"], 0.0, 0.9)
    add(D, 94.0, kit["crash"], 0.0, 0.7)
    for i, m in enumerate([47, 54, 59, 61, 62, 66, 71, 73, 78]):
        e = env_adsr(1.0, 0.002, 1.8, 0.0, 0.5)
        for det, pan in ((-0.12, -0.8), (0.12, 0.8)):
            add(buses["stab"], 94.0, osc("saw", mtof(m + det), len(e), cutoff=4000) * e, pan, 0.08)
    log("  fx")

    # ---------------- sidechain ducking ----------------
    duck = np.ones(N)
    L = s2n(0.3)
    c = (1.0 - np.arange(L) / L) ** 2
    att = s2n(0.004)
    for b in kicks + [188]:
        s = s2n(bt(b)) - att
        seg = np.concatenate([np.linspace(0, 1, att, endpoint=False), c])
        e = min(N, s + len(seg))
        duck[s:e] = np.minimum(duck[s:e], 1.0 - seg[: e - s])

    def ducked(x, depth):
        return x * (1.0 - depth * (1.0 - duck))

    # ---------------- filter automation on the synth bus ----------------
    def fc_at(t):
        fc = np.full_like(t, 20000.0)
        m = t < 11.0
        fc[m] = 450.0 * (1400.0 / 450.0) ** (np.clip(t[m], 0, 11) / 11.0)
        m = (t >= 11.0) & (t < 20.0)
        fc[m] = 1400.0 * (20000.0 / 1400.0) ** (((t[m] - 11.0) / 9.0) ** 2.2)
        m = (t >= 40.0) & (t < 42.0)
        fc[m] = 700.0 * (20000.0 / 700.0) ** (((t[m] - 40.0) / 2.0) ** 2.5)
        return fc

    def hpc_at(t):
        h = np.full_like(t, 10.0)
        m = (t >= 91.0) & (t < 94.0)
        h[m] = 10.0 * (500.0 / 10.0) ** ((t[m] - 91.0) / 3.0)
        return h

    def synth_filter(t, f):
        return g_lp(f, fc_at(t), 2) * g_hp(f, hpc_at(t), 2)

    synth = (ducked(buses["pad"], 0.65) + ducked(buses["arp"], 0.45) + ducked(buses["lead"], 0.25)
             + ducked(buses["chip"], 0.4) + ducked(buses["stab"], 0.4))
    # ping-pong echo on arp + chip for width
    echo = delay_pingpong((buses["arp"][0] + buses["arp"][1] + buses["chip"][0] + buses["chip"][1]) * 0.5,
                          0.375, 0.45, 4)
    synth += ducked(echo, 0.5) * 0.3
    synth = tv_filter(synth, synth_filter)
    log("  synth filter")

    bass = ducked(buses["bass"], 0.55)
    bass = fft_filter(bass, lambda f: g_hp(f, 28.0, 2))
    bass = np.repeat(bass.mean(axis=0, keepdims=True), 2, axis=0)   # bass is mono

    send = (synth[0] + synth[1]) * 0.5 * 0.6 + (buses["drums"][0] + buses["drums"][1]) * 0.5 * 0.15 \
        + (buses["fx"][0] + buses["fx"][1]) * 0.5 * 0.3
    wet = reverb(send, 3.0, 2.3, 7, 6500)
    wet = ducked(wet, 0.3)
    log("  reverb")

    drums = buses["drums"] + buses["kick"]
    mix = 1.0 * drums + 0.9 * bass + 1.0 * synth + 0.8 * buses["fx"] + 0.22 * wet
    # gentle intro fade-in and final ring-out fade
    t = np.arange(N) / SR
    fade = np.clip(t / 1.5, 0, 1) * np.where(t > 97.5, np.cos(np.clip((t - 97.5) / (TOTAL - 97.5), 0, 1) * np.pi / 2), 1.0)
    mix *= fade
    mix -= mix.mean(axis=1, keepdims=True)

    # loudness: iterate gain into the limiter
    g = 10 ** ((MUSIC_LUFS - lufs(mix)) / 20.0)
    for _ in range(4):
        y = limit(mix * g, MUSIC_PEAK_DB - 0.05)
        L = lufs(y)
        if abs(L - MUSIC_LUFS) < 0.1:
            break
        g *= 10 ** ((MUSIC_LUFS - L) / 20.0)
    log("  master: %.2f LUFS, peak %.2f dBFS, gain %.1f dB" % (lufs(y), db(np.max(np.abs(y))), db(g)))
    return y


# --------------------------------------------------------------------------
# Sound effects
# --------------------------------------------------------------------------
def to_stereo(x, pan=0.0):
    if x.ndim == 2:
        return x
    gl, gr = pan_gains(pan)
    return np.stack([x * gl, x * gr])


def tail_fade(x, sec):
    n = s2n(sec)
    x[..., -n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2
    return x


def with_reverb(dry, wet_gain, dur, rt60, seed):
    total = dry.shape[-1]
    mono = dry.mean(axis=0) if dry.ndim == 2 else dry
    return to_stereo(dry) + wet_gain * reverb(mono, dur, rt60, seed)[:, :total]


def sfx_chime():
    n = s2n(1.5)
    out = np.zeros((2, n))
    for (t0, m, pan) in ((0.0, 76, -0.35), (0.075, 83, 0.0), (0.15, 88, 0.35), (0.15, 64, 0.0)):
        k = n - s2n(t0)
        t = np.arange(k) / SR
        f = mtof(m)
        v = np.zeros(k)
        for ratio, amp, tau in ((1, 1, 0.8), (2, .45, .45), (3, .25, .3), (4.17, .12, .18), (5.43, .08, .12)):
            v += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / tau)
        v *= np.minimum(1, t / 0.002)
        add(out, t0, v, pan, 0.4 if m > 70 else 0.25)
    pad = np.zeros(n)
    t = np.arange(n) / SR
    for m in (64, 71, 76):
        pad += osc("saw", mtof(m), n, cutoff=1500) * np.sin(np.pi * np.clip(t / 1.4, 0, 1)) ** 2
    add(out, 0.0, pad, 0.0, 0.05)
    out = with_reverb(out, 0.35, 1.6, 1.3, 31)
    return tail_fade(out, 0.25)


def sfx_whoosh(dur=0.6, f0=350.0, f1=5000.0, seed=41):
    n = s2n(dur)
    x = noise(n, seed)

    def gfn(t, f):
        u = np.clip(t / dur, 0, 1)
        fc = f0 * (f1 / f0) ** np.sin(np.pi * np.clip(u * 0.9, 0, 1)) ** 1.5
        return g_bp(f, fc, 1.0)
    y = tv_filter(x, gfn)
    t = np.arange(n) / SR
    u = t / dur
    amp = np.sin(np.pi * np.clip(u, 0, 1)) ** 2 * np.exp(-1.5 * u) * (u < 1)
    y = y * amp
    p = (u * 2 - 1) * 0.8
    a = (p + 1) * np.pi / 4
    out = np.stack([y * np.cos(a), y * np.sin(a)]) * math.sqrt(2)
    return tail_fade(out, 0.03)


def sfx_riser():
    out = noise_riser(3.0, 200, 9500, 51) * 0.8 + 0.35 * pitch_riser(3.0, 45, 69)
    return out


def sfx_hit():
    b = boom(2.0, f_hi=80.0, f_lo=33.0, tau=0.55, seed=61)
    out = to_stereo(b)
    t = np.arange(len(b)) / SR
    cr = fft_filter(noise(len(b), 62), lambda f: g_hp(f, 3000)) * np.exp(-t / 0.35)
    out[0] += 0.12 * cr
    out[1] += 0.12 * np.roll(cr, 211)
    out = with_reverb(out, 0.25, 2.0, 1.6, 63)
    return tail_fade(out, 0.2)


def sfx_blip():
    n = s2n(0.12)
    t = np.arange(n) / SR
    f = 1320 * (1 + 0.25 * np.exp(-t / 0.008))
    v = osc("square", f, n, cutoff=6000) * np.exp(-t / 0.03) * np.minimum(1, t / 0.002)
    return tail_fade(to_stereo(v), 0.01)


def sfx_blip2():
    n = s2n(0.32)
    out = np.zeros((2, n))
    for t0, m, d in ((0.0, 83, 0.07), (0.075, 88, 0.2)):
        e = env_adsr(d, 0.002, 0.08, 0.5, 0.05)
        add(out, t0, osc("pulse25", mtof(m), len(e), cutoff=7000) * e, 0.0, 0.6)
        add(out, t0, osc("square", mtof(m - 12), len(e), cutoff=3000) * e, 0.0, 0.25)
    return tail_fade(out, 0.02)


def sfx_slam():
    n = s2n(3.0)
    t = np.arange(n) / SR
    out = to_stereo(np.concatenate([boom(2.6, f_hi=90, f_lo=30, tau=0.9, seed=71), np.zeros(n - s2n(2.6))]))
    met = np.zeros(n)
    for fq in (431.0, 617.0, 893.0, 1187.0, 1553.0):
        met += np.sin(2 * np.pi * fq * t) * np.exp(-t / 0.5)
    nz = fft_filter(noise(n, 72), lambda f: g_hp(f, 2500)) * np.exp(-t / 0.6)
    add(out, 0.0, met / 5 * 0.25, -0.3)
    add(out, 0.0, nz / np.max(np.abs(nz)) * 0.25, 0.3)
    for m, pan in ((45, 0.0), (52, -0.5), (57, 0.5), (64, 0.0)):
        e = env_adsr(0.6, 0.002, 0.5, 0.3, 1.2)
        add(out, 0.0, osc("saw", mtof(m), len(e), cutoff=2500) * e, pan, 0.12)
    out = with_reverb(out, 0.4, 3.0, 2.4, 73)
    return tail_fade(out, 0.4)


def sfx_swish_short():
    return sfx_whoosh(0.25, 1500.0, 11000.0, 81)


# --------------------------------------------------------------------------
def write_wav(path, x):
    x = to_stereo(np.asarray(x, dtype=np.float64))
    pcm = np.clip(np.round(x.T * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    outdir = argv[1]
    os.makedirs(outdir, exist_ok=True)
    t0 = time.time()
    sfx = {
        "chime": sfx_chime(), "whoosh": sfx_whoosh(), "riser": sfx_riser(), "hit": sfx_hit(),
        "blip": sfx_blip(), "blip2": sfx_blip2(), "slam": sfx_slam(), "swish_short": sfx_swish_short(),
    }
    sfx["whoosh_rev"] = sfx["whoosh"][:, ::-1].copy()
    for name, x in sfx.items():
        x = peak_normalise(x - x.mean(axis=-1, keepdims=True), SFX_PEAK_DB)
        write_wav(os.path.join(outdir, name + ".wav"), x)
        print("%-12s %5.2f s  peak %.2f dBFS" % (name, x.shape[-1] / SR, db(np.max(np.abs(x)))))
    print("music:")
    y = render_music(lambda s: print(s, "(%.1fs)" % (time.time() - t0)))
    write_wav(os.path.join(outdir, "music.wav"), y)
    print("music.wav    %.2f s  written to %s  (total %.1fs)" % (y.shape[1] / SR, outdir, time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
