# Native GBA AI party status

`if_status_in_party` is now runnable through the native GBA AI interpreter.
It compares the complete STATUS1 word for equality, including zero and high
bits; it is not an ANY/subset bitmask test. It reads six stored party slots,
including active mons, and requires nonzero HP and species other than NONE
or EGG. Sparse records and an extra seventh slot preserve that boundary.

FireRed interprets selector 1 as the enemy party and every other selector as
the player party. Emerald selects the current user's or target's side;
non-1 selectors mean target. The commands do not use an active battler's
cached condition instead of its stored party record, mutate data, consume
RNG or invoke a public substitution hook.

The native MON_DATA_SPECIES reader exposes the underlying species of ordinary
eggs, so the normal egg flag is not an exclusion. Bad eggs and the explicit
EGG species are excluded. This preserves the command's actual behavior
rather than reusing an unrelated usable-party predicate.

Numeric status words retain all 32 bits. Named native conditions use their
native values; named sleep reads stored remaining turns. Legacy sleep
records without a counter retain the existing source value of seven.
Actual GBA sleep infliction and interruption now maintain the stored party
counter. The default GBA sleep roll uses 0–3 plus two, Early Bird decrements
twice, and waking permits the pending move. Other generations keep their
existing RNG/waking policy; explicit custom sleep ranges remain authoritative.
The host also preserves the party's toxic identity independently of the
active battler's advancing toxic counter.

This is an internal native-AI reader, not a new public party API. Other
unsupported opcodes remain gated. The unused, broken inverse macro
`if_status_not_in_party` remains unsupported rather than being advertised as
a functioning inverse. Active-battler status bitmask predicates and unrelated
status producers are outside this change.

Primary references:
[FireRed AI commands](https://github.com/pret/pokefirered/blob/master/src/battle_ai_script_commands.c),
[FireRed species reader](https://github.com/pret/pokefirered/blob/master/src/pokemon.c),
[FireRed attack canceller](https://github.com/pret/pokefirered/blob/master/src/battle_util.c),
[Emerald AI commands](https://github.com/pret/pokeemerald/blob/731ad5bfd6e6f265508d0efcca0ba42f9dcf5881/src/battle_ai_script_commands.c).

## Reproduce

```sh
luajit tests/engine/gen3_ai_party_status.lua
python3 tools/gen3-ai-party-status-contract-check/check.py --gen1 /path/to/fixed/gen1
```

The checker requires clean counterpart `9e372ef7f18a8069289b3c2b367fa45490f98ab0`
and checks a byte-identical shared fixture. The source is the
explicit `Roxas2712/gen1recomp-Mac-fix` fork based on upstream dev
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`; it also needed equality, species,
party-selection and stored-sleep fixes. The workflow pins the exact source
counterpart. No upstream merge or agreement with the previous approximation
is implied.

## Local validation

- Host focused checks: **10,006/10,006**; source: **7,496/7,496**.
- **4 workers / 2,500 paired observations**, zero differences on FireRed and
  Emerald through actual native VMs, status producers and attack cancellers.
- Coverage includes all 256 low-byte status words, unsigned/high-bit values,
  all user/target double slots and selectors, six-slot/HP/species boundaries,
  eggs, stored versus cached status, read purity and complete producer RNG.
- Unchanged source dev fails **352** checks and differs in **352** observations
  per GBA profile. Unchanged host main fails **2,494** checks and differs in
  **1,246** observations per profile.
- Full host run: **65/75** engine suites, SDK **3/3**, B30 passes. The exact
  **27 FAIL lines across ten suites** match clean main (**64/74**).
- Authored Lua formatting, workflow lint and diff checks pass.

Reports remain in ignored `tmp/ai-party-status-qa/` and the external QA folder
of the same name. Fixtures supply cartridge-shaped records; only source ROM
text presentation is replaced. No cartridge assets are committed. These are
bounded CPU VM/status checks; they do not establish all status moves, native
controller paths, graphics, complete AI or full gameplay parity.
