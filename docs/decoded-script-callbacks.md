# Per-mod decoded script callbacks (M5)

The host can select a callback profile without editing a mod's manifest or Lua
files. Native callbacks remain the default. For example, the normal options
record can include:

```lua
modCallbackProfiles = {
  example_mew_starter = "decoded",
}
```

`Loader.new({ callbackProfiles = { example_mew_starter = "decoded" } })` is
an alternative for an embedding host. Select `"native"` or remove the entry to
roll back. The profile applies to Gen 2/3 and requires the mod's native callback
format. Unified callback records remain a separate existing choice.

The selected mod registers `script.command` on a private, loader-owned bus.
Native subscribers retain their existing bus, names, operand arrays, ordering
and context. The original compiled script table remains identical until a mod
actually changes a decoded operation. Compiler provenance and tracing stay in
private side tables; no scratch records are placed in public script rows.
Provenance holds weak source references: retained rows cannot keep a retired
dataset alive, and replaced source pools explicitly retire their old provenance.

The profile presents `(next, ctx, op, row)` for Gen 3 and
`(next, ctx, op, args, cmd)` for Gen 2. Numeric operand slots and the supported
named aliases describe the source operation, before native lowering. A single
source operation may have zero, one or several native rows. `next` runs that
whole native group; code after `next` observes its native effects. Rewriting an
opcode or operand recompiles a private overlay using the same native compiler.
Calls keep their active return addresses. Gen-2 call hooks remain open until
the called subroutine returns, including across native waits. Each loop visit offers the original
source operation again, so a previous rewrite or veto cannot rewrite the
imported source. Vetoes also remove compile-time text state. A retained `next`
cannot replay a completed operation.

Gen-2 numeric `b/w/m` layouts in the stock editions support lossless raw byte
edits. Normalized pointers, rich menu/queue records and hack-specific operand
layouts do not have a lossless raw byte reconstruction here. Use supported
decoded fields; unsupported byte edits fail explicitly. This does not add
missing native opcode implementations or a separate foreign VM. Manually
replaced compiled row lists cannot be paired with stale source provenance and
are explicitly declined by the decoded profile. Hand-authored ordinary runner
lists keep their native callbacks.

`pokemon.before_give` uses its existing event call site once. Only the selected
listener receives a separate view with symbolic species, `speciesId` when the
native species order provides it, and its profile context. Species changes
(including numeric IDs), bounded level changes and nicknames commit to the
native gift. A variable-backed Gen-3 gift also retains the edited species in
that native variable. Existing native listeners receive their original record.
Priorities, unsubscribe, once and failed-entry cleanup use the existing buses.

The current context translation has one explicit map alias: the verified
FireRed/LeafGreen native Oak's Lab definition (group 4, number 3) appears as
`OAKS_LAB`. The definition must belong to that live map registry; conflicting
slot definitions decline translation. Other maps retain their existing IDs.
Shared map objects, storage keys and saves are never renamed. Broader map-name
compatibility is a separate existing integration.

## Qualification

The authenticated, unchanged starter package at pinned reference `535a5ec` runs
through the production Loader, compiler, runner, gift event and Pokémon
constructor over owned synthetic data. Its Gen-3 hook changes variable `0x4002`
to 151 and creates exactly one level-20 Mew named `HOGHEAD`; native map identity
remains `MAP_G04_N03`. This is a runtime contract check, not cartridge gameplay
acceptance. The fixture authentication manifest and mod package bytes are
unchanged.

The focused suite also covers native command order and script identity,
post-next effects, multi-row calls, opcode replacements, return remapping,
zero-row commands, vetoed text state, repeated visits, Gen-2 raw/named operands,
retained callbacks, once/rollback cleanup and native gift record identity.

`tools/check_decoded_profiles.py` runs an owned LÖVE window, the actual Loader
profile and the real ScriptRunner. It compares a pre-change runner, the current
native path and the selected decoded path over 64 writes plus an end per frame,
with 120 warm-up and 120 measured frames per phase. F11 reports
`script.exec (64 writes + end)` and each hook's own time. This deliberately
stresses script dispatch every frame; it does not measure a world/battle scene,
GPU improvements or handheld performance. The enabled translation has a cost;
no general FPS improvement is claimed. See the PR for fingerprinted results.
