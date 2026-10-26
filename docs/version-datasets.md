# Read-only version datasets

API-3 mods can inspect another imported Gen1–3 version without importing engine
modules or switching the active game:

```lua
local view, why = mod.datasets:open("gold")
if view then
  local mew = view.content.pokemon:get("MEW")
  for id, species in view.content.pokemon:each() do
    -- Canonical content IDs and detached data records.
  end
end
```

The view contains `version`, `generation`, `content` and `assets`. Registry
handles expose `get`, `has` and sorted `each`; write methods are absent. Core
records use the existing unified content shapes. Function-bearing engine
records are omitted. No live game, save, mod overlays or runtime registration
state is exposed or changed. A view is independent of enabled mods.

`open` returns `nil, "unknown_version"`, `"unsupported_generation"`,
`"not_imported"` or `"invalid_cache"` when appropriate. The host's exact
import format and ROM-hash marker is authoritative; required generated
metadata must be present. A complete developer source can be used without a
marker only with verified source provenance for every required module.
Gen4/5 dataset adapters remain unavailable.

Generated files are parsed as literals, never compiled or executed. Limits
are 8 MiB per module, 48 MiB aggregate, depth 64, 500,000 nodes, 250,000 entries
per table and 2 MiB per string. Arrays, keyed tables, comments, quoted/long
strings and finite numeric literals are accepted; code, operators, duplicate
keys and invalid/nonfinite data are refused. Native record schemas validate
reads. `open` leaves semantic data lazy; engine descriptor shaping may load
additional data roots at first access.

Repeated reads check cached module bytes and rebuild the isolated view after
valid edits. A rejected view stays retired; reopen it after repairing the
cache. Iteration returns a detached, validated snapshot rather than mixing
records from different revisions. Observed content changes, marker changes
and root changes retire outstanding iterators. Merely editing a file does not
mutate an already captured snapshot. Iteration does not re-read every large
generated module for every returned row.

`view.assets:path("assets/generated/...")` returns the host's native virtual
path; `assets:info` returns copied file metadata. Paths reject traversal,
backslashes and control characters. Cache layouts differ between engines:
use the returned path rather than composing a prefix. Gen2Recomped's Red
cache remains at the root. While another edition's overlay is active, a Red
asset path is refused (`nil, "unavailable asset path"`) because that string
would resolve to the active edition. Exact Red metadata and asset info still
use the correct physical cache. Other editions retain explicit prefixes.

Native reads use the already resolved cache root, default save directory or
verified developer source. They never initialize a cache root, mount or
unmount a version, change `CacheFs.prefix`, change `GameVersion`, load a Game,
execute an imported module or rewrite a cache. If root resolution has not run,
only verified developer source is considered. Asset paths are native resource
addresses, not permanent handles to immutable file bytes.

Shared contract fixtures use the same mod on eight versions and both engines,
with each backend's own synthetic cache format. This validates public reads,
mutation isolation, canonical iteration and asset metadata; it does not claim
ROM-content equality or real asset decoding. Local tests additionally cover
parser bounds, stale/malformed caches, repairs, iterator revisions, real
physical file reads beneath a conflicting virtual overlay and the developer
permission tripwire.
