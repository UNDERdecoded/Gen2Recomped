# Native object and connected-map views

`src.core.game3.objects` observes the live native GBA NPC pool. Importing it
does not create a Game, a world, an NPC, a texture or a second update loop.
`src.core.game3.ghosts` observes the native connected-map pools in map-local
coordinates; the consumer applies each connection placement exactly once.

The imported object `index` is its preserved cartridge local ID. Canonical
map names resolve through the checked group/number binding, including when
native storage uses different map keys. The current and connected maps may
contain the same local ID without sharing an actor view. Invalid map names
cannot fall back to current-map objects. Conflicting live local IDs decline
the pool rather than publishing an ambiguous identity.

Views have stable identities within a native cohort and expose live position,
movement, elevation, facing, step phase, visibility and actual resolved sprite
row. Their template and nested script data are owned copies. Extension fields
stay on the view; source code never receives a native actor or sprite resource.
The native pose rules supply jump lift on an observational copy. Queries do not
advance animation, NPC AI, script moves, playtime or the game RNG.

Writes are limited to validated native visibility, facing, freeze state,
passability, horizontal presentation offset and in-range fixed-frame commands.
Movement-type changes and facing the player use the native NPC methods.
Position, movement state, elevation and raw graphics identity writes decline:
those changes need the actual native map/movement/script command owners.
View clearing retires observations only; it never deletes the native cast.

An observed removal or a map, player, world, save, dataset, map-registry,
loader or edition replacement irreversibly retires an old handle. Reload/exit
retires the facade through the existing compatibility teardown, after wrapper
unwind. New observations can adopt the still-live native cast.

## Validation

`tools/object-runtime/check.lua` uses the real native NPC class and updater
with synthetic field metadata across FireRed, LeafGreen, Emerald, Ruby and
Sapphire. It checks live movement observations, native pose rules, connected
map identities/offsets, typed commands, detached records and cohort retirement.
It does not import cartridges or use player profiles.

## Remaining actor contracts

This is not complete actor compatibility or gameplay acceptance. Runtime
spawning/removal, script movement streams/tracks, virtual/network actors,
subpriority/fade/figure-eight commands, foreign carry/snapshots, template
visibility persistence and prefetch/adoption protocols remain to be connected
to their native owners. Source collision wrappers are not yet called by native
NPC AI or trainer sight. Sprite pixel/frame/anchor resources and special berry,
disguise and multipart poses still require the separate sprite interface.
`Objects.loadMap` can observe only the already active native map, and cannot
load or instantiate another map. No unchanged renderer or GPU acceptance is
claimed by this read-side interface.
