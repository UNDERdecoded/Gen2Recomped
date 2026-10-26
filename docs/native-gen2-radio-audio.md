# Native Gen2 radio music and Snorlax admission

The native tuner and wall-radio script now start the imported channel song
through `src.core.Music`. Retuning starts the new station once; advancing
text or drawing never restarts it. Leaving the card or removing its screen
transfers the actual playing song to the native map owner, so battle music
can restore it. A new map replaces that override normally. Unavailable or
failed channel audio produces silence and restores map music on exit; it
cannot accidentally leave a previously selected flute song active.

The EXPN Card still controls availability of the flute station. The native
`SnorlaxAwake` special now checks actual flute playback and the player's
local map cell against the five cartridge proximity cells. Owning EXPN,
stale `g2RadioChannel`/`g2MapMusic` fields and rendering coordinates cannot
substitute for those conditions. A music selection hook replacing the flute
is respected and does not manufacture flute admission.

`tests/engine/gen2_radio_audio.lua` exercises actual Music with a fake audio
device, native Pokegear input/StateStack and compiled Gen2 scripts through
ScriptRunner: 167 checks across Gold, Silver and Crystal. It covers all five
cells, wrong-cell refusal, real wall-radio suspension/return, retuning,
failed audio, close, battle restoration, map replacement, external music
ownership, mod-selected audio and generation isolation.

This change covers station entry/exit and the native story gate. Complete
ROM-driven show text, timing, schedules, intermediate jingles and music-show
choices are still open. Device-free tests do not establish audible hardware
playback, original story-trigger admission, unchanged-mod GPU acceptance or
a complete playthrough. Exact-source runtime/GPU qualification is required
before inclusion in the existing preview.

Original implementation by Roxas2712; existing upstream/third-party credits
and licenses remain applicable. Specific contribution permission and required credits:
<https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md>.
