# Native GBA Focus Band presentation

This path queues the native Focus Band general
animation before the held-on message in both native damage paths. The real
battle queue owns its frame clock, sound, red palette fades and signed
fixed-point movement. Animation options retain the native general-animation
pause. Visible Substitute and hidden actors skip playback; a temporarily
lowered Substitute permits playback without changing its logical HP.

The complete native sequencer/VM comparison currently matches **384 paired
inputs / 11,112 tick states / 192 sound controls** across FireRed and Emerald.
It covers Poison and Focus Band, all six single/double actor positions,
animation options, mono/stereo, ordinary, hidden, Substitute and lowered
Substitute states. The expanded host unit covers **13,778 checks**.

The first controller and incomplete Emerald fixture failures are retained in
`tmp/focus-band-qa/`. Emerald requires native picture coordinates to execute
its return task. The owned test dataset supplies those coordinates through
the existing virtual cache filesystem; no reference functions or files are
patched. The comparison checker now rejects native VM error/wait-cap
diagnostics even if the worker exits zero, and fingerprints the sound fixture.

The frozen runtime completes 161/170 engine suites, SDK 3/3 and B30, with
exactly the same 25 inherited FAIL lines as fresh #258. The corrected frozen
controller rerun passes all eight Poison/Focus Band and PCM workers at
`d470eeee`. FireRed retains its built-in back offset 10; the owned Emerald
input uses 8. The earlier incorrect shared-offset assertion remains retained
as a failed fixture. The final 32-worker matrix also passes on the combined
fork. Native revision 17, Substitute fade and linked/imported qualification
are documented in `native-gen3-mirror-move.md`. The reference remains read-only
at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`; final GPU pixels and whole
synthesizer waveforms are outside these CPU results.
