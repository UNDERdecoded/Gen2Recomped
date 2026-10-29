# Native GSC SFX admission

Normal `Sound.play` and battle-animation `Sound.playStereo` now have separate
native GSC admission. Previously both called the unrestricted static-source
path, so the fork had neither the ordinary priority rule nor an explicit
animation entry. The animation VM now uses the latter for indexed native SFX.

The priority byte follows `PlaySFX` in `pret/pokecrystal` commit
`5c877ef55197039c9676e8e3eec6d254b1c40fe8`, `home/audio.asm:180–207`:
while an indexed native SFX source is playing, a larger low byte is refused;
equal or smaller replaces the native SFX group. Completion comes from the
actual Source rather than a second timer. `PlayStereoSFX` bypasses admission
and preserves the current byte; mono mode clears preceding indexed voices.
See also `audio/engine.asm:2472–2670` at the same revision. No assembly or
ROM-derived audio is included in this contribution.

The native importer supplies sparse zero-based `sfxIndex` with `engine=gen2`
headers. The source-native `sfxOrder` format and `generation=2` headers are
also accepted. Exact labels take precedence over definition/header aliases;
no priority is guessed from an effect name. Non-GSC/file definitions retain
their previous playback path. Accepted playback is registered before public
sound events. The fork adaptation also revokes borrowed playback on ordinary preemption;
that separate lease API does not exist in this upstream baseline.
Invalidation and session suspension retire the same source owner.

`tests/engine/gen2_sfx_arbitration.lua` exercises actual Sound, ChipAudio,
ChipSynth and the native animation VM in Gold, Silver and Crystal, with both
index schemas. The only device seam is `love.audio.newSource`; a finite GSC
bytecode program is genuinely synthesized into non-silent PCM. It checks
priority, low-byte comparison, completion, stereo/mono entry, alias mapping,
source reuse, public events, reentrancy and lifecycle. The fork-only lease
and weather assertions are absent here because those owners are not present
in this older upstream baseline.
The source-native VM also resolves sounds from the actual `sfxOrder`.

## Limits of this change

This adds SFX admission over the existing static PCM voices. It does not
implement a live, shared hardware-channel mixer: partial per-channel
replacement, cry-versus-SFX channel arbitration, animation panning/duration
and authentic stereo PCM remain separate work. Stereo overlapping voices
retain the current Gen1 reference behavior. The existing PCM renderer still
writes duplicated mono to the front stereo pair. CPU/device-seam checks do
not establish audible output, complete unchanged-VASC gameplay, Windows
execution, GPU/window acceptance or a release qualification.

Only engine sources change. VASC, protected Gen1/player installations,
original ROMs and player saves are untouched. Contributions by Roxas2712;
see `LICENSE-ROXAS2712.md`, with existing third-party rights retained.
