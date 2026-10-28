# Native Gen2 model RNG

Expose `rng`, `random` and `roller()` on the live source model, backed by the
existing native controller's current function. LOVE-style ranges normalize
missing/small bounds and reversed ranges; the source random/roller domain is
zero-based for positive integer bounds. Queries consume no randomness and
retained adapters follow native function replacement, including link setup.

The source random field and decorated roller method stay distinct. The native
read-only reader policy remains in effect. Model-owned function caches do not
enter party mons or serialized battlers, and no second generator is created.
Standalone constructor/RNG-injection and complete source-model parity remain
separate work.

Reference: read-only Gen1Recomp Gen2 revision
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, `Battle.new`, its LOVE-style RNG
view and `Battle:roller`. This older host's native model, volatile-state and
protection prerequisites are offered separately. The fork-only semantic
checkpoint backend is absent here, so its checkpoint result is not inherited.

Native integration/tests by Roxas2712, offered to Cedric / UNDERdecoded under
the specific PR contribution permission, with existing rights intact.
Independent validation on this offered host passes 7951 native RNG checks,
174 actual host/guest/spectator source-callback checks, model (262), volatile
(423) and protection-link (66) regressions. A separately executed frozen Gen1
comparison passes 9471 comparisons / 7020 draw cases over actual seeded native
LinkBattle backends; reference hashes remain unchanged. The exact official
whole-host command passes 71/82 engine suites and SDK3/3, with the same eleven
pre-existing failures as its protection base (69/80). It adds two passing suites
without adding a whole-host failure; this older prerequisite stack is not
entirely green. Full model/mod/GPU/release acceptance remains separate.
