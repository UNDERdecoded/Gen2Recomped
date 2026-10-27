# Compatibility terrain semantics

`src.compat.gen1.MetatileBehavior` and `CollisionClass` translate terrain
semantics for compatibility views without changing native maps or gameplay.
They are independently implemented building blocks for the active-map bridge,
not a replacement field runtime or a completed mod loader.

Behavior bytes differ across cartridges. For example Hoenn byte 17 describes
interior deep water, while Kanto byte 17 describes fast water. The semantic
namespace preserves shared names, renamed names, Hoenn-only IDs and unmapped
Ruby/Sapphire bytes. Conversion always selects an explicit edition. Metadata
comes from the clean public reference at
`37a49b31f458d51ea9e00b90f2a247272ad09cb8`; regenerate it with
`tools/metatile-compat/export.lua`. Only public interface identifiers and
conversion metadata are included, not ROM assets or runtime source copies.

`CollisionClass.impl("frlg"|"rse")` provides `classify`, `seed`, and `fromCell`.
Their classified collision bytes are different from the native two-bit GBA
blocking field. Behavior dispatch rows are built once; classification allocates
no cell tables. Hoenn's surfability flags are borrowed live from the caller via
`setTileBits`, including later mutations and retirement. Missing flags do not
invent water classification. Indoor doorway facing, directional ledges,
secondary-metatile categories, nil collision semantics and original category
precedence are preserved. Native Gen2 collision is unaffected.

Run the same input stream against both implementations:

```sh
python3 tools/metatile-compat/check.py --reference /path/to/clean/reference --lua luajit
luajit tests/engine/compatibility_cell_semantics.lua
```

The oracle check compares all public names, reverse names, all five cartridge
conversions, unknown and fractional inputs, all 10-bit metatile IDs, collision
bit patterns plus nil, all semantic IDs at terrain boundaries, map kinds,
category/direction seeding, and every live surfability flag value 0–7. It
compares 517,218 result tuples per host using two independent rolling digests;
metadata regeneration must also be byte-identical. The focused suite checks
807 expectations, including semantic counterexamples and snapshot isolation.
`benchmark.lua reference|native` is an optional CPU microbenchmark, not an FPS
or gameplay acceptance test.

## Integration still required

These modules deliberately have their own namespace. They do not claim the
entire old `game3.mb` or importer contract, including ROM symbol resolution and
tile-flag extraction. The internal `MapViews` backend now observes the native session and live grid
revisions through source metadata supplied by #246. It requires the companion
identity/layout contributions #239/#240; see `native-map-observations.md` for
explicit integration tests. `CollisionClass.new(family, bits)` gives each view
its own flag state without replacing `impl` singleton state. Script writes,
atlas ownership and the complete map/Game3 facade still require integration.
Stale normalized-only caches cannot establish source bytes. Full compatibility
remains open.

Blattgrün, Rubin and Saphir are included in the explicit cartridge scope.
Their existing upstream contributions are #183, #186 and #187; US Rev 0 support
and separate cache/save namespaces do not imply full story or mobile coverage.

In seven alternating fresh-process CPU measurements of 1,048,576 calls per
family on macOS LuaJIT, Kanto median time was 0.067380 s for the reference and
0.045807 s for this implementation; Hoenn was 0.035833 s versus 0.026162 s.
Checksums agree. A separate mixed-family process run was slower for Hoenn
(0.097837 s reference versus 0.194992 s candidate), so these numbers establish
no general performance win or frame-rate improvement. Keep both workloads
when integrating with long-lived sessions. Native gameplay does not call these
new helpers yet.
