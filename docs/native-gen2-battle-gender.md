# Native battle HUD gender

The public native battle screen supplies `screen:genderSymbol(mon)`, returning
the male/female symbol or nil when the native identity has no gender. This is
the method exposed by Gen1Recomp's Gen2 battle screen; presentation clients can
reuse it without reading a separately shaped native DV record or requiring a
persisted `mon.gender` field.

The screen delegates to `Pokemon.genderOf(data, mon)`. The existing native
authority owns explicit overrides, cartridge species ratios, Gen2 DVs and the
personality rules of PID editions. Drawing does not stamp gender on a saved
Pokemon, replace the party/model, or add a second identity calculation.

`tests/engine/gen2_battle_gender.lua` exercises actual native battle/Pokemon
constructors across Gold, Silver, Crystal and the supported Gen2 variants,
every Attack-DV value at every cartridge ratio class, both Speed-DV extremes,
explicit overrides, missing identities, unchanged serialized Pokemon bytes,
no extra native RNG draws and the shared class's FireRed PID behavior.
ROM-free checks do not establish real mod/GPU or final-package acceptance.

Reference contract: Gen1Recomp revision
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, native Gen2
`BattleState:genderSymbol`. Existing project notices and contribution licensing
remain applicable. Contributions by Roxas2712.
