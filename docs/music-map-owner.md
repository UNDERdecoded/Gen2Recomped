# Remembered map music contract

Mods that coordinate weather music through the engine's central Music owner
need to distinguish its remembered native map cue from the current selected
song. VASC 3.0.65-rc.4 checks for `Music.current`, `Music.mapSong` and
`Music.playMap`; the missing `mapSong` accessor previously kept its playback
adapter inactive in the fork despite successful mod loading.

`src.core.Music.mapSong()` now reads the existing remembered cue.
`Music.setMapSong(song)` changes only that cue, matching Gen1Recomp's native
radio contract. Neither operation creates, starts or stops an audio Source or
calls the music selector. Battle/direct playback preserves the cue, a real
map change replaces it, and ordinary `restoreMap` still replays it through
the existing selector and audio owner. `nil` clears the remembered cue.

The same fixture passes **168 actual-owner checks on each engine**, across
Red, Blue, Yellow, Gold, Silver, Crystal, FireRed and Emerald, with identical
public results. The clean read-only reference is
`bryanthaboi/gen1recomp@535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.
It exercises actual Music modules and hook buses; only audio-device Sources
are fakes. Unchanged Gen2Recomped main `13af468b` fails at the missing
accessor. Applying only the Music addition to that base passes all 168 checks,
without portable-API or rendering prerequisites. Existing fanfare ownership
and volume-hook regressions also pass (18 and 6 checks).

```sh
luajit tests/engine/music_map_owner.lua
python3 tools/music-map-owner-contract-check/check.py --gen1 /path/to/clean/pinned/reference
```

This closes the central map-cue API gap. These CPU fixtures alone do not
certify VASC weather-track audio, fades, device resets or general Music parity.
