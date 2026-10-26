# Native GBA AI random-branch contract

The native AI bytecode's four random comparisons consume `rng(0, 65535)`
and compare the result modulo 256 with the script's byte operand.
`if_random_less_than` and `if_random_greater_than` previously drew only
0–255, changing deterministic RNG behavior. `if_random_equal` and
`if_random_not_equal` were absent, causing the host's whole-script capability
gate to skip any reachable script using them.

All four operators now use the native draw range and byte comparison. The
existing whole-script gate still refuses other unsupported instructions.
This change does not add the unfinished public enemy switch/item hook.

## Shared interpreter checks

`tests/gen3_ai_random/cases.lua` runs equal conditional/score/call/end programs
through Gen1Recomp's actual GBA `AiVm` and Gen2Recomped's actual `Gen3AI`.
No copied interpreter or stubbed score handler supplies the result. Each
program scores two moves with consecutive RNG values, checking both branch
effects and complete RNG ranges/order. The matrix covers FireRed and Emerald,
all four comparisons, operands 0/128/255, and ten raw values from 0 to 65535,
including equal low bytes with different high bytes.

Run the ROM-free engine checks and cross-engine comparison with:

```sh
luajit tests/engine/gen3_ai_random.lua
python3 tools/gen3-ai-random-contract-check/check.py --gen1 /path/to/gen1
```

The reference checkout must be clean at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Workers run from their respective
engine directories; the same case file drives both. The dedicated workflow
retains its JSON comparison report.

These checks prove native interpreter branch behavior. They do not claim
complete AI opcode coverage, identical damage estimates, full ordinary
opponent-controller RNG setup, or a portable public battle-hook contract.

## Optional native cartridge checks

To reproduce the bounded native-import comparison locally, supply your own
English Emerald ROM matching both engines' manifests:

```sh
python3 tools/gen3-ai-random-contract-check/check.py --gen1 /path/to/gen1 \
  --emerald-rom /path/to/emerald.gba --report /tmp/gen3-ai-random.json
```

The checker validates the ROM hash before starting either worker. Both native
AI importers read that same cartridge into memory. Each real interpreter
runs imported subroutines whose reachable instructions consist entirely of
random comparisons, score changes and control flow. Ten raw RNG values probe
each common entry, including byte-boundary and high-byte changes. No synthetic
instruction replaces the imported code. No normal cache, save or generated
cartridge asset is written.

The report explicitly lists unpaired entry offsets: the importers split
bodies at different boundaries. A reference-only entry fails the check;
additional host entries are reported separately and are not counted as
paired evidence. The current supported ROM yields 39 common subroutines /
390 paired observations, plus 42 host-only entries. This is an interpreter
subroutine check, not a complete trainer decision or graphical gameplay test.
The workflow runs the ROM-free matrix only.

## Validation record

At clean feature runtime `40ec724aaeb65ea470d2503af86edcf0d1c6c31e`:

- The host checks pass **1,920/1,920**. The ROM-free cross-engine matrix passes
  **4 workers / 240 paired observations**, with zero differences.
- Both native Emerald AI-stage imports pass **39 common subroutines / 390
  paired observations**, with zero differences and no missing reference entry.
  The 42 additional host entries remain explicitly unpaired.
- Clean upstream `13af468b97dc37015d14ad5c71d7f067c3ee810d` fails **631
  assertions per GBA profile** on the new matrix. On the same native Emerald
  subroutines it differs in all 390 RNG traces and in 41 resulting scores.
- The complete feature run passes **65/75** engine suites, **3/3** SDK suites
  and B30. Upstream passes **64/74**; the **27 FAIL lines across ten suites**
  match exactly. There are no new baseline failures.
- Workflow lint and formatting checks for the new Lua files pass. A wrong ROM
  is rejected by the hash gate before either import worker starts.

Local evidence is in the ignored `tmp/gen3-ai-random-qa/` directory:
`full-final.log`, `main-baseline-full.log`, `contracts-final.json`,
`native-final.json`, `main-parent-negative.json` and
`main-native-parent-differences.json`. Hosted workflow results are separate
from this local record. No new LÖVE gameplay run is claimed.
