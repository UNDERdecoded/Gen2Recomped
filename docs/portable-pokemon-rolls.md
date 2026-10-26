# Portable Pokemon identity hooks

`shiny.roll` and `gender.roll` wrap the native Gen-2/3 identity predicates.
API 3 supplies common species IDs and definition records; native API 1/2
retain native IDs. Host API-2/unified is also supported. GB and DS report
both hooks unavailable through `mod:supports("hooks", name)`.

```lua
local mod = ...
if mod:supports("hooks", "shiny.roll") then
  mod.hooks:wrap("shiny.roll", function(next, ctx)
    if ctx.species == "CHARMANDER" then return true end
    return next(ctx)
  end)
end
```

Both contexts carry `species` and `def`. Gen 2 carries the native `dvs`
(`attack`, `defense`, `speed`, `special`, derived `hp`) and construction/
refresh `level`. Its bare breeding gender query has no level. Gen 3 carries
`personality`; shiny queries also carry `level`, `ivs`, `otId` (or the native
trainer-ID fallback) and optional `otSecretId`. The native unhooked GBA
reader also handles split secret IDs and the `trainerId` alias; installing a
delegating hook is not required for those explicit identity layouts. Unified GBA IV keys follow
the reference: `hp`, `atk`, `def`, `spe`, `spa`, `spd`. IVs are a detached
query copy, so editing them does not edit the Pokemon.

The gender context includes the informational ratio byte. To steer the
native threshold, edit `ctx.def.genderRatio` and delegate, or return a gender
directly. Changing `ctx.ratio` alone does not replace the definition's byte.
Gen-2 definition steering has the reference's live-definition scope; Gen-3
metadata is call-local. Other unified definition metadata is read-only.

Shiny results use Lua truthiness (including truthy zero); nil means false.
Gender returns `male`, `female` or `unknown`. Invalid gender returns fall
back to the native predicate. Gen 2 re-reads its current DV/definition state;
Gen 3 retains the native value captured before its hook. Its PID low byte
and the Gen-2 two-DV-byte comparison keep their native boundary rules.

Gen 2 stores the construction results on the Pokemon. Its native summary
refresh re-evaluates gender and a false shiny result, while an already true
shiny remains true, matching the reference. Gen 3 evaluates gender at birth
and retains the native display cache; breeding/query reads remain separate
live evaluations. Unsubscribing stops callbacks but does not erase a native
cached value. Explicit cartridge-forced shininess bypasses the normal shiny
hook, including the native forced-wild construction path.

Plain result overrides and Gen-3 queries do not change DV/PID/IV values or
draw RNG. Deliberate Gen-2 DV edits retain native write-back semantics; API-3
replacement contexts/DV records retain the original native table identity.
Do not treat these mutation cases as pure read-only predicates. Unified
callback writes are committed through the existing call-local transaction;
pre-next failure and invalid threshold writes cannot partially edit the
engine. Retained views and late `next` calls cannot edit native state later.

See `examples/portable_pokemon_rolls` and
`tools/pokemon-roll-contract-check/`. The shared tests use both real SDKs,
Gen-2 constructors/refresh/breeding and native GBA party creation/predicates.
They compare every outcome in the 65,536-case Gen-2 ratio/DV matrix rather
than relying only on an aggregate checksum. This is a native hook contract,
not a claim that every screen recomputes cached identity at the same time or
that all battle and save-format differences are resolved.
