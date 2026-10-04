# Emerald party HP transfer

Softboiled and Milk Drink were offered by the extracted party action table but had no dispatcher. Both now enter a recipient picker in the existing Emerald party screen. Setup requires donor HP strictly greater than floor(max HP / 5). A successful transfer subtracts that full amount from the donor and restores up to that amount to the recipient, capped at max HP, without spending PP.

The donor's HP bar drains before the recipient's bar fills. The shared party animation now supports decreases as well as increases. The donor remains highlighted alongside the selected recipient, and the bottom prompt uses the extracted "Use on which POKéMON?" message. Invalid self, fainted, or fully healed targets retain recipient selection. B and the Cancel panel abandon selection while keeping the party screen open. Completion uses the ROM's HP-restored message and reports the actual gain.

Reference: [fldeff_softboiled.c](https://github.com/pret/pokeemerald/blob/master/src/fldeff_softboiled.c). The native item-use sound role is played for both the drain and restoration stages.

`python tools/run_lua_check.py tools/emerald_hp_transfer_check.lua` verifies both moves, rounding, threshold boundaries, capped restoration, animation order/completion, PP preservation, refusals, cancellation, and sound dispatch. Visual timing and device rendering are not yet checked against emulator footage. No ROM reimport is required.

Sweet Scent was also inspected against the Emerald reference; its setup has no weather refusal, so no weather restriction was introduced. Its cartridge palette effect and some encounter branches remain future work.
