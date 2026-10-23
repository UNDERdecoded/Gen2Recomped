# Gen1Recomp Gen-2 naming screen compatibility

API-2 mods may open `mod.ui.push(game, "Gen2NamingScreen", opts)`, the public
screen ID used by Anytime Rename 1.2.1. The adapter uses Gen2Recomped's native
keyboard and supports `type` (player, rival, mom, box, nickname), `prompt`,
`maxLength`, `initial`, `mon`, `monName` and `onDone(name)`.

The completion callback owns closing this screen. It runs while the naming
state is still on the stack; a caller may pop it and return to its existing
parent menu. The ordinary `NamingScreen` API remains different: it pops itself
before calling `onDone`. Mapping the ID directly to that class would pop two
states when an existing Gen1Recomp mod closes its own screen.

`text` reflects the editable name and may also be assigned. Initial values and
assignments are limited by glyph count, preserving UTF-8 and charmap tokens.
The adapter keeps the native keyboard's input, drawing and `ui.naming.grid`
hook; it does not reproduce Gen1Recomp's separate Gen-2 keyboard layout or
change native game save fields. Mods should use the native naming screen for
their target host when they do not need this compatibility contract.

Regression coverage: `tests/engine/gen2_mod_naming.lua`. External verification
uses the unchanged Anytime Rename 1.2.1 entry point and its 55-check suite;
its native-menu flow suite additionally runs six games in two languages.
