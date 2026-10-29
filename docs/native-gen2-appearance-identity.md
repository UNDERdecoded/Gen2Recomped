# Native Gen2 appearance identity

The real Gen2 Pokemon constructor now publishes `gender` and `shiny`, including
ordinary births without a hook subscriber. Previously the native predicates
could answer these queries, but unchanged consumers reading the Pokemon fields
directly received nil. This could select a normal model variant for a female.

`opts.dvs` accepts the four finalized native 0–15 DVs for fixed-gene births.
The constructor owns a copy, derives HP DV and spends no discarded random DV
roll. Trainer parties, NPC trades, Odd Eggs and inherited day-care eggs use this
path before appearance hooks run. Definitions and other Pokemon do not share
the mutable gene table. Ordinary native births still use four random DVs.

Save validation fills absent appearance fields on actual known Pokemon after
gene/level validation. Explicit saved values survive loading. Summary/stat
refresh, evolution, hatching, forced-shiny gene changes and companion stat edits
refresh the actual identity. True shininess remains sticky, matching the Gen1
Gen2 refresh contract. Refresh does not change HP, stats, genes, moves or EXP
by itself. Hook context edits retain their existing ownership contract.

`tests/engine/gen2_appearance_identity.lua` covers all seven gender-ratio
classes, DV boundaries and shiny attack classes in Gold, Silver and Crystal;
save codec/validation for party, sparse boxes, day care and contest parties;
fixed trainer genes, Odd Eggs, actual DayCare.step and evolution. `tests/engine/gen2_appearance_transactions.lua` additionally runs the actual
NPC trade script, party picker and movie continuation, plus the real companion
DV/species mutation handlers. Passive panel recalculation preserves identity
and does not dispatch appearance hooks every frame. The existing
identity authority/roll suites cover hook delegation, suppression, forced shiny
and failed callback rollback across generations and API formats.

These are engine behavior checks. They do not certify GPU model loading,
complete menu/battle appearance parity, optional asset availability, or overall
release readiness. No mod changes are needed for this engine contract.

Upstream adaptation: based on the native species/runtime series in PR371. The
existing extra-shiny option remains in the upstream birth path. IdentityRolls
is the exact helper already offered in PR169; this change does not introduce
a second hook contract or advertise unsupported public hook capability.
The native-only regression is independent of that SDK integration.
