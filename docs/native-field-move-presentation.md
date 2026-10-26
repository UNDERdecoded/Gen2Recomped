# Native field-move presentation ownership

`src.core.game3.field_move_show_mon` uses the existing `Gen3FieldMove`
StateStack admission. `start` and the native entry seam use that admission's
Pokemon, optional pose and guarded continuation. `step` consumes only the
current native update scope. Native draw wrappers consume one draw body;
explicit source draws render the current native picture in the caller's
coordinates. The renderer's frame serial prevents the normal UI pass from
painting the same externally rendered cut-in again. Drawing never advances
the streak or player-pose clock.

The cut-in retains its own 240x160 GBA surface. A mod's dialogue-box theme
cannot shrink it to the Game Boy surface or enlarge it to a DS surface.

The native admission owns its front image and resolves actual generated-asset
overrides. Completion, explicit reset, failed entry and owner retirement
release it and restore the prior player pose. Covered admissions cannot pop a
foreign screen or advance through direct source ticks. Cancelling a source
owner under another screen retires its callback immediately and leaves that
cover in place. Continuations preserve nil returns/errors and cannot execute
twice or before native completion. Retired callbacks release captured data,
and cohort references are weak so retained wrappers cannot keep a retired
save alive. Observer release leaves engine-owned continuations intact.

This is not original cut-in visual/task/audio equivalence. The current native
band, dimensions and phase lengths are still the existing reconstructed
presentation, not the original indoors/outdoors streak artwork and window
tasks. Exact cry modes/ducking, original `_fx` internals and shared band-image
cache semantics remain open. `noDuck` starts explicitly refuse unsupported
options; `invalidate` reports that native resources belong to each admission.
There are no placeholder task tables or additional gameplay clocks.

The focused lifecycle suite covers all five GBA edition identities. The real
GPU host checks upright asymmetric pictures, repeated/explicit/native draw
composition, two view sizes, one native clock and borrowed-image preservation.
Those synthetic checks do not establish original cartridge artwork parity,
unchanged mod initialization, complete renderer behavior or gameplay.
