# Native Gen-3 constrained party creation

Teachy TV previously called the ordinary random-mon builder with midpoint IVs,
then overwrote its nature and gender. That left a PID inconsistent with its
stored identity and passed the nature into the wrong `Stats.calc` argument.
Hard-coded English species/move keys also failed against native-index or
translated registries.

The private `Gen3ConstrainedMon` builder now follows the unchanged Gen1 native
`Pokedude.build` creation path. It consumes low/high 16-bit PID words until the
requested native nature and gender match, with `gender.roll` evaluated only for
nature-matching candidates. It creates zero IVs/EVs, native nature-adjusted
stats, full HP/PP, the PID-selected ability, experience, friendship and the
native Poke Ball. It does not invoke generic encounter generation, random
IV/DV generation or the shiny-odds roll. No new public API is introduced.

Species, moves, nature and ball use cartridge order maps, falling back to
explicit native indices. Missing or ambiguous rows fail explicitly. All party
members are created before taking ownership of the player's actual party;
normal restoration keeps its original reference and contents. Catching retains
its already-correct move order `{93, 77, 79, 78}`.

This change composes the critical-context work in PR #212 and the published
identity hooks in PR #169. Gen1 remains a clean, read-only reference at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.

## Reproduce

Run `luajit tests/engine/gen3_constrained_party.lua`, or the full ROM-free
`scripts/test.sh --quick`. The enemy-action checker now also runs the shared
`tests/enemy_actions/constrained_party.lua`:

```sh
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference \
  --lua /path/to/pinned/luajit \
  --report /tmp/enemy-action-report.json
```

The maintained LuaJIT source pin is
`a4c064539ea931274d407e1249b4bb575424a0f4`, as in the existing dedicated workflow.
The fixture runs all four native presets, three seeds, three registry layouts
(canonical, raw native IDs without order maps, translated names/keys) and five
public gender policies (absent, delegation, first-candidate rejection, invalid
result fallback, call-local threshold steering). It compares the actual created
fields, every consumed word, final input-stream state and public gender callback
order, rather than overwriting generated stats afterward.

The source executes its original LCRNG; a pass-through observer records its
actual output. The host receives an independently generated equivalent word
stream through the constructor's private RNG argument. Observations normalize
only engine schema differences: registry IDs, stat/IV/EV field names, native
gender codes and growth-curve IDs. Every observation is retained by the checker.
Host-only assertions also cover party restoration, incomplete opposing data,
the default word source and absence of a shiny callback during private creation.

## Scope

There are 180 paired presets per GBA data profile. The existing comparison
matrix remains intact: 56 worker runs compare 5,574 paired observations. Emerald
runs prove the shared Gen-3 builder contract with Emerald data; the retail
Teachy-TV entry point is FireRed-specific. These ROM-free tests do not certify
live UI playback or a complete retail tutorial playthrough.

Global game RNG/VBlank scheduling and the subsequent demo controller's existing
midpoint battle RNG are still separate gaps. This constructor-level comparison
does not claim to close them. The move-effects protocol and fingerprint are
unchanged.
