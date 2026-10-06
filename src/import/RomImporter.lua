local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local HostShell = require("src.core.HostShell")
local SafeArea = require("src.core.SafeArea")
local Platform = require("src.core.Platform")
local GamepadMap = require("src.core.GamepadMap")
-- Breadcrumbs through the constructor (src/core/BootTrace.lua).  This is the
-- largest thing that runs before the first frame on a phone, and when the
-- process dies inside it there is nothing on screen and nothing in any log to
-- say how far it got.
local BootTrace = require("src.core.BootTrace")
-- Pure and dependency-free (it decodes one options field), so it can be
-- required up here beside the rest of the launcher's own modules -- unlike
-- src/mods/LauncherMods.lua, which reaches for love.filesystem and stays lazy.
local ModGens = require("src.mods.ModGens")

local RomImporter = {}
RomImporter.__index = RomImporter

-- love.system.pickFile is a NATIVE BRIDGE, not part of LÖVE: it exists only on
-- builds that compiled one (Android, and iOS builds patched by
-- mobile/ios/patch_love_src.py). A build without it must fall back to the
-- copy-it-into-the-save-folder flow that every caller below already has --
-- calling the nil field instead took the whole app down the moment the player
-- pressed Import ROM:
-- force build
--   src/import/RomImporter.lua: attempt to call field 'pickFile' (a nil value)
--
-- love.system.createFile was already guarded this way at its one call site;
-- these three were not. Every caller here treats `false` as "no picker
-- available" and shows its own notice, so a missing bridge now degrades to
-- exactly the path a picker-less Android device has always taken.
local function pickFile(...)
  local fn = love.system.pickFile
  if not fn then return false end
  return fn(...) and true or false
end

-- Android folder picker for the game-data / mods install path.  Same bridge
-- pattern as pickFile: the dialog is a separate UI, and the chosen path lands
-- later as picked_folder.txt in the save identity (see GameActivity).
local function pickFolder()
  local fn = love.system.pickFolder
  if not fn then return false end
  return fn() and true or false
end

-- v17: Force a fresh Gen2 re-import after tileset registry and map-id fixes.
-- v32: item ItemAttributes property bits (CANT_SELECT / CANT_TOSS).
-- v33: shiny half of each PokemonPalettes row (MON_<id>_SHINY).
-- v34: SPRITE_MON_nnn defs for every species, for the day-care yard.
-- v35: trainer class pics bake their TrainerPalettes colors on every
--      platform (ImageWriter.recolorShades no longer keys on float
--      equality, which missed on Android and left the pics DMG grey).
-- v36: warps are decoded from the cart's MapEvents instead of the scaffold,
--      which now ships empty so no map geometry is committed.
-- v38: `writecmdqueue` resolves its CMDQUEUE_STONETABLE rows, so a Strength
--      boulder pushed onto a hole knows which script to run (Ice Path,
--      Blackthorn Gym).
-- v39: UnownFont + UnownWords for the Pokédex's UNOWN MODE.
-- v40: UnownWords are tile ids, not charmap text, and the font rip keeps the
--      ROM's stored polarity.
-- v41: battle animation `anim_loop` rows carry their jump target.
-- v42: Gen2 map defs carry their MapGroupPointers (group, number) pair, which
--      is what a Gold/Silver battery save stores as the player's location
--      (src/save_convert/Gen2Save.lua).
-- v43: field.engineFlags (the EngineFlags address/bit rows) and
--      field.spawnFlags (wVisitedSpawns bit -> map), so an imported battery
--      save carries every ENGINE_* flag and its FLY destinations.
-- v44: battle animation framesets stop at `oamdelete` ($FC) and carry
--      `oamwait` ($FD) rows as blanks instead of reading both as OAM ids.
-- v45: two Crystal-only additions.  field.playerForms carries KRIS's whole
--      asset set (card portrait, intro pic, back pic, default names) so the
--      Oak speech can ask boy/girl, and pokemon[*].picAnim plus
--      assets/generated/battle/anim/*.png carry the front-pic frame
--      animations.  Neither exists in a v44 cache, and without this bump
--      isReady() calls that cache current and the import never re-runs.
-- v46: picAnim for real.  A v45 cache has the playerForms half but NO
--      pokemon[*].picAnim and no assets/generated/battle/anim: the
--      extractor's animation-script reader was named gen2AnimScript, which
--      this file already used for battle MOVE animations, and the later
--      definition silently won -- so every species came back empty.  A v45
--      marker has to be treated as stale or that empty result sticks.
-- v47: Crystal tileset identity.  gen2TilesetNames matched Tilesets entries
--      on the GFX pointer alone, and in Crystal six families share
--      TilesetRuinsOfAlphGFX while TilesetJohtoModern shares its GFX with
--      TilesetBattleTowerOutside -- so every Ruins of Alph map was imported
--      with TilesetAerodactylWordRoom's blocks AND collision (glitched art,
--      and no walkable exit in the inner chamber / item rooms) and every
--      JOHTO_MODERN map (Azalea Town, Goldenrod, Routes 33/34) with
--      TilesetBattleTowerOutside's.  A v46 cache has the wrong blocks baked
--      into data/generated/tilesets.lua and the wrong tileset name baked into
--      data/generated/maps.lua, so it has to be treated as stale.
-- v48: three more things baked into a v47 cache are wrong.
--      * maps[*].mapPalette did not exist, so every indoor map and the Ruins
--        of Alph chambers followed the clock into the NITE palette row
--        instead of the PALETTE_DAY their header forces.
--      * map_scripts.varSprites came back EMPTY on Crystal (the
--        InitializeEventsScript scan looked for Gold's variablesprite opcode
--        $6C and bailed at Crystal's $6D), which is why Route 36's Sudowoodo
--        and Route 37's Twins Ann & Anne -- both wVariableSprites slot 4 --
--        drew as placeholders.  Crystal's initial-event set was truncated at
--        the same byte.
--      * every decoded `getstring` has a byte-swapped string pointer, so the
--        EXPN CARD / RADIO CARD / GEAR / EGG / COIN lines printed a stale
--        buffer.  The literal is resolved at extract time now.
-- v49: a Gen2 tileset is 192 tiles in TWO VRAM banks, and the metatile bytes
--      that reach the second one ($80-$DF) were being read as literal tile
--      numbers.  Both data/generated/tilesets.lua's blocks and its palMap are
--      re-keyed to a flat 0..191 index now, so a v48 cache draws Ecruteak's
--      building fronts, the Burned Tower roof and Elm's desk as blank or
--      garbage until it is rebuilt.  25 of Crystal's 37 tilesets are affected.
-- v50: field.gen2TreeMons was read with Gold's TreeMons pointer-table shape on
--      both ROMs.  A v49 Crystal cache has no sets 3-7 at all -- so the nine
--      set-3 routes (29/30/31/34-39), Routes 26/27/32, Route 43, Lake of Rage
--      and Ilex Forest have no headbutt table to roll against -- and files
--      TreeMonSet_Route as the rock-smash list.
-- v51: the two player characters wore each other's colours.
--      * registerGen2KrisSprites' skip guard was `sprites[id] and nil or
--        spriteDefFor(...)`, which in Lua is just `spriteDefFor(...)` -- so it
--        overwrote Crystal's real SPRITE_KRIS / SPRITE_KRIS_BIKE (rows 96/97,
--        OBJ palette 1, blue) with a clone of Chris's row 1 on palette 0.  A
--        v50 cache has no sprite at index 96 at all.
--      * the boy's gender-select pic was left for the SGB zone shader to
--        colour instead of being baked from PlayerPalette, so Chris showed up
--        purple and white.
-- v52: field.gen2BugContest -- the Bug Catching Contest's own encounter table
--      (ContestMons), the nine AI contestants with their score picks, and the
--      20 Park Balls / 20 minutes the ROM hands out.  A v51 cache has none of
--      it, so the contest has nothing to roll against.
-- v53: field.gen2BattleTower -- Crystal's Battle Tower.  The 70 trainers with
--      their classes, genders and overworld sheets; the ten level groups of 21
--      opponents each, with the DVs and stat exp that make their stat blocks
--      the cartridge's own; the male and female line pools; the party rule
--      texts and the two menus.  A v52 cache has none of it, so the tower's
--      scripts have nothing to roll an opponent from.  Gold and Silver have no
--      Battle Tower at all, but they share the marker, so they re-import once
--      too.
-- v54: the player's name in Gen2 dialogue.  Inside a TX_START run the byte
--      $14 is PlaceGenderedPlayerName -- the player's name -- not the
--      TX_STRINGBUFFER command it is at the outer level, so 691 lines carried
--      "{RAM:wStringBuffer1}" where the name belonged and printed whatever the
--      player last picked up ("ELM: POKeGEAR / There you are!").  The operand
--      byte it wrongly ate was usually the "!" after the name.  A v53 cache
--      has the broken text baked into data/generated/text.lua.
-- v55: CHRIS's trainer card portrait and battle back pic, baked in
--      PlayerPalette as battle/chriscard.png and battle/chrisback.png.  The
--      boy form declared trueColor while pointing at the plain four-shade
--      chrisf.png / chrisb.png rips, so the renderer left them alone and both
--      drew in black and white.
-- v56: field.egg.pic.  EggPic decompresses to 47 tiles in Crystal -- 25 of pic
--      and 22 of appended animation frames -- so the "the tile count must be a
--      perfect square" rule threw, field.egg came out with no pic key, and an
--      EGG's stats page drew nothing.  Now read as a declared 5x5 and baked in
--      the egg's own palette.
-- v57: the rest of the v54 player-name fix.  v54 corrected the texts reached
--      through a manifest symbol, but gen2RegisterScriptText -- the path every
--      writetext/jumptext operand takes, and so every line an NPC actually
--      speaks -- skipped the leading $00 before storing the address.  That is
--      TX_START, the byte that opens the PlaceString run where $14 is the
--      player's name, so 152 script texts kept printing the last item picked
--      up where the name belongs.  decodeGen2TextAt now also seeds its mode
--      from the first byte, so a mid-run address decodes correctly whoever
--      hands it over.
-- v58: battle_anims.functions.  DoBattleAnimFrame's 80-entry jumptable was
--      read at Gold's hardcoded $4F1D; Crystal's is at $4FCE, and Crystal's
--      symbols name none of those routines, so the table came out EMPTY.  With
--      no name to look up, every animation object fell through
--      Gen2AnimPlayer's MOTION table to "Null" and stayed exactly where the
--      script spawned it -- no move animation travelled anywhere on Crystal.
--      The address now comes from the symbol and the names from a baked
--      table-order list.
-- v59: two more Gold-shaped assumptions.
--      * object_event sprite bytes $F0 and up are wVariableSprites SLOTS, and
--        naming them after a sheet (SPRITE_ROCKET for $F6) pinned the object to
--        that sheet for the whole game.  $F6 defaults to the Rocket and a
--        script reassigns it to SILVER, so the rival in Azalea Town turned up
--        as a Team Rocket grunt.  They now carry the slot's own constant name,
--        which NPC.lua resolves through save.gen2VarSprites.
--      * field.overworldFx.healMachine.gen2ObjPal came from MapObjectPals[6],
--        but HealMachineAnim.LoadPalettes copies its OWN four colours over
--        palette 6 first -- so the Poke Balls were reading the green tree
--        palette instead of ball red.
-- v60: every Crystal Pokedex entry.  Gold computes the entry's bank as
--      `$68 + group` and really does end GetDexEntryPointer with `add a, $68`;
--      Crystal replaced that with a four-byte lookup ($60, $6E, $73, $74)
--      because its entries are no longer in consecutive banks.  Reading
--      Crystal with Gold's arithmetic put all 251 entries in the wrong bank --
--      VENONAT's came out as Brock's BOULDERBADGE speech.
-- v61: headbutt never dropped a Pokemon.  GetTreeMons (2E:$42D2) is `cp $08 /
--      jr nc, .quit` then `and a / jr z, .quit` -- SEVEN sets are reachable
--      (1 Canyon, 2 Town, 3 Route, 4 Kanto, 5 Lake, 6 Forest, 7 Rock) -- but
--      the extractor kept only sets 1-3 and read index 3 as the rock-smash
--      list.  Index 3 is Route, which TreeMonMaps assigns to NINE maps
--      (Routes 29/30/31/34/35/36/37/38/39, i.e. most of the early game), and
--      Kanto, Lake and Forest were dropped outright -- so Routes 26/27/32,
--      Route 33, Route 42/43, Lake of Rage and Ilex Forest had no table
--      either.  Every one of those maps rolled against a nil set and could
--      only ever answer "Nope. Nothing…".  Rock is set 7 and TreeMonSet_Rock
--      now pins it; it is also the last table in the bank and has no rare
--      half, so the rare read is skipped for it rather than walking on into
--      GetTreeMon's own code.
-- v62: audio.battle carried four themes; PlayBattleMusic (11:$6E6C) picks
--      eleven.  Missing were the rival theme (classes RIVAL $09 and $2A),
--      the Rocket theme (classes $1F and $42), the two Kanto themes and the
--      night-time wild theme -- so Silver, Team Rocket and every Kanto
--      trainer all fought to Music_JohtoTrainerBattle, Kanto gym leaders
--      to the Johto gym theme, and night battles to the day song.
-- v63: map_scripts.phone rows now carry the contact's own map (bytes 3 and 4
--      of the PhoneContacts row).  GetAvailableCallers (36:$40DE) compares it
--      against wMapGroup/wMapNumber to drop a contact who is standing on the
--      map you are on, and RandomPhoneWildMon (0A:$651F) reads that map's
--      grass table for the species its line names.  A v62 cache has neither,
--      so no trainer can ring in and the wild-mon lines have no species.
-- v64: field.gen2Trades -- the seven in-game trades.  NPCTrades (3F:$4E58) is
--      seven 32-byte rows (dialog set, the species wanted, the species given,
--      the nickname, the DVs, the OT id and name, the gender required), and
--      TradeTexts (3F:$4F53) is the five kinds of line times four dialog sets
--      that PrintTradeText indexes.  A v63 cache has none of it, so the
--      `trade` script command -- which was not lowered either -- had nothing
--      to work from and every trade NPC in the game stood silent.
-- v65: three more Gold-shaped or byte-order faults, all in the extractor.
--      * StdScripts was walked as 46 rows, which is GOLD's count.  Crystal has
--        FIFTY-TWO, and the six it adds -- GymStatue2Script, ReceiveItemScript,
--        ReceiveTogepiEggScript, PCScript, GameCornerCoinVendorScript and
--        HappinessCheckScript -- were dropped, so a `jumpstd` to any of them
--        ran nothing.  The count now comes off the table's own first pointer.
--      * `farjumptext`'s operand was typed as a far SCRIPT pointer, so the
--        extractor disassembled the text as bytecode and the operand came out
--        as a script label.  Every bookshelf, sign, window and trash can in
--        Crystal reaches its line through one of those eleven std scripts.
--      * Battle Tower opponents' stat blocks were read one 16-bit field early
--        AND little-endian, so the first L10 opponent had 10496 HP and 6400
--        defense instead of 41 and 24 -- nothing the player did could dent it.
-- v66: field.gen2UnownWalls -- the four words carved into the Ruins of Alph
--      chamber walls.  UnownWalls (22:$6EBC) is four $FF-terminated runs of
--      tile ids and MenuHeaders_UnownWalls (22:$6ED5) is the window each one
--      opens in; DisplayUnownWords, the special the wall scripts run right
--      after "Patterns appear on the wall!", had neither, so the line printed
--      and the writing it announces never appeared.
-- v67: field.gen2OddEggs -- Crystal's fourteen Odd Eggs.  OddEggs (7E:$756E)
--      is fourteen 59-byte records in the battle_tower_mon shape (a 48 byte
--      party_struct then an 11 byte "EGG"), seven species listed twice with
--      the second of each pair carrying the shiny DV pair, and
--      OddEggProbabilities (7E:$7552) is the fourteen cumulative thresholds
--      _GiveOddEgg rolls a 16-bit Random against.  Neither was extracted and
--      `special GiveOddEgg` had no handler, so the DAY-CARE MAN gave his whole
--      speech and the egg never arrived.
-- v68: two corrections and one addition.
--      * MenuHeaders_UnownWalls is Y FIRST.  Word 0's row is $40 $04 $03 $09
--        $10, and only y1 4 / x1 3 / y2 9 / x2 16 gives a window wide enough
--        for six two-tile glyphs -- which is what _CopyWord wants, since its
--        loop ends each glyph with `inc hl / inc hl`, two COLUMNS.  Read the
--        other way round the wall writing came out as a totem pole.
--      * field.gen2MomBank -- Mom's thirteen banking lines.  MomScript's
--        `checkevent $40` branch is `setevent $40 / special BankOfMom /
--        waitbutton / closetext / end` with no writetext in it at all, so
--        without the special AND its text she simply said nothing.
-- v69: field.gen2TileAnim -- SPROUT TOWER's swaying pillar.  TilesetTowerAnim
--      (3F:$427F) is ten `dw <ptr>, AnimateTowerPillarTile` rows and each ptr
--      is `dw <VRAM dest>, dw <frames>`, so one animation step rewrites TEN
--      tiles at once ($5D $5F $4D $4F $3C $2C $3D $3F $2D $2F).  The routine
--      (3F:$4645) takes `wTileAnimationTimer & 7` through the offset table
--      0, 16, 32, 48, 64, 48, 32, 16 -- five 16-byte frames played
--      1 2 3 4 5 4 3 2, the sway going out and coming back again.  Extracted
--      as one 80x40 strip (ten columns, five rows) to
--      assets/generated/tilesets/towerpillar.png.  Nothing read that table
--      before, so the tower's central support stood perfectly still.
-- v71: overworld sprite sheets were being sized from the sprite_header's
--      length byte, which is the VRAM ALLOCATION and not the sheet.  Every
--      walking sheet is declared at half its real size (pokecrystal:
--      `overworld_sprite ChrisSpriteGFX, 12, WALKING_SPRITE` = 192 bytes,
--      gfx/sprites/chris.png = 16x96 = 384), so every one of them extracted
--      as 3 frames instead of 6, `walker` went false, and the player and
--      every NPC in Gold, Silver and Crystal SLID instead of walking.
--      A v70 cache holds those half-height PNGs, so the extractor fix alone
--      changes nothing until the sheets are re-extracted -- which is what
--      this bump is for.  See src/import/RomExtractorGen2.lua's
--      gen2OverworldSprites.
-- v72: field.fishGroups is keyed by the FISHGROUP_* CONSTANT now, not by the
--      row number.  `Fish` runs GetFishGroupIndex (`dec d`) before indexing
--      FishGroups, so row 0 is FISHGROUP_SHORE = 1 -- and the map header byte
--      the runtime looks a group up with is the constant.  Off by one, every
--      map in the game fished the NEXT group's table: Olivine served OCEAN,
--      the Lake of Rage served DRATINI_2, Ilex Forest's Super Rod could land a
--      DRAGONAIR, Corsola and Dratini were uncatchable, and Routes 12 and 13
--      indexed past the end and never got a bite at all.  A v71 cache holds
--      the old keys, so this bump is what makes the fix reach a save.
-- v73: field.overworldFx gains the Gen2 fishing pose and rod (redFishFront /
--      redFishBack / redFishSide / fishingRod from FishingGFX and
--      FishingRodGFX).  Those keys only ever had Gen1 values, so on
--      Gold/Silver/Crystal the player fished in the plain walking sprite with
--      no rod on screen.
--
--      This bump is ALSO the fishing-table safety net.  A cache written before
--      gen2Fishing existed has no field.fishGroups at all, and the runtime then
--      falls through to the Gen1 `fishing` table -- which a Gen2 manifest does
--      not carry -- so every rod on every map answers "Not even a nibble!".
--      That is indistinguishable from the off-by-one v72 fixed, and it is what
--      a stale cache still does.  Re-extracting is the only cure, and the
--      extractor now warns instead of failing silently.
-- v74: two sheets that only the Gen1 extractor ever wrote.
--      * assets/generated/battle/balls.png -- the party ball row's four icons
--        (healthy / statused / fainted / empty), from LoadBallIconGFX.gfx.
--        BattleState:drawBallRow has always wanted it and the coordinates were
--        always right; without the file the image load failed, ballQuads
--        latched false, and BOTH ball rows drew nothing -- so a trainer battle
--        never showed how many Pokemon the foe had left.
--      * playerForms[*].fish -- the three fishing-pose strips per CHARACTER.
--        LoadFishingGFX picks between FishingGFX and KrisFishingGFX off
--        wPlayerGender, and Kris was fishing on Chris's sprite because the
--        pose lived in overworldFx, which has one slot.
-- v75: five Gen2 move effects stopped being aliased onto Gen1 names that threw
--      their weather rules away, and the sandstorm upkeep animation got an id.
--      * $97 EFFECT_SOLARBEAM was CHARGE_EFFECT -- so Solar Beam never skipped
--        its charge turn in sun and was never halved in rain.
--      * $98 EFFECT_THUNDER was PARALYZE_SIDE_EFFECT2 -- the 30% paralysis was
--        right, but Thunder never always-hit in rain nor dropped to 50% in sun.
--      * $84/$85/$86 EFFECT_MORNING_SUN / SYNTHESIS / MOONLIGHT were all
--        HEAL_EFFECT, a flat half of max HP, so the clock and the weather (the
--        whole point of those three moves) did nothing.
--      * battle_anims.misc gains inSandstorm = 267 (ANIM_IN_SANDSTORM, $10b),
--        the animation the end-of-turn sandstorm hit plays.
--      Rain Dance, Sunny Day and Sandstorm themselves needed no cache change:
--      their effect names were already correct, there was simply no handler --
--      which is why they printed "But, it failed!" every time.
-- v76: two script-decoding fixes and one new table.
--      * GOLD ONLY, and it is the serious one: `getnum` was declared as TWO
--        operand bytes.  pokegold's macro is `db \1 ; string_buffer` and
--        nothing else, exactly like Crystal's, so the decoder over-read by one
--        byte and every Gold script DESYNCED from its first getnum onward.
--      * src.gen2BugContest gains contestantFlags -- the ten event-flag ids
--        from BugCatchingContestantEventFlagTable, which
--        SelectRandomBugContestContestants needs to pick the five entrants.
--        They differ between Gold (1121+) and Crystal (1146+), so they have to
--        be read off the cartridge rather than hardcoded.
-- v77: polished crystal -- ROM font sheets, BattleExtras HUD, the 220-entry
-- opcode table with handler-verified widths, kind-3/kind-5 objects, the
-- layout-driven scripts list, initial events, day periods, and the chunked
-- LuaWriter -- every generated file changes, so every cache must rebuild.
-- v78: the $BE/$BF charmap rows carried "M"/"F" instead of the gender
-- symbols and hijacked the letters; the fix lives in the manifest charmap,
-- which is baked into the generated text and font records.
-- v79: the accented-e charmap row, text-command operand decoding (TX_RAM
-- and friends), the ROM-derived textbox border, three player forms, and
-- the 1:1 object script ids -- text, font and field records all change.
-- v80: polished crystal's SPECIES-DATA layouts, read off the cartridge:
-- the 34-byte no-dex-number BaseData (stats/types/growth/packed gender all
-- layout-keyed), $FF-terminated species-word EvosAttacks (real learnsets
-- instead of the ACROBATICS fallback), 8-byte move rows with the category
-- byte and plain-percent accuracy, offset-table TypeNames, 3-byte dex
-- pointers + PokemonBodyData measures, the bg-event renumbering (kind 7 is
-- jumptext, items ride the kind byte), movement-table actions (cut trees
-- draw the tree frame, $12/$13 are the real rocks, $18/$19 spinners), and
-- the "+" charmap row -- pokemon, moves, maps, map_scripts and text all
-- change.
-- v81: polished crystal's MOVE-EFFECT numbering, read off MoveEffectsPointers
-- (09:$72b5) instead of Crystal's static table -- Growl's effect byte $39 was
-- Crystal's TRANSFORM_EFFECT, so status/stat moves misfired ("used Growl,
-- transformed into Cyndaquil"); moves.lua changes for every affected move.
-- v104: Emerald's move rows gained `highCrit` (effect 43/200/209), and the
-- three effect numbers the Gen 2 join named behaviourally wrong got their
-- pret names -- 196 EFFECT_LOW_KICK (was FLINCH_SIDE_EFFECT2, and Gen 3's
-- Low Kick is weight-based with power 1), 43 EFFECT_HIGH_CRITICAL (was
-- NO_ADDITIONAL_EFFECT) and 104 EFFECT_TRIPLE_KICK.  moves.lua changes.
-- v105: the bike terrain -- every tileset pair gained muddySlopeBehaviour
-- ($D0) and acroObstacles ($D1/$D3-$D6), and constants gained gen3Bike.
-- tilesets.lua and constants.lua change.
-- v106: MB_MT_PYRE_HOLE joins the fall-through holes (it was warping as a
-- door), and every tileset pair gained escalatorBehaviours ($6A/$6B).
-- tilesets.lua and constants.lua change.
-- v107: constants gained gen3MetatileText (the wall region map, the
-- television and the running-shoes booklet) and gen3Questionnaire -- the four
-- lines no script in Hoenn references, because only C code prints them.
-- v108: the water currents south of Pacifidlog (currentBehaviours,
-- constants.gen3Currents) and the ground the RUNNING SHOES refuse
-- (noRunBehaviours, constants.gen3NoRunning).  tilesets.lua and
-- constants.lua change.
-- v109: constants gained gen3WeatherNames and gen3BattleWeather -- the map
-- header's weather byte had no name anywhere in the engine, so the 90 maps
-- that set one were all clear skies.  constants.lua changes.
-- v110: every item row gained `keyItem` (gItems[].importance ~= 0).  The bag
-- and the mart have always asked for that name and Gen 3 wrote only the
-- number, so every key item in Hoenn could be tossed and sold.  items.lua
-- changes.
-- v111: constants gained `badges` -- Hoenn's eight, under the flag names the
-- save writes them as.  Without it Badges.list fell back to KANTO'S eight and
-- the trainer card showed no badge ever earned.  constants.lua changes.
-- v112: the ART FINALLY REACHES THE ENGINE.  Every species row gained
-- spriteFront/spriteBack/spriteShiny (the pictures were written on every
-- import and no row named them, so Sprites.path answered nil for all 386 and
-- there was no mon on the battle screen, the summary, the party or the dex);
-- every trainer row's `pic` is now the PATH rather than the raw
-- gTrainerFrontPicTable index, which the image cache could not use; and
-- constants.gen3Bag is MERGED by its two writers instead of the later one
-- wiping the earlier one's picture.  pokemon.lua, trainers.lua and
-- constants.lua all change.
-- v167: the round of Emerald parity that starts with the box wallpapers.
-- constants gained gen3BoxWallpapers (all thirty-two, plus the rectangle they
-- go in and the grid that sits on them) and assets/generated/storage/ gained
-- their thirty-two pictures; gen3SpritePriority (the elevation-to-priority
-- tables and the field's background priorities, which is what puts a walker
-- ON a bridge instead of under it); gen3GabbyAndTy; gen3AbnormalWeather; and
-- gen3PCMenu gained `orders`, `screen` and `multichoice`.  map_scripts gained
-- the script the field runs for a PC, which no map header names.  A cache
-- built before this has none of the art and none of the records, so the box
-- screen draws a flat rectangle and the storm never appears -- which is why
-- this is a bump rather than a note.
-- v168: the "!" bubble, and the two beside it.  An emote is NOT a field
-- object -- it is a field EFFECT, and its picture is reached only by
-- disassembling the native the effect script calls -- so the three overworld
-- emotes (exclamation, question, heart) had no art anywhere in the cache and
-- every startled trainer, every wondering NPC and every Pokemon in love drew
-- the Game Boy sheet's bubble instead.  constants gained gen3Emotes and
-- assets/generated/overworld/ gained the three pictures.  Nothing but a fresh
-- import can produce them, which is what makes this a bump.
-- v169: THE DECORATIONS -- all 121 of gDecorations, found by its own shape
-- (121 records of 32 bytes whose first byte is the record's index) because no
-- symbol names it.  constants gained gen3Decorations: the name, price, shape,
-- permission, category and description of every one.  Without it `checkdecor`
-- answered "you own none" to every script that hands one over,
-- `bufferdecorationname` printed a hole, and `adddecoration` recorded a number
-- nothing could read back.  A cache built before this has no catalogue at all,
-- so this is a bump.
-- v170: FLASH.  constants gained gen3Flash -- the nine radii, the two levels a
-- cave uses and the screen centre the circle is drawn on, all read off the
-- cartridge's own window setter and SetDefaultFlashLevel.  A dark cave in
-- Hoenn is a black window with a hole in it, not the Game Boy's flat shade,
-- and without this record the field has no radius to cut and falls back to
-- leaving the cave lit.
-- v171: the POKEMON CENTER'S HEALING MACHINE, which is a field effect rather
-- than the OAM table the Game Boy importers read -- two sprites made by machine
-- code and placed by four immediates inside it, so nothing on the machine ever
-- lit up in Hoenn.  constants gained gen3HealMachine and
-- assets/generated/overworld/ gained the glow and the monitor's two frames.
-- Where they go is measured from the player's own cell, and that point comes
-- from the FLASH circle's centre in the record above -- so this needs v170's
-- data as well as its own.
-- v172: THE ROTATING GATES, which is the data half of Fortree Gym's puzzle and
-- the Trick House's sixth room -- nineteen gates the port did not have, so the
-- sixth Gym was a walk across an empty floor.  constants gained
-- gen3RotatingGates: where each gate stands, which of the eight shapes it is,
-- which way it faces, and what each shape's arms reach.  The puzzle itself --
-- walking into an arm, the turn, the collision -- is the next slice; this is
-- the part that cannot be guessed.
-- v173: SLATEPORT'S TRAINER FAN CLUB -- eight members and a counter packed
-- into one halfword, read off the four specials that use it, plus the six
-- names behind its two switches.  Sixty-four call sites in one building said
-- "I'm a big fan of ." before this.  constants gained gen3FanClub, and
-- gen3StartMenu gained `pokenavFlag` -- the flag the cartridge's row builder
-- actually tests, since the name the port had could never be true.
-- v174: WHICH TRAINERS FIGHT TWO AT A TIME.  A map object already carried the
-- trainer it fights; it now also carries the trainerbattle MODE that starts
-- the fight (gen3TrainerKind).  Modes 4, 6, 7 and 8 are the double battles,
-- and CheckTrainer (0B3D6E) reads that same byte off the object's script to
-- decide that one twin alone is already a double and no partner should be
-- looked for.  Without it nothing on the sight path could tell a twin from
-- anybody else.
-- v175: WHERE EVERYTHING IN A BATTLE STANDS -- and one panel that has been
-- wrong in every single battle since the HUD stage was written.  There are
-- FIVE distinct healthbox blobs in the sheet run, not two: the player's
-- single-battle box is 4096 bytes (two 64x64 sprites, and the only one with
-- an EXP bar), and the stage filtered on 2048 -- so it threw that one away
-- and saved the DOUBLES box as `player.png`.  The EXP bar art was never
-- extracted at all, and the opponent was decided by a table.sort on two
-- equal tags, which Lua does not define an order for.  All five are now
-- named by size and tag the way the load site at 05DFFC names them.
-- constants gained gen3BattlerCoords: sBattlerCoords (0525F58) for where the
-- four Pokemon stand, and the six healthbox places read back off the
-- instructions InitBattlerHealthboxCoords (072B18) loads them with.  The
-- single-battle foe comes out at x=176, which is exactly the platform centre
-- the placement test scans out of the drawn background -- code and art
-- agreeing on one number.
-- v176: THE PARTY MENU'S OWN SCREEN.  Reported from play: "still missing the
-- background and pokemon tiles for the emerald pokemon party menu".  The
-- icons were ripped a while back; the screen they sit on never was, and
-- Gen3PartyMenu.lua said so in its own header -- "RECONSTRUCTED, not
-- derived: the panels".  Six boxes this port drew itself, at coordinates it
-- chose itself, on a flat fill.  constants gained gen3PartyMenu: the 62-tile
-- sheet, its 32x32 tilemap and all ELEVEN palettes; the five panel maps
-- (wide, narrow, an egg variant of each, and the empty slot) which are
-- arrays of tile INDICES rather than pictures; the ball that sits behind
-- each icon and opens on the cursor slot; and the two tables that say where
-- everything goes -- sPartyMenuWindowTemplates in tiles and
-- sPartyMenuSpriteCoords in pixels, stepping three and twenty-four
-- respectively, which is the same pitch read two ways.
-- v177: FOUR THINGS THE PORT COULD NOT DO, AND ONE IT DID WRONG.
--
-- THE SEALED CHAMBER.  Reported: "make sure the sealed chamber event works to
-- unlock the regi doors, it is a prerequisite".  It is, and this port had no
-- DIG braille wall at all -- so flag $8AF was never set, the inner room was
-- unreachable, $E4 was never set, and the ON_LOAD of Routes 105, 111 and 120
-- kept writing an impassable metatile ONTO THE WARP CELL of each ruin.  All
-- three Regis were walled off from outside, forever.  gen3RegiChambers gained
-- `sealedChamber`, decoded from DoBrailleDigEffect -- whose six tiles are the
-- Regi door's own, which is what proves it is the same door.  gen3FieldMoves
-- gained DIG, which is a TM and therefore has no badge, which is why the
-- HM-keyed table never had it.
--
-- MAP SEAMS.  Two edges in Hoenn carry TWO connections -- Route 111's west
-- and Route 124's east -- and only the first was kept, so both were one-way:
-- the neighbour was drawn across the seam and could not be entered.  Every
-- connection is now kept in ROM order and selected the way
-- IsCoordInIncomingConnectingMap does, by which strip covers the player.
--
-- THE POKeDEX ROW.  The lab really does set $861; the start menu asked
-- `Flags.hasPokedex`, which answers for the Game Boy names.  Both gated rows
-- are now read off BuildStartMenuActions itself.
--
-- THE REGION MAP knows what is under the cursor.  GetMapSecIdAt indexes a
-- flat 28x15 table, one byte per cell; the port hit-tested the section
-- rectangles, which are anchors and agree with it for only 413 of 420 cells.
--
-- ...AND THE BAG SCREEN, which was a flat green rectangle and three boxes
-- this port chose the size of.  gen3BagScreen carries the 53-tile sheet, both
-- gendered palettes, and every window rectangle from sDefaultBagWindows.
-- ...AND THE SUMMARY SCREEN'S PLACES.  "the pokemon stats/ summary page the
-- text isnt in the right places" -- and that screen's own comment admitted
-- the method: its numbers were "read off the background this screen now
-- draws".  By eye is exactly as accurate as it sounds.  The right-hand stat
-- column was 26 pixels out, the move names 32, the nickname 79, and both row
-- pitches were wrong (fourteen and thirteen against the cartridge's sixteen),
-- so the fourth line of each page drifted out of its own box.
-- constants gained gen3SummaryWindows: all four WindowTemplate arrays.
-- v179: THE WALL WAS BUILT AND THE KEY WAS NEVER CUT.
--
-- Collision's Acro Bike rule handles all five obstacle behaviours and its own
-- comment said it was written out in full "instead of a `return false` nobody
-- remembers to revisit".  Nobody revisited what was outside it: the bag knew
-- only the Game Boy's BICYCLE so Hoenn's two bikes did nothing when used,
-- `mover.acroBike` was read by the rule and written by nothing, and
-- `p.bikeSpeed` -- the only thing that beats a muddy slope -- was read in one
-- place and set in none.  Jagged Pass's bumpy slopes were a wall to everyone,
-- and behind them are Mt. Chimney and the Magma Hideout.
--
-- gen3FieldMoves also gained DIG properly this time: `move` is the cartridge's
-- move NUMBER, the way every other row holds it, not the name.
-- v181: HOENN'S OTHER HALF.
--
-- "Continue finish the pokenav and the contests next".  Both were absent
-- entirely, and both are mostly DATA the import had never gone looking for:
--
--   * gItemIconTable -- 378 pairs of a 24x24 sheet and a palette, found by
--     the only shape in the cartridge that decompresses to exactly 288 and 32
--     bytes 378 times running.  The bag had a hole cut in its background for
--     these and nothing to put in it.
--   * the POKeNAV: five menus, thirteen button pictures, fourteen row
--     descriptions, the 256-byte condition-radius LUT, the seventeen-row
--     ribbon bit layout with its 25 descriptions, all 21 match call headers
--     with their 107 phone lines, and gRematchTable's 78 rows.
--   * contests: 96 opponents in four ranks of 24 (nine of each post-game
--     only), the 5x5 crowd table, the rank names, the combo starter and
--     follow ids on every move, and the Contest Lady's five.
--   * Pokeblocks: the 25x5 nature/flavour table -- proved by deriving it from
--     each nature's raised and lowered stat and finding all 25 rows agree --
--     and the fourteen colour words.
--
-- ...and the engine side: contest stats on the Pokemon (which is also what
-- makes FEEBAS able to evolve at last), ribbons, the Pokeblock case and the
-- Berry Blender's arithmetic, the rematch step counter and its map-load roll,
-- and the region map's zoom.
-- v182: THE BOTTOM OF THE BATTLE SCREEN, AND THREE THINGS IN THE BAG.
--
-- "the text in battle doesnt seem to be correct its really dark but its not
-- like that in the real rom, and the text box in battle has a background in
-- the real game but not in ours" -- one missing picture behind both.  The
-- strip is 240x48 with its own tiles, tilemap and palette, and the message on
-- it is WHITE with a dark violet shadow on TEAL; the four actions beside it
-- are dark grey on white, in the player's own OPTIONS frame.  Two colour
-- records, not one, and every string printed twice.
--
-- The tilemap is 32 by SIXTY-FOUR and only eighteen rows carry art -- three
-- runs of six, which the cartridge scrolls between.  That shape is the check.
--
-- ...and the bag: the item picture's box is 32 by TWENTY-EIGHT, so centring a
-- 24-pixel icon in a 32x32 put it two rows low and its right column on the
-- border; the pocket name was drawn four pixels too far down and the pill's
-- own border ran through it; and the selected pocket's dot is a TILE THE
-- CARTRIDGE SWAPS IN -- a 4x4 block that is red for the boy and blue for the
-- girl -- which the importer now finds by asking which unplaced tile differs
-- from the dot by a solid block.  Exactly one does.
-- v183: WHO YOU CAN SEE, AND WHO IS STANDING ON WHAT.
--
-- "all kekleons are visible without using the scope" -- Emerald's invisible
-- KECLEON wear the ordinary KECLEON sprite, and what hides them is their
-- MOVEMENT TYPE, whose step-0 callback sets the object's own invisible bit.
-- Found by walking all eighty-one callbacks -- wrapper to sub-callback to
-- step table to step 0 -- and looking for the four instructions that set bit
-- 5 of byte 1.  Exactly one reaches them.  They still block and still talk,
-- because the cartridge's collision test never looks at whether an object can
-- be seen.
--
-- "some sprites that are on bridges are appearing under them like steven on
-- the bridge next to the kekleon" -- the whole rule was already here and NPCs
-- simply had no elevation to look it up with.  It cannot come off the ground
-- either: a bridge SPAN is elevation 15, which the cartridge refuses to write,
-- so an NPC standing on one would never learn anything from the cell beneath
-- it.  The template's own byte is the answer, and the data says outright who
-- belongs on top of what: every one of Steven's nine appearances in Hoenn is
-- elevation 3 except the Route 120 bridge, which is 4.
--
-- "After battling may ... her sprite stays there even though she drives away
-- on her bike" -- trainerbattle mode 3 ends with `gotopostbattlescript`, not
-- `gotobeatenscript`: it resumes at the byte AFTER its ten-byte record, which
-- is the rest of the cutscene.
-- v184: THE BALL.
--
-- "Pokeball throwing animations dont exist in battle either" / "neither do
-- the capturing shaking etc eniamtions".  The catch MATHS has been right for
-- a long time and none of it was ever shown: the chain is written in Gen 1's
-- and Gen 2's animation SCRIPTS, and a Gen 3 dataset has none of them.
--
-- Twelve sheets of three 16x16 frames, and the third frame is a lie in nine
-- of them -- all zeroes in the compressed sheet, overwritten at load time
-- with one shared "open halves" blob for every ball but DIVE, LUXURY and
-- PREMIER.  Every timing is the cartridge's: a 34-frame throw with a
-- 40-pixel sine hump, a 28-frame absorb that shrinks the Pokemon to a fifth
-- while its palette blends to the BALL'S OWN colour, four bounces of 16, 13,
-- 11 and 10 frames with a sound each, and 59-frame shakes 31 frames apart.
-- v185: THE SECRET BASE'S DOOR OUT, AND THE PC IN THE ROOM.
--
-- "after making a secret base when i try and exit it puts me right back in
-- the secret base room" / "the pc in the secret base room doesnt work".  Two
-- faults, and the first hid nothing while the second hid everything.
--
-- The exit was an ALIAS: specials 8 and 24 were the same function here, and
-- 8's first act is to record where you are standing as the way back out.  8
-- runs outside on the route and 24 runs INSIDE, after 8 has already put you
-- in the room -- so the alias recorded the base room as the way out of the
-- base room.  The cartridge's 24 never touches the dynamic warp at all; it
-- warps to two coordinate bytes on the room's own table row, which 8 never
-- reads.  gen3SecretBases.rooms gained those, checked against each room's own
-- size because the twenty-four are not one shape.
--
-- The PC is a METATILE.  Not an object, not a bg event -- behaviour $B0 for
-- your own base and $B1 for someone else's, answered by
-- GetInteractedMetatileScript with a script address, so no walk over a map's
-- events was ever going to find one.  gen3SecretBases gained `pc`, read out
-- of that function's two arms: the predicate each calls, the behaviour that
-- predicate compares, and the script it answers.
--
-- ...and its DECORATION row now has something behind it.  gen3Decorations
-- gained the ten shapes (1x1 through 3x3, plus a 4x2 and a 2x4, read off the
-- jump table in ShowDecorationOnMap because they are not a table anywhere),
-- each record's metatile list -- stored 512 low, because they are offsets
-- into the secondary tileset -- the object-event graphics id that the
-- forty-five DOLLs and CUSHIONs carry INSTEAD of metatiles, the permission
-- that says which ones you may stand on, and the menu's own four rows.
-- v186: THE ROTATING GATES, FOUR YEARS LATE.
--
-- v172 read them and nothing ever looked at the record: nineteen gates, eight
-- shapes, their arm tables, four rotation grids and two sweep tables, sitting
-- in the cache unread while Fortree Gym stayed an empty hall.  That is this
-- port's dominant Gen 3 bug -- not "extracted wrong" but "extracted correctly
-- and read by nothing" -- and the fix is a reader, plus three things the
-- record was still missing.
--
-- WHERE THE COLOURS COME FROM.  Both sprite templates carry paletteTag $FFFF,
-- which reads as "it borrows the player's" and is wrong; their OAM names OBJ
-- palette SLOT 2, and the overworld fills its slots from a fixed tag table
-- shipped four times over.  All four copies say slot 2 is tag $1103, that tag
-- is the first NPC palette, and its entries 11, 12, 13 and 15 -- the only
-- four the eight sheets touch -- are an olive ramp and a black outline.  A
-- bamboo lattice, which is what a gate is.  The record gained the palette and
-- one baked 64-square strip.
--
-- AND A BLANK IS NOW A BLANK.  The four rotation grids were written with
-- `(v == NONE) and false or v` -- the oldest trap in Lua, since `true and
-- false` is false and `false or v` is v -- so all forty-eight blanks came out
-- as the byte $FF and the intended `false` was never written once.  Nothing
-- read the record, so it broke nothing; the first reader would have taken
-- $FF for a rotation of 15 into arm 15.  They are now decoded pairs, and the
-- two sweep tables are keyed by the rotation NUMBER that selects them rather
-- than by a name this port made up.
-- v187: THE ONE THAT WON'T STAND STILL.
--
-- Beat the league and the television names a Pokemon seen over Hoenn.  The
-- special that puts it in the air had no handler, and src/world/RoamMons.lua
-- is Crystal's three-beast byte roll keyed by names a Hoenn save has none of
-- -- so the whole system was a legendary the game announces and that is
-- nowhere in the region.  constants gained gen3Roamers, and two of its
-- numbers are the kind that look plausible while being wrong: the second
-- species is written `mov #204 / lsl #1`, so reading the immediate gives a
-- completely different Pokemon; and both sets of odds are masks over a Random
-- shifted left sixteen, so reading the immediates gives 240 and 192 rather
-- than one in sixteen and one in four.  Twenty places with fifty ways between
-- them, every one checked to be a real map and every way out to lead to
-- another of the twenty.
-- v188: THE CABLE CAR, which is the one way up Mt. Chimney.
--
-- Both stations run the same three rows -- `setvar $8004, <which> / special
-- 154 / special 155 / waitstate` -- and neither special had a handler, so
-- walking into the car incremented a game statistic and left the player
-- standing on the platform.  Where it goes is five immediates in one
-- function and no table at all: the special branches on VAR_0x8004 and calls
-- SetWarpDestination with a group, a map, a warp id of -1 and a cell in each
-- arm.  constants gained gen3CableCar, refused unless the two arms agree on
-- everything but the map number -- one group, one cell, one platform at each
-- end.
-- v189: THE HEALTHBOX, MEASURED.
--
-- "im also not nseeing the symbols for pokemons gender in blue or red in
-- battle next to their names and their names are looking a little too bold"
-- / "The exp bar is also overlapping the hp text".  Three faults and all
-- three were the layout guessing at numbers the panel already carries.
--
-- gen3BattleHud gained `geometry`, measured off each panel's own pixels: the
-- cream interior is the one index that fills a solid rectangle, and the EXP
-- strip is the row below it whose pixels alternate between two colours for
-- more than forty across.  The two panels are NOT the same shape -- the
-- foe's interior is nineteen tall and the player's twenty-seven, because the
-- player's box has a third row for the current-and-max numbers -- and one
-- height for both is what put those numbers eight pixels low, on the EXP
-- strip.  The strip is inside the panel too, not below it.
--
-- It also gained `text` and `gender`.  The healthbox renders into a window of
-- its own and names its three indices; the two gender symbols each override
-- the letter's colour in the STRING rather than in the call, so the index and
-- the glyph come out of the same four bytes -- 11 for a male and 10 for a
-- female, which in the healthbox palette are a light blue and a pink.  And
-- the two species whose own NAME ends in a symbol get none beside it.
-- v199: THE BACK OF A SHINY POKEMON.
--
-- Reported from play: "make sure shiny pokemon work".  In Hoenn they did not.
-- The importer had been decoding every species' FRONT sheet through
-- gMonShinyPaletteTable since v112 and writing it to spriteShiny, and nothing
-- in the engine ever read it, because every shiny test in the port asked for
-- `mon.dvs` -- which a Gen 3 Pokemon does not have.  With that fixed the
-- front pictures light up on their own, but the BACK sheet was still decoded
-- through the ordinary palette only: gMonShinyPaletteTable is one palette per
-- species and the cartridge applies it to whichever sheet is on screen, so
-- the player's own shiny Pokemon -- the one on screen for the whole battle --
-- came up in its ordinary colours from behind.
--
-- Every species row now also carries spriteShinyBack, and
-- assets/generated/battle/shiny_back/ gains its 386 pictures.  A cache built
-- before this has neither, so the file falls back to the ordinary back pic
-- rather than showing nothing -- but the fallback is the bug, which is why
-- this is a bump.
-- v200: THE HELD-ITEM ICON.
--
-- Reported from play: "in the pokemon party menu the hold item icon shows,
-- currently when theyre holding items it doesnt show anything like in the
-- rom".  sPartyMenuSpriteCoords has been read since the panels were, so every
-- slot's `item` x/y was already in gen3PartyMenu -- there was simply no
-- picture to put there.
--
-- It is not in the compressed party-graphics block with the ball and the
-- status pills, which is why a sweep of that block never turned it up: it is
-- sixty-four RAW bytes sitting in the middle of the sprite tables at 615E30,
-- named by the SpriteSheet at 615EB0 { 615E30, 0x40, tag 55120 } with its own
-- palette at 615E70.  Sixty-four bytes of 4bpp is two 8x8 tiles, and the
-- two-entry anim table at 615EA8 says what they are -- and the art proves the
-- reading on its own: frame 0 is a yellow-topped, red-bottomed parcel and
-- frame 1 a white envelope.
--
-- gen3PartyMenu.images gains `heldItem` (and `heldItemFrames`), and the
-- record gains `mail` -- the twelve item ids ItemIsMail (0D47BC, `cmp #132 /
-- bgt` then `cmp #121 / blt`) answers true for, kept as IDS so the screen
-- never sees a raw item number.
-- v201: A SHINY THAT STAYS SHINY WHILE IT MOVES.
--
-- Reported from play: "shiny pokemon during their emerald battle sprite
-- animation are turning to their normal non shiny colors and then after their
-- animation appear as their normal shiny colors".
--
-- Exactly that, and the cause is a seam the cartridge does not have.  Emerald
-- loads ONE palette for a battler and draws every frame of every sheet
-- through it; this port bakes the palette into each decoded PNG, so a species
-- needs one picture per palette per sheet.  v199 gave the front and back
-- STILLS their shiny decode -- and left the two-frame ANIMATION strip with
-- only the ordinary one, so a shiny lost its colours for precisely the frames
-- it was moving and got them back the moment it settled.
--
-- picAnim gains `shinySheet`, and assets/generated/battle/anim/shiny/ gains
-- its strips.  PicAnim.sheetFor is the one place that chooses between them.
-- v202: THE SEAFLOOR -- the diving suit, the blob, and the way back up.
--
-- Three reports, one dive.
--
-- "the surf sprite and character sprite that appears when diving isnt
-- appearing as well when underwater".  The underwater player is a whole
-- separate graphics row wearing its own palette -- 111 for the boy, 112 for
-- the girl -- seventy rows past the walking sheet, so the block walk that
-- finds the bicycle and the surfboard by palette could never reach it.  What
-- names it is sPlayerAvatarGfxIds, one { boy, girl } pair per avatar state;
-- the stage finds that table by the walking pair the manifest already names
-- and CHECKS it against the surfing pair the block derivation produced on its
-- own.  gen3PlayerSprites gains boyUnderwater / girlUnderwater.
--
-- "the underwater submarine room I cant use dive to go up here like im
-- supposed to be able to".  gen3Dive.noSurfacing was a STATISTIC taken over
-- the seven route/seafloor pairs, and it says nothing about the seven
-- underwater ROOMS, which have no surface map above them -- their ordinary
-- floor wears behaviours a route calls sealed, so the submarine room, the
-- Marine Cave and the Sealed Chamber's approach all refused to surface
-- anywhere.  MetatileBehavior_IsUnableToEmerge (0895D0) is four instructions
-- over two constants -- $19 and $2A -- and the stage now reads it, keeping
-- the statistic as a cross-check in the log.  (The same pass corroborates
-- the DIVE side: MetatileBehavior_IsDiveable is $11/$12/$14, exactly what the
-- old statistic had already produced.)
--
-- The third, the surf blob sitting eight pixels too high, needed no new data
-- -- see Player:drawSurfBlob.
--
-- v225: THE MAUVILLE OLD MAN.  The house east of the gym holds one of five
-- men, chosen from the trainer id, and every arm of it hung off a special
-- with no handler -- so the dispatcher branched on a stale VAR_RESULT and the
-- man in it said nothing.  extractMauvilleMan derives his block inside
-- SaveBlock1 off TraderDoDecorationTrade (and proves it: the four
-- eleven-byte name slots end exactly where the already-traded byte begins),
-- his four starting decorations and their previous owners off TraderSetup
-- (two tables that are adjacent in the ROM, so finding one finds the other),
-- and the sprite variable his map object reads out of gSpecials[107].  The
-- same stage finally answers a question this port had left open: the eight
-- decoration arrays in SaveBlock1, off SetDecorationInventoriesPointers --
-- ten desks, thirty ornaments, forty dolls -- which TILE to 150 slots with
-- no gap, and which `Gen3Decorations.roomFor` had been saying yes to
-- everything for want of.  constants gain gen3MauvilleMan and
-- gen3Decorations.capacity; the save layout gains mauvilleMan and
-- decorations.
--
-- ...and LILYCOVE'S LIFT, off the same tracer.  The department store's panel
-- asked two questions nothing answered: which row to open the cursor on (433)
-- and how long the ride is (276).  Zero is a valid answer to the first and it
-- means the TOP floor, so the lift offered 5F from the ground floor every
-- time.  extractElevator reads the map group and the run of map numbers off
-- the panel's own switch, checks the two bytes it reads sit a whole number of
-- eight-byte warp records past the saved location, traces each arm for the
-- row it answers -- they run backwards, top floor first -- and reads the
-- shake table, whose length ENDS ITSELF (the counts climb and the next byte
-- drops) and is the same number the ride clamps a long trip to.  constants
-- gain gen3Elevator.
--
-- v227: THE BATTLE HUD CARD.  Reported from play: "the EXP icon is not lined
-- up and the 12/12 HP text sits outside the card".  Two separate faults, both
-- off-by-a-few-pixels and both now read rather than placed.  The EXP one: the
-- import measures the dotted GROOVE in the panel art (two rows) and the ramp
-- FRAME that draws over it is a whole 8x8 tile with three rows of the box's
-- own edge above the bar, so laying the tile's top on the groove put the bar
-- three rows under it -- extractBattleHud now reads that offset off the empty
-- frame and proves it by the frame's bar being exactly as many rows as the
-- groove.  gen3BattleHud.bars gains expTop and expHeight.  (The other fault
-- needed no data: Font.glyphHeight was reading the DEFAULT page while the
-- healthbox had the small face pushed, so a box laid out for eleven-pixel
-- rows was being measured in fifteens.)
--
-- v228: THE SCROLLING MULTICHOICE.  `multichoice` draws a fixed list out of a
-- table this already read; the OTHER one -- a list too long for the screen --
-- is a special, and it was unserved, so thirteen counters in Hoenn branched
-- on whatever the last unrelated script had left in VAR_RESULT.  TWO OF THEM
-- ARE SHOPS no mart audit could find, because they are not `pokemart` lists:
-- Lavaridge's herb shop and Fallarbor's glass workshop.  extractScrollMulti-
-- choice reads the thirteen lists out of one flat run the task indexes as
-- `base + id * 64 + row * 4`, and what identifies it is that each of the
-- thirteen ARMS separately writes how many rows its own list has -- two
-- numbers found by two routes, agreeing thirteen times.  readText also gained
-- a `spacers` argument, because the cartridge lays a price out with CLEAR_TO
-- and dropping it reads as "PROTEIN1,000".  constants gain
-- gen3ScrollMultichoice.
--
-- v229: WHICH SLOT LINE PAID.  Reported from play: "when winning the slots it
-- should show where you lined them up to win" -- the machine could say how
-- much it had paid and not why, and on a three-coin spin that is five lines
-- it could have been.  The answer is already in the cartridge's art: the five
-- paylines are drawn into the machine's own tilemap, in the gaps between the
-- reel windows and outside the outer two, and the colour of each is its
-- PRICE -- blue for the coin that buys the middle row, yellow for the one
-- that buys the top and the bottom, red for the one that buys the diagonals,
-- the same three colours as the 3 / 2 / 1 / 2 / 3 lamps down either side.
-- extractSlotMachine now finds the three reel windows (the only holes the
-- backdrop leaves, because the reels are sprites) and reads a marker at each
-- row's centre and at each midpoint between two centres, and it CLOSES: five
-- samples come back as exactly three colours, the outer rows agreeing with
-- each other, the diagonals with each other, and the middle row with
-- neither.  gen3Slots gains `screen`.
--
-- v230: BEATING THE GAME.  The champion's room ends `setrespawn /
-- fadescreenspeed / special 275 / waitstate`, and 275 is GameClear -- it was
-- unserved, so beating the league changed nothing that lasts.  Its first two
-- acts are what the rest of Hoenn waits on: HealPlayerParty, then FlagSet on
-- the game-clear flag -- and this port READ that flag in two places and wrote
-- it in none, so a finished playthrough stayed permanently unfinished.  The
-- flag is derived as the one script-flag-sized word in gSpecials[275]'s own
-- literal pool, and it CLOSES: the PC's multichoice had already found the
-- same number by a completely different route, as the gate on its HALL OF
-- FAME row.  constants gain gen3GameClear.
-- v269: THE PC'S OWN SENTENCES, both screens'.  Reported from play: "the item
-- deposit and withdrawal doesn't seem to work like it would in emerald and is
-- falling back to gen1 menu, also allows for the depositing of key items".
-- The words were the missing half of fixing that: "Withdraw how many
-- {VAR1}(s)?", "There is no more room in the BAG.", "Important items can't be
-- stored in the PC!", "Deposit in which BOX?", "That's your last POKeMON!".
-- Each is swept out of the string run its screen's own labels sit in, which
-- is how the bag's lines were already found -- and WHERE they sit is itself
-- the evidence for the flow: the deposit lines are BAG strings, sat among the
-- bag's own, because on this cartridge depositing an item is a bag screen.
-- gen3PCMenu gains `text` and `storage.text`.
-- v270: THE TITLE SCREEN'S OWN LETTERING, and where its logo actually is.
-- Reported from play: "the pokemon logo is left aligned instead of center
-- aligned above the emerald logo" and "the press start text has the wrong
-- font compared to the actual rom".  Both come of a sheet being read as a
-- picture when it is a LAYOUT: the logo is 166 pixels of art inside a
-- 256-pixel background bitmap, so the ink's own box is measured now
-- (contentX/contentWidth) and a screen centres that instead of the padding;
-- and tag 03E9 is a linear tile strip holding PRESS START and the copyright
-- end to end, which reads as scrambled text laid out eight tiles across and
-- so was never drawn.  Its runs are cut at their own blank tiles and written
-- out one row of tiles each (sheets[n].pieces).
-- v271: WHERE THE INTRO'S SPARKLES GO.  Asked for directly: "double check the
-- full rom intro, make sure our engine is matching it exactly".  Walking the
-- intro's task chain turned up two places where the port had a formula and the
-- cartridge has data: the second water drop is created at y=60 and the port
-- had 30, and the eleven sparkles are a run of {x, y} byte pairs the scene's
-- second task spawns one every twelve frames -- which the port was scattering
-- with arithmetic of its own.  gen3IntroShots.<shot> gains `sparkles`.
-- v272-v275: Emerald's trainer intro and defeat lines, the tilemap flip bits
-- in the screen bakes, the Poke Mart's own field, and the trainer card's art.
-- v276: PRISM'S DEX ENTRIES AND ITS BOULDER.  Reported from play, with a
-- screenshot of a Zubat page reading "BYTE:CE" where its species line belongs:
-- Prism keeps its dex entries in a shape of its own -- a COMPRESSED kind
-- string, METRIC height and weight, and a length-prefixed first page -- and
-- names its four entry banks with a plain `PokedexEntryBanks` label rather
-- than Crystal's three dotted ones, so the reader was looking 42 banks away
-- from the text.  In the same import, `changemap` now carries the replacement
-- block table it names (Mound Cave's boulder) and `givetm` carries the machine
-- it hands over.
-- v277: WHAT PRISM'S SCRIPTS WERE NEVER SAYING.  Two operand widths came out
-- of the generator wrong because the commands have no macro of their own name
-- (eventvarop is written as readeventvar/writeeventvar/..., modifyeventvar as
-- inceventvar/addtoeventvar/...), so eighteen and eleven sites respectively ate
-- the opcode after them; and `anonjumptable` / `menuanonjumptable` name a jump
-- table written INLINE, which the walker had no way to follow -- resolving
-- them turned up 159 scripts, every menu branch behind them, that had never
-- been decoded at all.
-- v278: `cmdwitharrayargs` resolved.  It builds one of seven commands and runs
-- it with some arguments taken from the array loadarray left loaded, and
-- eighteen of Prism's thirty-one uses are a warp whose destination coordinates
-- come out of that array -- eighteen places where pressing a thing took the
-- player nowhere.  The per-argument widths come from the cartridge's own
-- AllowedCustomScriptCommands (23:$5868) rather than a table written here.
-- v279: the MENU family.  `menuanonjumptable` is loadmenudata + verticalmenu
-- before it falls into the jump table, so the choice is what indexes it --
-- lowered as a bare table, every one of those menus took whichever branch the
-- previous command had left in the script variable.  Prism's loadmenudata and
-- its scrolling list are Crystal's loadmenu under other names, and the same
-- MenuHeader is behind them: eighteen of the thirty-seven menu sites now
-- resolve to their real labels.
-- v280: PRISM'S SIGNPOSTS, and the tail of its script table.
--
-- Its five is SIGNPOST_ITEM and its six is SIGNPOST_LOAD where Crystal has
-- IFSET and IFNOTSET, so the map-scripts pass had been inventing a condition
-- for 248 signs out of the first two bytes of their own words, and queueing
-- kinds 6 and 7 -- 235 of them -- as BYTECODE.  Every one of those signs ran
-- the disassembly of its own text instead of printing it, and eight of the
-- cartridge's twenty-six script desyncs started there; the count is four now.
-- EagulouCity is the closure check (source says LOAD, LOAD, ITEM, LOAD, LOAD;
-- the ROM's kind bytes are 6, 6, 5, 6, 6).
--
-- With the noise gone the real remainder was small enough to finish:
-- getnthstring's string list and itemplural's suffix rules -- both read out of
-- the ROM, the plural arms by walking GiveItemCheckPluralMain's own compares --
-- plus readpersonxy, variablestablerandom, copystring, loadsignpost,
-- loadmemtrainer, trainertext, checkpokemontype and the two Pokemon-mode party
-- commands.  Nineteen unlowered kinds down to four, of which two are Z80.
--
-- And a rule that was never Prism's alone: GetScriptByteOrVar answers the
-- SCRIPT VARIABLE for a zero operand, so `cry 0`, `pokenamemem 0` and
-- `checkitem 0` name what the script just looked up -- Crystal's Strength
-- script is `readmem wScriptVar / cry 0`, and it had been crying species zero.
-- v281: THE ONE TRAINER PIC THAT IS NOT COMPRESSED.  GetTrainerPic (0B:$707C)
-- compares wTrainerClass against a single class and copies that one's 49 tiles
-- RAW, skipping the FarDecompress every other class takes; Prism's PALETTE
-- class is it, and read as an LZ stream its 784 plain bytes decoded to 311 and
-- the pic was dropped -- which is why every Palette agent in Mound Cave fought
-- under the placeholder.  The class number comes from that routine's own
-- `cp n / jr nz`, so Gold and Crystal (which `cp n / ret nc` there) are
-- untouched.  Sixty-six of Prism's sixty-seven classes decompressed to exactly
-- 784 bytes; this was the one that did not, and now all sixty-seven do.
-- v282: THE SUMMARY SCREEN'S OWN TILE SHEET.  LoadStatsScreenPageTilesGFX
-- copies one seventeen-tile block to VRAM $31, and the exp bar's END CAPS on
-- that screen are two tiles of it -- the pink page writes them itself, $40 at
-- the bar's left and $41 at its right, on both Prism and Crystal.  With no
-- sheet to draw them from the screen closed its exp bar with the HP bar's own
-- $62 and double-bar cap, which is exactly what "the xp bar looks like the hp
-- bar" describes.  The source, destination and count all come out of that
-- routine's own `ld de / ld hl / lb bc`, and the cap tiles out of the two
-- tilemap writes, so nothing about either is written down in the port.
-- v283: EMERALD'S INTRO HAS A THIRD ACT, and the port had never played it.
-- The intro's own task chain runs on past the bike ride -- 016D7E8 arms
-- 016DBAC, and the chain goes through 016DD28 and 016E2A0 before the title
-- takes over -- and what those handlers decompress is a Poke Ball, Groudon in
-- three poses and Kyogre in four.  The scene pass could never have found them:
-- they are 256-colour AFFINE backgrounds, a map of one BYTE per cell over
-- 64-byte tiles, where every background it knows is a 4bpp sheet under a
-- 16-bit tilemap.  Addresses, palette and widths are the routines' own
-- arguments, traced; the figures are the runs of non-empty rows in each map.
-- v284: THE THIRD ACT'S REAL SHAPE.  It is FIVE beats, not three -- a Poke Ball,
-- Groudon, Kyogre, a cloud field closing over the screen and the same field
-- parting again -- and 893 frames, and the movement is the cartridge's:
-- tools/gen3_intro_act3.py runs the intro's own task code under a THUMB
-- interpreter and records what the hardware is handed every frame, which
-- compresses to 269 runs of constant step.  The act also is NOT black and
-- white: a figure is drawn in two palette entries, a black body and markings
-- (Groudon's 31, Kyogre's 47) that each handler animates through a table at
-- $0D85CD0 -- black, blue, purple, magenta, RED -- so the markings are composed
-- as their own mask and wear that colour at run time.
-- v310: EMERALD'S SCRIPT TABLE HAD THE WRONG TAIL.  Opcodes $C7-$E2 were named
-- and sized from FireRed's table and from guesses at what each handler calls,
-- and pret's gScriptCmdTable disagrees with fourteen of those slots.  Most of
-- the disagreements were names only -- $D1 is warpspinenter and $D7 is
-- warpmossdeepgym, both `bbbww`, both lowering to a warp -- but $E0 is
-- warpwhitefade, `bbbww`, and it had been bufferitemnameplural, `bww`.  Two
-- bytes short, twice, in Sootopolis City.  The Rayquaza scene's own
-- `warpwhitefade MAP_SOOTOPOLIS_CITY, 43, 32` disappeared, the decode ran off
-- the end of the script and straight into the next one, and the scene came
-- out with a whole second copy of itself attached: Rayquaza descended twice,
-- the player was never warped back in front of the Pokemon Center, and the
-- `end` that would have handed the controls back was on the far side of the
-- damage.  $C7-$CC and $D0 are ScrCmd_nop1 and take no operand at all.
-- v311: A CUTSCENE BACKGROUND WITH NO TILES OF ITS OWN IS NOT A FREE GUESS.
-- The Rayquaza scene's layer pass fell back to "whichever character block the
-- scene did load" for a BG that had a tilemap and no tiles, scanning BG0
-- upwards.  Which block a background really reads is in its BGCNT register,
-- which that walk does not decode, so the fallback is a guess -- and it is
-- only a safe one when the scene loaded exactly one block.  Rayquaza's charge
-- loads several: BG0 borrowed BG1's, which is Rayquaza's own sheet, and the
-- screen came out with chunks of him scattered over himself in tidy 8x8
-- blocks that look for all the world like corruption.  An unresolvable
-- background is now left out instead.
-- v312: ...AND THE LAYER THAT FIX TOOK OUT WAS NEEDED.  Leaving out every
-- unresolvable background dropped three, and two of them were real: the
-- chase's sky and the chase-away's backdrop, which is why Rayquaza came down
-- against black instead of through the hole in the clouds.  A shared
-- character block is what a BACKDROP is drawn from, so the inference is now
-- checked against what it draws rather than refused outright -- the two real
-- ones paint 712 and 1024 cells of 1024, the wrong one paints 78.
-- v313: ...AND COUNT PIXELS, NOT CELLS.  The v312 check kept a borrowed
-- background if it touched half the 8x8 grid, and debris composed from the
-- wrong sheet is precisely the thing that touches most of the grid while
-- filling none of it: the chase's BG3 scored 712 cells of 1024 on 17% of the
-- pixels, passed, and sat as a checkered band across Rayquaza's descent.  By
-- pixels the scene's three borrowed layers are 17%, 5% and 100%.
-- v314b: ...AND HIS TAIL WAS DROPPED ON THE WAY OUT OF THE CARTRIDGE.  A
-- CompressedSpriteSheet's `size` is the VRAM it is given and the load copies
-- exactly that: short blobs are zero filled, LONG ones are cut off.  Only the
-- short case was handled, so tag 30557 -- 512 bytes of VRAM, two 16x32
-- frames, decompressing to 1100 -- sized itself at 34 tiles, divided by
-- nothing, fitted no shape and was skipped; Rayquaza came down the descent
-- with no tail.  Six of this scene's sprites also borrow their owner's
-- palette rather than naming one under their own tag, which is now read off
-- the template instead of landing on a fallback.
-- v314: RAYQUAZA HAS FOUR FACINGS AND WAS EXTRACTED AS ONE STILL.  The
-- object-event facing test wants three DISTINCT standing pictures and an east
-- mirrored from the west; graphics row 207 has neither -- all three of his
-- stands are the same coil, and his east is drawn.  So he came out
-- `frames = 1, walker = false` and the Sky Pillar flew him away without ever
-- reaching image 4, the one where he is uncoiled and climbing.  A second pass
-- accepts the twelve-slot layout when its four standing anims are
-- single-frame; over all 246 rows that admits exactly one the first pass
-- turns away, and it is him.
-- v315: PRISM'S BERRY TREES HANDED OUT NOTHING, because FruitTreeItems was
-- being cut in half.  The table is 18 apricorn trees then 11 berry trees, and
-- it marks the seam with `EndApricornTrees:` -- a label that exists only so
-- CheckFruitTree can tell one kind from the other.  Bounding the table at
-- "the next symbol in the bank" stopped there, so trees 19-29 had no item and
-- every berry tree in the game said "It's a fruit-bearing tree." forever.
-- Labels naming the END of a run are no longer treated as boundaries.
-- v316: PRISM COULD NOT LEARN A SINGLE TM OR HM.  Its base_stats rows are 24
-- bytes, so the 8-byte learnset bitfield Crystal keeps at offset 25 is simply
-- not there -- every species came out with an EMPTY tmhm list and the bag
-- refused Cut, Surf, Strength and all 96 TMs.  Prism keeps them in a table of
-- its own instead (TMHMLearnsets, 13 bytes per species), which is what its
-- CanLearnTMHMMove copies into wCurBaseData.  Read from there when the ROM
-- has that symbol.  TMHMMoves is also walked to its own zero terminator now,
-- so Prism's 101 machines no longer gain three imaginary tutor slots.
-- v317: THE POKEMON ORPHANAGE'S ADOPTION SCRIPT DESYNCED ON ITS OWN OPERAND.
-- CheckOrphanPointsFromScript and TakeOrphanPointsFromScript read a halfword
-- out of the script stream themselves (LoadCoinAmountToMem ->
-- GetScriptHalfwordOrVar), so the `dw -1` after each callasm is the routine's
-- operand and not bytecode.  Walked as bytecode the decode stopped there and
-- everything after it -- the party-space check, the confirmation, the givepoke
-- -- was lost.  Also: menu option strings now decode as plain PlaceString
-- glyphs, which is what the adoption LIST itself was failing on.
-- v318: PRISM'S PACHISI BOARD IS NOW IN THE CACHE.  The whole minigame is four
-- flat byte tables -- the tile at each board position, the step that leaves
-- it, sixteen species per habitat and sixty-four items -- which nothing ever
-- extracted, so the five `callasm` routines that read them had nothing to
-- read.  field.gen2Pachisi carries them, bounded by the End symbols the source
-- declares.  Verified by walking the real tables: the section terminators sit
-- exactly one square before each warp destination the script writes back.
-- v319: THE FLY LIST OFFERED THE PLAYER'S BEDROOM.  A spawn interior shares its
-- LANDMARK with the town it stands in -- PLAYERS_HOUSE2_F is landmark 1 with
-- NEW_BARK_TOWN, VIRIDIAN_POKECENTER1_F is landmark 49 with VIRIDIAN_CITY --
-- so the Fly cursor, which walks landmarks, listed "NEW BARK TOWN" twice and
-- the second one dropped the player in their bedroom.  gen2FlyWarps meant to
-- exclude interiors and asked the wrong question: its Pokemon Center test was
-- `tileset == 6`, and id 6 is TilesetPlayersHouse in Crystal, so it caught the
-- player's house, Elm's, Red's and the Copycat's and no Center at all.  Now
-- the Center test reads the tileset NAME off the map def, and a Fly
-- destination additionally has to be a TOWN or a ROUTE -- FlyFromAnim's own
-- rule, and the same one EnterMapWarp.SetSpawn makes on the other side.
-- v320: Gen 3 object animations stop at their terminator, so a walk with
--       one held frame is no longer given the next animation's frames as a
--       second step -- and a sheet whose walks are held is marked holdStep
--       (Rayquaza's Sky Pillar flight; he is the only row in the cartridge)
-- v321: Polished Crystal's TM/HM pocket commands resolve their machine
--       operand to the TM_nn/HM_nn item, and changemapblocks decodes its
--       far pointer into the replacement block table -- both change what
--       map_scripts.lua holds, so every Gen 2 cache rebuilds
-- v322: field.gen2Stairs -- Polished Crystal's four stairs collision
--       classes and the one facing each admits, read off its own
--       DoPlayerMovement.FacingStairsTable
-- v323: Polished Crystal's item table read one name early and at Crystal's
--       seven-byte attribute stride -- every item wore the name of the one
--       below it (layout.itemNameBias / itemAttrBytes / itemAttrPocketAt)
-- v324: field.gen2BattleMenuMon -- the battle menu's party button is two
--       glyph tiles and the pair is not $E1 $E2 everywhere; Polished
--       Crystal keeps the digits there, so the button read "12"
-- v325: Polished Crystal's battle HP bars were read from HPBarPals, which
--       on that cartridge is the PARTY MENU's four-colour set; the battle
--       screen reads HPBarInteriorPals, and its exp bar GenderAndExpBarPals
-- v326: field.gen2Roofs -- the nine tiles an outdoor tileset does NOT own.
--       MapGroupRoofs / MapGroupRoofGFX (or Roofs) and RoofPals, so a
--       town wears its own roof instead of whatever the GFX blob left
--       in tile slots 10-18
-- v327: field.gen2MapPalettes -- SpecialBGPalettes, the seventy-four rows
--       LoadMapPals consults BEFORE the environment row.  The Pokemon
--       Center and the Mart are two of them and were being coloured
--       from the generic indoor row
-- v328: the water shimmer is read from ALL four of Polished Crystal's
--       water routines, not just AnimateWaterTile -- Kanto, Safari,
--       the islands and Snowtop Mountain had a frozen sea -- and the
--       tile ids come off each script (tileset.animWaterTiles)
-- v329: FireRed named no music at all.  Its map-section names are a flat
--       pointer array, not Hoenn's eight-byte records, so gen3MapSections
--       came up empty -- and that is what extractSongNames proves the
--       song numbering against, so the names went with it and then the
--       roles did: audio.battle unwritten, and Music.playBattle plays
--       nothing without it
-- v330: FireRed's dex text.  Several TEXT addresses pointed at the
--       previous string's terminator and the retry landed on a keypad
--       glyph the reader could not decode, so whole control bars came
--       back as one letter -- and AREA, SIZE, PAGE and AREA UNKNOWN
--       were never asked for at all
-- v337: Gen 3 object-event frames preserve their gbagfx macroblock layout;
--       this fixes FireRed's 32x16 Town Map and changes generated sprite data.
-- v338: Gen 4 sheets carry `facings` -- which of their own frames faces which
--       way, read from mmodel.narc's own frame-sequence tables.  Without it
--       the renderer used the Game Boy's fixed six slots on a sheet that is
--       not in that order, and the player turned a different way on every
--       step: "when i try and walk my character spins in circles".  A
--       Platinum cache written before this has no `facings` at all, and there
--       is no missing FILE to notice it by, so the format is what says so.
--       Also: a Gen 4 map's object scripts are filed by the event's POSITION
--       rather than its localId, which the cartridge reuses inside a map.
-- v339: the terrain stage.  666 land chunks packed into a side-car binary with
--       their BDHC heights beside it, the 74 map texture sets as atlases, and
--       every matrix's chunk grid -- which is what replaces
--       TILESET_GEN4_STANDIN.  New FILES, but under assets/ and named by a new
--       module, so the missing-file gate cannot see them either.
-- v351: Gen 4 `applymovement` carries its DECODED STEPS.  The movement list
--       lives inside the script member, a signed displacement past the
--       instruction, so the bytes are only in hand during the import -- an
--       instruction cached before this has no `movement` field and the
--       executor falls back to turning the object to face the player, which
--       is what every one of the cartridge's 3,025 sites did until now.
-- v352: the Gen 4 scripted menu.  `init(global|local)textmenu` was not lowered
--       at all, so a cached script carries the menu's entries and its `show`
--       but not the VAR the choice goes into nor the TEXT BANK its lines come
--       out of -- 186 menus branching on a register nothing wrote.  The rows
--       are produced at import, so the fix only reaches a cache built after it.
-- v353: two Gen 4 faults reported from play, both in the cache rather than in
--       the engine.  (1) COLLISION.  The map grid wrote its collision flag at
--       bit 10 and `Map.blockArray` masks the word with `% 1024`, so every one
--       of Sinnoh's 335,165 blocked tiles -- 49.1% of the region -- arrived
--       walkable: "still able to walk out of bounds".  Blocked cells are now
--       the reserved value 255, and the border with them.  (2) OBJECT HIDE
--       FLAGS.  1,566 of 3,555 object events carry a flag that makes them
--       absent while it is set; the def never carried it, so nobody a script
--       dismissed stayed dismissed.
-- v354: a map's INIT SCRIPTS.  Every Gen 4 header names two members of
--       `scr_seq` and the port read only one: `initScriptsArchiveID` is the
--       map's own entry conditions -- what runs when you walk in, and the
--       var-gated table the cartridge checks every idle frame.  291 of 594
--       headers have one and none of them had ever run, which is why Mom's
--       scene in Twinleaf never fired and the actor it would have moved stayed
--       standing in the doorway.
-- v355: COORDINATE TRIGGERS.  The third thing on a Gen 4 map that runs a
--       script, extracted onto `def.coordEvents` since the maps stage was
--       written and read by nothing.  186 of them across 76 maps, every one
--       gated on a var and 72 of them covering a rectangle rather than a cell.
--       Twinleaf's player house has one on its exit tile, which is why the
--       neighbour standing there only ever spoke when pressed A on.
-- v356: THE NEW-GAME SCRIPT.  `FieldSystem_InitNewGameState` runs one script
--       before the first map is built, and it is 112 `setflag`s plus three
--       `setvarfromvalue`s -- the cutscene actors whose stories have not
--       started, hidden.  114 object events across Sinnoh are affected,
--       including the placeholder in the player's bedroom and the one in the
--       doorway below it.  Extracted as `constants.gen4NewGame` and applied
--       through `boot.initialFlags`, the seam Gen 3 already uses.
-- v357: the WAIT-AND-SCROLL control code.  0x25BC was decoded as "\r", which
--       is not one of TextBox's markers, so it printed as a stray glyph and
--       the box never waited for A.  It is "\v".  13,576 occurrences across
--       7,407 of the cartridge's 46,053 strings -- every line long enough to
--       need a second box, Mom's included.
-- v358: the DIALOGUE WINDOW's own geometry.  `FieldMessage_AddWindow` puts the
--       text interior at tiles (2,19), 27 x 4; the port was drawing Sinnoh's
--       lines into the Game Boy's 20x6 box at row 12, wrapping by character
--       count with a proportional font, on a 160x144 surface.
-- v359: SHADOWS.  `gObjectEventGfxRenderDetailsTable` out of overlay 5 (259
--       rows, 230 of them casting one), the `kage` texture out of fldeff
--       member 0x11, the five sizes and the nine tile behaviours that turn it
--       off.  Sinnoh's characters have stood on nothing until now.
-- v360: MERGED FROM main, which had independently taken v338 for a different
--       change: "FireRed exports its fifteen tutor moves and per-species tutor
--       compatibility instead of overreading sTutorLearnsets as moves."
--
--       THE NUMBER HAD TO MOVE PAST BOTH. Platinum's chain reached v359 and
--       main's reached v338, and the two v338s describe different work, so
--       neither value invalidates the other side's caches. `CACHE_FORMAT` is
--       the one gate that forces a re-import, and main's change alters what a
--       FireRed cache CONTAINS -- so keeping v359 would let a FireRed cache
--       built before the tutor fix pass as current. v360 invalidates both.
local CACHE_FORMAT = "rom-cache-v360:"
-- The completion marker is written under each version's cache prefix
-- (rom-cache.complete for Red, blue/rom-cache.complete for Blue).
local MARKER_PATH = "rom-cache.complete"

-- The marker a finished import writes for a version: the generation tag plus
-- that version's ROM hash, so both a format bump and a swapped ROM invalidate.
local function markerFor(version)
  local revision = version == "platinum" and "platinum-audio-ui-v15:" or ""
  if version == "emerald" then revision = "emerald-map-popup-v2:" end
  if version == "polishedcrystal" then revision = "polished-audio-v1:" end
  -- Include version-specific field encounters, sleep, swarm and rate tables.
  -- Only these three caches need rebuilding; other markers remain stable.
  if version == "gold" or version == "silver" or version == "crystal" then
    revision = "gen2-field-encounters-v7:"
  end
  return CACHE_FORMAT .. revision .. GameVersion.info(version).sha1
end

-- AND WHAT THAT IMPORT COULD NOT PRODUCE.
--
-- THE RE-IMPORT LOOP THIS ENDS. `isReady` demands the marker AND every
-- required file AND a plausible tileset registry, and the launcher re-imports
-- whenever it says no. That is right for a cache built before a file was
-- added: the next import writes it and the loop ends after one pass. It is
-- catastrophic for a file the version's extractor CANNOT write -- a romhack
-- whose title art, town map or player back-pic lives somewhere Gen 2's
-- symbols do not name. Then `isReady` is false forever, every launch re-runs a
-- three-minute extraction, and no amount of re-importing can clear it. Crystal
-- had exactly this (see the note on VERSION_REQUIRED_FILES) and it was fixed
-- by moving one filename; Prism hit it again, which is the sign the shape of
-- the check is wrong rather than any one list.
--
-- SO A FINISHED IMPORT RECORDS WHAT IT DID NOT PRODUCE, and those files stop
-- counting as a reason to run it again. The claim is narrow and true: this
-- exact cache format, against this exact ROM, has already been extracted once
-- and did not produce these -- so extracting again will not either. Any real
-- staleness still re-imports, because the marker line itself no longer matches
-- after a CACHE_FORMAT bump or a swapped ROM, and a gap list from an older
-- format is thrown away with it.
--
-- The marker stays a plain text file whose FIRST line is what it always was,
-- so an older build reading a newer marker sees a mismatch and re-imports,
-- which is the safe direction to be wrong in.
local function markerBody(version, gaps)
  local out = { markerFor(version) }
  for _, path in ipairs(gaps or {}) do out[#out + 1] = "absent:" .. path end
  return table.concat(out, "\n")
end

-- Split a marker file into its version line and the set of paths that import
-- proved it cannot make.
local function parseMarker(raw)
  if type(raw) ~= "string" then return nil, {} end
  local head = raw:match("^[^\n]*") or ""
  local absent = {}
  for line in raw:gmatch("[^\n]+") do
    local path = line:match("^absent:(.+)$")
    if path then absent[path] = true end
  end
  return head, absent
end
local COMMUNITY_URL = "https://discord.gg/4VXnEnePT"
local TILT_RIPS_URL = "https://tiltrips.com/r/GEN2RECOMP/"
-- Donations.  A plain PayPal checkout link, opened with the same
-- love.system.openURL the community mark and the release links use.
local DONATE_URL = "https://www.paypal.com/ncp/payment/F3QPTKT4E8HCS"
-- The map editor's own button, named in one place because it is drawn in two
-- (sharing the row with Touch Controls, or taking the row alone) and a label
-- that disagrees between them is a label somebody will change once.
--
-- BETA IS A PROMISE ABOUT THE STATE OF THE THING, not decoration: the editor
-- writes to an edit store the game reads on load, and a reader deciding how
-- much of an evening to spend in it deserves to know that up front rather than
-- after.
local MAP_EDITOR_LABEL = "Map Editor (Beta)"
local UD_URL = "https://discord.gg/4VXnEnePT"

-- WHO MADE THE GAME ON THIS TAB, AND WHERE TO THANK THEM.
--
-- The footer's credit line and its donate buttons, per tab:
--   * Red, Blue and Yellow are bryanthaboi's / Boi's Club's work, and they
--     asked for no donation link -- so there is none on those tabs.
--   * FireRed is Tranzue's, and the buttons go to Tranzue: Patreon and Ko-fi.
--   * Everything else -- the other games and the non-game tabs like mods --
--     is UNDERdecoded's, with the PayPal link.
-- A table rather than branches in `draw`, so a new tab is one row here.
local CREDITS = {
  default = {
    by = "UNDERdecoded",
    links = { { label = "DONATE", url = DONATE_URL } },
  },
  red = { by = "bryanthaboi / boisclub", links = {} },
  blue = { by = "bryanthaboi / boisclub", links = {} },
  yellow = { by = "bryanthaboi / boisclub", links = {} },
  firered = {
    by = "Tranzue",
    links = {
      { label = "Tranzue on Patreon",
        url = "https://www.patreon.com/c/cartethyia_bot/shop" },
      { label = "Tranzue on Ko-fi", url = "https://ko-fi.com/cartethyiabot" },
    },
  },
}
RomImporter.CREDITS = CREDITS

function RomImporter.creditFor(tab)
  return CREDITS[tab] or CREDITS.default
end
local TRUST_WARNING = "if you did not get this from UNDERdecodedHD's github " ..
  "or a link from the discord that UNDERdecodedHD himself posted, just know " ..
  "it might have been tampered with. go to the discord to verify " ..
  COMMUNITY_URL .. " (or click the logo above)"
local REQUIRED_FILES_GEN1 = {
  "data/generated/constants.lua",
  "data/generated/maps.lua",
  "data/generated/text.lua",
  "data/generated/field.lua",
  "data/generated/battle_anims.lua",
  "assets/generated/title/pokemon_logo.png",
  "assets/generated/fonts/font.png",
  "assets/generated/battle/front/pikachu.png",
  "assets/generated/battle/anims/move_anim_0.png",
  "assets/generated/battle/anims/move_anim_1.png",
  "assets/generated/audio/programs.bin",
}

local REQUIRED_FILES_GEN2 = {
  "data/generated/constants.lua",
  "data/generated/maps.lua",
  "data/generated/tilesets.lua",
  "data/generated/text.lua",
  "data/generated/text_pointers.lua",
  "data/generated/trainer_headers.lua",
  "data/generated/font.lua",
  "data/generated/sprites.lua",
  "data/generated/pokemon.lua",
  "data/generated/moves.lua",
  "data/generated/items.lua",
  "data/generated/type_chart.lua",
  "data/generated/trainers.lua",
  "data/generated/encounters.lua",
  "data/generated/field.lua",
  "data/generated/battle_anims.lua",
  "data/generated/audio.lua",
  "assets/generated/tilesets/playershouse.png",
  "assets/generated/fonts/font.png",
  "assets/generated/battle/chrisb.png",
  -- THE PARTY BALL ROW, which is easy to lose and gives no sign that it has
  -- been lost.  Reported from play, on Prism: "when battling vs a trainer it
  -- doesnt show how many pokemons hes holding".  BattleState:drawBallRow
  -- loads this sheet once, latches false when it is not there, and from then
  -- on draws NOTHING -- no error, no gap, just a HUD with no balls in it.
  -- Every Gen 2 cartridge can produce it (gen2RawSheet off LoadBallIconGFX),
  -- so listing it here makes a cache that lacks it say so.
  "assets/generated/battle/balls.png",
  "assets/generated/ui/town_map_johto.png",
  -- NOT the title screen: the extractor writes title/gen2_title.png for
  -- Gold/Silver and title/crystal_title.png for Crystal, so a shared entry can
  -- only ever be satisfied by one of them.  It lives in VERSION_REQUIRED_FILES
  -- below instead -- see the warning on the Yellow block about listing files a
  -- version cannot produce.
}

-- Gen 3.  A GBA cartridge produces a different set again, and listing it
-- properly is what makes a HALF-FINISHED import report itself as half
-- finished rather than boot into a game with no maps.  Every entry here was
-- checked against what the extractor actually writes -- the trap being a
-- required file the importer cannot produce, which turns every import into a
-- permanent failure (see the Yellow note below, which is that mistake).
--
-- save_layout and songs are Gen 3 only: the first carries the sector shape,
-- the substructure orders and where every field sits inside the save blocks,
-- and without it a save import refuses rather than guesses; the second carries
-- the music tables.
local REQUIRED_FILES_GEN3 = {
  "data/generated/constants.lua",
  "data/generated/pokemon.lua",
  "data/generated/moves.lua",
  "data/generated/items.lua",
  "data/generated/type_chart.lua",
  "data/generated/trainers.lua",
  "data/generated/encounters.lua",
  "data/generated/text.lua",
  "data/generated/text_pointers.lua",
  "data/generated/maps.lua",
  "data/generated/map_layouts.lua",
  "data/generated/map_tilesets.lua",
  "data/generated/map_scripts.lua",
  "data/generated/tilesets.lua",
  "data/generated/scenes.lua",
  "data/generated/save_layout.lua",
  -- FLY AND EVERY BLACKOUT IN HOENN.  field.lua is where sHealLocations
  -- lands: the fly destinations, the order the region map lists them in, and
  -- the map each `setrespawn` index names.  A cache without it does not
  -- degrade to a missing Fly menu -- the Gen 1 field table is still there for
  -- the overlay to inherit, so a blackout sends the player to Pallet Town's
  -- coordinates on a Hoenn map, which is how the moving van was the whole
  -- region's respawn point.
  "data/generated/field.lua",
  "data/generated/songs.lua",
  -- and the join between them: every map header carries a song NUMBER and
  -- the song table is keyed by name, so `audio` is the table that says which
  -- theme a map plays.  A cache without it is a region that boots and is
  -- silent, which reads as an audio problem rather than a missing file.
  "data/generated/audio.lua",
  -- REQUIRED, not optional.  A Gen 3 cache without its own font does not fall
  -- back to nothing -- the version overlay is additive, so it falls back to
  -- RED'S, silently, and the whole game reads in the wrong generation's
  -- letters.  Data.lua refuses the inheritance now; this is what makes the
  -- launcher notice a cache that predates the font stage and re-import it.
  "data/generated/font.lua",
  -- and the overworld art every object event in Hoenn resolves through.
  -- Absent, NPC.resolveSpriteDef falls through to SPRITE_RED and the whole
  -- region is populated by Kanto -- which is what it was.
  "data/generated/sprites.lua",
  -- THE PARTY MENU'S OWN ART, and required for the same reason as the font:
  -- Data no longer blocks `icons` on a Gen 3 cache, so a cache that does not
  -- carry its own resolves to RED'S and every Hoenn species wears a Kanto
  -- icon chosen by dex number.  Requiring the file is what turns that into a
  -- cache the launcher reports as incomplete and re-imports instead.
  "data/generated/icons.lua",
  -- one of each kind of asset, so a cache that wrote the tables but no
  -- graphics is caught: all 411 front pics and all 93 trainer pics decode
  -- from this cartridge, so neither of these can be a file it cannot make
  "assets/generated/battle/front/bulbasaur.png",
  "assets/generated/battle/trainers/000.png",
  -- ...and one party icon, which is a THIRD kind: raw 4bpp out of a table
  -- with six shared palettes rather than the compressed per-species art
  -- above, so a stage that silently produced none is caught here.
  "assets/generated/icons/bulbasaur.png",
  -- ...and the ground a battle is fought on.  Without it Hoenn fights on the
  -- Game Boy's sheet of white paper, which is most of the screen and is what
  -- makes an otherwise correct battle screen read as being in black and white.
  "assets/generated/battle/bg/grass.png",
  -- ...and the summary screen's own background, which is the screen a player
  -- opens more than any other: without it the page is drawn boxes at
  -- positions somebody chose, and with it the panels are the cartridge's and
  -- every row lands inside one.
  "assets/generated/ui/summary_info.png",
  -- the font page and Birch: one is every letter in the game, the other is
  -- the only picture the new game shows before the player reaches a map
  "assets/generated/fonts/gen3_normal.png",
  "assets/generated/intro/birch.png",
  -- row 0 of the graphics table: the player's own walking sheet
  "assets/generated/overworld/g3_000.png",
}

-- Files only one version's cache carries.  A version that predates one of
-- them re-imports on its own, without dragging the other versions through a
-- CACHE_FORMAT bump.
local VERSION_REQUIRED_FILES = {
  yellow = {
    "assets/generated/battle/trainers/jessie_james.png", -- #439
    -- Oak's own back pic and the pikapic base frames only exist in caches
    -- built after their manifest symbols landed, so an older Yellow cache
    -- has to re-import to stop falling back to the old man's back pic and
    -- to the battle front pic (#557, #561).  Both are gated on manifest
    -- symbols in RomExtractor, so these markers must only ever list files
    -- tools/rom_manifest_yellow.json can actually produce -- otherwise the
    -- cache reads as incomplete and re-importing cannot clear it.
    "assets/generated/battle/profoakb.png",
    "assets/generated/pikachu/pikapic_1.png",
  },
  -- the missing-pic fallback used to be named battle/front/pikachu.png, and
  -- extractAssets stamped the logo over it after extractPokemon had written
  -- the real one; a cache from before the rename still has a logo for PIKACHU
  gold = {
    "assets/generated/battle/front/placeholder.png",
    "assets/generated/title/gen2_title.png",
  },
  silver = {
    "assets/generated/battle/front/placeholder.png",
    "assets/generated/title/gen2_title.png",
  },
  -- Crystal's title screen is its own asset (extractGen2CrystalTitle writes
  -- title/crystal_title.png; there is no gen2_title.png in a Crystal cache).
  -- While gen2_title.png sat in the SHARED Gen2 list, allRequiredFilesExist
  -- could never be satisfied on Crystal: isReady returned false on every
  -- launch, the launcher re-imported the ROM every single time, and no amount
  -- of re-importing could clear it because nothing ever writes that file.
  crystal = { "assets/generated/title/crystal_title.png" },
  -- ...and Prism's is its own again: extractPrismTitleArt writes
  -- title/prism_title.png.  Prism answers the Crystal test
  -- (TitleLogoGFX present, TitleScreenTilemap absent) but has no
  -- TitleSuicuneGFX, so it used to fall into the Crystal reader and
  -- come back with nothing at all -- no title art, and no marker here
  -- to notice it was missing.
  prism = { "assets/generated/title/prism_title.png" },
  -- item_pc.c is FireRed-only, and an older FireRed cache otherwise has no
  -- reason to re-run the new extraction stage: constants.lua already exists
  -- and the shared Gen 3 required-file set is satisfied.  Requiring the one
  -- background this stage always writes upgrades only FireRed caches.
  firered = {
    "assets/generated/ui/item_pc_frlg.png",
    "assets/generated/ui/bag_male_item_pc.png",
  },
}

-- WHAT A GEN 4 IMPORT MUST HAVE PRODUCED.
--
-- These are the fifteen modules `Data.lua` actually requires of a Gen 4 cache:
-- the eleven every generation shares, plus the four its own branch adds.
--
-- It exists because `requiredFiles` had no generation-4 case and fell through
-- to the GEN 1 list, and that is not a harmless default.  A Platinum import
-- that had produced everything it can would be measured against `field.lua`,
-- `battle_anims.lua`, Pikachu's battle sprite, two move animations and the
-- audio program bank -- none of which Gen 4 produces or needs -- so the
-- launcher would report the same five gaps after every successful import and
-- offer to spend the minutes again, for ever.  The failure is silent in the
-- worst way: the import WORKED, and the only symptom is the game asking for it
-- again.
--
-- Deliberately SHORTER than the Gen 2 and Gen 3 lists.  Those name individual
-- PNGs because a cache that wrote its tables and then died partway through the
-- art is the failure they were written for.  Gen 4's art stages each keep
-- their own index table and no single image's absence means the import failed,
-- so naming one here would look stricter and test less.
local REQUIRED_FILES_GEN4 = {
  "data/generated/constants.lua",
  "data/generated/maps.lua",
  "data/generated/tilesets.lua",
  "data/generated/text.lua",
  "data/generated/text_pointers.lua",
  "data/generated/pokemon.lua",
  "data/generated/moves.lua",
  "data/generated/items.lua",
  "data/generated/type_chart.lua",
  "data/generated/trainers.lua",
  "data/generated/encounters.lua",
  "data/generated/map_layouts.lua",
  "data/generated/map_tilesets.lua",
  "data/generated/map_scripts.lua",
  "data/generated/font.lua",
  -- NOT one of Data.lua's required fifteen, and listed anyway, for a reason
  -- the other entries do not have: `field.lua` is where `boot.startMap` lives,
  -- Data.lua's overlay is ADDITIVE, and a Gen 4 cache without one silently
  -- reads RED'S -- which is how the first New Game on Platinum opened in
  -- REDS_HOUSE_2F and died in MapLoader.  Naming it here is also what makes an
  -- older Platinum cache, extracted before the field stage existed, report a
  -- gap and offer to re-import instead of crashing the same way for ever.
  "data/generated/field.lua",
  -- Same reasoning, one step on: `gen4_menus.lua` is what names the title
  -- art and carries the menu's own words, and `field.boot.screens` points the
  -- boot at screens that read it.  A cache with the screens and without the
  -- record boots to a black title with nothing on it, which looks like a
  -- broken screen rather than a missing table.
  "data/generated/gen4_menus.lua",
  -- And the opening.  `field.boot.screens.newGame` now names
  -- Gen4RowanIntro, so a cache with the boot record and without this one
  -- pushes a screen that has no television, no Rowan and no script --
  -- which skips itself and hands the player a game with no intro, silently.
  "data/generated/gen4_intro.lua",
  -- The 3D models, for the same reason and with one difference worth
  -- stating: nothing draws them YET.  They are listed anyway because the
  -- screen that will is the next piece of work, and requiring the table
  -- now means one re-import covers both rather than two.
  "data/generated/gen4_models.lua",
}

local function requiredFiles(version)
  local gen = GameVersion.generation(version)
  if gen == 4 then return REQUIRED_FILES_GEN4 end
  if gen == 3 then return REQUIRED_FILES_GEN3 end
  if gen == 2 then return REQUIRED_FILES_GEN2 end
  return REQUIRED_FILES_GEN1
end

local function gen2TilesetRegistryLooksValid(version)
  if GameVersion.generation(version) ~= 2 then return true end
  local CacheFs = require("src.import.CacheFs")
  local saved = CacheFs.prefix
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local raw = CacheFs.read("data/generated/tilesets.lua")
  CacheFs.prefix = saved
  if type(raw) ~= "string" then return false end
  local chunk = load(raw, "@data/generated/tilesets.lua", "t", {})
  if type(chunk) ~= "function" then return false end
  local ok, tilesets = pcall(chunk)
  if not ok or type(tilesets) ~= "table" then return false end
  return tilesets.TilesetPlayersHouse ~= nil or tilesets.TilesetHouse ~= nil
end

-- "Split-screen ROM selector" first-run palette (matches the FirstRun mockup):
-- a dark neon arcade panel, one column per game.
-- Red, Blue, and Yellow share the same importer flow once listed in
-- GameVersion.VERSIONS.  Values are 0-255 RGB; alpha is applied per draw.
local PAL = {
  -- radial background gradient (bright navy at top-centre -> near black)
  bgTop       = { 22, 34, 74 },   -- #16224a
  bgBot       = { 7, 11, 29 },    -- #070b1d
  -- The bright point of that gradient.  Identical to bgTop until a theme is
  -- applied, at which point LauncherTheme rewrites it as the preset's top
  -- colour with the accent mixed in -- which is what makes the accent visible
  -- across the whole screen rather than only on the links.
  bgGlow      = { 22, 34, 74 },   -- #16224a
  -- neon accents, one per cartridge
  red         = { 255, 60, 72 },  -- rgb(255,60,72)
  blue        = { 70, 150, 255 }, -- rgb(70,150,255)
  gold        = { 255, 203, 5 },  -- rgb(255,203,5)
  -- card interiors (the dark colour the accent tint fades into)
  cardRed     = { 20, 12, 26 },   -- #140c1a
  cardBlue    = { 12, 18, 40 },   -- #0c1228
  cardGold    = { 30, 22, 8 },    -- #1e1608
  -- text
  heading     = { 255, 255, 255 },
  detail      = { 198, 208, 230 }, -- #c6d0e6
  warning     = { 159, 176, 208 }, -- #9fb0d0
  link        = { 127, 208, 255 }, -- #7fd0ff, the bois.icu link
  linkHover   = { 191, 234, 255 }, -- #bfeaff, brighter on hover
  white       = { 255, 255, 255 },
  -- THE READING COLOUR, and deliberately not `white`.  Most of the launcher's
  -- text prints with this; `white` stays what it also is -- the glass sheen on
  -- a button, the 18% border highlight, the toggle knob, and the ink on a
  -- filled red or green plate where contrast against the FILL is what matters
  -- and the theme has no business changing it.  Identical to white until a
  -- text family is applied (src/import/LauncherTheme.lua).
  ink         = { 255, 255, 255 },
  -- "Play" button (green gradient) + its ink
  playTop     = { 62, 224, 138 }, -- #3ee08a
  playBot     = { 22, 163, 90 },  -- #16a35a
  playInk     = { 6, 32, 18 },    -- #062012
  -- "Choose ROM" button (red gradient)
  chooseTop   = { 255, 83, 97 },  -- #ff5361
  chooseBot   = { 214, 31, 44 },  -- #d61f2c
  -- disabled "Coming soon" button
  disabled    = { 120, 132, 158 },
  disabledInk = { 149, 161, 189 }, -- #95a1bd
  -- redesign (FirstRun.dc.html): tab chrome, cards, status pills
  green       = { 62, 224, 138 },  -- #3ee08a  "GOOD TO GO" / toggle-on / LOADED
  greenDark   = { 22, 163, 90 },   -- #16a35a
  labelGray   = { 143, 163, 200 }, -- #8fa3c8  letterspaced ROM / SAVE FILES labels
  cardBorder  = { 120, 150, 220 }, -- rgba(120,150,220,*) card + divider strokes
  slotBg      = { 9, 14, 34 },     -- rgba(9,14,34,0.6) save-slot row interior
  modDot      = { 159, 180, 221 }, -- #9fb4dd  MODS chip grid dots + underline
  -- tab-chip gradients (top -> bottom)
  chipRedTop  = { 255, 92, 103 },  -- #ff5c67
  chipRedBot  = { 181, 35, 42 },   -- #b5232a
  chipBlueTop = { 106, 168, 255 }, -- #6aa8ff
  chipBlueBot = { 30, 86, 168 },   -- #1e56a8
  chipYellowTop = { 255, 217, 74 }, -- #ffd94a
  chipYellowBot = { 199, 154, 0 },  -- #c79a00
  chipGoldTop = { 255, 196, 56 },   -- #ffc438
  chipGoldBot = { 191, 128, 0 },    -- #bf8000
  chipSilverTop = { 191, 206, 226 }, -- #bfcee2
  chipSilverBot = { 96, 116, 145 },  -- #607491
  chipCrystalTop = { 138, 226, 240 }, -- #8ae2f0
  chipCrystalBot = { 38, 122, 150 },  -- #267a96
  chipFireRedTop = { 255, 124, 72 },  -- #ff7c48  FireRed
  chipFireRedBot = { 174, 48, 27 },   -- #ae301b
  -- Emerald: the cartridge's own green, and deliberately deeper than Prism's
  -- mint so the two greens in the row are tellable apart at a glance rather
  -- than by reading their labels -- the same rule Polished Crystal's amethyst
  -- follows.
  chipEmeraldTop = { 82, 214, 130 },  -- #52d682  Emerald
  chipEmeraldBot = { 16, 110, 66 },   -- #106e42
  -- Platinum: the metal, with the cool cast its box art has -- deliberately
  -- NOT silver (#bfcee2 is near-white), not Crystal's cyan and not Polished
  -- Crystal's magenta-leaning purple, because all three sit in the same row
  -- and a chip that has to be read twice has failed.
  chipPlatinumTop = { 166, 176, 216 }, -- #a6b0d8  Platinum
  chipPlatinumBot = { 74, 82, 134 },   -- #4a5286
  chipPrismTop = { 106, 240, 150 },   -- #6af096  Prism
  chipPrismBot = { 22, 138, 82 },     -- #168a52
  -- Polished Crystal: amethyst, deliberately far from Crystal's cyan and
  -- Prism's green so three Gen 2 chips in a row stay tellable apart at a
  -- glance rather than by reading their labels.
  chipPolishedTop = { 186, 148, 252 }, -- #ba94fc  Polished Crystal
  chipPolishedBot = { 92, 56, 168 },   -- #5c38a8
  chipModTop  = { 61, 74, 109 },   -- #3d4a6d
  chipModBot  = { 32, 42, 69 },    -- #202a45
  chipInkGold = { 58, 44, 0 },     -- #3a2c00
  chipInkSilver = { 16, 23, 35 },  -- #101723
}

-- THE PALETTE IS REPAINTABLE.  Everything above is what the launcher ships
-- with; src/import/LauncherTheme.lua keeps a pristine copy of the keys a theme
-- may touch and lays the player's preset and accent over them.  Called once in
-- new() before anything draws, and again whenever either settings row steps.
-- The cartridge chip gradients are deliberately NOT themed: they are how a
-- player tells Crystal from Prism from Emerald in the row at a glance.
function RomImporter.applyTheme(options)
  local LauncherTheme = require("src.import.LauncherTheme")
  local theme, accent, text = LauncherTheme.fromOptions(options)
  LauncherTheme.apply(PAL, theme, accent, text)
  return theme, accent, text
end

-- The live palette, for tests and for anything that needs to read a colour the
-- launcher is actually drawing with rather than the one it shipped with.
function RomImporter.palette()
  return PAL
end

-- CacheFs.exists checks the game folder directly for a portable install,
-- otherwise the save directory through love.filesystem.  It honors
-- CacheFs.prefix, so we point it at the version's cache subtree (Red at the
-- root, Blue under blue/).
-- EVERY missing one, not the first: the caller needs the whole list to record
-- it, and "which files" is the question anybody debugging a re-import loop is
-- actually asking. Stopping at the first was cheaper and turned a five-file
-- gap into five successive imports to discover.
local function missingRequiredFiles(version)
  local CacheFs = require("src.import.CacheFs")
  local saved = CacheFs.prefix
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local missing = {}
  for _, path in ipairs(requiredFiles(version)) do
    if not CacheFs.exists(path) then missing[#missing + 1] = path end
  end
  for _, path in ipairs(VERSION_REQUIRED_FILES[version] or {}) do
    if not CacheFs.exists(path) then missing[#missing + 1] = path end
  end
  CacheFs.prefix = saved
  return missing
end

local function allRequiredFilesExist(version)
  return #missingRequiredFiles(version) == 0
end

-- A developer checkout / Python build leaves Red's generated data in the
-- physfs SOURCE at the un-prefixed root; that is always current.  Only Red
-- ships this way (Blue is import-only), so this stays a Red-root check.
local function sourceTreeHasData()
  if not allRequiredFilesExist("red") or not love.filesystem.getRealDirectory then
    return false
  end
  local real = love.filesystem.getRealDirectory(requiredFiles("red")[1])
  return real == love.filesystem.getSource()
end

-- ------- ROM cache location
--
-- The extracted cache (data/generated, assets/generated) plus the
-- rom-cache.complete marker normally live in LÖVE's per-user OS save
-- directory.  A portable install instead keeps them in the game folder next
-- to the executable (the folder holding portable.txt), so nothing is left on
-- the host machine.  Every cache write/read/remove goes through CacheFs,
-- which writes that folder with io.* and makes it readable (mounting it via
-- PhysFS for a fused build) -- there is no mirror step and no per-file
-- os.execute (issue #74: that flashed a console window per file on Windows
-- and froze the app).

-- Remove a cache subtree from the OS save directory.  The realDirectory
-- guard keeps this from ever deleting the game folder (portable installs
-- read the cache from there) or a developer's checked-out source tree.
local function removeTree(path)
  local info = love.filesystem.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(love.filesystem.getDirectoryItems(path)) do
      removeTree(path .. "/" .. child)
    end
  end
  if love.filesystem.getRealDirectory
      and love.filesystem.getRealDirectory(path)
        ~= love.filesystem.getSaveDirectory() then
    return
  end
  local ok, err = love.filesystem.remove(path)
  if ok == false then
    error("could not remove stale cache: " .. tostring(err))
  end
end

-- Portable installs read the cache from the game folder.  Any copy an
-- earlier non-portable run -- or the pre-#74 build, which always wrote the
-- cache to the save directory and only mirrored it out -- left behind would
-- shadow it, because physfs searches the save directory before the source.
-- Clear it out once, and only when a remnant is actually present so a clean
-- install pays nothing.
--
-- PORTABLE ONLY, AND THAT IS THE WHOLE POINT OF THE TEST BELOW.  This used to
-- run for ANY non-save root, which includes the player's chosen game-data
-- folder -- and the launcher calls readyReport for every version the moment
-- the folder changes.  So choosing a folder DELETED the installed game out of
-- AppData, a gigabyte at a time, while the new folder was still empty: the
-- next line of the same report then said "no cache for this version yet" and
-- the player was told to re-import a game they already had.
--
-- It cannot be right for a chosen folder, because the launcher offers MOVE
-- EXISTING DATA HERE for exactly this case (RomImporter:startDataMove).  A
-- purge that runs first deletes the thing the move exists to move.  The
-- shadowing the purge was there to prevent is handled where it belongs now --
-- CacheFs prepends the live root's generated trees, so the stale copy loses
-- the read path instead of being destroyed to get out of its way.
--
-- A portable install has no such action and no such choice: its root is a
-- fact about where the copy lives, so clearing the duplicate is still right.
local saveDirPurged = false
local function purgeSaveDirCache()
  if saveDirPurged then return end
  if not require("src.core.SaveData").isPortable() then return end
  saveDirPurged = true
  local saveDir = love.filesystem.getSaveDirectory()
  local function saveDirHas(rel)
    local f = io.open(saveDir .. "/" .. rel, "rb")
    if not f then return false end
    f:close()
    return true
  end
  -- Purge each version's stale save-directory copy (Red at the root, Blue
  -- under blue/) so it cannot shadow the portable game-folder cache.
  for _, version in ipairs(GameVersion.ORDER) do
    local prefix = GameVersion.cachePrefix(version)
    if saveDirHas(prefix .. MARKER_PATH)
        or saveDirHas(prefix .. requiredFiles(version)[1]) then
      removeTree(prefix .. "data/generated")
      removeTree(prefix .. "assets/generated")
      love.filesystem.remove(prefix .. MARKER_PATH)
    end
  end
end

-- Whether a given version's cache is current, AND WHY NOT WHEN IT IS NOT.
--
-- Returns { ok = bool, why = string|nil, missing = { path, ... } }. A bare
-- boolean was the whole difficulty in every re-import report this has ever
-- produced: three separate gates answer here, the launcher turns any `false`
-- into a three-minute extraction, and nothing anywhere said which gate or
-- which file. Somebody watching their ROM re-import on every launch could not
-- find out more than that it happened.
function RomImporter.readyReport(version)
  version = version or "red"
  local CacheFs = require("src.import.CacheFs")
  if CacheFs.rootReport().kind == "portable" then
    -- Portable: the cache lives in the game folder next to the executable
    -- (mounted onto the read path for a fused build).  Drop any stale
    -- save-directory copy that would otherwise shadow it at runtime.
    --
    -- ASKS rootReport, NOT root().  root() is non-nil for a chosen game-data
    -- folder too, and purging on that one destroyed the installed game the
    -- moment the setting changed -- see purgeSaveDirCache above.
    purgeSaveDirCache()
  end
  -- Red generated data in the physfs source (developer checkout / Python
  -- build) is always current; Blue is import-only and falls through to the
  -- version-marker gate.
  if version == "red" and sourceTreeHasData() then
    return { ok = true, missing = {} }
  end
  local saved = CacheFs.prefix
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local raw = CacheFs.read(MARKER_PATH)
  CacheFs.prefix = saved

  local head, absent = parseMarker(raw)
  if head ~= markerFor(version) then
    return { ok = false, missing = {},
             why = (raw == nil) and "no cache for this version yet"
               or "the cache was built by another version of this app, or "
                  .. "from a different ROM" }
  end

  -- KNOWN-ABSENT FILES ARE NOT A REASON TO RUN AGAIN. The import that wrote
  -- this marker already tried, at this cache format, against this ROM.
  local missing, gaps = {}, {}
  for _, path in ipairs(missingRequiredFiles(version)) do
    if absent[path] then gaps[#gaps + 1] = path else missing[#missing + 1] = path end
  end
  if #missing > 0 then
    return { ok = false, missing = missing,
             why = "the cache is missing " .. tostring(#missing)
                   .. " file(s) a finished import writes" }
  end
  if not gen2TilesetRegistryLooksValid(version) then
    -- Recorded the same way, and for the same reason: a hack whose tilesets
    -- carry none of the names this test knows would otherwise re-import for
    -- ever without the answer ever changing.
    if not absent["<tileset-registry>"] then
      return { ok = false, missing = { "data/generated/tilesets.lua" },
               why = "the tileset registry does not look like a Gen 2 one" }
    end
  end
  return { ok = true, missing = {}, gaps = gaps }
end

-- Whether a given game version's ROM has already been imported and cached.
function RomImporter.isReady(version)
  return RomImporter.readyReport(version).ok
end

-- Load the import manifest for a version and confirm it matches that ROM.
local function decodeManifest(version)
  local path = GameVersion.info(version).manifest
  local raw, readError = love.filesystem.read(path)
  if not raw then error("ROM import metadata is missing: " .. tostring(readError)) end
  local Json = require("src.link.Json")
  local manifest, decodeError = Json.decode(raw)
  if not manifest then error("ROM import metadata is invalid: " .. tostring(decodeError)) end
  -- acceptsSha1, not equality: Crystal's two revisions share one manifest, so
  -- the manifest's own romSha1 is only ever one of the accepted dumps.
  assert(GameVersion.acceptsSha1(version, manifest.romSha1),
    "ROM import metadata version mismatch")
  return manifest
end

-- The last gate before an import actually runs.  The panel already disables
-- the button for a version with `importable = false`, but that is only the UI:
-- a drag-and-drop, a CLI path or a future entry point could still reach here.
-- A version the build has deliberately withheld must be refused wherever the
-- import is started, not just where it is drawn.
--
-- POKEPORT_UNLOCK is the one way past it, and it exists so that WORKING on a
-- withheld version does not mean shipping it.  The gate is what a player
-- meets; the extractor still has to be exercised against the ROM to be fixed
-- at all, and with no escape hatch the only way to re-import Prism after an
-- extractor change was to edit GameVersion and remember to put it back.  Set
-- it to a version id, or to a comma-separated list, or to `1`/`all` for every
-- withheld version:
--
--   POKEPORT_UNLOCK=prism ./Play-Windows.bat
--
-- Deliberately an environment variable rather than a setting: it does not
-- persist, it does not appear in any menu, and a normal launch never has it.
local function unlockedByEnv(version)
  local value = os.getenv("POKEPORT_UNLOCK")
  if not value or value == "" then return false end
  value = value:lower()
  if value == "1" or value == "all" then return true end
  for id in value:gmatch("[^,%s]+") do
    if id == tostring(version):lower() then return true end
  end
  return false
end

local function blockedImportReason(version, manifest)
  local info = GameVersion.info(version)
  if info and info.importable == false and not unlockedByEnv(version) then
    return (info.launcherName or info.displayName or version)
      .. " is not ready to play yet"
  end
  return nil
end

local function sha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

local function readExternalPath(path)
  local file, openError = io.open(path, "rb")
  if not file then return nil, openError end
  local data = file:read("*a")
  file:close()
  return data
end

local function readDroppedFile(file)
  local ok, openError = file:open("r")
  if not ok then return nil, openError end
  local data, readError = file:read(file:getSize())
  file:close()
  return data, readError
end

local function trim(value)
  return value and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

-- Turn a filesystem path into a well-formed file:// URI for love.system.openURL.
-- openURL feeds SDL_OpenURL, whose macOS backend ([NSURL URLWithString:]) returns
-- nil for any unencoded space -- and the default save dir lives under
-- "Application Support" -- so the click silently no-ops on real macOS installs.
-- Windows needs forward slashes and a leading slash on the drive path so the
-- authority is empty (file:///C:/...), not a hostname.  Percent-encode the rest
-- (spaces -> %20) but keep the unreserved set plus "/" and ":" (drive letter and
-- path separators stay literal so the shell resolves the folder).
local function fileUrl(path)
  path = tostring(path):gsub("\\", "/")
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  local encoded = path:gsub("[^%w%-%._~/:]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return "file://" .. encoded
end

-- The native pickers below block the whole loop inside io.popen, and they are
-- opened straight out of mousepressed -- with the button still physically
-- down.  SDL auto-captures the pointer for the length of a press (on X11 an
-- XGrabPointer with owner_events) and only drops that capture when it
-- processes the matching button-up, which it cannot do while we sit in popen
-- and never pump.  The grab then outlives the click and every pointer event
-- over the file chooser is still routed to our window: the dialog draws and
-- keyboard-navigates (keyboard focus is a separate grab) but ignores the
-- mouse entirely -- issue #254 on Linux.  Whether it bites is a race with how
-- long the click was held, which is why the same build picks one ROM fine and
-- then hangs the mouse on the next.  So pump until no button is held, letting
-- SDL see the release and let go first; bounded, so a stuck button costs a
-- moment and never the launcher.  pump() only drains OS events into LOVE's
-- queue -- it dispatches nothing -- so there is no reentry into mousepressed
-- and the release is still delivered normally on the next frame.
local function releasePointerGrab()
  if not (love.mouse and love.mouse.isDown and love.event and love.event.pump
      and love.timer) then
    return
  end
  local deadline = love.timer.getTime() + 1
  while love.mouse.isDown(1, 2, 3) do
    love.event.pump()
    if love.timer.getTime() > deadline then break end
    love.timer.sleep(0.005)
  end
end

local function commandOutput(command)
  releasePointerGrab()
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local result = pipe:read("*a")
  pipe:close()
  result = trim(result)
  return result ~= "" and result or nil
end

-- A Game Boy cartridge is 1 MiB (Red/Blue/Yellow) or 2 MiB (Gold/Silver and
-- the Crystal hacks).  A Game Boy ADVANCE cartridge is none of those: Emerald
-- is 16 MiB, and this predicate rejecting it is why a perfectly good dump came
-- back as "Expected a 1 MiB ... Game Boy ROM; this file is 16.00 MiB."
--
-- The other GBA sizes are listed too.  Only 16 MiB is reachable today, but a
-- size table that admits exactly one cartridge is the same trap this one was:
-- it looks like a check and behaves like a hardcoded constant.
local ROM_SIZES = {
  [1024 * 1024] = true,        -- Game Boy
  [2 * 1024 * 1024] = true,    -- Game Boy Color
  [4 * 1024 * 1024] = true,    -- Game Boy Advance, from here down
  [8 * 1024 * 1024] = true,
  [16 * 1024 * 1024] = true,   -- Emerald
  [32 * 1024 * 1024] = true,
  -- ...and up here, a NINTENDO DS cartridge.  Platinum is 128 MiB, four times
  -- the largest Game Boy Advance cart, and the jump is why this is listed
  -- rather than folded into a range: the size table exists so a file that
  -- cannot be a cartridge is refused before it is hashed, and a range would
  -- wave through every truncated dump in between.
  [128 * 1024 * 1024] = true,  -- Platinum, and Diamond/Pearl after it
}

local function isSupportedRomSize(byteLength)
  return ROM_SIZES[byteLength] == true
end

-- One test, used everywhere a file is judged by its name.  There were five
-- copies of `%.gbc?$` scattered through this file and every one of them had to
-- be found and changed to let a .gba through -- which is exactly the kind of
-- thing that gets four out of five.
local function isRomFileName(name)
  local n = (name or ""):lower()
  return n:match("%.gb$") ~= nil or n:match("%.gbc$") ~= nil
         or n:match("%.gba$") ~= nil or n:match("%.nds$") ~= nil
end

-- LOVE 11.5 on Android has no native file picker (love.window.showFileDialog
-- is a LOVE 12 nightly-only addition) and never fires love.filedropped, so
-- neither desktop path below works there. conf.lua points the Android save
-- directory at the app's external-files folder instead (readable/writable
-- via USB or a file manager, no runtime permission needed), and this scans
-- it directly through love.filesystem -- already mounted at the physfs
-- root, so no io.* absolute-path handling is needed.
--
-- Only a .gb/.gbc whose SHA maps to a version that is not yet ready counts as
-- pending.  GameActivity always writes the SAF pick to picked_rom.gb, so a
-- naive "first ROM wins" scan would re-import Red when the player tries to
-- add Blue (issue #167). Yellow and Gen2 carts are typically .gbc.
-- The Switch has no file picker and no drag-and-drop, so the ROM arrives as
-- a file the player copied onto the SD card (MTP, DBI, or the card in a PC).
-- It goes in an `imports/` folder inside the save directory: a plain named
-- inbox is something a player can be told to use, where "the save directory
-- root" is a folder full of the game's own state.  Ported from gen1recomp,
-- whose Switch build has always worked this way; scripts/switch/pack_sd_zip.sh
-- ships the folder pre-made with a README in it.
local IMPORTS_DIR = "imports"

local MODS_INBOX_DIR = "imports/mods"
-- Battery saves get their own inbox for the same reason mods do: a .sav in the
-- save-dir root is ambiguous, and on a console the named folder is the ONLY
-- way to hand the game a file at all.
local SAVES_INBOX_DIR = "imports/saves"

function RomImporter:ensureImportsDir()
  local info = love.filesystem.getInfo(IMPORTS_DIR)
  if info and info.type == "directory" then return true end
  if info then return false end   -- a FILE named imports/ -- do not clobber it
  if love.filesystem.createDirectory then
    return love.filesystem.createDirectory(IMPORTS_DIR)
  end
  return false
end

function RomImporter:ensureSavesInboxDir()
  self:ensureImportsDir()
  local info = love.filesystem.getInfo(SAVES_INBOX_DIR)
  if info and info.type == "directory" then return true end
  if info then return false end
  if love.filesystem.createDirectory then
    return love.filesystem.createDirectory(SAVES_INBOX_DIR)
  end
  return false
end

-- Mods get their own inbox so a .zip cannot be mistaken for a cartridge and
-- vice versa.  createDirectory does NOT create parents, so imports/ first.
function RomImporter:ensureModsInboxDir()
  self:ensureImportsDir()
  local info = love.filesystem.getInfo(MODS_INBOX_DIR)
  if info and info.type == "directory" then return true end
  if info then return false end
  if love.filesystem.createDirectory then
    return love.filesystem.createDirectory(MODS_INBOX_DIR)
  end
  return false
end

-- love.filesystem paths on the Switch read "sdmc:/switch/...", but MTP tools
-- (DBI, OpenMTP) show the card root as "1: SD Card", so the sdmc: prefix is
-- noise there.  Strip it ONLY when it is actually present.
function RomImporter.mtpHintPath(saveDir)
  if type(saveDir) ~= "string" then return "" end
  if saveDir:sub(1, 6) == "sdmc:/" then return saveDir:sub(7) end
  return saveDir
end

-- Every .gb/.gbc under `dir`, skipping AppleDouble junk: a Mac writes
-- "._cart.gb" beside "cart.gb" on a FAT card, and it ends in .gb but is a
-- 4 KB resource fork, so an unfiltered scan tries it first and reports the
-- real dump as missing.
local function listRomPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if isRomFileName(name) and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

-- imports/ first, then the save-dir root, so a player who dropped the cart
-- in either place is served -- and so the platforms that have always scanned
-- the root keep behaving exactly as before.
local function pendingRomPaths()
  local paths = {}
  for _, path in ipairs(listRomPaths(IMPORTS_DIR)) do paths[#paths + 1] = path end
  for _, path in ipairs(listRomPaths("")) do paths[#paths + 1] = path end
  return paths
end

-- WHERE A PENDING FILE REALLY IS ON DISK, which a Gen 4 import cannot do
-- without.
--
-- Reported from play on Android: "failed to import please import from a file on
-- disk but i did import from a file on disk". Both halves are true and the
-- message was the misleading part. The Android route never goes through
-- `startPath`; it scans the save directory with `love.filesystem` and calls
-- `startData(data, name)` with NO third argument, so `self.romPath` is nil --
-- and `RomExtractorGen4` is the one extractor that takes a PATH rather than
-- bytes, because a 128 MB DS cartridge is reopened rather than carried. So the
-- "must be imported from a file on disk" guard fired on every Android Platinum
-- import, however the file got there.
--
-- The file IS on disk: `love.filesystem.getRealDirectory` names the directory it
-- was actually found in -- the save directory for a SAF pick or a USB copy, or
-- the game directory on an unpacked handheld build -- and both are readable by
-- `io.open` from our own process.
--
-- PROBED, NOT ASSUMED. A file found inside the mounted .love (a zip) has a real
-- directory too and cannot be opened as a file, so the open is the test. Nil
-- here leaves the old guard to fire, which is the honest answer for that case.
local function realPathFor(name)
  local ok, dir = pcall(love.filesystem.getRealDirectory, name)
  if not ok or type(dir) ~= "string" or dir == "" then return nil end
  local path = dir .. "/" .. name
  local handle = io.open(path, "rb")
  if not handle then return nil end
  handle:close()
  return path
end

-- `skip` holds the names of files whose import has already FAILED this session.
--
-- Reported in the same breath: "its also preventing people from importing other
-- roms after getting the error on android". That is this loop. It returns the
-- FIRST pending file whose version is not ready, and a cart that fails is still
-- pending -- so the next Choose finds the same one, fails the same way, and no
-- other cartridge can ever be reached. One bad file blocked the whole importer.
--
-- Skipped rather than deleted: the file is the player's, it may be perfectly
-- good and merely unsupported on this build, and quietly removing someone's ROM
-- is not ours to do. The set lives for the session, so relaunching retries.
local function findPendingRom(ready, skip)
  for _, name in ipairs(pendingRomPaths()) do
    if not (skip and skip[name]) then
      local data = love.filesystem.read(name)
      if type(data) == "string" and isSupportedRomSize(#data) then
        local version = GameVersion.forSha1(sha1(data))
        if version and not ready[version] then
          return name, data, realPathFor(name)
        end
      end
    end
  end
  return nil
end

-- GameActivity always writes the SAF pick to picked_rom.gb, so a leftover
-- under that exact basename is the file the player just chose and
-- findPendingRom silently refused: wrong size, or a hacked/overdumped cart
-- whose SHA-1 matches no known version ([b]/[BF] dumps never will).  Route it
-- through startData so the launcher says which of the two it was instead of
-- staying on "No ROM imported" with no message at all (issue #442), and drop
-- the file so the next tap starts from a clean slate.  A cart that is simply
-- already imported is not an error -- #167 skips it on purpose -- so leave
-- that one alone.
local function consumePickedRomError(self)
  local preferred = "picked_rom.gb"
  if not love.filesystem.getInfo(preferred, "file") then return false end
  local data = love.filesystem.read(preferred)
  if type(data) == "string" and isSupportedRomSize(#data) then
    local version = GameVersion.forSha1(sha1(data))
    if version and self.ready[version] then return false end
  end
  love.filesystem.remove(preferred)
  if type(data) ~= "string" then
    self:setError("The picked file could not be read. Reopen the picker and "
      .. "choose the ROM with the Files (Documents) app.")
    return true
  end
  self:startData(data, preferred)
  return true
end

-- Android SAF writes mod picks to picked_mod.zip; USB copies may use any
-- .zip basename at the save-dir root.  preferAny=true also accepts those USB
-- copies (Choose / Import); focus only consumes the SAF basename so a random
-- leftover archive is never auto-installed on every refocus.
-- Every .zip under `dir`, skipping AppleDouble junk: "._mod.zip" ends in
-- .zip but is a resource fork, and PhysFS fails to mount it as an archive.
local function listZipPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if name:lower():match("%.zip$") and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

local function findPendingMod(preferAny, skip)
  local preferred = "picked_mod.zip"
  if love.filesystem.getInfo(preferred, "file") then
    return preferred
  end
  if not preferAny then return nil end
  -- imports/mods/ first, then the save-dir root.  Consoles have no picker,
  -- so the named inbox is the only way to hand the game a mod; the root scan
  -- stays for every platform that already relied on it.
  for _, path in ipairs(listZipPaths(MODS_INBOX_DIR)) do
    if not (skip and skip[path]) then return path end
  end
  for _, path in ipairs(listZipPaths("")) do
    if not (skip and skip[path]) then return path end
  end
  return nil
end

-- Same pattern as findPendingMod for battery saves (picked_save.sav / *.sav):
-- the picker's own drop first, then imports/saves/, then the save-dir root.
local function listSavPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if name:lower():match("%.sav$") and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

local function findPendingSav(preferAny, skip)
  local preferred = "picked_save.sav"
  if love.filesystem.getInfo(preferred, "file") then
    return preferred
  end
  if not preferAny then return nil end
  for _, path in ipairs(listSavPaths(SAVES_INBOX_DIR)) do
    if not (skip and skip[path]) then return path end
  end
  for _, path in ipairs(listSavPaths("")) do
    if not (skip and skip[path]) then return path end
  end
  return nil
end

-- Retire an Android pick once it has been through the installer / importer,
-- whether or not it worked: a pick left on disk wins the scans above forever,
-- so the next tap re-runs the same failing file and the picker never reopens
-- (#420).  The SAF basename is GameActivity's own copy of the pick and is
-- always deleted; a USB copy is the player's file, so a failed one is only
-- skipped for the rest of the session.
local function consumePick(self, name, safName, ok)
  if ok or name == safName then
    love.filesystem.remove(name)
    return
  end
  self.pickSkip = self.pickSkip or {}
  self.pickSkip[name] = true
end

local function chooseRom(promptName)
  promptName = promptName or "Pokemon"
  local prompt = "Choose your " .. promptName .. " ROM"
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"gb", "gbc", "gba", "nds"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Pokemon ROM (*.gb;*.gbc;*.gba;*.nds)|*.gb;*.gbc;*.gba;*.nds|All files (*.*)|*.*';",
      -- write the pick as UTF-8: the console's OEM codepage would mangle
      -- non-ASCII names (Pokémon -> Pok\x82mon) and crash any text draw
      -- that shows them (#325)
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Pokemon ROM | *.gb *.gbc *.gba *.nds" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.gb *.gbc *.gba *.nds|Pokemon ROM" 2>/dev/null]])
  end
  return nil
end

-- WHAT A MULTI-SELECT DIALOG ACTUALLY SAID, and nothing else.
--
-- Every one of these pickers is a shell command whose stdout is trusted as a
-- list of paths, and that trust is what turned one broken PowerShell script
-- into twenty-six "failed" imports named after the lines of a parser error.
-- So a line only counts as a pick if it OPENS: a real chooser answers with
-- files that exist, and anything else -- a diagnostic, a usage message, a
-- shell complaint about a missing zenity -- does not.
--
-- Answering nil when nothing survives is deliberate: to every caller that is
-- "the dialog was cancelled", which is already handled and already harmless,
-- rather than an error the player has to read.
-- DID A DIALOG EVEN RUN?
--
-- The difference between "the player said no" and "there is nothing here to
-- ask with", which the pickers cannot tell apart on their own -- both answer
-- nil.  It decides whether an empty answer falls back to the save-dir inbox
-- (a console, where the inbox is the only way in) or is simply taken as no (a
-- desktop, where quietly importing a folder somebody did not choose would be
-- the surprise).
local function hasNativePicker()
  local platform = love.system.getOS()
  return platform == "OS X" or platform == "Windows" or platform == "Linux"
end

local function pickedFileList(out)
  if not out or out == "" then return nil end
  local paths = {}
  for line in tostring(out):gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      local probe = io.open(trimmed, "rb")
      if probe then
        probe:close()
        paths[#paths + 1] = trimmed
      end
    end
  end
  if #paths == 0 then return nil end
  return paths
end

-- ...AND THE SAME THING FOR CARTRIDGES.
--
-- Asked for directly: "add in a button to mass import roms for those
-- available in our game next to the gen select button".  Nine games are
-- registered now and each one was its own trip through a file dialog, on a
-- tab you had to find first -- and the tab is not even the thing that decides
-- which game a ROM becomes, because startData routes by SHA-1.
--
-- Same per-OS multi-select as chooseZips, with the ROM filter chooseRom uses.
local function chooseRoms()
  local prompt = Strings("Choose your Pokemon ROMs")
  local platform = love.system.getOS()
  local out
  if platform == "OS X" then
    out = commandOutput(
      ([[osascript -e 'set AppleScript'"'"'s text item delimiters to linefeed' ]]
       .. [[-e 'set f to choose file with prompt "%s" of type {"gb", "gbc", "gba", "nds"} with multiple selections allowed' ]]
       .. [[-e 'set p to {}' -e 'repeat with x in f' ]]
       .. [[-e 'set end of p to POSIX path of x' -e 'end repeat' ]]
       .. [[-e 'p as text' 2>/dev/null]]):format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Multiselect=$true;",
      "$d.Filter='Pokemon ROM (*.gb;*.gbc;*.gba;*.nds)|*.gb;*.gbc;*.gba;*.nds|All files (*.*)|*.*';",
      -- NOT copied to a temp name, unlike the mod picker: a batch of these is
      -- up to sixteen megabytes apiece and copying them all before reading any
      -- of them is a doubling of disk for nothing.  A non-ASCII path is the
      -- cost (io.open on Windows needs ANSI bytes) and it is reported per file
      -- as "could not be read" rather than taking the run down.
      "if($d.ShowDialog() -eq 'OK'){",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      -- [char]10, NOT "`n".  The whole script is handed to powershell inside
      -- `-Command "..."`, so every double quote in it is eaten before
      -- PowerShell ever sees the text -- `$o -join "`n"` arrives as
      -- `$o -join `n` and dies at the parse ("You must provide a value
      -- expression following the '-join' operator"), which is a dialog that
      -- never opens and an error where the file list should be.  Nothing else
      -- in this file quotes with " for the same reason; these two were the
      -- exception and the exception was the bug.
      "[Console]::Write($d.FileNames -join [char]10)}",
    })
    out = commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    out = commandOutput(
      -- `--separator="\n"` hands zenity a literal backslash-n (the shell does
      -- not expand escapes inside double quotes), so the list came back as one
      -- long line.  Ask for zenity's own default separator and turn it into
      -- newlines with tr, which needs nothing of the shell.
      ([[zenity --file-selection --multiple --separator="|" --title="%s" --file-filter="Pokemon ROM | *.gb *.gbc *.gba *.nds" 2>/dev/null | tr '|' '\n']])
        :format(prompt))
    if not out then
      local kd = commandOutput(
        [[kdialog --getopenfilename "$HOME" "*.gb *.gbc *.gba *.nds|Pokemon ROM" --multiple 2>/dev/null]])
      -- kdialog joins with spaces and quotes nothing, so a path with a space
      -- in it cannot be recovered; one file back is still one file
      if kd then out = kd:gsub("%s+", "\n") end
    end
  end
  return pickedFileList(out)
end

-- Open a native picker for a mod .zip (mirrors chooseRom's per-OS dialogs).
-- Returns the chosen absolute path or nil.  Android uses love.system.pickFile
-- ("mod") instead -- see RomImporter:chooseMod.
local function chooseZip()
  local prompt = Strings("Choose a mod .zip")
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"zip"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Mod archive (*.zip)|*.zip|All files (*.*)|*.*';",
      -- copy the pick to a plain-ASCII temp name and answer with that:
      -- the console's OEM codepage would mangle a non-ASCII path
      -- (Pokémon -> Pok\x82mon) and io.open on Windows needs ANSI bytes,
      -- so returning the original name both crashed the notice draw and
      -- could never have opened the file (#325)
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_mod_pick.zip';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Mod archive | *.zip" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.zip|Mod archive" 2>/dev/null]])
  end
  return nil
end

-- MANY AT ONCE, from the same native dialogs the single import uses.
--
-- Asked for directly: "add a way to mass import mods".  Each platform's
-- picker already supports a multiple selection; the launcher just never asked
-- for one.  Answers a LIST of absolute paths, or nil where there is no picker
-- (console, a handheld with neither zenity nor kdialog), which is the same
-- "nil means fall back to the inbox" contract chooseZip has.
--
-- The separator is what makes this awkward rather than hard: a path may
-- contain spaces on every one of these systems, so none of them can be split
-- on whitespace.  macOS and Windows are told to join with a newline, and
-- zenity is asked for one explicitly; kdialog answers space-separated and is
-- therefore only trusted when nothing it returned contains a space, which is
-- the honest limit rather than a silently wrong split.
local function chooseZips()
  local prompt = Strings("Choose mod .zip files")
  local platform = love.system.getOS()
  local out
  if platform == "OS X" then
    out = commandOutput(
      ([[osascript -e 'set AppleScript'"'"'s text item delimiters to linefeed' ]]
       .. [[-e 'set f to choose file with prompt "%s" of type {"zip"} with multiple selections allowed' ]]
       .. [[-e 'set p to {}' -e 'repeat with x in f' ]]
       .. [[-e 'set end of p to POSIX path of x' -e 'end repeat' ]]
       .. [[-e 'p as text' 2>/dev/null]]):format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Multiselect=$true;",
      "$d.Filter='Mod archive (*.zip)|*.zip|All files (*.*)|*.*';",
      -- the same plain-ASCII temp copy the single picker makes, once per
      -- pick: the console codepage would mangle a non-ASCII path and io.open
      -- could never reopen it (#325)
      "if($d.ShowDialog() -eq 'OK'){",
      "$i=0;$o=@();",
      "foreach($f in $d.FileNames){",
      "$t=Join-Path $env:TEMP ('pokeport_mod_pick_'+$i+'.zip');",
      "Copy-Item -LiteralPath $f -Destination $t -Force;",
      "$o+=$t;$i++};",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      -- see chooseRoms: a double quote cannot survive the -Command wrapper
      "[Console]::Write($o -join [char]10)}",
    })
    out = commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    out = commandOutput(
      -- see chooseRoms on the separator
      ([[zenity --file-selection --multiple --separator="|" --title="%s" --file-filter="Mod archive | *.zip" 2>/dev/null | tr '|' '\n']])
        :format(prompt))
    if not out then
      local kd = commandOutput(
        [[kdialog --getopenfilename "$HOME" "*.zip|Mod archive" --multiple 2>/dev/null]])
      -- kdialog joins with spaces and quotes nothing, so a path containing a
      -- space cannot be recovered.  One file back is still one file.
      if kd then out = kd:gsub("%s+", "\n") end
    end
  end
  return pickedFileList(out)
end

-- ...and a FOLDER, for the other half of the same request: point at where the
-- releases live and take everything in it.  LauncherMods.zipsInFolder decides
-- what counts as "in it" (the folder and one level under).
-- `prompt` is optional: the game-data folder row opens the same dialog with a
-- different question, and a picker whose title says "mod .zip files" while it
-- is choosing where to install games is a picker a player closes again.
local function chooseFolder(prompt)
  prompt = prompt or Strings("Choose a folder of mod .zip files")
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose folder with prompt "%s")' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.FolderBrowserDialog;",
      "$d.Description='" .. prompt .. "';",
      "if($d.ShowDialog() -eq 'OK'){",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($d.SelectedPath)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --directory --title="%s" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getexistingdirectory "$HOME" 2>/dev/null]])
  end
  return nil
end

-- Open a native picker for a mod's declared base file (`required_imports`).
-- The extension list comes from the manifest rather than being fixed, because
-- what a mod needs is its own business: STADIUM2_IMPORTER wants a Nintendo 64
-- cartridge in any of its three byte orders (.z64/.n64/.v64).
local function chooseFileByExt(exts, promptName)
  if type(exts) ~= "table" or #exts == 0 then return nil end
  local prompt = Strings("Choose your %s", promptName or "file")
  local platform = love.system.getOS()
  local quoted, globs, semis = {}, {}, {}
  for index, ext in ipairs(exts) do
    quoted[index] = '"' .. ext .. '"'
    globs[index] = "*." .. ext
    semis[index] = "*." .. ext
  end
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {%s})' 2>/dev/null]])
        :format(prompt, table.concat(quoted, ", ")))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Base file (" .. table.concat(semis, ";") .. ")|"
        .. table.concat(semis, ";") .. "|All files (*.*)|*.*';",
      -- THE TEMP COPY IS THE FALLBACK NOW, NOT THE DEFAULT.
      --
      -- io.open on Windows needs ANSI bytes, so a path with characters outside
      -- them cannot be opened at all (#325) and the pick has to be copied to
      -- an ASCII temp name first.  That was done for EVERY pick, on the
      -- reasoning that "a cartridge is tens of megabytes, so this copy is the
      -- one slow step" -- which stopped being true the moment a mod could
      -- declare a GameCube disc.  A 1.4 GB pick was copied into %TEMP% on the
      -- system drive before anything looked at it: minutes of apparent freeze,
      -- 1.4 GB of C: needed to import a file already sitting on G:, and -- the
      -- reported failure -- Copy-Item leaves $ErrorActionPreference at
      -- Continue, so a copy that ran out of space still fell through to
      -- writing the temp path, and the launcher opened a file that was never
      -- created.  "that file could not be opened", for a file that was right
      -- there.
      --
      -- So: an ASCII path is handed back AS IS, which is every ordinary path
      -- and costs nothing.  Only a path io.open genuinely cannot take is
      -- copied, and that copy now has to prove it landed before its
      -- destination is reported -- otherwise nothing is written and the
      -- caller falls through to the "copy it into imports/" instructions,
      -- which at least tell the player what to do next.
      "if($d.ShowDialog() -eq 'OK'){",
      "$p=$d.FileName;",
      "$ascii=$true;",
      "foreach($c in $p.ToCharArray()){",
      "if([int]$c -lt 32 -or [int]$c -gt 126){$ascii=$false}};",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "if($ascii){[Console]::Write($p)}else{",
      "$t=Join-Path $env:TEMP 'pokeport_base_pick.bin';",
      "Copy-Item -LiteralPath $p -Destination $t -Force "
        .. "-ErrorAction SilentlyContinue;",
      "if(Test-Path -LiteralPath $t){[Console]::Write($t)}}}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Base file | %s" 2>/dev/null]])
        :format(prompt, table.concat(globs, " ")))
    if path then return path end
    return commandOutput(
      ([[kdialog --getopenfilename "$HOME" "%s|Base file" 2>/dev/null]])
        :format(table.concat(globs, " ")))
  end
  return nil
end

-- PUBLISHED, because the map editor needs a picker too.
--
-- It imports character sheets from PNGs and maps from other cartridges, and
-- both want exactly this: a native dialog, filtered to an extension list, that
-- goes through `commandOutput` -- which releases the pointer grab SDL is
-- still holding from the click that opened it (#254) and tolerates the
-- platforms where `io.popen` raises rather than returning nil.
--
-- Publishing the existing one rather than writing a second: there is a
-- regression test asserting every desktop picker funnels through the one
-- `io.popen` call, and a panel with its own copy would be the exception that
-- makes that test a lie.
RomImporter.chooseFileByExt = chooseFileByExt

-- Open a native picker for a raw .sav battery save (mirrors chooseZip's per-OS
-- dialogs).  Returns the chosen absolute path or nil.  Android uses
-- love.system.pickFile("sav") instead -- see RomImporter:chooseSaveImport.
local function chooseSav()
  local prompt = Strings("Choose a .sav save file")
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"sav"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Game Boy save (*.sav)|*.sav|All files (*.*)|*.*';",
      -- UTF-8, like the ROM and mod pickers (#325)
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Game Boy save | *.sav" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.sav|Game Boy save" 2>/dev/null]])
  end
  return nil
end

-- The self-updater only surfaces on the real distributed build: a fused,
-- interactive launcher with no scripted-run override.  A dev / source checkout
-- (unfused, where Boot.run already no-ops) or an autopilot / driver /
-- import-only run all skip the release check so headless and CI runs never spin
-- up the background worker or reach out to the network.
local function updaterAllowed()
  if not (love.filesystem.isFused and love.filesystem.isFused()) then return false end
  if os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER") then return false end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  return true
end

-- The launcher runs each GameVersion as an independent tab.  Each dropped or
-- chosen ROM is routed to its version by SHA-1, extracted into that version's
-- own cache (Red at the root, Blue under blue/, Yellow under yellow/), so all
-- can be imported and played side by side.  onComplete(version) hands the
-- chosen game off to boot.
-- opts: launcher (a fresh import stays on the launcher instead of auto-booting),
-- forceImport (treat every version as not-yet-imported, so re-import is forced),
-- onEditSave(version, slotId) (host handler for the Edit affordance on a save
-- row -- main.lua opens the bundled save editor on that slot; when it is not
-- supplied the Edit label is not drawn at all),
-- onEditTouchControls() (host handler for the Touch Controls button -- main.lua
-- opens the layout editor; when it is not supplied the button is not drawn),
-- onEditMaps(version) (host handler for the Map Editor button -- main.lua opens
-- the bundled editor in map mode on that game; drawn only when supplied AND
-- the game is imported, because the editor has nothing to show otherwise).
function RomImporter.new(onComplete, opts)
  opts = opts or {}
  -- iOS rides the same mobile import flows as Android: the save-dir
  -- pending-file scan plus love.system.pickFile / createFile, provided
  -- natively by the Swift GRPickerBridge (mobile/ios/native/).  The flag
  -- keeps its historical name so every Android call site stays untouched.
  local mobileOS = love.system.getOS()
  local android = mobileOS == "Android" or mobileOS == "iOS"
  BootTrace.mark("launcher: platform " .. tostring(mobileOS))
  local CacheFs = require("src.import.CacheFs")
  local self = setmetatable({
    onComplete = onComplete,
    launcher = opts.launcher or false,
    forceImport = opts.forceImport or false,
    onEditSave = opts.onEditSave,
    onEditTouchControls = opts.onEditTouchControls,
    onEditMaps = opts.onEditMaps,
    android = android,
    -- Read by the three console-inbox branches below.  It was never assigned,
    -- so every one of them leaned entirely on the romImportMode fallback
    -- beside it; naming the platform once makes those reads mean something.
    isNX = require("src.core.Platform").isNX(),
    ios = mobileOS == "iOS",
    -- love-nx reports "NX".  Nothing in this tree knew that string, so the
    -- Switch fell through every platform branch to the desktop one and was
    -- told to use a file picker it does not have.
    isNX = Platform.isNX(),
    -- One startup poll pass on both mobiles.  iOS: files dropped through the
    -- Files app are swept into the save dir before Lua boots (GRBootstrap) with
    -- no love.focus event necessarily following.  Android: the SAF picker is a
    -- separate activity, and Android is free to destroy GameActivity while it
    -- is up (memory pressure, or "Don't keep activities"), so the app RESTARTS
    -- instead of resuming and the love.focus(true) that would have consumed the
    -- pick never arrives.  The file is sitting in the save dir either way, so
    -- boot armed and let the first poll tick consume it, rather than making the
    -- player tap Import a second time to trigger the scan by hand (#553).
    pickPending = android or nil,
    -- Android drag: the launcher is handed no move events at all (main.lua
    -- forwards neither touchmoved nor mousemoved while it is up), and its mouse
    -- emulation is what "no reliable pointer polling" below refers to.
    -- love.touch IS pollable, so where it exists a touch drag can be resolved
    -- inside draw the same way the desktop mouse is.  Where it does not, every
    -- Android path stays exactly as it was: act on press, never arm.
    touchPollable = android and love.touch ~= nil
      and love.touch.getTouches ~= nil and love.touch.getPosition ~= nil,
    -- The settings drawer: whether it is up, which of its two pages is
    -- showing (nil = the main one, "launcher" = LAUNCHER SETTINGS), and which
    -- generation the GAME DEFAULTS rows are being set for (nil = all).
    settingsOpen = false,
    settingsPage = nil,
    settingsGen = nil,
    settingsScroll = 0,
    tab = "red",          -- active launcher tab: "red"/"blue"/"yellow"/"mods"
    logo = love.graphics.newImage("assets/logo/logo.png"),
    tiltRipsLogo = love.graphics.newImage("assets/logo/tilt-rips.png",{mipmaps=true}),
    bcg = love.graphics.newImage("assets/logo/UD.png"),
    -- Gold/Silver get their own branding: the Gen2 wordmark over the strip and
    -- the UD credit in the footer, swapped in whenever one of those tabs is up.
    gen2Logo = love.graphics.newImage("assets/logo/gen2logo.png"),
    gen2Bcg = love.graphics.newImage("assets/logo/UD.png"),
    ready = {}, returning = {}, romName = {},
    importing = nil,      -- the version currently extracting, or nil
    workState = nil,      -- "working" / "complete" / "error" for that import
    errorVersion = nil,   -- which column shows the current error
    notice = nil,         -- { version, status, detail } transient hint (Android)
    status = "", detail = "", progress = 0,
    stageCurrent = 0, stageTotal = 1, pulse = 0,
    -- SAVE SLOT panel state (pass 2): each keyed by version.  slots is the
    -- cached SaveData.listSlots array (refreshed lazily on first draw and after
    -- any slot mutation); activeSlot drives the LOADED pill; slotScroll is the
    -- per-version list scroll offset (px), clamped against content in draw.
    slots = {}, activeSlot = {}, slotScroll = {},
    -- SAVE FILES card state: the last import/export result per version, shown as
    -- a green/red notice line under the Import save / Export save buttons.  A
    -- successful export carries { dir } so the notice can offer an open-folder
    -- affordance (desktop love.system.openURL).
    saveNotice = {},
    -- MODS panel state (pass 3): mods is the cached LauncherMods.list() array
    -- (refreshed lazily on first draw and after any toggle/install/delete);
    -- modScroll is the list scroll offset (px, clamped in draw); modNotice is
    -- the last install/delete result { ok, text } shown as a line above the list.
    mods = nil, modScroll = 0, modNotice = nil,
    -- FIND MODS panel state (src/mods/ModIndex.lua).  findLoaded gates the
    -- first fetch the way `mods = nil` gates the mods list, but it is a flag
    -- rather than a nil listing because "no index added" is a legitimate
    -- loaded state and must not re-fetch every frame.  findSources is the
    -- player's index list from options; findIndex is the merged listing;
    -- _findThumbs caches one image per mod id (false = fetched and failed).
    findLoaded = false, findSources = nil, findIndex = nil,
    findScroll = 0, findNotice = nil, findQuery = "", findCategory = nil,
    _findSearchFocus = false, _findThumbs = nil,
    -- Page scroll offset (px) for the column under the tab bar -- panel, updater
    -- banner and footer -- used only while that column is taller than the window
    -- (see draw()).  Clamped against content in draw, reset on a tab change.
    pageScroll = 0,
    tabScroll = 0,
    -- Android SAF: which game tab should receive the next picked_save.sav when
    -- focus consumes it (set by chooseSaveImport before opening the picker).
    androidPendingVersion = nil,
    -- the mod whose `required_imports` file the native picker is fetching
    modImportPending = nil,
    -- Android SAF create-document: which game's SAVE FILES card should show
    -- "Save exported." when export_done.flag appears on focus.
    androidPendingExportVersion = nil,
    iosPendingKind = nil,
    iosPendingVersion = nil,
    -- Virtual pointer for handhelds / gamepads (Anbernic stock OS has no
    -- mouse).  D-pad + left stick move it; A clicks; shoulders cycle tabs;
    -- right stick scrolls the save-slot / mods lists.
    _padCursor = { x = 0, y = 0 },
    _padCursorActive = false,
    _padAxis = { leftx = 0, lefty = 0, righty = 0 },
    _padDir = {},
    _rawHatDirs = {},
    _padInited = false,
  }, RomImporter)
  -- Everything the table constructor above did, including the four
  -- love.graphics.newImage calls -- the first GPU work of the whole launch,
  -- and the most likely place for a driver or memory failure that no Lua
  -- handler can catch.
  BootTrace.mark("launcher: state + images")

  -- WHICH FOLDER THE CACHE IS USING, named once per launch, before the
  -- readiness scan below is the first thing to ask for it.
  --
  -- A player who points the game-data folder somewhere and finds files still
  -- landing in AppData has no way to tell whether the setting did not save,
  -- was refused, or was accepted and then could not be mounted -- and the one
  -- log line that would have said so never reached disk, because the logger
  -- buffers 64 lines and a launch produces a handful.  This goes in the boot
  -- trace, which is open-write-close per line, so the answer is on disk before
  -- the question gets asked.
  do
    local ok, report = pcall(function()
      return require("src.import.CacheFs").rootReport()
    end)
    if ok and type(report) == "table" then
      BootTrace.mark(("launcher: game data %s %s%s"):format(
        tostring(report.kind), tostring(report.path or "?"),
        report.why and (" -- " .. tostring(report.why)) or ""))
    end
  end

  for _, version in ipairs(GameVersion.ORDER) do
    local info = GameVersion.info(version)
    local report = RomImporter.readyReport(version)
    local ready = report.ok and not self.forceImport
    self.ready[version] = ready
    -- SAID OUT LOUD, ONCE PER LAUNCH. A re-import costs minutes and used to
    -- announce itself only by happening; a player watching their ROM extract
    -- again on every start had no way to learn which file was behind it, and
    -- neither did anybody they reported it to.
    if not report.ok then
      require("src.core.Logger").info(
        "%s will be imported: %s%s", tostring(version),
        tostring(report.why or "the cache is not current"),
        (report.missing and report.missing[1])
          and (" -- " .. table.concat(report.missing, ", ")) or "")
    elseif report.gaps and report.gaps[1] then
      require("src.core.Logger").info(
        "%s cache accepted with %d known gap(s): %s", tostring(version),
        #report.gaps, table.concat(report.gaps, ", "))
    end
    -- a marker present but for an older cache generation / different ROM means
    -- "update required" (re-import) rather than a clean first-run choose
    local saved = CacheFs.prefix
    CacheFs.prefix = info.cachePrefix
    local marker = CacheFs.read(MARKER_PATH)
    CacheFs.prefix = saved
    -- Compared on the marker's FIRST LINE: the rest is the gap list this
    -- build writes, and a cache carrying one is not a cache from another
    -- version of the app.
    local head = select(1, parseMarker(marker))
    self.returning[version] =
      (not ready) and marker ~= nil and head ~= markerFor(version)
    self.romName[version] = "pokemon_" .. info.id
      .. (info.generation == 4 and ".nds"
          or info.generation == 3 and ".gba"
          or ((info.id == "yellow" or info.generation == 2) and ".gbc" or ".gb"))
  end

  BootTrace.mark("launcher: versions scanned")

  -- Android: import a save-dir .gb/.gbc that is not yet ready (USB drop or a
  -- leftover SAF pick), routed by SHA-1.  Already-imported carts are skipped
  -- so a stale picked_rom.gb cannot block another version.
  local needRom = false
  for _, version in ipairs(GameVersion.ORDER) do
    if not self.ready[version] then needRom = true; break end
  end
  if android and needRom then
    local name, data, romPath = findPendingRom(self.ready, self.failedRoms)
    if name then
      self:startData(data, name, romPath)
    else
      -- The picker runs as its own activity and Android may kill us while it
      -- is up, so a rejected pick can outlive the focus handler (#442).
      consumePickedRomError(self)
    end
  end

  -- Mouse-wheel scroll for the save-slot / mods lists.  main.lua (off limits)
  -- swallows love.wheelmoved while the launcher is up and never forwards it
  -- here, so the interactive launcher chains the global handler once,
  -- non-destructively: our scroll runs first, then the previous handler (which
  -- no-ops while the Importer is live and resumes feeding the game after
  -- handoff).  Only the interactive launcher installs this; the scripted /
  -- import-only paths (launcher = false) leave the handler untouched.
  if self.launcher and love and love.wheelmoved then
    local prevWheel = love.wheelmoved
    love.wheelmoved = function(dx, dy)
      if not self._handedOff then pcall(self.wheelmoved, self, dx, dy) end
      if prevWheel then return prevWheel(dx, dy) end
    end
  end

  -- Self-updater: the interactive launcher on a real fused build kicks off one
  -- async release check as it comes up; draw() polls Check.state() to render an
  -- unobtrusive banner beneath the columns.  Held behind pcall so a broken or
  -- absent updater can never take the launcher down with it.
  if self.launcher and updaterAllowed() then
    local ok, Check = pcall(require, "src.update.Check")
    if ok and Check then
      self.Check = Check
      pcall(Check.start)
    end
  end

  -- The generation the player last filtered the chip row to (see
  -- _selectGeneration).  `false` is ALL and is what a fresh options file says,
  -- so nothing changes for anybody who never opens the dropdown.
  do
    local okOpt, options = pcall(require("src.core.SaveData").loadOptions)
    -- The palette, before anything draws with it.  Applied here rather than at
    -- module load so that the launcher picks up a theme chosen on the previous
    -- run, and re-applied by _applyLauncherTheme the moment either row steps.
    if okOpt then pcall(RomImporter.applyTheme, options) end
    local g = okOpt and type(options) == "table" and options.launcherGeneration
    self.genFilter = RomImporter.isGeneration(g)
    -- ...and a filter that hides the tab the launcher opened on would show an
    -- empty row with a panel behind it.
    if self.genFilter and GameVersion.VERSIONS[self.tab]
        and GameVersion.generation(self.tab) ~= self.genFilter then
      for _, v in ipairs(GameVersion.ORDER) do
        if GameVersion.generation(v) == self.genFilter then
          self.tab = v
          break
        end
      end
    end
  end

  -- On Linux handhelds a gamepad is usually already connected at boot; arm
  -- the virtual cursor immediately so the player does not have to press a
  -- button before seeing something move.
  -- Any connected pad arms the virtual cursor, not just on Linux.  The OS
  -- literal here was written for PortMaster handhelds and left a Switch
  -- player looking at a launcher with no visible pointer until they happened
  -- to nudge a stick.
  if self.launcher
      and love.joystick and love.joystick.getJoystickCount
      and love.joystick.getJoystickCount() > 0 then
    self:_activatePadCursor()
  end

  return self
end

-- The system picker runs as a separate top activity, so LOVE's own
-- love.focus/love.visible pause while it's up (see main.lua) -- once the
-- player returns here with a file picked, GameActivity has already copied
-- it into the save directory, so a pending-file rescan on refocus picks it
-- up without the player needing to tap the button again.  Mod and save SAF
-- drops (picked_mod.zip / picked_save.sav) are consumed first so a leftover
-- ROM pick cannot steal the focus path when both games are already ready.
-- NOTE (iOS): do NOT clear pickPending here.  The picker's dismissal focus
-- event can arrive before the Swift delegate has finished copying the pick
-- into the save dir; if this scan runs early and finds nothing, the poll in
-- _pollPickedFiles must stay armed so it consumes the file when it lands
-- moments later (it clears pickPending itself once something is found).
function RomImporter:focus(f)
  if not (f and self.android and self.workState ~= "working") then return end
  -- SAF create-document finished: GameActivity wrote export_done.flag.
  if love.filesystem.getInfo("export_done.flag", "file") then
    love.filesystem.remove("export_done.flag")
    love.filesystem.remove("pending_export.sav")
    local version = self.androidPendingExportVersion or self:_savedropTarget()
    self.androidPendingExportVersion = nil
    self.saveNotice[version] = { ok = true, text = "Save exported." }
    if self.tab == "mods" then self.tab = version end
    return
  end
  -- Game-data folder pick: GameActivity wrote the absolute path into
  -- picked_folder.txt.  The volume dialog does not steal focus, so this
  -- also has to run from _pollPickedFiles.
  if love.filesystem.getInfo("picked_folder.txt", "file") then
    local path = love.filesystem.read("picked_folder.txt")
    love.filesystem.remove("picked_folder.txt")
    self.pickPending = nil
    path = type(path) == "string" and path:match("^%s*(.-)%s*$") or ""
    if path ~= "" then self:setDataDir(path) end
    return
  end
  -- The SAF pick failed inside GameActivity, which wrote pick_error.flag with
  -- the destination basename in it: some OEM shells (ColorOS) let a third-party
  -- archive manager win the ACTION_OPEN_DOCUMENT chooser and hand back a URI
  -- this app has no permission to read, and until #442 that returned to a
  -- launcher that said nothing at all.
  local pickError = love.filesystem.getInfo("pick_error.flag", "file")
    and love.filesystem.read("pick_error.flag")
  if pickError then
    love.filesystem.remove("pick_error.flag")
    if self._pickMany then
      self:_pickManyTally(false)
      self:_pickManyFinish()
    end
    -- WHAT THE FLAG CARRIES NOW. Line 1 is the destination basename (which is
    -- what the branches below match on, so it has to stay first); the rest is
    -- the native side's account of why nothing could be read -- which app
    -- served the pick, and the exception it threw.
    --
    -- The old advice ended with "or copy it into: <save dir>", and that save
    -- dir is under Android/data. Android 11+ blocks the stock Files app from
    -- browsing in there at all, so on the devices where this message actually
    -- appears the escape hatch it offered could not be taken. What CAN be done
    -- is pick again through the system documents UI, so that is what it says.
    local detail = pickError:match("^[^\n]*\n(.+)$")
    detail = detail and detail:gsub("%s+$", "") or nil
    local text = "Could not read the picked file. Tap Import again and choose "
      .. "it with the Files app (the menu's BROWSE), not a third-party file "
      .. "manager or a cloud app."
    if detail and detail ~= "" then
      text = text .. "  [" .. detail:gsub("\n", " / ") .. "]"
    end
    if pickError:find("picked_folder", 1, true) then
      local text = "Could not use that folder."
      if detail and detail ~= "" then
        text = text .. "  " .. detail:gsub("\n", " ")
      end
      self.settingsNotice = text
      self._settingsRowCache = nil
      self.pickPending = nil
      return
    elseif pickError:find("picked_mod", 1, true) then
      self.modNotice = { ok = false, text = text }
    elseif pickError:find("picked_save", 1, true) then
      local version = self.androidPendingVersion or self:_savedropTarget()
      self.androidPendingVersion = nil
      self.saveNotice[version] = { ok = false, text = text }
    else
      self:setError(text)
    end
    return
  end
  -- a base file picked for a mod (`required_imports`); the native bridge
  -- writes it under one of these basenames
  if self.modImportPending then
    for _, name in ipairs({ "picked_base.bin", "picked_rom.bin", "picked_rom.z64",
                            "picked_rom.n64", "picked_rom.v64" }) do
      if love.filesystem.getInfo(name, "file") then
        local modId = self.modImportPending
        self.modImportPending = nil
        self.pickPending = nil
        self:_installModImport(modId, name)
        love.filesystem.remove(name)
        return
      end
    end
  end
  local modName = findPendingMod(false, self.pickSkip)
  if modName then
    self:_installMod(modName)
    local installed = self.modNotice and self.modNotice.ok
    consumePick(self, modName, "picked_mod.zip", installed)
    -- ...and if this is a run, count it and open the picker again.
    if self:_pickManyActive("mod") then
      self:_pickManyTally(installed)
      self:_pickManyAgain()
    end
    return
  end
  local savName = findPendingSav(false, self.pickSkip)
  if savName then
    local version = self.androidPendingVersion or self:_savedropTarget()
    self.androidPendingVersion = nil
    self:_importSave(version, savName)
    consumePick(self, savName, "picked_save.sav",
      self.saveNotice[version] and self.saveNotice[version].ok)
    return
  end
  for _, v in ipairs(GameVersion.ORDER) do
    if not self.ready[v] then
      local name, data, romPath = findPendingRom(self.ready, self.failedRoms)
      if name then
        self:startData(data, name, romPath)
      elseif consumePickedRomError(self) then
        if self:_pickManyActive("rom") then self:_pickManyTally(false) end
      elseif self:_pickManyActive("rom") then
        -- came back from the picker with nothing: that is Back, and the end
        -- of the run (see _pickManyBegin)
        self:_pickManyFinish()
      end
      return
    end
  end
  -- ...and the same signal for a mod run: every branch above has declined, so
  -- the player returned from the picker without choosing anything.
  if self._pickMany then self:_pickManyFinish() end
end

function RomImporter:setError(message, version)
  require("src.import.CacheFs").prefix = ""
  -- THIS FILE HAS HAD ITS TURN. Without this the Android scan hands the same
  -- failing cartridge back on every attempt and nothing else can be imported;
  -- with it, the next Choose moves on to the next pending file.
  if type(self.importSourceName) == "string" and self.importSourceName ~= "" then
    self.failedRoms = self.failedRoms or {}
    self.failedRoms[self.importSourceName] = true
  end
  self.importSourceName = nil
  self.workState = "error"
  self.errorVersion = version or self.importing or self.chooseVersion or "red"
  self.importing = nil
  self.notice = nil
  self.status = "That ROM could not be imported"
  self.detail = tostring(message)
  self.progress = 0
  self.worker = nil
  self.romData = nil
  -- The other way a run ends -- for a desktop queue and for a mobile
  -- keep-picking run alike.  Deferred rather than called straight from here:
  -- setError is reached from inside the worker coroutine, and starting the next
  -- import on that stack would resume a coroutine from within itself.
  if self._romQueue or self._pickMany then self._romQueueResume = true end
end

-- draw() may leave the system hand cursor set while hovering a Play /
-- Choose control.  Once the importer is torn down that draw path stops
-- running, so restore the arrow before handing off to boot (issue #114).
local function resetPointerCursor(self)
  if self.android then return end
  if not (love.mouse.isCursorSupported and love.mouse.isCursorSupported()) then
    return
  end
  if not self.arrowCursor then
    local ok, cursor = pcall(love.mouse.getSystemCursor, "arrow")
    if not ok then return end
    self.arrowCursor = cursor
  end
  love.mouse.setCursor(self.arrowCursor)
end

-- Verify + extract a ROM. The version is decided by the ROM's own SHA-1, so
-- dropping any supported cart into any column always lands in the
-- right one.
-- `sourcePath` is where the file came from on disk, when the caller knows.
-- Everything up to and including the SHA-1 still works on `data`, because
-- verifying a cartridge means hashing its bytes and there is no way around
-- that.  What the path buys is the stage AFTER verification: a Gen 4
-- extractor must not be handed 128 MiB as a Lua string (see
-- src/import/RomExtractorGen4.lua), and it is the only thing that can open
-- the cartridge itself and read ranges out of it on demand.
function RomImporter:startData(data, displayName, sourcePath, verified)
  if self.workState == "working" then return end
  if not verified and type(data)=='string' then
    if self:_beginRomProbe(data,sourcePath,displayName) then return end
  end
  if type(data) ~= "string" then
    self:setError("The selected file could not be read.")
    return
  end
  if not isSupportedRomSize(verified and verified.size or #data) then
    self:setError(("Expected a 1 MiB (Red/Blue/Yellow), 2 MiB (Gold/Silver), "
      .. "16 MiB (Emerald) or 128 MiB (Platinum) cartridge; this file is "
      .. "%.2f MiB."):format(#data / 1024 / 1024))
    return
  end
  local actualHash = verified and verified.hash or sha1(data)
  local version = GameVersion.forSha1(actualHash)
  if not version then
    self:setError(("Unsupported ROM (SHA-1 %s). This needs a clean US Pokemon "
      .. "Red, Blue, Yellow, Gold, Silver, Crystal, FireRed, Emerald or "
      .. "Platinum dump; patched, "
      .. "trimmed or "
      .. "\"fixed\" dumps "
      .. "(tagged [b] or [BF]) never verify."):format(actualHash))
    return
  end
  local info = GameVersion.info(version)

  -- Bring the launcher to this version's tab so its progress bar is on screen
  -- (a dropped cart is routed by SHA-1 regardless of which tab was showing).
  if GameVersion.VERSIONS[self.tab] then
    self.tab = version
  end
  self.importing = version
  self.workState = "working"
  self.notice = nil
  self.status = "Verifying " .. info.displayName
  self.detail = displayName or info.displayName
  self.progress = 0
  self.romData = data
  self.romPath = sourcePath
  -- KEPT SO A FAILURE CAN BE ATTRIBUTED. `setError` clears everything else, and
  -- without the name there is no way to know which pending file to stop
  -- offering -- see `findPendingRom`'s `skip`.
  self.importSourceName = displayName
  -- BREADCRUMBS THROUGH THE IMPORT, for the same reason boot has them.
  --
  -- An import is the longest, most memory-hungry thing this program does -- a
  -- Gen 3 cartridge unpacks to hundreds of megabytes -- and when it dies it
  -- usually dies BELOW LUA: an allocation failure or an OOM kill reaches no
  -- error handler, writes no crash.txt, and leaves log.txt empty because the
  -- logger had not filled its buffer yet.  From the outside that is
  -- indistinguishable from the app simply vanishing, which is exactly how it
  -- gets reported.
  --
  -- BootTrace.mark is an open-write-close per call, so the file on disk is
  -- current even when the next instruction is the one that kills us: whatever
  -- the last line says is the stage the import did not survive.  Marked on
  -- STAGE CHANGES only -- onProgress fires per map and per tileset, and one
  -- file write each would be its own performance bug -- which is a couple of
  -- dozen lines per import.
  BootTrace.mark(("import %s: begin (%.1f MB rom)")
    :format(tostring(version), (verified and verified.size or #data) / 1048576))
  self.worker = coroutine.create(function()
    self.status = "Preparing private game data"
    coroutine.yield()

    local manifest = decodeManifest(version)
    local blocked = blockedImportReason(version, manifest)
    if blocked then
      self:setError(blocked, version)
      return
    end

    local CacheFs=require('src.import.CacheFs')
    local modules={[1]='src.import.RomExtractor',[2]='src.import.RomExtractorGen2',
      [3]='src.import.RomExtractorGen3',[4]='src.import.RomExtractorGen4'}
    local task=require('src.import.RomImportTask').new({action='extract',version=version,
      generation=info.generation,module=modules[info.generation],manifest=manifest,
      prefix=info.cachePrefix,root=CacheFs.root(),path=self.romPath,bytes=info.generation~=4 and self.romData or nil,clear=true})
    if task then
      self.romData=nil
      local complete=false
      while not complete do
        local message=task:poll()
        while message do
          if message.kind=='error' then error(message.error) end
          if message.kind=='complete' then complete=true end
          if message.kind=='progress' then
            self.status=message.stage;self.progress=message.progress
            self.stageCurrent=message.current;self.stageTotal=message.total
          end
          message=task:poll()
        end
        if not complete then coroutine.yield("background") end
      end
      CacheFs.prefix=info.cachePrefix
    else
    -- Redirect every cache write to this version's subtree, then clear only
    -- that version's previous cache from both homes (save directory and, for
    -- a portable install, the game folder).  The other version is untouched.
    CacheFs = require("src.import.CacheFs")
    local prefix = info.cachePrefix
    CacheFs.prefix = prefix
    removeTree(prefix .. "data/generated")
    removeTree(prefix .. "assets/generated")
    love.filesystem.remove(prefix .. MARKER_PATH)
    CacheFs.removeTree("data/generated")
    CacheFs.removeTree("assets/generated")
    CacheFs.remove(MARKER_PATH)
    BootTrace.mark("import " .. tostring(version) .. ": old cache cleared")

    -- WHICH EXTRACTOR, and spelled out rather than inferred.
    --
    -- This was a two-way ternary: generation 2 took the Gen 2 extractor and
    -- EVERYTHING ELSE took the Gen 1 one.  That is fine while there are two
    -- generations and silently wrong the moment there are three -- a 16 MiB
    -- Game Boy Advance cartridge went to the Gen 1 extractor and died in
    -- extractTilesets on a constants table that was never built.  The failure
    -- was two layers from the cause, which is what an `or` fallback buys you.
    --
    -- So: a table keyed by generation, and a refusal if the generation has no
    -- entry.  Adding a fourth generation should be a line here, not a bug.
    local EXTRACTORS = {
      [1] = { module = "src.import.RomExtractor", takesVersion = false },
      [2] = { module = "src.import.RomExtractorGen2", takesVersion = true },
      [3] = { module = "src.import.RomExtractorGen3", takesVersion = true },
      -- ...and the fourth is a line here, as the comment above promised.
      -- `takesPath` is the one thing that made it more than a line: Gen 4
      -- opens the cartridge itself instead of being handed its bytes.
      [4] = { module = "src.import.RomExtractorGen4", takesVersion = true,
              takesPath = true },
    }
    local choice = EXTRACTORS[info.generation]
    if not choice then
      error(("no extractor for %s (generation %s)")
            :format(tostring(version), tostring(info.generation)))
    end
    local RomExtractor = require(choice.module)
    BootTrace.mark(("import %s: %s"):format(tostring(version), choice.module))
    local markedStage = nil
    local function onProgress(progress, total, stage, current, stageTotal)
      self.status = stage
      self.progress = progress / total
      self.stageCurrent = current
      self.stageTotal = stageTotal
      -- One line per STAGE, carrying how much Lua memory is live when it
      -- starts.  The number is the point: an import that dies below Lua dies
      -- of memory far more often than of anything else, and a trace whose last
      -- two lines are a stage and a figure climbing towards a limit says so
      -- without anybody having to reproduce it under a profiler.
      if stage ~= markedStage then
        markedStage = stage
        BootTrace.mark(("import %s: %s (%.0f MB lua)"):format(
          tostring(version), tostring(stage), collectgarbage("count") / 1024))
      end
      coroutine.yield()
    end
    -- A DROPPED FILE MAY HAVE NO PATH.  love.filedropped gives a File whose
    -- getFilename is a real path on desktop and need not be anywhere else, and
    -- the Android save-directory scan reads through love.filesystem rather
    -- than the disk.  A Gen 4 import that reaches here without one cannot
    -- proceed, and saying so plainly is much better than passing nil into
    -- `new` and failing inside NdsRom with something about a missing path.
    local extractor, extractorError
    if choice.takesPath then
      if type(self.romPath) ~= "string" or self.romPath == "" then
        error(("%s must be imported from a file on disk -- use the Import "
               .. "button rather than dropping it, so the game can read the "
               .. "cartridge without holding all %d MB of it in memory")
              :format(info.displayName or tostring(version),
                      math.floor(#(self.romData or "") / 1048576)))
      end
      extractor, extractorError =
        RomExtractor.new(self.romPath, version, manifest, onProgress)
      if not extractor then
        error(("could not open %s: %s"):format(self.romPath, tostring(extractorError)))
      end
      -- The bytes are finished with: verification is done and the extractor
      -- reads from its own handle.  Dropping them HERE rather than after the
      -- run is the entire point of taking a path -- otherwise the 128 MiB
      -- stays live for the whole extraction and nothing was gained.
      self.romData = nil
      collectgarbage("collect")
    else
      extractor = choice.takesVersion
        and RomExtractor.new(self.romData, version, manifest, onProgress)
        or RomExtractor.new(self.romData, manifest, onProgress)
    end
    extractor:run()
    if extractor.close then extractor:close() end
    self.romData = nil
    collectgarbage("collect")
    BootTrace.mark(("import %s: extracted (%.0f MB lua)")
      :format(tostring(version), collectgarbage("count") / 1024))
    end
    -- Written last: the marker is what isReady() checks, so it must only
    -- appear once the extraction has finished.
    --
    -- AND IT CARRIES WHAT THE EXTRACTION COULD NOT PRODUCE. Measured here,
    -- immediately after the run, which is the only moment anything can
    -- honestly say "this ROM has been through this extractor and these files
    -- did not come out" -- and the only thing that stops the launcher asking
    -- for the same three minutes on every launch for ever. See markerBody.
    local gaps = missingRequiredFiles(version)
    if not gen2TilesetRegistryLooksValid(version) then
      gaps[#gaps + 1] = "<tileset-registry>"
    end
    if #gaps > 0 then
      require("src.core.Logger").warn(
        "%s imported, but %d expected file(s) were not produced: %s. The "
        .. "cache is accepted anyway -- re-importing cannot make them, and "
        .. "asking for it every launch would be the worse bug.",
        tostring(version), #gaps, table.concat(gaps, ", "))
    end
    local ok, writeError = CacheFs.write(MARKER_PATH, markerBody(version, gaps))
    CacheFs.prefix = ""   -- restore the default so later writes stay at the root
    if not ok then error("could not finish the private cache: " .. tostring(writeError)) end
    self.ready[version] = true
    self.returning[version] = false
    self.romName[version] = (displayName
      and (displayName:match("[^/\\]+$") or displayName)) or self.romName[version]
    -- Android: drop the consumed save-dir .gb/.gbc (picked_rom.gb or a USB copy)
    -- so the next Choose / focus cannot treat it as a fresh pending ROM.
    if self.android and type(displayName) == "string"
        and not displayName:find("[/\\]") then
      love.filesystem.remove(displayName)
    end
    self.importing = nil
    self.workState = "complete"
    self.completeVersion = version
    self.status = "Ready"
    self.detail = "Starting " .. info.displayName .. "..."
    self.progress = 1
    if self.launcher then
      -- Stay on the launcher; the player presses Play to boot the new game.
      return
    end
    self._handedOff = true
    resetPointerCursor(self)
    if self.onComplete then self.onComplete(version) end
  end)
end

function RomImporter:_beginRomProbe(bytes,path,name)
  local task=require('src.import.RomImportTask').new({action='verify',bytes=bytes,path=path})
  if not task then return false end
  self.probeTask=task;self.probePath=path;self.probeName=name
  self.workState='working';self.importing=GameVersion.VERSIONS[self.tab] and self.tab or nil
  self.status='Verifying cartridge';self.progress=0;self.detail=name or path or 'ROM'
  return true
end

function RomImporter:_pollRomProbe()
  local task=self.probeTask
  if not task then return end
  local message=task:poll()
  if not message then return end
  if message.kind=='error' then self.probeTask=nil;self:setError(message.error);return end
  if message.kind=='verified' then
    local path,name=self.probePath,self.probeName
    self.probeTask=nil;self.probePath=nil;self.probeName=nil
    self.workState='idle';self.importing=nil
    self:startData(message.bytes,name,path,message)
  end
end

function RomImporter:startPath(path)
  if not path or self.workState=='working' then return end
  if self:_beginRomProbe(nil,path,path:match('[^/\\]+$') or path) then return end
  local data, readError = readExternalPath(path)
  if not data then
    self:setError("Could not read the selected file: " .. tostring(readError))
    return
  end
  -- The whole path is kept, not just the basename: a Gen 4 import reopens the
  -- file after verification rather than carrying its bytes around.
  self:startData(data, path:match("[^/\\]+$") or path, path)
end

-- ---------------------------------------------------------------------------
-- MASS ROM IMPORT
--
-- "add in a button to mass import roms for those available in our game next to
-- the gen select button".
--
-- THE SORTING IS THE FEATURE, and it is the part the player cannot do
-- themselves.  A folder of dumps is a pile of files with whatever names
-- somebody gave them; what decides which game each one becomes is its SHA-1,
-- which is what startData has always routed on.  So this reads each file ONCE
-- up front, hashes it, and answers three questions before importing anything:
-- is it one of ours, do we already have it, and have we already seen this same
-- cartridge earlier in the same pick.
--
-- READ, HASHED, THROWN AWAY.  The queue holds paths, not bytes.  Emerald alone
-- is sixteen megabytes and a pick of nine would be well over sixty held at
-- once for no reason: each one is read again when its turn comes, which costs
-- a second read and keeps the high-water mark at one cartridge.
--
-- ONE AT A TIME, because an extraction is a coroutine pumped by update() and
-- there is exactly one of it.  _advanceRomQueue is the pump: it is called
-- wherever a run ENDS -- the worker going dead, and setError -- records what
-- happened, and starts the next.
-- ---------------------------------------------------------------------------

-- What a pick turns into: the entries worth importing, and one line about
-- everything that was left out.  `paths` may be absolute (a picker) or
-- save-dir relative (the console inbox); `read` remembers which.
function RomImporter:_scanRomSources(paths)
  local queue, rejects = {}, { unknown = {}, present = {}, duplicate = {},
                               unreadable = {} }
  local seen = {}
  for _, path in ipairs(paths or {}) do
    local name = path:match("[^/\\]+$") or path
    local data = readExternalPath(path)
    local fromSaveDir = false
    if not data and love.filesystem then
      data = love.filesystem.read(path)
      fromSaveDir = data ~= nil
    end
    if type(data) ~= "string" then
      rejects.unreadable[#rejects.unreadable + 1] = name
    elseif not isSupportedRomSize(#data) then
      rejects.unknown[#rejects.unknown + 1] = name
    else
      local version = GameVersion.forSha1(sha1(data))
      if not version then
        rejects.unknown[#rejects.unknown + 1] = name
      elseif self.ready[version] and not self.returning[version] then
        -- ALREADY IMPORTED IS NOT A FAILURE.  Pointing at the folder you keep
        -- your dumps in when you already have half of them is the normal case,
        -- and re-extracting a cartridge costs minutes -- the game's own
        -- "Re-import ROM" button is where that decision belongs.
        rejects.present[#rejects.present + 1] = GameVersion.info(version).displayName
      elseif seen[version] then
        rejects.duplicate[#rejects.duplicate + 1] = name
      else
        seen[version] = true
        queue[#queue + 1] = { path = path, name = name, version = version,
                              saveDir = fromSaveDir }
      end
    end
    data = nil
    collectgarbage("step")
  end
  -- import in the row's own order, so the launcher walks left to right through
  -- the chips rather than in whatever order the dialog handed them over
  local rank = {}
  for i, v in ipairs(GameVersion.ORDER) do rank[v] = i end
  table.sort(queue, function(a, b)
    return (rank[a.version] or 99) < (rank[b.version] or 99)
  end)
  return queue, rejects
end

function RomImporter:_beginRomScan(paths)
  local task=require('src.import.RomImportTask').new({action='scan',paths=paths,sizes=ROM_SIZES})
  if not task then return false end
  self.scanTask=task;self.workState='working';self.status='Checking cartridges'
  self.progress=0;self.detail='';self.importing=nil
  return true
end

function RomImporter:_pollRomScan()
  if not self.scanTask then return end
  local message=self.scanTask:poll()
  while message do
    if message.kind=='error' then self.scanTask=nil;self:setError(message.error);return end
    if message.kind=='progress' then
      self.progress=message.current/math.max(1,message.total);self.detail=message.name
    elseif message.kind=='scanned' then
      self.scanTask=nil;self.workState='idle'
      local queue,seen={},{}
      local rejects={unknown={},present={},duplicate={},unreadable={}}
      for _,entry in ipairs(message.results) do
        if entry.unreadable then table.insert(rejects.unreadable,entry.name)
        elseif not entry.version then table.insert(rejects.unknown,entry.name)
        elseif self.ready[entry.version] and not self.returning[entry.version] then
          table.insert(rejects.present,GameVersion.info(entry.version).displayName)
        elseif seen[entry.version] then table.insert(rejects.duplicate,entry.name)
        else seen[entry.version]=true;queue[#queue+1]=entry end
      end
      local rank={};for i,v in ipairs(GameVersion.ORDER) do rank[v]=i end
      table.sort(queue,function(a,b) return (rank[a.version] or 99)<(rank[b.version] or 99) end)
      self._romQueue={pending=queue,done={},failed={},rejects=rejects,total=#queue,index=0}
      self:_advanceRomQueue()
      return
    end
    message=self.scanTask and self.scanTask:poll()
  end
end

local function countLine(label, list)
  if #list == 0 then return nil end
  return ("%d %s (%s)"):format(#list, label, table.concat(list, ", "))
end

function RomImporter:_romBatchSummary(q)
  local parts = {}
  if #q.done > 0 then
    local names = {}
    for _, e in ipairs(q.done) do
      names[#names + 1] = GameVersion.info(e.version).displayName
    end
    parts[#parts + 1] = ("Imported %d: %s"):format(#q.done,
      table.concat(names, ", "))
  end
  local r = q.rejects or {}
  local more = {
    countLine("already imported", r.present or {}),
    countLine("not recognised", r.unknown or {}),
    countLine("duplicate", r.duplicate or {}),
    countLine("unreadable", r.unreadable or {}),
  }
  for _, line in ipairs(more) do
    if line then parts[#parts + 1] = line end
  end
  if #q.failed > 0 then
    local names = {}
    for _, e in ipairs(q.failed) do names[#names + 1] = e.name end
    parts[#parts + 1] = ("%d failed: %s"):format(#q.failed,
      table.concat(names, ", "))
    -- the first reason in full: a list of names with no cause is a support
    -- thread, and one cause usually explains all of them
    parts[#parts + 1] = tostring(q.failed[1].err)
  end
  if #parts == 0 then return false, Strings("Nothing to import.") end
  return #q.done > 0 and #q.failed == 0, table.concat(parts, "  -  ")
end

-- Begin (or continue) a queued run.  Called once when the queue is built and
-- again every time an extraction ends.
function RomImporter:_advanceRomQueue()
  -- Taken here rather than where it is set, so the deferred wake and the
  -- direct call after a refusal cannot both fire for the same ending.
  self._romQueueResume = nil
  local q = self._romQueue
  if not q then return end
  if self.workState == "working" then return end

  -- WHAT HAPPENED TO THE ONE THAT JUST RAN, judged by the only thing that
  -- settles it: whether that version is ready now.  `workState` is not enough
  -- on its own -- setError can fire for a reason that is nothing to do with
  -- this cartridge -- and `ready` is what the rest of the launcher believes.
  local active = q.active
  if active then
    q.active = nil
    if self.ready[active.version] then
      q.done[#q.done + 1] = active
    else
      q.failed[#q.failed + 1] = { name = active.name,
        err = self.detail or Strings("that ROM could not be imported") }
    end
  end

  local nextUp = table.remove(q.pending, 1)
  if not nextUp then
    self._romQueue = nil
    local ok, text = self:_romBatchSummary(q)
    self.romBatch = { ok = ok, text = text, at = love.timer.getTime() }
    return
  end

  q.index = (q.index or 0) + 1
  if require('src.import.RomImportTask').available() then
    q.active=nextUp
    self:startPath(nextUp.path)
    if self.workState~='working' then self._romQueueResume=true end
    return
  end
  local data = nextUp.saveDir and love.filesystem.read(nextUp.path)
    or readExternalPath(nextUp.path)
  if type(data) ~= "string" then
    q.failed[#q.failed + 1] = { name = nextUp.name,
      err = Strings("could not be read a second time") }
    -- straight on to the next rather than stopping: a batch that gives up on
    -- one unreadable file is a batch that has to be started again
    return self:_advanceRomQueue()
  end
  q.active = nextUp
  -- `workState` is "error" or "complete" from the previous run; startData only
  -- refuses while one is actually working, so nothing has to be cleared.
  self:startData(data, nextUp.name)
  -- ...unless startData refused it outright (a file that changed underneath
  -- the scan), in which case there is no worker to end and nothing would ever
  -- call this again.
  if self.workState ~= "working" then
    return self:_advanceRomQueue()
  end
end

-- WHAT HAPPENS AFTER ONE CARTRIDGE FINISHES, on a phone.
--
-- A desktop batch is a queue of paths the dialog already handed over, so
-- _advanceRomQueue owns it.  A mobile one cannot be: the bridge gives one file
-- per trip, so the next trip can only be asked for once this extraction has
-- ended -- and an extraction is the one thing here that takes minutes.
--
-- Both endings reach this: the worker going dead, and setError's deferred
-- wake.  `workState` says which, and a cartridge that failed is counted as
-- failed rather than stopping the run -- the player picked six and one of them
-- being a bad dump is not a reason to make them start again.
function RomImporter:_romPickContinue()
  if self._romQueue then return end        -- a desktop queue still has work
  if self.workState == "working" then return end
  if self._romPickAfterQueue then
    self._romPickAfterQueue = nil
    self:_pickManyBegin("rom")
    return
  end
  if not self:_pickManyActive("rom") then return end
  self:_pickManyTally(self.workState == "complete")
  self:_pickManyAgain()
end

-- The button.  One press: pick, sort, queue.
function RomImporter:chooseRomBatch()
  if self.workState == "working" then return end
  self.romBatch = nil
  local paths
  if self.android or self.ios then
    -- THE INBOX FIRST, THEN THE PICKER -- and the picker is the part this used
    -- to skip entirely.  Reported from play: "Import ROMs on Android says no
    -- ROMs waiting and doesn't popup with a file picker."  It refused instead
    -- of asking, which on a phone is the only way in: a USB copy is a desktop
    -- move and the save directory lives under Android/data, where the stock
    -- Files app cannot browse at all.
    paths = pendingRomPaths()
    if #paths == 0 then
      self:_pickManyBegin("rom")
      return
    end
    -- ...and once the waiting ones are in, keep asking for more.
    self._romPickAfterQueue = true
  else
    paths = chooseRoms()
    if not paths then
      self:ensureImportsDir()
      local waiting = pendingRomPaths()
      -- A CANCELLED DIALOG IS A NO.  On a machine with a picker, falling
      -- through to the inbox would start importing cartridges the player had
      -- just backed out of choosing -- and an extraction is minutes, not
      -- something to start by accident.  Where there is no dialog at all
      -- (a console, a handheld with neither zenity nor kdialog) the inbox is
      -- the only way in and this button is how it is reached.
      if hasNativePicker() then
        self.romBatch = { ok = false, at = love.timer.getTime(), text =
          #waiting > 0
            and Strings("No ROMs chosen. %d are waiting in %s/imports/ if you meant those.",
                  #waiting, love.filesystem.getSaveDirectory())
            or Strings("No ROMs chosen.") }
        return
      end
      paths = waiting
      if #paths == 0 then
        self.romBatch = { ok = false, at = love.timer.getTime(), text =
          Strings("No file picker here. Copy your ROMs into %s/imports/ and press this again.",
            love.filesystem.getSaveDirectory()) }
        return
      end
    end
  end

  if self:_beginRomScan(paths) then return end
  local queue, rejects = self:_scanRomSources(paths)
  self._romQueue = { pending = queue, done = {}, failed = {},
                     rejects = rejects, total = #queue, index = 0 }
  if #queue == 0 then
    local q = self._romQueue
    self._romQueue = nil
    local ok, text = self:_romBatchSummary(q)
    self.romBatch = { ok = ok, text = text, at = love.timer.getTime() }
    return
  end
  self:_advanceRomQueue()
end

-- The line under the tab bar while a batch is running or has just finished.
-- Returns text, ok -- or nil when there is nothing to say, which is what
-- reserves no band in the layout.
function RomImporter:_romBatchLine()
  local q = self._romQueue
  if q then
    local active = q.active
    local name = active and GameVersion.info(active.version).displayName
      or Strings("cartridge")
    return Strings("Importing %d of %d  -  %s", q.index or 1, q.total or 1,
                   name), true
  end
  local b = self.romBatch
  if not b then return nil end
  -- It clears itself: a summary that stays for ever becomes furniture, and
  -- this one is about something that just happened.  Generous, because an
  -- import the player walked away from is exactly when they want to come back
  -- and read it.
  if love.timer.getTime() - (b.at or 0) > 90 then
    self.romBatch = nil
    return nil
  end
  return b.text, b.ok
end

function RomImporter:filedropped(file)
  if self.workState == "working" then return end
  -- A dropped .zip is a mod archive: hand it straight to the mods installer
  -- (which mounts + validates it).  Everything else is treated as a ROM.  The
  -- dropped file itself is passed through -- installZip opens it the same way
  -- readDroppedFile does here.
  local name = file:getFilename() or ""
  if name:lower():match("%.zip$") then
    -- QUEUED, not installed here: a multi-file drop arrives as one call per
    -- file and wants to be one import with one notice (_flushDroppedMods).
    self:_queueDroppedMod(file)
    return
  end
  -- A dropped .sav is a battery save: import it to a new slot for the active
  -- game tab (see _savedropTarget for the tab-selection rule).  It never steals
  -- .gb/.zip routing above.
  if name:lower():match("%.sav$") then
    self:_importSave(self:_savedropTarget(), file)
    return
  end
  -- Desktop drops expose the physical path. Let the worker read it rather
  -- than allocating a large DS ROM on the UI thread first.
  if name:match("^%a:[/\\]") or name:sub(1,1)=="/" then
    self:startPath(name)
    return
  end
  local data, readError = readDroppedFile(file)
  if not data then
    self:setError("Could not read the dropped file: " .. tostring(readError))
    return
  end
  self:startData(data, file:getFilename())
end

-- Install a mod .zip from a picker path or a dropped file, then surface the
-- result on the mods panel (switching to it so the notice is visible).  The
-- source is whatever LauncherMods.installZip accepts: an absolute path string
-- or a love DroppedFile.
-- opts.replace: reinstall over a same-id mod instead of refusing.  The inbox
-- path sets it, because an inbox zip is not consumed -- it stays in
-- imports/mods/ for MTP recovery, so the NEXT press finds the same file and
-- the plain install refuses it as "a mod named 'x' is already installed".
-- On a console that is the only way to install anything, so pressing Import
-- twice reported an error for a mod that was sitting there working.
function RomImporter:_installMod(source, opts)
  if self.workState == "working" then return end
  self.tab = "mods"
  local ok, installed, res = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    return LauncherMods.installZip(source, opts)
  end)
  if not ok then
    self.modNotice = { ok = false,
      text = "Import failed: " .. tostring(installed) }
    return
  end
  if installed then
    pcall(self._refreshMods, self)
    self.modNotice = { ok = true, text = "Installed " .. tostring(res) }
  else
    self.modNotice = { ok = false, text = tostring(res) }
  end
end

-- ---------------------------------------------------------------------------
-- MASS IMPORT ON A PHONE, where there is no multi-select to ask for.
--
-- Reported from play: "Import ROMs on Android says no ROMs waiting and doesn't
-- popup with a file picker, and on Android the import many button pulls up the
-- file picker but won't let me select many files."  Both are the same wall:
-- the desktop pickers are shell dialogs this file drives and can ask for a
-- multiple selection, and the mobile one is a NATIVE BRIDGE
-- (love.system.pickFile) that starts a system document activity and copies
-- exactly ONE file back under a fixed basename.  There is no argument for
-- "several", and adding one means changing the native side, not this file.
--
-- So a run is a LOOP rather than a list: pick, install, and open the picker
-- again -- and the player ends it by pressing Back instead of picking.  That
-- costs one tap per file instead of one round trip through the launcher per
-- file, which is the part that made adding six mods unreasonable.
--
-- HOW A RUN ENDS, and it has to be something the OS actually tells us.  The
-- picker is a separate activity, so returning from it raises love.focus(true)
-- -- and RomImporter:focus already runs every branch that could consume a
-- pick.  Falling through all of them means the player came back with nothing,
-- which is a cancel.  That is the only end signal here; a timer would have to
-- guess how long somebody takes to find a file.
--
-- IOS DOES NOT LOOP.  Its bridge answers through love.system.getPickedFile in
-- update() rather than a focus event, so there is no "came back empty" moment
-- to read -- an armed run would simply sit armed for ever.  One pick there,
-- the same as before, and the notice says so.
-- ---------------------------------------------------------------------------

function RomImporter:_pickManyActive(kind)
  local run = self._pickMany
  return run ~= nil and (kind == nil or run.kind == kind) and run or nil
end

-- Open the picker for the kind this run is collecting.  Answers false when the
-- bridge refuses (no picker on this build), which ends the run.
function RomImporter:_pickManyArm()
  local run = self._pickMany
  if not run then return false end
  if run.kind == "rom" then
    if self.ios then
      self.iosPendingKind = "rom"
      if not pickFile("rom") then return false end
    elseif not pickFile() then
      return false
    end
  else
    if self.ios then
      self.iosPendingKind = "mod"
      if not pickFile("mod") then return false end
    elseif not pickFile("mod") then
      return false
    end
  end
  self.pickPending = true
  self.pickTimer = 0
  -- the cancel watchdog in _pollPickedFiles counts focused polls; a fresh arm
  -- starts it over or the previous trip's count would end this one early
  self._pickIdle = nil
  return true
end

function RomImporter:_pickManyBegin(kind)
  self._pickMany = { kind = kind, taken = 0, failed = 0 }
  if not self:_pickManyArm() then
    self._pickMany = nil
    return false
  end
  -- Say what Back does BEFORE they are looking at a system file browser: the
  -- loop is only obvious once it has looped, and by then they have already
  -- wondered why the picker came back.
  local hint = self.ios
    and Strings("Choose a file to import.")
    or Strings("Choose one, then keep choosing -- press Back when you are done.")
  if kind == "rom" then
    self.romBatch = { ok = true, at = love.timer.getTime(), text = hint }
  else
    self.modNotice = { ok = true, text = hint }
  end
  return true
end

function RomImporter:_pickManyTally(ok)
  local run = self._pickMany
  if not run then return end
  if ok then run.taken = run.taken + 1 else run.failed = run.failed + 1 end
end

-- One more, unless this is iOS (see the note above) or the bridge has stopped
-- answering.
function RomImporter:_pickManyAgain()
  local run = self._pickMany
  if not run then return end
  if self.ios or not self:_pickManyArm() then
    self:_pickManyFinish()
  end
end

function RomImporter:_pickManyFinish()
  local run = self._pickMany
  if not run then return end
  self._pickMany = nil
  self.pickPending = nil
  local text
  if run.taken == 0 and run.failed == 0 then
    text = run.kind == "rom" and Strings("No ROMs imported.")
      or Strings("No mods installed.")
  elseif run.failed > 0 then
    text = run.kind == "rom"
      and Strings("Imported %d, %d failed.", run.taken, run.failed)
      or Strings("Installed %d, %d failed.", run.taken, run.failed)
  else
    text = run.kind == "rom" and Strings("Imported %d.", run.taken)
      or Strings("Installed %d.", run.taken)
  end
  local ok = run.taken > 0 and run.failed == 0
  if run.kind == "rom" then
    self.romBatch = { ok = ok, at = love.timer.getTime(), text = text }
  else
    self.modNotice = { ok = ok, text = text }
  end
end

-- MASS IMPORT: a list of sources through one install pass and one notice.
--
-- `sources` is whatever LauncherMods.installZip takes -- absolute paths from
-- the multi-select picker or the folder scan, love DroppedFiles from a
-- multi-file drop -- so nothing here has a second idea of what a mod archive
-- is.  LauncherMods.installMany does the work and summarize writes the line.
function RomImporter:_installMods(sources, opts)
  if self.workState == "working" then return end
  self.tab = "mods"
  if not (sources and #sources > 0) then
    self.modNotice = { ok = false, text = Strings("Nothing to import.") }
    return
  end
  local LauncherMods = require("src.mods.LauncherMods")
  local ok, res = pcall(LauncherMods.installMany, sources, opts)
  if not ok then
    self.modNotice = { ok = false, text = "Import failed: " .. tostring(res) }
    return
  end
  pcall(self._refreshMods, self)
  local good, text = LauncherMods.summarize(res)
  self.modNotice = { ok = good, text = text }
end

-- "Import many" -- the multi-select picker, with the console/handheld inbox as
-- the fallback the single import already has.  On a machine with no picker,
-- pressing this takes EVERY .zip sitting in imports/mods/, which is the one
-- thing a player on that machine most wants and could not do.
function RomImporter:chooseMods()
  if self.workState == "working" then return end
  -- MOBILE KEEPS PICKING.  The bridge takes a kind, not a count, so a run
  -- there is a loop the player ends with Back -- see _pickManyBegin.  What is
  -- already waiting in the inbox comes first, because a USB or MTP copy is a
  -- whole batch that costs no taps at all.
  if self.android or self.ios then
    local waiting = self:_inboxMods()
    if #waiting > 0 then
      -- Reinstall rather than refuse: an inbox zip is not consumed (it stays
      -- for MTP recovery), so a second press finds the same files and a plain
      -- install would call every one of them "already installed".
      self:_installMods(waiting, { replace = true })
    end
    if not self:_pickManyBegin("mod") then
      if #waiting == 0 then
        self.modNotice = { ok = false, text =
          Strings("Could not open the file picker. Copy your mod .zip files "
                  .. "into imports/mods/ instead.") }
      end
    end
    return
  end
  local picks = chooseZips()
  if picks then
    -- A single pick through the multi picker is still a single install; going
    -- through installMany keeps one code path and one notice shape.
    self:_installMods(picks)
    return
  end
  -- NOTHING PICKED MEANS NOTHING, on a machine that has a dialog to pick with.
  -- Falling through to the inbox there would install a folder of mods somebody
  -- had just cancelled out of choosing.
  self:ensureModsInboxDir()
  local inbox = self:_inboxMods()
  if hasNativePicker() then
    self.modNotice = { ok = false, text = #inbox > 0
      and Strings("No mod .zip files chosen. %d are waiting in %s/imports/mods/ if you meant those.",
            #inbox, love.filesystem.getSaveDirectory())
      or Strings("No mod .zip files chosen.") }
    return
  end
  if #inbox > 0 then
    -- Reinstall rather than refuse: an inbox zip is not consumed (it stays in
    -- imports/mods/ for MTP recovery), so a second press finds the same files
    -- and a plain install would call every one of them "already installed".
    self:_installMods(inbox, { replace = true })
    return
  end
  self.modNotice = { ok = false, text =
    Strings("No file picker here. Copy your mod .zip files into:\n%s/imports/mods/\nthen press Import many again.",
      love.filesystem.getSaveDirectory()) }
end

-- Every .zip waiting in the save-dir inbox, in the save-dir-relative spelling
-- findPendingMod already hands the single import (readArchive falls back to
-- love.filesystem for exactly these).  Both inboxes, because the root scan is
-- what every platform relied on before imports/mods/ existed.
function RomImporter:_inboxMods()
  if not (love.filesystem and love.filesystem.getDirectoryItems) then
    return {}
  end
  pcall(self.ensureModsInboxDir, self)
  local out, seen = {}, {}
  for _, dir in ipairs({ MODS_INBOX_DIR, "" }) do
    local ok, paths = pcall(listZipPaths, dir)
    for _, path in ipairs((ok and paths) or {}) do
      -- a Mac MTP copy leaves "._name.zip" resource forks beside the real
      -- file; installZip's magic-byte check would reject them one by one and
      -- fill the summary with failures that are not the player's problem
      local base = path:match("[^/]+$") or path
      if base:sub(1, 2) ~= "._" and not seen[path] then
        seen[path] = true
        out[#out + 1] = path
      end
    end
  end
  table.sort(out)
  return out
end

-- "Import folder" -- point at where the releases live and take the lot.
function RomImporter:chooseModFolder()
  if self.workState == "working" then return end
  if self.android or self.ios then
    -- no folder picker on either bridge; the inbox IS the folder there
    local inbox = self:_inboxMods()
    if #inbox > 0 then
      self:_installMods(inbox, { replace = true })
    else
      self.modNotice = { ok = false, text =
        Strings("Copy your mod .zip files into imports/mods/ first.") }
    end
    return
  end
  local folder = chooseFolder()
  if not folder or folder == "" then
    self.modNotice = { ok = false, text = Strings("No folder chosen.") }
    return
  end
  local LauncherMods = require("src.mods.LauncherMods")
  local zips, err = LauncherMods.zipsInFolder(folder)
  if not zips then
    self.tab = "mods"
    self.modNotice = { ok = false, text = tostring(err) }
    return
  end
  self:_installMods(zips)
end

-- A MULTI-FILE DROP IS ONE IMPORT, not N.
--
-- LOVE delivers one love.filedropped per file, so dropping a folder's worth of
-- mods used to run a full install per file and leave the panel showing
-- whichever one happened to land last -- including, quite often, a failure
-- from the middle of a run that otherwise worked.  Dropped archives are
-- queued here and flushed on the next update, which is the first moment the
-- whole drop is known to have arrived.
function RomImporter:_queueDroppedMod(file)
  self._modDropQueue = self._modDropQueue or {}
  self._modDropQueue[#self._modDropQueue + 1] = file
end

function RomImporter:_flushDroppedMods()
  local queue = self._modDropQueue
  if not (queue and #queue > 0) then return end
  self._modDropQueue = nil
  if #queue == 1 then
    self:_installMod(queue[1])
  else
    self:_installMods(queue)
  end
end

-- Remove an installed mod from the save-dir mods/ tree and refresh the panel.
function RomImporter:_deleteMod(id)
  if self.workState == "working" then return end
  local ok, deleted, res = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    return LauncherMods.uninstall(id)
  end)
  if not ok then
    self.modNotice = { ok = false,
      text = "Delete failed: " .. tostring(deleted) }
    return
  end
  if deleted then
    pcall(self._refreshMods, self)
    self.modNotice = { ok = true, text = "Deleted " .. tostring(id) }
  else
    self.modNotice = { ok = false, text = tostring(res) }
  end
end

-- "Import mod .zip" button: open a native picker and install the pick.
-- Android mirrors ROM import: scan for a pending .zip in the save dir (USB
-- or a fresh SAF drop), else love.system.pickFile("mod") -> picked_mod.zip
-- which focus/Choose consumes on return.
function RomImporter:chooseMod()
  if self.workState == "working" then return end
  if self.ios and love.system.getPickedFile then
    self.iosPendingKind = "mod"
    if not pickFile("mod") then
      self.iosPendingKind = nil
      self.modNotice = { ok = false, text = "Could not open the file picker." }
    end
    return
  end
  if self.android then
    local name = findPendingMod(true, self.pickSkip)
    if name then
      self:_installMod(name)
      consumePick(self, name, "picked_mod.zip",
        self.modNotice and self.modNotice.ok)
      return
    end
    if not pickFile("mod") then
      self.modNotice = { ok = false,
        text = "Could not open the file picker. Copy a mod .zip via USB." }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local path = chooseZip()
  if path then self:_installMod(path) return end

  -- No picker (console, or a Linux handheld with neither zenity nor kdialog):
  -- scan the inbox the same way the ROM path does.  Before this, chooseMod
  -- reached here, got nil from chooseZip and returned in silence -- pressing
  -- Import on the MODS tab did nothing at all and said nothing about why.
  local found = findPendingMod(true, self.pickSkip)
  if found then
    -- Reinstall rather than refuse: see _installMod's note on the inbox.
    self:_installMod(found, { replace = true })
    return
  end
  if self.isNX or Platform.romImportMode() == "save-directory"
      or love.system.getOS() == "Linux" then
    self:ensureModsInboxDir()
    local saveDir = love.filesystem.getSaveDirectory()
    local rel = RomImporter.mtpHintPath(saveDir)
    if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
    self.modNotice = { ok = true, text =
      "Copy your mod .zip into:\n" .. saveDir .. "/imports/mods/\n"
      .. "DBI MTP -> 1: SD Card/" .. rel .. "imports/mods/" }
    return
  end
  self.modNotice = { ok = false,
    text = "No file picker here. Copy a mod .zip into:\n"
      .. love.filesystem.getSaveDirectory() }
end

-- ---------------------------------------------------------------------------
-- "Import <base file>" on a mod card.
--
-- A mod may declare `required_imports` -- a file it needs but cannot ship.
-- STADIUM2_IMPORTER declares a Pokemon Stadium 2 cartridge, and until this
-- existed the ONLY way to give it one was to unzip the release, drop a 64 MB
-- ROM inside it, re-zip and reinstall; the mod's own discovery says as much
-- ("the engine sandbox has no scoped external ROM picker").  That is the
-- "players can't import the Stadium 2 ROM" report.
--
-- The file is written into the mod's own folder at the path the manifest
-- names, which is where the mod already looks, so no mod needs changing.
-- ---------------------------------------------------------------------------
function RomImporter:_modImportEntry(modId)
  for _, m in ipairs(self.mods or {}) do
    if m.id == modId then
      local needs = m.missingImports and m.missingImports[1]
      return needs and needs.entry or nil, m
    end
  end
  return nil
end

-- STREAMED, NOT SLURPED.  Reported from play: importing a ROM from the
-- launcher crashed it.  This read the whole file into one Lua string and
-- handed that to ModImports.install, which then held it while the hash walked
-- it, while it was written out, and while the shared bank wrote a second copy
-- -- a couple of hundred megabytes live for a 64 MB cartridge, which a desktop
-- absorbs and an Android heap does not.  ModImports.installFrom copies a
-- megabyte at a time and never has the file in hand; `source` is a path
-- either way (absolute off a picker, save-dir relative off the inbox) and it
-- works out which.
--
-- `bytes` is still accepted, because a caller that genuinely has the bytes
-- (the shared store) should not be made to write them to disk first.
function RomImporter:_installModImport(modId, source, bytes)
  local ModImports = require("src.mods.ModImports")
  local entry, row = self:_modImportEntry(modId)
  if not (entry and row) then return end
  local manifest = { path = row.manifestPath or ("mods/" .. modId) }
  local ok, why, notes
  if bytes then
    ok, why = ModImports.install(manifest, entry, bytes)
  elseif source then
    ok, why, notes = ModImports.installFrom(manifest, entry, source)
  else
    self.modNotice = { ok = false, text = "Could not read that file." }
    return
  end
  if ok then
    local text = "Imported " .. tostring(entry.name)
                 .. " for " .. tostring(row.name)
    -- ...and if the file was too big to checksum on this device, SAY so
    -- rather than implying it was verified.
    if notes then text = text .. "\n" .. tostring(notes) end
    self.modNotice = { ok = true, text = text }
    self:_refreshMods()
  else
    self.modNotice = { ok = false, text = tostring(why) }
  end
end

function RomImporter:chooseModImport(modId)
  if self.workState == "working" then return end
  local ModImports = require("src.mods.ModImports")
  local entry = self:_modImportEntry(modId)
  if not entry then return end
  local exts = ModImports.extensions(entry)

  -- Already banked?  A cartridge the player gave another mod satisfies this
  -- one with no picker at all (ModImports' shared store).
  do
    local bytes = ModImports.shared(entry)
    if bytes then return self:_installModImport(modId, nil, bytes) end
  end

  -- then the inbox, on every platform: a file already waiting is the answer
  -- whether or not a picker exists
  self:ensureSavesInboxDir()
  for _, dir in ipairs({ "imports/base", "imports", "imports/mods", "" }) do
    for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
      local path = (dir == "" ) and name or (dir .. "/" .. name)
      if ModImports.accepts(entry, name)
         and love.filesystem.getInfo(path, "file") then
        return self:_installModImport(modId, path)
      end
    end
  end

  -- ANDROID AND iOS: the same native document picker the ROM, save and mod
  -- buttons use (love.system.pickFile -> GameActivity / GRPickerBridge).  It
  -- drops the pick into the save directory under a fixed basename and returns
  -- immediately; _pollPickedFiles picks it up on a later frame, which is why
  -- the pending id is recorded rather than the path being awaited here.
  if self.android or self.ios then
    self.modImportPending = modId
    if pickFile("base") or pickFile("rom") then
      self.pickPending = true
      self.pickTimer = 0
      self.modNotice = { ok = true,
        text = "Choose your " .. tostring(entry.name) .. " in the file picker." }
      return
    end
    self.modImportPending = nil
    self.modNotice = { ok = false,
      text = "Could not open the file picker. Copy the file into:\n"
        .. love.filesystem.getSaveDirectory() .. "/imports/" }
    return
  end

  do
    local path = chooseFileByExt(exts, entry.name)
    if path then return self:_installModImport(modId, path) end
  end

  local saveDir = love.filesystem.getSaveDirectory()
  local rel = RomImporter.mtpHintPath(saveDir)
  if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
  local want = table.concat(exts, "/")
  self.modNotice = { ok = true, text =
    ("Copy your %s (.%s) into:"):format(tostring(entry.name), want)
    .. "\n" .. saveDir .. "/imports/\n"
    .. "DBI MTP -> 1: SD Card/" .. rel .. "imports/" }
end

-- Which game a dropped .sav imports into: a .sav has no version signature of
-- its own, so it lands on the active game tab.  When a non-game tab (mods) is
-- showing, default to red -- the always-present first game -- rather than
-- guess.
function RomImporter:_savedropTarget()
  local v = self.tab
  if GameVersion.VERSIONS[v] then return v end
  return "red"
end

-- Import a raw .sav into a fresh slot for a version, from a picker path or a
-- dropped file, and surface the outcome on that game's SAVE FILES card.  Brings
-- the target tab forward so the notice (and, on success, the new active slot)
-- is visible.  Requires the ROM to be imported first, since a save is only
-- playable with its game's data present.
function RomImporter:_importSave(version, source)
  if self.workState == "working" then return end
  if GameVersion.VERSIONS[self.tab] or self.tab == "mods" then
    self.tab = version
  end
  if not self.ready[version] then
    self.saveNotice[version] = { ok = false, text = "Import the "
      .. GameVersion.info(version).displayName .. " ROM before importing a save." }
    return
  end
  local ok, res = require("src.import.SaveFileIO").importToSlot(source, version)
  if ok then
    self:_refreshSlots(version)
    self.activeSlot[version] = res
    self.slotScroll[version] = math.huge   -- pin the new row on screen (clamped in draw)
    self.saveNotice[version] = { ok = true, text = "Imported save into " .. tostring(res) .. "." }
  else
    self.saveNotice[version] = { ok = false, text = tostring(res) }
  end
end

-- "Import save" button: open a native .sav picker and import the pick.
-- Android mirrors ROM / mod import via love.system.pickFile("sav").
function RomImporter:chooseSaveImport(version)
  if self.workState == "working" then return end
  if self.ios and love.system.getPickedFile then
    self.iosPendingKind = "sav"
    self.iosPendingVersion = version
    if not pickFile("sav") then
      self.iosPendingKind = nil
      self.iosPendingVersion = nil
      self.saveNotice[version] = { ok = false, text = "Could not open the file picker." }
    end
    return
  end
  if self.android then
    local name = findPendingSav(true, self.pickSkip)
    if name then
      self.androidPendingVersion = version
      self:_importSave(version, name)
      consumePick(self, name, "picked_save.sav",
        self.saveNotice[version] and self.saveNotice[version].ok)
      return
    end
    self.androidPendingVersion = version
    if not pickFile("sav") then
      self.androidPendingVersion = nil
      self.saveNotice[version] = { ok = false,
        text = "Could not open the file picker. Copy a .sav via USB." }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local path = chooseSav()
  if path then self:_importSave(version, path) return end

  -- No picker (a console, or a Linux handheld with neither zenity nor
  -- kdialog): scan the inbox the way the ROM and mod buttons already do.
  -- Before this, IMPORT SAVE reached chooseSav, got nil and returned in
  -- SILENCE -- on the Switch the button did nothing and said nothing, which
  -- is the whole reason a correctly-copied .sav looked like a broken build.
  local found = findPendingSav(true, self.pickSkip)
  if found then
    self:_importSave(version, found)
    consumePick(self, found, "picked_save.sav",
                self.saveNotice[version] and self.saveNotice[version].ok)
    return
  end
  -- Every platform with no picker gets the inbox, not just the Switch:
  -- Platform.detect().console covers Xbox (UWP), whose romImportMode is still
  -- "desktop" because it has no native picker to name.
  if self.isNX or Platform.detect().console
      or Platform.romImportMode() == "save-directory"
      or love.system.getOS() == "Linux" then
    self:ensureSavesInboxDir()
    local saveDir = love.filesystem.getSaveDirectory()
    local rel = RomImporter.mtpHintPath(saveDir)
    if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
    self.saveNotice[version] = { ok = true, text =
      "Copy your .sav into:\n" .. saveDir .. "/imports/saves/\n"
      .. "DBI MTP -> 1: SD Card/" .. rel .. "imports/saves/" }
    return
  end
  self.saveNotice[version] = { ok = false,
    text = "No file picker here. Copy a .sav into:\n"
      .. love.filesystem.getSaveDirectory() }
end

-- "Export save" button: write the active slot back out to a raw .sav in the save
-- directory's exports/ folder.  On desktop, show the path with an open-folder
-- affordance.  On Android, stage pending_export.sav and open the system
-- create-document picker (love.system.createFile) so the player can save to
-- Downloads / Drive / etc. -- the app-private exports/ path is not useful there.
-- WHOSE PROJECT A TAB IS, which is what the wordmark and the footer credit
-- actually say -- not which generation the cartridge is.
--
-- The Gen1 wordmark and the Boi's Club footer belong to the columns this
-- launcher inherited; everything this project built itself wears the
-- Gen2Recomp logo and the UD credit.  That was first written as "Gold and
-- Silver", which left CRYSTAL out; widening it to `generation == 2` fixed
-- Crystal and Prism -- and then left EMERALD wearing the Gen1 wordmark, for
-- exactly the same reason, one version further along.
--
-- So the rule is "anything past Gen 1", which is the widening
-- GameVersion.isGen3's own comment describes: a site that asks `== 2` takes
-- the Gen 1 branch for a Gen 3 game, and this was one of them.  Non-version
-- tabs like "mods" have no entry and answer generation 1, so they keep the
-- Gen1 art, and the next version added is right by default.
--
-- A NAMED RULE RATHER THAN A LINE INSIDE `draw`, because it decides three
-- things that have to agree -- the wordmark, the footer badge and whether
-- that badge is inverted (only the Boi's Club mark is dark ink; the UD badge
-- is already bright art) -- and because a rule that has now been widened
-- twice is one a test should be able to ask directly.
function RomImporter.wearsOurMark(tab)
  return GameVersion.generation(tab) >= 2
end

function RomImporter:exportSave(version)
  if self.workState == "working" then return end
  local ok, res = require("src.import.SaveFileIO").exportActiveSlot(version)
  if not ok then
    self.saveNotice[version] = { ok = false, text = tostring(res) }
    return
  end
  if self.android then
    local rel = res:match("exports[/\\][^/\\]+$")
    local data = rel and love.filesystem.read(rel)
    if not data then
      self.saveNotice[version] = { ok = false,
        text = "Exported, but could not stage the file for the picker." }
      return
    end
    local suggested = rel:match("[^/\\]+$") or "export.sav"
    local wrote, writeErr = love.filesystem.write("pending_export.sav", data)
    if not wrote then
      self.saveNotice[version] = { ok = false,
        text = "Could not stage the export: " .. tostring(writeErr) }
      return
    end
    self.androidPendingExportVersion = version
    if love.system.createFile and love.system.createFile(suggested, love.filesystem.getSaveDirectory()) then
      self.pickPending = true
      self.pickTimer = 0
      self.saveNotice[version] = { ok = true,
        text = "Pick where to save " .. suggested .. "..." }
    else
      self.androidPendingExportVersion = nil
      self.saveNotice[version] = { ok = true,
        text = "Exported inside the app folder (picker unavailable)." }
    end
    return
  end
  local dir = res:match("^(.*)[/\\][^/\\]+$")
  self.saveNotice[version] = { ok = true, text = "Exported to " .. res, dir = dir }
end

-- Delete a save slot from the registry and disk, then refresh the panel.  If the
-- deleted slot was active, SaveData.deleteSlot points active at another slot.
function RomImporter:_deleteSlot(version, id)
  if self.workState == "working" then return end
  local SaveData = require("src.core.SaveData")
  local ok, err = SaveData.deleteSlot(version, id)
  if ok then
    self:_refreshSlots(version)
    self.saveNotice[version] = { ok = true, text = "Deleted " .. tostring(id) .. "." }
  else
    self.saveNotice[version] = { ok = false, text = tostring(err) }
  end
end

-- Open a picker (or, on Android, scan the external folder) for a column.  The
-- version argument only titles the dialog and steers error/notice text; the
-- picked ROM is still routed by its SHA-1, so choosing a Blue cart in the Red
-- column imports Blue.
function RomImporter:choose(version)
  if self.workState == "working" then return end
  self.chooseVersion = version or "red"
  if self.ios and love.system.getPickedFile then
    self.iosPendingKind = "rom"
    if not pickFile("rom") then
      self.iosPendingKind = nil
      self:setError("Could not open the file picker.")
    end
    return
  end
  if self.android then
    -- Prefer a not-yet-imported .gb/.gbc already in the save dir (USB copy, or
    -- a fresh SAF pick).  Never reuse an already-imported cart's file -- that
    -- was the #167 failure mode (second Choose just re-extracted Red).
    local name, data, romPath = findPendingRom(self.ready, self.failedRoms)
    if name then
      self:startData(data, name, romPath)
    elseif consumePickedRomError(self) then
      return   -- a rejected pick explains itself instead of silently reopening
    elseif not pickFile() then
      -- Picker unavailable (API < 19, or no document-picker app installed):
      -- fall back to the USB folder-drop path as a friendly notice, not an
      -- error (which would read as a rejected file).
      self.notice = {
        version = self.chooseVersion,
        status = "No picker available, copy your ROM into:",
        detail = love.filesystem.getSaveDirectory(),
      }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local path = chooseRom(GameVersion.info(self.chooseVersion).displayName)
  if path then
    self:startPath(path)
    return
  end
  -- Handheld Linux (Anbernic stock OS / PortMaster) rarely has zenity or
  -- kdialog.  Fall back to the same "drop a .gb/.gbc next to the game" scan
  -- used on Android, which works when the game is launched as an unpacked
  -- directory (see build-rg34xxsp.sh).
  local name, data, romPath = findPendingRom(self.ready, self.failedRoms)
  if name then
    self:startData(data, name, romPath)
    return
  end
  if love.system.getOS() == "Linux" then
    local where = love.filesystem.getSourceBaseDirectory
      and love.filesystem.getSourceBaseDirectory()
      or love.filesystem.getSource and love.filesystem.getSource()
      or "the game folder"
    self.notice = {
      version = self.chooseVersion,
      status = "No file picker. Copy your .gb/.gbc into:",
      detail = where,
    }
    return
  end
  -- Console: no picker, no drag-and-drop, no shell to spawn one.  The scan
  -- above already looked; reaching here means the inbox is empty, so say
  -- where the inbox IS.  The old text sent the player to "drop the file onto
  -- the window", which on a Switch is not an instruction anyone can follow --
  -- it is the message that made a correct install look broken.
  if self.isNX or Platform.romImportMode() == "save-directory" then
    self:ensureImportsDir()
    local saveDir = love.filesystem.getSaveDirectory()
    local rel = RomImporter.mtpHintPath(saveDir)
    if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
    self.notice = {
      version = self.chooseVersion,
      status = "Copy your .gb/.gbc into:",
      detail = saveDir .. "/imports/\nDBI MTP -> 1: SD Card/" .. rel .. "imports/",
    }
    return
  end
  if love.system.getOS() ~= "OS X" and love.system.getOS() ~= "Windows" then
    self:setError("File selection is unavailable here. Drop the "
      .. ".gb/.gbc/.gba/.nds file onto the window.")
  end
end

-- Poll the save dir for a delivered pick (picked_rom.gb / picked_mod.zip /
-- picked_save.sav / export_done.flag) and run the same import path a refocus
-- runs.  Both mobiles need this, for different reasons:
--
--   iOS     the document picker is an in-process modal sheet, so there is no
--           love.focus(true) when it dismisses -- nothing else would consume it.
--   Android the SAF picker IS a separate activity and normally does refocus,
--           but Android may destroy GameActivity while it is up, in which case
--           the app restarts and that focus event never comes.  Polling makes
--           the outcome the same either way instead of leaving the pick on disk
--           for the next tap to find, which is what made users import twice and
--           what made it look random: it depends on memory pressure (#553).
--
-- Deliberately NO timeout.  A version of this disarmed the poll after 120s so a
-- cancelled picker would stop scanning, which was wrong on iOS: the picker there
-- is an in-process modal sheet, so update() keeps running while it is open and
-- the window burned down while the player was still browsing Files.  The pick
-- then landed with nothing armed to consume it, and because every path here is
-- silent on success the import just did not happen, with no error shown.  A
-- half-second directory listing on a menu screen is far cheaper than an import
-- that vanishes, so the poll stays armed until something is actually consumed.

function RomImporter:_pollPickedFiles(dt)
  if not self.pickPending then return end
  if self.workState == "working" then return end
  self.pickTimer = (self.pickTimer or 0) + dt
  if self.pickTimer < 0.5 then return end
  self.pickTimer = 0
  -- The Swift bridge reports a failed pick copy through pick_error.txt;
  -- surface it on whichever tab the player is looking at rather than
  -- letting the pick silently do nothing.
  local pickError = love.filesystem.read("pick_error.txt")
  if pickError then
    love.filesystem.remove("pick_error.txt")
    self.pickPending = nil
    if self._pickMany then
      self:_pickManyTally(false)
      self:_pickManyFinish()
    end
    self.modNotice = { ok = false, text = pickError }
    self.notice = { version = self.chooseVersion or "red",
                    status = "File import failed:", detail = pickError }
    return
  end
  local found = love.filesystem.getInfo("export_done.flag", "file") ~= nil
    or love.filesystem.getInfo("pick_error.flag", "file") ~= nil
    or love.filesystem.getInfo("picked_folder.txt", "file") ~= nil
  if not found then
    for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
      local n = name:lower()
      if isRomFileName(n) or n == "picked_mod.zip" or n == "picked_save.sav"
          or n == "picked_folder.txt" then
        found = true
        break
      end
    end
  end
  if found then
    self._pickIdle = nil
    self.pickPending = nil
    self:focus(true)
    return
  end
  -- A RUN NOBODY CANCELLED OUT LOUD.
  --
  -- love.focus(true) is the clean end of a keep-picking run (see
  -- _pickManyBegin), and Android is free to destroy the activity while the
  -- picker is up -- the app RESTARTS instead of resuming and that event never
  -- arrives.  A run left armed there would poll for a file for ever.
  --
  -- So: while THIS window has focus the picker is not in front of it, and a
  -- run that has sat through several focused polls with nothing to show for
  -- itself has been backed out of.  Three seconds, because the picker takes a
  -- moment to come up and the copy takes a moment to land.
  if self._pickMany and love.window and love.window.hasFocus
      and love.window.hasFocus() then
    self._pickIdle = (self._pickIdle or 0) + 1
    if self._pickIdle >= 6 then
      self._pickIdle = nil
      self:_pickManyFinish()
    end
  else
    self._pickIdle = nil
  end
end

function RomImporter:update(dt)
  self.pulse = self.pulse + dt
  self:_updatePadCursor(dt)
  -- A drop that landed last frame is a COMPLETE drop now: LOVE hands over one
  -- file per call and gives no "that was the last one", so the first update
  -- after the calls is where the whole set becomes knowable.
  self:_flushDroppedMods()
  if self._romQueueResume then
    self._romQueueResume = nil
    self:_advanceRomQueue()
    self:_romPickContinue()
  end
  if self.ios and love.system.getPickedFile and self.workState ~= "working" then
    local path = love.system.getPickedFile()
    if path then
      local kind = self.iosPendingKind or "rom"
      local version = self.iosPendingVersion
      self.iosPendingKind = nil
      self.iosPendingVersion = nil
      if kind == "mod" then
        self:_installMod(path)
        -- iOS does not loop (see _pickManyBegin), so this both counts the pick
        -- and closes the run.
        if self:_pickManyActive("mod") then
          self:_pickManyTally(self.modNotice and self.modNotice.ok)
          self:_pickManyAgain()
        end
      elseif kind == "sav" then
        self:_importSave(version or self:_savedropTarget(), path)
      else
        self:startPath(path)
      end
    elseif love.system.getPickError then
      local errorText = love.system.getPickError()
      if errorText then
        local kind = self.iosPendingKind or "rom"
        local version = self.iosPendingVersion or self:_savedropTarget()
        self.iosPendingKind = nil
        self.iosPendingVersion = nil
        -- a rejected pick ends a run rather than leaving it armed for a
        -- second file that is never asked for
        if self._pickMany then
          self:_pickManyTally(false)
          self:_pickManyFinish()
        end
        if kind == "mod" then
          self.modNotice = { ok = false, text = errorText }
        elseif kind == "sav" then
          self.saveNotice[version] = { ok = false, text = errorText }
        else
          self:setError(errorText)
        end
      end
    end
  end
  self:_pollPickedFiles(dt)
  self:_stepDataMove()
  self:_pollRomProbe()
  self:_pollRomScan()
  if self.workState ~= "working" or not self.worker then return end
  local started = love.timer.getTime()
  repeat
    local worker = self.worker
    if type(worker) ~= "thread" then return end
    local ok, workerError = coroutine.resume(worker)
    if not ok then
      print(debug.traceback(worker, tostring(workerError)))
      local detail = tostring(workerError)
      local missing = detail:match("required symbol is missing:%s*([%w_]+)")
      if missing then
        detail = "ROM import metadata is missing required symbol '" .. missing ..
          "'. This usually means the selected version's manifest/extractor " ..
          "pair does not support full runtime import yet."
      end
      self:setError(detail)
      return
    end
    -- A worker step may call setError(), which clears self.worker.
    if self.worker ~= worker then return end
    if coroutine.status(worker) == "dead" then
      self.worker = nil
      -- A QUEUED RUN CONTINUES HERE.  This is the one place an extraction is
      -- known to have finished successfully; setError is the other ending, and
      -- pumps the queue itself.
      self:_advanceRomQueue()
      self:_romPickContinue()
      return
    end
    if workerError=="background" then return end
  until love.timer.getTime() - started >= 0.003
end

-- ------- gamepad virtual cursor (handheld / PortMaster) --------------------
local PAD_DEAD = 0.28
local PAD_SPEED = 560   -- px/s at full stick deflection
local PAD_DPAD_SPEED = 420

function RomImporter:_activatePadCursor()
  if self._padCursorActive then return end
  local ox, oy, w, h = SafeArea.rect()
  if not self._padInited then
    self._padCursor.x = ox + w * 0.5
    self._padCursor.y = oy + h * 0.45
    self._padInited = true
  end
  self._padCursorActive = true
end

-- THE ROW AS IT IS ON SCREEN, not a list written when there were three games.
--
-- This named red / blue / yellow / mods / find and nothing else, so a gamepad
-- could not reach GOLD, SILVER, CRYSTAL, EMERALD, PRISM or POLISHED CRYSTAL at
-- all -- and pressing the bumper from any of them jumped to RED.  Reading
-- _visibleTabIds fixes that and makes the shoulder buttons walk exactly the
-- chips the generation filter is showing.
function RomImporter:_cycleTab(delta)
  local order = self:_visibleTabIds()
  local idx = 1
  for i, id in ipairs(order) do
    if id == self.tab then idx = i; break end
  end
  idx = ((idx - 1 + delta) % #order) + 1
  self.tab = order[idx]
  self._slotPress = nil
  self._modPress = nil
  self._findSearchFocus = false
  self:_disarmTextInput()
end

function RomImporter:_updatePadCursor(dt)
  -- Real mouse motion yields the pad cursor so desktop users keep a normal
  -- pointer after bumping a stick once.
  local mx, my = love.mouse.getPosition()
  if self._lastMouseX and self._padCursorActive then
    if math.abs(mx - self._lastMouseX) > 3 or math.abs(my - self._lastMouseY) > 3 then
      self._padCursorActive = false
    end
  end
  self._lastMouseX, self._lastMouseY = mx, my

  local ax = self._padAxis.leftx or 0
  local ay = self._padAxis.lefty or 0
  local dx, dy = 0, 0
  if math.abs(ax) > PAD_DEAD then dx = dx + ax end
  if math.abs(ay) > PAD_DEAD then dy = dy + ay end
  if self._padDir.dpleft then dx = dx - 1 end
  if self._padDir.dpright then dx = dx + 1 end
  if self._padDir.dpup then dy = dy - 1 end
  if self._padDir.dpdown then dy = dy + 1 end

  if dx ~= 0 or dy ~= 0 then
    self:_activatePadCursor()
    local mag = math.sqrt(dx * dx + dy * dy)
    if mag > 1 then dx, dy = dx / mag, dy / mag end
    local speed = (math.abs(ax) > PAD_DEAD or math.abs(ay) > PAD_DEAD)
      and PAD_SPEED or PAD_DPAD_SPEED
    local ox, oy, w, h = SafeArea.rect()
    local nx = self._padCursor.x + dx * speed * dt
    local ny = self._padCursor.y + dy * speed * dt
    self._padCursor.x = math.max(ox, math.min(ox + w, nx))
    self._padCursor.y = math.max(oy, math.min(oy + h, ny))
  end

  -- Right stick scrolls the active list (save slots or mods), or the whole page
  -- when it is the thing that overflows.
  local ry = self._padAxis.righty or 0
  if math.abs(ry) > PAD_DEAD then
    self:_activatePadCursor()
    local step = -ry * 480 * dt
    local maxPage = self._pageMax or 0
    if maxPage > 0 then
      self.pageScroll = math.max(0, math.min(maxPage, (self.pageScroll or 0) + step))
    elseif self.tab == "mods" then
      local maxS = self._modMax or 0
      if maxS > 0 then
        local next = (self.modScroll or 0) + step
        self.modScroll = math.max(0, math.min(maxS, next))
      end
    elseif self.tab == "find" then
      local maxS = self._findMax or 0
      if maxS > 0 then
        local next = (self.findScroll or 0) + step
        self.findScroll = math.max(0, math.min(maxS, next))
      end
    elseif GameVersion.VERSIONS[self.tab] then
      local maxS = (self._slotMax and self._slotMax[self.tab]) or 0
      if maxS > 0 then
        local next = (self.slotScroll[self.tab] or 0) + step
        self.slotScroll[self.tab] = math.max(0, math.min(maxS, next))
      end
    end
  end
end

function RomImporter:gamepadpressed(_, button)
  self:_activatePadCursor()
  -- Through GamepadMap, so the Switch's face buttons resolve to the Nintendo
  -- labels: SDL names them by POSITION, and Nintendo's A and B sit opposite
  -- to the Xbox layout SDL is named after, so SDL "b" is the button
  -- physically labelled A.  Testing the raw SDL name here accepted only the
  -- button labelled B -- which is why a Switch player saw the cursor move
  -- (sticks and dpad are position-independent) and click on nothing.
  local action = GamepadMap.mapGamepadButton(button)
  if action == "a" then
    -- Instant click at the virtual pointer (same path as a mouse/touch tap).
    self:mousepressed(self._padCursor.x, self._padCursor.y, 1)
  elseif button == "leftshoulder" then
    self:_cycleTab(-1)
  elseif button == "rightshoulder" then
    self:_cycleTab(1)
  elseif button == "dpup" or button == "dpdown"
      or button == "dpleft" or button == "dpright" then
    self._padDir[button] = true
  elseif button == "start" or button == "back" then
    -- Start / Select: Play if ready, else Choose ROM on the active game tab.
    if self.workState == "working" then return end
    local version = self.tab
    if GameVersion.VERSIONS[version] then
      if self.ready[version] then self:play(version) else self:choose(version) end
    end
  end
end

function RomImporter:gamepadreleased(_, button)
  if button == "dpup" or button == "dpdown"
      or button == "dpleft" or button == "dpright" then
    self._padDir[button] = nil
  end
end

function RomImporter:gamepadaxis(_, axis, value)
  if axis == "leftx" or axis == "lefty" or axis == "righty" then
    self._padAxis[axis] = value
    if math.abs(value) > PAD_DEAD then self:_activatePadCursor() end
  end
end

-- Same gate as src/core/Input.lua's isRawStick: a pad SDL can map already
-- reached gamepadpressed this frame, so re-entering it from the raw event
-- would fire the virtual cursor's click twice off one A press (#620).
local function isMappedPad(joystick)
  return GamepadMap.ignoreRawForJoystick(joystick)
end

function RomImporter:joystickpressed(joystick, button)
  if isMappedPad(joystick) then return end
  -- Raw index -> SDL button name, which gamepadpressed then resolves through
  -- the same face-swap table.  Hardcoding "a" here served only button 1 and
  -- meant an unmapped pad could reach exactly one action.
  local name = GamepadMap.mapRawToGamepadButton(button)
  if name then self:gamepadpressed(joystick, name) end
end

function RomImporter:joystickreleased(joystick, button)
  if isMappedPad(joystick) then return end
  local name = GamepadMap.mapRawToGamepadButton(button)
  if name then self:gamepadreleased(joystick, name) end
end

function RomImporter:joystickaxis(joystick, axis, value)
  if isMappedPad(joystick) then return end
  if axis == 1 then
    self:gamepadaxis(joystick, "leftx", value)
  elseif axis == 2 then
    self:gamepadaxis(joystick, "lefty", value)
  end
end

function RomImporter:joystickhat(joystick, hat, direction)
  if isMappedPad(joystick) then return end
  for _, dir in ipairs(self._rawHatDirs[hat] or {}) do
    self._padDir[dir] = nil
  end
  local dirs = ({
    u = { "dpup" }, d = { "dpdown" }, l = { "dpleft" }, r = { "dpright" },
    lu = { "dpleft", "dpup" }, ru = { "dpright", "dpup" },
    ld = { "dpleft", "dpdown" }, rd = { "dpright", "dpdown" },
  })[direction] or {}
  for _, dir in ipairs(dirs) do self._padDir[dir] = true end
  self._rawHatDirs[hat] = dirs
  if #dirs > 0 then self:_activatePadCursor() end
end

-- Player pressed Play on a game whose ROM is imported: hand off to boot.
function RomImporter:play(version)
  if self.workState == "working" then return end
  if not self.ready[version] then return end
  self._handedOff = true
  resetPointerCursor(self)
  if self.onComplete then self.onComplete(version) end
end

-- "re-import" a column: drop it back to the choose/drop state so a fresh ROM
-- can be selected (the extract replaces that version's cache).
function RomImporter:reimport(version)
  if self.workState == "working" then return end
  if not self.ready[version] then return end
  self.ready[version] = false
  self.returning[version] = false
  self.chooseVersion = version
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- set the current draw colour from a PAL triple (0-255), with optional alpha 0-1
local function col(c, a)
  love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
end

-- Faux-bold: the launcher's UI font ships no bold face, so 800-weight text
-- (headings, buttons) is thickened with a second sub-pixel pass.
local function printfB(text, x, y, w, align)
  love.graphics.printf(text, x, y, w, align)
  love.graphics.printf(text, x + 0.6, y, w, align)
end
local function printB(text, x, y)
  love.graphics.print(text, x, y)
  love.graphics.print(text, x + 0.6, y)
end

-- UTF-8 helpers for the slot-rename field (#205).  The `utf8` library only
-- exists inside LOVE (plain luajit, which loads this module in tests, has
-- none), so codepoint walking is done by hand -- the same lead-byte width
-- classes GenSave's encodeName uses.  utf8Back drops the last codepoint;
-- utf8Cap truncates to maxChars whole codepoints.
local function utf8Back(t)
  local i = #t
  while i > 0 do
    local b = t:byte(i)
    i = i - 1
    if b < 0x80 or b >= 0xC0 then break end -- lead or ASCII: dropped, done
  end
  return t:sub(1, i)
end
local function utf8Cap(t, maxChars)
  local count, i = 0, 1
  while i <= #t do
    count = count + 1
    if count > maxChars then return t:sub(1, i - 1) end
    local b = t:byte(i)
    i = i + ((b < 0x80) and 1 or (b < 0xE0) and 2 or (b < 0xF0) and 3 or 4)
  end
  return t
end

-- One reusable unit quad, recoloured per call, for every vertical gradient
-- fill (LOVE has no gradient primitive and a per-frame newMesh would churn
-- the GPU).  Callers set the blend mode; this only touches colour + geometry.
local gradMesh
local function setGrad(cTop, cBot, aTop, aBot)
  if not gradMesh then gradMesh = love.graphics.newMesh(4, "fan", "dynamic") end
  gradMesh:setVertices({
    { 0, 0, 0, 0, cTop[1] / 255, cTop[2] / 255, cTop[3] / 255, aTop },
    { 1, 0, 1, 0, cTop[1] / 255, cTop[2] / 255, cTop[3] / 255, aTop },
    { 1, 1, 1, 1, cBot[1] / 255, cBot[2] / 255, cBot[3] / 255, aBot },
    { 0, 1, 0, 1, cBot[1] / 255, cBot[2] / 255, cBot[3] / 255, aBot },
  })
end
local function fillGrad(x, y, w, h, cTop, cBot, aTop, aBot)
  setGrad(cTop, cBot, aTop, aBot)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(gradMesh, x, y, 0, w, h)
end
-- vertical gradient clipped to a rounded rectangle (via the stencil buffer)
local function fillGradRounded(x, y, w, h, r, cTop, cBot, aTop, aBot)
  love.graphics.stencil(function()
    love.graphics.rectangle("fill", x, y, w, h, r, r)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)
  fillGrad(x, y, w, h, cTop, cBot, aTop, aBot)
  love.graphics.setStencilTest()
end

-- Soft additive neon halo around a rounded rect.  LOVE has no blur, so stack
-- progressively larger, fainter translucent rounded rects.
local function neonGlow(x, y, w, h, r, c, strength)
  strength = math.max(0, strength)
  if strength == 0 then return end
  love.graphics.setBlendMode("add")
  local layers = 7
  for i = 1, layers do
    local g = i * 2.4
    love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255,
      strength * 0.05 * (1 - (i - 1) / layers))
    love.graphics.rectangle("fill", x - g, y - g, w + 2 * g, h + 2 * g, r + g, r + g)
  end
  love.graphics.setBlendMode("alpha")
end

-- A white shine band that sweeps across an active button, clipped to its
-- rounded shape.  phase is 0..1 (left of the button -> right of it).
local shineMesh
local function buttonShine(x, y, w, h, r, phase)
  if not shineMesh then
    -- triangle strip: three columns (transparent, white, transparent)
    shineMesh = love.graphics.newMesh({
      { 0,   0, 0,   0, 1, 1, 1, 0 },
      { 0,   1, 0,   1, 1, 1, 1, 0 },
      { 0.5, 0, 0.5, 0, 1, 1, 1, 0.5 },
      { 0.5, 1, 0.5, 1, 1, 1, 1, 0.5 },
      { 1,   0, 1,   0, 1, 1, 1, 0 },
      { 1,   1, 1,   1, 1, 1, 1, 0 },
    }, "strip", "static")
  end
  local bandW = w * 0.6
  local bx = x - bandW + phase * (w + bandW)
  love.graphics.stencil(function()
    love.graphics.rectangle("fill", x, y, w, h, r, r)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(shineMesh, bx, y, 0, bandW, h)
  love.graphics.setBlendMode("alpha")
  love.graphics.setStencilTest()
end

-- Draw letterspaced text (the UI font has no tracking control): advance glyph
-- by glyph.  Returns the total drawn width so a caller can align to it.
local function printSpaced(font, text, x, y, spacing)
  local cx = x
  for i = 1, #text do
    local ch = text:sub(i, i)
    love.graphics.print(ch, cx, y)
    cx = cx + font:getWidth(ch) + spacing
  end
  return math.max(0, cx - x - spacing)
end

-- Clip text to a pixel width, appending an ellipsis when it overflows (the UI
-- font has no built-in truncation).  Used for save-slot names / meta lines.
-- Drops whole UTF-8 codepoints (never mid-byte) so Font:getWidth cannot see
-- a truncated multi-byte sequence and throw "UTF-8 decoding error".
local function ellipsize(font, text, maxW)
  text = tostring(text or "")
  if maxW <= 0 or font:getWidth(text) <= maxW then return text end
  local ell = "..."
  local ew = font:getWidth(ell)
  while #text > 0 and font:getWidth(text) + ew > maxW do
    text = utf8Back(text)
  end
  return text .. ell
end

-- Stroke a rounded rectangle as a dashed outline (LOVE has no dashed line):
-- sample the path into a polyline -- corners as short arcs -- then walk it,
-- toggling on/off every dash/gap.  Used for the "+ New save slot" button and
-- the empty-slots box.  Caller sets colour + line width.
local function dashedRoundRect(x, y, w, h, r, dash, gap)
  r = math.min(r, w / 2, h / 2)
  local seg = 4
  local pts = {}
  local function arc(cx, cy, a0, a1)
    for i = 0, seg do
      local a = a0 + (a1 - a0) * (i / seg)
      pts[#pts + 1] = cx + math.cos(a) * r
      pts[#pts + 1] = cy + math.sin(a) * r
    end
  end
  arc(x + w - r, y + r, -math.pi / 2, 0)
  arc(x + w - r, y + h - r, 0, math.pi / 2)
  arc(x + r, y + h - r, math.pi / 2, math.pi)
  arc(x + r, y + r, math.pi, math.pi * 1.5)
  pts[#pts + 1] = pts[1]; pts[#pts + 1] = pts[2]   -- close the loop
  local remaining, drawing = dash, true
  for i = 1, #pts - 2, 2 do
    local x1, y1 = pts[i], pts[i + 1]
    local dx, dy = pts[i + 2] - x1, pts[i + 3] - y1
    local segLen = math.sqrt(dx * dx + dy * dy)
    local pos = 0
    while pos < segLen do
      local step = math.min(remaining, segLen - pos)
      if drawing then
        local t0, t1 = pos / segLen, (pos + step) / segLen
        love.graphics.line(x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1)
      end
      pos = pos + step
      remaining = remaining - step
      if remaining <= 0.0001 then
        drawing = not drawing
        remaining = drawing and dash or gap
      end
    end
  end
end

-- The redesign's standard content card: a faint top-lit blue tint fading into
-- a dark interior, with a thin cool-gray border.  Shared by the ROM / SAVE
-- FILES / SAVE SLOT cards and the mod cards so every panel matches.
local function roundedCard(x, y, w, h, r)
  fillGradRounded(x, y, w, h, r, PAL.blue, PAL.cardBlue, 0.08, 0.5)
  love.graphics.setLineWidth(1)
  col(PAL.cardBorder, 0.28)
  love.graphics.rectangle("line", x, y, w, h, r, r)
end

-- {top, bottom} of the scrolling page viewport, or nil while the page fits and
-- nothing scrolls.  Written once per frame by draw(); read by the two hit tests
-- (`inside` for clicks, `_ptIn` for hover) so a control scrolled out from under
-- the pinned header, or past the window bottom, stops responding at the moment
-- it stops being visible.  Rects that live in the pinned header carry
-- `pinned = true` and are exempt.
local pageBand = nil

-- Page-scroll arithmetic, kept pure (no love, no self) so the engine tier can
-- pin it: given how tall the column under the tab bar wants to be and how much
-- room is left under it, say whether the page scrolls, where it sits, and how
-- far it can go.  A window that grew back pulls the offset down with it rather
-- than leaving the page parked past its own end.
function RomImporter.pageScrollFor(naturalH, viewportH, scroll)
  local maxPage = math.max(0, (naturalH or 0) - math.max(0, viewportH or 0))
  return maxPage > 0, clamp(scroll or 0, 0, maxPage), maxPage
end

-- Every hit rect mousepressed dispatches on, cleared before any panel draws:
-- each rect is rebuilt only by the panel that draws its control, so whatever a
-- frame does not draw must not stay clickable.  Missing the Delete rects here
-- let a click on the mods tab land on the game tab's save Delete label (#433).
function RomImporter:_resetFrameRects()
  self.romButtonRect = nil
  self.playButtonRect = nil
  self.tabRects = {}
  -- Rebuilt only by the active version's SAVE SLOT panel, so the mods tab (or a
  -- version with no panel drawn this frame) cannot inherit last frame's rows.
  self.slotRects = nil
  self.slotEditRects = nil
  self.slotDeleteRects = nil
  self.newSlotRect = nil
  -- Rebuilt only by the mods panel; nil elsewhere so a game tab cannot inherit
  -- last frame's mod toggles / Delete labels / import button.
  self.modRects = nil
  self.modDeleteRects = nil
  self.modImportRect = nil
  self.modImportFileRects = nil
  self.modImportGameRects = nil
  -- Enable all / Disable all share that header and the same rule (#647): they
  -- are only drawn when the row is wide enough, so a stale rect would otherwise
  -- stay clickable over whatever the next tab (or the next window size) draws.
  self.modEnableAllRect = nil
  self.modDisableAllRect = nil
  self.modImportManyRect = nil
  self.modImportFolderRect = nil
  self.modGenRects = nil
  -- The generation dropdown is drawn on every tab, but only when the row is
  -- wide enough for it (see draw()), so a stale rect would keep taking clicks
  -- on a narrow window.  The MENU's rows are rebuilt only while it is open.
  self.genDropdownRect = nil
  self.genMenuRects = nil
  -- Drawn beside the dropdown and dropped on a narrow row for the same reason,
  -- so it gets the same treatment: a stale rect would keep taking clicks.
  self.romBatchRect = nil
  -- Same rule as the toggles above, and it started to bite once FIND MODS gave
  -- the mods tab a neighbour: these two were rebuilt by the mods panel but
  -- never cleared, so switching tabs left the last mod row's Update / Versions
  -- labels clickable over whatever the next tab drew there (#433's shape).
  self.modUpdateRects = nil
  self.modVersionsRects = nil
  -- The gear and the settings rows: the gear is drawn on every tab, the rows
  -- only by the settings panel.
  self.settingsRect = nil
  self.settingsRowRects = nil
  self.mapEditorRect = nil
  -- Rebuilt only by the FIND MODS panel.
  self.findAddRect = nil
  self.findRefreshRect = nil
  self.findSearchRect = nil
  self.findCatRects = nil
  self.findInstallRects = nil
  self.findDetailRects = nil
  self.findRepoRects = nil
  self.findSourceRemoveRects = nil
  -- Rebuilt only by the active game panel's SAVE FILES card; nil elsewhere so
  -- the mods tab cannot inherit last frame's save Import/Export/open-folder hits.
  self.saveImportRect = nil
  self.saveExportRect = nil
  self.saveFolderRect = nil
  -- Rebuilt only by the active game panel; nil elsewhere so the mods tab
  -- cannot inherit last frame's Touch Controls button.
  self.touchControlsRect = nil
end

function RomImporter:draw()
  -- Full window for immersive backdrop; safe rect for interactive chrome so
  -- notch / Dynamic Island / home indicator / Android cutouts are respected.
  local fullW, fullH = love.graphics.getDimensions()
  local ox, oy, width, height = SafeArea.rect()
  local s = clamp(height / 768, 0.7, 1.6)
  local pulse = self.pulse
  self._s = s

  -- Hover state.  Desktop mouse, or the gamepad virtual cursor on handhelds
  -- (Android stays touch-only -- no hover).  Panel methods read the pointer +
  -- set self._anyHover through self:_hover; the cursor is set at the end.
  -- Reset the per-frame hit rects so a tab with no controls (mods) cannot
  -- inherit last frame's game-panel buttons.
  if self._padCursorActive then
    self._mx, self._my = self._padCursor.x, self._padCursor.y
  else
    self._mx, self._my = love.mouse.getPosition()
  end
  self._hoverEnabled = self._padCursorActive or not self.android
  self._anyHover = false
  self:_resetFrameRects()

  -- Fonts + size-dependent scenery, rebuilt only when the window / safe
  -- area changes (rotation, resize, inset changes).
  local fontKey = ("%dx%d@%d,%d"):format(fullW, fullH, ox, oy)
  if self.fontKey ~= fontKey then
    self.fontKey = fontKey
    local function f(px) return love.graphics.newFont(math.max(8, math.floor(px + 0.5))) end
    self.headFont     = f(19 * s)
    self.detailFont   = f(14 * s)
    self.buttonFont   = f(19 * s)
    self.hintFont     = f(13 * s)
    self.warningFont  = f(11 * s)
    -- redesign faces
    self.gameNameFont = f(26 * s)   -- game / "Mods" heading
    self.pillFont     = f(13 * s)   -- status pill
    self.labelFont    = f(12 * s)   -- letterspaced ROM / SAVE FILES / SAVE SLOT
    self.stateFont    = f(16 * s)   -- ROM state line
    self.saveBtnFont  = f(14 * s)   -- glassy card buttons
    self.chipFont     = f(20 * s)   -- R / B / Y tab letters
    self.tabLabelFont = f(14 * s)   -- active tab label
    self.readyFont    = f(12 * s)   -- "N of X ready"
    self.playFont     = f(20 * s)   -- Play button
    self.slotNameFont = f(15 * s)   -- save-slot player name / "NEW GAME"

    -- CRT vignette: a gentle edge darkening, centred slightly above the middle.
    do
      local cx, cy = fullW / 2, fullH * 0.45
      local rx, ry = fullW * 0.78, fullH * 0.78
      local n = 72
      local verts = { { cx, cy, 0, 0, 0, 0, 0, 0 } }
      for i = 0, n do
        local a = (i / n) * math.pi * 2
        verts[#verts + 1] =
          { cx + math.cos(a) * rx, cy + math.sin(a) * ry, 0, 0, 0, 0, 0, 0.32 }
      end
      self.vignetteMesh = love.graphics.newMesh(verts, "fan", "static")
    end

    -- CRT scanlines: a 1px dark line every 3px, baked into a tiny tile and
    -- drawn once with a repeat-wrapped quad (one draw call, correct alpha).
    if not self.scanlineImage then
      local id = love.image.newImageData(1, 3)
      id:setPixel(0, 0, 0, 0, 0, 0.08)
      id:setPixel(0, 1, 0, 0, 0, 0)
      id:setPixel(0, 2, 0, 0, 0, 0)
      self.scanlineImage = love.graphics.newImage(id)
      self.scanlineImage:setWrap("repeat", "repeat")
      self.scanlineImage:setFilter("nearest", "nearest")
    end
    self.scanlineQuad = love.graphics.newQuad(0, 0, fullW, fullH, 1, 3)
  end

  -- Invert shader: the Boi's Club Games mark is dark ink; on this dark panel it
  -- is rendered white (the design's filter:invert(1)).  Built lazily so a
  -- headless require never needs a GL context.
  self.invertShader = self.invertShader or love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      return vec4((vec3(1.0) - p.rgb) * color.rgb, p.a * color.a);
    }
  ]])

  -- Shine shader: the same white sweep the active buttons get, but clipped to
  -- the logo's own shape (a soft band brightens the pixels it crosses; fully
  -- transparent pixels stay transparent).
  self.shineShader = self.shineShader or love.graphics.newShader([[
    extern number shinePos;
    extern number shineW;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      float band = smoothstep(shineW, 0.0, abs(tc.x - shinePos));
      return vec4(p.rgb + band * 0.55, p.a) * color;
    }
  ]])

  -- BACKGROUND: a radial gradient (bright point at top-centre -> near black).
  -- A triangle fan from the top-centre gives the radial falloff; the screen is
  -- cleared to the outer colour first so the corners it does not reach match
  -- seamlessly.  Sized to the full window so unsafe edges stay filled.
  --
  -- ITS OWN KEY, not the font one.  A mesh's vertex colours are BAKED at build
  -- time, so while this was rebuilt only on a resize, changing the theme
  -- repainted every card, every label and the flat clear underneath -- and
  -- left the gradient on top of them exactly as it was.  Reported as the theme
  -- not changing the background, which is precisely what it was.
  local glow = PAL.bgGlow or PAL.bgTop
  local bgKey = ("%dx%d|%d,%d,%d|%d,%d,%d"):format(fullW, fullH,
    glow[1], glow[2], glow[3], PAL.bgBot[1], PAL.bgBot[2], PAL.bgBot[3])
  if self.bgKey ~= bgKey or not self.bgMesh then
    self.bgKey = bgKey
    local cx, cy = fullW / 2, 0
    local rx, ry = fullW * 1.3, fullH * 1.08
    local n = 72
    local verts = { { cx, cy, 0, 0,
      glow[1] / 255, glow[2] / 255, glow[3] / 255, 1 } }
    for i = 0, n do
      local a = (i / n) * math.pi * 2
      verts[#verts + 1] = { cx + math.cos(a) * rx, cy + math.sin(a) * ry, 0, 0,
        PAL.bgBot[1] / 255, PAL.bgBot[2] / 255, PAL.bgBot[3] / 255, 1 }
    end
    self.bgMesh = love.graphics.newMesh(verts, "fan", "static")
  end

  -- background (full window — unsafe edges stay painted)
  col(PAL.bgBot)
  love.graphics.rectangle("fill", 0, 0, fullW, fullH)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.bgMesh)

  -- Centered content container (max ~1440 scaled units on very wide windows)
  -- with a responsive side gutter; every column below derives from these.
  -- Origin is the safe-area top-left so chrome clears device insets.
  local appW = math.min(width, 1440 * s)
  local appX = ox + (width - appW) / 2
  local padH = clamp(appW * 0.03, 12 * s, 26 * s)
  local third = appW / 3

  -- tricolor strip (Red | Blue | Yellow), 6px tall, with a soft downward bloom
  local stripH = math.max(4, 6 * s)
  local stripY = oy
  local segs = {
    { PAL.red,  appX,             third },
    { PAL.blue, appX + third,     third },
    { PAL.gold, appX + 2 * third, appW - 2 * third },
  }
  love.graphics.setBlendMode("add")
  for _, seg in ipairs(segs) do
    fillGrad(seg[2], stripY + stripH, seg[3], stripH * 3.6, seg[1], seg[1], 0.30, 0.0)
  end
  love.graphics.setBlendMode("alpha")
  for _, seg in ipairs(segs) do
    col(seg[1]); love.graphics.rectangle("fill", seg[2], stripY, seg[3], stripH)
  end

  -- Footer (Boi's Club Games logo + trust warning), measured first so the
  -- content region knows where it must stop.  Only its height is fixed here:
  -- it is laid out from a top edge further down, which is the window bottom
  -- while the page fits and the end of the scrolled content when it does not.
  local warningWidth = math.min(appW - 32 * s, 640 * s)
  local _, warningLines = self.warningFont:getWrap(TRUST_WARNING, warningWidth)
  local warningH = #warningLines * self.warningFont:getHeight()
  local ourTab = RomImporter.wearsOurMark(self.tab)
  local bcgImage = ourTab and self.gen2Bcg or self.bcg
  local logoImage = ourTab and self.gen2Logo or self.logo
  local bcgW, bcgH = bcgImage:getDimensions()
  local bcgScale = math.min(math.min(appW - 48 * s, 190 * s) / bcgW, height * 0.06 / bcgH)
  local bcgDW, bcgDH = bcgW * bcgScale, bcgH * bcgScale
  -- The credit line and the donate chips sit on their own rows under the
  -- warning, so their height is reserved here too: measure them the same way
  -- _chipButton will, or the page ends up scrolling short and a chip falls off
  -- the bottom edge. A tab with no donate links reserves no chip row.
  local credit = RomImporter.creditFor(self.tab)
  local footerLinks, paypalLink = {},nil
  for _,link in ipairs(credit.links) do
    if link.url==DONATE_URL then paypalLink=link
    else footerLinks[#footerLinks+1]=link end
  end
  local creditH = self.hintFont:getHeight()
  local donateH = self.hintFont:getHeight() + 10 * s
  local chipsH = (#footerLinks > 0) and (8 * s + donateH) or 0
  local footerH = 10 * s + bcgDH + 6 * s + warningH + 8 * s + creditH + chipsH + 12 * s

  -- Logo: centred over the strip, width clamped, gentle bob + glow pulse.  The
  -- resting metrics fix the tab bar's top so the layout never shifts as it bobs.
  local logoW, logoH = logoImage:getDimensions()
  local tiltW, tiltH = self.tiltRipsLogo:getDimensions()
  local tiltTargetW = math.min(116 * s,appW * 0.20)
  local tiltScale = tiltTargetW / tiltW
  local tiltDH = tiltH * tiltScale
  local tiltCodeScale = math.min(1,tiltTargetW / self.warningFont:getWidth("GEN2RECOMP"))
  local tiltCodeH = self.warningFont:getHeight() * 2 * tiltCodeScale
  local tiltBlockH = tiltDH + 4 * s + tiltCodeH
  local paypalW = paypalLink and math.min(self.hintFont:getWidth(paypalLink.label)+24*s,appW*0.20) or 0
  local paypalFont = self.hintFont
  if paypalLink and paypalFont:getWidth(paypalLink.label)>paypalW-12*s then paypalFont=self.warningFont end
  local paypalBaseW = paypalW
  paypalW = paypalW * 2
  local paypalH = donateH * 2
  local paypalStacked = paypalLink and appW < 2 * (paypalW + padH + 8 * s) + 180 * s
  if paypalLink then
    local fontSize=paypalFont:getHeight()*2
    if self._paypalFontSize~=fontSize then
      self._paypalFontSize=fontSize
      self._paypalFont=love.graphics.newFont(fontSize)
    end
    paypalFont=self._paypalFont
  end
  -- Keep the centered wordmark clear of the corner link on narrow screens.
  local logoTargetW = math.min(appW - 2 * (math.max(tiltTargetW,paypalStacked and paypalBaseW or paypalW) + padH + 8 * s),math.max(math.min(180 * s, appW - 32 * s),
    math.min(330 * s, appW - 32 * s)))
  local logoScale = math.min(logoTargetW / logoW, height * 0.15 / logoH)
  local logoDW, logoDH = logoW * logoScale, logoH * logoScale
  local logoY = stripY + stripH + 14 * s
  local paypalY = paypalStacked and (logoY + math.max(logoDH,tiltBlockH) + 12 * s) or (logoY + 16 * s)

  -- Tab bar: R/B/Y/divider/MODS chips (label + underline on the active one),
  -- with "N of X ready" right-aligned.
  local chip = 44 * s
  local tabBarY = math.max(logoY + math.max(logoDH,tiltBlockH),paypalLink and (paypalY+paypalH) or 0) + 6 * s
  local tabBarH = chip + 22 * s

  -- Self-updater banner state: computed up front so its band can be reserved
  -- above the footer, then drawn after the content below.
  --
  -- WHICH STATES SURFACE is Check's answer, not a list kept here.  It was a
  -- list, of four, and "error" was not in it -- so a host that cannot check at
  -- all (the Switch, an Xbox UWP container: no HTTPS client reachable from Lua)
  -- ended on "error" and the launcher drew NOTHING, which is why those two
  -- looked like builds with no updater rather than builds with a disabled one.
  -- Check.STATUS now marks the drawable states and Check.state() reports a
  -- `notify` one for exactly that case; tools/auto_update_check.lua asserts the
  -- two halves still agree.
  --
  -- upAdvice is "download" | "ota" | "package" | "releases" -- what the player
  -- should DO on this host, decided in src/update/Check.lua so the banner only
  -- has to pick the wording.
  local upStatus, upLatest, upProgress, upAdvice, upCannotCheck
  if self.Check then
    local ok, st = pcall(self.Check.state)
    st = (ok and type(st) == "table") and st or nil
    local status = st and st.status
    local drawable = self.Check.STATUS or {}
    if status and drawable[status] then
      upStatus, upLatest, upProgress = status, st.latest, st.progress
      upAdvice = st.advice or "releases"
      -- Resolved HERE and not in the banner below, so that the only places the
      -- text `upStatus == "<state>"` appears in this file are the branch heads
      -- of the banner's own dispatch.  tools/auto_update_check.lua derives the
      -- set of states the banner draws by reading those heads, and a second
      -- test of the same literal further in made that derivation pass while
      -- the state was no longer drawn at all -- a vocabulary scan with two
      -- sources for one token cannot grade membership.
      upCannotCheck = (status == "notify")
    end
  end
  local bannerActive = upStatus ~= nil
  local bannerH = 46 * s

  -- THE MASS-IMPORT LINE, between the chips and the panel.
  --
  -- It needs its own band rather than a corner of somebody else's: a queued
  -- run walks from game to game, so there is no one tab its progress belongs
  -- on, and its summary is about files that may have become no game at all.
  -- Measured here so `contentTop` below moves with it and the panel is never
  -- drawn under it.
  local batchText, batchOk = self:_romBatchLine()
  local batchH, batchLines = 0, 1
  if batchText then
    -- Measured for the same reason the mods notice is (see _drawModsPanel): a
    -- summary that names four cartridges and two rejects is not one line, and
    -- a band sized for one would run down through the panel below it.
    local _, wrapped = self.hintFont:getWrap(batchText, appW - 2 * padH - 24 * s)
    batchLines = math.max(1, math.min(#wrapped, 4))
    batchH = batchLines * self.hintFont:getHeight() + 16 * s
  end
  local batchBand = batchText and (batchH + 10 * s) or 0

  -- Content region: from below the tab bar down to the footer, minus the
  -- updater band when one is showing.
  local contentTop = tabBarY + tabBarH + 16 * s + batchBand
  local bannerBand = bannerActive and (bannerH + 20 * s) or 6 * s
  local cX = appX + padH
  local cW = appW - 2 * padH
  -- THE HEADER ROW'S REMAINING WIDTH, and NOT the content width.
  --
  -- The gear, the generation dropdown and IMPORT ROMS each take their slice
  -- off the right-hand end of the row they share, so what is left over is what
  -- the chip row may use.  That is a fact about ONE ROW.  It used to be
  -- subtracted from `cW` itself, which is also the width every panel below is
  -- drawn at -- so on a phone in portrait, where those three controls eat most
  -- of a narrow row, the whole launcher underneath was squeezed into a strip
  -- about a third of the screen wide with its labels wrapping one word to a
  -- line (reported with a screenshot).  Nothing below the bar has any business
  -- narrowing because of what is on it.
  local barW = cW
  local contentBottom = oy + height - footerH - bannerBand
  local cH = math.max(0, contentBottom - contentTop)

  -- Page scroll.  Everything under the tab bar -- panel, updater banner and
  -- footer -- is one column: too short a window scrolls it instead of letting
  -- the panel run under a footer pinned to the window bottom (a stacked
  -- single-column layout on a phone-shaped window overflows by a card or two).
  -- The panels report their natural height as they draw, so the decision reads
  -- the previous frame's measurement, the same one-frame settle the slot and
  -- mod lists already rely on.  While the page fits, `paged` is false and every
  -- measurement below is what it always was.
  local viewportH = math.max(0, oy + height - contentTop)
  self._panelNaturalH = self._panelNaturalH or {}
  local naturalH = (self._panelNaturalH[self.tab] or 0) + bannerBand + footerH
  local paged, pageScroll, maxPage =
    RomImporter.pageScrollFor(naturalH, viewportH, self.pageScroll)
  self.pageScroll, self._pageMax = pageScroll, maxPage
  -- read by the hit tests; a scrolled control is live only inside the viewport
  pageBand = paged and { contentTop, oy + height } or nil

  -- THE GEAR, top right, on every tab.
  --
  -- Pinned beside the tab bar rather than made a chip in it: the bar scrolls
  -- horizontally and a chip can be pushed off the edge, which is exactly what
  -- must not happen to the way back out of a settings screen. Drawn before the
  -- bar so the bar's own scissor cannot clip it.
  do
    local gear = 30 * s
    local gx = cX + barW - gear
    local gy = tabBarY + (tabBarH - gear) / 2
    local on = self.settingsOpen and true or false
    col(on and PAL.link or PAL.warning, on and 1 or 0.75)
    love.graphics.setLineWidth(math.max(1, 2 * s))
    local cx, cy, r = gx + gear / 2, gy + gear / 2, gear * 0.28
    love.graphics.circle("line", cx, cy, r)
    -- eight teeth: a ring of short spokes reads as a gear at any size, and
    -- costs nothing next to shipping an icon that has to be themed twice.
    for i = 0, 7 do
      local a = i * math.pi / 4
      local c2, s2 = math.cos(a), math.sin(a)
      love.graphics.line(cx + c2 * r, cy + s2 * r,
                         cx + c2 * r * 1.55, cy + s2 * r * 1.55)
    end
    love.graphics.circle("line", cx, cy, r * 0.38)
    love.graphics.setLineWidth(1)
    -- `width`/`height`, not `w`/`h`: `inside` reads those two names and
    -- nothing else, so the short spelling was a nil arithmetic the first time
    -- anyone clicked anywhere. And `pinned`, because the gear is drawn above
    -- the scrolling viewport -- without it the hit test rejects the press the
    -- moment the page scrolls at all, which is the one control that must
    -- always answer: it is the way back out of the settings screen.
    self.settingsRect = { x = gx - 6 * s, y = gy - 6 * s,
                          width = gear + 12 * s, height = gear + 12 * s,
                          pinned = true }
    -- and the bar stops short of it, so a long chip row cannot run underneath
    barW = barW - gear - 10 * s
  end

  -- THE GENERATION DROPDOWN, beside the gear and on the same rule: pinned out
  -- of the chip row's own horizontal scroll, so it cannot be pushed off the
  -- edge by a row it exists to shorten.
  do
    love.graphics.setFont(self.hintFont)
    local function widthOf(short)
      local widest = self.hintFont:getWidth(
        RomImporter.generationLabel(false, short))
      for _, g in ipairs(RomImporter.GENERATIONS) do
        widest = math.max(widest, self.hintFont:getWidth(
          RomImporter.generationLabel(g, short)))
      end
      return widest + 36 * s
    end
    local dh = math.max(26 * s, self.hintFont:getHeight() + 12 * s)
    local dw, short = widthOf(false), false
    -- A phone-width row cannot carry "GEN 2" as well as nine chips and a gear,
    -- so the chip shortens to "G2" before it is given up on.
    if barW <= dw + 140 * s then dw, short = widthOf(true), true end
    if barW > dw + 110 * s then
      self._genFilterSuppressed = nil
      self:_drawGenDropdown(cX + barW - dw, tabBarY + (tabBarH - dh) / 2, dw, dh,
                            short)
      barW = barW - dw - 10 * s
      -- MASS ROM IMPORT, immediately left of it ("next to the gen select
      -- button").  Dropped before the dropdown is on a narrow row, because the
      -- dropdown is the control that makes a nine-chip row usable at all and
      -- every game's own panel still has its own Import ROM button.
      local label = Strings("IMPORT ROMS")
      local rw = self.hintFont:getWidth(label) + 26 * s
      if barW > rw + 110 * s then
        self.romBatchRect = self:_chipButton(cX + barW - rw,
          tabBarY + (tabBarH - dh) / 2, label,
          { w = rw, h = dh, kind = "accent" })
        self.romBatchRect.pinned = true
        barW = barW - rw - 10 * s
      end
    else
      -- NO DROPDOWN MEANS NO FILTER, or the player is left looking at one
      -- generation's chips with nothing on screen that could put the rest
      -- back.  The choice is kept -- it is still in options and comes back the
      -- moment the window is wide enough -- it simply does not apply here.
      self._genFilterSuppressed = true
      self.genDropdownRect = nil
      self._genMenuOpen = false
    end
  end

  -- tab bar (rebuilds self.tabRects).  Pinned: it is the launcher's navigation,
  -- and it sits above the scrolling viewport.
  self:_drawTabBar(cX, tabBarY, barW, tabBarH, chip)

  if batchText then
    local by = tabBarY + tabBarH + 10 * s
    local bw = appW - 2 * padH
    local tint = batchOk and PAL.playTop or PAL.chooseTop
    col(tint, 0.12)
    love.graphics.rectangle("fill", cX, by, bw, batchH, 8 * s, 8 * s)
    love.graphics.setLineWidth(math.max(1, s))
    col(tint, 0.5)
    love.graphics.rectangle("line", cX, by, bw, batchH, 8 * s, 8 * s)
    love.graphics.setFont(self.hintFont)
    col(batchOk and PAL.playTop or PAL.warning)
    -- the whole block centred, not one line's worth: batchH was measured off
    -- the wrap above and a summary is routinely two or three lines
    love.graphics.printf(batchText, cX + 12 * s,
      by + (batchH - batchLines * self.hintFont:getHeight()) / 2,
      bw - 24 * s, "left")
  end

  local panelY = contentTop - (paged and self.pageScroll or 0)
  if paged then
    love.graphics.setScissor(math.floor(appX), math.floor(contentTop),
      math.ceil(appW), math.ceil(viewportH))
  end

  -- content: game panel for a version tab, mods panel for the mods tab
  local panelH
  if self.tab == "mods" then
    panelH = self:_drawModsPanel(cX, panelY, cW, cH, paged)
  elseif self.tab == "find" then
    panelH = self:_drawFindPanel(cX, panelY, cW, cH, paged)
  else
    panelH = self:_drawGamePanel(self.tab, cX, panelY, cW, cH, paged)
  end
  panelH = panelH or 0
  self._panelNaturalH[self.tab] = panelH

  -- THE SETTINGS DRAWER, over the panel it belongs to.
  --
  -- Drawn here rather than in the panel branch above because it is over the
  -- tab you were on, not instead of it: the mod options make more sense with
  -- the mod list still visible behind them, and nothing in here is worth
  -- losing sight of your games for.
  --
  -- Its rects are stamped `pinned` (it floats above the page viewport, so the
  -- page's own band must not reject them) and `clipY` to the drawer's
  -- viewport (it scrolls independently, so a row scrolled out of ITS view has
  -- to be dead even though the page has not scrolled at all).
  self.settingsDrawerRect = nil
  if self.settingsOpen then
    local pad = 16 * s
    local dw = math.max(300 * s, math.min(560 * s, appW * 0.52))
    local dx = appX + appW - dw
    local dy = contentTop
    local dh = math.max(60 * s, contentBottom - contentTop)
    self.settingsDrawerRect = { x = dx, y = dy, width = dw, height = dh,
                                pinned = true }

    col(PAL.bgTop or PAL.bgBot, 0.97)
    love.graphics.rectangle("fill", dx, dy, dw, dh)
    col(PAL.cardBorder, 0.5)
    love.graphics.rectangle("fill", dx, dy, math.max(1, 1 * s), dh)

    local prevBand = pageBand
    pageBand = nil                     -- the drawer is not the page
    love.graphics.setScissor(math.floor(dx), math.floor(dy),
                             math.ceil(dw), math.ceil(dh))
    local natural = self:_drawSettingsPanel(dx + pad,
      dy + pad - (self.settingsScroll or 0), dw - 2 * pad, dh, false) or 0
    love.graphics.setScissor()
    pageBand = prevBand

    for _, r in ipairs(self.settingsRowRects or {}) do
      for _, part in pairs(r) do
        if type(part) == "table" and part.width then
          part.pinned = true
          part.clipY = { dy, dy + dh }
        end
      end
    end
    self._settingsMax = math.max(0, natural + 2 * pad - dh)
  end

  -- The updater band and the footer follow the content: pinned to the window
  -- bottom while the page fits, riding at the end of the scroll when it does not.
  local bandTop = paged and (panelY + panelH) or contentBottom
  local footerTop = bandTop + bannerBand

  -- Self-updater banner: a compact pill centred in the reserved band just above
  -- the footer, on every tab.  Same green "Play" treatment on its CTA.
  self.updateButton = nil
  if bannerActive then
    local bannerW = math.min(appW - 32 * s, 560 * s)
    local bx = appX + (appW - bannerW) / 2
    local by = bandTop + math.max(0, (footerTop - bandTop - bannerH) / 2)
    local r = 12 * s
    local accent = PAL.gold

    neonGlow(bx, by, bannerW, bannerH, r, accent, 0.28)
    fillGradRounded(bx, by, bannerW, bannerH, r, accent, PAL.bgBot, 0.14, 0.6)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(accent, 0.5)
    love.graphics.rectangle("line", bx, by, bannerW, bannerH, r, r)

    local padX = 16 * s
    local innerX = bx + padX
    local innerW = bannerW - 2 * padX

    local function actionButton(label)
      love.graphics.setFont(self.detailFont)
      local bw = math.min(innerW * 0.62, self.detailFont:getWidth(label) + 34 * s)
      local bh = bannerH - 12 * s
      local abx = bx + bannerW - padX - bw
      local aby = by + (bannerH - bh) / 2
      local br = 9 * s
      local rect = { x = abx, y = aby, width = bw, height = bh }
      local hot = self:_hover(rect)
      local gp = 0.5 + 0.5 * math.sin(pulse * 2 * math.pi / 2.4)
      neonGlow(abx, aby, bw, bh, br, PAL.playTop, (0.6 + 0.25 * gp) * (hot and 1.7 or 1))
      fillGradRounded(abx, aby, bw, bh, br, PAL.playTop, PAL.playBot, 1, 1)
      if hot then
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 1, 1, 0.12)
        love.graphics.rectangle("fill", abx, aby, bw, bh, br, br)
        love.graphics.setBlendMode("alpha")
      end
      buttonShine(abx, aby, bw, bh, br, (pulse % 2.8) / 2.8)
      love.graphics.setFont(self.detailFont)
      col(PAL.playInk)
      printfB(label, abx, aby + (bh - self.detailFont:getHeight()) / 2, bw, "center")
      return rect
    end

    local function message(text, reserveW)
      love.graphics.setFont(self.detailFont)
      col(PAL.heading)
      love.graphics.printf(text, innerX,
        by + (bannerH - self.detailFont:getHeight()) / 2,
        math.max(1, innerW - reserveW - 12 * s), "left")
    end

    if upStatus == "available" then
      local rect = actionButton("Update")
      self.updateButton = { x = rect.x, y = rect.y, width = rect.width,
        height = rect.height, action = "download" }
      message(upLatest and ("Update v" .. upLatest .. " available")
        or Strings("An update is available"), rect.width)
    elseif upStatus == "needs_full" or upStatus == "notify" then
      -- ONE ROW, THREE TRUTHS, and it used to tell only the first of them.
      --
      -- "A new version needs a fresh download" + "Open releases" is right on a
      -- desktop and on Android: the release carries no in-place payload (or its
      -- minShell needs a newer native build), and the releases page is where
      -- the installer is.  It is wrong on both consoles.  A Switch player
      -- updates by running ports/switch/ota-launcher's gen2recomp.nro, which
      -- checks GitHub and replaces both NROs itself; an Xbox player installs a
      -- newer package.  And neither has a browser for the button to open --
      -- love.system.openURL on those hosts does nothing at best.
      --
      -- So the two console advices draw NO button: a dead button is worse than
      -- no button, because the player taps it and concludes the updater is
      -- broken.  The sentence is the whole row there.
      local label, action
      if upAdvice == "ota" then
        label = Strings("Update from the OTA launcher (gen2recomp.nro)")
      elseif upAdvice == "package" then
        label = Strings("Install the newer package to update")
      elseif upCannotCheck then
        label = Strings("Cannot check for updates on this build")
        action = "openurl"
      else
        label = Strings("A new version needs a fresh download")
        action = "openurl"
      end
      local reserve = 0
      if action then
        local rect = actionButton("Open releases")
        self.updateButton = { x = rect.x, y = rect.y, width = rect.width,
          height = rect.height, action = action }
        reserve = rect.width
      end
      message(label, reserve)
    elseif upStatus == "ready" then
      local rect = actionButton("Restart to update")
      self.updateButton = { x = rect.x, y = rect.y, width = rect.width,
        height = rect.height, action = "restart" }
      message("Update downloaded", rect.width)
    elseif upStatus == "downloading" then
      love.graphics.setFont(self.hintFont)
      col(PAL.detail)
      love.graphics.print("Downloading update", innerX, by + 7 * s)
      local h2 = math.max(8, 10 * s)
      local track = by + bannerH - h2 - 8 * s
      col(PAL.bgBot, 0.85)
      love.graphics.rectangle("fill", innerX, track, innerW, h2, h2 / 2, h2 / 2)
      local pw = innerW * clamp(upProgress or 0, 0, 1)
      if pw > h2 then
        neonGlow(innerX, track, pw, h2, h2 / 2, accent, 0.6)
        col(accent)
        love.graphics.rectangle("fill", innerX, track, pw, h2, h2 / 2, h2 / 2)
      end
    end
  end

  -- footer: a hairline top border, the BCG mark (inverted to white, glowing
  -- brighter on hover) + the trust warning with its live bois.icu link.  Laid
  -- out downward from footerTop, so the same code serves the pinned and the
  -- scrolled position.
  love.graphics.setLineWidth(1)
  col(PAL.cardBorder, 0.18)
  love.graphics.line(appX + padH, footerTop, appX + appW - padH, footerTop)

  local bcgX, bcgY = appX + (appW - bcgDW) / 2, footerTop + 10 * s
  local warningY = bcgY + bcgDH + 6 * s
  self.bcgButton = { x = bcgX, y = bcgY, width = bcgDW, height = bcgDH }
  self.bcgUrl = ourTab and UD_URL or COMMUNITY_URL

  local bcgHot = self:_hover(self.bcgButton)
  -- only the Boi's Club mark is dark ink needing the invert; the UD badge is
  -- already bright art
  if not ourTab then love.graphics.setShader(self.invertShader) end
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 1, 1, bcgHot and 0.5 or 0.22)
  love.graphics.draw(bcgImage, bcgX - bcgDW * 0.02, bcgY - bcgDH * 0.02, 0,
    bcgScale * 1.04, bcgScale * 1.04)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(bcgImage, bcgX, bcgY, 0, bcgScale, bcgScale)
  love.graphics.setShader()

  love.graphics.setFont(self.warningFont)
  col(PAL.warning)
  local wrapX = appX + (appW - warningWidth) / 2
  love.graphics.printf(TRUST_WARNING, wrapX, warningY, warningWidth, "center")
  self.linkUrlRect = nil
  do
    local lh = self.warningFont:getHeight()
    local _, lines = self.warningFont:getWrap(TRUST_WARNING, warningWidth)
    for i, line in ipairs(lines) do
      local sidx = line:find(COMMUNITY_URL, 1, true)
      if sidx then
        local before = line:sub(1, sidx - 1)
        local lineW = self.warningFont:getWidth(line)
        local ux = wrapX + (warningWidth - lineW) / 2 + self.warningFont:getWidth(before)
        local uy = warningY + (i - 1) * lh
        local uw = self.warningFont:getWidth(COMMUNITY_URL)
        self.linkUrlRect = { x = ux, y = uy, width = uw, height = lh }
        local linkHot = self:_hover(self.linkUrlRect)
        col(linkHot and PAL.linkHover or PAL.link)
        love.graphics.print(COMMUNITY_URL, ux, uy)
        love.graphics.setLineWidth(1)
        love.graphics.line(ux, uy + lh - 1, ux + uw, uy + lh - 1)
        break
      end
    end
  end

  -- "Created by ..." and the tab's donate chips (see CREDITS), centred on
  -- their own rows below the warning.  Drawn from warningY so they track the
  -- footer wherever the footer landed (pinned or scrolled).
  do
    love.graphics.setFont(self.hintFont)
    local creditY = warningY + warningH + 8 * s
    col(PAL.warning)
    love.graphics.printf("Created by " .. credit.by, appX, creditY, appW, "center")
    self.donateButtons = {}
    self.donateButton = nil
    if #footerLinks > 0 then
      local gap = 10 * s
      local widths, total = {}, 0
      for i, link in ipairs(footerLinks) do
        widths[i] = self.hintFont:getWidth(link.label) + 24 * s
        total = total + widths[i] + (i > 1 and gap or 0)
      end
      local x = appX + (appW - total) / 2
      local y = creditY + creditH + 8 * s
      for i, link in ipairs(footerLinks) do
        local rect = self:_chipButton(x, y, link.label,
          { font = self.hintFont, w = widths[i], h = donateH, kind = "accent" })
        if rect then
          rect.url = link.url
          self.donateButtons[#self.donateButtons + 1] = rect
        end
        x = x + widths[i] + gap
      end
      self.donateButton = self.donateButtons[1]
    end
  end

  -- End of the scrolling column; the logo and the page scrollbar are pinned and
  -- draw outside it.
  if paged then love.graphics.setScissor() end

  if paypalLink then
    local rect=self:_chipButton(appX+padH,paypalY,paypalLink.label,
      {font=paypalFont,w=paypalW,h=paypalH,r=16*s,kind="accent",pinned=true})
    rect.url=paypalLink.url
    self.donateButtons[#self.donateButtons+1]=rect
    self.donateButton=rect
  end

  -- logo, over the split, with a gentle bob + gold glow + sweeping shine
  local bob = math.sin(pulse * (2 * math.pi / 4)) * 6 * s
  local lx, ly = ox + (width - logoDW) / 2, logoY + bob
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 0.85, 0.2, 0.16 + 0.12 * (0.5 + 0.5 * math.sin(pulse * 1.6)))
  love.graphics.draw(logoImage, ox + (width - logoDW * 1.05) / 2, ly - logoDH * 0.025, 0,
    logoScale * 1.05, logoScale * 1.05)
  love.graphics.setBlendMode("alpha")
  local shineW = 0.16
  self.shineShader:send("shinePos", -shineW + ((pulse % 2.8) / 2.8) * (1 + 2 * shineW))
  self.shineShader:send("shineW", shineW)
  love.graphics.setShader(self.shineShader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(logoImage, lx, ly, 0, logoScale, logoScale)
  love.graphics.setShader()

  local tiltX = appX + appW - padH - tiltTargetW
  self.tiltRipsButton = {x=tiltX,y=logoY,width=tiltTargetW,height=tiltBlockH,pinned=true}
  if not self._tiltFilterSet then
    self.tiltRipsLogo:setFilter("linear","linear")
    self.tiltRipsLogo:setMipmapFilter("linear")
    self._tiltFilterSet=true
  end
  local tiltHot = self:_hover(self.tiltRipsButton)
  love.graphics.setColor(1,1,1,tiltHot and 1 or 0.92)
  love.graphics.draw(self.tiltRipsLogo,tiltX,logoY,0,tiltScale,tiltScale)
  love.graphics.push("all")
  love.graphics.translate(tiltX,logoY + tiltDH + 4 * s)
  love.graphics.scale(tiltCodeScale,tiltCodeScale)
  love.graphics.setFont(self.warningFont)
  col(PAL.ink)
  printfB("Use code\nGEN2RECOMP",0,0,tiltTargetW / tiltCodeScale,"center")
  love.graphics.pop()

  -- page scrollbar: the same thin thumb the lists use, against the app edge
  if paged then
    local thumbH = math.max(24 * s, viewportH * (viewportH / naturalH))
    local thumbY = contentTop + (viewportH - thumbH) * (self.pageScroll / maxPage)
    col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", appX + appW - padH * 0.5, thumbY, 3 * s, thumbH,
      1.5 * s, 1.5 * s)
  end

  -- CRT scanlines + vignette, over everything
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.scanlineImage, self.scanlineQuad, 0, 0)
  love.graphics.draw(self.vignetteMesh)
  love.graphics.setColor(1, 1, 1, 1)

  -- drag-to-scroll the save-slot list (polls the pointer; no move/release
  -- events reach the launcher, so click-vs-drag is resolved here)
  self:_updateSlotDrag()

  -- save-slot rename modal (#205), drawn over everything
  if self._rename then
    col(PAL.bgBot, 0.72)
    love.graphics.rectangle("fill", 0, 0, fullW, fullH)
    local dw = math.min(appW - 32 * s, 420 * s)
    local dh = 128 * s
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    neonGlow(dx, dy, dw, dh, rr, PAL.green, 0.4)
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.85, 0.85)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.green, 0.5)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)

    love.graphics.setFont(self.slotNameFont)
    col(PAL.ink)
    love.graphics.print(Strings("Name save slot"), dx + 16 * s, dy + 14 * s)

    -- the field: bordered strip, current text, blinking caret on the pulse
    local fx, fy = dx + 16 * s, dy + 44 * s
    local fw, fh = dw - 32 * s, 30 * s
    col(PAL.bgBot, 0.9)
    love.graphics.rectangle("fill", fx, fy, fw, fh, 8 * s, 8 * s)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.cardBorder, 0.45)
    love.graphics.rectangle("line", fx, fy, fw, fh, 8 * s, 8 * s)
    love.graphics.setFont(self.detailFont)
    col(PAL.heading)
    local shown = ellipsize(self.detailFont, self._rename.text, fw - 20 * s)
    love.graphics.print(shown, fx + 10 * s, fy + (fh - self.detailFont:getHeight()) / 2)
    if (self.pulse * 2 % 1) < 0.5 then
      local cx = fx + 10 * s + self.detailFont:getWidth(shown) + 2 * s
      col(PAL.green)
      love.graphics.rectangle("fill", cx, fy + 6 * s, math.max(1, 1.5 * s),
        fh - 12 * s)
    end

    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    printfB(Strings("Enter to save - Esc to cancel - empty clears"),
      dx + 16 * s, dy + dh - 30 * s, dw - 32 * s, "left")
  end

  -- "Add an index" prompt: the same field as the rename modal, sized for a URL
  -- and with the caret pinned to the tail so a long one stays readable while
  -- it is typed.
  if self._indexPrompt then
    col(PAL.bgBot, 0.72)
    love.graphics.rectangle("fill", 0, 0, fullW, fullH)
    local dw = math.min(appW - 32 * s, 520 * s)
    local dh = 176 * s
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    neonGlow(dx, dy, dw, dh, rr, PAL.modDot, 0.4)
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.9, 0.9)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.modDot, 0.55)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)

    love.graphics.setFont(self.slotNameFont)
    col(PAL.ink)
    love.graphics.print(Strings("Add a mod index"), dx + 16 * s, dy + 14 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    love.graphics.printf(
      Strings("Paste the index URL, or its owner/repo."),
      dx + 16 * s, dy + 40 * s, dw - 32 * s, "left")

    local fx, fy = dx + 16 * s, dy + 66 * s
    local fw, fh = dw - 32 * s, 32 * s
    col(PAL.bgBot, 0.9)
    love.graphics.rectangle("fill", fx, fy, fw, fh, 8 * s, 8 * s)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.cardBorder, 0.45)
    love.graphics.rectangle("line", fx, fy, fw, fh, 8 * s, 8 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.heading)
    -- keep the END of the URL visible: the interesting half is the tail
    local text = self._indexPrompt.text or ""
    local maxW = fw - 20 * s
    local shown = text
    while #shown > 0 and self.hintFont:getWidth(shown) > maxW do
      shown = shown:sub(2)
    end
    love.graphics.print(shown, fx + 10 * s,
      fy + (fh - self.hintFont:getHeight()) / 2)
    if (self.pulse * 2 % 1) < 0.5 then
      col(PAL.modDot)
      love.graphics.rectangle("fill",
        fx + 10 * s + self.hintFont:getWidth(shown) + 2 * s,
        fy + 7 * s, math.max(1, 1.5 * s), fh - 14 * s)
    end

    -- PASTE under the field: a touch screen has no ctrl+V, and an index URL
    -- is not something anyone retypes on a soft keyboard (#578).  This rect
    -- is the one click mousepressed honors while the prompt is up; pinned so
    -- page-scroll banding never eats the tap.
    self._indexPasteRect = self:_chipButton(fx + fw - 84 * s, fy + fh + 8 * s,
      Strings("Paste"), { w = 84 * s, h = 28 * s, kind = "accent" })
    self._indexPasteRect.pinned = true

    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    printfB(Strings("Enter to add - Esc to cancel"),
      dx + 16 * s, dy + dh - 32 * s, dw - 32 * s, "left")
  end

  -- The generation menu hangs off the tab bar and over the panel, so it is
  -- painted after the panel and before the modal dim below: a modal is a
  -- different conversation and closes it (see _drawGenMenu).
  self:_drawGenMenu()

  -- Mod confirm / versions / release-notes / index-details overlays
  if self._modConfirm or self._modVersions or self._modReleaseNotes
      or self._findDetails then
    col(PAL.bgBot, 0.72)
    love.graphics.rectangle("fill", 0, 0, fullW, fullH)
  end
  if self._modConfirm then
    local c = self._modConfirm
    local dw = math.min(appW - 32 * s, 400 * s)
    local lineH = self.hintFont:getHeight() + 4 * s
    local dh = 36 * s + (#c.lines) * lineH + 56 * s
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.92, 0.92)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col((c.kind == "update") and PAL.green or PAL.gold, 0.65)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)
    love.graphics.setFont(self.slotNameFont)
    col(PAL.ink)
    love.graphics.printf(c.title or "Confirm", dx + 16 * s, dy + 14 * s,
      dw - 32 * s, "left")
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    local ty = dy + 42 * s
    for _, line in ipairs(c.lines) do
      love.graphics.printf(line, dx + 16 * s, ty, dw - 32 * s, "left")
      ty = ty + lineH
    end
    local btnH = 34 * s
    local btnW = (dw - 48 * s) / 2
    local by = dy + dh - btnH - 14 * s
    self._modConfirmYes = { x = dx + 16 * s, y = by, width = btnW, height = btnH }
    self._modConfirmNo = { x = dx + dw - 16 * s - btnW, y = by,
      width = btnW, height = btnH }
    local yhot = self:_hover(self._modConfirmYes)
    local nhot = self:_hover(self._modConfirmNo)
    fillGradRounded(self._modConfirmYes.x, by, btnW, btnH, 8 * s,
      PAL.playTop, PAL.playBot, yhot and 1 or 0.85, yhot and 1 or 0.85)
    col(PAL.disabled, nhot and 0.55 or 0.35)
    love.graphics.rectangle("fill", self._modConfirmNo.x, by, btnW, btnH, 8 * s, 8 * s)
    love.graphics.setFont(self.saveBtnFont)
    col(PAL.ink)
    printfB(c.yesLabel or "OK", self._modConfirmYes.x,
      by + (btnH - self.saveBtnFont:getHeight()) / 2, btnW, "center")
    col(PAL.detail)
    printfB("Cancel", self._modConfirmNo.x, by + (btnH - self.saveBtnFont:getHeight()) / 2,
      btnW, "center")
  elseif self._modReleaseNotes then
    local n = self._modReleaseNotes
    local ModUpdate = require("src.mods.ModUpdate")
    local dw = math.min(appW - 32 * s, 480 * s)
    local dh = math.min(height - 48 * s, 360 * s)
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.92, 0.92)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.green, 0.5)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)
    love.graphics.setFont(self.slotNameFont)
    col(PAL.ink)
    love.graphics.printf("v" .. tostring(n.version) .. " notes",
      dx + 16 * s, dy + 12 * s, dw - 32 * s, "left")
    local body = ModUpdate.cleanBody(n.body or "", 0)
    if body == "" then body = "(No release notes.)" end
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    local textTop = dy + 44 * s
    local textH = dh - 44 * s - 52 * s
    love.graphics.setScissor(math.floor(dx + 16 * s), math.floor(textTop),
      math.ceil(dw - 32 * s), math.ceil(textH))
    love.graphics.printf(body, dx + 16 * s, textTop - (n.scroll or 0),
      dw - 32 * s, "left")
    love.graphics.setScissor()
    local closeW = self.hintFont:getWidth("Close") + 28 * s
    local closeH = 30 * s
    self._modReleaseNotesClose = {
      x = dx + (dw - closeW) / 2, y = dy + dh - closeH - 12 * s,
      width = closeW, height = closeH,
    }
    local chot = self:_hover(self._modReleaseNotesClose)
    col(PAL.disabled, chot and 0.55 or 0.35)
    love.graphics.rectangle("fill", self._modReleaseNotesClose.x,
      self._modReleaseNotesClose.y, closeW, closeH, 8 * s, 8 * s)
    col(PAL.detail)
    printfB("Close", self._modReleaseNotesClose.x,
      self._modReleaseNotesClose.y + (closeH - self.hintFont:getHeight()) / 2,
      closeW, "center")
  elseif self._findDetails then
    -- The index's description markdown, stripped by the same cleanBody a
    -- release changelog goes through.  There is no markdown renderer in the
    -- engine and a listing does not warrant one: the point is to read what the
    -- author wrote before installing, not to reproduce their formatting.
    local d = self._findDetails
    local ModUpdate = require("src.mods.ModUpdate")
    local dw = math.min(appW - 32 * s, 520 * s)
    local dh = math.min(height - 48 * s, 420 * s)
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.94, 0.94)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.modDot, 0.5)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)
    love.graphics.setFont(self.slotNameFont)
    col(PAL.ink)
    love.graphics.printf(ellipsize(self.slotNameFont, d.title, dw - 32 * s),
      dx + 16 * s, dy + 12 * s, dw - 32 * s, "left")
    local body = ModUpdate.cleanBody(d.body or "", 0)
    if body == "" then body = "(No description.)" end
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    local textTop = dy + 44 * s
    local textH = dh - 44 * s - 52 * s
    local _, lines = self.hintFont:getWrap(body, dw - 32 * s)
    local bodyH = #lines * self.hintFont:getHeight()
    d.max = math.max(0, bodyH - textH)
    d.scroll = clamp(d.scroll or 0, 0, d.max)
    love.graphics.setScissor(math.floor(dx + 16 * s), math.floor(textTop),
      math.ceil(dw - 32 * s), math.ceil(textH))
    love.graphics.printf(body, dx + 16 * s, textTop - d.scroll,
      dw - 32 * s, "left")
    love.graphics.setScissor()
    local closeW = self.hintFont:getWidth("Close") + 28 * s
    local closeH = 30 * s
    self._findDetailsClose = {
      x = dx + (dw - closeW) / 2, y = dy + dh - closeH - 12 * s,
      width = closeW, height = closeH,
    }
    local chot = self:_hover(self._findDetailsClose)
    col(PAL.disabled, chot and 0.55 or 0.35)
    love.graphics.rectangle("fill", self._findDetailsClose.x,
      self._findDetailsClose.y, closeW, closeH, 8 * s, 8 * s)
    col(PAL.detail)
    printfB("Close", self._findDetailsClose.x,
      self._findDetailsClose.y + (closeH - self.hintFont:getHeight()) / 2,
      closeW, "center")
  elseif self._modVersions then
    local ModUpdate = require("src.mods.ModUpdate")
    local v = self._modVersions
    local dw = math.min(appW - 40 * s, 520 * s)
    local pad = 16 * s
    local headerH = 56 * s
    local rowH = 52 * s
    local footerH = 48 * s
    local listN = math.min(6, math.max(0, #v.releases))
    local listH = math.max(rowH, listN * rowH)
    local dh = headerH + listH + footerH
    dh = math.min(dh, height - 40 * s)
    -- recompute how many rows fit under the clamped dialog height
    local fitN = math.max(1, math.floor((dh - headerH - footerH) / rowH))
    listN = math.min(listN, fitN)
    listH = listN * rowH
    dh = headerH + listH + footerH
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.96, 0.96)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.green, 0.5)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)

    love.graphics.setFont(self.slotNameFont)
    col(PAL.ink)
    love.graphics.printf("Other versions: " .. tostring(v.name),
      dx + pad, dy + 10 * s, dw - pad * 2, "left")
    love.graphics.setFont(self.hintFont)
    local info = self:_modUpdateInfo(v.id)
    local statusTxt = "Installed: v" .. tostring(v.current)
    local statusCol = PAL.detail
    if info and info.status == "available" then
      statusTxt = statusTxt .. "  -  Update v" .. tostring(info.latest)
      statusCol = PAL.playTop
    elseif info and info.status == "current" then
      statusTxt = statusTxt .. "  -  Up to date"
      statusCol = PAL.playTop
    end
    col(statusCol)
    love.graphics.printf(statusTxt, dx + pad, dy + 34 * s, dw - pad * 2, "left")

    self._modVersionRects = {}
    self._modVersionNotesRects = {}
    local listTop = dy + headerH
    local notesW = self.hintFont:getWidth("Read more") + 20 * s
    local installW = self.hintFont:getWidth("Install") + 20 * s
    local btnH = 26 * s
    -- clip the list to the band above the footer so nothing can paint over Close
    love.graphics.setScissor(math.floor(dx + 2 * s), math.floor(listTop),
      math.ceil(dw - 4 * s), math.ceil(listH))
    for i = 1, listN do
      local rel = v.releases[i]
      local ly = listTop + (i - 1) * rowH
      local rect = { x = dx + 12 * s, y = ly + 2 * s, width = dw - 24 * s,
        height = rowH - 6 * s, release = rel }
      col(PAL.bgBot, 0.45)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 8 * s, 8 * s)
      love.graphics.setLineWidth(1)
      col(PAL.cardBorder, 0.35)
      love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 8 * s, 8 * s)

      love.graphics.setFont(self.hintFont)
      local label = "v" .. rel.version
      if rel.version == v.current then label = label .. " (installed)" end
      if rel.prerelease then label = label .. " pre" end
      col(rel.version == v.current and PAL.warning or PAL.ink)
      love.graphics.print(label, rect.x + 12 * s, rect.y + 6 * s)

      -- one-line ellipsized preview only (never wrap changelog into the row)
      local btnStackW = 0
      local hasNotes = type(rel.body) == "string" and rel.body:match("%S")
      local canInstall = rel.version ~= v.current
      if hasNotes then btnStackW = btnStackW + notesW end
      if canInstall then btnStackW = btnStackW + (hasNotes and 8 * s or 0) + installW end
      local previewW = math.max(24 * s, rect.width - 24 * s - btnStackW - 12 * s)
      local preview = ModUpdate.previewLine(rel.body or "", 90)
      if preview ~= "" then
        col(PAL.detail)
        love.graphics.print(
          ellipsize(self.hintFont, preview, previewW),
          rect.x + 12 * s,
          rect.y + 6 * s + self.hintFont:getHeight() + 2 * s)
      end

      local btnY = rect.y + (rect.height - btnH) / 2
      local bx = rect.x + rect.width - 10 * s
      if canInstall then
        bx = bx - installW
        local irect = self:_chipButton(bx, btnY, "Install", {
          w = installW, h = btnH, id = v.id, kind = "accent",
        })
        irect.release = rel
        self._modVersionRects[#self._modVersionRects + 1] = irect
        bx = bx - 8 * s
      end
      if hasNotes then
        bx = bx - notesW
        local nrect = self:_chipButton(bx, btnY, "Read more", {
          w = notesW, h = btnH, id = v.id, kind = "neutral",
        })
        nrect.release = rel
        self._modVersionNotesRects[#self._modVersionNotesRects + 1] = nrect
      end
    end
    love.graphics.setScissor()

    -- opaque footer so list content can never bleed under Close
    local footerY = dy + dh - footerH
    col(PAL.slotBg, 1)
    love.graphics.rectangle("fill", dx + 2 * s, footerY, dw - 4 * s, footerH - 2 * s)
    local closeW = self.hintFont:getWidth("Close") + 32 * s
    local closeH = 32 * s
    self._modVersionsClose = {
      x = dx + (dw - closeW) / 2,
      y = footerY + (footerH - closeH) / 2 - 2 * s,
      width = closeW, height = closeH,
    }
    local chot = self:_hover(self._modVersionsClose)
    col(PAL.disabled, chot and 0.55 or 0.35)
    love.graphics.rectangle("fill", self._modVersionsClose.x,
      self._modVersionsClose.y, closeW, closeH, 8 * s, 8 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    printfB("Close", self._modVersionsClose.x,
      self._modVersionsClose.y + (closeH - self.hintFont:getHeight()) / 2,
      closeW, "center")
  end

  -- pointer cursor over any interactive element (desktop only)
  if self._hoverEnabled and not self._padCursorActive
      and love.mouse.isCursorSupported and love.mouse.isCursorSupported() then
    if self._anyHover then
      if not self.handCursor then
        local ok, cursor = pcall(love.mouse.getSystemCursor, "hand")
        if ok then self.handCursor = cursor end
      end
      if self.handCursor then love.mouse.setCursor(self.handCursor) end
    else
      resetPointerCursor(self)
    end
  end

  -- Gamepad virtual cursor (drawn last so it sits above the CRT overlay).
  if self._padCursorActive then
    local x, y = self._padCursor.x, self._padCursor.y
    local hot = self._anyHover
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setLineWidth(1)
    -- Drop shadow
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.polygon("fill",
      x + 2, y + 2, x + 2, y + 22, x + 8, y + 16, x + 14, y + 26,
      x + 18, y + 24, x + 11, y + 14, x + 20, y + 14)
    -- Pointer body
    if hot then
      love.graphics.setColor(0.25, 0.95, 0.55, 1)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.polygon("fill",
      x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
      x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
    love.graphics.setColor(0.05, 0.07, 0.12, 1)
    love.graphics.polygon("line",
      x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
      x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
    love.graphics.pop()
  end
end

local function inside(r, x, y)
  if not (r and x >= r.x and x <= r.x + r.width and y >= r.y and y <= r.y + r.height) then
    return false
  end
  -- Page-scroll mode: only the header is pinned, so any other rect is a
  -- scrolled one and is live only where the viewport actually shows it.
  if pageBand and not r.pinned and (y < pageBand[1] or y > pageBand[2]) then
    return false
  end
  -- Horizontally scrolled strips (the tab bar) carry their own viewport.
  if r.clipX and (x < r.clipX[1] or x > r.clipX[2]) then
    return false
  end
  -- ...and vertically scrolled ones (the settings drawer) carry theirs. Same
  -- rule as `pageBand` above, but per rect rather than global: the drawer
  -- scrolls independently of the page behind it, so a row scrolled out of its
  -- own viewport must be dead even though the page is not scrolled at all.
  if r.clipY and (y < r.clipY[1] or y > r.clipY[2]) then
    return false
  end
  return true
end

-- A Delete label is armed by one click and commits on a second one on the same
-- target; it disarms on any other press and after this many seconds, because
-- nothing in the launcher can undo a delete (#433).
local DELETE_CONFIRM_SECONDS = 4

local function armedDelete(a, kind, id, version)
  return a ~= nil and a.kind == kind and a.id == id and a.version == version
    and (love.timer.getTime() - a.t) <= DELETE_CONFIRM_SECONDS
end

function RomImporter:touchpressed(id, x, y, dx, dy, pressure)
  -- Android-specific touch handler to avoid mouse emulation issues
  if self._rename then return end -- the rename modal swallows all clicks
  -- Route to the same mousepressed logic but with touch handling
  return self:mousepressed(x, y, 1)
end

function RomImporter:mousepressed(x, y, button)
  if self._rename then return end -- the rename modal swallows all clicks
  -- The add-index prompt swallows clicks too, except its PASTE button: a
  -- touch screen has no ctrl+V, so the button is the only paste path (#578).
  if self._indexPrompt then
    if button == 1 and inside(self._indexPasteRect, x, y) then
      self:_pasteIndexUrl()
    end
    return
  end
  -- Mod confirm / versions / release-notes modals swallow clicks too.
  if self._modConfirm then
    if button ~= 1 then return end
    if inside(self._modConfirmYes, x, y) then
      local c = self._modConfirm
      self._modConfirm = nil
      -- An index install carries its whole entry: the confirm is the only
      -- place the compatibility warnings were shown, so the install must not
      -- be reachable by any other route.
      if c.indexEntry then
        self:_findInstall(c.indexEntry)
      elseif c.kind == "update" then
        self:_confirmModUpdate(c.id, c.release)
      elseif c.kind == "enableAll" then
        self:_setAllMods(true, true)
      elseif c.kind == "experimentalGen" or c.kind == "forceGen" then
        self:_toggleModGeneration(c.id, c.gen, true)
      else
        self:_toggleMod(c.id, true)
      end
    elseif inside(self._modConfirmNo, x, y) then
      self._modConfirm = nil
    end
    return
  end
  if self._modReleaseNotes then
    if button ~= 1 then return end
    if inside(self._modReleaseNotesClose, x, y) then
      self._modReleaseNotes = nil
    end
    return
  end
  if self._findDetails then
    if button ~= 1 then return end
    if inside(self._findDetailsClose, x, y) then
      self._findDetails = nil
    end
    return
  end
  if self._modVersions then
    if button ~= 1 then return end
    if inside(self._modVersionsClose, x, y) then
      self._modVersions = nil
      return
    end
    for _, r in ipairs(self._modVersionNotesRects or {}) do
      if inside(r, x, y) and r.release then
        self._modReleaseNotes = {
          version = r.release.version,
          body = r.release.body or "",
          scroll = 0,
        }
        return
      end
    end
    for _, r in ipairs(self._modVersionRects or {}) do
      if inside(r, x, y) and r.release then
        self:_installModVersion(self._modVersions.id, r.release)
        return
      end
    end
    return
  end
  -- Whether a press can be ARMED and resolved on release, which needs a
  -- pollable pointer: always on desktop, on Android only where love.touch is.
  local armDrag = (not self.android) or self.touchPollable
  -- right-click a save-slot row to rename it (#205); desktop only (touch
  -- has no secondary button)
  if button == 2 then
    if not self.android and self.workState ~= "working" then
      for _, r in ipairs(self.slotRects or {}) do
        if inside(r, x, y) then
          self:_beginRename(self.panelVersion, r.id)
          return
        end
      end
    end
    return
  end
  if button ~= 1 then return end
  -- THE GENERATION MENU EATS THE PRESS WHILE IT IS OPEN, which is the whole
  -- difference between a dropdown and four buttons that happen to overlap the
  -- panel: a click on a row picks that generation, a click anywhere else
  -- closes the menu and goes no further.  Ahead of every other hit test,
  -- because the menu is drawn over them.
  if self._genMenuOpen then
    for _, r in ipairs(self.genMenuRects or {}) do
      if inside(r, x, y) then
        self:_selectGeneration(r.gen)
        return
      end
    end
    self._genMenuOpen = false
    if inside(self.genDropdownRect, x, y) then return end
    return
  end
  if inside(self.genDropdownRect, x, y) then
    self._genMenuOpen = true
    return
  end
  if inside(self.romBatchRect, x, y) then
    self:chooseRomBatch()
    return
  end
  -- Any press that is not the second click on an armed Delete disarms it, so
  -- take the arm off self up front and let the Delete loops below re-arm.
  local armed = self._confirmDelete
  self._confirmDelete = nil
  if inside(self.bcgButton, x, y) then
    love.system.openURL(self.bcgUrl or COMMUNITY_URL)
    return
  end
  if inside(self.tiltRipsButton,x,y) then
    love.system.openURL(TILT_RIPS_URL)
    return
  end
  for _, button in ipairs(self.donateButtons or {}) do
    if inside(button, x, y) then
      love.system.openURL(button.url or DONATE_URL)
      return
    end
  end
  if inside(self.linkUrlRect, x, y) then
    love.system.openURL(COMMUNITY_URL)
    return
  end
  -- Self-updater banner (touch routes here through love.touchpressed too).
  -- Kept ahead of the "working" guard so it stays live during a ROM import.
  if inside(self.updateButton, x, y) then
    local action = self.updateButton.action
    if action == "download" and self.Check then
      pcall(self.Check.download)
    elseif action == "restart" then
      HostShell.restart()
    elseif action == "openurl" and self.Check then
      -- pcall because this is reachable on hosts whose love.system.openURL is
      -- a stub or absent; an unguarded call there takes the launcher down on a
      -- tap.  The banner only offers the button where a page can be opened
      -- (see upAdvice above), so this is the belt to that braces.
      pcall(love.system.openURL, self.Check.releaseUrl())
    end
    return
  end
  -- Tab chips switch panels even mid-import so the player can look around
  -- while a ROM extracts.
  --
  -- The bar is wider than the window once GOLD/SILVER/CRYSTAL and FIND MODS
  -- are in it, and until now the only way to reach the chips past the edge was
  -- the mouse wheel -- which a touch screen does not have.  So where the
  -- pointer can be polled AND the bar actually overflows, a press only ARMS:
  -- _updateSlotDrag pans the bar if the finger moves and switches tabs if it
  -- does not.  Everywhere else the tab still switches on press, unchanged.
  -- The gear first: it is drawn over the tab bar's right end, so it has to be
  -- tested before the bar's own "press beside the chips pans it" fallback.
  if button == 1 and inside(self.settingsRect, x, y) then
    -- A DRAWER OVER THE LAUNCHER, not a screen instead of it.
    --
    -- Settings used to take the whole content area and push the tab you came
    -- from off the screen, which is why it needed `_settingsFrom` to remember
    -- the way back. Nothing in it is worth losing sight of your games for --
    -- most of it is toggles you set once -- and half the rows are ABOUT what
    -- is on the tab behind them (a mod's options, with the mod list behind).
    self.settingsOpen = not self.settingsOpen
    self._settingsPress = nil   -- a press armed on a row the drawer just hid
    if self.settingsOpen then
      self.settingsScroll = 0
      -- Always opens on the first page.  The launcher page is a place you go
      -- to do one thing and come back from; reopening the gear onto it, days
      -- later, would hide every row the gear is actually for.
      self.settingsPage = nil
      self.settingsGen = nil
      self.settingsNotice = nil
      -- rebuilt on each opening, not per frame: reading every installed mod's
      -- schema file is disk work, and at sixty frames a second on a folder of
      -- mods it is disk work for as long as the drawer is open.
      self._settingsRowCache = nil
    end
    return
  end

  -- THE DRAWER SHIELDS WHAT IS UNDER IT. The launcher dispatches by walking a
  -- list of rects, and the panel behind registered its own before this frame
  -- drew the drawer over them -- so without this a press on the drawer's blank
  -- space would fall through to whatever game slot happens to be beneath it
  -- and start an import. Tested AFTER the settings rows so those still answer,
  -- and after the gear so it can always close.
  local shielded = button == 1 and self.settingsOpen
    and inside(self.settingsDrawerRect, x, y)

  -- Settings rows: both arrows and the value between them step the option.
  --
  -- A press only ARMS the row where a drag can be resolved (_updateSlotDrag),
  -- for the same reason the mods list does: the drawer scrolls, a finger that
  -- starts on a row and moves means to scroll it, and stepping VIDEO MODE
  -- because a player swiped through it is a setting changed by accident on a
  -- screen with no undo.  Where a pointer cannot be polled -- Android without
  -- love.touch -- it steps on press exactly as it always did.
  if button == 1 and self.settingsRowRects then
    for _, r in ipairs(self.settingsRowRects) do
      local entry = r.entry
      local hit = nil
      if entry and entry.kind == "action" then
        if inside(r.value, x, y) then hit = 0 end
      else
        if inside(r.left, x, y) then hit = -1
        elseif inside(r.right, x, y) or inside(r.value, x, y) then hit = 1 end
      end
      if hit then
        if armDrag then
          self._settingsPress = { entry = entry, dir = hit, y0 = y,
            scroll0 = self.settingsScroll or 0, moved = false }
        elseif hit == 0 then
          self:_settingsAction(entry)
        else
          self:_stepSetting(entry, hit)
        end
        return
      end
    end
  end
  -- ...and the drawer's own blank space pans it.  Armed before `shielded`
  -- swallows the press, so a swipe that starts between two rows scrolls the
  -- list rather than doing nothing at all -- which, on a phone, is most of
  -- the drawer's area and was the whole of the reported bug.
  if button == 1 and self.settingsOpen and armDrag
     and inside(self.settingsDrawerRect, x, y) then
    self._settingsPress = { y0 = y, scroll0 = self.settingsScroll or 0,
                            moved = false }
    return
  end
  -- and everything else in the drawer's rectangle stops here: see `shielded`.
  if shielded then return end

  local tabOverflows = (self._tabMax or 0) > 0
  for _, t in ipairs(self.tabRects or {}) do
    if inside(t, x, y) then
      if armDrag and tabOverflows then
        self._tabPress = { id = t.id, x0 = x, scroll0 = self.tabScroll or 0 }
      else
        self:_selectTab(t.id)
      end
      return
    end
  end
  -- ...and a press on the bar BESIDE the chips (the gaps, the active chip's
  -- label, the "N of X ready" tail) pans it too, the way a press on empty
  -- background pans the page.
  local band = self._tabBand
  if armDrag and tabOverflows and band
     and x >= band[1] and x <= band[2] and y >= band[3] and y <= band[4] then
    self._tabPress = { x0 = x, scroll0 = self.tabScroll or 0 }
    return
  end
  if self.workState == "working" then return end
  -- Active game panel's controls (only the shown version has live hit rects).
  if inside(self.playButtonRect, x, y) then
    self:play(self.panelVersion); return
  end
  if inside(self.romButtonRect, x, y) then
    local version = self.panelVersion
    if self.ready[version] then self:reimport(version) else self:choose(version) end
    return
  end
  -- SAVE FILES card: Import save / Export save, and the open-folder affordance
  -- shown on the notice line after a successful export.
  if inside(self.saveImportRect, x, y) then
    self:chooseSaveImport(self.panelVersion); return
  end
  if inside(self.saveExportRect, x, y) then
    self:exportSave(self.panelVersion); return
  end
  if inside(self.saveFolderRect, x, y) then
    if self.saveFolderRect.dir then
      love.system.openURL(fileUrl(self.saveFolderRect.dir))
    end
    return
  end
  if inside(self.touchControlsRect, x, y) then
    if self.onEditTouchControls then self.onEditTouchControls() end
    return
  end
  if inside(self.mapEditorRect, x, y) then
    if self.onEditMaps then self.onEditMaps(self.panelVersion) end
    return
  end
  -- SAVE SLOT rows / Edit / Delete.  The two labels are checked first so a tap
  -- on either never also selects the row.  A press only ARMS a row click:
  -- _updateSlotDrag commits it on release when the pointer did not move (a
  -- moved pointer scrolls instead).  Android arms too wherever love.touch can
  -- be polled; without that there is nothing to resolve a release with, so it
  -- keeps selecting on press.  Edit and Delete fire immediately (small fixed
  -- targets, no scroll conflict).
  for _, r in ipairs(self.slotDeleteRects or {}) do
    if inside(r, x, y) then
      if armedDelete(armed, "slot", r.id, self.panelVersion) then
        self:_deleteSlot(self.panelVersion, r.id)
      else
        self._confirmDelete = { kind = "slot", id = r.id,
          version = self.panelVersion, t = love.timer.getTime() }
      end
      return
    end
  end
  for _, r in ipairs(self.slotEditRects or {}) do
    if inside(r, x, y) then
      if self.onEditSave then self.onEditSave(self.panelVersion, r.id) end
      return
    end
  end
  for _, r in ipairs(self.slotRects or {}) do
    if inside(r, x, y) then
      if not armDrag then
        self:_selectSlot(self.panelVersion, r.id)
      else
        self._slotPress = { version = self.panelVersion, id = r.id, y0 = y,
          scroll0 = self.slotScroll[self.panelVersion] or 0,
          pageScroll0 = self.pageScroll or 0, moved = false }
      end
      return
    end
  end
  if inside(self.newSlotRect, x, y) then
    self:_newSlot(self.panelVersion); return
  end
  -- Mods panel: the import button dispatches on press (fixed header, no scroll
  -- conflict); Delete fires immediately; a toggle switch, which lives in the
  -- scrollable list, only ARMS a press so _updateSlotDrag can tell a click from
  -- a drag-scroll (Android, with no pointer polling, toggles on press).
  if inside(self.modImportRect, x, y) then
    self:chooseMod(); return
  end
  -- Enable all / Disable all sit in that same fixed header, so they dispatch on
  -- press like the import button rather than arming a drag (#647).
  if inside(self.modEnableAllRect, x, y) then
    self:_setAllMods(true); return
  end
  if inside(self.modDisableAllRect, x, y) then
    self:_setAllMods(false); return
  end
  -- The two mass importers share that header and dispatch on press for the
  -- same reason: nothing here is a toggle a drag-scroll could be mistaken for.
  if inside(self.modImportManyRect, x, y) then
    self:chooseMods(); return
  end
  if inside(self.modImportFolderRect, x, y) then
    self:chooseModFolder(); return
  end
  for _, r in ipairs(self.modDeleteRects or {}) do
    if inside(r, x, y) then
      if armedDelete(armed, "mod", r.id, nil) then
        self:_deleteMod(r.id)
      else
        self._confirmDelete = { kind = "mod", id = r.id, t = love.timer.getTime() }
      end
      return
    end
  end
  for _, r in ipairs(self.modImportFileRects or {}) do
    if inside(r, x, y) then
      self:chooseModImport(r.id)
      return
    end
  end
  -- STRAIGHT INTO THE IMPORTER FOR THAT CARTRIDGE.
  --
  -- `choose` is the same call the game-selection screen makes, so this is the
  -- ordinary import flow with the version already chosen -- not a second path
  -- to maintain. The alternative was telling the player the name of a game and
  -- leaving them to back out of the mod list and find it, which is the step
  -- that gets skipped and turns into "the map pack crashes".
  for _, r in ipairs(self.modImportGameRects or {}) do
    if inside(r, x, y) then
      if r.version then self:choose(r.version) end
      return
    end
  end
  for _, r in ipairs(self.modSupportRects or {}) do
    if inside(r, x, y) then
      if r.url then love.system.openURL(r.url) end
      return
    end
  end
  for _, r in ipairs(self.modUpdateRects or {}) do
    if inside(r, x, y) then
      self:_modGithubAction(r.id, "update")
      return
    end
  end
  for _, r in ipairs(self.modVersionsRects or {}) do
    if inside(r, x, y) then
      self:_modGithubAction(r.id, "versions")
      return
    end
  end
  -- The generation chips sit in the scrolling list beside the switch, and take
  -- the press the same way the switch does -- ahead of it, because they are
  -- inside its cluster and a chip press must not read as a master toggle.
  for _, r in ipairs(self.modGenRects or {}) do
    if inside(r, x, y) then
      if not armDrag then
        self:_toggleModGeneration(r.id, r.gen)
      else
        self._modPress = { id = r.id, gen = r.gen, y0 = y,
          scroll0 = self.modScroll or 0,
          pageScroll0 = self.pageScroll or 0, moved = false }
      end
      return
    end
  end
  for _, r in ipairs(self.modRects or {}) do
    if inside(r, x, y) then
      if not armDrag then
        self:_toggleMod(r.id)
      else
        self._modPress = { id = r.id, y0 = y, scroll0 = self.modScroll or 0,
          pageScroll0 = self.pageScroll or 0, moved = false }
      end
      return
    end
  end
  -- FIND MODS panel.  Everything here dispatches on press: none of it is a
  -- toggle that a drag-scroll could be mistaken for, and the search field wants
  -- focus the instant it is touched.
  if inside(self.findAddRect, x, y) then
    self:_promptAddIndex(); return
  end
  if inside(self.findRefreshRect, x, y) then
    self._findSearchFocus = false
    self:_disarmTextInput()
    self:_refreshFind(true)
    return
  end
  if inside(self.findSearchRect, x, y) then
    self._findSearchFocus = true
    self:_armTextInput()
    return
  end
  for _, r in ipairs(self.findSourceRemoveRects or {}) do
    if inside(r, x, y) then self:_removeIndex(r.id); return end
  end
  for _, r in ipairs(self.findCatRects or {}) do
    if inside(r, x, y) then
      -- the "All" chip carries the empty id; every other chip toggles itself
      -- off when it is already the filter, so a second tap is the way back
      self.findCategory = (r.id ~= "" and self.findCategory ~= r.id) and r.id or nil
      self.findScroll = 0
      return
    end
  end
  for _, r in ipairs(self.findDetailRects or {}) do
    if inside(r, x, y) and r.entry then self:_findShowDetails(r.entry); return end
  end
  for _, r in ipairs(self.findRepoRects or {}) do
    if inside(r, x, y) and r.entry and r.entry.repo then
      love.system.openURL(r.entry.repo)
      return
    end
  end
  for _, r in ipairs(self.findInstallRects or {}) do
    if inside(r, x, y) and r.entry then self:_findConfirmInstall(r.entry); return end
  end
  -- A press anywhere else on the tab drops the search caret, so the field does
  -- not silently keep eating keystrokes once the player has moved on.
  if self.tab == "find" and self._findSearchFocus then
    self._findSearchFocus = false
    self:_disarmTextInput()
  end
  -- Nothing was hit.  On a scrolling page that is a press on empty background,
  -- which is the natural place to grab and pan from.
  if armDrag and (self._pageMax or 0) > 0 then
    self._pagePress = { y0 = y, scroll0 = self.pageScroll or 0 }
  end
end

function RomImporter:keypressed(key)
  -- Esc closes the generation menu before it reaches anything else, the way
  -- every other dropdown anybody has used does.
  if self._genMenuOpen and key == "escape" then
    self._genMenuOpen = false
    return
  end
  if self._rename then
    if key == "backspace" then
      self._rename.text = utf8Back(self._rename.text)
    elseif key == "return" or key == "kpenter" then
      self:_commitRename()
    elseif key == "escape" then
      self._rename = nil
      self:_disarmTextInput()
    end
    return
  end
  if self._indexPrompt then
    if key == "backspace" then
      self._indexPrompt.text = utf8Back(self._indexPrompt.text)
    elseif key == "return" or key == "kpenter" then
      self:_commitAddIndex()
    elseif key == "escape" then
      self._indexPrompt = nil
      self:_disarmTextInput()
    elseif key == "v" and (love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")) then
      -- an index URL is long and comes from a browser: typing it out by hand
      -- is the difference between adding one and giving up
      self:_pasteIndexUrl()
    end
    return
  end
  if self._modConfirm or self._modVersions or self._modReleaseNotes
      or self._findDetails then
    if key == "escape" then
      if self._findDetails then
        self._findDetails = nil
      elseif self._modReleaseNotes then
        self._modReleaseNotes = nil
      else
        self._modConfirm = nil
        self._modVersions = nil
      end
    end
    return
  end
  if self._findSearchFocus then
    if key == "backspace" then
      self.findQuery = utf8Back(self.findQuery or "")
      self.findScroll = 0
    elseif key == "escape" or key == "return" or key == "kpenter" then
      self._findSearchFocus = false
      self:_disarmTextInput()
    end
    return
  end
  if self.workState == "working" then return end
  if key == "return" or key == "space" or key == "kpenter" then
    -- Enter acts on the visible game tab: Play if its ROM is ready, otherwise
    -- open its picker.  The mods tab has no keyboard action.
    local version = self.tab
    if GameVersion.VERSIONS[version] then
      if self.ready[version] then self:play(version) else self:choose(version) end
    end
  end
end

-- ------- Redesign panel rendering (FirstRun.dc.html) ------------------------
-- These run inside draw(): they read the per-frame pointer through self:_hover
-- and self._s, and set the hit rects mousepressed dispatches (self.tabRects,
-- self.romButtonRect, self.playButtonRect, self.panelVersion).

function RomImporter:_ptIn(r)
  local mx, my = self._mx, self._my
  if not (r and mx >= r.x and mx <= r.x + r.width and my >= r.y and my <= r.y + r.height) then
    return false
  end
  -- Same clip the click path applies, so nothing glows outside the viewport.
  if pageBand and not r.pinned and (my < pageBand[1] or my > pageBand[2]) then
    return false
  end
  -- Horizontally scrolled strips (the tab bar) carry their own viewport.
  if r.clipX and (mx < r.clipX[1] or mx > r.clipX[2]) then
    return false
  end
  return true
end

function RomImporter:_hover(r)
  local hot = self._hoverEnabled and self:_ptIn(r) or false
  if hot then self._anyHover = true end
  return hot
end

-- A glassy white-on-dark button (ROM import + the disabled SAVE FILES pair).
-- Returns its hit rect when live, or nil when disabled (inert).
-- The largest of the button fonts that puts `label` on ONE line inside `w`.
--
-- `_glassyButton` prints through love.graphics.printf, which WRAPS: a label
-- one pixel too wide does not overflow the button, it becomes two lines
-- centred on the first, and the second half hangs out of the bottom. That is
-- not a thing anybody notices until a translation or a suffix -- "(Beta)" --
-- pushes a label over, and then it looks like the button is broken rather
-- than the label being long.
function RomImporter:_fittingFont(label, w)
  for _, font in ipairs({ self.saveBtnFont, self.hintFont }) do
    if font and font:getWidth(label) <= w then return font end
  end
  return self.hintFont or self.saveBtnFont
end

function RomImporter:_glassyButton(x, y, w, h, label, font, enabled)
  local s = self._s
  local r = 10 * s
  love.graphics.setFont(font)
  if enabled == false then
    col(PAL.disabled, 0.25)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(1)
    col(PAL.disabledInk, 0.3)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(PAL.disabledInk)
    printfB(label, x, y + (h - font:getHeight()) / 2, w, "center")
    return nil
  end
  local rect = { x = x, y = y, width = w, height = h }
  local hot = self:_hover(rect)
  fillGradRounded(x, y, w, h, r, PAL.white, PAL.white, hot and 0.24 or 0.16, 0.04)
  love.graphics.setLineWidth(1)
  col(PAL.white, 0.18)
  love.graphics.rectangle("line", x, y, w, h, r, r)
  col(PAL.ink)
  printfB(label, x, y + (h - font:getHeight()) / 2, w, "center")
  return rect
end

-- Compact pill button for row actions (Edit / Delete / Update / Versions).
-- kind: "neutral" (default), "accent" (green), "danger" (red), "dangerArmed"
-- (filled confirm). Returns the hit rect; opts.id is copied onto it.
function RomImporter:_chipButton(x, y, label, opts)
  opts = opts or {}
  local s = self._s
  local font = opts.font or self.hintFont
  local padX = opts.padX or (12 * s)
  local h = opts.h or (font:getHeight() + 10 * s)
  love.graphics.setFont(font)
  local w = opts.w or (font:getWidth(label) + 2 * padX)
  local r = opts.r or math.min(8 * s, h / 2)
  local kind = opts.kind or "neutral"
  local rect = { x = x, y = y, width = w, height = h, id = opts.id, pinned = opts.pinned }
  local hot = self:_hover(rect)

  if kind == "dangerArmed" then
    fillGradRounded(x, y, w, h, r, PAL.chooseTop, PAL.chooseBot,
      hot and 1 or 0.92, hot and 1 or 0.92)
    col(PAL.white)
  elseif kind == "danger" then
    col(PAL.chooseTop, hot and 0.28 or 0.14)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.chooseTop, hot and 0.95 or 0.7)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(hot and PAL.white or PAL.chooseTop)
  elseif kind == "accent" then
    col(PAL.playTop, hot and 0.28 or 0.12)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.playTop, hot and 0.95 or 0.65)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(hot and PAL.white or PAL.playTop)
  else
    fillGradRounded(x, y, w, h, r, PAL.white, PAL.white,
      hot and 0.22 or 0.12, 0.04)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.white, hot and 0.35 or 0.18)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(PAL.ink)
  end
  printfB(label, x, y + (h - font:getHeight()) / 2, w, "center")
  return rect
end

-- The tall green Play button (ready) or a disabled placeholder.  Sets
-- self.playButtonRect.
function RomImporter:_playButton(x, y, w, h, gameName, ready, locked)
  local s, pulse = self._s, self.pulse
  local r = 12 * s
  love.graphics.setFont(self.playFont)
  if ready then
    local rect = { x = x, y = y, width = w, height = h }
    local hot = self:_hover(rect)
    local g = 0.5 + 0.5 * math.sin(pulse * 2 * math.pi / 2.4)
    neonGlow(x, y, w, h, r, PAL.playTop, (0.7 + 0.25 * g) * (hot and 1.6 or 1))
    fillGradRounded(x, y, w, h, r, PAL.playTop, PAL.playBot, 1, 1)
    if hot then
      love.graphics.setBlendMode("add")
      love.graphics.setColor(1, 1, 1, 0.12)
      love.graphics.rectangle("fill", x, y, w, h, r, r)
      love.graphics.setBlendMode("alpha")
    end
    buttonShine(x, y, w, h, r, (pulse % 2.8) / 2.8)
    local label = "Play " .. gameName
    local tw = self.playFont:getWidth(label)
    local tri = self.playFont:getHeight() * 0.55
    local groupW = tri + 12 * s + tw
    local gx = x + (w - groupW) / 2
    local gy = y + h / 2
    col(PAL.playInk)
    love.graphics.polygon("fill", gx, gy - tri / 2, gx, gy + tri / 2, gx + tri * 0.9, gy)
    printB(label, gx + tri + 12 * s, y + (h - self.playFont:getHeight()) / 2)
    self.playButtonRect = rect
  else
    col(PAL.disabled, 0.3)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(1)
    col(PAL.disabledInk, 0.3)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(PAL.disabledInk)
    local label = locked and "Coming soon" or Strings("Import a ROM to play")
    printfB(label, x, y + (h - self.playFont:getHeight()) / 2, w, "center")
    self.playButtonRect = nil
  end
end

-- The game/divider/MODS chip row. Only the active tab shows its label +
-- underline; the rest are dimmed.  Rebuilds self.tabRects (chip squares).

-- ---------------------------------------------------------------------------
-- THE GENERATION FILTER
--
-- Asked for directly: "add in a dropdown at the top right of the launcher in
-- the same row as the game squares for selecting between gen1, gen2, gen3
-- games where when selected itll only show the games in the row for the
-- selected generation".
--
-- The chip row runs nine cartridges now and scrolls to fit them; a player who
-- only ever boots Emerald was paging past six Game Boy chips to reach it.  The
-- filter is a VIEW and nothing else -- it hides chips, it does not unregister
-- a game, and ALL puts every one of them back.
--
-- Persisted (options.launcherGeneration) because a filter that resets every
-- launch is a filter nobody uses twice.
-- ---------------------------------------------------------------------------

-- THE GENERATIONS THE FILTER OFFERS, derived from what is actually registered
-- rather than written out.  It was the literal { 1, 2, 3 }, and adding
-- Platinum would have left a launcher that has a GEN 4 cartridge, counts it,
-- and offers no way to filter to it -- the same shape as registering a version
-- with no chip.  Built once at load because GameVersion.ORDER is fixed by
-- then; a generation with no registered version never appears, so the
-- dropdown cannot offer an empty row either.
RomImporter.GENERATIONS = (function()
  local seen, out = {}, {}
  for _, id in ipairs(GameVersion.ORDER) do
    local g = GameVersion.generation(id)
    if g and not seen[g] then seen[g] = true; out[#out + 1] = g end
  end
  table.sort(out)
  return out
end)()

-- Is `g` a generation the launcher will accept as a filter?  One test, used
-- by the saved-filter restore, the settings lens and the settings stepper --
-- all three of which spelled it `g == 1 or g == 2 or g == 3` in three separate
-- places, so a fourth generation meant finding all three or silently keeping
-- a filter the player could select and never restore.
function RomImporter.isGeneration(g)
  return require("src.core.GenOptions").isGeneration(g) and tonumber(g) or nil
end

function RomImporter.generationLabel(g, short)
  if not g then return Strings("ALL") end
  if short then return Strings("G%d", g) end
  return Strings("GEN %d", g)
end

-- The tab ids on screen right now, in row order, honouring the filter.  One
-- list, so the chips, the gamepad's tab cycling and the "which tab do I land
-- on" rule after a filter change cannot disagree.
-- THE FILTER AS IT ACTUALLY APPLIES, which is not always what is stored.
--
-- Two things switch it off without touching the player's choice:
--
--   * a window too narrow to carry the dropdown (`_genFilterSuppressed`, set
--     by draw) -- a filtered row with no control to unfilter it is a trap;
--   * A MASS ROM IMPORT IN PROGRESS.  A queued run walks from game to game and
--     brings the launcher to each one's tab as it starts, so a filter set to
--     GEN 2 would put the panel for EMERALD on screen with no chip above it.
--     The filter comes back the moment the run ends.
function RomImporter:_activeGenFilter()
  if self._genFilterSuppressed or self._romQueue then return nil end
  return self.genFilter
end

function RomImporter:_visibleTabIds()
  local out = {}
  local filter = self:_activeGenFilter()
  for _, v in ipairs(GameVersion.ORDER) do
    if not filter or GameVersion.generation(v) == filter then
      out[#out + 1] = v
    end
  end
  -- MODS and FIND MODS are not games and are never filtered away: they are the
  -- only route to the mod panels, and a filter that could hide them would be a
  -- filter that locks a player out of their own mod list.
  out[#out + 1] = "mods"
  out[#out + 1] = "find"
  return out
end

function RomImporter:_selectGeneration(g)
  self.genFilter = g or nil
  self._genMenuOpen = false
  local SaveData = require("src.core.SaveData")
  local ok, options = pcall(SaveData.loadOptions)
  if ok and type(options) == "table" then
    -- `false` rather than nil for ALL: mergeOptions keeps unknown keys but a
    -- nil is simply absent, and absent has to keep meaning "never chosen" for
    -- a build that adds a default later.
    options.launcherGeneration = g or false
    pcall(SaveData.saveOptions, options)
  end
  -- The tab you were on may have just been filtered away, and a launcher
  -- showing a panel with no chip to match it is the shape of a bug report.
  if GameVersion.VERSIONS[self.tab]
      and self.genFilter
      and GameVersion.generation(self.tab) ~= self.genFilter then
    local first
    for _, id in ipairs(self:_visibleTabIds()) do
      if GameVersion.VERSIONS[id] then first = id break end
    end
    self:_selectTab(first or "mods")
  end
  -- the row is a different row now; start it at the left rather than wherever
  -- the old one had been scrolled to
  self.tabScroll = 0
  self._tabFollow = true
end

-- The dropdown itself: a chip that says which generation is showing, with a
-- caret.  The MENU is drawn by draw()'s overlay pass -- it has to sit over the
-- panel below it, and this is drawn inside the tab-bar row.
function RomImporter:_drawGenDropdown(x, y, w, h, short)
  local s = self._s
  local label = RomImporter.generationLabel(self.genFilter, short)
  local rect = { x = x, y = y, width = w, height = h, pinned = true }
  local hot = self:_hover(rect)
  local open = self._genMenuOpen and true or false
  fillGradRounded(x, y, w, h, 8 * s, PAL.slotBg, PAL.slotBg,
                  (hot or open) and 0.95 or 0.75,
                  (hot or open) and 0.95 or 0.75)
  love.graphics.setLineWidth(math.max(1, 1.2 * s))
  col(open and PAL.link or PAL.cardBorder, open and 0.9 or 0.55)
  love.graphics.rectangle("line", x, y, w, h, 8 * s, 8 * s)
  love.graphics.setFont(self.hintFont)
  col(open and PAL.link or PAL.ink)
  love.graphics.print(label, x + 10 * s,
    y + (h - self.hintFont:getHeight()) / 2)
  -- caret, pointing the way the menu will go
  local cxx = x + w - 14 * s
  local cyy = y + h / 2 + (open and 2 * s or -1 * s)
  local d = 4 * s
  col(open and PAL.link or PAL.warning)
  if open then
    love.graphics.polygon("fill", cxx - d, cyy, cxx + d, cyy, cxx, cyy - d * 1.2)
  else
    love.graphics.polygon("fill", cxx - d, cyy, cxx + d, cyy, cxx, cyy + d * 1.2)
  end
  self.genDropdownRect = rect
  return rect
end

-- The open menu, drawn last so nothing can be painted over it and clicked
-- through.  Rows are ALL / GEN 1 / GEN 2 / GEN 3 with the count of games each
-- one holds, which is what makes an empty generation obvious rather than
-- looking like a broken filter.
function RomImporter:_drawGenMenu()
  self.genMenuRects = nil
  -- A modal owns the screen; a dropdown left hanging behind one would be
  -- drawn under the dim and still take clicks.
  if self._modConfirm or self._modVersions or self._modReleaseNotes
      or self._findDetails or self._rename or self._indexPrompt then
    self._genMenuOpen = false
  end
  if not (self._genMenuOpen and self.genDropdownRect) then return end
  local s = self._s
  local r = self.genDropdownRect
  local rows = { false }
  for _, g in ipairs(RomImporter.GENERATIONS) do rows[#rows + 1] = g end
  love.graphics.setFont(self.hintFont)
  local rowH = self.hintFont:getHeight() + 14 * s
  local w = math.max(r.width, 120 * s)
  local h = #rows * rowH + 8 * s
  local x = r.x + r.width - w
  local y = r.y + r.height + 6 * s
  fillGradRounded(x, y, w, h, 10 * s, PAL.slotBg, PAL.slotBg, 0.98, 0.98)
  love.graphics.setLineWidth(math.max(1, 1.2 * s))
  col(PAL.cardBorder, 0.7)
  love.graphics.rectangle("line", x, y, w, h, 10 * s, 10 * s)
  local rects = {}
  local ry = y + 4 * s
  for _, g in ipairs(rows) do
    local value = g or nil
    local rr = { x = x + 4 * s, y = ry, width = w - 8 * s, height = rowH,
                 gen = value, pinned = true }
    local hot = self:_hover(rr)
    local active = (self.genFilter or false) == (value or false)
    if hot or active then
      col(active and PAL.link or PAL.cardBorder, active and 0.18 or 0.25)
      love.graphics.rectangle("fill", rr.x, rr.y, rr.width, rr.height,
        6 * s, 6 * s)
    end
    local ready, total = 0, 0
    if value then
      for _, v in ipairs(GameVersion.ORDER) do
        if GameVersion.generation(v) == value then
          total = total + 1
          if self.ready[v] then ready = ready + 1 end
        end
      end
    else
      total = #GameVersion.ORDER
      for _, v in ipairs(GameVersion.ORDER) do
        if self.ready[v] then ready = ready + 1 end
      end
    end
    col(active and PAL.link or PAL.ink)
    love.graphics.print(RomImporter.generationLabel(value), rr.x + 8 * s,
      ry + (rowH - self.hintFont:getHeight()) / 2)
    col(PAL.warning, 0.8)
    local count = ("%d/%d"):format(ready, total)
    love.graphics.print(count, rr.x + rr.width - 8 * s
      - self.hintFont:getWidth(count),
      ry + (rowH - self.hintFont:getHeight()) / 2)
    rects[#rects + 1] = rr
    ry = ry + rowH
  end
  self.genMenuRects = rects
end

function RomImporter:_drawTabBar(x, y, w, h, chip)
  local s, pulse = self._s, self.pulse
  local tabs = {
    { id = "red",    letter = "R", top = PAL.chipRedTop,  bot = PAL.chipRedBot,
      under = PAL.red,    label = Strings("RED"),    ink = PAL.white },
    { id = "blue",   letter = "B", top = PAL.chipBlueTop, bot = PAL.chipBlueBot,
      under = PAL.blue,   label = Strings("BLUE"),   ink = PAL.white },
    { id = "yellow", letter = "Y", top = PAL.chipYellowTop, bot = PAL.chipYellowBot,
      under = PAL.gold,   label = Strings("YELLOW"), ink = PAL.chipInkGold },
    { id = "gold",   letter = "G", top = PAL.chipGoldTop, bot = PAL.chipGoldBot,
      under = PAL.gold,   label = Strings("GOLD"),   ink = PAL.chipInkGold },
    { id = "silver", letter = "S", top = PAL.chipSilverTop, bot = PAL.chipSilverBot,
      under = PAL.detail, label = Strings("SILVER"), ink = PAL.chipInkSilver },
    { id = "crystal", letter = "C", top = PAL.chipCrystalTop, bot = PAL.chipCrystalBot,
      under = PAL.chipCrystalTop, label = Strings("CRYSTAL"),
      ink = PAL.chipInkSilver },
    { id = "firered", letter = "FR", top = PAL.chipFireRedTop,
      bot = PAL.chipFireRedBot, under = PAL.chipFireRedTop,
      label = Strings("FIRERED"), ink = PAL.chipInkSilver },
    -- FireRed and Emerald sit after Crystal because they are cartridges, and
    -- the row runs cartridges in generation order and then the hacks -- the same rule
    -- GameVersion.ORDER follows, and the one polished_crystal_registration_test
    -- asserts.
    --
    -- It was registered without this chip, and the comment below said exactly
    -- what that costs: the game was hashed, recognised by setup, counted in
    -- "N of X ready" -- and had no way in.  The tab row showed eight tabs
    -- beside a counter that said nine.
    { id = "emerald", letter = "E", top = PAL.chipEmeraldTop,
      bot = PAL.chipEmeraldBot, under = PAL.chipEmeraldTop,
      label = Strings("EMERALD"), ink = PAL.chipInkSilver },
    -- Platinum closes the cartridge run, because it is a cartridge and the
    -- row is cartridges in generation order before the hacks -- the same rule
    -- GameVersion.ORDER follows.  "PL": "P" is Prism's and "PC" is Polished
    -- Crystal's, and the 44px chip has room for two letters.
    --
    -- It is withheld (importable = false) and that is the point of giving it
    -- a chip anyway: a player who owns the cartridge can reach the panel and
    -- read what is and is not ready, instead of finding a counter that says
    -- eleven above a row of ten.
    { id = "platinum", letter = "PL", top = PAL.chipPlatinumTop,
      bot = PAL.chipPlatinumBot, under = PAL.chipPlatinumTop,
      label = Strings("PLATINUM"), ink = PAL.chipInkSilver },
    -- Prism sits after Crystal: it is a Crystal romhack, so it belongs at the
    -- end of the Gen 2 run rather than beside the official carts.
    { id = "prism", letter = "P", top = PAL.chipPrismTop, bot = PAL.chipPrismBot,
      under = PAL.chipPrismTop, label = Strings("PRISM"),
      ink = PAL.chipInkSilver },
    -- ...and Polished Crystal after Prism, for the same reason. Two letters
    -- rather than one: "P" is Prism's, and the 44px chip has room.
    --
    -- THIS CHIP IS THE ONLY WAY IN. Registering a version in GameVersion.ORDER
    -- does not create a tab, and the tab row is the sole navigation into a
    -- version's panel -- so without this the game is registered, hashed,
    -- recognised by setup and completely unreachable. That is exactly what
    -- happened to Prism. The bar scrolls, so the row never runs out of space.
    { id = "polishedcrystal", letter = "PC",
      top = PAL.chipPolishedTop, bot = PAL.chipPolishedBot,
      under = PAL.chipPolishedTop, label = Strings("POLISHED"),
      ink = PAL.chipInkSilver },
    { id = "mods",   mods = true,  top = PAL.chipModTop,  bot = PAL.chipModBot,
      under = PAL.modDot, label = Strings("MODS") },
    -- Browsing a community index sits beside the installed list rather than
    -- inside it: one answers "what do I have", the other "what is out there",
    -- and the second is empty until the player adds an index of their own.
    { id = "find",   find = true,  top = PAL.chipModTop,  bot = PAL.chipModBot,
      under = PAL.modDot, label = Strings("FIND MODS") },
  }
  -- THE GENERATION FILTER, applied to the row and nowhere else.  MODS and
  -- FIND MODS stay whatever is selected -- see _visibleTabIds for why -- and
  -- ALL is simply no filter at all, so the row is byte-for-byte what it was
  -- before this existed.
  local rowFilter = self:_activeGenFilter()
  if rowFilter then
    local kept = {}
    for _, t in ipairs(tabs) do
      if t.mods or t.find or GameVersion.generation(t.id) == rowFilter then
        kept[#kept + 1] = t
      end
    end
    tabs = kept
  end

  local gap = 10 * s
  local r = 12 * s
  local chipY = y + (h - chip) / 2 - 2 * s
  local underY = y + h - 3 * s

  -- The bar grew past the window once GOLD/SILVER joined R/B/Y and MODS
  -- picked up FIND MODS, and the rightmost chips simply fell off the edge.
  -- Scroll it horizontally instead: clip to the bar, slide the whole run by
  -- tabScroll, and keep the active chip in view.  The chip rects are stored
  -- in absolute coordinates AFTER the slide, so the hit tests need no idea
  -- any of this is happening -- but they do have to be clipped to the band,
  -- or a chip scrolled off the edge stays clickable.
  self._tabBand = { x, x + w, y, y + h }
  local contentW = self._tabContentW or 0
  local maxTab = math.max(0, contentW - w)
  self.tabScroll = math.max(0, math.min(self.tabScroll or 0, maxTab))
  self._tabMax = maxTab
  local activeRect = self._tabActiveRect
  -- Bring the selected chip into view ONCE, when the selection changes -- not
  -- every frame.  Every frame meant the bar snapped straight back the moment
  -- the player scrolled the active chip off the edge, which made the wheel
  -- useless there and would have made a drag impossible.
  --
  -- Armed by noticing self.tab changed rather than by the code that changed
  -- it: a tab switch also arrives from a dropped ROM, an installed mod, an
  -- imported save and the gamepad, and each of those would otherwise have to
  -- remember.  The rect is measured during the draw, so the flag can outlive a
  -- frame waiting for one.
  if self._tabFollowFor ~= self.tab then
    self._tabFollowFor = self.tab
    self._tabFollow = true
  end
  if activeRect and maxTab > 0 and self._tabFollow then
    if activeRect[1] - self.tabScroll < 0 then
      self.tabScroll = activeRect[1]
    elseif activeRect[2] - self.tabScroll > w then
      self.tabScroll = activeRect[2] - w
    end
    self.tabScroll = math.max(0, math.min(self.tabScroll, maxTab))
    self._tabFollow = nil
  end

  love.graphics.setScissor(math.floor(x), math.floor(y),
    math.ceil(w), math.ceil(h))
  local originX = x - self.tabScroll
  local cursorX = originX
  for _, t in ipairs(tabs) do
    if t.mods then
      -- divider between the game chips and MODS
      col(PAL.cardBorder, 0.25)
      love.graphics.rectangle("fill", cursorX, y + (h - 34 * s) / 2,
        math.max(1, 1 * s), 34 * s)
      cursorX = cursorX + gap + 6 * s
    end
    local active = self.tab == t.id
    -- chip body
    fillGradRounded(cursorX, chipY, chip, chip, r, t.top, t.bot, 1, 1)
    if t.mods then
      local d = 5 * s
      local gd = 3 * s
      local grid = 3 * d + 2 * gd
      local gx = cursorX + (chip - grid) / 2
      local gy = chipY + (chip - grid) / 2
      col(PAL.modDot)
      for row = 0, 2 do
        for c2 = 0, 2 do
          love.graphics.rectangle("fill", gx + c2 * (d + gd), gy + row * (d + gd), d, d)
        end
      end
    elseif t.find then
      -- magnifier: a ring plus a handle running down-right out of it
      local cr = chip * 0.20
      local ccx = cursorX + chip / 2 - cr * 0.35
      local ccy = chipY + chip / 2 - cr * 0.35
      col(PAL.modDot)
      love.graphics.setLineWidth(math.max(1.5, 2 * s))
      love.graphics.circle("line", ccx, ccy, cr)
      local d = cr * 0.72
      love.graphics.line(ccx + d, ccy + d, ccx + d + cr * 0.9, ccy + d + cr * 0.9)
      love.graphics.setLineWidth(1)
    else
      love.graphics.setFont(self.chipFont)
      col(t.ink)
      printfB(t.letter, cursorX, chipY + (chip - self.chipFont:getHeight()) / 2, chip, "center")
    end
    if not active then
      col(PAL.bgBot, 0.62)
      love.graphics.rectangle("fill", cursorX, chipY, chip, chip, r, r)
    end
    -- pinned: the bar sits above the page viewport, so it stays live there --
    -- but it has its own horizontal viewport now, and a chip scrolled out of
    -- it must stop taking clicks.
    if cursorX + chip > x and cursorX < x + w then
      self.tabRects[#self.tabRects + 1] =
        { x = cursorX, y = chipY, width = chip, height = chip, id = t.id,
          pinned = true, clipX = { x, x + w } }
    end
    local segEnd = cursorX + chip
    if active then
      love.graphics.setFont(self.tabLabelFont)
      col(PAL.ink)
      local labelX = cursorX + chip + gap
      local lw = printSpaced(self.tabLabelFont, t.label, labelX,
        y + (h - self.tabLabelFont:getHeight()) / 2, 2 * s)
      segEnd = labelX + lw
      neonGlow(cursorX, underY, segEnd - cursorX, 3 * s, 2 * s, t.under, 0.45)
      col(t.under)
      love.graphics.rectangle("fill", cursorX, underY, segEnd - cursorX, 3 * s)
    end
    if active then
      self._tabActiveRect = { cursorX - originX, segEnd - originX }
    end
    cursorX = segEnd + gap
  end
  self._tabContentW = cursorX - gap - originX
  love.graphics.setScissor()
  -- "N of X ready" from GameVersion.ORDER -- or from the generation on show,
  -- because a count of nine beside a row of one reads as a broken row.
  local shownGen = rowFilter
  local ready, total = 0, 0
  for _, v in ipairs(GameVersion.ORDER) do
    if not shownGen or GameVersion.generation(v) == shownGen then
      total = total + 1
      if self.ready[v] then ready = ready + 1 end
    end
  end
  love.graphics.setFont(self.readyFont)
  -- was hardcoded to 3 while ORDER already held five versions
  local label = Strings("%d of %d ready", ready, total)
  local lw = self.readyFont:getWidth(label)
  if x + w - lw > cursorX + 8 * s then
    col(PAL.labelGray)
    love.graphics.print(label, x + w - lw, y + h - self.readyFont:getHeight() - 6 * s)
  end
  love.graphics.setLineWidth(1)
  col(PAL.cardBorder, 0.22)
  love.graphics.line(x, y + h, x + w, y + h)
end

-- One version's game panel: header (name + status pill), then a responsive
-- two-column grid (left: ROM + SAVE FILES cards + Play; right: SAVE SLOT).
-- `paged`: the whole page is scrolling (see draw()), so nothing stretches to
-- fill `h` -- Play sits right under the SAVE FILES card instead of being pinned
-- to the column bottom, and the slot card takes its natural height.  Returns
-- the panel's natural height either way, which is what draw() measures the page
-- against on the next frame.
-- WHY EACH WITHHELD CARTRIDGE IS WITHHELD, in the player's terms and one
-- sentence each.  This is a table rather than a literal because the literal
-- it replaced said "Prism imports its data, but its scripts still misbehave"
-- for EVERY withheld game -- which was true while Prism was the only one, and
-- became a panel explaining Prism to somebody looking at Platinum the moment
-- a second game arrived.  A comment right above it said "ONE SENTENCE PER
-- GAME"; the code had one sentence, full stop.
--
-- Hung off the module table rather than declared as a file-local: this file
-- is half a megabyte and Lua 5.1 allows 200 locals per chunk, so a new
-- file-scope local here is a real risk of taking the whole launcher out.
RomImporter.WITHHELD_REASON = {
  prism = "Prism imports its data, but its scripts still misbehave; "
    .. "it is not ready to play.",
  platinum = "Platinum's cartridge is recognised and its filesystem reads, "
    .. "but Gen 4 extraction is still being built. The DS keeps its data in "
    .. "archives inside a filesystem rather than in tables at fixed "
    .. "addresses, so none of the earlier extractors carry over.",
}

function RomImporter:_drawGamePanel(version, x, y, w, h, paged)
  local s, pulse = self._s, self.pulse
  self.panelVersion = version
  -- Defensive: only lock when the version is absent from GameVersion (never
  -- solely because id == "yellow").
  local info = GameVersion.info(version)
  -- "locked" covers two cases: a version the build does not know at all, and
  -- one that is registered but whose extraction data is not ready (Prism).
  -- POKEPORT_UNLOCK (see blockedImportReason) has to reach the panel too, or
  -- the import it permits is one the UI never offers: the button stays
  -- disabled and the pill still reads COMING SOON.
  local withheld = info ~= nil and info.importable == false
                   and not unlockedByEnv(version)
  local locked = info == nil or withheld
  local partial = withheld
  -- A VERSION THAT IMPORTS BUT HAS NOT BEEN PROVEN.
  --
  -- `importable = false` refuses the import; this refuses the impression that
  -- the import is proven. Polished Crystal reads every table off the
  -- cartridge and has ground on all 605 of its maps, but nobody has walked
  -- around in the result, and a player who meets a failure with no warning
  -- concludes their dump is bad or the build is broken. Both wrong, and both
  -- send them somewhere unhelpful.
  local experimental = (not locked) and info ~= nil
                       and info.experimental == true
  -- WHICH WORD, because unproven has stages.  BETA is the default and is what
  -- every version that has carried this flag has said; a version earlier than
  -- that says so in its own registry entry rather than being described here,
  -- so the launcher never has to know which game is at which stage.
  local stage = experimental
                and tostring(info.experimentalLabel or "BETA"):upper() or nil
  local gameName = info and (info.launcherName or info.displayName)
                   or tostring(version)
  local ready = (not locked) and self.ready[version] or false

  -- header: name + status pill
  love.graphics.setFont(self.gameNameFont)
  col(PAL.ink)
  printB(gameName, x, y)
  local nameW = self.gameNameFont:getWidth(gameName)
  local pill
  -- BETA outranks GOOD TO GO: a finished import does not stop the version
  -- being unproven, and the pill is the one thing read at a glance.
  if experimental then pill = { text = stage, c = PAL.gold }
  elseif ready then pill = { text = "GOOD TO GO", c = PAL.green }
  elseif locked then pill = { text = "COMING SOON", c = PAL.disabledInk }
  else pill = { text = "ROM REQUIRED", c = PAL.gold } end
  love.graphics.setFont(self.pillFont)
  local pw = self.pillFont:getWidth(pill.text) + 24 * s
  local ph = self.pillFont:getHeight() + 8 * s
  local px = x + nameW + 14 * s
  local py = y + (self.gameNameFont:getHeight() - ph) / 2
  col(pill.c, 0.1)
  love.graphics.rectangle("fill", px, py, pw, ph, ph / 2, ph / 2)
  love.graphics.setLineWidth(1)
  col(pill.c, 0.55)
  love.graphics.rectangle("line", px, py, pw, ph, ph / 2, ph / 2)
  col(pill.c)
  printfB(pill.text, px, py + (ph - self.pillFont:getHeight()) / 2, pw, "center")

  local headerH = math.max(self.gameNameFont:getHeight(), ph)
  local bodyTop = y + headerH + 14 * s
  local bodyH = math.max(0, (y + h) - bodyTop)

  -- responsive grid: two columns when they comfortably fit, else stacked
  local colGap = 18 * s
  local twoCol = w >= (300 * s * 2 + colGap)
  local colW = twoCol and (w - colGap) / 2 or w
  local leftX = x
  local rightX = twoCol and (x + colW + colGap) or x

  -- ROM card contents by state (rehomes the existing import flow)
  -- The hint names every extension the picker accepts.  Telling a player to
  -- drop a ".gb/.gbc" while the game also takes a .gba is a small lie that
  -- costs someone an hour.
  local dropHint = self.android and "Copy the .gb/.gbc/.gba/.nds via USB."
    or Strings("Or drop the .gb/.gbc/.gba/.nds file here.")
  local accent = PAL.blue
  if version == "red" then accent = PAL.red
  elseif version == "yellow" then accent = PAL.gold
  elseif version == "gold" then accent = PAL.chipGoldTop
  elseif version == "silver" then accent = PAL.chipSilverTop
  elseif version == "crystal" then accent = PAL.chipCrystalTop
  elseif version == "firered" then accent = PAL.chipFireRedTop
  elseif version == "emerald" then accent = PAL.chipEmeraldTop
  elseif version == "platinum" then accent = PAL.chipPlatinumTop
  elseif version == "prism" then accent = PAL.chipPrismTop
  -- Without a branch here the panel silently falls back to PAL.blue, which
  -- reads as a rendering bug rather than a missing case.
  elseif version == "polishedcrystal" then accent = PAL.chipPolishedTop
  end
  local romState, romDetail, romBtnLabel, romBtnEnabled, romProgress
  if locked then
    if partial then
      -- Say what is actually true, and keep it accurate as the work moves.
      -- The ROM is recognised and its data extracts correctly; what is not
      -- ready is the scripting.  "Support is on the way" would imply the
      -- cartridge is the problem and send the player hunting a different dump.
      romState = "Recognised, not playable yet"
      -- ONE SENTENCE PER GAME: a withheld cartridge is withheld for its own
      -- reason, and a shared line would be whichever game got here first.
      romDetail = RomImporter.WITHHELD_REASON[version]
        or ((info.launcherName or info.displayName or version)
            .. " is recognised, but its import is not ready yet.")
    else
      romState, romDetail = "Not supported yet", "Support for this game is on the way."
    end
    romBtnLabel, romBtnEnabled = "Import unavailable", false
  else
    local importing = self.importing == version
    local erroring = self.workState == "error" and self.errorVersion == version
    local notice = self.notice and self.notice.version == version and self.notice
    if importing and (self.workState == "working" or self.workState == "complete") then
      romState = self.status or "Importing"
      romDetail = self.detail or ""
      romProgress = self.progress or 0
    elseif ready then
      romState = self.romName[version] or Strings("ROM imported")
      -- "Verified." is a claim about the ROM, and it stays true. What is not
      -- verified on a beta version is the WORLD the import built, so say that
      -- rather than letting one word cover both.
      romDetail = experimental
        and ("ROM verified. The world it builds is " .. stage:lower()
             .. " -- expect rough edges, and report what breaks.")
        or "Verified."
      romBtnLabel, romBtnEnabled = "Re-import ROM", true
    elseif erroring then
      romState = "Import failed"
      romDetail = self.detail or Strings("That ROM could not be imported.")
      romBtnLabel, romBtnEnabled = "Import ROM", true
    elseif notice then
      romState = "No ROM imported"
      romDetail = trim((notice.status or "") .. " " .. (notice.detail or ""))
      romBtnLabel, romBtnEnabled = "Import ROM", true
    elseif self.returning[version] then
      romState = "Update required"
      romDetail = "This build needs a few more things from your "
        .. info.label .. " ROM. Re-import to continue."
      romBtnLabel, romBtnEnabled = "Re-import ROM", true
    else
      romState = "No ROM imported"
      romDetail = (experimental
        and (stage:sub(1, 1) .. stage:sub(2):lower()
             .. ": this cartridge's tables all read and the world they build "
             .. "loads, but it is still being played through and fixed. The "
             .. "ROM is verified before any files are created. ")
        or "The ROM is verified before any files are created. ") .. dropHint
      romBtnLabel, romBtnEnabled = "Import ROM", true
    end
  end

  -- card metrics
  local pad = 16 * s
  local innerW = colW - 2 * pad
  local labelH = self.labelFont:getHeight()
  love.graphics.setFont(self.stateFont)
  local _, stl = self.stateFont:getWrap(romState, innerW)
  local stateH = math.max(1, #stl) * self.stateFont:getHeight()
  love.graphics.setFont(self.hintFont)
  local _, dtl = self.hintFont:getWrap(romDetail, innerW)
  local detailH = math.max(1, #dtl) * self.hintFont:getHeight()
  local btnH = math.max(40 * s, self.saveBtnFont:getHeight() + 22 * s)
  local romCardH = pad + labelH + 10 * s + stateH + 5 * s + detailH + 14 * s + btnH + pad

  -- SAVE FILES card: Import save is live once the ROM is imported (playable);
  -- Export save is live only when the active slot actually holds a save.  The
  -- hint line doubles as the last import/export outcome (green ok / red error).
  local sfImportEnabled, sfExportEnabled = false, false
  if not locked then
    self:_ensureSlots(version)
    sfImportEnabled = ready and true or false
    local activeId = self.activeSlot[version]
    for _, sl in ipairs(self.slots[version] or {}) do
      if sl.id == activeId and sl.exists then sfExportEnabled = true; break end
    end
  end
  local sfNotice = (not locked) and self.saveNotice[version] or nil
  local sfHintText, sfHintCol
  if sfNotice then
    sfHintText, sfHintCol = sfNotice.text, (sfNotice.ok and PAL.green or PAL.red)
  elseif locked then
    sfHintText, sfHintCol = "Not available yet.", PAL.warning
  elseif self.android then
    sfHintText, sfHintCol =
      "Import or export a .sav with the system file picker.", PAL.warning
  else
    sfHintText, sfHintCol =
      "Import a .sav to a new slot, or export the active slot.", PAL.warning
  end

  local sfBtnH = math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s)
  love.graphics.setFont(self.hintFont)
  local _, sfHl = self.hintFont:getWrap(sfHintText, innerW)
  local sfHintH = math.max(1, #sfHl) * self.hintFont:getHeight()
  local sfFolderH = (sfNotice and sfNotice.dir) and (self.hintFont:getHeight() + 4 * s) or 0
  local saveFilesH = pad + labelH + 10 * s + sfBtnH + 6 * s + sfHintH + sfFolderH + pad
  local playH = math.max(50 * s, self.playFont:getHeight() + 30 * s)
  -- Touch Controls editor entry (layout + permanent disable).  Drawn whenever
  -- the host supplied onEditTouchControls; height reserved only then so a
  -- scripted/headless importer without the callback stays compact.
  -- Map Editor shares the Touch Controls row when both are up, so the pair
  -- costs no more height than the one did. Only offered once the game is
  -- imported: with no cache to mount, the editor would open on an empty map
  -- list, which looks like a broken editor rather than a missing import.
  -- DRAWN WHENEVER THE HOST CAN OPEN IT, and disabled with a reason when the
  -- game is not ready for it -- the same rule EXPORT and IMPORT already follow
  -- inside the editor, and for the same reason: a control that VANISHES when
  -- its precondition is unmet is indistinguishable from one that does not
  -- exist. "I'm not seeing it in the launcher like I am for other tabs" is
  -- exactly that failure being reported, and it cannot be answered by looking
  -- at the button, because there is no button to look at.
  --
  -- The precondition itself has not moved: with no imported cache the editor
  -- opens on an empty map list, which looks broken rather than absent.
  local canMapEdit = (ready and not locked) and true or false
  local showMapBtn = self.onEditMaps and true or false
  -- The row is reserved when EITHER button wants it. Keying the height off
  -- onEditTouchControls alone left touchY equal to playY on a build without
  -- it, which drew the map button straight over Play.
  local touchBtnH = (self.onEditTouchControls or showMapBtn)
    and math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s) or 0
  -- The one-line reason under a disabled Map Editor button needs room of its
  -- own, or it prints through Play -- which is how the Touch Controls row got
  -- its own note about reserving height in the first place.
  local mapHintH = (showMapBtn and not canMapEdit and touchBtnH > 0)
    and (self.hintFont:getHeight() + 4 * s) or 0
  local touchGap = touchBtnH > 0 and (12 * s) or 0

  -- vertical placement of the left column
  local romY = bodyTop
  local saveFilesY = romY + romCardH + 12 * s
  local leftNaturalH = romCardH + 12 * s + saveFilesH + touchGap + touchBtnH
    + mapHintH + 12 * s + playH
  local playY, touchY
  if twoCol and not paged then
    -- Play pinned to the column bottom; Touch Controls sits just above it
    playY = bodyTop + bodyH - playH
    touchY = playY - touchGap - touchBtnH - mapHintH
  else
    touchY = saveFilesY + saveFilesH + touchGap
    playY = touchY + touchBtnH + mapHintH + 12 * s
  end

  -- ROM card
  roundedCard(leftX, romY, colW, romCardH, 16 * s)
  local ix, iy = leftX + pad, romY + pad
  love.graphics.setFont(self.labelFont)
  col(PAL.labelGray)
  printSpaced(self.labelFont, "ROM", ix, iy, 2 * s)
  iy = iy + labelH + 10 * s
  love.graphics.setFont(self.stateFont)
  col(PAL.ink)
  printfB(romState, ix, iy, innerW, "left")
  iy = iy + stateH + 5 * s
  love.graphics.setFont(self.hintFont)
  col(PAL.detail)
  love.graphics.printf(romDetail, ix, iy, innerW, "left")
  iy = iy + detailH + 14 * s
  if romProgress ~= nil then
    local barH = math.max(8, 10 * s)
    local track = iy + (btnH - barH) / 2
    col(PAL.bgBot, 0.85)
    love.graphics.rectangle("fill", ix, track, innerW, barH, barH / 2, barH / 2)
    local pw2 = innerW * clamp(romProgress, 0, 1)
    if pw2 > barH then
      neonGlow(ix, track, pw2, barH, barH / 2, accent, 0.6)
      col(accent)
      love.graphics.rectangle("fill", ix, track, pw2, barH, barH / 2, barH / 2)
    end
  else
    self.romButtonRect =
      self:_glassyButton(ix, iy, innerW, btnH, romBtnLabel, self.saveBtnFont, romBtnEnabled)
  end

  -- SAVE FILES card: Import save (new slot) + Export save (active slot), with an
  -- outcome/hint line under them and an open-folder affordance after an export.
  roundedCard(leftX, saveFilesY, colW, saveFilesH, 16 * s)
  ix, iy = leftX + pad, saveFilesY + pad
  love.graphics.setFont(self.labelFont)
  col(PAL.labelGray)
  printSpaced(self.labelFont, "SAVE FILES", ix, iy, 2 * s)
  iy = iy + labelH + 10 * s
  local bGap = 10 * s
  local halfW = (innerW - bGap) / 2
  self.saveImportRect =
    self:_glassyButton(ix, iy, halfW, sfBtnH, "Import save", self.saveBtnFont, sfImportEnabled)
  self.saveExportRect = self:_glassyButton(ix + halfW + bGap, iy, halfW, sfBtnH,
    "Export save", self.saveBtnFont, sfExportEnabled)
  iy = iy + sfBtnH + 6 * s
  love.graphics.setFont(self.hintFont)
  col(sfHintCol)
  love.graphics.printf(sfHintText, ix, iy, innerW, "left")
  iy = iy + sfHintH
  if sfNotice and sfNotice.dir then
    iy = iy + 4 * s
    love.graphics.setFont(self.hintFont)
    local label = Strings("Open folder")
    local lw = self.hintFont:getWidth(label)
    local frect = { x = ix, y = iy, width = lw, height = self.hintFont:getHeight(),
      dir = sfNotice.dir }
    local fhot = self:_hover(frect)
    col(fhot and PAL.linkHover or PAL.link)
    love.graphics.print(label, ix, iy)
    love.graphics.setLineWidth(1)
    love.graphics.line(ix, iy + self.hintFont:getHeight() - 1, ix + lw,
      iy + self.hintFont:getHeight() - 1)
    self.saveFolderRect = frect
  end

  -- Touch Controls: open the drag-to-reposition / disable editor (#327).
  -- Map Editor beside it when this game is imported: the two share the row,
  -- each taking half, so adding the second button did not push Play down.
  if self.onEditTouchControls and touchBtnH > 0 then
    if showMapBtn then
      local halfW = (colW - 10 * s) / 2
      self.touchControlsRect = self:_glassyButton(
        leftX, touchY, halfW, touchBtnH, "Touch Controls", self.saveBtnFont, true)
      self.mapEditorRect = self:_glassyButton(
        leftX + halfW + 10 * s, touchY, halfW, touchBtnH, MAP_EDITOR_LABEL,
        self:_fittingFont(MAP_EDITOR_LABEL, halfW - 16 * s), canMapEdit)
    else
      self.touchControlsRect = self:_glassyButton(
        leftX, touchY, colW, touchBtnH, "Touch Controls", self.saveBtnFont, true)
    end
  elseif showMapBtn and touchBtnH > 0 then
    -- No Touch Controls host (a desktop-only build): the map button takes the
    -- reserved row on its own.
    self.mapEditorRect = self:_glassyButton(
      leftX, touchY, colW, touchBtnH, MAP_EDITOR_LABEL,
      self:_fittingFont(MAP_EDITOR_LABEL, colW - 16 * s), canMapEdit)
  end
  -- WHY IT IS GREY, under it, rather than left to be guessed at. One line,
  -- and only when the button is disabled: a reader looking at a lit button
  -- does not need to be told it works.
  if showMapBtn and not canMapEdit and touchBtnH > 0 then
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    local why = locked and "import this game first to edit its maps"
      or "finish importing this ROM to edit its maps"
    printB(why, leftX, touchY + touchBtnH + 2 * s)
  end

  -- Play button
  self:_playButton(leftX, playY, colW, playH, gameName, ready, locked)

  -- SAVE SLOT card (right column, or stacked below Play when single-column).
  -- Skip only when the version is absent from GameVersion (no save backend).
  local slotNaturalH = 0
  if not locked then
    if twoCol then
      _, slotNaturalH = self:_drawSaveSlotPanel(version, rightX, bodyTop, colW, bodyH, paged)
    else
      local slotY = playY + playH + 12 * s
      local slotH = math.max(160 * s, (bodyTop + bodyH) - slotY)
      _, slotNaturalH = self:_drawSaveSlotPanel(version, leftX, slotY, colW, slotH, paged)
    end
  end

  -- Natural height: side by side the two columns overlap, stacked they add up.
  -- Measured from the panel's own top (y), so draw() can compare it against the
  -- viewport without knowing anything about the cards inside.
  local bodyNaturalH
  if twoCol then
    bodyNaturalH = math.max(leftNaturalH, slotNaturalH)
  elseif locked then
    bodyNaturalH = leftNaturalH
  else
    bodyNaturalH = leftNaturalH + 12 * s + slotNaturalH
  end
  return (bodyTop - y) + bodyNaturalH
end

-- Reload a version's slot list + active id from SaveData (the source of truth).
-- Cheap enough to call on any mutation; the per-frame draw only calls it lazily
-- through _ensureSlots so a still list costs nothing after the first paint.
function RomImporter:_refreshSlots(version)
  local SaveData = require("src.core.SaveData")
  self.slots[version] = SaveData.listSlots(version) or {}
  local opts = SaveData.loadOptions()
  local reg = opts.saveSlots and opts.saveSlots[version]
  -- fall back to the first slot as the shown "loaded" one when the registry
  -- has a list but no explicit active id (matches saveNames' own resolution)
  self.activeSlot[version] = reg and (reg.active or reg.list[1]) or nil
end

function RomImporter:_ensureSlots(version)
  if not self.slots[version] then self:_refreshSlots(version) end
end

-- The host calls this when the save editor closes: the edited slot's player
-- name, badge count and dex total all feed the cached row summary, so it has
-- to be re-read rather than trusted across the round trip.
function RomImporter:savesChanged(version)
  self:_refreshSlots(version)
end

-- Point the active slot at id (persisted immediately, per the contract) and
-- reflect it in the LOADED pill without a full relist.
function RomImporter:_selectSlot(version, id)
  require("src.core.SaveData").setActiveSlot(version, id)
  self.activeSlot[version] = id
end

-- Inline slot rename (#205): right-click arms a modal text field; Enter
-- commits through SaveData.renameSlot (empty clears the label), Esc cancels.
-- While it is up, keypressed/textinput/mousepressed all route here first.
local MAX_SLOT_LABEL = 24
-- Long enough for a Pages URL with a deep path; short enough that a paste of
-- something that is not a URL at all cannot fill options.lua.
local MAX_INDEX_URL = 200
local MAX_FIND_QUERY = 48

-- Mobile LOVE only delivers love.textinput while setTextInput(true) is armed,
-- and arming it is also what raises the soft keyboard, so a cabled USB
-- keyboard is just as dead without it (#578).  Every site that opens one of
-- the launcher's three text fields (_rename, _indexPrompt, _findSearchFocus)
-- arms through here, and every site that closes one disarms.  Desktop has
-- text input on by default and the save editor hosted from this launcher
-- depends on it staying on (tools/save-editor/Kit.lua, #529), so disarm only
-- lowers on mobile -- setTextInput is global SDL state, not per-widget.
function RomImporter:_armTextInput()
  if love.keyboard and love.keyboard.setTextInput then
    local ok, err = pcall(love.keyboard.setTextInput, true)
    if not ok then
      -- Log error but don't crash - text input failure on Android is non-critical
      print("Failed to arm text input: " .. tostring(err))
    end
  end
end

function RomImporter:_disarmTextInput()
  if not self.android then return end
  if love.keyboard and love.keyboard.setTextInput then
    local ok, err = pcall(love.keyboard.setTextInput, false)
    if not ok then
      -- Log error but don't crash - text input failure on Android is non-critical
      print("Failed to disarm text input: " .. tostring(err))
    end
  end
end

function RomImporter:_beginRename(version, id)
  local label
  for _, slot in ipairs(self.slots[version] or {}) do
    if slot.id == id then label = slot.label break end
  end
  self._rename = { version = version, id = id, text = label or "" }
  self._slotPress = nil -- cancel any armed click/drag on the list
  self:_armTextInput()
end

function RomImporter:_commitRename()
  local r = self._rename
  if not r then return end
  self._rename = nil
  self:_disarmTextInput()
  require("src.core.SaveData").renameSlot(r.version, r.id, r.text)
  self:_refreshSlots(r.version)
end

function RomImporter:textinput(text)
  if self._indexPrompt then
    -- URLs never contain a literal space, and a pasted one usually arrives
    -- with a stray newline attached
    self._indexPrompt.text =
      utf8Cap(self._indexPrompt.text .. text:gsub("%s", ""), MAX_INDEX_URL)
    return
  end
  if self._findSearchFocus then
    self.findQuery = utf8Cap((self.findQuery or "") .. text, MAX_FIND_QUERY)
    self.findScroll = 0
    return
  end
  if not self._rename then return end
  self._rename.text = utf8Cap(self._rename.text .. text, MAX_SLOT_LABEL)
end

-- Clipboard into the index prompt, shared by ctrl/cmd+V and the prompt's
-- on-screen PASTE button (#578).  Same rule as typed input: URLs never
-- contain a literal space, and a pasted one usually arrives with a stray
-- newline attached.
function RomImporter:_pasteIndexUrl()
  if not self._indexPrompt then return end
  local ok, text = pcall(love.system.getClipboardText)
  if ok and type(text) == "string" then
    self._indexPrompt.text =
      utf8Cap(self._indexPrompt.text .. text:gsub("%s", ""), MAX_INDEX_URL)
  end
end

-- "+ New save slot": register an empty slot, make it active, relist, and pin the
-- scroll to the bottom (clamped next draw) so the new row is on screen.
function RomImporter:_newSlot(version)
  local SaveData = require("src.core.SaveData")
  local id = SaveData.createSlot(version)
  SaveData.setActiveSlot(version, id)
  self:_refreshSlots(version)
  self.activeSlot[version] = id
  self.slotScroll[version] = math.huge
end

-- Poll the pointer once per frame to drive drag-scroll + deferred click on the
-- save-slot list.  main.lua forwards neither move nor release events to the
-- launcher, so a press only ARMS a click (see mousepressed) and this resolves
-- it: a pointer that moved past the threshold scrolls; one that did not, on
-- release, selects.  Desktop only -- Android selects on press instead.
-- Where the pointer is this frame and whether it is held, read by polling
-- because no move event ever reaches the launcher: the mouse on desktop, the
-- first active touch on Android.  A nil y means "nothing to read" -- the
-- release branches below do not need one.
-- x comes back as a THIRD value, after y, so every existing `local down, py =`
-- call site keeps reading the same thing.  Only the tab bar wants x: it is the
-- one strip on the page that scrolls sideways.
function RomImporter:_pointerHold()
  if not self.android then return love.mouse.isDown(1), self._my, self._mx end
  if not self.touchPollable then return false, nil, nil end
  local ok, list = pcall(love.touch.getTouches)
  if not ok or type(list) ~= "table" or list[1] == nil then return false, nil, nil end
  local ok2, tx, ty = pcall(love.touch.getPosition, list[1])
  if not ok2 or type(ty) ~= "number" then return false, nil, nil end
  return true, ty, tx
end

-- Switch tabs and reset everything that belonged to the old one.
-- ---------------------------------------------------------------------------
-- SETTINGS: the gear in the top right.
--
-- `SaveData.loadOptions()` is not a per-save table -- it is the APPLICATION's
-- options file, and a save merges it on load (SaveData.mergeOptions). So the
-- launcher can edit these before any cartridge is open, and what it writes
-- becomes the default every new game and every loaded slot inherits.
--
-- Deliberately NOT reusing src/ui/OptionsMenu's rows: those are built against a
-- LIVE game (`g.save.options`, and they call Music.setVolumeLevel and friends
-- as they step). There is no game here. These rows read and write the options
-- table directly, and the ones with a live subsystem behind them nudge it only
-- when that subsystem is actually loaded.
--
-- Only options that MEAN something before a cartridge is chosen are listed.
-- Battle style, text speed and the rest are per-playthrough decisions that the
-- in-game OPTIONS menu already owns; putting them here as well would give the
-- player two switches for one setting and no clue which one won.
RomImporter.SETTINGS_ROWS = {
  { id = "musicVol", label = "MUSIC VOLUME", kind = "range", min = 0, max = 7,
    apply = function(v)
      local ok, M = pcall(require, "src.core.Music")
      if ok and M and M.setVolumeLevel then pcall(M.setVolumeLevel, v) end
    end },
  { id = "sfxVol", label = "SOUND VOLUME", kind = "range", min = 0, max = 7,
    apply = function(v)
      local ok, S = pcall(require, "src.core.Sound")
      if ok and S and S.setVolumeLevel then pcall(S.setVolumeLevel, v) end
    end },
  { id = "colors", label = "COLORS",
    values = { "gbc", "sgb", "dmg", "classic" },
    labels = { gbc = "GBC", sgb = "SGB", dmg = "DMG", classic = "CLASSIC" } },
  { id = "gbcfx", label = "GBC FX",
    values = { false, true }, labels = { [false] = "OFF", [true] = "ON" } },
  { id = "videoMode", label = "VIDEO MODE",
    values = { "windowed", "borderless", "fullscreen" },
    labels = { windowed = "WINDOWED", borderless = "BORDERLESS",
               fullscreen = "FULLSCREEN" } },
  { id = "faithfulRes", label = "FAITHFUL RES",
    values = { false, true }, labels = { [false] = "OFF", [true] = "ON" } },
  { id = "fpsCap", label = "MAX FPS",
    values = { 0, 30, 60, 120, 144 },
    labels = { [0] = "UNCAPPED", [30] = "30", [60] = "60", [120] = "120",
               [144] = "144" } },
  { id = "performance", label = "PERFORMANCE",
    values = { "quality", "balanced", "speed" },
    labels = { quality = "QUALITY", balanced = "BALANCED", speed = "SPEED" } },
}

-- Every row the settings screen shows, in order, as one flat list of
-- {kind="section"|"option"|"action"} entries.
--
-- Flat rather than nested because the panel scrolls: a section that owns its
-- own rows has to know its own height, and the moment mods contribute rows
-- (one shipped mod declares forty-three) that height is not knowable until
-- the mods have been read. A flat list measures in one pass.
--
-- SCOPE is what tells _stepSetting where a value lives:
--   "game"  options.<id>                  -- the engine defaults
--   "touch" options.touchControls.enabled -- the on-screen pad
--   "mod"   options.modOptions[modId][key]
-- All three end up in the same options file, which is why one Save covers
-- them; they are simply not the same shape inside it.
function RomImporter:_settingsRows()
  if self.settingsPage == "launcher" then
    return self:_launcherSettingsRows()
  end
  local rows = {}
  local function add(r) rows[#rows + 1] = r; return r end
  local GenOptions = require("src.core.GenOptions")
  local gen = self:_settingsGeneration()

  -- THE LAUNCHER'S OWN SETTINGS ARE A PAGE, NOT A SECTION.  What follows this
  -- is every default a GAME starts with; where the launcher installs those
  -- games and what colour it paints itself are about the launcher, they are
  -- set once and never again, and interleaving them with the rows a player
  -- actually comes here to change makes both lists longer to read.
  add({ kind = "section", label = "LAUNCHER" })
  add({ kind = "action", label = "LAUNCHER SETTINGS",
        value = "OPEN", action = "launcherPage",
        note = "Where games are installed, and how the launcher looks." })

  add({ kind = "section", label = "GAME DEFAULTS",
        note = "These are the defaults every game starts with. A "
            .. "playthrough's own OPTIONS menu still overrides them." })
  -- WHICH GAMES THE ROWS BELOW ARE FOR.  DMG green is right for Red and wrong
  -- for Emerald; the frame cap and FAITHFUL RES mean different things on a
  -- Game Boy screen and a GBA one.  ALL sets the shared value every generation
  -- follows, a generation sets an override only it reads
  -- (src/core/GenOptions.lua).
  add({ kind = "option", scope = "settingsGen", label = "APPLIES TO",
        row = { id = "settingsGen",
                values = { false, 1, 2, 3 },
                labels = { [false] = "ALL GAMES", [1] = "GEN 1 ONLY",
                           [2] = "GEN 2 ONLY", [3] = "GEN 3 ONLY" } } })
  for _, row in ipairs(RomImporter.SETTINGS_ROWS) do
    add({ kind = "option", scope = "game", gen = gen, row = row,
          label = row.label })
  end
  -- Only while a generation is selected AND has something to clear: an action
  -- that is always there and usually does nothing is one a player learns to
  -- ignore, and this one is the way back from an override they regret.
  if gen then
    local opts = self:_settings()
    local n = GenOptions.count(opts, gen)
    if n > 0 then
      add({ kind = "action", label = "USE SHARED VALUES",
            value = (n == 1) and "1 SET" or (tostring(n) .. " SET"),
            action = "clearGenOverrides",
            note = ("GEN %d is overriding %d of the rows above. This puts it "
                    .. "back on the shared values."):format(gen, n) })
    end
  end

  -- TOUCH CONTROLS. The toggle and the layout editor belong together: turning
  -- the pad on and never being able to move it is half a feature, and the
  -- editor was previously only reachable from a button on the game panel that
  -- a desktop player would never think to look at.
  add({ kind = "section", label = "TOUCH CONTROLS" })
  add({ kind = "option", scope = "touch", label = "ON-SCREEN PAD",
        row = { id = "touchEnabled", values = { false, true },
                labels = { [false] = "OFF", [true] = "ON" } } })
  if self.onEditTouchControls then
    add({ kind = "action", label = "EDIT LAYOUT",
          value = "OPEN", action = "touchLayout" })
  end

  -- MOD OPTIONS, one section per installed mod that declares any. Read through
  -- LauncherMods, which parses the mod's declared schema FILE rather than
  -- running the mod -- the launcher loads no mod code, and this must not be
  -- the exception that does.
  local okMods, list = pcall(function()
    return require("src.mods.LauncherMods").list()
  end)
  if okMods and type(list) == "table" then
    local LM = require("src.mods.LauncherMods")
    for _, mod in ipairs(list) do
      local okRows, modRows = pcall(LM.optionRows, mod)
      if okRows and modRows then
        add({ kind = "section", label = tostring(mod.name or mod.id):upper(),
              note = mod.enabled and nil
                or "This mod is disabled; its settings are kept but not used." })
        for _, r in ipairs(modRows) do
          add({ kind = "option", scope = "mod", modId = mod.id, row = r,
                label = tostring(r.label or r.key) })
        end
      end
    end
  end
  return rows
end


-- THE LAUNCHER SETTINGS PAGE, the drawer's second page.
--
-- Two things live here, and both are about the installation rather than any
-- one playthrough: where imported games are written, and what the launcher
-- looks like while you pick one.
function RomImporter:_launcherSettingsRows()
  local rows = {}
  local function add(r) rows[#rows + 1] = r; return r end
  local SaveData = require("src.core.SaveData")
  local LauncherTheme = require("src.import.LauncherTheme")

  add({ kind = "action", label = "BACK", value = "SETTINGS",
        action = "settingsBack" })

  -- ------- where games are installed
  add({ kind = "section", label = "GAME DATA FOLDER",
        note = self:_dataDirNote() })
  if SaveData.dataDirSupported() then
    if SaveData.isPortable() then
      -- Portable mode already answered this question, with a file sitting next
      -- to the executable.  Showing a stepper that cannot win against it would
      -- be a control that does nothing.
      add({ kind = "action", label = "PORTABLE MODE", value = "IN USE",
            action = "openDataDir",
            note = "portable.txt sits beside the game, so everything is kept "
                .. "in the game folder. Remove it to choose a folder here." })
    else
      add({ kind = "action",
            label = self.android and "CHOOSE STORAGE" or "CHOOSE FOLDER",
            value = self.android and "PICK" or "BROWSE",
            action = "chooseDataDir",
            note = self.android
              and "Phone storage, an SD card, or Browse for another writable folder. Android will not let this app write to Downloads."
              or nil })
      for _, vol in ipairs(SaveData.externalDataDirs()) do
        add({ kind = "action", label = vol.label,
              value = "USE", action = "setDataDirVolume",
              path = vol.path, note = vol.path })
      end
      if SaveData.dataDirSetting() then
        add({ kind = "action", label = "USE THE DEFAULT FOLDER",
              value = "RESET", action = "clearDataDir" })
      end
      if not self.android then
        add({ kind = "action", label = "OPEN FOLDER", value = "SHOW",
              action = "openDataDir" })
      end
      -- ...and the way to stop having TWO homes.  Changing the folder points
      -- future writes at it and leaves what is already installed where it was;
      -- love.filesystem shows both at once, so the launcher goes on listing
      -- mods that are not in the new place and a re-install becomes a second
      -- copy of the same mod.  An explicit action rather than something the
      -- switch does for you: this can be gigabytes.
      if require("src.import.CacheFs").rootReport().kind ~= "save" then
        add({ kind = "action", label = "MOVE EXISTING DATA HERE",
              value = self.moveWorker and "WORKING" or "MOVE",
              action = "moveData",
              note = self.moveNotice
                or "Moves installed mods, mod storage and imported base files "
                .. "out of the app's folder into this one. Saves and settings "
                .. "stay where they are." })
      end
    end
  else
    add({ kind = "action", label = "NOT AVAILABLE HERE", value = "-",
          action = "none",
          note = "This platform has no folder to point at; games stay in the "
              .. "app's own storage." })
  end

  -- ------- how the launcher looks
  add({ kind = "section", label = "APPEARANCE",
        note = "Chip colours stay as they are: they are how you tell the "
            .. "cartridges apart at a glance." })
  add({ kind = "option", scope = "launcher", label = "THEME",
        row = { id = "launcherTheme", values = LauncherTheme.presetValues(),
                labels = self:_themeLabels(LauncherTheme.PRESETS,
                                           LauncherTheme.presetValues()) } })
  add({ kind = "option", scope = "launcher", label = "ACCENT",
        row = { id = "launcherAccent", values = LauncherTheme.accentValues(),
                labels = self:_themeLabels(LauncherTheme.ACCENTS,
                                           LauncherTheme.accentValues()) } })
  -- TEXT is its own axis rather than something a ground decides, because it is
  -- the row a player comes here for when the reason is their eyes rather than
  -- their taste -- CONTRAST brightens the small print without taking the
  -- ground they chose away from them.
  add({ kind = "option", scope = "launcher", label = "TEXT",
        row = { id = "launcherText", values = LauncherTheme.textValues(),
                labels = self:_themeLabels(LauncherTheme.TEXTS,
                                           LauncherTheme.textValues()) } })
  -- The chosen entries explain themselves under the rows, one line each.  Only
  -- the ones that are set: DEFAULT has nothing to say, and three lines of
  -- "the launcher's own" would be three lines of nothing.
  local opts = self:_settings()
  -- Appended one at a time rather than gathered into a list first: a nil from
  -- the first lookup would end an ipairs walk before it reached the second, so
  -- choosing a text family while the ground was DEFAULT would silently lose
  -- its line.
  local themeNote = LauncherTheme.presetNote(opts.launcherTheme or nil)
  if themeNote then add({ kind = "section", label = "", note = themeNote }) end
  local textNote = LauncherTheme.textNote(opts.launcherText or nil)
  if textNote then add({ kind = "section", label = "", note = textNote }) end
  add({ kind = "action", label = "RESET APPEARANCE", value = "DEFAULT",
        action = "resetTheme" })

  return rows
end

-- A `labels` map for a theme stepper: every id's own label, plus DEFAULT for
-- the `false` entry the value lists start with.  Built rather than written out
-- because the two tables it serves have different shapes and the same rule.
function RomImporter:_themeLabels(source, values)
  local labels = { [false] = "DEFAULT" }
  for _, id in ipairs(values) do
    if id then
      local entry = source[id]
      labels[id] = entry and entry.label or tostring(id):upper()
    end
  end
  return labels
end

-- The line under the GAME DATA FOLDER heading: where games are going right
-- now, and -- when the stored folder is not the one in use -- why not.
--
-- Says the FULL PATH rather than "custom folder": the whole point of the
-- setting is that the player chose a place, and a panel that will not name it
-- is one they have to go hunting through an options file to verify.
function RomImporter:_dataDirNote()
  local SaveData = require("src.core.SaveData")
  local CacheFs = require("src.import.CacheFs")
  local lines = {}
  local stored = SaveData.dataDirSetting and SaveData.dataDirSetting() or nil
  -- ASKS THE THING THAT DOES THE WRITING.  This used to ask SaveData, which
  -- only knows whether the folder is readable and writable -- not whether the
  -- cache can actually live there, which additionally needs it on the PhysFS
  -- read path.  When those disagreed this panel said "games are installed in
  -- D:\..." while every byte went to the save directory, and there was
  -- nothing on screen or on disk to say otherwise.
  local report = CacheFs.rootReport()
  if report.kind == "portable" then
    lines[#lines + 1] = "Portable: " .. tostring(report.path or "the game folder")
  elseif report.kind == "custom" then
    lines[#lines + 1] = "Games are installed in " .. tostring(report.path)
  elseif stored then
    lines[#lines + 1] = "Set to " .. stored
    lines[#lines + 1] = "NOT IN USE ("
      .. tostring(report.why or "unavailable")
      .. "). Games are going to the default folder instead."
  else
    lines[#lines + 1] = "Games are installed in the app's own folder "
      .. "(" .. tostring(report.path or "AppData on Windows") .. ")."
  end
  -- STAYS ON THE PANEL, not just in the one-shot notice a tab change clears:
  -- this is true for the rest of the session, and it is the one thing that
  -- explains a folder the panel says is in use still reading like the old one.
  if report.restart then
    lines[#lines + 1] = "The previous folder is still on the read path. "
      .. "Restart the app to finish applying this."
  end
  -- A DIFFERENT PROBLEM WITH THE SAME SYMPTOM, so it gets its own line.  On a
  -- build where nothing can position a mount (an Android APK whose liblove.so
  -- the FFI cannot reach), the chosen folder is written and read but cannot be
  -- put AHEAD of the default one -- so a game imported before the change goes
  -- on being the one that loads.  A restart does not help; moving it does.
  if report.shadowed and report.kind ~= "save" then
    lines[#lines + 1] = "A game already imported to the default folder can "
      .. "still be the one that loads on this device. Use MOVE EXISTING DATA "
      .. "HERE to be sure."
  end
  -- WHAT MOVES AND WHAT DOES NOT, said here rather than discovered.
  --
  -- Everything that grows without bound follows the folder: the ROM cache, the
  -- mods themselves, their storage, and the shared base-file bank where a
  -- 1.4 GB disc lands.  Saves and settings deliberately do not.  They are
  -- kilobytes, so they buy nothing by moving, and they are the state you most
  -- want to still have when the drive this points at is not plugged in --
  -- which is the failure this setting makes possible and cannot prevent.
  lines[#lines + 1] = "Moves: imported games, installed mods, mod storage and "
    .. "imported base files. Stays: your saves and settings, so they survive "
    .. "this folder going missing."
  -- THE ONE THING THAT SURPRISES PEOPLE.  Changing this does not move what is
  -- already imported: the launcher would have to copy gigabytes through the UI
  -- thread to do it, and a launcher that appears to hang for four minutes
  -- after a settings change is worse than one that tells you to re-import.
  lines[#lines + 1] = "Changing this does not move games you have already "
    .. "imported; they stay where they are and can be re-imported or copied "
    .. "across by hand."
  if self.android then
    lines[#lines + 1] = "On Android, Phone storage is the same drive as the "
      .. "app folder; pick an SD card (or Browse a writable folder on it) "
      .. "when the app folder is out of space. Then use MOVE EXISTING DATA "
      .. "HERE if mods are already installed."
  end
  return table.concat(lines, "\n")
end

-- The options table, read once per settings frame and cached until something
-- writes: loadOptions parses a file, and the panel would otherwise re-read it
-- sixty times a second while the player looks at it.
function RomImporter:_settings()
  if not self._settingsCache then
    local ok, opts = pcall(function()
      return require("src.core.SaveData").loadOptions()
    end)
    self._settingsCache = (ok and type(opts) == "table") and opts or {}
  end
  return self._settingsCache
end

-- The generation the GAME DEFAULTS rows are currently being set for, or nil
-- for the shared values.  Deliberately NOT persisted: it is a lens on the
-- rows below it, not a setting, and a launcher that opens next week still
-- pointed at GEN 1 is one where a player changes COLORS and cannot work out
-- why Emerald ignored them.
function RomImporter:_settingsGeneration()
  return RomImporter.isGeneration(self.settingsGen)
end

-- The current value of one entry, whichever scope it lives in.
function RomImporter:_settingValue(entry)
  local opts = self:_settings()
  if entry.scope == "settingsGen" then
    -- `false` rather than nil: the stepper matches against its own value list,
    -- and ALL is spelled `false` there for the same reason the generation
    -- filter spells it that way.
    return self:_settingsGeneration() or false
  elseif entry.scope == "launcher" then
    local v = opts[entry.row.id]
    if v == nil or v == false then return false end
    return v
  elseif entry.scope == "game" and entry.gen then
    return require("src.core.GenOptions").get(opts, entry.row.id, entry.gen)
  end
  if entry.scope == "touch" then
    local tc = opts.touchControls
    -- Absent means ON: SaveData's defaults ship `touchControls = {enabled=true}`
    -- and the loader treats a missing table the same way, so reading a nil as
    -- OFF here would show the opposite of what the game does.
    if type(tc) ~= "table" or tc.enabled == nil then return true end
    return tc.enabled and true or false
  elseif entry.scope == "mod" then
    return require("src.mods.LauncherMods")
      .optionValue(opts, entry.modId, entry.row)
  end
  return opts[entry.row.id]
end

function RomImporter:_setSettingValue(entry, value)
  local opts = self:_settings()
  if entry.scope == "settingsGen" then
    self.settingsGen = RomImporter.isGeneration(value)
    -- The rows below it change meaning, and one of them (USE SHARED VALUES)
    -- appears and disappears with it, so the cached list has to go.
    self._settingsRowCache = nil
    return
  elseif entry.scope == "launcher" then
    opts[entry.row.id] = value or false
    -- Repaint immediately.  A theme row that only takes effect on the next
    -- launch is one a player steps through four times looking for a preview.
    pcall(RomImporter.applyTheme, opts)
    return
  elseif entry.scope == "game" and entry.gen then
    require("src.core.GenOptions").set(opts, entry.row.id, value, entry.gen)
    -- The first override a generation gains is also when USE SHARED VALUES
    -- has to appear, and the last one it loses is when it has to go; both are
    -- decided by _settingsRows, so the cached list is now wrong.
    self._settingsRowCache = nil
    return
  end
  if entry.scope == "touch" then
    local tc = type(opts.touchControls) == "table" and opts.touchControls or {}
    tc.enabled = value and true or false
    opts.touchControls = tc
  elseif entry.scope == "mod" then
    require("src.mods.LauncherMods")
      .setOptionValue(opts, entry.modId, entry.row.key, value)
  else
    opts[entry.row.id] = value
  end
end

-- A mod's `choice` rows carry `choices = {{LABEL, value}, ...}`; the engine's
-- own rows carry `values` plus a `labels` map. Normalised here so the drawing
-- and stepping code sees one shape.
function RomImporter:_settingChoices(entry)
  local row = entry.row
  if row.type == "number" or row.type == "text" then return nil, nil end
  if row.type == "choice" and type(row.choices) == "table" then
    local values, labels = {}, {}
    for _, pair in ipairs(row.choices) do
      values[#values + 1] = pair[2]
      labels[pair[2]] = tostring(pair[1])
    end
    return values, labels
  end
  if row.type == "toggle" then
    return { false, true }, { [false] = "OFF", [true] = "ON" }
  end
  return row.values, row.labels
end

function RomImporter:_entryLabel(entry)
  local row = entry.row
  local v = self:_settingValue(entry)
  if row.type == "number" then return tostring(tonumber(v) or row.default or 0) end
  if row.type == "text" then
    local str = tostring(v == nil and (row.default or "") or v)
    if str == "" then return "(empty)" end
    return str
  end
  if row.kind == "range" then
    local n = tonumber(v)
    if n == nil then n = row.max end
    if n <= (row.min or 0) then return "OFF" end
    return tostring(n)
  end
  local _, labels = self:_settingChoices(entry)
  if labels ~= nil and labels[v] ~= nil then return labels[v] end
  return tostring(v)
end

function RomImporter:_settingsLabel(row)
  local v = self:_settings()[row.id]
  if row.kind == "range" then
    local n = tonumber(v)
    if n == nil then n = row.max end
    if n <= (row.min or 0) then return "OFF" end
    return tostring(n)
  end
  if row.labels ~= nil and row.labels[v] ~= nil then return row.labels[v] end
  return tostring(v)
end

-- `dir` is +1 or -1. A range steps by one and CLAMPS rather than wrapping --
-- a volume slider that jumps from silent to loudest on one more click is a
-- nasty surprise through headphones. A value list wraps, because it is a
-- cycle with no ends.
function RomImporter:_stepSetting(entry, dir)
  -- Callers used to pass a bare SETTINGS_ROWS row. Both shapes arrive now (the
  -- rects carry entries), so a bare row is wrapped rather than rejected: this
  -- is reached from a mouse handler, and a wrong type here is a crash on a
  -- click, not a message.
  if entry.kind == nil and entry.id ~= nil then
    entry = { kind = "option", scope = "game", row = entry }
  end
  local row = entry.row
  -- A mod's `text` option is shown but not edited here: its editor in the
  -- in-game manager is a keyboard applet this panel does not have, and a
  -- stepper that walks a string one arrow at a time is not an editor. Left
  -- visible on purpose -- hiding it would make the launcher's list quietly
  -- shorter than the in-game one with nothing to say why.
  if row.type == "text" then
    self.settingsNotice = tostring(row.label or row.key)
      .. " is edited in the in-game mod manager"
    return
  end
  if row.type == "number" then
    local cur = tonumber(self:_settingValue(entry)) or tonumber(row.default) or 0
    local next_ = cur + dir * (tonumber(row.step) or 1)
    if row.min then next_ = math.max(row.min, next_) end
    if row.max then next_ = math.min(row.max, next_) end
    self:_setSettingValue(entry, next_)
  elseif row.kind == "range" then
    local lo, hi = row.min or 0, row.max or 7
    local n = tonumber(self:_settingValue(entry))
    if n == nil then n = hi end
    n = math.max(lo, math.min(hi, n + dir))
    self:_setSettingValue(entry, n)
    if row.apply then row.apply(n) end
  else
    local values = select(1, self:_settingChoices(entry)) or {}
    if #values == 0 then return end
    local current = self:_settingValue(entry)
    local at = 1
    for i, v in ipairs(values) do if v == current then at = i break end end
    at = ((at - 1 + dir) % #values) + 1
    self:_setSettingValue(entry, values[at])
    if row.apply then row.apply(values[at]) end
  end
  -- The scope selector is a lens, not a setting: it lives on `self` and there
  -- is nothing to write.  Returning before the save also keeps it out of the
  -- options file, where a future build would have to decide what a stale one
  -- means.
  if entry.scope == "settingsGen" then return end
  local opts = self:_settings()
  local ok = pcall(function()
    require("src.core.SaveData").saveOptions(opts)
  end)
  if not ok then
    pcall(function()
      require("src.core.Logger").warn(
        "launcher settings: the options file could not be written")
    end)
  end
end

-- What an `action` row does when it is pressed.  One place rather than a chain
-- of ifs in mousepressed, because the drawer now has two pages of them and the
-- touch path below resolves the same rows on release.
function RomImporter:_settingsAction(entry)
  local action = entry and entry.action
  if not action or action == "none" then return end
  if action == "touchLayout" then
    if self.onEditTouchControls then self.onEditTouchControls() end
  elseif action == "launcherPage" then
    self.settingsPage = "launcher"
    self.settingsScroll = 0
    self.settingsNotice = nil
    self._settingsRowCache = nil
  elseif action == "settingsBack" then
    self.settingsPage = nil
    self.settingsScroll = 0
    self.settingsNotice = nil
    self._settingsRowCache = nil
  elseif action == "clearGenOverrides" then
    local gen = self:_settingsGeneration()
    if gen then
      local opts = self:_settings()
      require("src.core.GenOptions").clear(opts, gen)
      self:_saveSettings()
      self._settingsRowCache = nil
      self.settingsNotice = Strings("GEN %d now uses the shared settings", gen)
    end
  elseif action == "moveData" then
    self:startDataMove()
  elseif action == "resetTheme" then
    local opts = self:_settings()
    opts.launcherTheme, opts.launcherAccent, opts.launcherText = false, false, false
    pcall(RomImporter.applyTheme, opts)
    self:_saveSettings()
    self._settingsRowCache = nil
    self.settingsNotice = Strings("Appearance back to the default")
  elseif action == "chooseDataDir" then
    self:chooseDataDir()
  elseif action == "setDataDirVolume" then
    self:setDataDir(entry.path)
  elseif action == "clearDataDir" then
    self:setDataDir(nil)
  elseif action == "openDataDir" then
    self:openDataDir()
  end
end

-- The options file write every settings path ends with, in one place so a
-- failure is reported the same way wherever it came from.
function RomImporter:_saveSettings()
  local opts = self:_settings()
  local ok = pcall(function()
    require("src.core.SaveData").saveOptions(opts)
  end)
  if not ok then
    pcall(function()
      require("src.core.Logger").warn(
        "launcher settings: the options file could not be written")
    end)
  end
  return ok
end

-- ---------------------------------------------------------------------------
-- THE GAME DATA FOLDER
--
-- Opening a native folder picker takes as long as the player takes, and on
-- Windows it is a PowerShell process -- so, like every other picker in here,
-- the call is made from the click and the result handled inline rather than
-- polled.  Nothing is moved and nothing is deleted: the setting points the
-- NEXT import somewhere else, which is the whole of what it claims to do.
-- ---------------------------------------------------------------------------

-- Re-run the readiness report for every cartridge.  The same loop new() runs
-- at boot, minus the logging: this is a deliberate action a player just took,
-- not a diagnosis of a launch.
function RomImporter:_recheckReady()
  for _, version in ipairs(GameVersion.ORDER) do
    local ok, report = pcall(RomImporter.readyReport, version)
    if ok and type(report) == "table" then
      self.ready[version] = report.ok and not self.forceImport
    end
  end
end

function RomImporter:chooseDataDir()
  local SaveData = require("src.core.SaveData")
  if not SaveData.dataDirSupported() then
    self.settingsNotice = Strings("This platform keeps games in one place")
    return
  end
  -- Android: a native volume / tree picker writes picked_folder.txt into
  -- the save identity (same async contract as pickFile).  hasNativePicker
  -- is desktop-only (osascript / PowerShell / zenity) and must not gate
  -- this path.
  if self.android then
    if pickFolder() then
      self.pickPending = true
      self.pickTimer = 0
      self.settingsNotice = Strings("Pick where to keep games and mods.")
    else
      self.settingsNotice = Strings("No folder picker on this device")
    end
    return
  end
  if not hasNativePicker() then
    self.settingsNotice = Strings("No folder picker on this device")
    return
  end
  local folder = chooseFolder(Strings("Choose where to install games"))
  if not folder or folder == "" then return end
  self:setDataDir(folder)
end

function RomImporter:setDataDir(path)
  local SaveData = require("src.core.SaveData")
  local ok, why = SaveData.setDataDir(path)
  if not ok then
    self.settingsNotice = Strings("Could not use that folder: %s",
      tostring(why or "unknown reason"))
    return false
  end
  -- The options table this panel is holding still has the old value in it, and
  -- setDataDir wrote through its own copy; drop both caches so the next frame
  -- reads what is actually on disk.
  self._settingsCache = nil
  self._settingsRowCache = nil
  -- Which games count as imported depends on which folder is being looked at,
  -- so the readiness of every tab has just changed.  Re-checked here rather
  -- than left for the next launch: a player who points at a folder with a
  -- previous install in it should see those games come back immediately, and
  -- one who points at an empty folder should see the truth rather than a row
  -- of PLAY buttons for data that is no longer on the read path.
  self:_recheckReady()
  pcall(function() self:_refreshMods() end)
  -- Reported from CacheFs, for the same reason the note above is: SaveData
  -- accepting a folder is not the same as the cache being able to live in it,
  -- and a confirmation that names a folder nothing will be written to is
  -- worse than no confirmation at all.
  local report = require("src.import.CacheFs").rootReport()
  -- A FOLDER CHANGE THAT CANNOT FULLY TAKE EFFECT SAYS SO.  CacheFs takes the
  -- previous home's mounts back off the read path so the change applies
  -- without a restart; where it cannot (Android's mountDirectory bridge has no
  -- unmount, and a mount something is streaming from will refuse), the old
  -- home is still in front of the new one for the rest of the session.  A
  -- setting that silently does nothing is the bug being fixed here; one that
  -- says "restart to apply" is not.
  local tail = report.restart
    and "  Restart the app to finish applying it." or ""
  if report.shadowed and report.kind ~= "save" then
    tail = tail .. "  A game already in the default folder can still be the "
      .. "one that loads; use MOVE EXISTING DATA HERE."
  end
  if report.kind == "custom" then
    self.settingsNotice = Strings("Games will be installed in %s",
      tostring(report.path)) .. tail
  elseif path ~= nil and path ~= "" then
    self.settingsNotice = Strings("That folder was saved but cannot be used: %s",
      tostring(report.why or "unknown reason"))
  else
    self.settingsNotice =
      Strings("Games will be installed in the default folder") .. tail
  end
  return true
end

-- ---------------------------------------------------------------------------
-- MOVING WHAT IS ALREADY INSTALLED into the chosen folder.
--
-- Its own coroutine rather than the import worker's: that one is driven by
-- workState and ends by pumping the ROM queue, and a migration finishing must
-- not start an import.  Stepped from the same update, inside the same frame
-- budget, so the launcher keeps drawing while gigabytes move.
-- ---------------------------------------------------------------------------

function RomImporter:startDataMove()
  if self.moveWorker then return end
  local DataMove = require("src.import.DataMove")
  local report = function(done, total, label)
    self.moveNotice = ("Moving %s ... %d%%"):format(
      tostring(label or ""),
      total > 0 and math.floor(done / total * 100) or 0)
  end
  self.moveNotice = "Moving..."
  self._settingsRowCache = nil
  self.moveWorker = coroutine.create(function()
    local result, why = DataMove.run(report)
    if not result then
      self.moveNotice = "Could not move: " .. tostring(why)
    else
      self.moveNotice = DataMove.summarize(result)
    end
  end)
end

-- One slice per frame.  Rebuilds the settings rows when it finishes so the
-- MOVE row stops saying WORKING and the folder note re-reads the disk.
function RomImporter:_stepDataMove()
  local worker = self.moveWorker
  if type(worker) ~= "thread" then return end
  local started = love.timer.getTime()
  repeat
    local ok, err = coroutine.resume(worker)
    if not ok then
      self.moveNotice = "Could not move: " .. tostring(err)
      self.moveWorker = nil
      self._settingsRowCache = nil
      return
    end
    if coroutine.status(worker) == "dead" then
      self.moveWorker = nil
      self._settingsCache = nil
      self._settingsRowCache = nil
      self:_recheckReady()
      self:_refreshMods()
      return
    end
  until love.timer.getTime() - started >= 0.003
end

function RomImporter:openDataDir()
  local SaveData = require("src.core.SaveData")
  local dir = SaveData.dataDir()
  if not dir and SaveData.isPortable() then dir = SaveData.portableBaseDir() end
  if not dir then
    -- The default folder is LOVE's save directory, which love.system can name
    -- and the player otherwise cannot.
    local ok, path = pcall(love.filesystem.getSaveDirectory)
    if ok then dir = path end
  end
  if not dir or dir == "" then
    self.settingsNotice = Strings("There is no folder to open")
    return
  end
  pcall(love.system.openURL, fileUrl(dir))
end

function RomImporter:_selectTab(id)
  -- "settings" is no longer a tab -- it is a drawer over whichever tab you are
  -- on -- so there is no _settingsFrom to remember any more and no way to be
  -- stranded on a screen you did not choose. Both caches still drop when the
  -- tab changes underneath the drawer, because a mod may have been installed
  -- or removed on the MODS tab and a stale row list would offer settings for a
  -- mod that is gone.
  self._settingsCache = nil
  self._settingsRowCache = nil
  self.tab = id
  self._slotPress = nil   -- drop any half-started slot drag on tab change
  self._modPress = nil    -- and any half-started mod toggle press
  self._settingsPress = nil -- and any half-started settings row press
  self._pagePress = nil   -- and any half-started page pan
  self._tabPress = nil    -- and any half-started tab-bar pan
  self._findSearchFocus = false  -- and the search caret, now off screen
  self:_disarmTextInput()
  -- Each tab is its own column of a different length; carrying one tab's
  -- offset into another lands somewhere arbitrary.
  self.pageScroll = 0
  -- (_drawTabBar notices self.tab moved and scrolls the new chip into view.)
end

function RomImporter:_updateSlotDrag()
  if self.android and not self.touchPollable then return end
  local down, py, px = self:_pointerHold()
  py = py or self._my
  px = px or self._mx
  local maxPage = self._pageMax or 0

  -- The tab bar is the one strip here that scrolls SIDEWAYS, so its drag is
  -- resolved on x: past the threshold it pans the bar, and a press that never
  -- moved falls through to the chip it landed on when the finger comes up.
  local tp = self._tabPress
  if tp then
    if down then
      local d = (px or tp.x0) - tp.x0
      if math.abs(d) > 4 * (self._s or 1) then tp.moved = true end
      if tp.moved then
        self.tabScroll = clamp(tp.scroll0 - d, 0, self._tabMax or 0)
      end
    else
      local id = (not tp.moved) and tp.id or nil
      self._tabPress = nil
      if id then self:_selectTab(id) end
    end
  end

  -- A press on empty background pans the page while it overflows.  Nothing is
  -- armed by it, so there is no release action to resolve.
  local pp = self._pagePress
  if pp then
    if down then
      if maxPage > 0 then
        self.pageScroll = clamp(pp.scroll0 - (py - pp.y0), 0, maxPage)
      end
    else
      self._pagePress = nil
    end
  end

  local p = self._slotPress
  if p then
    if down then
      local d = py - p.y0
      if math.abs(d) > 4 * (self._s or 1) then p.moved = true end
      if p.moved then
        -- Paged, the list has no scroll of its own: the drag pans the page, so
        -- a swipe that starts on a slot row behaves like one starting beside it.
        if maxPage > 0 then
          self.pageScroll = clamp(p.pageScroll0 - d, 0, maxPage)
        else
          local maxS = (self._slotMax and self._slotMax[p.version]) or 0
          self.slotScroll[p.version] = clamp(p.scroll0 - d, 0, maxS)
        end
      end
    else
      if not p.moved then self:_selectSlot(p.version, p.id) end
      self._slotPress = nil
    end
  end
  -- THE SETTINGS DRAWER.  Same rule, its own scroll offset: the drawer is a
  -- panel over the page, so a drag inside it must move the drawer and never the
  -- page behind it -- which is why this clamps against _settingsMax and never
  -- touches pageScroll the way the lists above do.
  local sp = self._settingsPress
  if sp then
    if down then
      -- `(py or sp.y0)` for the same reason the tab bar's drag reads
      -- `(px or tp.x0)`: the pointer position can be absent for a frame, and a
      -- nil arithmetic here is a crash while a finger is on the screen.
      local d = (py or sp.y0) - sp.y0
      if math.abs(d) > 4 * (self._s or 1) then sp.moved = true end
      if sp.moved then
        self.settingsScroll = clamp(sp.scroll0 - d, 0, self._settingsMax or 0)
      end
    else
      if not sp.moved and sp.entry then
        if sp.dir == 0 then
          self:_settingsAction(sp.entry)
        elseif sp.dir then
          self:_stepSetting(sp.entry, sp.dir)
        end
      end
      self._settingsPress = nil
    end
  end

  -- The same click-vs-drag resolution for the mods list: a moved pointer scrolls
  -- the list, a still one toggles the armed mod on release.
  local mp = self._modPress
  if mp then
    if down then
      local d = py - mp.y0
      if math.abs(d) > 4 * (self._s or 1) then mp.moved = true end
      if mp.moved then
        if maxPage > 0 then
          self.pageScroll = clamp(mp.pageScroll0 - d, 0, maxPage)
        else
          self.modScroll = clamp(mp.scroll0 - d, 0, self._modMax or 0)
        end
      end
    else
      if not mp.moved then
        if mp.gen then
          self:_toggleModGeneration(mp.id, mp.gen)
        else
          self:_toggleMod(mp.id)
        end
      end
      self._modPress = nil
    end
  end
end

-- Mouse wheel over a game tab scrolls its save-slot list (installed onto the
-- global love.wheelmoved in new(); see the chain there).  Clamped to the last
-- content extent draw computed for that version.
function RomImporter:wheelmoved(_, dy)
  local step = 48 * (self._s or 1)
  -- An open modal owns the wheel: the page behind it is not what the player is
  -- looking at, and a long description is the one thing here that needs it.
  if self._findDetails then
    self._findDetails.scroll = clamp(
      (self._findDetails.scroll or 0) - dy * step, 0, self._findDetails.max or 0)
    return
  end
  -- The settings drawer scrolls itself, for the same reason the modal above
  -- does: it is what the player is looking at, and the page behind it is not.
  -- Only while the pointer is inside it, so the wheel still reaches the page
  -- on the side the drawer does not cover.
  if self.settingsOpen and self._mx and self._my
     and inside(self.settingsDrawerRect, self._mx, self._my) then
    self.settingsScroll = clamp((self.settingsScroll or 0) - dy * step,
                                0, self._settingsMax or 0)
    return
  end
  -- The tab bar is its own horizontal strip and sits above the page viewport,
  -- so it claims the wheel while the pointer is inside it.  Checked before the
  -- page scroll or the bar would be unreachable on an overflowing page.
  local band = self._tabBand
  if band and (self._tabMax or 0) > 0 and self._mx and self._my
     and self._mx >= band[1] and self._mx <= band[2]
     and self._my >= band[3] and self._my <= band[4] then
    self.tabScroll = clamp((self.tabScroll or 0) - dy * step, 0, self._tabMax)
    return
  end
  -- An overflowing page scrolls as a whole; the panels' own lists are flattened
  -- in that mode, so there is never a second scroll region competing for this.
  local maxPage = self._pageMax or 0
  if maxPage > 0 then
    self.pageScroll = clamp((self.pageScroll or 0) - dy * step, 0, maxPage)
    return
  end
  if self.tab == "mods" then
    local maxS = self._modMax or 0
    if maxS <= 0 then return end
    self.modScroll = clamp((self.modScroll or 0) - dy * step, 0, maxS)
    return
  end
  if self.tab == "find" then
    local maxS = self._findMax or 0
    if maxS <= 0 then return end
    self.findScroll = clamp((self.findScroll or 0) - dy * step, 0, maxS)
    return
  end
  local version = self.panelVersion
  if not version or self.tab ~= version then return end
  local maxS = (self._slotMax and self._slotMax[version]) or 0
  if maxS <= 0 then return end
  self.slotScroll[version] = clamp((self.slotScroll[version] or 0) - dy * step, 0, maxS)
end

-- SAVE SLOT card: header ("SAVE SLOT" + "N slots"), a scrollable list of slot
-- rows (name + meta, LOADED pill on the active one), and a dashed "+ New save
-- slot" button pinned to the bottom.  Empty registries show a dashed hint box.
-- `paged` (the whole launcher page is scrolling, see draw()) drops the inner
-- scroll region: the card grows to its natural height, every row is drawn, and
-- the page's own scrollbar is the only one on screen.  Returns the height the
-- card actually took, which is what the caller measures the page against.
function RomImporter:_drawSaveSlotPanel(version, x, y, w, h, paged)
  local s = self._s
  local pad = 16 * s
  self:_ensureSlots(version)
  local slots = self.slots[version] or {}
  local active = self.activeSlot[version]
  local n = #slots

  -- Row metrics up front: the natural height needs them, and the natural height
  -- decides the card's height before anything is drawn.
  local labelH = self.labelFont:getHeight()
  local newBtnH = math.max(38 * s, self.saveBtnFont:getHeight() + 18 * s)
  local nameH = self.slotNameFont:getHeight()
  local metaH = self.labelFont:getHeight()
  local rowPadV = 10 * s
  local chipBtnH = self.hintFont:getHeight() + 10 * s
  -- LOADED sits top-right; Edit/Delete sit bottom-right -- row must fit both
  -- without stacking on the same y (chip buttons are taller than the old text).
  local loadedH = self.warningFont:getHeight() + 6 * s
  local rowH = math.max(rowPadV * 2 + nameH + 4 * s + metaH,
    rowPadV + loadedH + 4 * s + chipBtnH + rowPadV)
  local rowGap = 8 * s
  local rr = 12 * s
  local btnGap = 8 * s
  -- an empty registry shows a fixed-height dashed hint box instead of rows
  local totalH = (n > 0) and (n * rowH + (n - 1) * rowGap) or (96 * s)
  local naturalH = pad + labelH + 12 * s + totalH + 10 * s + newBtnH + pad
  if paged then h = naturalH end

  roundedCard(x, y, w, h, 16 * s)

  -- header: "SAVE SLOT" (left) + "N slots" / "1 slot" (right)
  love.graphics.setFont(self.labelFont)
  col(PAL.labelGray)
  printSpaced(self.labelFont, "SAVE SLOT", x + pad, y + pad, 2 * s)
  local countTxt = (n == 1) and "1 slot" or (n .. " slots")
  local cw = self.labelFont:getWidth(countTxt)
  love.graphics.print(countTxt, x + w - pad - cw, y + pad)

  local listTop = y + pad + labelH + 12 * s

  -- "+ New save slot" pinned to the card bottom; the list fills the gap above.
  local newBtnY = y + h - pad - newBtnH
  local listBottom = newBtnY - 10 * s
  local listH = math.max(0, listBottom - listTop)
  local rx, rw = x + pad, w - 2 * pad

  if n == 0 then
    -- empty state: a dashed box with the centred hint
    love.graphics.setLineWidth(math.max(1, 1 * s))
    col(PAL.cardBorder, 0.45)
    dashedRoundRect(rx, listTop, rw, listH, 12 * s, 7 * s, 5 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    love.graphics.printf("No saves yet - start a new game or import one.",
      rx + 12 * s, listTop + listH / 2 - self.hintFont:getHeight() / 2,
      rw - 24 * s, "center")
    self.slotRects = {}
    self.slotDeleteRects = {}
    self.slotEditRects = {}
  elseif listH > 0 then
    -- clamp scroll against the current content extent, and stash the max so the
    -- wheel handler (which has no geometry) can clamp against the same value.
    -- Paged, listH already equals totalH, so this is 0 and the wheel falls
    -- through to the page scroll.
    local maxScroll = math.max(0, totalH - listH)
    self._slotMax = self._slotMax or {}
    self._slotMax[version] = maxScroll
    local scroll = clamp(self.slotScroll[version] or 0, 0, maxScroll)
    self.slotScroll[version] = scroll

    self.slotRects = {}
    self.slotDeleteRects = {}
    self.slotEditRects = {}
    -- Paged, the page viewport's scissor is already set and nothing here
    -- overflows the card, so leave it alone rather than replace and clear it.
    if not paged then
      love.graphics.setScissor(math.floor(rx), math.floor(listTop),
        math.ceil(rw), math.ceil(listH))
    end
    for i, slot in ipairs(slots) do
      local ry = listTop - scroll + (i - 1) * (rowH + rowGap)
      if ry + rowH >= listTop and ry <= listBottom then
        local selected = slot.id == active
        if selected then neonGlow(rx, ry, rw, rowH, rr, PAL.green, 0.5) end
        fillGradRounded(rx, ry, rw, rowH, rr, PAL.slotBg, PAL.slotBg, 0.6, 0.6)
        love.graphics.setLineWidth(math.max(1, (selected and 1.5 or 1) * s))
        col(selected and PAL.green or PAL.cardBorder, selected and 0.9 or 0.22)
        love.graphics.rectangle("line", rx, ry, rw, rowH, rr, rr)

        -- Edit + Delete chip buttons (bottom-right row). Delete arms on the
        -- first click and asks "Sure?" on the second; width stays on "Delete"
        -- so the row never reflows (#433).
        love.graphics.setFont(self.hintFont)
        local darmed = armedDelete(self._confirmDelete, "slot", slot.id, version)
        local delLabel = darmed and "Sure?" or "Delete"
        local delW = self.hintFont:getWidth("Delete") + 24 * s
        local delX = rx + rw - 12 * s - delW
        local delY = ry + rowH - rowPadV - chipBtnH
        local drect = self:_chipButton(delX, delY, delLabel, {
          w = delW, h = chipBtnH, id = slot.id,
          kind = darmed and "dangerArmed" or "danger",
        })
        local rightReserve = delW + 18 * s

        -- Edit, immediately left of Delete: opens the bundled save editor on
        -- this slot's file. Only when the host supplied onEditSave and the
        -- slot actually holds a save.
        local erect = nil
        if self.onEditSave and slot.exists then
          local edW = self.hintFont:getWidth("Edit") + 24 * s
          local edX = delX - btnGap - edW
          erect = self:_chipButton(edX, delY, "Edit", {
            w = edW, h = chipBtnH, id = slot.id, kind = "accent",
          })
          rightReserve = rightReserve + edW + btnGap + 6 * s
        end

        -- LOADED pill top-right (above the button row, never over Delete)
        local pillW = 0
        if selected then
          love.graphics.setFont(self.warningFont)
          local pText = "LOADED"
          local pw = self.warningFont:getWidth(pText) + 14 * s
          local ph = loadedH
          local ppx = rx + rw - 12 * s - pw
          local ppy = ry + rowPadV
          col(PAL.green)
          love.graphics.rectangle("fill", ppx, ppy, pw, ph, ph / 2, ph / 2)
          col(PAL.playInk)
          printfB(pText, ppx, ppy + (ph - self.warningFont:getHeight()) / 2, pw, "center")
          pillW = pw + 10 * s
        end

        love.graphics.setFont(self.slotNameFont)
        col(PAL.ink)
        -- a custom label (#205) wins over the player name; both ellipsize
        local name = slot.label or slot.name or Strings("NEW GAME")
        printB(ellipsize(self.slotNameFont, name, rw - 24 * s - math.max(pillW, rightReserve)),
          rx + 12 * s, ry + rowPadV)

        local metaTxt
        if slot.exists and slot.meta then
          metaTxt = Strings("%d badges - %s - %d caught", slot.meta.badges or 0, slot.meta.timeText or "0:00",
            slot.meta.dexCount or 0)
        else
          metaTxt = "empty slot"
        end
        love.graphics.setFont(self.labelFont)
        col(PAL.warning)
        love.graphics.print(ellipsize(self.labelFont, metaTxt, rw - 24 * s - rightReserve),
          rx + 12 * s, ry + rowPadV + nameH + 4 * s)

        -- clip the hit rect to the visible list band so a partly-scrolled row
        -- is only clickable where it actually shows
        local vy = math.max(ry, listTop)
        local vy2 = math.min(ry + rowH, listBottom)
        if vy2 > vy then
          self.slotRects[#self.slotRects + 1] =
            { x = rx, y = vy, width = rw, height = vy2 - vy, id = slot.id }
        end
        local dvy = math.max(drect.y, listTop)
        local dvy2 = math.min(drect.y + drect.height, listBottom)
        if dvy2 > dvy then
          self.slotDeleteRects[#self.slotDeleteRects + 1] =
            { x = drect.x, y = dvy, width = drect.width, height = dvy2 - dvy, id = slot.id }
        end
        if erect then
          local evy = math.max(erect.y, listTop)
          local evy2 = math.min(erect.y + erect.height, listBottom)
          if evy2 > evy then
            self.slotEditRects[#self.slotEditRects + 1] =
              { x = erect.x, y = evy, width = erect.width, height = evy2 - evy,
                id = slot.id }
          end
        end
      end
    end
    if not paged then love.graphics.setScissor() end

    -- thin scrollbar thumb when the list overflows
    if maxScroll > 0 then
      local trackH = listH
      local thumbH = math.max(24 * s, trackH * (listH / totalH))
      local thumbY = listTop + (trackH - thumbH) * (scroll / maxScroll)
      col(PAL.cardBorder, 0.35)
      love.graphics.rectangle("fill", rx + rw - 3 * s, thumbY, 3 * s, thumbH,
        1.5 * s, 1.5 * s)
    end
  end

  -- "+ New save slot" (dashed, transparent) pinned to the bottom
  local nrect = { x = rx, y = newBtnY, width = rw, height = newBtnH }
  local nhot = self:_hover(nrect)
  love.graphics.setLineWidth(math.max(1, 1.4 * s))
  col(PAL.cardBorder, nhot and 0.7 or 0.45)
  dashedRoundRect(nrect.x, nrect.y, nrect.width, nrect.height, 10 * s, 6 * s, 5 * s)
  love.graphics.setFont(self.saveBtnFont)
  col(PAL.detail, nhot and 1 or 0.9)
  printfB("+ New save slot", nrect.x,
    nrect.y + (newBtnH - self.saveBtnFont:getHeight()) / 2, nrect.width, "center")
  self.newSlotRect = nrect
  return h, naturalH
end

-- Reload the mods list from LauncherMods (the source of truth: it reads the
-- same options.mods enable-state the loader persists).  Cheap enough to call on
-- any toggle / install; the per-frame draw calls it lazily through _ensureMods
-- so a still list costs nothing after the first paint.
function RomImporter:_refreshMods()
  local LauncherMods = require("src.mods.LauncherMods")
  -- Once per session, ahead of the first listing: pull in any mod the player
  -- unzipped beside the executable, which an ordinary (non-portable) install
  -- has no way to read.  It happens here rather than behind a button because
  -- the failure being fixed is one where nothing on screen suggests there is
  -- anything to press -- the panel just comes up empty.  Guarded so a toggle
  -- or a delete does not re-scan; adoptStrays is idempotent regardless.
  if not self.modStraysChecked then
    self.modStraysChecked = true
    local imported, failed = {}, {}
    for _, s in ipairs(LauncherMods.adoptStrays() or {}) do
      table.insert(s.err and failed or imported, s.id)
    end
    -- the failure wins the notice: an import that worked speaks for itself in
    -- the list right below it, one that did not is the only word they get
    if #imported > 0 then
      self.modNotice = { ok = true,
        text = "Imported from the game folder: " .. table.concat(imported, ", ") }
    end
    if #failed > 0 then
      self.modNotice = { ok = false,
        text = "Found beside the game but could not import: "
               .. table.concat(failed, ", ") }
    end
  end
  self.mods = LauncherMods.list() or {}
  self:_syncModUpdateInfo(false)
end

function RomImporter:_ensureMods()
  if not self.mods then self:_refreshMods() end
end

-- Resolve cached (or freshly fetched) GitHub status for every mod that
-- declares a github field and has not opted out with `update_check: false`.
-- force=true bypasses the 6h cache on every repo.
-- Results live on self.modUpdateInfo[id] = { status, latest, best, releases }.
function RomImporter:_syncModUpdateInfo(force)
  local ModUpdate = require("src.mods.ModUpdate")
  self.modUpdateInfo = self.modUpdateInfo or {}
  for _, m in ipairs(self.mods or {}) do
    if m.github and m.github ~= "" and m.updateCheck ~= false then
      local ok, packed = pcall(function()
        local releases, err, meta = ModUpdate.fetchReleases(m.github, m.id, {
          force = force == true,
        })
        local cached = ModUpdate.readCache(m.github)
        return {
          releases = releases,
          err = err,
          meta = meta,
          checkedAt = (cached and cached.checkedAt) or os.time(),
        }
      end)
      if not ok then
        self.modUpdateInfo[m.id] = {
          status = "error", err = tostring(packed),
        }
      elseif packed.releases then
        local status, best = ModUpdate.statusFor(m.version, packed.releases)
        self.modUpdateInfo[m.id] = {
          status = status,
          latest = best and best.version or nil,
          best = best,
          releases = packed.releases,
          err = nil,
          checkedAt = packed.checkedAt or os.time(),
        }
      else
        self.modUpdateInfo[m.id] = {
          status = "error",
          latest = nil,
          best = nil,
          releases = nil,
          err = tostring(packed.err),
        }
      end
    else
      self.modUpdateInfo[m.id] = nil
    end
  end
end

function RomImporter:_modUpdateInfo(id)
  return self.modUpdateInfo and self.modUpdateInfo[id] or nil
end

-- Flip a mod's enabled flag (persisted via LauncherMods.setEnabled) and relist
-- so the toggle, count, and every status chip reflect the new resolution.
-- Enabling an experimental mod arms a confirm first.
function RomImporter:_toggleMod(id, confirmed)
  local LauncherMods = require("src.mods.LauncherMods")
  local cur, experimental = false, false
  for _, m in ipairs(self.mods or {}) do
    if m.id == id then
      cur = m.enabled
      experimental = m.experimental == true
      break
    end
  end
  local want = not cur
  if want and experimental and not confirmed then
    self._modConfirm = {
      kind = "experimental", id = id,
      title = "Experimental mod",
      yesLabel = "Enable",
      lines = {
        "This mod is marked experimental.",
        "It may be unfinished or unstable.",
        "Enable it anyway?",
      },
    }
    return
  end
  self._modConfirm = nil
  LauncherMods.setEnabled(id, want)
  self:_refreshMods()
end

-- One of the three generation chips under a mod's switch.
--
-- No confirm of its own, even for an experimental mod: the master switch above
-- it is the opt-in, and a chip can only narrow or widen a mod that is already
-- on.  Turning a chip on for a mod that is OFF turns the mod on too (see
-- ModGens.withGen) -- which IS the experimental opt-in, so that one route
-- keeps the warning.
function RomImporter:_toggleModGeneration(id, gen, confirmed)
  local LauncherMods = require("src.mods.LauncherMods")
  if not (gen and ModGens.LABELS[gen]) then return end
  local row
  for _, m in ipairs(self.mods or {}) do
    if m.id == id then row = m break end
  end
  if not row then return end
  -- absent means ticked, the same way ModGens reads it
  local want = (row.gens or {})[gen] == false
  -- LIGHTING A CHIP THE MOD SAYS IT CANNOT FILL.
  --
  -- The loader refuses to load a mod outside its declared `generations`, and
  -- that refusal is a default rather than a wall (ModGens.permits).  The door
  -- is here, and it asks first: a plain chip press is "I want this mod here",
  -- and overruling the author's own claim is a different sentence, which the
  -- player has to say out loud.  Unticking the chip again clears the override
  -- (ModGens.withGen), so there is nothing to undo separately.
  local declared = ModGens.supported(row.supportedGens
    and { generations = row.supportedGens } or nil)
  if want and declared and not declared[gen] then
    if not (row.forcedGens or {})[gen] and not confirmed then
      local claim = {}
      for i = 1, ModGens.COUNT do
        if declared[i] then claim[#claim + 1] = ModGens.LABELS[i] end
      end
      self._modConfirm = {
        kind = "forceGen", id = id, gen = gen,
        title = "Not made for this generation",
        yesLabel = "Run it anyway",
        lines = {
          (row.name or id) .. " says it is for "
            .. (claim[1] and table.concat(claim, " and ") or "no generation")
            .. ".",
          "Running it under " .. tostring(ModGens.LABELS[gen] or "?")
            .. " may break the mod, this game, or both.",
          "Turn it on there anyway?",
        },
      }
      return
    end
    self._modConfirm = nil
    LauncherMods.setForcedGeneration(id, gen, true)
    self:_refreshMods()
    return
  end
  if want and not row.enabled and row.experimental and not confirmed then
    self._modConfirm = {
      kind = "experimentalGen", id = id, gen = gen,
      title = "Experimental mod",
      yesLabel = "Enable",
      lines = {
        "This mod is marked experimental.",
        "It may be unfinished or unstable.",
        "Turn it on for " .. tostring(ModGens.LABELS[gen] or "?") .. "?",
      },
    }
    return
  end
  self._modConfirm = nil
  LauncherMods.setGeneration(id, gen, want)
  self:_refreshMods()
end

-- Enable all / Disable all (#647).  One options write for the whole list
-- (LauncherMods.setAllEnabled) and one relist afterwards, so the count, the
-- switches and every status chip resolve together instead of per mod.
-- Enabling routes through the same experimental confirm _toggleMod arms: that
-- opt-in is the only warning an experimental mod ever gets, and a bulk button
-- must not be the way around it.  Disabling needs no confirm -- it is the
-- recovery action, and Delete is the only destructive one on this panel.
function RomImporter:_setAllMods(want, confirmed)
  local LauncherMods = require("src.mods.LauncherMods")
  local ids, experimental = {}, false
  for _, m in ipairs(self.mods or {}) do
    if m.enabled ~= want then
      ids[#ids + 1] = m.id
      if want and m.experimental then experimental = true end
    end
  end
  if #ids == 0 then
    self.modNotice = { ok = true, text = want
      and Strings("Every mod is already enabled.")
      or Strings("Every mod is already disabled.") }
    return
  end
  if want and experimental and not confirmed then
    self._modConfirm = {
      kind = "enableAll",
      title = "Experimental mods",
      yesLabel = "Enable all",
      lines = {
        "Some of these mods are marked experimental.",
        "They may be unfinished or unstable.",
        "Enable everything anyway?",
      },
    }
    return
  end
  self._modConfirm = nil
  LauncherMods.setAllEnabled(ids, want)
  self:_refreshMods()
  self.modNotice = { ok = true, text = want
    and Strings("Enabled %d mods.", #ids)
    or Strings("Disabled %d mods.", #ids) }
end

-- GitHub Update / Check for updates / Versions. Soft-fails into modNotice.
-- Update button: when a newer release is known, confirm then install; when
-- already current, force-refresh the 6h cache and report / offer update.
function RomImporter:_modGithubAction(id, action)
  local ran, err = pcall(function()
    local ModUpdate = require("src.mods.ModUpdate")
    local row
    for _, m in ipairs(self.mods or {}) do
      if m.id == id then row = m; break end
    end
    if not row or not row.github then
      self.modNotice = { ok = false, text = "This mod has no github field" }
      return
    end
    if row.updateCheck == false then
      self.modNotice = { ok = false,
        text = row.name .. " is a fork; it does not track " .. row.github }
      return
    end

    if action == "versions" then
      self.modNotice = { ok = true, text = "Loading versions..." }
      local releases, fetchErr = ModUpdate.fetchReleases(row.github, row.id, {})
      if not releases then
        self.modNotice = { ok = false, text = tostring(fetchErr) }
        return
      end
      local status, best = ModUpdate.statusFor(row.version, releases)
      self.modUpdateInfo = self.modUpdateInfo or {}
      self.modUpdateInfo[row.id] = {
        status = status, latest = best and best.version, best = best,
        releases = releases,
      }
      self._modVersions = {
        id = row.id, name = row.name, current = row.version,
        releases = releases, scroll = 0,
      }
      self.modNotice = nil
      return
    end

    -- update / check
    local info = self:_modUpdateInfo(id)
    if info and info.status == "available" and info.best then
      self._modConfirm = {
        kind = "update", id = row.id, release = info.best,
        title = "Update available",
        yesLabel = "Update",
        lines = {
          "Update " .. row.name .. "?",
          "Installed v" .. tostring(row.version),
          "Latest v" .. tostring(info.best.version),
        },
      }
      return
    end

    -- Manual check (or first click when status is current/unknown/error)
    self.modNotice = { ok = true, text = "Checking " .. row.github .. "..." }
    local releases, fetchErr = ModUpdate.fetchReleases(row.github, row.id, {
      force = true,
    })
    if not releases then
      self.modNotice = { ok = false, text = tostring(fetchErr) }
      return
    end
    if #releases == 0 then
      self.modNotice = { ok = false, text = "No .zip releases found" }
      return
    end
    local status, best = ModUpdate.statusFor(row.version, releases)
    self.modUpdateInfo = self.modUpdateInfo or {}
    self.modUpdateInfo[row.id] = {
      status = status, latest = best and best.version, best = best,
      releases = releases, checkedAt = os.time(),
    }
    if status == "available" and best then
      self.modNotice = { ok = true,
        text = row.name .. ": new version available (v" .. best.version .. ")" }
      self._modConfirm = {
        kind = "update", id = row.id, release = best,
        title = "Update available",
        yesLabel = "Update",
        lines = {
          "Update " .. row.name .. "?",
          "Installed v" .. tostring(row.version),
          "Latest v" .. tostring(best.version),
        },
      }
    else
      self.modNotice = { ok = true,
        text = row.name .. " is up to date (v"
          .. tostring(row.version) .. ")" }
    end
  end)
  if not ran then
    self._modVersions = nil
    self.modNotice = { ok = false,
      text = "Update failed: " .. tostring(err) }
  end
end

function RomImporter:_confirmModUpdate(modId, release)
  local row
  for _, m in ipairs(self.mods or {}) do
    if m.id == modId then row = m; break end
  end
  local name = row and row.name or modId
  self.modNotice = { ok = true,
    text = "Downloading " .. tostring(release and release.version or "?") .. "..." }
  local ran, err = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    local ok, res, mismatch = LauncherMods.installFromRelease(modId, release)
    if ok then
      pcall(self._refreshMods, self)
      -- A MIS-STAMPED RELEASE IS NOT A SUCCESSFUL UPDATE, whatever the files
      -- say.  installFromRelease hands back the version the installed
      -- manifest.json declares and, when that is not the release's own
      -- number, the reason -- because the alternative is "Updated to 0.7.47"
      -- followed by 0.7.47 still being offered, with nothing anywhere saying
      -- why (see installFromRelease).
      self.modNotice = mismatch
        and { ok = false, text = name .. ": " .. mismatch }
        or { ok = true, text = "Updated " .. name .. " to " .. tostring(res) }
    else
      self.modNotice = { ok = false, text = tostring(res) }
    end
  end)
  if not ran then
    self.modNotice = { ok = false, text = "Update failed: " .. tostring(err) }
  end
end

function RomImporter:_installModVersion(modId, release)
  self._modVersions = nil
  self._modReleaseNotes = nil
  local version = release and release.version or "?"
  self.modNotice = { ok = true, text = "Downloading " .. tostring(version) .. "..." }
  local ran, err = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    local ok, res, mismatch = LauncherMods.installFromRelease(modId, release)
    if ok then
      pcall(self._refreshMods, self)
      self.modNotice = mismatch
        and { ok = false, text = tostring(modId) .. ": " .. mismatch }
        or { ok = true,
             text = "Installed " .. tostring(modId) .. " " .. tostring(res) }
    else
      self.modNotice = { ok = false, text = tostring(res) }
    end
  end)
  if not ran then
    self.modNotice = { ok = false,
      text = "Install failed: " .. tostring(err) }
  end
end

-- The status-chip label + colour for a mod row (deriveList's status verdict).
local function modStatusChip(status)
  if status == "ok" then return "Ready", PAL.green end
  if status == "conflict" then return "Conflict", PAL.red end
  return "Incompatible", PAL.gold   -- "warn": bad range or missing dependency
end

-- MODS panel.  Header ("Mods" + "N of M enabled" + "Import mod .zip"), an
-- install-result / drag-drop notice line, then a scrollable list of mod cards
-- (name + badge chip + description, a status chip, and a toggle switch).  An
-- empty install shows a friendly dashed hint box.
-- `paged` behaves as it does on the game panel: no inner scroll region, the
-- card list is drawn whole, and the returned natural height is what draw()
-- measures the page against.
function RomImporter:_drawModsPanel(x, y, w, h, paged)
  local s = self._s
  self:_ensureMods()
  local mods = self.mods or {}

  -- header: "Mods" + "N of M enabled" (left) and "Import mod .zip" (right)
  love.graphics.setFont(self.gameNameFont)
  col(PAL.ink)
  printB("Mods", x, y)
  local nameW = self.gameNameFont:getWidth("Mods")
  local headerH = self.gameNameFont:getHeight()

  local enabledCount = 0
  for _, m in ipairs(mods) do if m.enabled then enabledCount = enabledCount + 1 end end
  love.graphics.setFont(self.hintFont)
  col(PAL.warning)
  local countText = Strings("%d of %d enabled", enabledCount, #mods)
  local countX = x + nameW + 14 * s
  love.graphics.print(countText, countX,
    y + (headerH - self.hintFont:getHeight()) / 2)

  local btnLabel = "Import mod .zip"
  local btnH = math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s)
  local btnW = math.min(w * 0.5, self.saveBtnFont:getWidth(btnLabel) + 40 * s)
  local btnX = x + w - btnW
  local btnY = y + (headerH - btnH) / 2
  self.modImportRect =
    self:_glassyButton(btnX, btnY, btnW, btnH, btnLabel, self.saveBtnFont, true)

  -- The chip run beside "Import mod .zip": the two mass importers and the two
  -- bulk switches.
  --
  -- MASS IMPORT (asked for directly: "add a way to mass import mods").
  -- "Import many" opens a multi-select picker; "Import folder" takes every
  -- .zip in a folder and one level under it.  Both end in one install pass and
  -- one summary line rather than a notice per archive -- see _installMods.
  --
  -- Enable all / Disable all (#647) keep their place at the right, so coming
  -- back from a cable-club session (which asks for a vanilla fingerprint,
  -- src/link/Fingerprint.lua) still costs one click.
  --
  -- The header is a single row shared with the count, so chips are DROPPED
  -- rather than overlapped when the column is too narrow (a phone-width
  -- layout).  They go in a deliberate order: the bulk switches first, because
  -- every mod card carries its own switch, and the mass importers last,
  -- because nothing else on the panel does what they do.  "Import mod .zip"
  -- itself is never dropped.
  self.modEnableAllRect, self.modDisableAllRect = nil, nil
  self.modImportManyRect, self.modImportFolderRect = nil, nil
  do
    love.graphics.setFont(self.hintFont)
    local bulkH = self.hintFont:getHeight() + 10 * s
    local bulkY = y + (headerH - bulkH) / 2
    local bulkGap = 8 * s
    -- left to right, as they read
    local run = {
      -- `drop` is the order they go in as the room runs out, highest first
      { label = Strings("Import many"), field = "modImportManyRect",
        kind = "accent", drop = 2 },
      { label = Strings("Import folder"), field = "modImportFolderRect",
        drop = 3 },
    }
    if #mods > 0 then
      run[#run + 1] = { label = Strings("Enable all"),
                        field = "modEnableAllRect", drop = 5 }
      -- Disable all outlives Enable all by one step: it is the recovery
      -- action, and a launcher too narrow to show both should show that one.
      run[#run + 1] = { label = Strings("Disable all"),
                        field = "modDisableAllRect", drop = 4 }
    end
    for _, c in ipairs(run) do
      c.w = self.hintFont:getWidth(c.label) + 24 * s
    end
    local room = btnX - (countX + self.hintFont:getWidth(countText) + bulkGap)
    local function span(list)
      local total = 0
      for _, c in ipairs(list) do total = total + c.w + bulkGap end
      return total + bulkGap
    end
    local shown = run
    while #shown > 0 and span(shown) > room do
      -- drop the lowest-priority chip still standing
      local worst, at = -1, nil
      for i, c in ipairs(shown) do
        if c.drop > worst then worst, at = c.drop, i end
      end
      local kept = {}
      for i, c in ipairs(shown) do if i ~= at then kept[#kept + 1] = c end end
      shown = kept
    end
    local cx2 = btnX - bulkGap
    for i = #shown, 1, -1 do
      local c = shown[i]
      cx2 = cx2 - c.w
      self[c.field] = self:_chipButton(cx2, bulkY, c.label,
        { w = c.w, h = bulkH, kind = c.kind })
      cx2 = cx2 - bulkGap
    end
  end

  local top = y + headerH + 14 * s

  -- Notice line: the last install/delete result, else the platform hint.
  --
  -- MEASURED, NOT ASSUMED.  This advanced `top` by exactly one line whatever
  -- it had just drawn, so any notice that wrapped ran straight down through
  -- the cards underneath it -- which is what a failed mass import looks like,
  -- because its summary names every archive it could not take.  Reported with
  -- a screenshot of a panel with the first mod card behind six lines of red.
  --
  -- Capped as well as measured: an error from a shell command can be a
  -- hundred lines, and a notice that pushes the whole list off the bottom is
  -- no more readable than one drawn over it.
  love.graphics.setFont(self.hintFont)
  local noticeText, noticeColor
  if self.modNotice then
    noticeText = tostring(self.modNotice.text)
    noticeColor = self.modNotice.ok and PAL.green or PAL.red
  else
    -- MODS LEFT IN THE OLD HOME, said here rather than left as a mystery.
    -- Once a game-data folder is in use the panel lists only what is in it, so
    -- a player who changed the folder after installing things sees a shorter
    -- list than they had.  Those mods are not gone and not deleted; this is
    -- the line that says where they are and what brings them over.
    local stranded = {}
    pcall(function()
      stranded = require("src.mods.LauncherMods").strandedMods() or {}
    end)
    if #stranded > 0 then
      noticeText = Strings(
        "%d mod(s) are still in the app's own folder and are not being used: "
        .. "%s. Settings -> LAUNCHER SETTINGS -> MOVE EXISTING DATA HERE "
        .. "brings them over.",
        #stranded, table.concat(stranded, ", "))
      noticeColor = PAL.warning
    else
      noticeText = self.android and "Or copy a mod .zip via USB."
        or Strings("Or drop a mod .zip onto the window.")
      noticeColor = PAL.warning
    end
  end
  local NOTICE_MAX_LINES = 6
  local _, noticeLines = self.hintFont:getWrap(noticeText, w)
  local shown = #noticeLines
  if shown > NOTICE_MAX_LINES then
    -- rebuild from the lines that fit rather than trusting the wrap to land
    -- the same way twice on a shorter string
    local kept = {}
    for i = 1, NOTICE_MAX_LINES - 1 do kept[#kept + 1] = noticeLines[i] end
    kept[#kept + 1] = ("... (%d more lines)"):format(shown - (NOTICE_MAX_LINES - 1))
    noticeText = table.concat(kept, "\n")
    shown = NOTICE_MAX_LINES
  end
  col(noticeColor)
  love.graphics.printf(noticeText, x, top, w, "left")
  top = top + math.max(1, shown) * self.hintFont:getHeight() + 12 * s

  local listH = math.max(0, (y + h) - top)

  -- empty state: a dashed box with a centred hint
  if #mods == 0 then
    local boxH = paged and (120 * s) or math.min(listH, 120 * s)
    love.graphics.setLineWidth(math.max(1, 1 * s))
    col(PAL.cardBorder, 0.45)
    dashedRoundRect(x, top, w, boxH, 14 * s, 7 * s, 5 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    local emptyHint = self.android
      and "No mods installed - tap Import mod .zip to add one."
      or Strings("No mods installed - drop a mod .zip here to add one.")
    love.graphics.printf(emptyHint,
      x + 16 * s, top + boxH / 2 - self.hintFont:getHeight() / 2, w - 32 * s, "center")
    self.modRects = {}
    self.modDeleteRects = {}
    self.modUpdateRects = {}
    self.modVersionsRects = {}
    self.modImportFileRects = {}
    self.modImportGameRects = {}
    self.modSupportRects = {}
    self.modGenRects = {}
    self._modMax = 0
    return (top - y) + boxH
  end

  -- card metrics: status + toggle top-right; action chip-buttons in one row
  -- under the body (Update / Versions / Delete when github is set).
  local padH, padV = 16 * s, 14 * s
  local cardGap, cardR = 10 * s, 14 * s
  local tw, th = 52 * s, 28 * s
  local innerW = w - 2 * padH
  local chipH = self.hintFont:getHeight() + 8 * s
  local btnH = self.hintFont:getHeight() + 10 * s
  local btnGap = 8 * s

  love.graphics.setFont(self.stateFont)
  local nameH = self.stateFont:getHeight()

  -- pre-pass: per-card layout + total height, so scroll can clamp to content
  local layout, total = {}, 0
  for i, m in ipairs(mods) do
    local chipText = modStatusChip(m.status)
    local chipW = self.hintFont:getWidth(chipText) + 20 * s
    local delW = self.hintFont:getWidth("Delete") + 24 * s
    local verW = self.hintFont:getWidth("Versions") + 24 * s
    local hasGh = m.github and m.github ~= "" and m.updateCheck ~= false
    local info = hasGh and self:_modUpdateInfo(m.id) or nil
    local updLabel = "Check for updates"
    local updateKind = "neutral"
    -- checkLine: always on the mod row for github mods so the check result
    -- is visible without relying on the top-of-panel notice.
    local checkLine = nil
    local checkLineColor = PAL.detail
    if info and info.status == "available" then
      updLabel = "Update"
      updateKind = "accent"
      checkLine = "Checked for updates - v" .. tostring(info.latest) .. " available"
      checkLineColor = PAL.playTop
    elseif info and info.status == "current" then
      updLabel = "Check again"
      checkLine = "Checked for updates - up to date"
      checkLineColor = PAL.playTop
    elseif info and info.status == "error" then
      checkLine = "Checked for updates - failed"
      checkLineColor = PAL.chooseTop
    elseif hasGh then
      checkLine = "Not checked for updates yet"
      checkLineColor = PAL.warning
    end
    local updW = self.hintFont:getWidth(updLabel) + 24 * s
    -- `required_imports`: a base file the mod cannot ship (a Stadium 2
    -- cartridge, another game's ROM).  Until it arrives the mod is installed,
    -- enabled and completely inert, so the card says which file is missing and
    -- offers the button that supplies it -- see src/mods/ModImports.lua.
    local needs = m.missingImports and m.missingImports[1] or nil
    local impLabel = needs and ("Import " .. tostring(needs.entry.name)) or nil
    if impLabel and #impLabel > 34 then impLabel = "Import base file" end
    local impW = impLabel and (self.hintFont:getWidth(impLabel) + 24 * s) or 0
    local needLine = needs and (needs.reason
      or ("Needs " .. tostring(needs.entry.name))) or nil
    -- ...and the other half of that state.  A mod whose base file HAS arrived
    -- just loses the red line and the button, which reads the same as a mod
    -- that never wanted one -- so a player who imported the cartridge for a
    -- second mod (or had it adopted from the shared store without being asked)
    -- had nothing on screen telling them it worked.  Say so.
    -- ...and say WHERE, not just "ready".  A `root = "save"` entry (a shared
    -- 64 MB cartridge) never lands in the mod folder, so a bare "ready" sent
    -- players looking for a file that was never going to be there and reading
    -- the panel as broken.
    local readyLine = nil
    if not needs and m.requiredImports and m.requiredImports[1] then
      local okDesc, line = pcall(function()
        return require("src.mods.ModImports").describe(
          { path = m.manifestPath or ("mods/" .. tostring(m.id)) },
          m.requiredImports[1])
      end)
      readyLine = (okDesc and line)
        or (tostring(m.requiredImports[1].name) .. ": ready")
    end
    -- `required_games`: a CARTRIDGE THE PLAYER MUST HAVE IMPORTED, which is
    -- not a file they can hand over -- so it gets its own line and its own
    -- button, and the button goes to the importer rather than a file picker.
    --
    -- A map pack exported from the map editor is the case this exists for. It
    -- carries maps copied out of another game and REFERENCES that game's
    -- tilesets rather than shipping them, so until that game is imported the
    -- pack is not merely inert: MapLoader asserts on a tileset id that exists
    -- nowhere. Naming the game here is the difference between a two-click fix
    -- and a crash with nothing on screen to explain it.
    local needGame = m.missingGames and m.missingGames[1] or nil
    local gameLabel = needGame and ("Import " .. tostring(needGame.name)) or nil
    if gameLabel and #gameLabel > 34 then gameLabel = "Import game" end
    local gameW = gameLabel and (self.hintFont:getWidth(gameLabel) + 24 * s) or 0
    local gameLine = nil
    if needGame then
      local okA, AT = pcall(require, "src.import.AdoptedTileset")
      -- `already`: this card is describing a mod that IS installed, so the
      -- pre-install ending ("Import those games first, then install this")
      -- tells the reader to redo something they are looking at the result of.
      gameLine = okA and AT.requirementText(m.missingGames, "This mod", true)
        or ("Needs " .. tostring(needGame.name) .. " imported")
    end

    -- "Support the creator": the manifest's `support` link, first in the row
    -- so it is the button a player reads before the maintenance ones.
    local supLabel = (m.support and m.support ~= "") and "Support the creator" or nil
    local supW = supLabel and (self.hintFont:getWidth(supLabel) + 24 * s) or 0
    local btnRowW = delW
    if hasGh then btnRowW = updW + btnGap + verW + btnGap + delW end
    if supLabel then btnRowW = supW + btnGap + btnRowW end
    if impLabel then btnRowW = impW + btnGap + btnRowW end
    if gameLabel then btnRowW = gameW + btnGap + btnRowW end
    -- PER-GENERATION CHIPS, under the switch.
    --
    -- Asked for directly: "a per generation mod selection menu so you can have
    -- mods on for gen1, gen2, or gen3 games selectively".  The switch above
    -- them is still the master -- off is off everywhere -- and these say which
    -- games it reaches while it is on (src/mods/ModGens.lua).
    --
    -- Three tiny pills rather than a second menu: a mod's generations are a
    -- property of the mod, and burying them behind a click would leave the
    -- panel unable to answer "why did this not load" at a glance.
    love.graphics.setFont(self.warningFont)
    local genW = 0
    for _, short in ipairs(ModGens.SHORT) do
      genW = math.max(genW, self.warningFont:getWidth(short) + 12 * s)
    end
    local genGap = 4 * s
    local genH = self.warningFont:getHeight() + 6 * s
    local genRowW = genW * ModGens.COUNT + genGap * (ModGens.COUNT - 1)
    local clusterW = math.max(chipW, tw, genRowW)
    local leftW = math.max(40 * s, innerW - clusterW - 14 * s)
    local descH = 0
    if m.description ~= "" then
      love.graphics.setFont(self.hintFont)
      local _, dl = self.hintFont:getWrap(m.description, leftW)
      descH = math.max(1, #dl) * self.hintFont:getHeight()
    end
    local clusterH = chipH + 6 * s + th + 6 * s + genH
    local metaH = self.hintFont:getHeight() + 2 * s
    if checkLine then
      metaH = metaH + self.hintFont:getHeight() + 2 * s
    end
    if needLine or readyLine then
      metaH = metaH + self.hintFont:getHeight() + 2 * s
    end
    -- WRAPPED, not one line. This sentence names a game and tells the player
    -- what to do about it, and truncating it to the card width would cut off
    -- exactly the half that says what to do.
    local gameLineH = 0
    if gameLine then
      love.graphics.setFont(self.hintFont)
      local _, gl = self.hintFont:getWrap(gameLine, leftW)
      gameLineH = math.max(1, #gl) * self.hintFont:getHeight() + 2 * s
      metaH = metaH + gameLineH
    end
    if descH > 0 then
      metaH = metaH + self.hintFont:getHeight() + 2 * s + descH
    end
    local bodyH = math.max(nameH + 4 * s + metaH, clusterH)
    local cardH = padV * 2 + bodyH + 10 * s + btnH
    layout[i] = { h = cardH, leftW = leftW, clusterW = clusterW,
      genW = genW, genH = genH, genGap = genGap, genRowW = genRowW,
      chipText = chipText, chipW = chipW, delW = delW,
      updW = updW, verW = verW, hasGh = hasGh, clusterH = clusterH,
      btnRowW = btnRowW, bodyH = bodyH, updLabel = updLabel,
      updateKind = updateKind, checkLine = checkLine,
      checkLineColor = checkLineColor,
      needs = needs, impLabel = impLabel, impW = impW, needLine = needLine,
      readyLine = readyLine,
      needGame = needGame, gameLabel = gameLabel, gameW = gameW,
      gameLine = gameLine, gameLineH = gameLineH,
      supLabel = supLabel, supW = supW, support = m.support }
    total = total + cardH
  end
  total = total + (#mods - 1) * cardGap

  -- Paged, the list band is the list itself: nothing to clip, nothing to scroll
  -- here, and the page's scrollbar covers the overflow.
  if paged then listH = total end
  local maxScroll = math.max(0, total - listH)
  self._modMax = maxScroll
  local scroll = clamp(self.modScroll or 0, 0, maxScroll)
  self.modScroll = scroll
  self.modRects = {}
  self.modDeleteRects = {}
  self.modUpdateRects = {}
  self.modVersionsRects = {}
  self.modImportFileRects = {}
  self.modImportGameRects = {}
  self.modSupportRects = {}
  self.modGenRects = {}

  if not paged then
    love.graphics.setScissor(math.floor(x), math.floor(top),
      math.ceil(w), math.ceil(listH))
  end
  local cy = top - scroll
  for i, m in ipairs(mods) do
    local L = layout[i]
    local cardH = L.h
    if cy + cardH >= top and cy <= top + listH then
      roundedCard(x, cy, w, cardH, cardR)
      local nx = x + padH
      local ny = cy + padV

      -- name (ellipsized to leave room for the badge chip) + badge chip
      love.graphics.setFont(self.warningFont)
      local badgeTW = self.warningFont:getWidth(m.badge)
      local badgeW = badgeTW + 12 * s
      local badgeH = self.warningFont:getHeight() + 6 * s
      love.graphics.setFont(self.stateFont)
      col(PAL.ink)
      local drawnName = ellipsize(self.stateFont, m.name, L.leftW - badgeW - 8 * s)
      printB(drawnName, nx, ny)
      local bxx = nx + self.stateFont:getWidth(drawnName) + 8 * s
      local byy = ny + (nameH - badgeH) / 2
      love.graphics.setLineWidth(1)
      col(PAL.cardBorder, 0.5)
      love.graphics.rectangle("line", bxx, byy, badgeW, badgeH, 5 * s, 5 * s)
      love.graphics.setFont(self.warningFont)
      col(m.experimental and PAL.gold or PAL.warning)
      love.graphics.print(m.badge, bxx + 6 * s,
        byy + (badgeH - self.warningFont:getHeight()) / 2)

      -- version + check status line + description under the name
      love.graphics.setFont(self.hintFont)
      col(PAL.detail)
      local metaY = ny + nameH + 4 * s
      love.graphics.print("v" .. tostring(m.version or "?"), nx, metaY)
      metaY = metaY + self.hintFont:getHeight() + 2 * s
      if L.checkLine then
        col(L.checkLineColor or PAL.detail)
        love.graphics.print(
          ellipsize(self.hintFont, L.checkLine, L.leftW), nx, metaY)
        metaY = metaY + self.hintFont:getHeight() + 2 * s
      end
      if L.needLine then
        col(PAL.chooseTop)
        love.graphics.print(
          ellipsize(self.hintFont, L.needLine, L.leftW), nx, metaY)
        metaY = metaY + self.hintFont:getHeight() + 2 * s
      elseif L.readyLine then
        col(PAL.detail)
        love.graphics.print(
          ellipsize(self.hintFont, L.readyLine, L.leftW), nx, metaY)
        metaY = metaY + self.hintFont:getHeight() + 2 * s
      end
      -- PRINTF, NOT ELLIPSIZE, unlike every other line on this card.
      --
      -- The lines above are status ("Checked for updates"), where the first
      -- few words carry it and a tail cut off costs nothing. This one names a
      -- cartridge AND says what to do about it, and the instruction is at the
      -- end -- ellipsized, the player is told there is a problem and not how
      -- to fix it, which is the half worth keeping.
      if L.gameLine then
        col(PAL.chooseTop)
        love.graphics.printf(L.gameLine, nx, metaY, L.leftW, "left")
        metaY = metaY + (L.gameLineH or (self.hintFont:getHeight() + 2 * s))
      end
      if m.description ~= "" then
        col(PAL.detail)
        love.graphics.printf(m.description, nx, metaY, L.leftW, "left")
      end

      -- right cluster: status chip + toggle (action buttons are a bottom row)
      local clusterX = x + w - padH - L.clusterW
      local clusterY = cy + padV
      local _, chipColor = modStatusChip(m.status)
      local chipX = clusterX + (L.clusterW - L.chipW) / 2
      col(chipColor, 0.1)
      love.graphics.rectangle("fill", chipX, clusterY, L.chipW, chipH, chipH / 2, chipH / 2)
      love.graphics.setLineWidth(1)
      col(chipColor, 0.55)
      love.graphics.rectangle("line", chipX, clusterY, L.chipW, chipH, chipH / 2, chipH / 2)
      love.graphics.setFont(self.hintFont)
      col(chipColor)
      printfB(L.chipText, chipX,
        clusterY + (chipH - self.hintFont:getHeight()) / 2, L.chipW, "center")

      -- toggle switch (ON = green gradient + glow, knob right; OFF = gray, left)
      local tx = clusterX + (L.clusterW - tw) / 2
      local ty = clusterY + chipH + 6 * s
      local rr = th / 2
      local trect = { x = tx - 6 * s, y = ty - 6 * s,
        width = tw + 12 * s, height = th + 12 * s, id = m.id }
      self:_hover(trect)
      if m.enabled then
        neonGlow(tx, ty, tw, th, rr, PAL.green, 0.45)
        fillGradRounded(tx, ty, tw, th, rr, PAL.playTop, PAL.playBot, 1, 1)
      else
        col(PAL.disabled, 0.35)
        love.graphics.rectangle("fill", tx, ty, tw, th, rr, rr)
      end
      local kd = th - 6 * s
      local kcx = m.enabled and (tx + tw - 3 * s - kd / 2) or (tx + 3 * s + kd / 2)
      col(PAL.white)
      love.graphics.circle("fill", kcx, ty + th / 2, kd / 2)

      -- ...and the three generation chips under it.  A chip is LIT only when
      -- the mod is on AND that generation is ticked, because a lit chip over a
      -- dead switch would be claiming the mod loads somewhere it does not;
      -- ticked-but-master-off draws as an outline, so the selection is still
      -- readable while the mod is parked.
      local gx2 = clusterX + (L.clusterW - L.genRowW) / 2
      local gy2 = ty + th + 6 * s
      local gens = m.gens or { true, true, true }
      -- A CHIP THE MOD SAYS IT CANNOT FILL.  `supportedGens` is the manifest's
      -- own claim; a chip outside it is not something the player can usefully
      -- tick, because the loader will not load the mod there -- so it draws
      -- dead rather than lit, and a lie is not what a green chip should be.
      -- Overrule the claim (ModGens.forced, behind the confirm in
      -- _toggleModGeneration) and it lights GOLD instead of green: on, and on
      -- somewhere the author did not promise.
      local declared = m.supportedGens
      local forcedGens = m.forcedGens or {}
      for gi = 1, ModGens.COUNT do
        local ticked = gens[gi] ~= false
        local live = ticked and m.enabled
        local claimed = true
        if declared then
          claimed = false
          for _, n in ipairs(declared) do
            if tonumber(n) == gi then claimed = true break end
          end
        end
        local blocked = (not claimed) and not forcedGens[gi]
        if blocked then live = false end
        local hue = claimed and PAL.green or PAL.gold
        local edge = blocked and PAL.disabled or hue
        local shown = ticked and not blocked
        local grect = { x = gx2, y = gy2, width = L.genW, height = L.genH,
                        id = m.id, gen = gi }
        self:_hover(grect)
        local rr2 = L.genH / 2
        if live then
          col(hue, 0.85)
          love.graphics.rectangle("fill", gx2, gy2, L.genW, L.genH, rr2, rr2)
        else
          col(PAL.cardBorder, shown and 0.30 or 0.12)
          love.graphics.rectangle("fill", gx2, gy2, L.genW, L.genH, rr2, rr2)
          love.graphics.setLineWidth(1)
          col(shown and edge or PAL.disabled, shown and 0.7 or 0.4)
          love.graphics.rectangle("line", gx2, gy2, L.genW, L.genH, rr2, rr2)
        end
        love.graphics.setFont(self.warningFont)
        col(live and PAL.slotBg or (shown and edge or PAL.disabled))
        printfB(ModGens.SHORT[gi], gx2,
          gy2 + (L.genH - self.warningFont:getHeight()) / 2, L.genW, "center")
        local gvy = math.max(grect.y, top)
        local gvy2 = math.min(grect.y + grect.height, top + listH)
        if gvy2 > gvy then
          self.modGenRects[#self.modGenRects + 1] =
            { x = grect.x, y = gvy, width = grect.width,
              height = gvy2 - gvy, id = m.id, gen = gi }
        end
        gx2 = gx2 + L.genW + L.genGap
      end

      -- Action chip-buttons in one right-aligned row under the body
      local btnY = cy + cardH - padV - btnH
      local btnX = x + w - padH - L.btnRowW
      local darmed = armedDelete(self._confirmDelete, "mod", m.id, nil)
      local function clipHit(rect, bucket)
        if not rect then return end
        local vy = math.max(rect.y, top)
        local vy2 = math.min(rect.y + rect.height, top + listH)
        if vy2 > vy then
          bucket[#bucket + 1] = {
            x = rect.x, y = vy, width = rect.width, height = vy2 - vy,
            id = rect.id,
          }
        end
      end
      if L.supLabel then
        local srect = self:_chipButton(btnX, btnY, L.supLabel, {
          w = L.supW, h = btnH, id = m.id, kind = "accent",
        })
        local before = #self.modSupportRects
        clipHit(srect, self.modSupportRects)
        if #self.modSupportRects > before then
          self.modSupportRects[#self.modSupportRects].url = L.support
        end
        btnX = btnX + L.supW + btnGap
      end
      if L.impLabel then
        local irect = self:_chipButton(btnX, btnY, L.impLabel, {
          w = L.impW, h = btnH, id = m.id, kind = "accent",
        })
        clipHit(irect, self.modImportFileRects)
        btnX = btnX + L.impW + btnGap
      end
      if L.gameLabel then
        local grect = self:_chipButton(btnX, btnY, L.gameLabel, {
          w = L.gameW, h = btnH, id = m.id, kind = "accent",
        })
        -- The version travels on the rect: the handler opens the importer for
        -- THIS cartridge, and a card for a mod needing Blue must not send the
        -- player to whatever game the panel happened to have selected.
        grect.version = L.needGame and L.needGame.version or nil
        clipHit(grect, self.modImportGameRects)
        btnX = btnX + L.gameW + btnGap
      end
      if L.hasGh then
        local urect = self:_chipButton(btnX, btnY, L.updLabel, {
          w = L.updW, h = btnH, id = m.id, kind = L.updateKind or "neutral",
        })
        clipHit(urect, self.modUpdateRects)
        btnX = btnX + L.updW + btnGap
        local vrect = self:_chipButton(btnX, btnY, "Versions", {
          w = L.verW, h = btnH, id = m.id, kind = "neutral",
        })
        clipHit(vrect, self.modVersionsRects)
        btnX = btnX + L.verW + btnGap
      end
      local drect = self:_chipButton(btnX, btnY, darmed and "Sure?" or "Delete", {
        w = L.delW, h = btnH, id = m.id,
        kind = darmed and "dangerArmed" or "danger",
      })
      clipHit(drect, self.modDeleteRects)

      -- toggle hit rect clipped to the visible list band
      local vy = math.max(trect.y, top)
      local vy2 = math.min(trect.y + trect.height, top + listH)
      if vy2 > vy then
        self.modRects[#self.modRects + 1] =
          { x = trect.x, y = vy, width = trect.width, height = vy2 - vy, id = m.id }
      end
    end
    cy = cy + cardH + cardGap
  end
  if not paged then love.graphics.setScissor() end

  -- thin scrollbar thumb when the list overflows
  if maxScroll > 0 then
    local thumbH = math.max(24 * s, listH * (listH / total))
    local thumbY = top + (listH - thumbH) * (scroll / maxScroll)
    col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", x + w - 3 * s, thumbY, 3 * s, thumbH, 1.5 * s, 1.5 * s)
  end
  return (top - y) + total
end

-- ------- FIND MODS: browsing a community mod index -------------------------
--
-- The index is metadata only (src/mods/ModIndex.lua): it says where a mod's
-- zip lives, and the install runs through exactly the same path "Import mod
-- .zip" does.  Nothing here is automatic -- no index ships with the launcher,
-- and the tab stays an empty "Add an index" prompt until the player names one,
-- because subscribing to somebody's list of mods is a trust decision and not a
-- default.
--
-- Fetching is the same synchronous curl the update checks already use, cached
-- in options for a day, so the first open of the tab costs one round trip and
-- every later one is free until the player hits Refresh.

-- The sources list, reloaded from options.  Cheap; called whenever the panel
-- has reason to think the list changed.
function RomImporter:_refreshFindSources()
  local ModIndex = require("src.mods.ModIndex")
  local ok, rows = pcall(ModIndex.sources)
  self.findSources = ok and rows or {}
end

-- Fetch every source and merge into one listing.  First source wins on a
-- duplicate id, matching how the mod loader resolves two mods with one id --
-- there is one "nuzlocke" as far as the installer is concerned, so the panel
-- must not offer two.  Per-source failures are collected rather than fatal: an
-- index that is down should cost its own rows, not everybody else's.
function RomImporter:_refreshFind(force)
  local ModIndex = require("src.mods.ModIndex")
  self:_refreshFindSources()
  local mods, seen, cats, catSeen, errs = {}, {}, {}, {}, {}
  local stale, oldest = false, nil
  for _, source in ipairs(self.findSources or {}) do
    local ok, index, err, meta = pcall(function()
      return ModIndex.fetch(source, { force = force == true })
    end)
    if not ok then
      errs[#errs + 1] = (source.label or source.feed) .. ": " .. tostring(index)
    elseif not index then
      errs[#errs + 1] = (source.label or source.feed) .. ": " .. tostring(err)
    else
      if meta and meta.stale then stale = true end
      if meta and meta.checkedAt then
        oldest = math.min(oldest or meta.checkedAt, meta.checkedAt)
      end
      for _, entry in ipairs(index.mods or {}) do
        if not seen[entry.id] then
          seen[entry.id] = true
          entry._source = source.label or source.feed
          entry._base = source.base
          mods[#mods + 1] = entry
        end
      end
      for _, c in ipairs(ModIndex.categoriesIn(index)) do
        if not catSeen[c] then catSeen[c] = true; cats[#cats + 1] = c end
      end
    end
  end
  self.findIndex = { mods = mods, categories = cats, stale = stale,
                     checkedAt = oldest }
  self.findLoaded = true
  if #errs > 0 then
    self.findNotice = { ok = false, text = table.concat(errs, "  -  ") }
  elseif force then
    self.findNotice = { ok = true,
      text = Strings("Refreshed - %d mods listed", #mods) }
  end
  -- A category that no longer exists after a refresh would filter everything
  -- away with no way back except guessing.
  if self.findCategory and not catSeen[self.findCategory] then
    self.findCategory = nil
  end
end

function RomImporter:_ensureFind()
  if not self.findLoaded then
    self:_refreshFindSources()
    if #(self.findSources or {}) == 0 then
      -- Nothing to fetch, but the panel is loaded: the empty state is the
      -- answer, not a pending request.
      self.findIndex = { mods = {}, categories = {} }
      self.findLoaded = true
    else
      self:_refreshFind(false)
    end
  end
end

-- The rows the filters leave, and the installed-mod context the compatibility
-- warnings are judged against.
function RomImporter:_findRows()
  local ModIndex = require("src.mods.ModIndex")
  local all = (self.findIndex and self.findIndex.mods) or {}
  return ModIndex.filter(all, {
    query = self.findQuery,
    category = self.findCategory,
  })
end

function RomImporter:_findInstalledMap()
  local map = {}
  for _, m in ipairs(self.mods or {}) do map[m.id] = m.version or true end
  return map
end

-- One thumbnail per frame, and only for a card actually on screen: the fetch
-- is a blocking curl, so downloading a whole listing's worth on open would
-- stall the launcher for as many seconds as there are mods.  A failure is
-- remembered as `false` so a broken URL is tried once, not every frame.
function RomImporter:_findThumb(entry)
  self._findThumbs = self._findThumbs or {}
  local cached = self._findThumbs[entry.id]
  if cached ~= nil then return cached or nil end
  if self._findThumbFetched then return nil end   -- budget spent this frame
  local ModIndex = require("src.mods.ModIndex")
  local url = ModIndex.joinUrl(entry._base, entry.thumbnail)
  if not url then
    self._findThumbs[entry.id] = false
    return nil
  end
  self._findThumbFetched = true
  local ok, image = pcall(function()
    local path, err = ModIndex.downloadThumbnail(url, entry.id)
    if not path then error(err or "download failed", 0) end
    return love.graphics.newImage(path)
  end)
  self._findThumbs[entry.id] = ok and image or false
  return ok and image or nil
end

-- Open the "add an index" text prompt.  Deliberately a typed URL rather than a
-- picked-from-a-list affair: there is no blessed index, and presenting one
-- would make the launcher's choice look like an endorsement.
function RomImporter:_promptAddIndex()
  self._indexPrompt = { text = "" }
  self:_armTextInput()
end

function RomImporter:_commitAddIndex()
  local prompt = self._indexPrompt
  self._indexPrompt = nil
  self:_disarmTextInput()
  if not prompt then return end
  local ModIndex = require("src.mods.ModIndex")
  local row, err = ModIndex.addSource(prompt.text or "")
  if not row then
    self.findNotice = { ok = false, text = tostring(err) }
    return
  end
  self.findNotice = { ok = true, text = Strings("Added %s", row.label or row.feed) }
  self.findLoaded = false
  self:_ensureFind()
end

function RomImporter:_removeIndex(feed)
  local ModIndex = require("src.mods.ModIndex")
  local ok, err = ModIndex.removeSource(feed)
  if not ok then
    self.findNotice = { ok = false, text = tostring(err) }
    return
  end
  self.findNotice = { ok = true, text = Strings("Index removed") }
  self.findLoaded = false
  self:_ensureFind()
end

-- Fetch and show an entry's description markdown.  Loaded on demand, never
-- with the listing: a feed of any size would otherwise be one request per mod.
function RomImporter:_findShowDetails(entry)
  local ModIndex = require("src.mods.ModIndex")
  local url = ModIndex.joinUrl(entry._base, entry.description_url)
  local body = entry.summary or ""
  if url then
    local ok, text = pcall(ModIndex.fetchText, url)
    if ok and type(text) == "string" and text ~= "" then body = text end
  end
  self._findDetails = {
    title = entry.title or entry.id,
    body = body,
    scroll = 0,
  }
end

-- Arm the install confirm.  The compatibility list is the whole point of the
-- dialog: the panel deliberately does not hide an incompatible mod (an index
-- entry can be months stale, and a hidden mod looks like a missing one), so
-- this is where the player is told what the author declared before anything
-- is downloaded.
function RomImporter:_findConfirmInstall(entry)
  local ModIndex = require("src.mods.ModIndex")
  local Version = require("src.core.Version")
  local url, why = ModIndex.installUrl(entry)
  if not url then
    self.findNotice = { ok = false,
      text = (entry.title or entry.id) .. ": " .. tostring(why) }
    return
  end
  local installed = self:_findInstalledMap()
  local issues = ModIndex.compatIssues(entry, {
    modApi = Version.modApi,
    engineVersion = Version.engine,
    installed = installed,
  })
  local version = ModIndex.displayVersion(entry)
  local lines = { (entry.title or entry.id) .. " v" .. tostring(version) }
  if entry.author then lines[#lines + 1] = "by " .. entry.author end
  local have = installed[entry.id]
  if have then
    lines[#lines + 1] = "Replaces installed v" .. tostring(have)
  end
  for _, issue in ipairs(issues) do
    lines[#lines + 1] = "! " .. issue.text
  end
  lines[#lines + 1] = "Mods are not reviewed - trust the author."
  self._modConfirm = {
    kind = (#issues > 0) and "warn" or "update",
    indexEntry = entry,
    title = have and "Reinstall mod" or "Install mod",
    yesLabel = have and "Reinstall" or "Install",
    lines = lines,
  }
end

function RomImporter:_findInstall(entry)
  local name = entry.title or entry.id
  self.findNotice = { ok = true, text = Strings("Downloading %s...", name) }
  local ran, err = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    local ok, res, mismatch = LauncherMods.installFromIndex(entry)
    if ok then
      -- The installed list is what the Install / Installed labels read, so it
      -- has to be re-derived before the next paint or the card lies.
      pcall(self._refreshMods, self)
      self.findNotice = mismatch
        and { ok = false, text = name .. ": " .. mismatch }
        or { ok = true, text = Strings("Installed %s %s", name, tostring(res)) }
    else
      self.findNotice = { ok = false, text = tostring(res) }
    end
  end)
  if not ran then
    self.findNotice = { ok = false, text = "Install failed: " .. tostring(err) }
  end
end

-- The label + colour for an entry's install state, given what is installed.
local function findActionFor(entry, installedVersion)
  local ModIndex = require("src.mods.ModIndex")
  if not ModIndex.canInstall(entry) then
    return nil, "Not installable from this index"
  end
  if not installedVersion then return "Install", nil end
  local listed = ModIndex.displayVersion(entry)
  local ModUpdate = require("src.mods.ModUpdate")
  if type(installedVersion) == "string"
      and ModUpdate.isNewer(installedVersion, listed) then
    return "Update", "Installed v" .. installedVersion
  end
  return "Reinstall", "Installed v" .. tostring(installedVersion)
end

-- FIND MODS panel.  Header ("Find Mods" + count + Refresh / Add an index),
-- notice line, the source list, a search field and category chips, then the
-- listing.  With no index added at all it collapses to a single dashed prompt.
-- `paged` behaves as everywhere else: no inner scroll region, the list is drawn
-- whole, and the returned natural height is what draw() measures the page on.
-- The settings list: one row per option, `LABEL   < VALUE >`.
--
-- Both arrows are hit rects and so is the value between them, because on a
-- touch screen a 12px chevron is not a target. Clicking the value steps it
-- forward, which is the same thing the in-game menu's A button does.
function RomImporter:_drawSettingsPanel(x, y, w, h, paged)
  local s = self._s
  local GenOptions = require("src.core.GenOptions")
  self.settingsRowRects = {}

  -- Built once per entry into the tab, not once per frame: reading every
  -- installed mod's schema file is disk work, and at sixty frames a second on
  -- a folder of mods it is disk work the whole time the screen is open.
  if not self._settingsRowCache then
    self._settingsRowCache = self:_settingsRows()
  end
  local entries = self._settingsRowCache

  love.graphics.setFont(self.gameNameFont)
  col(PAL.ink)
  printB(self.settingsPage == "launcher" and Strings("Launcher settings")
                                          or Strings("Settings"), x, y)
  local top = y + self.gameNameFont:getHeight() + 10 * s

  -- WHAT JUST HAPPENED, under the title.  This line has been set by the
  -- settings code for as long as it has existed and was never drawn, so a
  -- player who pressed a row that could only answer in words -- a mod's text
  -- option, and now every game-data folder outcome -- got no answer at all.
  -- Measured rather than assumed one line: a folder path is longer than the
  -- drawer is wide.
  if self.settingsNotice then
    love.graphics.setFont(self.hintFont)
    col(PAL.link)
    local text = Strings(tostring(self.settingsNotice))
    local _, lines = self.hintFont:getWrap(text, w)
    printfB(text, x, top, w, "left")
    top = top + math.max(1, #lines) * self.hintFont:getHeight() + 8 * s
  end

  local rowH = 34 * s
  local cy = top
  for _, entry in ipairs(entries) do
    if entry.kind == "section" then
      -- A little air above a heading, none above the first one.
      if cy > top then cy = cy + 10 * s end
      love.graphics.setFont(self.hintFont)
      -- A section with no label is a note on its own -- the theme's one-line
      -- description under the APPEARANCE rows.  It gets the text and neither
      -- the heading nor the rule, because both would announce a section that
      -- has no rows in it.
      local titled = entry.label ~= nil and entry.label ~= ""
      if titled then
        col(PAL.heading)
        printB(Strings(entry.label), x, cy)
        cy = cy + self.hintFont:getHeight() + 4 * s
      end
      if entry.note then
        col(PAL.warning)
        local _, lines = self.hintFont:getWrap(Strings(entry.note), w)
        printfB(Strings(entry.note), x, cy, w, "left")
        cy = cy + math.max(1, #lines) * self.hintFont:getHeight() + 4 * s
      end
      if titled then
        col(PAL.cardBorder, 0.35)
        love.graphics.rectangle("fill", x, cy, w, 1)
        cy = cy + 8 * s
      end

    elseif entry.kind == "action" then
      col(PAL.cardBlue, 0.55)
      love.graphics.rectangle("fill", x, cy, w, rowH - 4 * s, 6 * s, 6 * s)
      love.graphics.setFont(self.hintFont)
      col(PAL.heading)
      printB(Strings(entry.label), x + 12 * s, cy + 9 * s)
      local vW = self.hintFont:getWidth(entry.value)
      col(PAL.link)
      printB(entry.value, x + w - 12 * s - vW, cy + 9 * s)
      -- The whole row is the hit target. An action has no left/right arrows to
      -- aim at, and a 40px word on the far side of a full-width plate is a
      -- worse target than the plate.
      self.settingsRowRects[#self.settingsRowRects + 1] = {
        entry = entry,
        value = { x = x, y = cy, width = w, height = rowH - 4 * s },
      }
      cy = cy + rowH
      -- An action can carry its own explanation -- where games are being
      -- installed, what USE SHARED VALUES is about to undo.  Under the plate
      -- rather than in the section heading, because the sentence is about
      -- THAT button and a heading two rows up is not read as being about it.
      if entry.note then
        love.graphics.setFont(self.hintFont)
        col(PAL.warning)
        local _, lines = self.hintFont:getWrap(Strings(entry.note), w)
        printfB(Strings(entry.note), x, cy, w, "left")
        cy = cy + math.max(1, #lines) * self.hintFont:getHeight() + 6 * s
      end

    else
      col(PAL.cardBlue, 0.55)
      love.graphics.rectangle("fill", x, cy, w, rowH - 4 * s, 6 * s, 6 * s)

      love.graphics.setFont(self.hintFont)
      col(PAL.heading)
      printB(Strings(entry.label), x + 12 * s, cy + 9 * s)

      local value = self:_entryLabel(entry)
      -- A DOT MEANS "THIS GENERATION ONLY".  Without it the rows look
      -- identical whether the value on screen is the shared one or an override
      -- only Gen 1 reads, and the first way a player finds out which is by
      -- wondering why Emerald ignored a setting they watched themselves change.
      local overridden = entry.scope == "game" and entry.gen
        and GenOptions.hasOverride(self:_settings(), entry.row.id, entry.gen)
      if overridden then value = value .. " *" end
      local vW = self.hintFont:getWidth(value)
      local arrowW = 22 * s
      local rightPad = 12 * s
      local vX = x + w - rightPad - arrowW - vW - 10 * s
      local leftX = vX - arrowW - 4 * s

      col(PAL.link)
      printB("<", leftX + 6 * s, cy + 9 * s)
      printB(">", vX + vW + 14 * s, cy + 9 * s)
      col(PAL.ink)
      printB(value, vX, cy + 9 * s)

      -- `width`/`height`, never `w`/`h`: `inside` reads only those two names,
      -- and the short spelling here is a nil arithmetic on the next click
      -- anywhere in the launcher. Deliberately NOT pinned -- these ride the
      -- scrolling page, so the band should stop them answering off screen.
      self.settingsRowRects[#self.settingsRowRects + 1] = {
        entry = entry,
        left = { x = leftX, y = cy, width = arrowW + 10 * s, height = rowH - 4 * s },
        right = { x = vX + vW + 6 * s, y = cy,
                  width = arrowW + rightPad, height = rowH - 4 * s },
        value = { x = vX - 4 * s, y = cy, width = vW + 8 * s, height = rowH - 4 * s },
      }
      cy = cy + rowH
    end
  end

  return (cy - y) + 8 * s
end

function RomImporter:_drawFindPanel(x, y, w, h, paged)
  local s = self._s
  self._findThumbFetched = false
  self:_ensureFind()
  self:_ensureMods()
  local ModIndex = require("src.mods.ModIndex")
  local sources = self.findSources or {}
  local rows = self:_findRows()
  local total = #((self.findIndex and self.findIndex.mods) or {})

  self.findCatRects = {}
  self.findInstallRects = {}
  self.findDetailRects = {}
  self.findRepoRects = {}
  self.findSourceRemoveRects = {}

  -- header
  love.graphics.setFont(self.gameNameFont)
  col(PAL.ink)
  printB("Find Mods", x, y)
  local nameW = self.gameNameFont:getWidth("Find Mods")
  local headerH = self.gameNameFont:getHeight()
  if #sources > 0 then
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    local countLabel = (#rows == total)
      and Strings("%d mods listed", total)
      or Strings("%d of %d mods", #rows, total)
    love.graphics.print(countLabel, x + nameW + 14 * s,
      y + (headerH - self.hintFont:getHeight()) / 2)
  end

  local btnH = math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s)
  local btnY = y + (headerH - btnH) / 2
  local addLabel = (#sources == 0) and "Add an index" or "Add index"
  local addW = math.min(w * 0.45, self.saveBtnFont:getWidth(addLabel) + 40 * s)
  local addX = x + w - addW
  self.findAddRect =
    self:_glassyButton(addX, btnY, addW, btnH, addLabel, self.saveBtnFont, true)
  if #sources > 0 then
    local refLabel = "Refresh"
    local refW = math.min(w * 0.3, self.saveBtnFont:getWidth(refLabel) + 36 * s)
    self.findRefreshRect = self:_glassyButton(addX - refW - 8 * s, btnY,
      refW, btnH, refLabel, self.saveBtnFont, true)
  end

  local top = y + headerH + 14 * s

  -- notice line: the last add / refresh / install result, else the standing
  -- reminder that a listing is not a review
  love.graphics.setFont(self.hintFont)
  if self.findNotice then
    col(self.findNotice.ok and PAL.green or PAL.red)
    love.graphics.printf(self.findNotice.text, x, top, w, "left")
  else
    col(PAL.warning)
    love.graphics.printf(
      Strings("Mods here are listed, not reviewed - read the source and trust the author."),
      x, top, w, "left")
  end
  top = top + self.hintFont:getHeight() + 12 * s

  -- no index: one dashed prompt and nothing else.  This is the whole tab until
  -- the player names a feed.
  if #sources == 0 then
    local boxH = 150 * s
    love.graphics.setLineWidth(math.max(1, 1 * s))
    col(PAL.cardBorder, 0.45)
    dashedRoundRect(x, top, w, boxH, 14 * s, 7 * s, 5 * s)
    love.graphics.setFont(self.stateFont)
    col(PAL.heading)
    printfB(Strings("No mod index added"), x + 16 * s, top + boxH / 2
      - self.stateFont:getHeight(), w - 32 * s, "center")
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    love.graphics.printf(
      Strings("Add an index to browse mods. An index is a published list; paste its URL or its owner/repo."),
      x + 24 * s, top + boxH / 2 + 4 * s, w - 48 * s, "center")
    self._findMax = 0
    return (top - y) + boxH
  end

  -- source rows: which indexes are feeding this list, each with a Remove
  local srcH = self.hintFont:getHeight() + 10 * s
  for _, source in ipairs(sources) do
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    local remW = self.hintFont:getWidth("Remove") + 20 * s
    love.graphics.print(
      ellipsize(self.hintFont, source.label or source.feed, w - remW - 20 * s),
      x + 2 * s, top + 5 * s)
    local rrect = self:_chipButton(x + w - remW, top, "Remove", {
      w = remW, h = srcH, id = source.feed, kind = "danger",
    })
    self.findSourceRemoveRects[#self.findSourceRemoveRects + 1] = rrect
    top = top + srcH + 4 * s
  end
  top = top + 6 * s

  -- search field: click to focus, type to filter.  Not a modal -- the results
  -- have to move while the player types or the field is guesswork.
  local fieldH = 30 * s
  local focused = self._findSearchFocus == true
  col(PAL.bgBot, 0.9)
  love.graphics.rectangle("fill", x, top, w, fieldH, 8 * s, 8 * s)
  love.graphics.setLineWidth(math.max(1, s))
  col(focused and PAL.green or PAL.cardBorder, focused and 0.7 or 0.45)
  love.graphics.rectangle("line", x, top, w, fieldH, 8 * s, 8 * s)
  love.graphics.setFont(self.detailFont)
  local query = self.findQuery or ""
  if query == "" and not focused then
    col(PAL.disabledInk)
    love.graphics.print(Strings("Search mods"), x + 10 * s,
      top + (fieldH - self.detailFont:getHeight()) / 2)
  else
    col(PAL.heading)
    local shown = ellipsize(self.detailFont, query, w - 20 * s)
    love.graphics.print(shown, x + 10 * s,
      top + (fieldH - self.detailFont:getHeight()) / 2)
    if focused and (self.pulse * 2 % 1) < 0.5 then
      col(PAL.green)
      love.graphics.rectangle("fill",
        x + 10 * s + self.detailFont:getWidth(shown) + 2 * s,
        top + 6 * s, math.max(1, 1.5 * s), fieldH - 12 * s)
    end
  end
  self.findSearchRect = { x = x, y = top, width = w, height = fieldH }
  self:_hover(self.findSearchRect)
  top = top + fieldH + 10 * s

  -- category chips: "All" plus whatever the feeds actually use
  local cats = (self.findIndex and self.findIndex.categories) or {}
  if #cats > 0 then
    local chipH = self.hintFont:getHeight() + 8 * s
    local cx, cy = x, top
    local function catChip(label, id, active)
      local cw = self.hintFont:getWidth(label) + 20 * s
      if cx + cw > x + w and cx > x then
        cx = x
        cy = cy + chipH + 6 * s
      end
      local rect = { x = cx, y = cy, width = cw, height = chipH, id = id }
      local hot = self:_hover(rect)
      col(active and PAL.green or PAL.cardBorder, active and 0.18 or 0.10)
      love.graphics.rectangle("fill", cx, cy, cw, chipH, chipH / 2, chipH / 2)
      love.graphics.setLineWidth(1)
      col(active and PAL.green or PAL.cardBorder, active and 0.6 or 0.35)
      love.graphics.rectangle("line", cx, cy, cw, chipH, chipH / 2, chipH / 2)
      love.graphics.setFont(self.hintFont)
      col(active and PAL.green or (hot and PAL.heading or PAL.detail))
      printfB(label, cx, cy + (chipH - self.hintFont:getHeight()) / 2, cw, "center")
      self.findCatRects[#self.findCatRects + 1] = rect
      cx = cx + cw + 6 * s
    end
    catChip("All", "", self.findCategory == nil)
    for _, c in ipairs(cats) do
      catChip(c, c, self.findCategory == c)
    end
    top = cy + chipH + 12 * s
  end

  local listH = math.max(0, (y + h) - top)

  if #rows == 0 then
    local boxH = paged and (110 * s) or math.min(listH, 110 * s)
    love.graphics.setLineWidth(math.max(1, 1 * s))
    col(PAL.cardBorder, 0.45)
    dashedRoundRect(x, top, w, boxH, 14 * s, 7 * s, 5 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    local hint = (total == 0)
      and Strings("This index lists no mods yet.")
      or Strings("No mods match that search.")
    love.graphics.printf(hint, x + 16 * s,
      top + boxH / 2 - self.hintFont:getHeight() / 2, w - 32 * s, "center")
    self._findMax = 0
    return (top - y) + boxH
  end

  -- card metrics.  The thumbnail column is fixed whether or not a given entry
  -- has one, so rows stay aligned down the list.
  local padH, padV = 16 * s, 14 * s
  local cardGap, cardR = 10 * s, 14 * s
  local thumbW = 64 * s
  local innerW = w - 2 * padH
  local chipH = self.hintFont:getHeight() + 8 * s
  local rowBtnH = self.hintFont:getHeight() + 10 * s
  local btnGap = 8 * s
  local installed = self:_findInstalledMap()

  love.graphics.setFont(self.stateFont)
  local nameH = self.stateFont:getHeight()

  local layout, totalH = {}, 0
  for i, entry in ipairs(rows) do
    local action, note = findActionFor(entry, installed[entry.id])
    local detW = self.hintFont:getWidth("Details") + 24 * s
    local repoW = entry.repo and (self.hintFont:getWidth("Source") + 24 * s) or 0
    local actW = action and (self.hintFont:getWidth(action) + 24 * s) or 0
    local btnRowW = detW
    if repoW > 0 then btnRowW = btnRowW + btnGap + repoW end
    if actW > 0 then btnRowW = btnRowW + btnGap + actW end
    local leftX = thumbW + 12 * s
    local textW = math.max(60 * s, innerW - leftX)
    local summaryH = 0
    if entry.summary ~= "" then
      local _, sl = self.hintFont:getWrap(entry.summary, textW)
      summaryH = math.max(1, #sl) * self.hintFont:getHeight()
    end
    local metaH = self.hintFont:getHeight() + 2 * s   -- version + author
    if note then metaH = metaH + self.hintFont:getHeight() + 2 * s end
    if summaryH > 0 then metaH = metaH + 2 * s + summaryH end
    local bodyH = math.max(nameH + 4 * s + metaH, thumbW)
    local cardH = padV * 2 + bodyH + 10 * s + rowBtnH
    layout[i] = { h = cardH, textW = textW, leftX = leftX, action = action,
      note = note, detW = detW, repoW = repoW, actW = actW,
      btnRowW = btnRowW, summaryH = summaryH }
    totalH = totalH + cardH
  end
  totalH = totalH + (#rows - 1) * cardGap

  if paged then listH = totalH end
  local maxScroll = math.max(0, totalH - listH)
  self._findMax = maxScroll
  local scroll = clamp(self.findScroll or 0, 0, maxScroll)
  self.findScroll = scroll

  if not paged then
    love.graphics.setScissor(math.floor(x), math.floor(top),
      math.ceil(w), math.ceil(listH))
  end
  local cy = top - scroll
  for i, entry in ipairs(rows) do
    local L = layout[i]
    local cardH = L.h
    if cy + cardH >= top and cy <= top + listH then
      roundedCard(x, cy, w, cardH, cardR)
      local nx = x + padH
      local ny = cy + padV

      -- thumbnail, or a placeholder tile so the text column never shifts
      local image = self:_findThumb(entry)
      if image then
        local iw, ih = image:getDimensions()
        local fit = math.min(thumbW / iw, thumbW / ih)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, nx + (thumbW - iw * fit) / 2,
          ny + (thumbW - ih * fit) / 2, 0, fit, fit)
      else
        col(PAL.cardBorder, 0.18)
        love.graphics.rectangle("fill", nx, ny, thumbW, thumbW, 8 * s, 8 * s)
        love.graphics.setFont(self.warningFont)
        col(PAL.disabledInk)
        printfB("MOD", nx, ny + (thumbW - self.warningFont:getHeight()) / 2,
          thumbW, "center")
      end

      local tx = nx + L.leftX
      love.graphics.setFont(self.stateFont)
      col(PAL.ink)
      printB(ellipsize(self.stateFont, entry.title or entry.id, L.textW), tx, ny)

      love.graphics.setFont(self.hintFont)
      col(PAL.detail)
      local metaY = ny + nameH + 4 * s
      local meta = "v" .. tostring(ModIndex.displayVersion(entry))
      if entry.author then meta = meta .. "  -  " .. entry.author end
      if entry.categories[1] then meta = meta .. "  -  " .. entry.categories[1] end
      love.graphics.print(ellipsize(self.hintFont, meta, L.textW), tx, metaY)
      metaY = metaY + self.hintFont:getHeight() + 2 * s
      if L.note then
        col(PAL.playTop)
        love.graphics.print(ellipsize(self.hintFont, L.note, L.textW), tx, metaY)
        metaY = metaY + self.hintFont:getHeight() + 2 * s
      end
      if L.summaryH > 0 then
        col(PAL.detail)
        love.graphics.printf(entry.summary, tx, metaY + 2 * s, L.textW, "left")
      end

      -- An entry the index could not resolve a download for still shows: a
      -- broken upstream is worth seeing, and hiding it reads as "no such mod".
      if not L.action then
        local warnChipW = self.hintFont:getWidth("Unavailable") + 20 * s
        local wx = x + w - padH - warnChipW
        col(PAL.gold, 0.1)
        love.graphics.rectangle("fill", wx, cy + padV, warnChipW, chipH,
          chipH / 2, chipH / 2)
        love.graphics.setLineWidth(1)
        col(PAL.gold, 0.55)
        love.graphics.rectangle("line", wx, cy + padV, warnChipW, chipH,
          chipH / 2, chipH / 2)
        love.graphics.setFont(self.hintFont)
        col(PAL.gold)
        printfB("Unavailable", wx,
          cy + padV + (chipH - self.hintFont:getHeight()) / 2,
          warnChipW, "center")
      end

      -- action row, clipped to the visible band exactly like the mods panel
      local by = cy + cardH - padV - rowBtnH
      local bx = x + w - padH - L.btnRowW
      local function clipHit(rect, bucket)
        if not rect then return end
        local vy = math.max(rect.y, top)
        local vy2 = math.min(rect.y + rect.height, top + listH)
        if vy2 > vy then
          bucket[#bucket + 1] = { x = rect.x, y = vy, width = rect.width,
            height = vy2 - vy, id = rect.id, entry = entry }
        end
      end
      local drect = self:_chipButton(bx, by, "Details", {
        w = L.detW, h = rowBtnH, id = entry.id, kind = "neutral",
      })
      clipHit(drect, self.findDetailRects)
      bx = bx + L.detW + btnGap
      if L.repoW > 0 then
        local rrect = self:_chipButton(bx, by, "Source", {
          w = L.repoW, h = rowBtnH, id = entry.id, kind = "neutral",
        })
        clipHit(rrect, self.findRepoRects)
        bx = bx + L.repoW + btnGap
      end
      if L.action then
        local arect = self:_chipButton(bx, by, L.action, {
          w = L.actW, h = rowBtnH, id = entry.id, kind = "accent",
        })
        clipHit(arect, self.findInstallRects)
      end
    end
    cy = cy + cardH + cardGap
  end
  if not paged then love.graphics.setScissor() end

  if maxScroll > 0 then
    local thumbH = math.max(24 * s, listH * (listH / totalH))
    local thumbY = top + (listH - thumbH) * (scroll / maxScroll)
    col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", x + w - 3 * s, thumbY, 3 * s, thumbH,
      1.5 * s, 1.5 * s)
  end
  return (top - y) + totalH
end

return RomImporter
