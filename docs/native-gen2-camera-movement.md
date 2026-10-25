# Native Gen2 external movement handoffs

`src.world.gen2.FieldMoves` now resolves to `Gen2FieldMoves` for its movement
constants and `isBiking` / `isSurfing` predicates. They are the existing
`Gen2PlayerState` functions, so scripts and native surf/bicycle changes remain
immediately observable. There is no shadow movement byte. Legacy action,
fly-picker and collision-classification APIs are still absent: native script
and ROM-derived terrain protocols must not be replaced with guessed results.

This is sufficient for the supplied continuous camera controller to install
over the existing native `pollInput` and `stepBody` phases. Merely supplying
the name was insufficient for forced terrain: that controller completes its
public landing phases itself, then hands ice/current/forced-door movement back
to the engine. The native engine previously waited for its own grid landing
before starting those actions.

`resumeForcedMovement` now admits that return before ordinary input. Current
and forced-door collision bytes select their native direction without a held
key. The external ice `turningDirection` latch starts the existing ice handler.
Both paths retain native collision, actor interpolation, script queues and
completed-step callbacks. They do not replay an already completed free-body
landing. Blocked forced movement retains ownership of that frame. Scripts,
overlays, transitions, battles and in-progress actions cannot acquire a second
queue. The external ice latch and native ice latch are retired on map changes;
ordinary floor clears the external latch. Other generations retain their path.

## Verification

- `tests/engine/gen2_field_state_queries.lua`: 30 state/alias assertions.
- `tests/engine/gen2_forced_body_handoff.lua`: 584 assertions using real native
  maps, collision, runner and actor queues across Gold, Silver, Crystal and
  Prism, plus other-generation refusal. Includes blocked currents, directional
  walls, pending owners and error recovery.
- Existing body/input, special-handoff and CountStep suites: 21, 549 and 313
  assertions respectively.
- The committed fork passes 328 engine suites, three SDK suites and all quick
  tiers. The independent upstream composition passes the focused native suites.

An additional local CPU probe loads the supplied `3.1.2-omega.1.8`
`GoldCameraControls`, `FirstPerson`, `ThirdPerson`, `VoxelState` and `Mat4`
modules without changing their source. It passes 92 assertions on both the
fork and independent upstream composition. It exercises actual camera-space
key/stick math, both selected camera modes (including an extended third-person
body bearing), sub-cell travel, occupied-wall sliding, native counters, a real
coordinate script, Repel text ownership, native bicycle/surf movement and
ice/current/door returns. The previous `main` fails installation with
`Gold free-movement dependencies unavailable`.

The probe supplies a renderer-availability boundary and does not draw graphics.
It uses public native fixtures rather than an imported ROM. Script clocks
outside the body phase are not a complete game loop. This is **CPU integration
acceptance**, not full-package, GPU, all-story or Windows hardware acceptance.
No supplied mod code/assets or cartridge data are distributed. See the
[source-bound receipt](qa/native-foundation/johto-native-camera-state.json).

## Full-package GPU movement smoke

At source `62ca106fadebfcca1b262cde05a60a081c10d765`, fresh actual Crystal imports
with all 27,329 supplied Ver.1.8 files unchanged pass the scoped movement smoke
on macOS OpenGL/VSync 0 and Metal/VSync 1. Each backend executes 12 actual free
body ticks in First and Third Person, crosses a logical cell, retains a false
native grid-moving flag and accepts the real V key callback to change mode.
Each backend passes 19 driver assertions and two fresh OS-window proofs.
The images were inspected: they show visible, upright scenery.

The introduction is skipped and a native New Bark Town position is selected
for this controlled walk. This does not verify normal doors, map boundaries,
forced terrain with GPU, all story/encounters or Windows. A test-only assumption
about `npcAt` stopped the first run; the revised test uses native occupancy.

The generated model renderer still reports the separate 60-upvalue compile
failure. The fallback scene is visible; avatar/occlusion and complete First/
Third Person visual equivalence are **not accepted** by these proofs. The PR
remains a development checkpoint pending broader movement/transition tests.
The existing public release assets are unchanged by this follow-up.

## Full-package normal transition smoke

The next actual Crystal matrix passes 212 assertions on each of macOS
OpenGL and Metal. In both First and Third Person it walks through the normal
Cherrygrove Mart and Center entrances, opens/closes the native START menu
without moving behind it, walks inside to the exit, and returns through the
real directional carpet and native fade. It also crosses the actual
Cherrygrove/Route 29 connection in both directions. That is 12 transitions,
four menu ownership checks and four fresh owned-window proofs per backend.
Selected camera modes survive normal map handoffs and all final native owners
are clear. Original supplied files remain byte-identical.

OpenGL uses source `18489b7a`; Metal uses `aa669f69`, which additionally
integrates the current fork's separate launcher work. The
[source-bound receipt](qa/native-foundation/johto-native-camera-transitions.json)
distinguishes these builds. Initial exterior approaches are selected by QA;
travel itself uses real native input. Camera yaw uses the supplied look API,
so this is not physical mouse acceptance. No window resize is implied by the
legacy capture labels.

Two failed scenarios remain explicit: the first backward-facing entrance
looked into the front void and failed the blank-frame guard; the ordinary
forward-looking approach passes without changing that guard. A separate
fresh-save New Bark west approach did not clear a native owner and is not
accepted here. The successful connection matrix uses Cherrygrove/Route 29,
outside that early-story approach. Full story, all maps, forced-terrain GPU,
Windows and complete avatar/model/occlusion parity remain open. The generated
Stadium extension is still uninstalled. This checkpoint does not change the
existing release assets.

## Transitions with the experimental runtime

The separate extended-upvalue arm64 LÖVE host now repeats the complete normal
transition matrix with `rendererInstalled == true` required. OpenGL at source
`6f0f8d2c` and Metal at `6f926f9c` each pass 213 assertions, 12 normal door/map
transitions, four native menu ownership checks and four fresh OS-window
proofs. Both selected cameras retain native ownership and return correctly.
All 27,329 supplied files remain unchanged. The
[runtime receipt](qa/native-foundation/johto-native-runtime-upvalues.json)
binds these results to the separately qualified Lua library.

All eight room proofs were inspected and show upright geometry and NPC
figures. Black-and-white objects remain visible in some First Person frames;
complete avatar/model/occlusion and performance parity remain unaccepted.
Initial QA positions and skipped introduction still preclude all-story
acceptance. These tests use the experimental host, not the public release's
stock 60-upvalue runtime. Windows and universal packaging remain separate
gates.
