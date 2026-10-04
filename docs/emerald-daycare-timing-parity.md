# Emerald daycare production timing

Egg production uses the second resident's step count at low-byte phase 255, then every 256 steps. Deposits no longer restart a separate production clock. The compatibility check uses a 16-bit draw, integer division by 65535, and a strict comparison against the native 20/50/70 tiers.

Withdrawing the first resident shifts the second into its place with its earned steps intact. Withdrawal and subsequent deposits retain the waiting egg. Gen2 keeps its separate pen identities and clears its waiting egg on withdrawal.

Reference: [Emerald daycare source](https://github.com/pret/pokeemerald/blob/master/src/daycare.c), particularly `TryProduceOrHatchEgg`, `ShiftDaycareSlots`, and `TakePokemonFromDaycare`.

`tools/emerald_daycare_timing_check.lua` passes 327 checks using extracted Emerald species, native RNG boundaries, and attendant withdrawal/collection specials. Inheritance, hatch-cycle, and Gen2 daycare checks also pass: 5,179 checks total. No reimport is required. Full cartridge RNG timing and delaying inherited egg properties until collection remain unfinished; this change preserves the engine's existing pending-egg representation.
