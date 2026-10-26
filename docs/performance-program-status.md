# Performance and mod compatibility programme

Final concurrent integration: `8e336d45` includes the additional friend/suspend
and native Gen2 output commits through `fc46bd85`. Its **22/22 affected
engine suites**, all required compatibility gates and **14,520 native
checkpoint assertions per LÖVE host** pass. Full-engine **561/561** evidence
remains pinned to `a6f947a5`; it is not relabeled as a full rerun of this merge.

A1/A2, M1–M8 and P1–P9 are implemented in the composed fork and offered through
their existing upstream PRs. Existing acceptance repairs are reused.

| Task | Existing upstream PR |
| --- | --- |
| A1 — FrameProfile sections | [#272](https://github.com/UNDERdecoded/Gen2Recomped/pull/272) |
| A2 — pinned external fixtures | [#102](https://github.com/UNDERdecoded/Gen2Recomped/pull/102) |
| M1 — module aliases | [#274](https://github.com/UNDERdecoded/Gen2Recomped/pull/274) |
| M2 — selected storage | [#155](https://github.com/UNDERdecoded/Gen2Recomped/pull/155) |
| M3 — datasets | [#122](https://github.com/UNDERdecoded/Gen2Recomped/pull/122) |
| M4 — actor/battle checkpoints | [#279](https://github.com/UNDERdecoded/Gen2Recomped/pull/279) |
| M5 — per-mod callback profiles | [#303](https://github.com/UNDERdecoded/Gen2Recomped/pull/303) |
| M6 — API-2 NPC controls | [#305](https://github.com/UNDERdecoded/Gen2Recomped/pull/305) |
| M7 — native registries | [#306](https://github.com/UNDERdecoded/Gen2Recomped/pull/306) |
| M8 — lifecycle producers/followers | [#312](https://github.com/UNDERdecoded/Gen2Recomped/pull/312) |
| P1 — VSync deadline | [#283](https://github.com/UNDERdecoded/Gen2Recomped/pull/283) |
| P2 — idle GC budget | [#288](https://github.com/UNDERdecoded/Gen2Recomped/pull/288) |
| P3 — hot-path dependencies/scratch | [#290](https://github.com/UNDERdecoded/Gen2Recomped/pull/290) |
| P4 — world drawing | [#291](https://github.com/UNDERdecoded/Gen2Recomped/pull/291) |
| P5 — palette/zone uploads | [#293](https://github.com/UNDERdecoded/Gen2Recomped/pull/293) |
| P6 — PCM/prewarming/DS worker | [#316](https://github.com/UNDERdecoded/Gen2Recomped/pull/316) |
| P7 — anchored shadows | [#319](https://github.com/UNDERdecoded/Gen2Recomped/pull/319) |
| P8 — world/water budgets | [#321](https://github.com/UNDERdecoded/Gen2Recomped/pull/321) |
| P9 — LOW/AUTO/UI quads and QA starter | [#323](https://github.com/UNDERdecoded/Gen2Recomped/pull/323) |

## Acceptance

The composed fork includes concurrent friend/trade and Gen-2 display changes.
Runtime revision 9532ee36 passes **493/493 engine suites**, 3 SDK suites, 253
gallery checks, 200 API-3 comparisons and all 17 complete external entrypoints.

The public M4 runtime 13808f9d passes **168/168 engine suites** and all remaining
gates. The public performance stack a620d0c7 passes **179/179**, 3 SDK suites,
253 gallery checks, 48 API-3 comparisons and all 17 complete entrypoints.
Repairs reuse #128–#134 and #294; the eleven inherited failing suites are
resolved on both final public stacks.

LÖVE 11.5 and 12 each pass **14,520 checkpoint assertions** on the fork and public
M4 stack. CPU coverage spans all host selections (18 fork, 15 public), actual
native trainer/static producers, data-only story continuations and rollback.
That host uses synthetic content and substituted graphics; it is separate from
the actual GPU measurements below. See [checkpoint admission](https://github.com/Roxas2712/Gen2Recomped/blob/codex/upstream-native-checkpoints/docs/native-checkpoints.md)
and [exact qualification](https://github.com/Roxas2712/Gen2Recomped/blob/codex/upstream-native-checkpoints/docs/qa/checkpoint-runtime-m4.json).

## Full-game reproduction

Run tools/check_full_game_performance.py with --love, --emerald, --backend
(opengl or metal) and a new --out directory under this checkout's .local/qa.
A public checkout without the shared guard can pass --qa-tools pointing to the
fork's tools directory. Use a supported user-owned Emerald ROM.

The guarded starter freezes the committed engine and unmodified mod manifest,
imports fresh content into an isolated QA identity and blocks legacy migration,
portable saves and external import roots. It uses native Game/Overworld and the
ordinary mod loader on Pacifidlog Town. Inputs are pinned before cleanup; the
shared free-space reserve is 20 GiB.

Each flag is measured off/on over 180 warm-up and 240 measured frames, with two
120-frame FrameProfile windows. Simulation stays at 60 Hz. P1 uses cap 60 and
VSync 1; other phases use the highest normalized native cap (160 on these hosts) and VSync off. P7 applies a controlled
quarter-world-pixel camera pan after the native update. Voxel measurement waits
for quiescent native meshes and rejects missing sun sections/passes.

One disclosed test-only change enables the existing native pacing/idle-GC body
in the frozen main file, because scripted drivers normally bypass it. No timing
implementation, callbacks or installed mod permissions change. Every measured
phase must contain the actual pacing section. Results retain the original
runtime/source hashes and driver hash.

The desktop is an Apple M2 (ARM64). Metal completes every card; the additional
OpenGL replay completes the fourteen native phases, then stops at the shared
20 GiB reserve during voxel measurement. No complete OpenGL voxel qualification
is claimed for that replay. Separate earlier OpenGL component proofs remain. Sequential
FrameProfile wall/submission samples are not GPU completion timings or a
universal speedup claim; slower sections stay visible. P7 cast counts separately
show avoided static work. Component pixel, allocation, PCM/worker and rollback
proofs remain in the individual P1–P9 docs.

Emerald does not exercise DS Nitro synthesis, GB palette uniforms or UI
quad-heavy menus; their separate component acceptance remains authoritative.
Physical Android/Switch/handheld performance: **not measured**, with no such
device available. No full-story checkpoint playthrough is claimed. Unsafe or
opaque checkpoint phases retain their documented named refusals.

Every performance rollback flag remains available. Approved DS snapshots/
fallbacks and per-mod callback profiles remain. Existing copyright and licence
notices are preserved.

## Recorded FrameProfile samples

Mean ms/frame, optimization off → on. Each state has two real windows. These
are measured samples, including regressions/noise, not attributed FPS gains.

| Card / section | OpenGL native | Metal |
| --- | ---: | ---: |
| P1 / frame pacing: sleep | 0.3952 → 0.2675 | 10.7076 → 0.3172 |
| P2 / update: gc step | 0.0038 → 0.0004 | 0.0081 → 0.0038 |
| P3 / draw: whole frame | 0.6132 → 0.5207 | 2.4563 → 2.8336 |
| P4 / world: entities | 0.1381 → 0.1587 | 0.2993 → 0.1190 |
| P5 / renderer: zone blit | 0.0253 → 0.0269 | 0.0215 → 0.0227 |
| P6 / update: music | 0.0155 → 0.0352 | 0.0381 → 0.0445 |
| P7 / voxel: sun pass | not qualified in this replay | 0.9418 → 0.7756 |
| P8 / voxel: water | not qualified in this replay | 0.0913 → 0.0474 |
| P9 / draw: whole frame | 0.5573 → 0.5189 | 3.4081 → 3.9999 |

P1 includes P2 idle GC within the pacing section. P7 replaces 240 legacy static
casts with 9 static and 240 small dynamic casts in the controlled moving-camera
Metal scene. P9 world timing does not exercise quad-heavy menus. See
[full source hashes and all samples](qa/performance-full-game-p1-p9.json).

## Current upstream and fork integration

Upstream `8d5b4387` and concurrent fork `8a362c6c` are integrated. The full
engine suite passes **561/561** at `a6f947a5`. Subsequent runtime
`86f9e593` passes **12/12 targeted engine suites**, every SDK/gallery/contract/
unchanged-fixture gate and **14,520 actual-LÖVE assertions on each of 11.5
and 12**. Its complete external entrypoint count is **17/17**, using an actual
native FireRed NPC and checking owned presentation, unchanged callback
arguments and owner retirement. The full engine count is not relabeled as
a full rerun of this later revision.

Public M4 `d2551170` passes **168/168 engine suites**, all four other gates
and **14,520 assertions per native host**. Public P9 `094d8627` passes
**180/180** and all four other gates. The programme's 19 existing upstream
PRs are ready and mergeable; the callback-owner integration fix is also
offered on existing companion draft #327.

Earlier standalone PRs retain explicit dependency boundaries: P3–P5 have
green engine/SDK suites but lack later acceptance tooling/fixtures; M5–M7
have green engine/SDK/gallery/contract gates and require the existing
asset-pack/follower offers for complete external fixture entrypoints. M8
and P6–P9 pass all five gates. See [exact revisions and outcomes](qa/program-current-upstream.json).
FrameProfile samples above remain evidence of their recorded revisions;
this integration does not invent or relabel measurements.
