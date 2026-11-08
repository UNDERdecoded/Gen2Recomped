# Trailer audio

`make_audio.py` synthesises the music and sound effects for the "Play Together" trailer (`../TRAILER_ONLINE.md`).
- Everything is generated from scratch: wavetable oscillators, filtered noise and FFT reverb.
- No samples, no downloads, no borrowed melodies. The chord loop, hook, riff and arpeggio are original.

```powershell
python tools/trailer/audio/make_audio.py tools/trailer/remotion/public/audio
```

- Needs Python 3 and numpy. Output is deterministic and takes about 35 s.
- Writes 48 kHz, 16-bit stereo WAVs. `public/audio/` is git-ignored, so don't commit them.

## music.wav

About 102 s at 120 BPM: one beat is 0.5 s and one bar is 2 s. It is mastered to about -14 LUFS integrated, with peaks at or below -1 dBFS. The bass is mono, the pads and arpeggio are wide, and the kick ducks the pads, arpeggio, bass and lead.

| Time | Bars | Section |
|---|---|---|
| 0:00–0:11 | 0–5½ | Intro. Pad and pulse arpeggio, with the low-pass opening slowly. A minor, loop Am–F–C–G. |
| 0:11–0:20 | 5½–9 | Build. Hats from 0:11, kick from 0:12, filtered bass from 0:16, filter fully open by 0:20. Noise and pitch riser from 0:16. Snare roll in bar 9 (0:18–0:20). |
| **0:20** | 10 | **Drop.** Boom and crash, full drums, octave bass, supersaw lead hook (2 × 4 bars, then a 2-bar answer). |
| 0:40–0:42 | 20 | Breakdown. Drums and bass out, low-pass dip, reverse crash into 0:42. |
| 0:42–1:08 | 21–33 | Main groove. Chip counter-riff, the hook an octave down on square, then the full hook with harmony and offbeat stabs. Snare roll and riser in bar 33 (F# major pivot). |
| **1:08** | 34 | **Second lift.** Key change up a whole tone to B minor (Bm–G–D–A). Hook with harmony, an octave chip layer, a high arpeggio layer and shakers. |
| 1:31–1:34 | 45½–47 | Riser. Drums cut to an accelerating snare roll, the synths high-pass sweep, and the big noise and pitch riser plays. |
| **1:34** | 47 | **Final hit.** Sub boom, kick, crash, a Bm(add9) stab, and a held pad and bass. Rings out, fading from 1:37.5 to 1:42. |

## Sound effects

Each is normalised to -3 dBFS peak.

| File | Length | Sound |
|---|---|---|
| `chime.wav` | 1.5 s | Start-up chime: three bell notes rising, over a soft pad |
| `whoosh.wav` | 0.6 s | Band-swept noise, panned left to right |
| `whoosh_rev.wav` | 0.6 s | The whoosh reversed, a swell into a cut |
| `riser.wav` | 3 s | Rising noise, a saw pitch sweep and a speeding tremolo |
| `hit.wav` | 2 s | Impact boom with a sub drop and a short air tail |
| `blip.wav` | 0.12 s | UI blip |
| `blip2.wav` | 0.32 s | Two-note confirm |
| `slam.wav` | 3 s | Logo slam: boom, metal ring, a power-chord stab and a long reverb |
| `swish_short.wav` | 0.25 s | Fast high swish for quick cuts |
