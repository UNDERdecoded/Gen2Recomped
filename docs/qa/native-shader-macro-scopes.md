# Native shader macro-local shadows

A shader macro can declare a local variable with the same spelling as a
uniform. Substituting the later local branch with the global uniform value
changes pixels. Track nested macro invocation arguments and preserve their
original native program. Token-pasted identifiers are also unqualified.
The existing conservative treatment of comma declarators remains unchanged.

Qualification:

- The actually offered public component passes CPU contracts:
  branch planner 55, alpha depth 69, sampler guard 16, platform policy 40 and
  the fork canvas adapter 128 is separately checked.
- Real LOVE12 Metal on Apple M3 passes 101 checks, including independent
  reference pixels with a live global uniform and a macro-declared local.
- An owned host with exact earlier planner 7727c172 passes global-zero pixels
  but fails the global-one pixel comparison. The negative fixture keeps the
  current test and native compiler; only the planner is replaced.
- The two actual world-program plans, 98669 and 96404 bytes, retain 16/15 flags
  and 273/266 conditions. Previously qualified rewrite bytes match the prior
  implementation for all-zero, all-one and mixed values. Private shader
  source is retained only in owned QA; it is not published.

This is a pixel-correctness fix, without 60 FPS acceptance. The current real
rainy Third-Person scene still has a measured 3133.971 ms cold compilation
spike and 59.712 ms mean warm frames on the preceding production source.
All 252 fork native CPU groups passed there. This macro change preserves the
actual world-program output; native Metal compilation and 5370 indexed draws
remain performance blockers. Failed broader optimization experiments are
excluded from this offered change. No private mod or player profile is edited.

Contributions by Roxas2712, under LICENSE-ROXAS2712.md. Other authors' existing
licences and rights remain in effect.

Depends on the offered native compiler/depth stack (#337, #388). Current
upstream-main composition and complete release qualification remain open.

The actual offered source fcaecd13 also passes all 101 native Metal checks
(receipt 7f7a699ac9); this is separate from the fork run d01eccac34.
