# Portable interactive frame example

Copy into `mods/`. This unchanged entry chunk works on Gen1Recomp and
Gen2Recomped. `exports.pause(true)` pauses Game updates while the mod continues
to observe interactive frames; `pause(false)` resumes. `exports.stop()` removes
the hook. The example starts unpaused and issues no synthetic input.

The public API, poll count and latest Game/delta observation are exported for
the headless contract tests. It retains only the latest observation, without
allocating an unbounded frame journal. The API-2 manifest is also exercised as
unified API 2 and API 3 by the checker. See
[the frame contract](../../docs/portable-core-update.md), particularly the
separate deterministic-driver routing.
