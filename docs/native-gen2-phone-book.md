# Native ordered phone book

The native script verbs and Pokegear now share ten ordered phone slots.
The existing `save.g2Phone` registration set stays available; the additive
`g2PhoneSlots` array retains insertion order and script-deletion holes.
Older sets receive deterministic initial order. External set edits are
adopted without resurrecting deletions or renumbering contact IDs. Reads do
not discard overflow entries from historical oversized sets.

Missing permanent numbers reserve slots, so eight ordinary contacts cannot
lock out Mom and Elm. Their imported non-trainer identities are authoritative;
explicit metadata and relocated rows take precedence over legacy retail
positions. The number being added never reserves against itself. Duplicate,
zero, unknown imported and full-book additions are refused. Native
checkcellnum retains the cartridge's empty-byte membership behavior.

Script deletion leaves a hole. Pokegear DELETE compacts the actual slots,
while the incoming selector walks registration order. The native card shows
ten slots, uses explicit blank rows instead of invented Mom/Elm entries,
refuses calls on blanks and scrolls slots nine and ten into view.

Validation:277 focused synthetic checks use actual Gen2ScriptVM/ScriptRunner
add/check/delete/ask opcodes, Pokegear input and drawing with only prompt,
audio and graphics IO substituted. Gold/Silver/Crystal exercise reservations,
ordering, external edits, slot deletion, empty rows, native ask result codes,
relocated permanent identities and visible slot-ten dispatch. This establishes
model/VM/UI behavior, not a hardware phone call or original story acceptance.
The existing content-bridge tests also check ten-slot native consumption.

The display hook is covered separately in [native-gen2-phone-list-hook.md](native-gen2-phone-list-hook.md).
The public legacy Phone facade, full special call/rematch contracts, new authored phone scripts/forward references, and
fresh-import/GPU/story acceptance remain open. Full Gen1 parity is unproven.

Original implementation by Roxas2712; existing upstream/third-party rights and
credits remain applicable. See the [specific PR contribution permission and credits](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md).
