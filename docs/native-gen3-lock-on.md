# Target-owned native GBA Lock-On

The generic producer stored a one-use `user.lockedOn` pointer. Native GBA
instead owns sure-hit state on the target, starting at two residual phases,
with the originating side and (in doubles) battler slot. Repeated accuracy
commands and attacks do not consume this timer. The source is unchanged Gen1
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`; all Gen1 files stay read-only.

The native Lock-On/Mind Reader producer now runs Substitute, accuracy and
Protect/semi-invulnerability checks in the observed order, then records target
ownership. The regular accuracy and OHKO consumers share that ownership check.
The real residual sweep expires the timer; normal target replacement drops it,
owner replacement clears its bindings and unrelated partner replacement leaves
it intact. Both direct primary-slot assignment and placed/forced replacements
pass through the lifecycle. The existing Baton Pass switch entry transfers the
target timer/side with the reference's slot-owner fallback behavior. The full
Baton Pass move/UI chooser is separate work; these tests exercise its explicit
switch-control entry, not a complete player chooser lifecycle.

Authored legacy GBA consumers can still supply their old one-use pointer;
older games keep their existing producer/consumer. Authored effect handlers
retain their own policies. Source constructor/party schemas and game-wide RNG
scheduling are not changed by these command contracts.

Native command revision 2 participates in full GBA link fingerprints. The
explicit revision guard prevents an overridden/custom fingerprint from admitting
different native battle rules. Matching party codecs can still negotiate shared
trade data; older command revisions cannot start a battle. Duration and owned
side/slot enter active-state components, normalized to host coordinates so the
guest's mirrored view agrees. The audited raw fixture changes from #216's
`2fd444270c3d90db` to `cf73a8e083fb8a54`: unchanged #216 hasher, only the explicit
`[native_gba_commands]1` to `2` token changes. Non-GBA golden values stay unchanged.

## Reproduce

Use maintained LuaJIT `a4c064539ea931274d407e1249b4bb575424a0f4`:

```sh
luajit tests/engine/gen3_lock_on.lua
luajit tests/engine/gen3_lock_on_link.lua
luajit tests/engine/gen3_battle_protocol.lua
bash scripts/test.sh --quick
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference \
  --lua /path/to/pinned/luajit --report /tmp/lock-on-report.json
```

The comparison executes actual Lock-On/Mind Reader move resolvers, accuracy
commands, native residual sweeps and switch functions in both engines. All four
actor slots, singles/doubles, reapplication/ownership transfer, owner/partner/
target replacement and the explicit Baton Pass transfer entry are covered.
Ordinary real hits, Protect and semi-invulnerability, Substitute including zero,
OHKO level/Sturdy/guard paths, accuracy overrides and both public accuracy/damage
entry points remain observable. Rows retain all bounded RNG calls/values,
public hook/event calls, PP, HP and raw timer/side/slot ownership. Only engine
schema representations are mapped; no observations are omitted.

A clean #216 negative control completes all 213 new rows but differs in 207,
failing 103 assertions. Its complete failing output is retained privately.
Two full seeded link mirrors aim on the first turn, attack thereafter, and
verify both marks at one residual phase then expiry, with every completed
paired turn hash/component agreeing. These are CPU/controller fixtures, not
GPU or whole-game playthrough acceptance.

A private CPU-only smoke loads actual FireRed/Emerald imports, selects canonical
`LOCK_ON` through the shared public enemy-action consumer, then executes two real
Tackle hits and two end-of-turn sweeps. It verifies one accuracy-hook call,
target/slot ownership, unchanged duration across hits and eventual expiry.
Controlled HP avoids a KO. No ROM/cache assets or saves are distributed.

Full Baton Pass chooser/playback, other side/volatile producers, native egg
legality, whole-game RNG/VBlank scheduling and live UI/full playthrough
acceptance remain separate work.
