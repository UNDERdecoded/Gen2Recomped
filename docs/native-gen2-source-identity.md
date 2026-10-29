# Source GSC gene identity API on the older native host

Prepared on offered PR401/current original main8d5b4387, retaining its actual
older RNG constructor and native owners. Source vanillaShiny/isShiny take
the gene table, vanillaGender/gender take definition then genes, and
randomDVs draws four native genes with HP derived at the later source birth
boundary. Native births/reads use those same GSC hook/predicate owners;
no extra Pokemon, simulator or RNG stream is introduced. GBA PID and cached/
forced native identity remain under their existing owners.

The newer c38d06a6 candidate passes262168pure-data/450actual SDK/native checks,
plus its existing identity, appearance, PP and stat groups. These do not
qualify this older combined host. The older host was missing the broader
identity fixtures too; they are ported with all assertions retained. Only
test setup for the absent newer edition-filter service is adapted to the
actual older generation-targeted loader, with no invented ModTargets facade.

The initial complete selected run `e700db57` exposed a real missing prerequisite:
native roll functions existed, but the public capability catalog, unified
callback records and some GBA native producers from offered PR169 were absent.
Their scoped identity payload is now composed with the actual current owners,
retaining native source fields, stat refresh and the new gene signatures.
Unrelated held-item roles from that older patch context are not fabricated.

Corrected source `6cea7865` independently passes all nine selected suites:
262168pure-data,450actual source SDK/native,4976broad native identity,
142ownership/rollback,5290appearance,63transactions,238stat refresh,
6642PP and185360stat-data checks. Receipt:
`native-selected-suites-1793249490611809000/receipt.json`. The original failed
combined receipt is retained. No full-suite/GPU/release qualification is claimed.
The source options-record constructor, remaining Mon and standalone battle/
turn/event APIs, full visuals and final packaged release remain open.

Integration/tests by Roxas2712 are offered under
https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md,
including its specific Cedric / UNDERdecoded permission with visible credit.
Existing authors' rights, provenance, notices and earlier grants remain.
