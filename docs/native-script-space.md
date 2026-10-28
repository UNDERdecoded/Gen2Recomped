# Field script observations over native execution

The `src.core.game3.scripting.space` module binds an unchanged consumer to the
actual GBA field runner, numeric command-backed flags/vars and current script
context. It does not load Game, create another world, write a save file or tick
a second field loop. Native map-entry and idle-frame callbacks open scopes;
source wrappers can consume the underlying callback once, or defer it. Native
runner update alone opens the VM tick scope. Extra render/query calls cannot
consume waits, and a wrapper cannot hide a failed native body and retry it.

Map entry temporarily exposes the actual entering world before StateStack has
published it. The scope restores on errors and nested visits. Map/runner/save/
dataset/loader/edition changes retire held VM views. Dataset projections survive
ordinary map changes. Exact owned cancellation uses native lock/fade cleanup
without inventing a trainer result, and declines foreign owners or active UI/
movement that has not finished. Preview replacements suspend live writes; loader
rollback releases only replacements belonging to the failed mod.

Connected-map object observations run the existing compiler and a bounded,
restricted native command pass on detached flags/vars/home templates. They do
not dispatch script hooks or script lifecycle events, borrow live entities, or
invoke UI/audio/IO commands. A loop exhausts the budget rather than blocking
the game. No preview result is committed to the live save.

The import retains opcode/address, raw operand payload/specification and the
original special number alongside normalized native IR. GBA cache markers
automatically require regeneration; player saves are unchanged. Script/event
projections are owned copies. Edited/authored/replaced script lists currently
fail explicitly instead of silently executing an unchanged native list.

## Verification

- `tools/script-space/check.lua`: actual native compiler/runner and loader
  rollback, all five edition identities; phase ordering, duplicate calls,
  waits, retired views, preview isolation, bounded neighbour evaluation,
  command ownership and operand projections.
- `tools/script-space/oracle-host`: actual five-cartridge map/script extraction,
  unchanged normalized IR against the corrected decoder before this metadata,
  raw-byte checks, independent original disassembly and Lua cache round-trip.
  The test reads caller-provided cartridges; none are distributed.
- The oracle visibly corrects reference-table discrepancies for money-window
  commands against the actual read counts in the primary sources linked in
  `native-money-command-layouts.md`. It does not pad missing operands with zeros.

## Remaining integration

This is not complete script API or game acceptance. Rich text/control-code and
canonical movement IR, symbolic label/flag catalogues, an overlay compiler for
authored/edited scripts, arbitrary source VM construction and full immediate/
return-to-field scheduling remain open. The native compiler still has unsupported
command lowerings. Full field services, complete session collections, renderer,
shaders, UI, battle, audio/RTC and all-edition gameplay/coexistence acceptance
remain required. The immutable full Origami package must be probed again after
each concrete bridge; module presence is not a claim that the game runs.
