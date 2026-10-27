# Native battle animation bridge

`src.core.game3.battle.anim` presents the admitted GBA battle through its native
`BattleState`, `Gen3MoveAnim` and `Gen3BallAnim` owners. It does not load another
battle engine or rewrite a mod package. FireRed, LeafGreen, Emerald, Ruby and
Sapphire use the same boundary and their own imported identifiers and records.

## Shared clock and ownership

The native update opens one presentation phase. A source `Anim.update()` can
advance that phase while a custom ending or pose holds the combat update.
Repeated source calls and a later native base call consume the same display
steps. The native dt drives sprite animations. Outside that phase, source
updates cannot manufacture frames.

Move/ball effects, visual waits, HP drain and EXP fill remain native operations.
Only the native combat update consumes command rows, input and outcomes.
Source-launched clips occupy the native animation player and hold the command
queue until that clip finishes. A presentation serial distinguishes a finished
source clip from a newer native animation on the same player. Reset/unload
cancels only a clip still owned by that source admission.

`present(id)` has stable identity for an admitted battler. It observes native
display HP/maximum/level/status/EXP, visibility, offsets and affine effects.
Source visual overrides compose around the existing native sprite draw;
reading a native effect never applies it a second time. `shownBattler` carries
an owned presentation override without replacing the native combatant.
Replacing the session, save, data or catalogue retires old poses and callbacks.

`GameVersion.layout(id)` also reports the registered GBA family (`frlg` or
`rse`) so an unchanged field companion probe can recognize the native host.
It supports current-version and colon queries without changing cache/save
selection; an explicit registered layout takes precedence.

## Geometry and screen effects

`anim_coords` exposes authored anchors and ordering for singles and doubles.
Current imported cartridge coordinates take precedence over the standard
240x160 anchors. Temporary side bindings restore on success and failure and
preserve trailing nil arguments/results.

Supported screen effects are inversion, fade to white/black, darkening,
grayscale and blending to a custom colour. Repeated begin calls reapply within
one guarded render seam; nested seams restore their caller's shader. The native
graphics guard restores render targets, transforms, shaders and leaked pushes
after an error. Synthetic asymmetric sprites test orientation as well as colour.

## Current boundary

This bridge implements native move launch/observation, source pose tweens,
display ratios, sequence observations, screen effects and coordinate bindings.
It deliberately does not advertise a complete presentation API version.
Authored animation commands, mutable VM/sprite/task/palette callbacks,
particle bands, trainer/intro/switch/catch stage control, source HP/EXP tween
commands and complete custom UI captures still require integration. A module
being importable is not evidence of a complete mod boot or playable campaign.

## Validation

- `tests/engine/native_battle_animation.lua`: all five editions; shared clocks,
  owned clip completion, held command queues, stale poses/callbacks and 180-frame
  native trajectory comparisons per edition with and without the bridge.
- `tools/battle-animation-runtime/lifecycle-check.lua`: SDK entry failure,
  teardown and native peer callback identities.
- `tools/battle-animation-runtime/coords-check.lua`: optional local contract
  oracle supplied through `BATTLE_COORDS_ORACLE`; no external engine is bundled.
- `tools/battle-animation-runtime/host`: actual Metal/OpenGL sprite and screen
  effect rendering, pixel comparisons and graphics error restoration.

Local qualification runs use the repository's QA storage manager, frozen source
copies and dedicated LOVE identities. They use synthetic imported data and art;
they do not open player profiles, save files or ROM originals.
