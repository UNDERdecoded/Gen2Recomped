# GSC replacement art and Crystal actor copies

The native importer reads `MonsterSpriteGFX` and `MinimizePic` from the mounted
ROM. It writes the two Substitute and two Minimize pictures in full 6x6/7x7
tile boxes, plus the indexed Substitute sheet for the public getter. Cartridge
scratch tiles are column-major; generated PNG tiles are row-major. No ROM
image is committed or published with this contribution. Missing symbols or
invalid byte ranges do not fabricate art.

Native drawing uses these images through its existing image/palette cache.
The full picture footprint composes with slide, resize and lifted-row owners;
Substitute no longer bypasses those operations through a fixed Gen1 doll draw.
Minimize cannot turn into a Stadium model. The native faint picture retains
its owner. Gen2 backs use the 6x6 box at (16,48), including trainer and grow-in
placement, rather than Gen1's left-padding compensation. Image-specific scale
settings still refer to the underlying Pokemon image. Opposite-orientation
captures use the requested box dimensions with the real battler's palette.

Where the public `pic`/`drawPic` boundary already exists, the getter keeps its
original indexed-Pokemon contract and the capture paints the current replacement.
The upstream adaptation does not invent those missing methods. `substituteDoll` exposes
the actual indexed 16x32 ROM sheet with cached front/back quads, allowing the
source caller to own its palette operation.

Crystal differs from Gold/Silver: Transform and Minimize stage actor tiles in
vTiles0; `updateactorpic` later copies them into the actor's BG slot. The pinned
Gen1 reference's immediate Transform and empty Minimize/updateactorpic handlers
missed this distinction. Positive ROM symbols advertise these capabilities;
Gold/Silver retain their direct Transform and dummy $e8/$e9 commands. The same
existing VM owns staging, delays and publication. The native pin reconciler
also reads that VM's actual `stopped` field, including a program returning
without an image opcode. No additional animation or combat clock is added.

The primary definitions are in [Crystal's commands](https://github.com/pret/pokecrystal/blob/master/engine/battle_anims/anim_commands.asm),
[Crystal's programs](https://github.com/pret/pokecrystal/blob/master/data/moves/animations.asm)
and [Gold/Silver's commands](https://github.com/pret/pokegold/blob/master/engine/battle_anims/anim_commands.asm).
The Gen2-only animation cache revision is now 2 so an existing v1 cache gets
the new art/capabilities on import; other generations and saves retain their
existing contracts. Renamed editions advertise only data their symbols expose.

ROM-free tests check every decoded pixel, real native drawing, palettes,
requested capture geometry, resize/lifted composition, image-scale settings,
error restoration and native terminal ownership. CPU checks with the supplied
Crystal ROM independently validate 10,880 picture pixels against its bitplanes,
then exercise 2,804 cases and 355,718 frames. Crystal's actor staging is checked
at VM frame 8 and publication at frame 57 against the actual imported programs.
For Transform/Minimize only, picture-override equality with the buggy pinned
reference is replaced by that primary-source oracle; all other command/object,
OAM and BG observations remain compared. No old generated-cache input is used.

These checks do not establish GPU, unchanged-mod, Windows or release parity.
The native OAM drawer still skips battler-row pseudo-sheets, as does the pinned
reference; that missing renderer path needs separate work. Complete send-out,
identity/EXP/capture/menu events, model/download options, the full native battle
factory/turn API and broader release qualification also remain open. Mods,
protected instances, ROM originals and player saves are unchanged.
