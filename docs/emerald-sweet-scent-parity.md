# Emerald Sweet Scent encounter audit

Sweet Scent previously selected only regular wild slots and always created an ordinary wild battle. It now checks the Gen 3 roamer first, on eligible land and water, and supplies roaming battle metadata so HP, status, personality and IVs persist. Safari mode is attached to the battle when a Safari game is active.

Sweet Scent also no longer requires a positive walking encounter rate in Gen 3. The native function requires a matching land/water table, then generates the encounter directly. Repel and the walking rate roll are bypassed. Gen 2 keeps its existing positive-rate gate.

The ordinary walking encounter path now permits Emerald's roamer while surfing. Its previous shared land-only gate excluded an encounter supported by Emerald's native water branch. FireRed's existing gate remains unchanged.

Reference: [SweetScentWildEncounter and TryStandardWildEncounter](https://github.com/pret/pokeemerald/blob/master/src/wild_encounter.c). The native function also handles outbreaks, the Battle Pike, the Battle Pyramid, and story-specific Sootopolis water suppression; those branches are not established as complete by this change.

Validation: `python tools/run_lua_check.py tools/emerald_sweet_scent_check.lua` checks regular land/water slots, zero walking rate, Repel preservation, roamer priority and persistent battle metadata, Safari mode, invalid terrain, and Gen 2 isolation. The broader Emerald suites also pass. This harness directly tests Sweet Scent; it does not simulate a complete walking step for the separate surfing-roamer gate.

Sweet Scent now runs a red blend from 0 to 8, holds for 65 frames, and tries the encounter without the inherited Gen 2 used-move dialogue. Failure fades back before displaying the extracted Emerald failure string. The effect sound resolves by its native name in the extracted song table, including when it has no shared engine SFX role. Sequence tests verify the boundary timing, one-shot callback, stack cleanup, and failure restoration.

The red rectangle reconstructs the visual blend; it does not implement the cartridge's palette mask, so the player is tinted as well. Weather/palette restoration and the Mirage Tower pulse interactions are not fully reproduced. No ROM reimport is required for these runtime fixes.
