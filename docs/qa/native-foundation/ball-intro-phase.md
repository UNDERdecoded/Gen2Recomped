# Keep ball observations in the actual native entry phase

The native send-out inserts its wait after the intro observation was bound.
That row is absent from the original observation map, so looking through the
queue reports the following message/action while the real ball still flies.
This also prevents consumers from identifying their genuine send-out window.

While the actual native ball is playing, retain the bound send-out step only
when its send-out side and battler identity match the current native player or
opponent. The existing slide still wins before release; after the ball retires,
normal native row synchronization resumes. Keep only scalar step indices in
the token. No new rows, callbacks, timeline, private trainer animation, native
controller or permission to skip an action are added.

`native_ball_intro_phase.lua` runs actual native trainer intros across five
GBA editions. It provides explicit synthetic sprite centres; this is phase/
queue/clock validation, not a rendered-geometry qualification. Repeated reads
leave the full native frame/queue/wait/ball-position/HP/PP trace equal to the
module-absent control, and completion retires the observation. Focused run
`a072cb532f` passes12 groups, including3475 new checks. Exact predecessor
`dd5a507d`, run `3b0c93abd8`, reproduces1035 failures out of3475 with the identical
fixture and no native controller overlay.

Frozen current-main composition `d05bd459f0` passes186 CPU groups including
main `0af0b3cf` appearance/new-game/ending changes. Source hashes match the
committed phase module and fixture. Older-public composition `dac22e1a00`
passes70 groups, including all3475 checks, preserving its existing native
simulation and cartridge prerequisites. The offered raw branch reuses the
previous entry observation/binding component (preimage already offered in
#329); qualification applies only the new observation hunk to that preimage.

The accepted real FireRed flight `368069098b` predates this phase addition.
It qualifies preceding import/progress/paint fixes only. Full trainer-specific
throw poses, the native tween notification/extension contract, switches and
other views still require separate native ownership work; exposing a correct
step identity alone does not implement those features. Hosted CI is separate.
Only owned profiles/copies are used, with a20GiB free floor. Player saves and
private files remain untouched.
