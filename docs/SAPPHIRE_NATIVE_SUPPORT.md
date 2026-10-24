# Sapphire native cartridge support

USA Rev 0 SHA-1: `3ccbbd45f8553c36463f13b938e833f652b793e4`. This adds an independent `sapphire/`
import cache, `_sapphire` saves and an ALPHA launcher entry. It does not alias
Emerald's cache, map data or cartridge hash.

## Cartridge contracts

`tools/gen3_rs_manifest.py` combines structural table checks with matching
pret/pokeruby ELF symbol identities. Every allocated ROM section in the ELF
must match the supplied cartridge bytes before any symbol is used. Matching
reference source: pret/pokeruby
`5784633ce4ef7ade1a7f2d2d0c288e3d5e6cdd7f`; both RS matching builds pass their
checksum comparisons. The Emerald reference is also byte-verified and is used
only to identify canonical special functions.

The generated manifest supplies 394 maps, 694 trainers, 349 items, 468 song
slots, 138 movement actions, its own pocket numbering and canonical type ids
for the cartridge's abbreviated type names. RS's raw 4bpp normal font and
mapped small healthbox font are decoded separately. Its three compressed
trainer back sheets are validated, decompressed and matched to their owners.
The 1bpp braille face uses the cartridge's own tile map, paired character
halves and MSB-first field blitter. All 64 patterns must match six independent
raised-dot masks. The six RS window/text header bytes and 32-pixel line pitch
are preserved; Emerald keeps its existing centered window contract.

Native script special ids are mapped to the engine's existing handlers by
function identity. Extractor readers use the inverse map: a missing identity
returns no function rather than probing an unrelated native slot. 197 of the
342 specials are mapped; this is not a claim that every story feature works.

Mauville's three RS switches are read from the verified ROM coordinate table
and checked against its map events. The shared beam rules retain RS's own
positions; five renamed Mauville/Petalburg specials map by verified function
identity. Petalburg's door frames/delays are checked against its own ROM.
The generator requires the pinned clean matching source for C-layout metadata.

The save layout is read from the cartridge's fourteen `sSaveBlockChunks`
records, which use RAM pointers and sizes. RS's 15040-byte SaveBlock1 and
2192-byte SaveBlock2 differ from Emerald. The inventory/money encryption key
is explicitly absent; Pokemon game-of-origin remains Sapphire. Flags, vars,
bag capacities and storage boundaries are checked, and all 24 substructure
orders are taken from the matching source. Only metadata and hashes are
committed; no cartridge, extracted image, map, audio or speech files are.

## Validation and reproduction

Candidate `d11d8cd` passed the native rendered driver with all mods off:

- Fresh import and Birch speech/naming reach the actual moving truck.
- Real directional input takes the dynamic truck warp; the normal Mom script
  reaches the new house.
- Native save/reload retains the player and the Sapphire version and creates
  no Emerald save in the fresh QA identity.
- The actual Route 101 bag interaction opens starter selection, records the
  chosen species in var `4023`, runs the first Poochyena battle and reaches
  Birch's lab through the script's warp.
- Roxanne's real map interaction and native battle return to the field with
  the Stone Badge and TM39. A level 100 Mewtwo is an intentional party fixture
  for this separate arena test, not evidence of a full story playthrough.
- All 22 braille walls decode without unknown cells. The actual Sealed
  Chamber sign opens the ABC wall at its cartridge text coordinates; B closes
  the wall and resumes the native runner. Its rendered view was inspected.
- The captured field/first-battle/healthbox/reward views were inspected locally.

Candidate `f8c23da` additionally passes `rs_gyms_native_driver.lua`: real
walking activates an RS floor switch, its beam picture/passability and saved
re-entry state agree, and Wattson's actual battle awards the Dynamo Badge and
TM34 before disabling all three switches. With a deliberate strong party and
story-state fixture, Randall's actual battle runs every one of the five door
frames in Petalburg and resumes the native script. Both views were inspected.
`rs_gym_puzzles.lua` adds 23 checks for the five aliases, RS switch coordinates,
beam collision, Emerald fallback and Petalburg door writes.

The run used macOS LÖVE 12/Metal with a QA-only renderer configuration, a fresh
own save identity and a migration marker created before boot. Physical
iPhone/iPad, link play and full story/post-game have not been certified.

`tests/engine/sapphire_registration.lua` verifies edition identity, type ids
and native/canonical special address spaces. `sapphire_save_layout.lua`
roundtrips patterned nonzero save blocks through multiple sector rotations and
checks plain RS inventory encryption and game-of-origin. `rs_braille.lua`
checks mapped 1bpp tiles, dot identities, header geometry and rejection of a
corrupted font (13/13). All five suites pass. The engine
suite is 69/79 passing; the same ten failures reproduce on the unmodified
baseline (64/74).

Reproduce using `tools/run_gen3_native_smoke.py sapphire --rom YOUR_ROM
--love YOUR_LOVE12_BINARY --lock YOUR_SHARED_QA_LOCK --driver
tests/sapphire_native_driver.lua --speed 8`. The helper snapshots committed
sources and rejects cache reuse if extraction inputs changed.

The generic summary fallback right-aligns each stat value within its own
column. Previously a value beginning at x=120 overlapped the next label at
x=132. The 15-check `summary_fallback_columns.lua` exercises worst-case
three-digit stats and full HP pairs; actual native summary/IV views were
inspected after the change. Extracted Emerald/FRLG window art keeps its own
unchanged layout.

Remaining alpha scope includes the original RS title/intro backdrop (the
engine currently uses its fallback title), several UI art/minigame stages,
and unmapped native specials. Generic `scenes.lua`/`summary_info.png` cache
warnings remain disclosed. This is playable native support with concrete
opening/battle tests, not a complete feature-parity certification.
