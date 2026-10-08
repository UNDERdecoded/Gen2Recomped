# October 7 regression fixes

Polished Crystal 3.2.3 now has 86 complete building pattern variants. The
profile includes Goldenrod's modern roof bands and large buildings, Celadon's
department store and civic blocks, Center/Mart roofs, Radio Tower, Lighthouse,
Sprout Tower's off-map upper drawing, Ecruteak pagodas, Azalea's kiln, Alph
chambers, and the harbor awnings. Profiles use actual extracted map grids;
Crystal, Gold, and Silver retain their existing profiles. Tree and sign pins
cover Polished's complete drawings. A regression check rejects forest rows
inside Ecruteak roofs, after visual inspection caught an oversized footprint.

Polished's `SPRITE_WEIRD_TREE` is a real sprite, unlike Crystal's variable
sprite alias. Its variable sprites begin at $F5, not $F0. The town map uses
compressed graphics, eight palettes, and tile bytes with X/Y flip flags in
their upper two bits. The importer now preserves those differences and also
decompresses the player icon. Existing installs require a Polished re-import
with the updated launcher; importer revision `polished-overworld-map-sprites-v3`
forces that refresh. Saves are not rewritten by this change.

Gen4 imported level evolution records now participate in the engine's method
registry and return their numeric target species. Tests cover Diamond, Pearl,
and Platinum level gates, Everstone, and the post-battle evolution queue.

Emerald restores an occupied Secret Base entrance when loading its map, using
the tileset's closed/open behaviour pair. Creation inside the room retains the
exterior location. Re-entering an owned base enters rather than recreating it.

Gen3 elevation zero and fifteen retain the player's current elevation. Surf
dismounts are restricted to default elevation 3, and interactions across a
bridge elevation are refused. NPC collision also respects elevation, so a
person on the deck does not block the river below. The attached Route 120
recording was inspected.
Mossdeep coordinate events now see the completed step's visit counter before
running, preventing the idle recheck from treating a switch as a second visit.
The actual extracted switch script and one-square movement are tested.

Android map/save editors now feed touch coordinates directly into their shared
pointer widgets and suppress duplicate synthesized clicks. Pinch tracking is
retained, real mouse input clears the touch pointer, and closing clears contacts.
Desktop regression tests cover taps with a stale mouse position. No physical
Android device was available for this pass.

Validation: native mesh generation across 605 Polished maps; representative
render inspection; decoded Johto/Kanto map images; level evolution, bridge/base/
switch, editor pointer, mobile control, original Emerald/Prism event, and editor
model/layout checks. The layout check requires a Windows directory-listing
adapter when run with the Lua DLL instead of LOVE.

Reference implementations:
- https://github.com/pret/pokeemerald/blob/master/src/secret_base.c
- https://github.com/pret/pokeemerald/blob/master/src/field_player_avatar.c
- https://github.com/Rangi42/polishedcrystal/blob/v3.2.3/constants/sprite_constants.asm
- https://github.com/Rangi42/polishedcrystal/blob/v3.2.3/engine/pokegear/pokegear.asm
