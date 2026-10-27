# Native GSC PC and mail menus

This is the menu layer for the native PC/mail core offered in PR #264.
It also uses the caller-owned native Gen2 keyboard adapter offered in
PR #135. Those prerequisite changes are included in this branch for an
executable comparison; the new menu commit is separate from them.

Native bag/party actions open the 32-character, two-line composition
keyboard. Cancelling consumes no stationery; acceptance commits the real
inventory exchange and party-slot letter together. Existing held mail
opens READ/TAKE choices; message destruction requires a default-No choice.
The player PC opens the real mailbox, which attaches the selected letter
through the native party picker and keeps dense row identities after removal.

Bill's PC uses native GSC deposit/withdraw/release guards and exposes its
actual save for existing Gen2 host adapters. Legacy callers owning dismissal
receive their close callback while the PC is still on the stack; native
callers retain pop-before-callback behavior. Alternate-save menus do not
write the live profile. Summary/dex entry IDs route to existing native screens.
Party reorders move slot-indexed letters alongside their carriers. Native
quarantine UI reports retained/recovered letters instead of hiding repairs.

Focused comparison: 208 core/codec checks, 69 bytecode/runner/SDK checks,
61 naming-adapter checks and 50 menu/inventory/codec/SDK checks pass. The new
menu suite drives actual production keyboard/menu input, failed/stale/cancelled
transactions, mailbox compaction, player-PC admission, caller-owned PC closing,
alternate saves and missing-carrier recovery. Synthetic fixtures only.

The fork separately has source-bound unchanged-Johto/Crystal GPU evidence.
That evidence does not qualify this different upstream composition. Full
stationery art, SRAM mail conversion, every legacy PC mode, complete VASC
compatibility and real hardware/story acceptance are not claimed here.
No private mod code/assets, cartridge bytes, generated art or saves are included.
