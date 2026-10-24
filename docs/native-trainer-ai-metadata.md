# Native trainer AI import metadata

Portable enemy switch/item hooks need the native inputs to the decision,
not just matching callback names. Import now preserves two missing inputs:

- Gen-2 trainer classes keep `attributes`, the exact seven bytes of
  `TrainerClassAttributes`, and `items`, the two nonzero item references in
  cartridge slot order. Duplicate items are preserved. The existing reward
  multiplier still comes from byte three; AI weights and item/switch flags
  are retained without inventing an interpretation.
- Each successfully parsed GBA `constants.gen3ItemEffects[id]` record also
  keeps `bytes`: the six native effect bytes followed by their actual argument
  bytes. This retains X-item bits, raw full/half-heal sentinels and compound
  EV/PP/friendship payloads needed by native battle readers. It accompanies
  the existing parsed medicine fields; their behavior is not changed here.

Gen-2 rows use the existing seven-byte class stride and version-selected
symbol lookup. Missing, invalid or truncated optional rows leave AI metadata
absent; they do not fabricate flags or stock. An empty valid stock becomes an
empty list. References use the host's existing `ITEM_nnn` format. GBA payloads
use native amount-field counts, including the shared PP argument. Ordinary ROM
bounds checks refuse truncated headers and argument payloads.

These fields are generated during import. Existing caches retain their previous
format until reimported; this change does not invent missing bytes or mutate a
loaded battle/save. It does not enable `battle.enemy_switch_or_item` by itself,
change native automatic decisions, or extend the writable API-3 trainer schema.
The hook and gameplay integration follow as separate work.

The ROM-free unit suite drives the real host trainer/group and item-effects
readers with synthetic cartridge bytes and checks cache serialization. Shared
contracts compare the actual reference importers at pinned Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`: six workers, 1,168 matching metadata
records across the Gen-2 reader and FireRed/Emerald effect-byte matrices.
See `tools/trainer-ai-metadata-contract-check/README.md` for reproduction.
No copyrighted ROM assets or text are included. This is not a full-ROM reimport,
native gameplay, AI-policy, save or pixel-equivalence claim.

The feature runtime `2ef7341810df813e09f0cc30f648cee1c57f5074` passes 32 focused
checks. Its complete ROM-free run is 138/148 engine suites, with exactly the
same 26 failure lines across ten baseline suites as parent #172; SDK 3/3 and
Dramatic Shape B30 pass. The combined runtime
`ddac8aaf1d6b042ddd3defe57fe3e8de1b8b2039`, including repairs #128–134, passes
193/193 engine suites, SDK 3/3 and B30. Formatting of the new Lua tests,
actionlint, Python compilation and diff checks also pass. Hosted CI remains
separate from these local results.
