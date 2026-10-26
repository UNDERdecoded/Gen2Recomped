# Native GSC PC/mail core

The legacy Gen2 Mail module is absent and the Boxes alias has an incompatible
count contract. Native gift/delivery scripts are stubs; Gold/Silver mail
operands consume three bytes instead of two.

Add native slot-indexed party letters, ten-entry mailbox operations and a
14x20 PC facade over the existing save tables. Mail follows team removal
and reordering APIs, held letters block deposit/ordinary item replacement,
and last-healthy restrictions use the actual native HP/stats. Save
validation retains detached letters from quarantined carriers.

Raw ROM mail is decoded separately from dialogue and queued scripts. The
actual ScriptRunner gives letters and yields to the real party menu for all
five delivery outcomes. mail.read emits once per opening; mail.written
identifies compose/script. Item recognition uses imported semantic keys.
The primary pointer contracts are in pret/pokegold and pret/pokecrystal,
engine/overworld/scripting.asm (Script_givepokemail/Script_checkpokemail).

Validation: 208 PC/mail/codec checks and 69 binary ROM/actual runner/public
SDK checks pass. The current upstream baseline also has existing suite
failures; comparative engine/SDK results are recorded in the PR.

This standalone core contribution does not import the fork's separate UI,
capability facade, qualified runtime or packaged acceptance. Composition,
mailbox screens, SRAM conversion, stationery artwork and complete parity
are not claimed here. No private mod, ROM or generated artwork is included.
