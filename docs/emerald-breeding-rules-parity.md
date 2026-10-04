# Emerald breeding inheritance audit

Emerald daycare creation now handles Lax Incense/Wynaut, Sea Incense/Azurill, personality-bit offspring selection for Nidoran♀ and Illumise, Everstone nature inheritance, and Light Ball's Volt Tackle bonus. Either parent's incense or Light Ball counts; Ditto takes precedence over the female parent for Everstone eligibility. Volt Tackle is added after ordinary inherited moves.

The inherited IV routine reproduces Emerald's original loop-index removal quirk, including repeat selections and later assignments overwriting earlier ones. Egg species, moves, ability slot, and stats are rebuilt from the final personality and inherited IVs. Existing move-inheritance category order is retained. Other versions keep their existing behavior.

Reference: [native daycare implementation](https://github.com/pret/pokeemerald/blob/master/src/daycare.c).

`tools/emerald_breeding_rules_check.lua` passes 512 checks, including all 120 stat-selection combinations and production daycare egg creation. The existing breeding suite passes 24 checks, and the broader Emerald checks pass. Exact cartridge RNG streams, pending-egg personality timing, and complete breeding parity are not established. No reimport is required.
