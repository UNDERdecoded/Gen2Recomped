# Native GBA AI move knowledge

`Gen3AI` now executes `if_has_move`, `if_doesnt_have_move`,
`if_has_move_with_effect` and `if_doesnt_have_move_with_effect`.
Previously, a reachable occurrence made the whole native script unavailable.
Other unsupported commands continue to reject the complete script.

FireRed reads actual moves, regardless of their remaining PP. Emerald reads
its own moves but uses observed move history for the opposing target. The
ordinary single/double decision entry points learn the target's last used move
before scoring. History preserves insertion order, avoids duplicates, holds
four entries per field position, and belongs to the current party object.
Changing that object invalidates stale knowledge, even before another move
is observed. Other battle history families are preserved.

The operand behavior follows clean Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, including Emerald's asymmetric
partner selectors and its positive effect query's user-slot gate. A missing
or fainted partner skips a positive partner-move branch. MOVE_NONE has effect
zero; a different missing numeric move definition errors. Queries themselves
neither learn moves nor consume RNG.

## Contract checks

The same cases run through the actual Gen1Recomp GBA `AiVm` and Gen2Recomped
`Gen3AI`, with equivalent native session records and engine-specific program
representations. The matrix covers FireRed/Emerald, all four commands and
selectors, numeric and named move records, zero PP, sparse slots, unseen and
duplicate moves, the four-move cap, distinct double slots, missing/fainted
partners, party changes, empty/unknown names, missing definitions and exact RNG non-consumption.
Host entry-point tests also check learning before scoring, resetting on switch
and independent left/right histories.

```sh
luajit tests/engine/gen3_ai_move_knowledge.lua
python3 tools/gen3-ai-move-knowledge-contract-check/check.py --gen1 /path/to/gen1
```

The reference must be clean at the pinned commit. Workers load their respective
engine implementations; no expected query algorithm replaces either VM.
The dedicated workflow retains its comparison report. Tests require no ROM
or graphics runtime.

This change is a bounded AI interpreter/history prerequisite for portable
battle mods. It does not publish the unfinished enemy switch/item hook or
establish complete AI, controller or gameplay parity. Held-item knowledge,
party/status queries and source-side placeholder commands remain separate work.

## Validation record

At clean feature runtime `d871fe0b49f7f2283194e85a73f86865bba0205e`:

- **19,116/19,116** host checks pass.
- Both actual interpreters match in **4 workers / 3,072 paired observations**,
  with zero differences against the clean pinned reference.
- Clean upstream `13af468b97dc37015d14ad5c71d7f067c3ee810d` fails **3,145**
  assertions for FireRed and **3,577** for Emerald; all **1,536 observations**
  per profile differ. The baseline worker reports the missing module/commands
  explicitly rather than substituting an implementation.
- The complete feature run passes **65/75** engine suites, SDK **3/3** and
  B30. Upstream passes **64/74**; all **27 FAIL lines across ten baseline
  suites** match exactly. Workflow lint and new-file formatting pass.

Local evidence is in ignored `tmp/ai-move-knowledge-qa/`: `targeted.log`,
`contracts-final-clean.json`, `full-final.log`, `baseline-final-comparison.json` and
`main-negative-final.json`. Hosted CI is separate from these local results.
No new graphical gameplay or full playthrough result is claimed.
