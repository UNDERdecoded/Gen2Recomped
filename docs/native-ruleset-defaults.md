# Automatic rulesets and native enemy PP

New settings select `options.ruleset = false`. The shared RULESET option row
shows AUTO first, followed by sorted non-hidden registered rulesets, and can
return to AUTO from an explicit choice. AUTO uses the existing false/no-explicit-choice value, so no string id is
reserved from mods (including a registered id named `auto`). Missing old
preferences have the same meaning.

Automatic selection honors `data.constants.defaultRuleset` before the existing
generation fallback. Gen 1 retains `gen1_faithful`; Gen 2 uses `gen2_finite_pp`;
Gen 3/4 use their existing `gen3_emerald`/`gen4_platinum` defaults. The same
fallback records are present without a mod loader. BW retains its existing
native attach-time override; this change does not redesign Gen-5 rules.

Previously `SaveData.defaultOptions()` inserted `gen1_faithful` into every new
profile, hiding the generation fallback even when the correct later-generation
ruleset was registered. AUTO fixes new profiles and can be stored as a
generation override even when the shared preference names an explicit ruleset.
Options save/reload preserves that override and the other generations' choices.
The cartridge save-import skeleton uses AUTO too, so importing a save does not
reintroduce the fixed Gen-1 preference.

## Existing settings and mods

Every explicit saved ruleset id remains explicit, including `gen1_faithful`,
`modern_clean` and mod-defined ids. Old files cannot reveal whether a literal
Gen-1 id was intentional or copied from the previous default; they are not
silently migrated. Select RULESET -> AUTO to opt an existing installation into
the new defaults, or select `gen2_finite_pp` explicitly. The next constructed
battle uses the preference; an already running battle keeps its chosen rules.
An unknown saved id retains the existing logged fallback to the game's default.

Mod-defined default ids and registered ruleset overrides continue through the
ordinary content registry. No separate per-mod PP switch is added.

## Bounded Gen-2 correction

`gen2_finite_pp` copies the previous host's Gen-1 rule fields and changes only
its name and `enemyUnlimitedPP = false`. This fixes the measured Gold-family
reference/host discrepancy without claiming complete Gen-2 mechanics. Critical
hits, damage, status behavior, Hyper Beam recharge and other rule differences
remain separate work. Gen-1's original built-in record is not mutated.

The existing native move pipeline now spends enemy PP and the existing AI
rejects depleted/disabled slots and chooses Struggle when none remain. A release
of a charged move remains locked even when its first turn spent the final PP;
it spends no additional PP. Called moves retain caller-owned PP accounting.
Unsubscribing or failing a mod entry preserves the native behavior.

## Reproduce

```sh
luajit tests/engine/enemy_pp_defaults.lua
python3 tools/enemy-pp-contract-check/check.py --gen1 /path/to/clean/gen1
python3 tools/charge-required-contract-check/check.py --gen1 /path/to/clean/gen1 \
  --api 3 --format unified --require-native-policy-parity
```

The external Gen1 checkout must be clean at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The unchanged public consumer in
`examples/portable_enemy_pp` forwards native enemy choices and reads current PP
through `mod.battle:snapshot()` on both engines. The Gold/Silver/Crystal harness
uses actual native move execution, AI selection and Struggle execution with
native-shaped data/session fixtures; the snapshot uses a fixture screen on the
reference side. It does not claim a full cartridge playthrough or identical UI.

The charge checker separately compares Red/Blue/Yellow, Gold/Silver/Crystal and
FireRed/Emerald in API 1 native, API 2 native/unified and API 3. Strict native PP
cost equality is required by the new enemy-PP workflow, rather than treating the
former Gold difference as an equivalent observation. Unit checks additionally
cover registered host defaults, no-loader fallbacks, explicit settings,
per-generation persistence, real option-row cycling, no-mod and entry rollback.
