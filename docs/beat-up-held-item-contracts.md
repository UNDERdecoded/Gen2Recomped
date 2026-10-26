# Beat Up held-item adjustment contracts

These contracts verify the composition of #206's native Beat Up executor
and #182's native held-item damage adjustment. They add no new runtime
behavior: both existing changes must reach the same build to match the
unchanged Gen1 reference.

FireRed and Emerald query Focus Band once after each reached strike's
critical/variation calculation, including nonlethal hits, Substitute hits
and Endure's zero-damage hits. Each strike receives its own roll; a previous
successful nonlethal or Substitute roll does not protect a later strike.
The separate Ruby/Sapphire reference policy keeps move-local success state;
that policy is not selected by these FireRed/Emerald profiles and is not
emulated here.

The same API-3 consumer and shared native fixture execute actual selected
moves on both engines. Seventeen cases at all four user positions cover:

- No item, physical native Focus Band (196), and an imported-shaped custom
  item with adjustable hold metadata (1196).
- Successful/failed nonlethal and lethal rolls, the strict 9/10 threshold,
  and a zero-percent item that must still consume its random draw.
- Breaking/surviving Substitute, Endure, later successful rolls, removal
  and equipping inside real public damage-event callbacks.
- A second move that cannot reuse a previous successful roll, owned PP,
  per-hit public event amounts/metadata, special counter memory and the
  precise number/order/value of Focus Band draws.

Native physical IDs have built-in hold metadata in the reference. Parameter
mutation therefore uses the imported-shaped custom ID rather than pretending
that changing a cached physical row overrides that native table. The test
restores source-process fixture tables when finished; the Gen1 checkout is
never edited.

```sh
luajit tests/engine/gen3_beat_up_adjustment.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua /path/to/pinned/luajit \
  --report /tmp/enemy-action-report.json
```

The focused suite passes **1,672 checks**. The full comparison passes
**44 isolated workers / 4,622 paired observations** against clean read-only
Gen1Recomp `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, using JIT-enabled
LuaJIT `a4c064539ea931274d407e1249b4bb575424a0f4`. The worker also retains
all previous action, target, Helping Hand, Follow Me, Spit Up and Beat Up
contracts. RNG observations normalize critical/variation operands; the new
Focus Band checks assert the actual 0..99 draws and their per-hit order,
not a complete raw engine RNG trace.

Negative control: #206 without #182 fails **56 assertions** in the new
FireRed cases. The clean composed prerequisite is
`45220e44` (#206 plus #182); it already passes the new behavior. No built-in
record revision or fingerprint golden changes are necessary for test-only
coverage. Full gameplay, animations, joined multi-trainer/link parties,
Ruby/Sapphire controllers and other scripted damage executors remain
separate acceptance surfaces.
