# Native transition observations and source phases

`src.core.game3.battle_transition` observes the actual `BattleTransition` on
the native StateStack. Entry, tick, draw and finish wrappers are dispatched at
that state's native phases. Calling the source tick outside the update scope
does not advance it. Duplicate base calls reuse a phase result; completion
retires one exact admission and invokes its native continuation at most once.
Covered, finished and retired-dataset admissions cannot pop another screen.
Aborting does not invoke the battle callback. Failed presentation-end notices
are reported without discarding the native continuation.

The source sequence identity, frame and phase are projections of that state.
There is no copied task scheduler, simulation, palette timer or audio loop.
Registered native style selection and foreground draws remain authoritative.
The enum/selection catalogue distinguishes FRLG, Emerald and RS, including
RS's shorter enum, class ordinals, class-based exceptions and level equality.
The inherited Emerald class profile is corrected during RS import. An RS-only
cache revision transparently rebuilds old imports. Runtime profile reads stay
authoritative, including deliberately authored Emerald-shaped profiles.
See https://github.com/pret/pokeruby/blob/master/include/constants/trainers.h.

For existing geometric native styles, an owned copy of the current world
override passes through `drawWorld` before the renderer blits it. Only the
transition's own wipe/veil packets are consumed. Borrowed world images are
never mutated or released. Explicit legacy orientation is normalized once;
native orientation stays upright. Scratch targets are reused until their
view changes, then released on exit/teardown. Foreground `def.draw` styles
keep their native UI pass and are not invoked a second time as world effects.

Verification uses the actual native stack and state, an independent original
selection oracle, and Metal/OpenGL pixel comparisons against the previous
native renderer. It includes explicit orientation negatives, callback replay,
covered UI, retired saves, native peer draws and error/teardown checks.

## Open contracts

This is not original task/visual parity or complete renderer/game acceptance.
FRLG spiral and the additional Emerald/Frontier effect tasks are not yet
implemented in the native renderer. Native mugshots still need their complete
portrait/task state. `defs()` reports owned native style descriptors, not the
original task-function tables; `_fx` task internals are not fabricated.
`blackSpans`/`screenCoverage` explicitly report unavailable native mask
observations. Full original palette/audio tasks, foreground/UI-owned world
effect composition, arbitrary source effect authoring, all custom renderer
paths, five-edition battle/gameplay and full mod-coexistence acceptance remain
required. Package loading past this module alone is not a gameplay result.
