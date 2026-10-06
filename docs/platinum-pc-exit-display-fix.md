# Platinum storage exit and Pokémon Center displays

The PC's `exit` method both popped the screen and notified its caller. `StateStack:pop` invokes `exit` as a lifecycle hook, so pressing B popped twice: first storage, then the fade beneath it. The field retained that detached fade and the common storage script subsequently parked at `g4_fade` row 665 waiting for an overlay that was no longer updated. `close` now performs the pop; `exit` only sends its notification, once.

PC monitor on/off animations (members 41/42), the alternate PC display (31), and the healing monitor (32) are marked deferred in the ROM's `bm_anime_list` records. They are now excluded from ambient looping and remain live for interaction effects. The healing monitor's animation is available while healing balls are active, then stops when healing ends. Ambient prop animations retain their existing path.

Validation: `tools/gen4_pc_exit_check.lua` passes 52 checks with the actual state stack, storage B-button handling, script storage command, and both fades in all four modes. Native deferred flags and idle/healing/ambient rendering selections are checked. The storage suite passes 22 checks and the full ROM/cache prop animation suite passes 544 with no skips. No reimport is needed.
