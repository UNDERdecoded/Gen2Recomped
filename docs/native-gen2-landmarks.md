# Native GSC landmark records

`mod.content.landmarks` projects semantic records into the native numeric
`field.townMap.landmarks` table. Pokegear, TownMap and the native
`getcurlandmarkname` / `getlandmarkname` script commands read that same table.
It does not create a competing map or name service.

```lua
mod.content.landmarks:patch("LANDMARK_ROUTE_29", {name="CUSTOM ROAD", x=80})
mod.content.landmarks:register("LANDMARK_EXTRA", {
  name="CUSTOM COVE", x=100, y=104, index=200,
})
```

The shape matches the reference: optional `id`, required `name`, `x`, `y`
and `index`. The native map-header index is a byte, including zero.
Coordinates retain the cartridge's hardware OAM units. They are not tile
cells: the existing TownMap marker-centre and Pokegear sprite-origin
corrections still apply once at drawing time. Changing a display name does
not rename the landmark identity.

The import records constant identities and the actual native row indices.
Gold/Silver have95 rows; Crystal has96, including byte95 for the ship. The
previous fixed95-row reader omitted Crystal's last row. Crystal's Battle
Tower also shifts the first Kanto byte from46 to47. Pokegear no longer uses
Crystal's literal boundary for Gold/Silver; both map readers consume
the authored native Pallet landmark index, retaining imported-map-header
fallbacks for older caches. An explicit manifest identity order overrides
the stock order. Unreviewed hack layouts do not acquire guessed stock names.
Stock caches require the `gen2-landmark-identities-v1` revision and reimport.

Valid native names survive a failed/absent map-picture decode without
inventing map artwork. Missing coordinate data is not replaced with guessed
positions. A new indexed authored name can also serve native scripts in a
dataset with no town-map art.

Upstream API1/2 native content uses detached record views. The fork separately
tests API2/3 unified content and its radio helper; those layers are not
imported by this standalone PR.
Failed entries roll back before native projection; content freezes after
loading. Numeric/string native aliases cannot resurrect a removed slot.
Index collisions follow the reference's deterministic rules: the native
identity wins its original slot, otherwise the lexically earlier ID wins.
The reference order remains a fallback for unclaimed original slots after
moving a record. Native map-header bytes are not implicitly rewritten.
Unload restores unchanged owned slots and removes exclusively created
namespaces, preserving external edits. Other generations report this native
target unavailable instead of mutating a similar-looking table.

Validation exercises the real mod loader, ROM reader/text decoder, native VM,
TownMap controller and Pokegear draw commands. Image loading/drawing uses an
authored IO fixture; the independent existing town-map pixel decoder suite
still runs. A private read-only Crystal Rev0 probe reads96 actual records,
compares every raw coordinate pair with an independent byte reader and
executes the ship's authored name through the real VM. The original ROM is
unchanged. This is not fresh GPU, full original-story, Windows hardware,
actual Gold/Silver ROM or complete Gen1 parity acceptance.

Reference behavior: read-only Gen1 source
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`, `Schemas.landmarks` and
`core/gen2/Nests.lua`. Constant identities and order were checked against
[pokegold landmark constants](https://github.com/pret/pokegold/blob/master/constants/landmark_constants.asm)
and [pokecrystal landmark constants](https://github.com/pret/pokecrystal/blob/master/constants/landmark_constants.asm).
Only compatibility identifiers/order and original adapter logic are included;
no cartridge coordinates, dialogue, graphics or private mod content is shipped.
Original contributions by Roxas2712; retain existing engine/third-party rights
and credits. The [specific permission for Cedric / UNDERdecoded, with visible
credit](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md)
applies to offered contributions; it does not license cartridge data or
other authors' work.
