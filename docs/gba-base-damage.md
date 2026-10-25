# Ordinary GBA base-damage contract

The shared damage calculator still applied earlier generations' base-damage
steps to the GBA profile. This could quarter wide stats, cap a large base at
997, halve the attack stat for burn, and apply weather after the final +2.
These steps produce different GBA results at rounding boundaries.

The GBA profile now selects `baseDamageStyle = "gba"`. It uses wide stats
without the older base cap and applies burn, screens, spread and weather to
the truncated base before +2. Its physical zero base becomes one; the special
base can remain zero. Solar Beam's bad-weather penalty follows the weather
type modifier, and weather does not apply the older minimum-one clamp.
Profiles without this opt-in retain their existing calculations.

For example, at level 1 with power 2, equal stats and STAB, an ordinary
physical move deals 4 damage at roll 100 rather than 3. At level 30, Fire
power 35, equal stats, STAB and rain, the base produces 9 damage rather than
7. These are noncritical calculations; critical/type rounding is addressed
separately by PR #175.

## Shared calculator checks

The same case file invokes Gen1Recomp's actual GBA `Damage.calc` and
Gen2Recomped's actual `Damage.compute`. It uses equal typed session stats,
move records, status/screen/weather flags and pinned noncritical rolls. No
copy of either damage formula supplies the expected result.

The matrix covers FireRed and Emerald, 18 contexts, six levels, four powers,
four Attack/Defense pairs and rolls 85/100: **4 workers / 6,912 paired numeric
observations**. Contexts include STAB, no STAB, burn, single/double screens,
spread with screens, resistance, immunity, rain/sun, and Solar Beam in rain,
sand and hail. Both calculators preserve the supplied Pokemon HP.
Six additional host checks preserve the older profiles' minimum base,
paired stat scaling and base cap. The host suite has **20,742 checks**.

```sh
luajit tests/engine/gba_damage_base.lua
python3 tools/gba-damage-base-contract-check/check.py --gen1 /path/to/gen1
```

The reference must be clean at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Each worker loads its own actual
engine modules. The workflow retains its comparison report. No ROM or
cartridge-derived assets are needed or included.

This contract covers ordinary noncritical base damage with the listed
inputs. It does not establish every move effect, ability, held-item rule,
critical rule, ordinary turn/controller, or a full graphical playthrough.
The unfinished enemy switch/item hook and AI simulation wiring are outside
this PR.
