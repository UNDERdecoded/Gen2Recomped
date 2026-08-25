-- Which Pokemon version this process is running: Red (the historical
-- default), Blue, Yellow, Gold, or Silver.
-- One source of truth for everything that differs by
-- version -- the accepted ROM hash, the import manifest, where the
-- extracted cache lives, and the save-file suffix -- so the importer,
-- cache mount, SaveData, title screen and palette all agree.
--
-- Red keeps every un-suffixed path it always used (save.lua, the root cache),
-- so existing installs are untouched; Blue is namespaced under blue/ and
-- _blue, Yellow under yellow/ and _yellow, Gold under gold/ and _gold,
-- Silver under silver/ and _silver, so versions can be imported and played
-- side by side.
--
-- Zero requires, so it loads during love.conf and under plain Lua for tools
-- and tests.  The active version is a process-global set once at boot from
-- the launcher's column choice (main.lua); it defaults to Red.

local GameVersion = {}

GameVersion.VERSIONS = {
  red = {
    id = "red",
    generation = 1,
    label = "Red",
    displayName = "Pokemon Red",
    launcherName = "Red",       -- game-panel header in the launcher
    sha1 = "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
    manifest = "tools/rom_manifest.json",
    cachePrefix = "",       -- Red owns the cache root (backwards compatible)
    saveSuffix = "",        -- save.lua / save.lua.bak / save.lua.tmp
  },
  blue = {
    id = "blue",
    generation = 1,
    label = "Blue",
    displayName = "Pokemon Blue",
    launcherName = "Blue",
    sha1 = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2",
    manifest = "tools/rom_manifest_blue.json",
    cachePrefix = "blue/",  -- blue/data/generated, blue/assets/generated
    saveSuffix = "_blue",   -- save_blue.lua / .bak / .tmp
  },
  yellow = {
    id = "yellow",
    generation = 1,
    label = "Yellow",
    displayName = "Pokemon Yellow",
    launcherName = "Yellow (alpha)",
    sha1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1",
    manifest = "tools/rom_manifest_yellow.json",
    cachePrefix = "yellow/",  -- yellow/data/generated, yellow/assets/generated
    saveSuffix = "_yellow",   -- save_yellow.lua / .bak / .tmp
  },
  gold = {
    id = "gold",
    generation = 2,
    label = "Gold",
    displayName = "Pokemon Gold",
    launcherName = "Gold (Phase 2B)",
    sha1 = "d8b8a3600a465308c9953dfa04f0081c05bdcb94",
    manifest = "tools/rom_manifest_gold.json",
    cachePrefix = "gold/",
    saveSuffix = "_gold",
  },
  silver = {
    id = "silver",
    generation = 2,
    label = "Silver",
    displayName = "Pokemon Silver",
    launcherName = "Silver (Phase 2B)",
    sha1 = "49b163f7e57702bc939d642a18f591de55d92dae",
    manifest = "tools/rom_manifest_silver.json",
    cachePrefix = "silver/",
    saveSuffix = "_silver",
  },
  -- Crystal is the Rev 1 (v1.1) build, which is what pokecrystal11.sym
  -- describes.  Rev 0 exists but moves three symbols, none of which the
  -- extractor reads -- the hash gate below still pins it to Rev 1 so an
  -- imported ROM can never disagree with the embedded symbol table.
  crystal = {
    id = "crystal",
    generation = 2,
    label = "Crystal",
    displayName = "Pokemon Crystal",
    launcherName = "Crystal (Beta)",
    sha1 = "f2f52230b536214ef7c9924f483392993e226cfb",
    -- Rev 0.  Only three symbols move between the revisions and the extractor
    -- reads none of them, so one manifest and one symbol table serve both --
    -- but the hash still has to be accepted explicitly.
    sha1Alt = { "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133" },
    manifest = "tools/rom_manifest_crystal.json",
    cachePrefix = "crystal/",
    saveSuffix = "_crystal",
  },
  -- Pokemon Prism, a CRYSTAL ROM hack, which is why it sits after Crystal and
  -- carries generation 2.
  --
  -- The base was MEASURED, not assumed: of 4001 routines whose code differs
  -- between Gold and Crystal, Prism matches Crystal's version 77 times and
  -- Gold's 0 times.  (A first pass used Gold on the strength of the
  -- monhacks/prism README; that README describes an older build with a
  -- different md5.  Rebuilding on Crystal took the recovered symbol count from
  -- 900 to 1279 code matches.)
  --
  -- Registered so the setup scripts stop rejecting the cartridge as unknown.
  --
  -- Everything is relocated (mean per-bank byte match 1.4% vs Crystal, no bank
  -- above 20%), so Crystal's symbol table does not apply positionally and each
  -- table had to be found on its own.  The BATTLE-side tables are now in and
  -- verified against the ROM by tests/prism_tables_test.lua: Moves, MoveNames,
  -- ItemNames, ItemAttributes, TrainerClassNames, PokemonNames, BaseData,
  -- TMHMMoves and TypeNames all decode, including the five ways Prism reshapes
  -- Crystal's records (see tools/prism_tables.py and the manifest's `layout`).
  --
  -- The WORLD tables are in as well.  Tilesets, SpecialsPointers and
  -- OverworldSprites all decode, and the last structural difference is
  -- handled: Prism stores every map's block table and every tileset's
  -- metatile and collision tables LZ3-COMPRESSED where Gold and Crystal store
  -- all three raw (`layout.tilesetCompressed` + RomExtractorGen2:gen2LzAt).
  -- Read raw, those tables WERE the compressed streams, so all 448 maps were
  -- built out of nonsense block ids against tilesets whose block counts were
  -- measured from the compressed span, and a new game died on the first map.
  -- 444 of the 448 now index inside their tileset.
  -- TypeMatchups is still unresolved: Prism does not use Crystal's
  -- attacker/defender/multiplier triple list in any form found so far, so type
  -- effectiveness falls back to engine defaults.
  -- See [[prism-support]] and [[prism-symbol-recovery]].
  prism = {
    id = "prism",
    generation = 2,
    label = "Prism",
    displayName = "Pokemon Prism",
    launcherName = "Prism (Beta)",
    sha1 = "752076692ae3387cf426ce5f51a98c6b60e8df6a",
    manifest = "tools/rom_manifest_prism.json",
    cachePrefix = "prism/",
    saveSuffix = "_prism",
    -- Importable, and labelled EXPERIMENTAL rather than shipped-quality.
    --
    -- A full run produces 254 moves, 253 items, 254 species, 449 maps, 184
    -- wild-encounter tables, 506 Pokemon sprites, 254 icons, 127 overworld
    -- sheets and 150 songs, all regenerated by tools/prism_tables.py +
    -- tools/prism_symbols.py and covered by tests/prism_tables_test.lua; the
    -- compressed-world reader is covered by
    -- tests/gen2_compressed_tilesets_test.lua.
    --
    -- What is still rough, and why the launcher says so out loud: the SCRIPT
    -- VM.  Prism's ScriptCommandTable has 232 commands to Crystal's ~120 and
    -- diverges from index 13; the derived table cut desyncs from 2206 to
    -- 1047, against Crystal's baseline of 16.  So the world loads and is
    -- walkable, but NPC dialogue and map events still misbehave often.  That
    -- is a state worth testing in, not one to present as finished -- hence
    -- the label.  See [[prism-data-tables]] for where to pick that up.
    importable = true,
    -- hold B to run (DoPlayerMovement's .run branch); see Player.beginStep
    hasRunning = true,
  },
  -- Pokemon Polished Crystal 3.2.3, also a CRYSTAL hack, so it sits after
  -- Prism at the end of the Gen 2 run.
  --
  -- THE OPPOSITE SITUATION TO PRISM, and that is the whole point of this
  -- entry. Prism has no usable public disassembly, so every table had to be
  -- recovered by signature matching and 1544 symbols was the ceiling. Polished
  -- Crystal IS a public disassembly that builds its own ROM: a reproducible
  -- rgbds v1.0.0 build emits 70171 exact symbols, and 97 of the 157 names
  -- RomExtractorGen2 reads are present under their own names -- including
  -- every table that blocked Prism for weeks (BaseData, PokemonNames, Moves,
  -- ItemNames, MapGroupPointers, Tilesets, SpecialsPointers, TMHMMoves,
  -- EvosAttacksPointers, TrainerGroups).
  --
  -- THE HASH IS THE BUILD THE MANIFEST WAS MADE FROM, and it has to be,
  -- because the manifest is 70172 exact addresses out of ONE rgblink run.
  --
  -- There is more than one 3.2.3 build in the wild and they are not the same
  -- ROM. Comparing the .sym shipped here against the one the previous manifest
  -- was built from: 23938 symbols agree, 44273 sit one to three bytes apart,
  -- and 1960 exist in only one of them. Feeding either manifest the other's
  -- ROM reads every table a few bytes off -- which is the exact failure the
  -- manifest's own notes exist to prevent, and it would present as an import
  -- that finishes and produces nonsense rather than as an error.
  --
  -- So this is NOT an `sha1Alt` case. Crystal's two revisions decode
  -- identically and share a manifest; two Polished Crystal builds do not.
  -- Supporting another build means running tools/polished_symbols.py against
  -- ITS .sym and .gbc and shipping that manifest -- not widening this list.
  -- `faithful` is a separate cartridge again and would need its own entry.
  --
  -- NOT IMPORTABLE YET, and this list is what is actually left rather than a
  -- placeholder. Two of the three things that used to be on it are done:
  --   * TEXT IS HUFFMAN-COMPRESSED, and now decodes. The rule came off the
  --     cartridge's own ReadHuffmanChar (00:$1273) rather than out of the
  --     source, and tests/polished_crystal_text_test.lua asserts it by making
  --     the ROM say a sentence back. What is still missing is the other half
  --     of constants/charmap.asm: `parse_charmap` reads `charmap "X", $YY`
  --     lines and Polished Crystal declares its letters some other way, so
  --     117 of the 256 characters have names and the rest are inferred from
  --     Gen 2's layout.
  --   * `TypeMatchup` vs `TypeMatchups` was not a trap after all -- the
  --     build's own symbol table carries `TypeMatchups`, under that name.
  --   * THE NAME TABLES ARE IN, read off this cartridge by
  --     tools/polished_tables.py: 291 species (Bulbasaur at 1, Mewtwo at 150,
  --     Lugia at 249), 255 moves and 255 items, both counts measured off the
  --     tables rather than typed in, and all of it through the ngram
  --     dictionary so "Karate Chop" comes back as words. Eleven character
  --     bytes are still unnamed and the script lists them.
  --   * THE MAP LIST IS IN: all 605 of them, and the header layout came out
  --     of the routines that read it -- a SEVEN-byte map_header (00:$24e9's
  --     `ld a,$07 / rst $18`), the attributes pointer at +2
  --     (GetMapAttributesPointer's `ld de,$0002`) and one fixed attributes
  --     bank (SwitchToMapAttributesBank's `ld a,$26`) instead of Gold and
  --     Crystal's per-map bank byte. Every header resolves to a
  --     `<Label>_MapAttributes` symbol and there are exactly 605 of those, so
  --     the walk accounts for all of them and invents none. The EXTRACTOR
  --     reads that shape now too, from the manifest rather than from the
  --     version id -- mapHeaderBytes/TilesetAt/EnvAt/AttrAt/LandmarkAt/MusicAt
  --     plus mapAttributesBank, with -1 for the palette and fish_group fields
  --     this header does not have. Until that landed the tables agreed and
  --     the importer still read nine-byte headers, which is the quietest
  --     shape of wrong there is: 80 of the 605 headers happen to resolve at
  --     the old stride, so the index came back looking populated.
  --   * AND THE TEXT READS. The marker turned out to be MID-STRING: a line is
  --     ordinary charmap bytes until $5D (`<CTXT>`) and a Huffman stream after
  --     it, so "W" + stream is "Which photo is on your Trainer Card?" and
  --     decoding the stream alone loses the W and reads the marker as data.
  --     The scaffold (data/generated_gen2_polishedcrystal) builds, so the
  --     extractor has a source tree to read through.
  --   * TYPES, ENCOUNTERS, TILESETS AND SPRITES ARE IN, and every one of them
  --     differed from Crystal in a way that would have imported silently:
  --       - 18 types, because this hack adds FAIRY;
  --       - 3 bytes per wild slot, not 2 -- there is a FORM byte after the
  --         species, and Crystal's stride reads Charmander at level 0;
  --       - 18-byte tileset entries opening with META and carrying neither a
  --         GFX nor a Coll pointer, where Crystal's offsets land in WRAM;
  --       - tileset graphics split across GFX0/GFX1/GFX2;
  --       - the overworld sprite table called `SpriteHeaders`, four bytes a
  --         row, bank at +2 where Crystal keeps a tile count.
  --     Collision needed nothing: the extractor already reaches `<Family>Coll`
  --     by symbol, and all 45 families have one -- naming the family was the
  --     whole of it.
  --   * AUDIO IS IN TOO. Music keeps `db bank, dw address`; SFX and Cries
  --     drop the bank and are bare `dw` pointers into whichever bank their
  --     data was assembled in, taken from the symbols so a rebuild that moves
  --     it moves the answer.
  --   * AND THE READERS ARE NOW DRIVEN AGAINST THE CARTRIDGE rather than
  --     asserted against the source: tests/polished_crystal_extract_test runs
  --     the audio, sprite, tileset and map-header readers on the ROM and
  --     names rows it must give back -- New Bark and Cherrygrove on one
  --     tileset, Pallet and Viridian on another, Elm's lab on a third, and
  --     the index agreeing with the manifest's own roster to the map. Putting
  --     any of Crystal's strides back fails it, which is what the
  --     source-level checks could not do.
  --   * AND THE GROUND IS IN, which was the last thing standing between the
  --     tables and a map that loads. Three separate things had to be right
  --     and each was wrong in a way that raises nothing:
  --       - this build ships a REWRITTEN LZ decompressor (00:$08bf), unrolled
  --         two bytes per iteration, whose LZ_ITERATE writes the run byte once
  --         before the fill loop and whose LZ_ALTERNATE writes the pair before
  --         the repeat loop -- so the same control byte means field+2 and
  --         field+3 bytes where pret's original means field+1. At the original
  --         lengths 246 of 605 maps decompressed to exactly width*height and
  --         359 came 1 to 23 bytes short; with the two pre-writes it is 605 of
  --         605. Prism run the same way goes 442 of 450 down to 74, so it is
  --         per-cartridge and lives in the manifest.
  --       - tileset ids START AT ONE: LoadMapTileset (00:$25f9) does `dec a`
  --         on wMapTileset before AddNTimes. Indexed from zero every map still
  --         got a real tileset family, just the one before its own -- wrong
  --         blocks, wrong collision, and nothing to see in a log. Nineteen of
  --         the 45 ids in use named a family with FEWER blocks than their own
  --         maps index (Ice Path's maps reach block 241 against an 82-block
  --         family) and one named nothing; from one, all 45 resolve and no map
  --         indexes past its own tileset.
  --       - the metatile, attribute and collision tables are COMPRESSED too.
  --         Decompressed they land exactly: Johto1 253 blocks, Johto2 255,
  --         Kanto1 256, Kanto2 249, with Attr the same length as Meta and Coll
  --         a quarter of it.
  --     Prism gained from the same pass: eight of its maps decode LONGER than
  --     their header declares and were being rejected and re-read raw, which
  --     is the compressed-stream-as-ground failure arrived at backwards. The
  --     cartridge itself copies width*height out of a full decompression, so
  --     a long decode is now truncated and, on a ROM whose blocks are declared
  --     compressed, the raw read is not a fallback at all. tests/map_blocks_
  --     decode drives all three cartridges and requires the opposite answer
  --     from Crystal, which stores its blocks raw.
  --   * AND A FULL IMPORT NOW RUNS END TO END, headless against the ROM.
  --     The first one produced 605 maps with ground and 599 of them with NO
  --     WARPS, NO SIGNS AND NO OBJECTS -- rooms without doors, towns with
  --     nobody in them -- and said nothing, because "this map has no events"
  --     is a legitimate answer. Two bytes: Gold and Crystal keep two far
  --     pointers in map_attributes (`dba <Map>_MapScripts` at +6, `dw
  --     <Map>_MapEvents` at +9) with the connection flags at +11; this build
  --     merged the structures, so the pointer is at +7 and the flags at +9,
  --     and its map_events opens with a counted list of 2-byte scene scripts
  --     and one of 3-byte callbacks before the warps (five-byte coord events
  --     after them, not Crystal's eight). Read from
  --     CopyMapPartialAndAttributes (00:$1d8f) and
  --     _LoadMapAttributes_ReadEvents (00:$1de6). It is now 590 of 605 maps
  --     with warps, 545 with objects, 377 with signs and 104 with
  --     connections; New Bark has its five doors, Route 29 west and Route 27
  --     east, and every warp coordinate on every map lands inside the map.
  --   * AND THEN IT WAS PLAYED, which found four more -- every one of them a
  --     field read at Gold and Crystal's offset on a cartridge that moved it,
  --     and not one of them raising at import time:
  --       - THE CRASH. A grass record's day and night blocks were reached
  --         with the slot stride folded in at Crystal's two bytes, so on a
  --         cartridge with a FORM byte they landed inside the MORNING block.
  --         Levels of 161, species of 0 -- and SPECIES_000 is what
  --         Pokemon.new refuses, so walking into grass at night killed the
  --         game while morning worked fine.
  --       - THE GREY WORLD. EnvironmentColorsPointers is eight ONE-BYTE
  --         relative offsets here, not eight `dw`; as words three of the four
  --         land outside the bank, so the read failed and all 45 tilesets got
  --         a palette map with no colours. A palette map with no colours
  --         renders GREY, which is the whole of "the world is black and white
  --         whatever colour mode I pick". Seven palettes to a row, not eight,
  --         and the environment byte carries flags above the constant that
  --         have to be masked off first (`and $07`, 02:$5fb4) -- Elm's lab
  --         reads 99 and means INDOOR.
  --       - THE OPENING OF THE GAME, SILENT. A five-byte coord_event keeps
  --         its script at offset 4; read at Crystal's 5 the high byte is off
  --         the end of the record and `nil * 256` RAISES -- caught per map, so
  --         the map lost every script it had. 64 maps went that way: New Bark
  --         Town, Elm's Lab, Player's House, Cherrygrove, Route 29. That is
  --         why events and scripts "were not working"; there were none where
  --         the player was standing.
  --       - THE SCRAMBLED SPRITES. The overworld sheets are LZ streams, not
  --         raw 2bpp -- the gaps between them are 214, 222, 236, 243 bytes,
  --         none of them a multiple of the 16 a tile takes. Decompressed,
  --         every walking sheet is exactly 384: 24 tiles, six poses. And the
  --         four-byte header row has no kind field at all, so Crystal's +4 and
  --         +5 were reading the NEXT row's pointer as a size cap and a
  --         palette.
  --     All 605 maps now carry scripts, all 45 tilesets carry colours, and no
  --     wild slot anywhere is SPECIES_000.
  --   * THEN IT WAS PLAYED AGAIN, and the text engine turned out to be a
  --     different machine from Crystal's. PlaceNextChar (00:$0e8d) sorts a
  --     byte with three compares -- `cp $5f` literal, `cp $52` special,
  --     `cp $0a` DICTIONARY WORD -- and Gold and Crystal have no dictionary
  --     band at all. Reading this cartridge at their offsets did two things
  --     at once: it stopped at $57, which is LineChar here and <DONE> there,
  --     so EVERY string in the game was one clause long; and it printed 69
  --     dictionary words ('the ', 'you', 'Pokemon') as raw control bytes.
  --     Together that is "NPCs don't have text". The punctuation had moved
  --     too -- "Mr:Mime", "Hello]", "Nintendo ?4" -- and each correction here
  --     was read out of a string whose English spelling is not in question
  --     ($9C from Mr. Mime and Exp.Share, $BC from Ho-Oh and Porygon-Z, the
  --     digits from BoughtN64Text) rather than copied across from Crystal.
  --   * AND THE INTRODUCTION EXISTS, under another professor. Polished
  --     Crystal's is ELM's -- ProfElmSpeech (01:$6291), ElmText1..7,
  --     AreYouABoyOrAreYouAGirlText, GenderMenu, NamePlayer. With nothing
  --     matching `OakText1` the extractor concluded the cartridge had no
  --     introduction, Data.lua turned the New Game screen off, and the player
  --     was dropped into the world with no speech, no boy/girl choice and no
  --     name prompt. The beat list is manifest data now, so the next hack
  --     with its own professor needs an entry and no code.
  --   * FIVE SCRIPT COMMAND WIDTHS were read out of the handlers the ROM's own
  --     jumptable points at. `warp` is FOUR bytes (25:$709b writes group,
  --     number, x and y); at two it handed the runtime a nil x, and setMap
  --     multiplies that immediately -- a hard crash in the middle of a
  --     cutscene. giveitem and takeitem are two, loadtrainer three (the
  --     commonest desync on the cartridge, 89 of them), jumptext a far
  --     pointer. Deliberately NOT chosen by minimising the desync count: that
  --     number improves when the walker decodes LESS, and a greedy search on
  --     it walked straight to `farscall` at one byte wide.
  --   * THE SPECIES ART CAME BACK FROM 35 TO 580, and the cause of the 271
  --     placeholders was TWO BYTES OF PADDING. Gold and Crystal pad their
  --     fixed-width name tables with $50 ("@"); this build pads with $53,
  --     which is FinishString in its own special block -- and $50 here is a
  --     dictionary word, the rival's name. Checking only $50, every species
  --     name came back wearing its padding as text ("Bulbasaur<RIVAL>"):
  --     still recognisably the species, and useless as a key, so the pic
  --     lookup asked for `BulbasaurRivalFrontpic` and got nothing. Two more
  --     followed once the names were right: the pic SIZE is in its own table
  --     (PokemonPicSizes, 76:$4ec5 -- one nibble per species, two to a byte,
  --     read by GetPicSize at 00:$3182) rather than in base_stats, and the
  --     base form of a species with regional variants is named
  --     `<Name>Plain<Pic>`, which is 45 of them. Party icons likewise: this
  --     build names one symbol per species (`AbraIcon` beside
  --     `AbraFrontpic`) where Crystal has two indirection tables and Prism a
  --     dba, so the stage produced ZERO and said nothing. 286 now.
  --   * AND THE TRAINERS ARE IN, which was the same padding byte a third
  --     time. TrainerGroups is a `dba` here, not a `dw` -- the parties sit in
  --     five different banks, so every row carries its own, and
  --     FindTrainerData (07:$4223) does `add hl,bc` THREE times before
  --     reading it. As words the first row is $d67c, not a ROM address at
  --     all, so the walk stopped on row 0 and the cartridge reported NO
  --     trainer classes: not an error, just every trainer keeping the
  --     placeholder pic, which is why two were written out of a table of 122.
  --     The class NAMES then needed the $53 terminator and the n-gram
  --     dictionary as well -- "Leader" is stored as `L`, the n-gram for "ea",
  --     `d`, the n-gram for "er" -- and so, it turned out, did the item and
  --     move tables, which had been coming out as "Park Ball<RIVAL>Pok B",
  --     one record's tail joined to the next one's head. Seeding the
  --     terminator once in run() rather than inside a stage is what fixed
  --     those: every stage that ran EARLIER had been reading Gold's.
  --   * THE NPCs WERE IN THE RIGHT PLACES AND WERE THE WRONG PEOPLE. The
  --     extractor's own sprite table reads id $24 as Elm, correctly, and then
  --     a table of CRYSTAL's sprite-id fixups relabelled it
  --     SPRITE_COOLTRAINER_F -- $0A became Janine, $01 became Red. Every
  --     index in that table is into Gold and Crystal's sprite_constants.asm,
  --     which this build renumbered; Prism already turns it off for the same
  --     reason. The coordinates were never wrong: scored against each map's
  --     own collision, y-then-x biased by 4 puts 83.5% of the cartridge's
  --     objects on a walkable tile and the transposed order 40.3%.
  --   * AND TWO SCRIPT OPERANDS WERE THE WRONG KIND. `f` is a far SCRIPT
  --     pointer and `T` a far TEXT pointer -- both three bytes, so a wrong
  --     letter costs nothing in alignment and everything in meaning: the
  --     operand is queued as a script nobody enters instead of as a line of
  --     dialogue. All 205 farwritetext and 38 farjumptext instructions were
  --     doing that, which is most of the rest of "NPCs have no text".
  --   * AND THE FIRST PASS AT THOSE WIDTHS WAS PARTLY WRONG, which is worth
  --     recording. The opcodes were enumerated from the source table with a
  --     pattern that only matched LOWERCASE operand specs, and three entries
  --     carry an uppercase one -- so every opcode from $4F up came out one too
  --     low and two of five "fixes" landed on the command NEXT to the one
  --     whose handler had been read. loadtrainer was already correct and was
  --     made wrong; loadwildmon was wrong and was left alone. Both are right
  --     now and the test names the handler address for each.
  --   * AND ELM ASKED FOR HELP FIVE TIMES BECAUSE ONE COMMAND DID NOTHING.
  --     This build adds sjumpfwd/iftruefwd/iffalsefwd/ifequalfwd, which Gold
  --     and Crystal have no equivalent of: the operand is a byte counted from
  --     the instruction AFTER it (Script_sjumpfwd, 25:$6c46, is
  --     `ld hl,[$ffec] / inc hl / GetScriptByte / add hl,bc`). Emitted as a
  --     bare number there is nothing to branch to, so the skip was inert and
  --     the script ran into the arm it meant to skip -- his is
  --     `checkevent 121 / iffalsefwd <past the request> / scall / jumptext`,
  --     which asks again however many times it is answered. The offset is
  --     resolved into an ordinary label at extraction now (operand kind `j`),
  --     and the VM has the four names. Following those branches also took the
  --     script walk from 4,119 scripts and 34,922 instructions to 6,665 and
  --     48,206 -- a third of the cartridge's script code had never been read.
  --   * THE COMPOUND TEXT COMMANDS ARE LOWERED TOO. This build collapses the
  --     pairs Gold spells out -- open a box, print, end -- into single
  --     opcodes, and adds "this" and "opened" families beside them. Unlowered
  --     they are not wrong, they are ABSENT: the NPC opens a box, says nothing
  --     and closes it. With those and the aliases that are genuinely the same
  --     operation under another name (nooryes, checkkeyitem, random16), the
  --     unhandled-opcode audit drops from 66 distinct commands over 6,316
  --     instructions to 43 over ~2,100. Anything with a real behavioural
  --     difference -- givetmhm, changemapblocks, trainerflagaction -- is
  --     deliberately still in the audit rather than aliased to something
  --     close, because a wrong alias is worse than an absent one.
  --   * AND THE NPCs INTRODUCING THEMSELVES AS TREES WERE READING THE WRONG
  --     SHARED SCRIPT. StdScripts is a plain `dw` table in ONE bank here, not
  --     Gold and Crystal's `dba`: StdScript (25:$6c2b) is `GetScriptByte /
  --     add hl,de / add hl,de / ld b,$2f` -- the index doubled and the bank
  --     forced. Read three bytes to a row the "bank" is the first pointer's
  --     low byte and the "address" is its high byte joined to the next
  --     pointer's low, which on this cartridge is $70:$6e40 -- a perfectly
  --     valid ROM address, just not one the table ever names. That is why
  --     nothing complained: all 348 jumpstd instructions ran somebody else's
  --     script, and the stds are the bookshelves, the signs, the PC, the mart
  --     counter and the fruit trees.
  --   * THE BATTLE PICS AND OVERWORLD SHEETS WERE CHECKED BY EYE, rendered to
  --     ASCII out of the cartridge: Bulbasaur's 5x5 front and 6x6 back and
  --     Elm's 16x96 walking sheet all come out clean. So "the sprites are
  --     scrambled" was the sprite-id override above -- the art was right and
  --     the wrong sheet was being asked for.
  --   * THE STARTER BALL HANDED OVER THE WRONG POKEMON, and it was one
  --     table read one entry late. PokemonNames opens with a DUMMY here --
  --     which is why the Python side reads 292 and drops the first -- and the
  --     extractor was not dropping it, so every species took the NEXT one's
  --     name. SPECIES_002 was called Bulbasaur; SPECIES_158, which is
  --     Totodile, was called Typhlosion. No name looks wrong on its own,
  --     because they are all real Pokemon; it shows only where a name is
  --     compared against an id, and picking a starter is exactly that.
  --   * THE PLAYER AND CARD PICS ARE COMPRESSED TOO. Gold and Crystal store
  --     ChrisPic, ChrisCardPic and the rest raw, which is what
  --     gen2RawColumnPic is named after. Read raw here, what reaches the 2bpp
  --     decoder is the LZ STREAM drawn as pixels -- and the length check
  --     passes, because a stream is exactly as many bytes as a pic needs.
  --     That is the noise where the player's picture should be in the
  --     new-game intro.
  --   * THE MENU TEXT WAS THE PLACEHOLDER, NOT THIS GAME'S TYPEFACE. The
  --     font stage looks for a `Font` symbol; polished has NONE. It calls
  --     the face `FontNormal` and lets the player pick one of EIGHT through
  --     FontPointers (08:$7535, masked $07, $390 apart). With the symbol
  --     missing the whole stage bailed and the importer copied
  --     assets/logo/pokemon_logo.png over BOTH font.png and font_extra.png,
  --     so every letter on screen was drawn out of the logo. That is the
  --     "rough looking" menu text -- not a rendering problem at all.
  --     The three loaders name their own tile counts in `lb bc, BANK, count`:
  --       _LoadStandardFont 08:$7501  ld bc,$0872 -> 114 tiles at $8800
  --       FontCommon        08:$64DA  ld bc,$0806 ->   6 tiles at $8F20
  --       _LoadFrame        08:$7551  ld bc,$0808 ->   8 tiles at $8F80
  --     which is $80-$F1, $F2-$F7 and $F8-$FF: the 128 sheet slots exactly,
  --     none spare and none missing. BattleExtrasGFX (08:$6D92) is the extra
  --     sheet and goes through DecompressRequest2bpp, so it is COMPRESSED
  --     and 2bpp where Crystal's FontExtra is neither.
  --     Rather than special-case a hack, the segments live in
  --     `manifest.fontSheets` as { symbol, tiles, code, bpp, compressed } and
  --     the Gold and Crystal path below runs unchanged when it is absent.
  --     A 2bpp tile is ink wherever EITHER plane is set -- colours 1, 2 and 3
  --     all draw and only 0 is paper -- so taking plane 0 alone left the HP
  --     bar full of holes.
  --     Checked by eye, rendered to ASCII from the cartridge: $80-$99 are
  --     A-Z, $A0 on are the lower case, $E0-$E9 are the digits and $F8-$FF
  --     are the text-box border.
  --   * NOTHING ON ANY MAP EVER STARTED HIDDEN, and that one absence is the
  --     whole of the reported "weird flag and event behavior".
  --     Gold and Crystal open a new game by RUNNING `InitializeEventsScript`,
  --     a flat run of `setevent`s, and the extractor walked those opcodes.
  --     This build has no such symbol. `InitializeEvents` (2f:$4c55) is a
  --     ROUTINE over three DATA tables, each ending on $FFFF (GetDWInDE,
  --     2f:$4c83, is `and e / inc a`):
  --       InitialEvents                      dw event, ... , -1  (b=1 -> SET)
  --       InitialEngineFlags                 dw flag,  ... , -1
  --       InitialVariableSpritesAndMapScenes dw addr, db value, -1
  --     Missing the symbol was not an error -- it returned an EMPTY set, and
  --     an empty set means NO OBJECT IS EVER HIDDEN. 177 events unread, and
  --     286 objects across the cartridge that should have been off-stage were
  --     standing on their maps from the first step:
  --       - the player's MOTHER in two places at once. PLAYERS_HOUSE1_F has
  --         five SPRITE_MOM rows -- one always-on gated on EVENT 1680, and
  --         four differing only in MAPOBJECT_TIMEOFDAY, all sharing EVENT
  --         1681. InitialEvents SETS 1681, so the four start hidden and the
  --         always-on row is the only one you see.
  --       - the ELM'S LAB OFFICER (EVENT 1750) already at his post before the
  --         egg errand that brings him in.
  --       - LYRA standing at NEW_BARK_TOWN (1,6) -- the character in the
  --         trees in front of the lab.
  --     The third table is read too: the rows landing inside wVariableSprites
  --     ($d7cc..$d7d6) are sprite slots and the rest are map SCENE bytes, told
  --     apart by ADDRESS -- matched against the MapScenes table rather than by
  --     parsing a symbol name. Three maps open on scene 1 (Goldenrod City,
  --     Bellchime Trail, the Battle Tower approach), and a scene left at 0
  --     arms a cutscene the game considers retired.
  --   * AND THE DAY HAS FOUR PERIODS HERE, NOT THREE. Gold and Crystal have
  --     MORN $01, DAY $02, NITE $04 and the engine had those baked in. The
  --     fourth is NOT appended past NITE: EVE is bit $08 and sits between DAY
  --     and NITE on the CLOCK while NITE keeps $04, so neither the bit nor the
  --     boundary follows from the count. Three tables together say so:
  --       GetValueByTimeOfDay     00:$05b1  boundaries, as `cp` operands
  --       GetTimeOfDay.TimesOfDay 05:$400a  band -> wTimeOfDay
  --       CheckObjectTime's table 00:$1596  wTimeOfDay -> the bit
  --     -> MORN 05:00, DAY 09:00, EVE 17:00, NITE 21:00 -- an hour earlier at
  --     each end than the 4/10/18 the port used. With three assumed, every
  --     object whose byte is $08 was masked at every hour of the day
  --     (floor(8/1), floor(8/2) and floor(8/4) are all even) and the DAY rows
  --     stayed up through the evening. The object filter now takes the bit
  --     from the HOUR through the cartridge's own period list; the period
  --     NAME still feeds the palette and encounter tables, which know Gen 2's
  --     three, so routing the filter through the name would have thrown the
  --     fourth period away again on the way past.
  --   * THE COMMAND TABLE WAS FOUR ROWS TOO GENEROUS AND 16 WIDTHS WRONG.
  --     RunScriptCommand.Jumptable (25:$62f2) holds EXACTLY $DC entries, each
  --     with a Script_<name> symbol -- the ROM's own name for every opcode --
  --     and the table here carried $E0 rows from a fork's const_def run.  The
  --     four phantoms (nooryes, digmod, toggleevent, usepaletteswap) decoded
  --     bytes the ROM never dispatches.  Widths were re-read from the
  --     handlers; the sweep needed two conventions first: `rst $10` is
  --     FarCall with an INLINE `dw addr, db bank`, and bit 15 of the word is
  --     a far-JUMP flag.  Sixteen specs changed; pokepic and cry are
  --     VARIABLE (the form byte exists only when the species byte is
  --     nonzero: GetCurPartyMonSpeciesIfZero skips the read), and givepoke's
  --     trigger byte pulls in six more.  checkmapscene/setmapscene/warpmod/
  --     blackoutmod/warpfacing matter twice: their (group, number) pairs
  --     were never read, so no scene command ever resolved a map -- a big
  --     slice of "step events don't work".
  --   * TWO OBJECT KINDS CRYSTAL DOES NOT HAVE. TryObjectEvent.Jumptable
  --     (25:$5413): kind 3 routes to .trainer beside kind 2, with an
  --     EIGHT-byte header (LoadTrainer_continue, 00:$2ffb, `cp 3` picks 8
  --     over 14) -- unhandled, every gym trainer's header was queued as a
  --     script AND registered as dialogue, which is the scrambled NPC text.
  --     Kind 5 is .command (25:$5473): the object's own sight/pointer/flag
  --     bytes ARE a four-byte inline script.  957 objects: 661
  --     jumptext(faceplayer) NPCs -- "some npcs have no text" was their
  --     dialogue sitting in an operand nothing read -- 191 jumpstd shelves
  --     and counters, 54 fruittree berry trees, 37 pokemart clerks, 8
  --     trades.
  --   * THE SCRIPTS LIST WAS READ AT CRYSTAL'S OFFSETS. extractMapScripts
  --     took the scene/callback list from map_attributes +6/+9 with 4-byte
  --     scenes; polished merged it into the events blob at +7 with 2-byte
  --     scenes.  The garbage pointer usually landed on a small byte, so fake
  --     scene lists decoded and QUEUED -- text blocks walked as scripts,
  --     junk scene ids for the coord-event gate, callbacks that ran nothing.
  --     Desyncs across these three: 1188 -> 105.
  --   * THE RENDER CHARMAP PREFERRED CRYSTAL'S CONSTANTS. gen2FontCharmap
  --     seeded GEN2_CHARMAP first and dedupes first-wins, so every character
  --     polished MOVED kept Crystal's code: "-" is $BC here ($E3 = polished's
  --     "3": "I do be3lieve"), digits are $E0-$E9 (Crystal $F6+), and the
  --     battle menu's <PK><MN> ligature ($E1 $E2) drew "12".  The cartridge's
  --     own charmap now loads first.
  --   * THE BATTLE HUD IS ONE BLOCK. Crystal spreads it over four symbols;
  --     polished folds everything into BattleExtrasGFX -- 32 compressed 2bpp
  --     tiles to VRAM $95f0 = tile $5F, one BELOW the text sheet -- and has
  --     none of the four, so extractBattleHudSheets bailed to placeholders.
  --     The tile identities are PROVEN by the text charmap (<HP2> $64,
  --     <NOHP> $65, <FULLHP> $6D, the halfarrow $6F), and "Lv" is MAIN-font
  --     $D6 (PrintLevel, 00:$3139).  manifest.battleExtrasHud carries the
  --     cut map; the extra text sheet draws from $5F with slots below the
  --     base clipped, which also blanks $7F -- the space glyph -- instead of
  --     leaving a corner tile there (the mid-word dots).
  --   * THE TRAINER CARD WAS THE LZ STREAM DRAWN AS PIXELS, one more raw
  --     read (gen2PlayerFrontPic falling back to ChrisCardPic) routed
  --     through gen2PicBytes.
  --   * AND map_scripts.lua DID NOT LOAD AT ALL: one `return { ... }` is one
  --     LuaJIT prototype, and a 605-map cartridge's scripts blew its
  --     constant table.  Data:load reported the failed pcall as "optional
  --     module missing (feature disabled)" -- no coord events, no NPC
  --     dialogue, with one warn line to show for it.  LuaWriter now splits
  --     big tables into immediately-invoked closures (identical value, own
  --     constant table each); rom-cache bumped to v77 so every cache
  --     rebuilds.
  --   * THE PARTIES, AT LAST. ReadTrainerParty (07:$4000): each trainer is
  --     `db length / name, $53 / db type / mons`, a mon `db level, species,
  --     form` plus fields the TYPE byte's BITS switch on -- item (1), a
  --     DVSpreads INDEX (3, one byte -- WriteTrainerDVs at 58:$5286 is a
  --     table lookup, not raw DVs), personality (4), a $53-terminated
  --     nickname (5), an EVSpreads index (2), four moves (6), in stream
  --     order.  Three more facts made it parse whole: a level byte past 100
  --     is a BADGE-SCALED OFFSET (AdjustLevelForBadges, 0C:$46cf: byte-$B2 +
  --     base -- Giovanni's ace is $CA, and "level 202" used to void his
  --     party); an EMPTY party is a REAL record (the first GRUNTF row is
  --     name-and-type, and breaking on it dropped every Rocket behind it);
  --     and the length byte is the VALIDATOR -- a record parsed right
  --     consumes itself exactly.  908 parties, 2383 mons.  FALKNER ends in
  --     the "er" n-gram, so names now go through the cartridge's charmap
  --     ("Falkn" was the constants-only decoder dropping it).
  --   * COMPRESSED DIALOGUE IS DIALOGUE. The letter-frequency plausibility
  --     sample read polished's n-grams and $5D Huffman streams as noise:
  --     549 of 671 trainer seen/won lines failed the 85% test and their
  --     trainers went SILENT around battles.  On a huffmanText cartridge
  --     the REAL decoder is now the test -- walk the block to a terminator
  --     inside dialogue length and it is dialogue.  698/699 headers carry
  --     their lines now.
  --   * FOUR MORE POINTER KINDS THAT ARE NOT SCRIPTS: callasm and
  --     changemapblocks ("f" -> "D": _UpdateSprites, the bridge callbacks,
  --     the gym trash cans and every *_BlockData table were being decoded
  --     as bytecode), usestonetable ("p" -> "d" + the stone-table reader),
  --     scalltable (a dw TABLE of scripts, expanded like jumptable), and
  --     object kind 4 -- TryObjectEvent.pokemon builds `showcrytext <ptr>`
  --     inline, so the talking Machoke/Jigglypuff/Abra pointers are TEXT.
  --     Desyncs 105 -> 27, and what remains is Battle Tower structure.
  --   * AND NINE MORE LOWERINGS, led by waitendtext (183 sites) and
  --     GIVEBADGE -- polished's own command where Gold runs `setflag
  --     ENGINE_<X>BADGE` (Script_givebadge, 25:$73f7: operand $10+ is
  --     Kanto, xor $18, engine flag = badge + $21).  Unlowered, beating a
  --     gym gave NO badge, so no HM ever unlocked.  Unhandled instructions:
  --     471 -> 162 of 29407, and 53 of those are the TM/HM pocket family,
  --     which needs a machine-number model, not an alias.
  --   * EVERY CAPITAL M DREW THE MALE SYMBOL. The manifest charmap filed
  --     ASCII "M"/"F" for the Nidoran gender codes $BE/$BF -- the GLYPHS
  --     there are the symbols, and the render charmap is first-wins per
  --     sequence, so those two rows hijacked the letters across the whole
  --     game. Fixed at the source (the fix table now files the symbols) and
  --     hardened in gen2FontCharmap: a CONSTANT fallback may no longer land
  --     on a code the cartridge has named -- which also finally unhijacked
  --     "PK"/"MN" from the digits ("FIGHT 12") and "'" from "0". Measured
  --     against all decoded dialogue: zero bare apostrophes and zero
  --     ampersands exist, so the dropped fallbacks cost nothing.
  --   * THE APPROACH CUTSCENES CHECK OUT END TO END in this build: New Bark's
  --     coord event at (1,8) attaches through Gen2ScriptVM.register
  --     ("scenes"), fires on the step, and its script compiles to
  --     g2_turn / g2_move with real movement rows (M29_41C8 is four
  --     step_lefts and a step_end -- Lyra walking over).  The movement
  --     bytecode table was verified against DoMovementFunction's jumptable
  --     (01:$53b4): identical to Crystal's through $4A.  A report of these
  --     not firing on an OLDER import is the map_scripts chunking fix (see
  --     above) not yet applied; the loader now names its real error when a
  --     module fails, so a recurrence will say why.
  --   * THE LETTERS WERE STILL BEING HIJACKED, twice more. $C8 is the
  --     ACCENTED e (the e of "Poke"), filed as plain "e" -- so every e in
  --     the game drew the accent; and Crystal's own e-acute row points at
  --     $EA, polished's CURRENCY glyph, which is the "PoK(money)GEAR"
  --     screenshot. Fixed three ways at once: the manifest files the real
  --     characters, gen2FontCharmap seeds the PLAIN ALPHABET before anything
  --     else can claim a letter, and constant fallbacks stay off
  --     cartridge-named codes.
  --   * "SO, ULTRA BALL!" -- the player's name was the string buffer.
  --     Polished addresses the player through TX_RAM (TextCommand_RAM,
  --     00:$113f, consumes a dw), and the decoder read the operand as
  --     GLYPHS behind a bare {RAM} token; the runtime then fell back to the
  --     shared buffer, which holds the last ITEM name. The polished reader
  --     now decodes control operands (RAM dw -> resolved WRAM symbol,
  --     DECIMAL dw+db, SOUND db, ASM terminates -- Z80 follows it), runs
  --     the same pass over HUFFMAN OUTPUT (the controls ride inside the
  --     stream), prefers WRAM bank <= 1 when naming a target (wStringBuffer3,
  --     not bank 4's wDexMon80Form), and TextBox answers wPlayerName /
  --     wRivalName / wTrendyPhrase directly.
  --   * THE OBJECT SCRIPT IDS ARE 1:1. Crystal's object_const_def opens at
  --     2 and the port hardcoded `slot = index - 1`; polished numbers
  --     objects straight into wMapObjects (GetMapObject, 00:$1556 --
  --     wPlayerObject slot 0, wMap1Object slot 1). One off, every
  --     applymovement landed one object EARLY: the New Bark teacher's
  --     approach ran on hidden Lyra ("the text appears and I walk back but
  --     the lady doesn't run up"), Elm's per-scene moveobject was rejected
  --     outright (id 1 < 2) so he stood at his object-row spot, and Lyra's
  --     lab cutscene drove the wrong objects. field.objectScriptBase now
  --     carries the importer's answer.
  --   * THE TEXTBOX FRAME comes from the ROM's own row table (TextboxBorder,
  --     00:$0e1a): $F8-$FF in the MAIN sheet, with distinct top/bottom rules
  --     and left/right rails -- Crystal's $79-$7E point into the extras
  --     sheet, which here holds battle HUD art (the "dashed" borders were
  --     thin EXP-bar fills). manifest.textBorder -> font.border, and
  --     Font.drawBox grew optional t/b/l/r keys.
  --   * AND THE THREE PLAYER CHARACTERS. There is no KrisPic, so the
  --     Crystal-shaped forms builder returned nil and NEW GAME skipped the
  --     who-are-you step entirely. Chris, Kris and Crys each have a
  --     compressed card pic (the intro pic too -- there is no 7x7), a
  --     compressed back pic, walk and bike sheets (decompressed now --
  --     spritesCompressed), a palette row and ONE default name
  --     (DefaultMale/Female/EnbyPlayerName). forms.order carries the three
  --     keys and OakSpeech builds the menu from it: CHRIS / KRIS / CRYS.
  --   * THE SPECIES TABLES ARE A DIFFERENT LANGUAGE (v80). BaseData is 34
  --     bytes with NO dex-number byte (_GetBaseData 00:$316e copies $22;
  --     the wBase* WRAM mirror names every field: stats open the record,
  --     gender and hatch cycles share ONE packed byte at +12 -- GetGenderRatio
  --     keeps the high nibble, the egg-steps math (03:$5d60) computes
  --     (low+1)*5 -- growth at +16, egg groups +17, FOURTEEN TM/HM bytes at
  --     +20). Crystal's offsets read everything one byte askew: "attack=0,
  --     weight=65472". All layout-keyed now.
  --   * EVOSATTACKS ends BOTH sections on $FF (skip_evos 06:$439f scans for
  --     it) and closes every evolution record with `db species, db form`,
  --     form bit 5 = +256 (extspecies). Methods run 1..10 -- level, item,
  --     trade ($E0 = no held item), holding, happiness, stat, location,
  --     move, crit, party; holding and stat carry two params. Crystal's
  --     zero-terminator reader derailed on Bulbasaur's first record, every
  --     learnset came back empty, and the fallback move -- the FIRST move in
  --     this cartridge's ALPHABETICAL order -- is why "every pokemon only
  --     knows ACROBATICS".
  --   * MOVES ARE 8 BYTES (GetMoveAttr 00:$3558, `ld bc,$0008`): the eighth
  --     is the phys/special/status category and accuracy is PLAIN PERCENT
  --     ($FF = sure-hit, capped at 100). TypeNames is an OFFSET table --
  --     GetTypeName (14:$499a) does `hl = base + type + [base + type]` --
  --     types to 17, ??? at 18, egg-group names sharing the table above.
  --     Surf used to read power 0, type NORMAL, 39% accurate.
  --   * DEX ENTRIES: PokedexDataPointerTable rows are `db bank, dw pointer`
  --     (GetDexEntryPointer adds bc three times), the entry is
  --     `kind@ page1@ page2@` in polished text, and the MEASUREMENTS live in
  --     PokemonBodyData (52:$4549): db height in DECIMETERS, dw weight in
  --     HECTOGRAMS, db shape/color -- converted to the feet/inches and
  --     tenths-of-pounds the dex screen prints. "No data" was Crystal's
  --     2-byte-pointer bank arithmetic landing nowhere.
  --   * BG EVENTS RENUMBER PAST IFNOTSET (BGEventJumptable 25:$549f): 7 is
  --     JUMPTEXT -- the pointer IS the sign's words -- 8 jumpstd (std index
  --     in the dw's LOW byte; the high byte rides a setval), 9 ifnotset
  --     again, and kinds >= $0A are hidden items with the ITEM ID IN THE
  --     KIND BYTE and the flag word sitting in the pointer slot. Crystal's
  --     "7 = hidden item" is exactly "signs give items instead of text".
  --   * ONE SHEET, THREE OBJECTS: SPRITE_BALL_CUT_FRUIT is ball / cut tree /
  --     fruit tree stacked, picked by the OBJECT ACTION in the movement row
  --     (SetFacingCutTree 01:$46cd draws tiles 4-7). The movement table now
  --     records actions, map objects carry `frame`, and NPC/SpriteRenderer
  --     draw that fixed row -- no more POKe BALL trees. Same table renumbers
  --     the rocks: $12 smashable (TryRockSmashFromMenu 03:$4f69), $13
  --     strength boulder, and Crystal's $18/$19 are polished's fixed
  --     SPINNERS -- 71 spinning trainers had become "boulders".
  --   * $DE is "+" ("Press Down{de}B" on the Route 29 tips sign; verified
  --     against the FontNormal tile).
  --   * THE MOVE-EFFECT TABLE IS RENUMBERED (v81). Polished has its own
  --     move_effect_constants, so an effect byte read through Crystal's
  --     static table lands on the wrong effect -- Growl's byte $39 is
  --     Crystal's TRANSFORM_EFFECT, which is the "her Pokemon used Growl and
  --     it said she transformed into my Cyndaquil" report, and most status
  --     and stat moves misfired the same way. The cartridge names its own
  --     effects: MoveEffectsPointers (09:$72b5) is a dw per effect id into a
  --     routine whose pret label IS the effect name (Transform, AttackDown,
  --     DoSleep...). polished_tables reads that byte->label off the ROM and
  --     translates label->engine-effect (MOVE_EFFECT_LABELS); the map rides
  --     the manifest (moveEffects) and the extractor reads through it when
  --     layout.polishedMoveEffects is set. Anything the battle engine does
  --     not implement maps to NO_ADDITIONAL_EFFECT -- plain damage, never a
  --     wrong dramatic effect.
  --   * THE PLAYER-NAME TOKEN was ALREADY CORRECT after the v79/v80 work:
  --     <PLAYER> is charmap $4F, an n-gram-pointer slot resolving to
  --     wPlayerName (_PlaceNgramChar 00:$0e9e, pointer at 00:$3c16 -> $d47b),
  --     the extractor emits {RAM:wPlayerName}, and TextBox resolves it to
  --     save.player.name (never the string buffer). 1052 lines carry it. A
  --     build still showing the last item/mon for the player's name is
  --     reading a pre-fix cache or a save made under one -- a fresh import
  --     (cache rebuilds on the v81 bump) plus a NEW GAME clears it.
  --   * WHAT REMAINS: the 27-desync Battle Tower tail, the TM/HM pocket,
  --     Furret's front pic report, and whatever the next play-test finds.
  --   * WHAT REMAINED before that run: every table reads, and whether they
  --     assemble into a world that loads and walks is a different question
  --     from whether each was read correctly.
  --     So `importable` is now TRUE and `experimental` carries what it used
  --     to say. A closed gate cannot be tested through: the one remaining
  --     question is whether these tables assemble into a world that loads,
  --     and only an import answers it. The panel says BETA and says the
  --     result is unwalked, which is the honest version of the same warning.
  -- See [[polished-crystal-support]].
  polishedcrystal = {
    id = "polishedcrystal",
    generation = 2,
    label = "Polished Crystal",
    displayName = "Pokemon Polished Crystal",
    launcherName = "Polished Crystal",
    sha1 = "6930b48af5844d373e3c9130f26d6dd1084cf4ed",
    manifest = "tools/rom_manifest_polishedcrystal.json",
    cachePrefix = "polishedcrystal/",
    saveSuffix = "_polishedcrystal",
    -- LOCKED DOWN FOR NOW -- "COMING SOON" IN THE LAUNCHER.
    --
    -- The tables all read off the cartridge and the world loads, but a
    -- play-through keeps turning up runtime issues (the move-effect
    -- numbering, the scripted player-name substitution, running shoes,
    -- and more the next session will find), so the version is held back
    -- rather than offered as importable while those are worked through.
    -- `importable = false` refuses the import AND makes the launcher panel
    -- draw the COMING SOON pill with the button disabled
    -- (RomImporter: `withheld` -> `locked`).  Flip this back to true (and
    -- restore `experimental = true` for the BETA pill) once the runtime is
    -- proven on a full run.  POKEPORT_UNLOCK still opens it for local work.
    importable = false,
    -- hold B to run (DoPlayerMovement's .run branch); see Player.beginStep
    hasRunning = true,
  },
}

-- Launcher column order.
GameVersion.ORDER = { "red", "blue", "yellow", "gold", "silver", "crystal",
                      "prism", "polishedcrystal" }

GameVersion.current = "red"

function GameVersion.set(id)
  GameVersion.current = GameVersion.VERSIONS[id] and id or "red"
  return GameVersion.current
end

function GameVersion.get()
  return GameVersion.current
end

function GameVersion.generation(id)
  local info = GameVersion.info(id)
  return info and info.generation or 1
end

function GameVersion.isGen1(id)
  return GameVersion.generation(id) == 1
end

function GameVersion.isGen2(id)
  return GameVersion.generation(id) == 2
end

function GameVersion.isBlue()
  return GameVersion.current == "blue"
end

function GameVersion.isYellow()
  return GameVersion.current == "yellow"
end

function GameVersion.isGold()
  return GameVersion.current == "gold"
end

function GameVersion.isSilver()
  return GameVersion.current == "silver"
end

-- Crystal shares the Gen2 engine with Gold/Silver but not its script opcode
-- table, so anything that decodes ROM bytecode has to branch on this.
function GameVersion.isCrystal(id)
  return (id or GameVersion.current) == "crystal"
end

-- Metadata for a version id, defaulting to the active one.
function GameVersion.info(id)
  return GameVersion.VERSIONS[id or GameVersion.current]
end

function GameVersion.saveSuffix(id)
  return GameVersion.info(id).saveSuffix
end

function GameVersion.cachePrefix(id)
  return GameVersion.info(id).cachePrefix
end

-- Does this version accept that ROM hash?  Most versions have exactly one
-- canonical dump; Crystal has two revisions that decode identically here.
function GameVersion.acceptsSha1(id, sha1)
  local info = GameVersion.info(id)
  if not info then return false end
  if info.sha1 == sha1 then return true end
  for _, alt in ipairs(info.sha1Alt or {}) do
    if alt == sha1 then return true end
  end
  return false
end

-- The version a ROM belongs to, by its SHA-1, or nil for an unknown ROM.
function GameVersion.forSha1(sha1)
  for id in pairs(GameVersion.VERSIONS) do
    if GameVersion.acceptsSha1(id, sha1) then return id end
  end
  return nil
end

return GameVersion
