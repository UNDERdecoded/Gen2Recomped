# Native GBA Substitute fade

This controller extends Focus Band presentation. Native damage
queues `SUBSTITUTE_FADE` before the break message and preserves the visible
doll while logical protection is removed. Actual playback executes the native
three-callback alpha decrement, white palette ramp, copied-background lifetime,
script delays and outward/exchange/return swap. The swap shares the previously
qualified controller; it does not maintain a second movement implementation.

The animation runs with battle animations disabled, following the native
general-animation exception. An already hidden doll exchanges immediately.
The native end callback and end-of-sequence visibility reconciliation remain
separate. Same-side double-battle partners retain their copied-background
state while only the acting battler fades. No HP, status, protection or RNG
is changed by playback.

The existing native doll renderer now applies the live palette contribution;
the complete battler wrapper applies its live alpha. Color and blend mode are
restored after drawing. CPU graphics doubles exercise actual drawing methods;
no GPU application or normal save/cache is opened.

Controller evidence:

- **288 paired fade inputs / 23,488 tick states**, every captured field equal
  through the unchanged reference sequencer/VM and actual host battle queue.
  All six single/double positions, animation options, mono/stereo, visible,
  hidden, lowered and absent Substitute states are included.
- Existing Poison/Focus Band **384 inputs / 11,112 ticks**, and existing native
  swap **360 inputs / 5,240 ticks**, remain equal in the same run. All twelve
  workers exit zero without native VM diagnostics or timeouts.
- **104,512 checks** cover the full host fade and real damage producer;
  **70 checks** cover native art import and drawing, including complete-wrapper
  alpha and palette composition.
- Initial incomplete-coordinate and visibility/partner-background failures
  remain retained in `tmp/substitute-fade-qa/`. FireRed uses its native built-in
  picture coordinates; Emerald uses owned data through the virtual cache.
  The corrected fixture explicitly validates each edition's expected input.

The frozen fade runtime completes 162/171 engine suites, SDK 3/3 and B30,
with exactly the same 25 inherited FAIL lines as fresh #258. Its complete
32-worker matrix passes 14,528 paired cases; the later history extension
passes 14,816. Native revision 17 and linked/imported qualification are
documented in `native-gen3-mirror-move.md`. The reference is read-only at
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. CPU state/draw results are not
a final GPU scene-parity claim.
