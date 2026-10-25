# Native GBA Nature Power caller

Tested contribution stacked on #248. Gen1 is an unchanged, read-only
reference at `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.

## Implemented contract

Nature Power announces before its terrain-selected child. The child owns the
selected Nature Power PP slot, reduces it after its public event subscribers,
and uses its own target/Pressure rules. Ordinary called moves continue to own
no PP slot. Zero PP is admitted/refused before the parent script; changing PP
inside a later callback cannot rewrite that admission decision.

The native terrain table covers grass, long grass, sand, underwater, water,
pond, mountain, cave, building and plain. Explicit numeric/string terrain
inputs retain the reference's coercion and fallback. Cached host terrain names
use the existing GBA terrain identifiers. The new builtin is installed only for
GBA, including the ordinary Loader path and no-Loader native fallback.

Shared called-target dispatch preserves existing Sleep Talk targets and caller
provenance. Nature Power lends PP ownership only to the first child body, so
spread continuations do not spend it repeatedly. Choice Band and move-end
commands identify the native parent. Generic authored calls keep their existing
ownership path. Nested native callers preserve the innermost caller's resulting
history: Sleep Talk -> Nature Power -> terrain move records Nature Power. Sleep
Talk scans all four native slots even when a callback removes an earlier slot. This is a public-event/native-command change, not a claim of
complete graphical or full-mod acceptance.

Native command revision is 14; party codec remains 1. The independent unchanged
#248 hasher, with only revision 13 changed to 14, reproduces
`cb314093f24370e7`; legacy digest `e33d251961f2a41d` is retained.

## Checkpoint evidence

- **6,048 equal paired rows** across FireRed and Emerald, all single/double
  actors, fourteen terrain inputs, four held-item cases, ordinary/Pressure/zero
  PP, callback zero/refill, replaced/removed/reordered slots, and consecutive
  public event subscribers. Captured payloads, native/public PP, every held
  read, RNG, damage, actor state and retired PP are compared without filtering.
- Exact #248 production differs in **5,376** of the same rows. Both negative
  workers exit zero: these are behavioral differences, not fixture crashes.
- A second **6,048-row** matrix runs the same authored API-3 mod on both engines.
  It registers `PORTABLE_NATURE` with canonical effect `NATURE_POWER`, verifies
  its public record round trip and retains the same full execution evidence.
  Its direct regression passes **17,474** checks.
- Another **6,048** paired rows exercise native Sleep Talk -> Nature Power
  chains, including slot removal, replacement, reordering and Pressure. The
  previous feature production differs in **4,032** chained rows. A complete
  actual-script probe originally showed last move 267 in the reference versus
  214 in the host; that failure is retained.
- Related Sleep Talk, Choice Band, Baton Pass, authored calls and PP contracts
  pass **36 workers / 21,474 paired rows**, including all three Nature Power
  modes. The direct chained regression passes **15,458** checks.
- The direct engine suite passes **28,926** checks, including generation
  boundaries and event-visible child PP. Actual host/guest/spectator completes
  two native menu turns per profile with stateful held steering, **108** checks,
  matching event traces, PP and every paired state hash/component.
- The initial fixture lacked a descriptive Choice Band record on both sides;
  the reference's intrinsic fallback then exposed different public IDs. Both
  sides now receive identical owned item definitions. All failed/superseded raw
  observations remain in local QA; no production fallback or relaxed assertion
  hides them.

The fixture uses owned, controlled native-shaped child definitions to isolate
caller behavior; it does not certify the complete cartridge child catalog.
Actual local FireRed/Emerald imports additionally pass **160 controlled public-menu
scenarios**: native and API-3 registered callers, all ten terrains, Choice Band
and Shell Bell, direct and Sleep Talk callers, event-visible PP, selected-slot
ownership, resulting history, advertised child IDs,
actual Stun Spore status and damaging children. Every move is submitted through
`mod.battle:submit()`, and the native text/result queue returns to its menu. This
is CPU-only constructed-battle acceptance with the intro skipped, not a graphics
or complete-playthrough result.

The first full feature/combined batches were explicitly interrupted after the
nested-history failure was proven. Partial raw logs and interruption records
are retained separately from final acceptance.

## Final acceptance

Feature `0536521ea23e41af8c206961a266db96f5ff6eb1` passes **153/162** engine
suites, SDK **3/3** and B30. The exact Counter of **25 inherited FAIL lines in
nine suites** equals fresh unchanged #248 (`1ea0f875`, **149/158**).
Combined `0ed0602be9019102a06f4df3ee22480bca1d800f` passes **271/271**, SDK
**3/3**, all quick tiers and B30, with zero FAIL lines.

Each runtime passes **172 workers / 122,012 identical paired enemy/action
rows**, plus **2,040 held-command** and **6,912 ordinary-damage rows**:
**180 workers / 130,964** selected paired observations. Every accepted worker
exits zero; there is no accepted timeout or filtered observation. The native,
public-content and chained Nature Power matrices each contribute 6,048 rows.

All four held-item formats pass strict scheduling (**40 workers / 1,914 rows**).
Charge contracts pass four formats (**64 workers / 1,020 rows**), preserving
the feature prerequisite's explicit legacy enemy-PP policy; the combined fork
requires raw native policy through existing #162. Existing imported Sleep Talk
and post-hit scenarios pass alongside the 160 new Nature Power scenarios.
Independent protocol audit, AST-verified formatting, actionlint and whitespace
checks pass. Later publication edits preserve these runtime, test and tool trees.

Source-bound summaries and raw-report digests are in
[the QA receipt](qa/native-gen3-nature-power.json).

## Remaining scope

Additional special callers/catalogs/controllers, broad public-effect overrides,
Ruby/Sapphire-specific qualification, native text-resource/pixel parity and
unchanged full-mod/complete graphical playthrough acceptance remain open.
No claim of complete battle or mod portability is made by this contribution.
No ROMs, caches, normal saves or mod assets
are included.

## Reproduction

Use maintained LuaJIT at `a4c064539ea931274d407e1249b4bb575424a0f4`.

```sh
python3 tools/enemy-action-contract-check/check.py --gen1 /path/to/read-only-gen1 --lua /path/to/luajit --mode nature_power --report /tmp/nature-power-report.json
/path/to/luajit tests/engine/gen3_nature_power.lua
/path/to/luajit tests/engine/gen3_nature_power_link.lua
/path/to/luajit tools/enemy-action-contract-check/imported-nature-power-smoke.lua /path/to/local-cache
/path/to/luajit tools/enemy-action-contract-check/imported-nature-power-smoke.lua /path/to/local-cache --sleep-talk
```
