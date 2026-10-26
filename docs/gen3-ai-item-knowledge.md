# Native GBA AI item knowledge

Native AI scripts can now use `get_hold_effect` and `if_holds_item` through
Gen2Recomped's actual GBA interpreter. Both commands share a battle-local
observed-effect cache populated by actual effect producers. Querying it does
not consume RNG, mutate history, call a public item-substitution hook or
reveal a hidden current opponent item.

The cartridge profiles intentionally have different rules:

- FireRed records player-side observations in one shared side byte; enemy
  observations do not populate it. Its getter reads that byte for player
  battlers and actual item metadata for enemy battlers.
- Emerald keeps slot bytes. The current AI battler reads its actual item;
  another battler passes its observed EFFECT byte through the ITEM metadata
  reader. This native second lookup is preserved, including live metadata.
- Membership checks own-side physical item IDs and opposing observed bytes.
  The two operand bytes are OR-ed as in retail; they are not silently decoded
  as a corrected little-endian word.

The cache lasts for the battle and preserves unrelated history families.
It records successful Focus Band rolls and actual Leftovers healing. Failed
rolls, full-HP Leftovers, pure reads, unrelated HP loss and berry consumption
do not invent item knowledge. Loaded metadata supports explicit NONE and
zero-percent effects.

Producing the same observations requires the same damage-adjustment order.
GBA Focus Band rolls on nonlethal hits, through Substitute and before Endure.
GBA confusion uses the native two-value decision and 85–100 damage variance;
self-hits can trigger the band. GBA OHKO effects roll before Sturdy,
level/chance failure and preserve native Lock-On behavior. The separate
`Gen3OHKO` policy applies to the default record only; explicit custom gates,
damage or accuracy policies retain their behavior. Other generations retain
their existing confusion and OHKO policies.

This is native battle behavior, not a new public inventory API. Other missing
AI commands remain gated rather than being declared supported.

Primary references:
[FireRed AI commands](https://github.com/pret/pokefirered/blob/master/src/battle_ai_script_commands.c),
[Emerald AI commands](https://github.com/pret/pokeemerald/blob/731ad5bfd6e6f265508d0efcca0ba42f9dcf5881/src/battle_ai_script_commands.c),
[Emerald battle commands](https://github.com/pret/pokeemerald/blob/731ad5bfd6e6f265508d0efcca0ba42f9dcf5881/src/battle_script_commands.c),
[Emerald item reader](https://github.com/pret/pokeemerald/blob/731ad5bfd6e6f265508d0efcca0ba42f9dcf5881/src/item.c).

## Reproducible comparison

```sh
luajit tests/engine/gen3_ai_item_knowledge.lua
python3 tools/gen3-ai-item-knowledge-contract-check/check.py --gen1 /path/to/fixed/gen1
```

The checker requires the clean counterpart
`Roxas2712/gen1recomp-Mac-fix@12c9e5b5a2325470d6bb266c9a1f37b7954b698e`,
based on upstream dev `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.
Gen1Recomp also needed its placeholder getter and item-history rules fixed;
the workflow explicitly checks out that counterpart. This is not an upstream
merge claim or agreement with the original placeholder implementation.

One shared case file exercises actual VMs and actual direct-damage,
attack-canceller and OHKO paths. Only source ROM text presentation is
substituted; cartridge-shaped item and move records are input fixtures.
Coverage includes all 67 effect values, single/double selectors, physical
IDs, byte folding, live metadata, cache lifetime, no-leak reads and complete
RNG traces. It checks Focus Band success/failure, zero-percent, nonlethal and
lethal hits, Substitute, Endure, confusion, Sturdy, OHKO chance boundaries,
Protect, invulnerability and Lock-On. Host OHKO cases start at the damaging
effect stage after PP; they do not establish the whole move controller.

## Local validation

- Host focused checks: **1,491/1,491**; counterpart: **1,240/1,240**.
- Actual-engine comparison: **4 workers / 364 paired observations**, no
  differences across FireRed and Emerald.
- Negative controls fail on unchanged upstream revisions. Gen1 dev reports
  116/113 failed checks and 117/127 differing observations (FR/EM); Gen2 main
  reports 310/320 failed checks and 157/161 differing observations.
- Full host run: **65/75** engine suites, SDK **3/3**, B30 passes. The exact
  **27 FAIL lines in ten suites** match clean main, which passes **64/74**.
- The source standard run passes all selected tiers, including **1,116/1,116**
  engine suites and SDK **79/79**; game3 reports **425/425**, including **261
  self-skips** without cartridge caches. Expanded focused cases pass after
  that run with unchanged source production code.
- Shared fixture formatting and workflow lint pass.

Reports remain in ignored `tmp/ai-item-knowledge-qa/` and the external QA
folder of the same name. These are bounded CPU VM/effect checks, without
ROMs or generated assets in the commit. Full AI, graphical gameplay and
hosted CI approval remain separate validation work.
