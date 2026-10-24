# Native GBA AI Taunt predicates

The native AI importer already decodes `if_target_taunted` and
`if_target_not_taunted`, but the host did not implement them. Reachable scripts
containing either command were therefore unavailable. Both predicates now
read the live target's `tauntTurns`; they do not read the user or its partner,
change the timer, or consume RNG. Other unsupported commands remain gated.

GBA Taunt now sets two residual ticks, matching the native `Cmd_settaunt` and
Gen1Recomp's owned effect. A repeated effect does not refresh the timer, and
an explicitly cleared zero counter permits application, and it can be applied again after expiration. Existing non-GBA duration behavior
is preserved.

The shared case file runs real equivalent AI programs through each engine's
VM. It checks both predicate directions, missing/zero/live timers, distinct
single/double targets and unchanged query state/RNG. It also calls each
engine's real owned Taunt effect and residual implementation to verify the
same 2 -> 1 -> expired lifetime, repeat refusal and reapplication. The source
uses its actual residual scheduler and adapter; only ROM text presentation is
replaced. This effect-stage fixture does not establish move-selection,
accuracy, animation or full gameplay parity.

Gen1Recomp's old predicates always treated the target as not taunted. The
paired source fix replaces those placeholders. Cross-engine checks require
the clean, explicitly pinned fixed reference documented below; they do not
claim agreement with the old placeholder implementation.

```sh
luajit tests/engine/gen3_ai_taunt.lua
python3 tools/gen3-ai-taunt-contract-check/check.py --gen1 /path/to/fixed/gen1
```

No ROM, generated cartridge assets or graphical process is required.

The fixed Gen1 reference is
`Roxas2712/gen1recomp-Mac-fix@10613015fc68d924915570bd1abee34b70d5bd01`,
based on upstream dev `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Its only
production changes replace the two AI predicate placeholders. The workflow
checks out this explicit counterpart; it is not an upstream merge claim.

## Validation record

At feature runtime `58a8f548a155973aae8de0307e6ad259f3ebf03c`:

- **567/567** checks pass, including non-GBA duration retention.
- The actual interpreters match in **4 workers / 96 paired observations**.
- Upstream Gen1 dev fails **56** assertions and differs in **28** observations
  per profile. Upstream Gen2 main fails **196** assertions and differs in all
  **48** observations per profile.
- The full feature run passes **65/75** engine suites, SDK **3/3** and B30.
  All **27 FAIL lines across ten upstream suites** match clean main exactly.
  Workflow lint and shared-test formatting pass.

Local reports are in ignored `tmp/ai-taunt-qa/` and external
`tmp/ai-taunt-paired-qa/`. The two fixed source commits used for these local
comparisons differ only by the source validation document; the final clean
comparison report pins the exact source head above. Hosted CI and upstream
review are separate from these local results. No new graphical run is claimed.
