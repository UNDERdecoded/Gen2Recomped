# Native companion terrain observations

Contributions by Roxas2712 — <https://github.com/Roxas2712>.
Existing upstream rights and notices remain applicable to the shared native machinery.

The GBA source namespace now reads grass, next elevation and ledge landing
from the native map owner. Elevation zero remains a real height; bridge
markers preserve the incoming height. Native movement and source queries
share the same transition and ledge classifier. Dataset overrides, older
standing-cell ledges, later-edition jump distances and callback arity remain
native. Queries never move actors, execute movement hooks or trigger warps.

`src.core.game3.encounters` provides `ensureLoaded`, `terrainAt` and `tableFor`
(`table_for` alias). Tables expose detached land/water/rocks/fishing areas,
with cartridge species indices and source level-range field names. Map
aliases resolve through the checked native map binding. Native header and
script-variable changes are visible on the next query; unknown species or
retired maps are refused instead of silently substituting another monster.
Altering Cave header selection is shared with native encounter generation.
These reads do not consume RNG or install another import cache.

This is a partial interface. Encounter rolling, encounter identity transfer
into battles, companion actor collection, follower commands and UI hooks
still need their own integrations. No complete companion or presentation
capability version is advertised, and unchanged Origami 1.0.9 initialization
is not yet expected to succeed.

Validation uses synthetic native owners for all five GBA editions, actual
native hop dispatch, height/bridge transitions, cave/underwater terrain,
sparse species indices, alternate headers, retired bindings, detached
records and real SDK failure/teardown alongside a native peer.
