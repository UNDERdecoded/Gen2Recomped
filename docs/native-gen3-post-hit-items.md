# Native GBA post-hit item command

This change is stacked on #244. It aligns the shared King's Rock / Shell Bell
move-end command with the pinned, unchanged Gen1 reference
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Gen1 is read-only.

## Contract

The native damaging command retains its first damage, including its native
substitute convention, rather than summing every hit. The shared held read runs
after Choice Band and the ordinary move-end cure sweep. An empty hand still
produces the same read. Public hook substitutions remain authoritative.

King's Rock performs the reference's extra canonical player-slot read, including
when the attacker belongs to the other side. A changed first answer selects its
own parameter; otherwise the second read selects the chance. RNG runs before the
move flag and living-target checks, and secondary refusal checks preserve native
Shield Dust, substitute, Inner Focus and already-moved behavior. The player-slot
parameter rule intentionally matches the pinned reference; this is not a claim
that it reproduces every cartridge edition's intended behavior.

Shell Bell uses the first damage and current divisor, with minimum one HP and
maximum-HP clamping. Its native held-item animation identifies the holder in both
positions. Physical item identities 186, 187 and 219 retain intrinsic GBA effects
even if mutable descriptive metadata clears them; public hooks can replace them.

Spread scripts retain their chosen target order and count occupied defending
slots until queued removal, including a just-fainted defender. An attacker that
faints before a later ordinary spread body does not run its damage commands.
Non-GBA damage and item handling retain their existing paths.

Already-moved state belongs to the current logical turn. Spectator action pairs
are buffered FIFO until the current animation/command queue finishes, preventing
an early next-turn packet from changing the turn under a running command.
Native battle protocol revision is 13; party codec remains 1. The independent
unchanged-hasher token audit changes only revision 12 to 13, yielding
`beacb71804a6af34`; legacy digest `e33d251961f2a41d` is retained.

## Validation

Full gate source/test trees: feature `d88be1fc` passes **149/158** engine suites,
SDK **3/3** and B30. Its exact Counter of **25 inherited FAIL lines in nine
suites** equals fresh unchanged #244 (`f7c18701`, **146/155**). Combined
`d9cf080d` passes **267/267**, SDK **3/3**, every quick tier and B30, with zero
FAIL lines. Subsequent checker, reproduction-tool and documentation changes
preserve those production and test trees.

The final checker (`80c8bd8e` / combined `f8294625`) passes **160 workers /
103,868 identical paired enemy/action rows** per runtime, with every worker
exiting zero and no timeout. Additional held-damage and ordinary-damage
comparisons pass **2,040 + 6,912** rows: **168 workers / 112,820** selected
paired observations per runtime.

- Shared post-hit command: **7,488 paired rows**, retaining all held reads,
  public parameters, RNG, activation, first-damage consumption, HP, flinch and
  animation metadata.
- Actual scripts: **15,840 paired rows** for Tackle, Double Slap, Triple Kick,
  Surf, Earthquake and Sleep Talk; single/double actor slots, substitutes,
  misses/immunity, target/attacker fainting, live item changes and overrides.
  The exact #244 production differs in **12,032** of these rows. Nothing is
  filtered from failed or successful comparisons.
- Actual host/guest/spectator: **172 checks** across both profiles, physical
  items, stateful canonical reads, already-moved targets, skipped PP, all held,
  event and RNG traces, and completed state hashes. The old spectator module
  fails **14** checks in the same test.
- Strict held scheduling: four API formats, **40 workers / 1,914 paired rows**.
  Charge-decision contracts: four formats, **64 workers / 1,020 rows**, retaining
  the feature prerequisite's explicit legacy enemy-PP policy; the combined
  fork requires raw native-policy parity through existing #162.
- Fresh full Sleep Talk held-phase probes match every captured payload:
  **10/2/2/4 reads** for success/awake/empty/blocked, on both profiles and both
  runtimes. The old successful host trace had eleven.
- Existing imported-data modes pass. The additional reproduction tool exercises
  **32 CPU-only scenarios** using actual imported item/move definitions and
  controlled battlers: physical items, both sides, single/multi-hit and public
  overrides. These are not graphical or complete-playthrough acceptance.
- Independent unchanged-hasher token audit, AST-verified formatting,
  whitespace checks and actionlint pass.

Failed and superseded observations remain separate in local QA. The first link
fixture omitted its move flag; supplying native-shaped flags exposed the real
spectator turn-overlap bug. The older held fixture likewise supplied flag 51
only on its source side. Matching the host input preserves all expectations and
passes **5,511** checks; the initial eight failures remain recorded. The large
script worker also hit the old sixty-second wall-clock limit under concurrent
QA. Its bound is now 180 seconds. A forced-timeout probe proves failure is
retained with partial text and exact captured bytes, while subsequent comparisons
complete. Final accepted matrices contain no timeout or nonzero worker.

### Reproduction

Use the pinned maintained LuaJIT `a4c064539ea931274d407e1249b4bb575424a0f4`.
The shared checker requires a clean read-only Gen1 checkout at the revision above.

```sh
LUA=/path/to/luajit bash scripts/test.sh --quick
python3 tools/enemy-action-contract-check/check.py --gen1 /path/to/read-only-gen1 --lua /path/to/luajit --report /tmp/enemy-action-report.json
/path/to/luajit tests/engine/gen3_post_hit_link.lua
/path/to/luajit tools/enemy-action-contract-check/imported-post-hit-smoke.lua /path/to/existing/local-cache
```

The last command needs existing FireRed/Emerald imports; it never creates or
publishes cartridge data. Source-bound acceptance metadata and raw-report digests
are in [the QA receipt](qa/native-gen3-post-hit-items.json).

## Scope

The executable reference comparison covers registered FireRed and Emerald paths.
Ruby/Sapphire's separate per-hit item scheduling is not certified. Other special
script boundaries, full catalogs and controllers, graphical playthroughs and
unchanged full-mod acceptance remain open. No ROM data, imported caches, normal
saves or third-party mod assets are committed.
