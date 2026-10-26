# Native GBA hit and secondary-chance commands

The GBA battle path previously reused the older byte accuracy/secondary model.
That changed bounded RNG consumption, stage arithmetic and public hook entry
points. Thunder's post-hit roll also used `0..255` rather than the reference's
`0..99`. The clean reference is Gen1 commit
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`; it remains read-only.

`Gen3Accuracy` now implements the observed native percentage command: combined
accuracy/evasion stages, sequential ability/item floors, identification,
all-occupied-slot weather suppression, Protect/semi-invulnerability, separate
Oak damage/stat guards and Teachy-TV guarantees. Public `battle.accuracy`
contexts include native move identity and the calculated threshold. As in the
reference, `accuracy` is steerable; its `rng` field is informational rather
than a replacement for the live battle stream. Absorb abilities resolve before
damage computation without a generic miss message. Older games keep their
existing byte path and fingerprints.

`Gen3Secondary` shares the ordinary secondary command across status, flinch,
confusion and stat-change families. It preserves the reference's inclusive
`roll <= secondaryChance` boundary, including explicit zero, Serene Grace and
the certain-opcode bypass. The chance draw precedes effect-level faint,
Substitute, Shield Dust, status/type, Safeguard and stat-protection gates.
Zero-length Substitute/protection states are inactive. Default built-in
handlers use this path; authored `run` handlers keep their own chance policy.
A real special Fire hit thaws the target after secondary processing; a
Substitute hit does not thaw it, even when the Substitute breaks.

Strong poison uses the existing native `PSN` representation plus a boolean
`mon.toxic` marker. Native status application, API-3 callback views and edits,
party/battle snapshots, save serialization, battle construction and party-wire
transport retain that identity. Editing a bound mon's status updates its
marker and the owning battler's counter in the same callback transaction.
The public API-3 value is `TOX`, as in the reference; this is an explicit
schema mapping, not an observation filter.

## Validation

Run these ROM-free suites with the maintained LuaJIT pin
`a4c064539ea931274d407e1249b4bb575424a0f4`:

```sh
luajit tests/engine/gen3_native_accuracy.lua
luajit tests/engine/gen3_native_secondary.lua
luajit tests/engine/gen3_battle_protocol.lua
bash scripts/test.sh --quick
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference \
  --lua /path/to/pinned/luajit --report /tmp/native-hit-report.json
```

The shared fixture invokes the actual reference accuracy context and
`Secondary.withChance`, plus both engines' real move resolvers through the
public mod loader. Execution probes use the same public critical override to
isolate these phases from the separately tested critical command. They retain
all bounded RNG calls/values, accuracy contexts, damage-hook counts, PP,
HP/stages, status events and confusion/flinch/Substitute state. Conditions
include stage limits, zero-valued guards, all four actor slots, explicit
0/30/100 chances, forced effects, existing statuses, strong poison, abilities,
Fire thaw and Substitute breakage. All earlier comparison modes remain.

Local acceptance: 15,082 accuracy checks, 53,598 secondary checks and 156
protocol checks pass. All 72 workers / 48,524 paired observations agree.
The full feature run passes 98/107 engine suites, SDK 3/3 and B30. The exact
Counter of the 25 inherited FAIL lines across nine suites matches clean
PR #214 (`440a5da6`, 95/104); no failure is suppressed. Clean pre-secondary
`184fdaaa` retains 56 differing Thunder execution observations in the negative
control. The original failing reports remain in ignored private QA outputs.

A separate CPU-only smoke loads actual locally imported FireRed/Emerald
Pokemon/move/item/type/constant tables and executes imported Thunder through
the public enemy-action and status-event path. Both profiles use the native
accuracy and secondary ranges and apply paralysis. Controlled HP avoids a KO;
this is imported-record execution acceptance, not live rendering or a full
cartridge playthrough. No imported data/assets/saves are distributed here.

## Link compatibility

The full GBA fingerprint carries native command revision 1. GBA move hashes
also include the native index/effect, secondary chance, target, flags and
Protect eligibility. Cache keys include the runtime native-rule revision so
switching game contexts cannot reuse an older digest. Non-GBA fixture digests
remain unchanged; no golden is reblessed. The audited raw fixture moves from
legacy `e33d251961f2a41d` to native `3a76cc5fce47a5c3`.

Identical revised peers remain compatible. Older GBA fingerprints negotiate
only a safe content subset; the actual link controller stops before battle
setup. Unversioned peers are refused for these native rules with an engine
update message. Both role directions, per-field mutations, marker wire/save
round trips and two complete synthetic seeded link mirrors are tested. Each
mirror compares multiple completed turn hashes and all state components;
native toxic identity is included in active/bench signatures.

This is a rule-compatibility and toxic-marker guarantee. Complete cartridge
party-codec fidelity (including GBA genetics), timed Lock-On/side/volatile
producers, whole-game RNG/VBlank scheduling and demo midpoint playback remain
separate work. These controlled command tests do not certify those lifecycles.
