# Native GSC battler rows

Contributions by Roxas2712. Existing GSC interpreter and object-drawing
provenance and licences remain in `compat/gen1-gsc/` and `NOTICE.md`.

The real interpreter already registers the player-head/enemy-feet pseudo
sheets. The renderer previously rejected every loaded entry carrying a
`battler` field, so its genuine OAM entries had no pixels to draw. The frozen
Gen1 reference also skips these entries; VM-state equality alone does not
qualify this drawing path.

At the existing `battlergfx` command the native player now snapshots the
actual screen-owned indexed picture into one/two tile rows. Enemy feet come
from the bottom of the seven-tile front slot; player head comes from the top
of the six-tile back slot. Five/six-tile native fronts have the cartridge's
one-tile left padding. The VM retains its actual command timing, descriptors,
OAM positions, flips and palettes. No second interpreter or battle state is
introduced. Source image data is shared/read-only where the native shared
decoder is available; older upstream uses its existing owned decoder once
per copy. Copying performs no GPU readback. Repeated drawing does not decode
or upload images.

OBJ colour zero is removed before palette application, independently of BG
register changes. Custom RGB art keeps its alpha and opts out of indexed
recolouring. Crystal crop descriptors select a single frame. Replacement
art and queued Transform use the existing picture presentation authority;
reading the source never reveals a queued future picture.

The OAM pass also restores the caller's indexed palette uniforms, including
when drawing throws. Graphics push/pop alone restores the shader reference
but cannot undo uploads to the same shader object. The stronger actual-draw
fixture reproduces 96 uniform mismatches before this palette-scope fix.

Copied images belong to the native view, keyed weakly by the actual loaded
descriptor. Retaining an old runner retains its copied picture; a restarted
animation cannot substitute its current image into old OAM. View retirement
releases remaining images. No mod, ROM, player save or Gen1 installation is
changed. No extracted ROM pixels are committed.

Primary source:

- [Crystal battlergfx copy commands](https://github.com/pret/pokecrystal/blob/master/engine/battle_anims/anim_commands.asm)
- [Native front-picture padding](https://github.com/pret/pokecrystal/blob/master/engine/gfx/load_pics.asm)

`tests/engine/gen2_battler_rows.lua` drives actual native battles, commands
and OAM, checking copied pixel values, column-major strip addressing,
attacker mirroring, both flips, palette uploads, read-only drawing, retained
runners and failure cleanup in Gold/Silver/Crystal. It also checks native
front sizes and custom RGB/crop input. This is CPU/device-record validation,
not a new GPU, full unchanged-client, Windows or release qualification.
