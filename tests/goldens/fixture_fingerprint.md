# Fixture link fingerprint audit

The previous `7de3051a7b3c108e` pin was already stale at Gen2Recomped's
`0b8c9c4` import: that checkout computes `8c94d595cd60ca69` against its own
ROM-free fixtures. It is not a baseline that current Gen2 data can satisfy.

At upstream `13af468b97dc37015d14ad5c71d7f067c3ee810d`, the same production
serializer and digest compute `41e69caf4afa35ab`. Comparing the canonical
`Fingerprint.surface(data, {})` strings against `0b8c9c4` changes **only**
`move_effects`: commit `3252aec` adds these four full-handler registry records:

- `POWER_BASED_ON_LOW_SPEED` (Gyro Ball)
- `INCREASE_POWER_WITH_MORE_HP` (Wring Out / Crush Grip)
- `DOUBLE_POWER_WHEN_BELOW_HALF` (Brine)
- `DOUBLE_POWER_HEAL_SLEEP` (Wake-Up Slap)

No records were removed or altered in the serialized surface comparison.
The current surface has 198 effect records. Species, moves, type chart,
statuses, constants and mod list are byte-identical to the imported checkout.
An independent Python implementation using integer XOR, multiplication by
16777619 and modulo 2**32 in both lanes also produces the current digest.
No fingerprint algorithm, allowlist, cache or production registry is changed
by this test repair.

`fixture_fingerprint_sections.txt` pins each populated section separately so
future intentional registry additions cannot hide changes in another section.
`gate_fingerprint.lua` retains all prior mutation and determinism assertions,
and additionally proves that removing any of the four Sinnoh registrations
changes compatibility. An empty `link_fields` registry has no serialized
section; a future nonempty one requires a deliberate new section pin.

To audit a future change, load a fresh `tests.modkit` fixture with
`T.sdk.loadNone({data=data})`, compare `Fingerprint.surface(data,{})` section
by section, and then update only reviewed pins. Run the gate again and keep
the mutation assertions enabled. The ROM-dependent vanilla golden is separate
and was not re-blessed by this update.
