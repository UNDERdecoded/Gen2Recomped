-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Loads generated data from either the private first-boot cache or the
-- optional source-tree developer build.

local Logger = require("src.core.Logger")

local Data = {}

-- WHAT A CACHE MUST CARRY, and it is not the same list for every generation.
--
-- This was one flat list, and a Gen 3 cache could not boot with it: the load
-- died on trainer_headers.lua, which is a Gen 2 script structure a GBA
-- cartridge has no equivalent of.  Four more would have followed.  None of the
-- per-stage test suites could see that, because each one checks its own table
-- against the cartridge and never asks whether the set as a whole is what the
-- engine opens.  That is the whole reason for a boot test.
local SHARED_MODULES = {
  "constants", "maps", "tilesets", "text", "text_pointers",
  "pokemon", "moves", "items", "type_chart", "trainers", "encounters",
}

-- Gen 1 and Gen 2 only.  trainer_headers is a Gen 2 script structure; font,
-- sprites and battle_anims index art the Gen 1/Gen 2 extractors lay out as
-- tables and the Gen 3 one writes straight to PNG; field is the Gen 1/Gen 2
-- field-move table.
local CLASSIC_MODULES = {
  "trainer_headers", "font", "sprites", "field", "battle_anims",
}

-- Gen 3 only, and REQUIRED rather than optional -- these are not niceties.
-- A Gen 3 map has no blockdata of its own (map_layouts), its tilesets come in
-- primary/secondary pairs (map_tilesets), its scripts are a separate table,
-- and save_layout is what stops a save import guessing where the fields are.
local GEN3_MODULES = {
  "map_layouts", "map_tilesets", "map_scripts", "scenes", "save_layout",
  "songs", "font", "sprites",
  -- ...and `icons`, the THIRD module to make this move, for the same reason
  -- and with the same hazard.  The party menu's little bouncing sprites are
  -- gMonIconTable, six shared palettes and two frames each; blocked, a Hoenn
  -- party was six panels of text with a blank where the Pokemon should be.
  -- Unblocked and NOT produced it would be worse -- the overlay is additive,
  -- so a Gen 3 cache with no icons of its own resolves to RED'S, and every
  -- Hoenn species would wear a Kanto icon chosen by dex number.  Which is why
  -- the import gate requires the file: a cache without it is reported
  -- incomplete rather than booting on somebody else's art.
  "icons",
  -- `field` IS NOW EMERALD'S OWN, and this is the second module to make the
  -- move (see GEN3_BORROWED below, which `sprites` emptied).
  --
  -- It was in CLASSIC_ONLY for a real reason: field.lua is where boot.startMap
  -- and boot.screens live, the overlay is additive, and a Gen 3 cache with no
  -- field of its own read RED'S -- which is how NEW GAME on Emerald opened
  -- Red's intro in Red's house.  Blocking it fixed that.
  --
  -- But extractHealLocations now WRITES one: sHealLocations, the fly warps and
  -- the order the region map lists them in.  Blocked, that file was produced,
  -- required by the import gate, and then thrown away on load -- so FlyMenu
  -- had no destinations and every blackout in Hoenn fell back.  Emerald's own
  -- table carries no boot keys at all, so what it inherits now is nothing
  -- rather than another game's.
  "field",
  -- `audio` made the same move, and for a louder reason: the region was
  -- SILENT.  The Gen 3 extractor writes mapSongs (which of the 611 songs each
  -- of the 518 maps plays) and Music.playMap reads exactly that -- so blocked,
  -- `data.audio` was nil, playMap chose no song, and not one map in Hoenn had
  -- a theme.  The import gate has required audio.lua all along, in as many
  -- words: "a cache without it is a region that boots and is silent".  It was
  -- required by one file and refused by another.
  "audio",
}

-- Gen 4 only.  A Platinum cache is SHARED plus these, and the list is short
-- because a Gen 4 map def carries its own grid, its warps and its objects, so
-- there is no Gen 1/Gen 2 shaped module left to want.
--
--   map_layouts  -- the shared grids; a map that owns its own inlines them,
--                   and the 291 that sit on a matrix another header also uses
--                   point at one of these instead of repeating 1.76 MB each.
--   map_tilesets -- the raw stand-in tileset the renderer composites from.
--                   Gen 4's world is 3D and has no tileset in the Gen 1-3
--                   sense, so this one is synthesised from the tile behaviour
--                   bytes; the pair record it names lives in `tilesets`.
--   map_scripts  -- the script pool and the per-map talk tables.
--   font         -- Platinum's own NFGR fonts, published as pages and faces.
--
-- NOT here, and each for a reason rather than an oversight: `save_layout` is
-- the GEN 3 marker and writing one would make a Gen 4 cache claim to be Gen 3;
-- `sprites`, `icons`, `scenes`, `songs` and `audio` are stages the Gen 4
-- extractor does not have yet, and requiring a file nothing writes would
-- refuse every import.  They are in OPTIONAL, so a cache that gains one later
-- picks it up with no change here.
local GEN4_MODULES = {
  "map_layouts", "map_tilesets", "map_scripts", "font",
}

-- PLATINUM'S OWN TABLES, READ BY THE GEN 4 SCREENS THROUGH `game.data`.
--
-- These are loaded by their real, prefixed names and ONLY on a Gen 4 cache.
-- The prefix is not decoration: an un-prefixed `menus` or `graphics` would
-- resolve through the additive overlay to the ROOT cache -- Red's -- on every
-- other game, which is the exact trap CLASSIC_ONLY below exists to close.
--
-- The OTHER gen4_ modules on disk (gen4_text, gen4_events,
-- gen4_map_permissions, ...) are extractor INPUT: they are lowered into `text`,
-- `map_scripts`, `maps` and `sprites` before the cache is written, and no
-- running screen reads them.  They are deliberately absent.
--
-- !! `gen4_overworld` WAS ON THAT LIST AND IS NOW ON THIS ONE, and the reason it
-- moved is the FOURTH instance of the bug the paragraphs below are about -- in
-- the one direction the wiring check cannot see.
--
-- It was correctly described as extractor input when that sentence was written:
-- the stage lowers it into `sprites` and nothing read the index itself. Then
-- `OverworldController.resolveGraphicsVar` started reading it. The sixteen
-- graphics ids 101..116 (`var_0`..`var_f`) are not pictures -- each names a
-- script var holding the real id -- and turning that id into a sheet needs the
-- NAME -> ARCHIVE MEMBER hop that only this index carries
-- (`gen4_overworld.sprites["player_f"].member` = 91 -> SPRITE_G4_091). With the
-- module unloaded the hop returned nil for every one of them, so EVERY var_N
-- OBJECT IN THE GAME KEPT ITS PLACEHOLDER AND DREW NOTHING.
--
-- Reported from play twice: "dawn and professor are supposed to be there but
-- they aren't", and then "dawns sprite seems to be missing shes invisible
-- particularly if i start as a boy". The log said so outright and precisely --
--   gen4 object: graphics id 101 is var_0 (var 0x4020) and it holds 97 --
--   this object keeps the placeholder and will not draw
-- -- 97 being `player_f`, which is the RIGHT answer: the entry script had run,
-- the gender branch was right, the var was written, and the only thing missing
-- was the table that turns 97 into a sheet.
--
-- WHY THE WIRING CHECK DID NOT CATCH IT. `tools/gen4_cache_wiring_check.lua`
-- compares every name the extractor WRITES against this list, which catches a
-- module written and never loaded. This was the mirror image: a module
-- deliberately not loaded that a consumer later began to READ. The check now
-- asserts that direction too -- every `data.gen4_*` read anywhere in `src/`
-- must name a module on this list.
-- `gen4_species_sprites` IS ON THIS LIST NOW, and it was not before -- so the
-- whole index the species stage writes was DEAD DATA: written on every import,
-- loaded by nothing, read by nothing. The battle's own front and back pictures
-- reach it by another route entirely, which is why nobody noticed.
--
-- It is loaded because the party icons ride inside it (see below), and that is
-- also worth a look the next time somebody wants what else is in there: the
-- per-species sheet paths, the female variants and the height offsets are all
-- sitting in it unused.
--
-- `gen4_move_anims` AND `gen4_particles` ARE THE SECOND AND THIRD TABLES TO
-- HAVE BEEN WRITTEN AND NEVER LOADED, and the pair cost every move in Platinum
-- its animation. The extractor wrote `move_anims.lua`; `Gen4MoveAnimPlayer.new`
-- reads `data.gen4_move_anims`, got nil on every boot, and returned nil -- so
-- the whole 501-program player, every opcode of it, sat behind a constructor
-- that never succeeded. Nothing failed, nothing logged, and the moves fell
-- back to the generic animation, which is what "written on every import,
-- loaded by nothing" looks like from the player's side of the screen.
--
-- The stages are named `gen4_move_anims` and `gen4_particles` now, which is
-- what puts them on this list at all -- and `tools/gen4_cache_wiring_check.lua`
-- compares every name the Gen 4 extractor writes against this file, so a
-- fourth one cannot happen quietly.
local GEN4_PREFIXED = { "gen4_menus", "gen4_graphics", "gen4_intro",
                        "gen4_naming", "gen4_dex", "gen4_models",
                        "gen4_terrain", "gen4_distortion_world",
                        "gen4_species_sprites",
                        "gen4_move_anims", "gen4_particles",
                        "gen4_cellactors",
                        -- the name -> archive member hop for `var_0`..`var_f`;
                        -- see the paragraph above for what its absence cost
                        "gen4_overworld",
                        -- `/data/arealight.narc`: four members of fifteen
                        -- time-of-day templates, selected by the `lighting` byte
                        -- that `gen4_terrain`'s `maps` table has carried on all
                        -- 593 maps since the terrain stage was written and that
                        -- nothing has ever read. Listed here from the day the
                        -- stage was added rather than after someone notices the
                        -- world is drawn unlit -- which is how the four above it
                        -- were found, one report at a time.
                        "gen4_arealight",
                        -- WHICH OF BANK 617'S 2,497 LINES EACH TRAINER SPEAKS.
                        -- The lines themselves are in `text` and always were;
                        -- this is the index, and without it loaded
                        -- `g4_print_trainer_dialogue` has nothing to look a
                        -- trainer up in, which is the fifth instance of
                        -- "written on every import, loaded by nothing" waiting
                        -- to happen. Listed from the day the stage was added.
                        "gen4_trainer_messages",
                        -- the 71 per-area prop allow-lists: a chunk object's
                        -- model id is a GLOBAL build_model.narc member, and one
                        -- outside its area's list draws `dmybox00` rather than
                        -- nothing, which is the "placeholder tile art" report
                        "gen4_mapprops" }

-- WHAT A GEN 3 CACHE MUST NOT INHERIT.
--
-- The version overlay is ADDITIVE: CacheFs mounts emerald/data/generated over
-- data/generated, so any module the Emerald import did not write still
-- resolves -- to whatever the ROOT cache holds, which is Red's.  That is not
-- a hypothetical.  It is why NEW GAME on Emerald opened Red's intro, Red's
-- main menu and Red's REDS_HOUSE_2F: `field` is where boot.startMap and
-- boot.screens live, and Emerald was reading Red's.
--
-- So a Gen 3 cache is not offered them at all.  Each of these is Gen 1/Gen 2
-- shaped -- keyed by Gen 1 ids, Gen 1 script structures, Gen 1 art -- and a
-- Gen 3 dataset that appears to have one is reading another game's.
local CLASSIC_ONLY = {
  -- `field`, `audio` and `icons` used to be here; all three are Emerald's own
  -- now (see GEN3_MODULES).  What is left is genuinely Gen 1/Gen 2 shaped.
  "trainer_headers", "battle_anims", "palettes",
  "unown_puzzle", "unown_dex",
}

-- Nothing is borrowed any more.  `sprites` was the last one -- Gen 3 had no
-- overworld art of its own, so every object event in Hoenn was drawn with
-- Red's sheets -- and it moved into GEN3_MODULES the moment the extractor
-- could produce them.  The table stays as the place to put the next one.
local GEN3_BORROWED = {}

-- requiredModules() lives just below loadModule, which it needs.

-- Optional for compatibility with developer and stale caches.  The Gen 3
-- world modules moved OUT of here and into GEN3_MODULES above: they were
-- optional while the extractor was being built, and leaving them optional
-- after it could produce them meant a cache missing its maps' blockdata would
-- boot and then draw nothing.
--
-- The classic modules appear here too, so a Gen 3 cache that happens to carry
-- them still picks them up, and one that does not degrades with a line in the
-- log rather than refusing to start.
local OPTIONAL = { "audio", "palettes", "icons", "unown_puzzle", "unown_dex",
                   "trainer_headers", "font", "sprites", "field",
                   "battle_anims", "map_layouts", "map_tilesets",
                   "map_scripts", "scenes", "save_layout", "songs" }

-- Vanilla defaults for rules exposed through the constants registry.  A
-- value has to exist before a mod can patch it; each one matches the
-- engine's no-mod behavior, so seeding them changes nothing on a vanilla
-- boot.
local CONSTANT_DEFAULTS = {
  bagSize = 20,                 -- BAG_ITEM_CAPACITY (Bag.capacity fallback)
  partyMax = 6,                 -- PARTY_LENGTH (src/pokemon/Party.lua)
  boxCount = 12, boxSize = 20,  -- Bill's PC (src/pokemon/Boxes.lua)
  moveMax = 4,
  levelCap = 100,
  coinCap = 9999,               -- MAX_COINS (src/ui/SlotMachine.lua)
  -- move-slot repair when a scrub empties a mon (src/core/SaveData.lua);
  -- a total conversion without TACKLE patches this to its own floor
  fallbackMove = "TACKLE",
  hmMoves = { "CUT", "FLY", "SURF", "STRENGTH", "FLASH" }, -- IsMoveHM
  -- gym order (data/scripts/victories.lua); list position is the badge
  -- number the trainer card draws
  badges = {
    { id = "BOULDERBADGE" }, { id = "CASCADEBADGE" }, { id = "THUNDERBADGE" },
    { id = "RAINBOWBADGE" }, { id = "SOULBADGE" },    { id = "MARSHBADGE" },
    { id = "VOLCANOBADGE" }, { id = "EARTHBADGE" },
  },
}

-- data/events/trades.asm in Pokemon Yellow has its own TradeMons table.
-- Old Yellow imports were built from the Red manifest, so correct that
-- table after loading as well as in the fixed import manifest below.
local YELLOW_TRADES = {
  { give = "LICKITUNG", get = "DUGTRIO", dialogset = 1, nickname = "GURIO" },
  { give = "CLEFAIRY", get = "MR_MIME", dialogset = 1, nickname = "MILES" },
  { give = "BUTTERFREE", get = "BEEDRILL", dialogset = 3, nickname = "STINGER" },
  { give = "KANGASKHAN", get = "MUK", dialogset = 1, nickname = "STICKY" },
  { give = "MEW", get = "MEW", dialogset = 3, nickname = "BART" },
  { give = "TANGELA", get = "PARASECT", dialogset = 1, nickname = "SPIKE" },
  { give = "PIDGEOT", get = "PIDGEOT", dialogset = 2, nickname = "MARTY" },
  { give = "GOLDUCK", get = "RHYDON", dialogset = 2, nickname = "BUFFY" },
  { give = "GROWLITHE", get = "DEWGONG", dialogset = 3, nickname = "CEZANNE" },
  { give = "CUBONE", get = "MACHOKE", dialogset = 3, nickname = "RICKY" },
}

-- field.boot is the total-conversion override point for the new game; the
-- values match what SaveData.newGame and the Oak speech used to inline.
local BOOT_DEFAULTS = {
  -- special_warps.asm NewGameWarp: REDS_HOUSE_2F, 3, 6 -- the bedroom, not
  -- the tile outside the house. lastHeal is deliberately absent: SaveData
  -- derives the vanilla blackout point, and seeding it here would leak into
  -- total conversions that patch the spawn without naming a heal point.
  startMap = "REDS_HOUSE_2F", startX = 3, startY = 6, startFacing = "down",
  playerName = "RED", rivalName = "BLUE",
  startMoney = 3000,
  screens = { splash = "IntroMovie", title = "TitleState",
              newGame = "OakSpeech", startMenu = "StartMenu",
              options = "OptionsMenu", bag = "BagMenu",
              party = "PartyMenu", trainerCard = "TrainerCard" },
}

-- Gen2 scaffold warps still reference map-group ids (MAP_Gxx_Nyy) while
-- map keys are symbolic ids (PLAYERS_HOUSE2_F, NEW_BARK_TOWN, ...).
-- Seed the New Bark aliases so NEW GAME can route room->stairs->town.
local GEN2_SCAFFOLD_MAP_ALIASES = {
  MAP_G03_N46 = "DARK_CAVE_VIOLET_ENTRANCE",
  MAP_G03_N47 = "DARK_CAVE_BLACKTHORN_ENTRANCE",
  MAP_G05_N08 = "ROUTE45",
  MAP_G05_N09 = "ROUTE46",
  -- Violet City area (G0A)
  MAP_G0A_N01 = "ROUTE32",
  MAP_G0A_N05 = "VIOLET_CITY",
  -- Azalea / Goldenrod area (G0B)
  MAP_G0B_N02 = "GOLDENROD_CITY",
  -- New Bark Town area (G18)
  MAP_G18_N03 = "ROUTE29",
  MAP_G18_N04 = "NEW_BARK_TOWN",
  MAP_G18_N05 = "ELMS_LAB",
  MAP_G18_N06 = "PLAYERS_HOUSE1_F",
  MAP_G18_N07 = "PLAYERS_HOUSE2_F",
  MAP_G18_N08 = "PLAYERS_NEIGHBORS_HOUSE",
  MAP_G18_N09 = "ELMS_HOUSE",
  MAP_G18_N0D = "ROUTE29_ROUTE46_GATE",
  -- Cherrygrove / Violet area (G1A)
  MAP_G1A_N01 = "ROUTE30",
  MAP_G1A_N02 = "ROUTE31",
  MAP_G1A_N03 = "CHERRYGROVE_CITY",
  MAP_G1A_N0B = "ROUTE31_VIOLET_GATE",
}

-- FireRed's import labels maps by group and number.  The story layer predates
-- that extractor and names the League rooms after their source scripts, so
-- retain both identities.  The aliases also make warps land on the map that
-- owns the League door, rival, and Hall of Fame hooks.
local FIRERED_STORY_MAP_ALIASES = {
  MAP_G01_N75 = "LORELEIS_ROOM",
  MAP_G01_N76 = "BRUNOS_ROOM",
  MAP_G01_N77 = "AGATHAS_ROOM",
  MAP_G01_N78 = "LANCES_ROOM",
  MAP_G01_N79 = "CHAMPIONS_ROOM",
  MAP_G01_N80 = "HALL_OF_FAME",
}

local FIRERED_STORY_OBJECT_TEXT = {
  LORELEIS_ROOM = "TEXT_LORELEISROOM_LORELEI",
  BRUNOS_ROOM = "TEXT_BRUNOSROOM_BRUNO",
  AGATHAS_ROOM = "TEXT_AGATHASROOM_AGATHA",
}

local FIRERED_STORY_OBJECT_NAMES = {
  LANCES_ROOM = "LANCESROOM_LANCE",
  CHAMPIONS_ROOM = "CHAMPIONSROOM_RIVAL",
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function normalizeMapId(mapId)
  if type(mapId) ~= "string" then return mapId end
  local id = mapId:gsub("([0-9]+)_([FB])$", "%1%2")
  local out, i, len = {}, 1, #id
  while i <= len do
    local ch = id:sub(i, i)
    if ch:match("%d") then
      local j = i + 1
      while j <= len and id:sub(j, j):match("%d") do
        j = j + 1
      end
      local prev = i > 1 and id:sub(i - 1, i - 1) or ""
      if prev:match("%a") and prev ~= "B" and out[#out] ~= "_" then
        out[#out + 1] = "_"
      end
      out[#out + 1] = id:sub(i, j - 1)
      i = j
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return table.concat(out)
end

-- AN ALIAS REMEMBERS WHAT IT WAS MADE FROM.
--
-- `normalizeMapId` exists for the Game Boy games, where a map id like
-- `POKEMON_TOWER_1F` wants friendly spelling, and it INSERTS an underscore
-- before any digit run that follows a letter.  Run over a Gen 4 cartridge it
-- rewrites the developers' own internal names: `T01R0201`, the name that
-- `mapname.bin` states and that every Gen 4 cache index is keyed by, becomes
-- `T_01R_0201`.  The alias is a COPY with `id` set to the new spelling, so a
-- map loaded through it carries an id no Gen 4 index has ever heard of, and
-- any join on it fails SILENTLY.
--
-- It did: `Gen4Ground.forMap` looks its map up in `gen4_terrain.maps`, found
-- nothing for `T_01R_0201`, and kept the checkerboard stand-in -- which is
-- what "no textures for the indoors of the house" was.  ZERO of the 593
-- terrain records are broken and ZERO of their ids contain an underscore;
-- the record was there under the cartridge's own name the whole time.
--
-- So the copy carries `sourceId`, and a join that wants the cartridge's
-- spelling asks for that first.  Recovering it by stripping underscores would
-- work today and is guessing at an inverse; this is the id itself.
local function aliasMap(maps, source)
  local alias = normalizeMapId(source)
  if alias == source or maps[alias] or not maps[source] then return end
  local mapped = copy(maps[source])
  mapped.id = alias
  mapped.sourceId = source
  maps[alias] = mapped
end

local function aliasAllMaps(maps)
  local sources = {}
  for source in pairs(maps) do sources[#sources + 1] = source end
  table.sort(sources)
  for _, source in ipairs(sources) do
    aliasMap(maps, source)
  end
end

local function seedMapAliases(maps, aliases)
  -- aliases table: rawId → friendlyId; work both directions so either source can seed the other
  for rawId, friendlyId in pairs(aliases or {}) do
    if not maps[rawId] and maps[friendlyId] then
      local mapped = copy(maps[friendlyId]); mapped.id = rawId; maps[rawId] = mapped
    end
    if not maps[friendlyId] and maps[rawId] then
      local mapped = copy(maps[rawId]); mapped.id = friendlyId; maps[friendlyId] = mapped
    end
  end
end

local function seedTrainerPartyAlias(trainers, alias, sourceIds)
  if not trainers or trainers[alias] then return end
  local first = trainers[sourceIds[1]]
  if not first then return end
  local mapped = copy(first)
  mapped.id = alias
  mapped.parties = {}
  for _, sourceId in ipairs(sourceIds) do
    local source = trainers[sourceId]
    if source and source.parties and source.parties[1] then
      mapped.parties[#mapped.parties + 1] = copy(source.parties[1])
    end
  end
  if #mapped.parties == #sourceIds then trainers[alias] = mapped end
end

-- A generated FireRed warp carries its group/number key.  Resolve that key to
-- the story alias too, so arriving through a real warp and explicitly opening
-- the readable alias select the same map-script contribution.
local function preferMapAliases(maps, aliases)
  for rawId, friendlyId in pairs(aliases or {}) do
    if maps[rawId] and maps[friendlyId] then maps[rawId] = maps[friendlyId] end
  end
end

local function syntheticGen2Tileset(id)
  local blocks = {}
  for index = 1, 256 do
    local block = {}
    for tile = 1, 16 do block[tile] = 0 end
    blocks[index] = block
  end
  return {
    id = id,
    source = "Gen2 scaffold",
    image = "assets/generated/title/pokemon_logo.png",
    imageWidth = 128,
    imageHeight = 128,
    tilesPerRow = 16,
    blocks = blocks,
    walkable = { 0 },
    counterTiles = {},
    doorTiles = {},
    warpTiles = {},
    animation = {},
  }
end

-- ------- Gen 2 BG palettes, published where a renderer can find them
--
-- The ROM colours the overworld in two halves: the tileset's PalMap says
-- which of eight palettes each 8x8 tile wears, and EnvironmentColorsPointers
-- says what those eight palettes ARE for this map's environment at this time
-- of day (LoadMapPals).  The importer writes both onto the tileset record --
-- `palMap` and `palColorsByTod` -- and TileRenderer bakes them into the atlas
-- it draws with.  So the data was always here; it was only ever reachable by
-- knowing those two field names.
--
-- That is fine for the 2D renderer, which lives in this repo.  It is not fine
-- for anything ELSE that has to reproduce the same colouring -- a voxel or 3D
-- pipeline meshes the map once and samples the atlas directly, so it cannot
-- use the per-quad bake and must do the substitution itself, landing on
-- exactly the colours the 2D tiles would have.  Handing it the raw generated
-- sheet instead gives a correct world in four shades of grey, which is what
-- STADIUM2_OVERWORLD_MODELS rendered: geometry, lighting and shadows all
-- right, every surface monochrome.
--
-- Two names make that reachable:
--
--   Data.gen2Palettes[tilesetId][tod] -> { pal1 .. pal8 }, pal = {r,g,b} x4
--     the palette SET, addressed the way the ROM addresses it.  A live view
--     over self.tilesets rather than a copy, so a mod that replaces a
--     tileset's colours is seen by the next lookup.
--
--   tileset.tilePalettes                tileset.palMap, one-based
--     the tile -> palette-slot map under the name the other engines in this
--     lineage use.  NOT an alias: palMap holds the raw ROM nibble, 0-7, and
--     gen2TileColors adds the one when it indexes palColors.  A reader given
--     the raw table has no way to know that, and one that assumes a direct
--     index silently draws every tile in its neighbour's colours -- grass in
--     the tree palette, water in the sand palette -- which looks like a
--     plausible palette rather than a bug.  So this table holds 1-8 and is
--     indexable as-is.  It costs one array per tileset, once.
local GEN2_TOD_ROWS = { "MORN", "DAY", "NITE", "DARK" }

local function gen2PaletteRows(tileset)
  if type(tileset) ~= "table" then return nil end
  local byTod = tileset.palColorsByTod
  if type(byTod) == "table" then return byTod end
  -- A cache extracted before palColorsByTod existed carries one row, and that
  -- row is the ROM's DAY row.  Answer every time of day with it rather than
  -- nothing: a slightly-too-bright cave beats a grey world.
  local single = tileset.palColors
  if type(single) ~= "table" then return nil end
  local rows = {}
  for _, tod in ipairs(GEN2_TOD_ROWS) do rows[tod] = single end
  return rows
end

function Data:publishGen2Palettes()
  local tilesets = self.tilesets
  if type(tilesets) ~= "table" then return false end

  local any = false
  for _, tileset in pairs(tilesets) do
    if type(tileset) == "table" then
      -- REBUILT WHENEVER palMap IS LONGER, not only when this is the first
      -- ask.  `tilePalettes` is a DERIVED COPY, and a copy taken once is a
      -- cache with no invalidation: the map editor can now append art to a
      -- tileset (MapEdits.extendAtlas), which grows palMap by a row per
      -- borrowed tile -- and this table went on answering with the length it
      -- had when the game booted.
      --
      -- The cost of that is not "no answer".  A tile past the end reads nil,
      -- and every reader of this table treats a missing slot as slot 1, which
      -- in a Gen 2 tileset is the TEXT palette -- flat grey.  So a borrowed
      -- tile came out correct in the 2D view (which reads palMap directly) and
      -- grey in the voxel one (which reads this), and the two disagreeing was
      -- the whole of the bug.
      --
      -- Length, not identity: the editor rewrites palMap in place on the same
      -- tileset table, so there is nothing else to compare.
      local palMap = tileset.palMap
      if type(palMap) == "table" then
        local have = tileset.tilePalettes
        if type(have) ~= "table" or #have < #palMap then
          local slots = {}
          for index = 1, #palMap do
            slots[index] = (tonumber(palMap[index]) or 0) + 1
          end
          tileset.tilePalettes = slots
        end
      end
      if gen2PaletteRows(tileset) then any = true end
    end
  end

  -- Publishing an EMPTY table would be worse than publishing nothing: a
  -- reader that checks `data.gen2Palettes` for "does this game have ROM
  -- colours at all" would be told yes and then fail per map, which is the
  -- harder failure to diagnose.  Gen 1 and a colourless Gen 2 cache both
  -- leave the name absent.
  if not any then
    self.gen2Palettes = nil
    return false
  end

  self.gen2Palettes = setmetatable({}, {
    __index = function(_, id) return gen2PaletteRows(tilesets[id]) end,
  })
  return true
end

local function seedMissingGen2Tilesets(self)
  local tilesets = self.tilesets or {}
  local needed = {}
  for _, map in pairs(self.maps or {}) do
    if type(map) == "table" and type(map.tileset) == "string"
        and tilesets[map.tileset] == nil then
      needed[map.tileset] = true
    end
  end
  local CacheFs = require("src.import.CacheFs")

  local function currentImageExists(path)
    local fs = love and love.filesystem
    return fs and fs.getInfo and fs.getInfo(path, "file") ~= nil
  end

  local function copySiblingImage(version, sourcePath, targetPath)
    if type(sourcePath) ~= "string" or type(targetPath) ~= "string" then
      return false
    end
    local siblingPath = version .. "/" .. sourcePath
    local data = love.filesystem and love.filesystem.read
      and love.filesystem.read(siblingPath)
    if type(data) ~= "string" then return false end
    local ok = CacheFs.write(targetPath, data)
    return ok == true
  end

  local function loadSiblingTileset(id)
    for _, version in ipairs({ "gold", "silver" }) do
      if require("src.core.GameVersion").get() ~= version then
        local path = version .. "/data/generated/tilesets.lua"
        local info = love.filesystem and love.filesystem.getInfo
          and love.filesystem.getInfo(path, "file")
        if info then
          local chunk = love.filesystem.load(path)
          if chunk then
            local ok, sibling = pcall(chunk)
            if ok and type(sibling) == "table" and sibling[id] then
              return copy(sibling[id])
            end
            if id == "TilesetPlayersHouse" and ok and type(sibling) == "table"
                and sibling.TilesetHouse then
              local alias = copy(sibling.TilesetHouse)
              alias.id = id
              return alias
            end
            if id == "TilesetPlayersRoom" and ok and type(sibling) == "table" then
              local source = sibling.TilesetPlayersRoom
                or sibling.TilesetPlayersHouse
                or sibling.TilesetHouse
              if source then
                local alias = copy(source)
                alias.id = id
                return alias
              end
            end
          end
        end
      end
    end
    return nil
  end

  local function ensureTilesetImage(id, tileset)
    if type(tileset) ~= "table" then return tileset end
    local imagePath = tileset.image
    if type(imagePath) == "string" and currentImageExists(imagePath) then
      return tileset
    end
    if id == "TilesetPlayersHouse" then
      local source = tilesets.TilesetHouse or loadSiblingTileset("TilesetHouse")
      if type(source) == "table" then
        if copySiblingImage("silver", source.image, imagePath)
            or copySiblingImage("gold", source.image, imagePath) then
          return tileset
        end
        local fallback = copy(source)
        fallback.id = id
        fallback.image = imagePath or fallback.image
        return fallback
      end
    end
    if id == "TilesetPlayersRoom" then
      local source = tilesets.TilesetPlayersRoom
        or tilesets.TilesetPlayersHouse
        or tilesets.TilesetHouse
        or loadSiblingTileset("TilesetPlayersRoom")
        or loadSiblingTileset("TilesetPlayersHouse")
        or loadSiblingTileset("TilesetHouse")
      if type(source) == "table" then
        if copySiblingImage("silver", source.image, imagePath)
            or copySiblingImage("gold", source.image, imagePath) then
          return tileset
        end
        local fallback = copy(source)
        fallback.id = id
        fallback.image = imagePath or fallback.image
        return fallback
      end
    end
    return tileset
  end

  local function ensureWalkableFallback(id, tileset)
    if type(tileset) ~= "table" then return tileset end
    local walkable = tileset.walkable
    if type(walkable) == "table" and #walkable > 0 then return tileset end
    local donor
    if id == "TilesetPlayersRoom" then
      donor = tilesets.TilesetPlayersHouse
        or tilesets.TilesetHouse
        or tilesets.TilesetTraditionalHouse
        or loadSiblingTileset("TilesetPlayersHouse")
        or loadSiblingTileset("TilesetHouse")
        or loadSiblingTileset("TilesetTraditionalHouse")
    elseif id == "TilesetPlayersHouse" then
      donor = tilesets.TilesetHouse
        or tilesets.TilesetTraditionalHouse
        or loadSiblingTileset("TilesetHouse")
        or loadSiblingTileset("TilesetTraditionalHouse")
    end
    if type(donor) ~= "table" or type(donor.walkable) ~= "table"
        or #donor.walkable == 0 then
      if id == "TilesetPlayersRoom" then
        local repaired = copy(tileset)
        repaired.walkable = { 1 }
        return repaired
      end
      return tileset
    end
    local repaired = copy(tileset)
    repaired.walkable = copy(donor.walkable)
    if id == "TilesetPlayersRoom" then
      local hasFloor = false
      for _, v in ipairs(repaired.walkable) do
        if v == 1 then hasFloor = true break end
      end
      if not hasFloor then repaired.walkable[#repaired.walkable + 1] = 1 end
    end
    return repaired
  end

  if next(needed) then
    if needed.TilesetPlayersHouse and tilesets.TilesetHouse ~= nil then
      tilesets.TilesetPlayersHouse = tilesets.TilesetHouse
      needed.TilesetPlayersHouse = nil
    end

    for id in pairs(needed) do
      tilesets[id] = loadSiblingTileset(id) or syntheticGen2Tileset(id)
    end
  end

  if tilesets.TilesetPlayersHouse == nil then
    tilesets.TilesetPlayersHouse = loadSiblingTileset("TilesetPlayersHouse")
      or loadSiblingTileset("TilesetTraditionalHouse")
      or loadSiblingTileset("TilesetHouse")
      or syntheticGen2Tileset("TilesetPlayersHouse")
  end
  tilesets.TilesetPlayersHouse = ensureTilesetImage(
    "TilesetPlayersHouse", tilesets.TilesetPlayersHouse)
  tilesets.TilesetPlayersHouse = ensureWalkableFallback(
    "TilesetPlayersHouse", tilesets.TilesetPlayersHouse)

  if tilesets.TilesetPlayersRoom == nil then
    tilesets.TilesetPlayersRoom = loadSiblingTileset("TilesetPlayersRoom")
      or loadSiblingTileset("TilesetPlayersHouse")
      or loadSiblingTileset("TilesetHouse")
      or syntheticGen2Tileset("TilesetPlayersRoom")
  end
  tilesets.TilesetPlayersRoom = ensureTilesetImage(
    "TilesetPlayersRoom", tilesets.TilesetPlayersRoom)
  tilesets.TilesetPlayersRoom = ensureWalkableFallback(
    "TilesetPlayersRoom", tilesets.TilesetPlayersRoom)
end

local function titleizeWords(key)
  local text = tostring(key or "")
    :gsub("^TEXT_", "")
    :gsub("[_%.]", " ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
    :lower()
  if text == "" then return "..." end
  text = text:gsub("(%a)([%w']*)", function(a, b)
    return a:upper() .. b
  end)
  return text .. "."
end

-- Gen2 charmap codes that spell a fixed word rather than a runtime value
-- ($4A <PKMN>, $5B <PC>, $5D <TRAINER>); RomExtractorGen2 writes them as
-- {NAME} spans and the token registry only knows PLAYER/RIVAL/RAM.
local GEN2_STATIC_TOKENS = {
  PKMN = "POK\195\169MON", PC = "PC", TRAINER = "TRAINER",
}
local GEN2_RUNTIME_TOKENS = { PLAYER = true, RIVAL = true, RAM = true }

-- Strip {BYTE:xx} control tokens the GBC text engine inserts (page breaks,
-- special chars, etc.) so extracted Gen2 strings display cleanly.
local function cleanGen2String(s)
  s = s:gsub("%{BYTE:%x%x?%}", "")
  s = s:gsub("%z", "")
  -- \011 (<CONT>) and \012 (<PARA>) are the markers TextBox.paginate splits
  -- on.  Flattening them to newlines put whole speeches on a single page,
  -- which the box then scrolled straight past with nothing to press A on.
  s = s:gsub("%{([%w_]+)%}", function(name)
    if GEN2_RUNTIME_TOKENS[name] then return nil end
    return GEN2_STATIC_TOKENS[name] or ""
  end)
  s = s:gsub("\n+", "\n")
  return (s:match("^%s*(.-)%s*$") or s)
end

local function sanitizeGen2Text(text)
  if type(text) ~= "table" then return end
  for key, value in pairs(text) do
    if type(value) == "string" then
      if key == "_OakSpeechText1" or key == "_OakSpeechText2A"
          or key == "_OakSpeechText2B" or key == "_OakSpeechText3"
          or key == "_IntroducePlayerText" or key == "_IntroduceRivalText"
          or key == "_YourNameIsText" or key == "_HisNameIsText" then
        -- Let OakSpeech.textOr handle these with its own known-good fallbacks.
      else
        local mapId, stubKey = value:match("^%{GEN2_TEXT_STUB:([^:}]+):([^}]+)%}$")
        if mapId and stubKey then
          if stubKey:find("_OBJ_", 1, true) then
            text[key] = "You examine the object.\n" .. titleizeWords(mapId)
          elseif stubKey:find("_BG_", 1, true) then
            text[key] = "You read the sign.\n" .. titleizeWords(mapId)
          else
            text[key] = titleizeWords(stubKey)
          end
        elseif value:match("^%{GEN2_TEXT:[^}]+%}$") then
          text[key] = titleizeWords(key)
        elseif value:find("{", 1, true) or value:find("[\011\012%z]") then
          text[key] = cleanGen2String(value)
        end
      end
    end
  end
end

local function ensureGen2WarpFallbacks(self)
  local maps = self.maps
  if type(maps) ~= "table" then return end
  local up = maps.PLAYERS_HOUSE2_F
  if type(up) ~= "table" or type(up.warps) ~= "table" or #up.warps == 0 then
    return
  end
  local stairs = up.warps[1]
  if type(stairs) ~= "table" then return end
  if stairs.x == 7 and stairs.y == 0 then
    local hasLeft = false
    for _, w in ipairs(up.warps) do
      if type(w) == "table" and w.x == 6 and w.y == 0 then
        hasLeft = true
        break
      end
    end
    if not hasLeft then
      local dup = copy(stairs)
      dup.x = 6
      up.warps[#up.warps + 1] = dup
    end
  end
end

local function ensureGen2HomeTextFallbacks(self)
  if type(self.text) ~= "table" then self.text = {} end
  local text = self.text
  -- Seed mom text via text_pointers if the resolved string is missing.
  -- OBJ_001 in PlayersHouse1F is the stove interaction (ROM-correct);
  -- the mom NPC on object index 2 resolves through PlayersHouse1FSinkText.
  -- Fallback plain strings are used only when extraction produced nothing.
  local function ensureText(key, fallback)
    if not text[key] or text[key] == "" then text[key] = fallback end
  end
  ensureText("PlayersHouse1FStoveText", "Mom's specialty!\nCINNABAR VOLCANO BURGER!")
  ensureText("PlayersHouse1FSinkText", "The sink is spotless.\nMom likes it clean.")
  ensureText("PlayersHouse1FFridgeText", "Let's see what's\nin the fridge...")
  ensureText("PlayersHouse1FTVText", "There's a movie on TV.")
  if not text.TEXT_PLAYERS_HOUSE2_F_OBJ_002 then
    text.TEXT_PLAYERS_HOUSE2_F_OBJ_002 = "It's your PC.\nWithdraw any item you need."
  end
  -- Fix placeholder names for key Gen2 items that the extractor doesn't name yet
  if type(self.items) == "table" then
    local function fixItem(id, name, keyItem)
      local it = self.items[id]
      if it and (it.name == id or (it.name or ""):find("Item %d")) then
        it.name = name
        if keyItem then it.keyItem = true end
      end
    end
    fixItem("ITEM_005", "POK\xc3\xa9GEAR", true)
    fixItem("ITEM_006", "MAP CARD",    true)
    fixItem("ITEM_007", "COIN CASE",   true)
    fixItem("ITEM_008", "ITEMFINDER",  true)
  end
end

function Data:applyVersionedFieldData()
  if require("src.core.GameVersion").isYellow() then
    self.field.trades = copy(YELLOW_TRADES)
    -- The old man's catch demo is a RATTATA in Yellow
    -- (scripts/ViridianCity.asm ViridianCityOldManStartCatchTrainingScript
    -- .SetupBattle: ld a, RATTATA / ld [wCurOpponent], a) but the Yellow
    -- manifest inherited Red's WEEDLE field.oldManBattle (#617), so old
    -- Yellow caches carry the wrong demo species too.  The fixed import
    -- manifest below stamps RATTATA for fresh imports.
    self.field.oldManBattle = { species = "RATTATA", level = 5 }
  end
end

-- Fills only what the cache is missing, so an importer that learns to
-- stamp one of these keys silently takes over from the engine.
function Data:seedDefaults()
  local constants = self.constants
  for key, value in pairs(CONSTANT_DEFAULTS) do
    if constants[key] == nil then constants[key] = copy(value) end
  end
  -- derived, not literal: a dataset with a different roster gets the right
  -- upper bound without 151 being written down anywhere
  if constants.dexSize == nil then
    local highest = 0
    for _, def in pairs(self.pokemon) do
      if def.dex and def.dex > highest then highest = def.dex end
    end
    constants.dexSize = highest
  end
  if constants.dexDigits == nil then
    constants.dexDigits = math.max(3, #tostring(constants.dexSize))
  end
  self:applyVersionedFieldData()
  -- A Gen 3 cache carries no field.lua -- that table is the Gen 1/Gen 2
  -- field-move layout, and a GBA cartridge lays the same information out
  -- differently.  Seed an empty one rather than dying here: every default
  -- below then lands in it, which is what a mod would patch anyway.
  self.field = self.field or {}
  local boot = self.field.boot
  if boot == nil then
    boot = {}
    self.field.boot = boot
  end
  for key, value in pairs(BOOT_DEFAULTS) do
    if boot[key] == nil then boot[key] = copy(value) end
  end
  -- Yellow and Gold/Silver boot their own attract movies
  -- (engine/movie/intro_yellow.asm, engine/movie/intro.asm); only the
  -- un-overridden default flips, so a total conversion that set
  -- field.boot.screens.splash keeps its choice on any version.
  if boot.screens.splash == BOOT_DEFAULTS.screens.splash then
    local V = require("src.core.GameVersion")
    if V.isYellow() then
      boot.screens.splash = "YellowIntro"
    elseif V.isGen2() then
      boot.screens.splash = "Gen2Intro"
    elseif self.isGen3Cache or V.isGen3() then
      -- NOT `false`, which is what this said and what dropped the studio card
      -- on a Gen 3 boot: that card is this port's own and belongs on every
      -- version.  IntroMovie is not the answer either -- everything after the
      -- card in it is Kanto art out of a field.intro manifest a Gen 3 cache
      -- does not have.  Gen3Intro keeps the card and puts Emerald's own
      -- attract skies behind it.
      boot.screens.splash = "Gen3Intro"
      -- FireRed has its own real boot intro -- pret's intro.c, not
      -- Emerald's bike ride -- and RomExtractorGen3:extractFireRedIntro
      -- extracts it under its own key so a cache that predates that stage
      -- still gets SOMETHING rather than a screen with no images to draw.
      local core = self.constants and self.constants.gen3FRLGIntro
      local images = core and core.images
      if V.get() == "firered" and type(images) == "table"
         and images.gfBg and images.scene1Grass and images.scene3Bg then
        boot.screens.splash = "Gen3IntroFRLG"
      end
    end
  end
  -- ------------------------------------------------------------ GEN 3 ----
  --
  -- EVERY ONE OF THESE WAS COMING FROM RED.  A Gen 3 cache carries no
  -- field.lua, the version overlay does not hide the un-prefixed one, and so
  -- an Emerald NEW GAME ran Red's boot record: Red's title screen, Red's
  -- professor speech, and REDS_HOUSE_2F -- a map no Hoenn dataset has, which
  -- is where it finally fell over.  CLASSIC_ONLY above stops the inheritance;
  -- this is what Gen 3 gets instead.
  --
  -- The spawn is NOT typed from memory.  NewGameInitData's last act is
  -- WarpToTruck, the only call to SetWarpDestination in 16 MiB whose map is a
  -- pair of immediates and whose warp id and coordinates are all -1 -- and -1
  -- is a request for the centre of the map, which SetPlayerCoordsFromWarp
  -- resolves to width/2, height/2.  tools/gen3_discover.py derives the group,
  -- the number and the layout's own dimensions and ships the result in the
  -- manifest; the extractor writes it here.
  -- Keyed on the CACHE, not on the selected version, and for the reason
  -- requiredModules already gives: asking GameVersion works only if the
  -- caller set it first, and a loader that quietly applies Gen 1 defaults
  -- when it was not is the ordering trap that works in the launcher and
  -- fails in a test.
  if self.isGen3Cache or require("src.core.GameVersion").isGen3() then
    local spawn = (self.constants or {}).gen3NewGameSpawn
    if boot.startMap == BOOT_DEFAULTS.startMap and type(spawn) == "table"
       and spawn.map then
      boot.startMap = spawn.map
      boot.startX = spawn.x or 0
      boot.startY = spawn.y or 0
      boot.startFacing = "down"
    end
    if boot.playerName == BOOT_DEFAULTS.playerName then
      boot.playerName = "BRENDAN"
    end
    if boot.rivalName == BOOT_DEFAULTS.rivalName then
      -- the other one: whichever the player does not choose is the rival,
      -- and BirchSpeech swaps the pair when the girl is picked
      boot.rivalName = "MAY"
    end
    if boot.screens.title == BOOT_DEFAULTS.screens.title then
      boot.screens.title = "Gen3Title"
    end
    if boot.screens.newGame == BOOT_DEFAULTS.screens.newGame then
      boot.screens.newGame = "BirchSpeech"
    end
    -- FIRERED IS OAK'S, not Birch's: its own guide, Pikachu card and
    -- professor, and a rival the player names rather than the other gender.
    local frlgOak = (self.constants or {}).gen3FRLGOakSpeech
    if type(frlgOak) == "table" and type(frlgOak.text) == "table"
       and frlgOak.text.welcome then
      if boot.screens.newGame == "BirchSpeech" then
        boot.screens.newGame = "Gen3OakSpeechFRLG"
      end
      local frlgTitle = (self.constants or {}).gen3FRLGTitle
      if boot.screens.title == "Gen3Title" and type(frlgTitle) == "table"
         and type(frlgTitle.images) == "table" and frlgTitle.images.mon then
        boot.screens.title = "Gen3TitleFRLG"
      end
      if boot.playerName == "BRENDAN" then boot.playerName = "RED" end
      if boot.rivalName == "MAY" then boot.rivalName = "GREEN" end
    end
    -- THE START MENU IS NOT THE GEN 2 ONE WITH DIFFERENT WORDS.  Its rows
    -- come off the cartridge (sStartMenuText, whose run IS the order), its
    -- fourth entry is a device Johto does not have, and it is drawn on a
    -- 240-wide screen rather than in a 20-tile letterbox.  Same for OPTION,
    -- whose six rows and every value they cycle through are read from the
    -- cartridge's own vocabulary.
    if boot.screens.startMenu == BOOT_DEFAULTS.screens.startMenu then
      boot.screens.startMenu = "Gen3StartMenu"
    end
    if boot.screens.options == BOOT_DEFAULTS.screens.options then
      boot.screens.options = "Gen3Options"
    end
    -- ...and the three the START menu opens.  Each is a GBA screen with a
    -- shape the Game Boy one does not have -- the bag's five pockets and its
    -- description panel, the party's six panels with the lead one large, the
    -- card's fields and its flip side -- and each is set in the cartridge's
    -- own words, read from the text region the same way the START menu's
    -- rows were.
    if boot.screens.bag == BOOT_DEFAULTS.screens.bag then
      boot.screens.bag = "Gen3BagMenu"
    end
    if boot.screens.party == BOOT_DEFAULTS.screens.party then
      boot.screens.party = "Gen3PartyMenu"
    end
    if boot.screens.trainerCard == BOOT_DEFAULTS.screens.trainerCard then
      boot.screens.trainerCard = "Gen3TrainerCard"
    end
    if boot.namePresets == nil then
      boot.namePresets = {
        player = { "BRENDAN", "MAY", "TERRY" },
        rival = { "MAY", "BRENDAN", "TERRY" },
      }
    end
    -- THE FLAGS THE WORLD OPENS WITH SET.
    --
    -- A set flag hides its object and every flag starts clear, so without
    -- this every gated NPC in Hoenn is on screen from the first frame.  The
    -- cartridge's own new-game script sets 159 of them; SaveData.newGame
    -- applies them through boot.initialFlags, the same way it applies the
    -- Gen 2 map scenes that do not start at zero.
    local opening = (self.constants or {}).gen3NewGameFlags
    if type(opening) == "table" and type(opening.flags) == "table"
       and boot.initialFlags == nil then
      boot.initialFlags = opening.flags
    end

    -- ...AND THE BERRIES ALREADY IN THE GROUND.
    --
    -- Reported from play: "for berries in the north of route 104 theres
    -- usually berry trees already planted and fully grown in the rom, theyre
    -- also all throughout hoenn already planted and fully grown in the rom
    -- but not in our game at the moment."
    --
    -- The same new-game script that sets those 159 flags ends with a call
    -- into a run of eighty `setberrytree` commands -- twenty different
    -- berries, every one of them at stage 5, fruiting.  The importer reads
    -- the run (gen3Berries.planted); this turns it into the save shape the
    -- berry code already uses, once, so SaveData.newGame only has to copy it.
    --
    -- The arithmetic is PlantBerryTree's (0x00E191C): the countdown is the
    -- berry's own stage duration, a tree planted straight into BERRIES has
    -- that countdown quadrupled and a yield rolled for it -- and with nothing
    -- watered CalcBerryYield is exactly the minimum, so there is no roll to
    -- make here -- and `setberrytree` always passes allowGrowth = FALSE, so
    -- every one of them is frozen until the player walks into view of it.
    local berries = (self.constants or {}).gen3Berries
    local planted = type(berries) == "table" and berries.planted
    if type(planted) == "table" and boot.initialBerryTrees == nil then
      local FRUITING, WATER_QUARTER = 5, 4
      local trees, n = {}, 0
      for _, row in ipairs(planted) do
        local id, number, stage = tonumber(row.tree), tonumber(row.berry),
                                  tonumber(row.stage)
        local info = number and berries[number]
        if id and id > 0 and info and stage and stage > 0 then
          local minutes = (tonumber(info.hours) or 0) * 60
          local yield = 0
          if stage == FRUITING then
            minutes = minutes * WATER_QUARTER
            yield = tonumber(info.minYield) or 1
          end
          trees[id] = { berry = number, stage = stage, minutes = minutes,
                        yield = yield, regrowth = 0, watered = {},
                        stopGrowth = true }
          n = n + 1
        end
      end
      if n > 0 then
        boot.initialBerryTrees = trees
        Logger.info("Gen3 new game: %d berry trees already in the ground -- %s",
                    n, tostring(berries.plantedSource))
      end
    end

    -- THE LEDGES, which Hoenn had none of.
    --
    -- field.ledges is a table of (standing tile, tile in front, direction)
    -- rows, because that is the only way Gen 1 and Gen 2 can say it.  Nothing
    -- ever filled it for Gen 3, so checkLedgeHop found no row for any cell in
    -- the region and every ledge was an ordinary wall -- no way down off any
    -- terrace in the game.  Gen 3 says it in the metatile itself, so the
    -- tileset carries the behaviour-to-direction map and the field takes it
    -- from whichever pair the dataset shipped.
    if self.field.ledgeBehaviours == nil then
      for _, ts in pairs(self.tilesets or {}) do
        if type(ts) == "table" and ts.ledgeBehaviours then
          self.field.ledgeBehaviours = ts.ledgeBehaviours
          break
        end
      end
    end

    -- THE TEXT BOX IS THE CARTRIDGE'S, not the Game Boy's.
    --
    -- Theme carries one box and it was Red's: 20 tiles wide with an
    -- 18-column budget.  Emerald's is 26 columns inside a 28-tile frame, and
    -- laying Emerald's text out in Red's window wrapped every authored line
    -- in half -- which turned every two-line page into a four-line one, and a
    -- page with more lines than the window shows scrolls them past instead of
    -- waiting for A.  That was the auto-scrolling text.
    --
    -- The window is the extracted record; the frame is one tile out from it
    -- on every side, which is how this cartridge draws every window.
    -- THE TWO CYCLING ROUTES' OWN TABLES.  Routes 119 and 123 pick their
    -- weather out of a four-byte table with a stage the save advances once a
    -- day; the module carries the same four steps as a default, so this only
    -- matters for a cartridge whose tables differ from Emerald's.
    local cycles = (self.constants or {}).gen3WeatherCycles
    if type(cycles) == "table" then
      require("src.world.Gen3Weather").setCycles(cycles)
    end

    local win = (self.constants or {}).gen3MessageWindow
    if type(win) == "table" and win.width and win.height then
      self.field.theme = self.field.theme or {}
      if self.field.theme.textBox == nil then
        self.field.theme.textBox = {
          tx = math.max(0, (win.left or 2) - 1),
          ty = math.max(0, (win.top or 15) - 1),
          tw = (win.width or 26) + 2,
          th = (win.height or 4) + 2,
          maxCols = win.width or 26,
        }
      end
      local dialogue = self.font and self.font.dialogueFrame
      if type(dialogue) == "table" and dialogue.layout ~= "gen4" then
        local box = self.field.theme.textBox
        -- new_menu_helpers.c sYesNo_WindowTemplate is a 6x4 content window
        -- at tile (21,9).  DrawStdWindowFrame adds the one-tile border around
        -- it, so the visible FireRed YES/NO box is x20..27, y8..13.  The
        -- shared Game Boy default sat at x13 and overlapped showmonpic 10,3
        -- during Oak's starter confirmation.
        box.choiceBox = box.choiceBox or {
          tx = 20, ty = 8, tw = 8, th = 6,
        }
      end
    end
    -- THE PLAYER'S OWN SPRITE, which is not an NPC's and does not come from
    -- the map.  Player:refreshForm reads field.playerSprites for the default
    -- pair and field.playerForms[gender] to override it, so the boy-or-girl
    -- answer the Birch speech records is what decides which of the two rows
    -- of the graphics table the player walks around Hoenn wearing.
    local avatars = (self.constants or {}).gen3PlayerSprites
    if type(avatars) == "table" and self.field.playerSprites == nil then
      self.field.playerSprites = {
        walk = avatars.boy, bike = avatars.boyBike, surf = avatars.boySurf,
        -- ...and the diving suit.  It is a different SHEET, not a palette
        -- swap: sPlayerAvatarGfxIds names rows 111 and 112 for it, seventy
        -- past the walking sheet and wearing their own palette, which is why
        -- the block walk that finds the bicycle and the surfboard could never
        -- reach it.  Absent on a cache imported before it was found, where
        -- every caller falls back to the sheet it used before.
        underwater = avatars.boyUnderwater,
        -- ...and the POSE, which is a sheet like the rest of them: the
        -- character standing still with a Poke Ball held out, worn while a
        -- field move's presentation is on screen.
        fieldMove = avatars.boyFieldMove,
      }
    end
    -- ...AND IT FILLS IN, RATHER THAN STANDING ASIDE.
    --
    -- Reported from play: "selecting may doesnt give me mays sprite when i
    -- start the game".  This used to write the whole table only when there
    -- was none -- and by the time it runs there always IS one, because the
    -- import writes field.playerForms itself to carry the two PORTRAITS (the
    -- trainer card's faces, read off the rival rows that name them).  So the
    -- test was always false, the sprite half was never written, and
    -- Player:refreshForm found a form with no `walk` in it and kept the
    -- default -- which is the BOY's.  A girl got her own face on the trainer
    -- card and walked Hoenn as Brendan.
    --
    -- The two halves come from different stages and neither owns the table,
    -- so this fills in the keys it is responsible for and leaves every other
    -- key alone.
    if type(avatars) == "table" then
      local forms = self.field.playerForms
      if type(forms) ~= "table" then
        forms = {}
        self.field.playerForms = forms
      end
      forms.order = forms.order or { "boy", "girl" }
      local sheets = {
        boy = { label = "BOY", walk = avatars.boy, bike = avatars.boyBike,
                surf = avatars.boySurf, underwater = avatars.boyUnderwater,
                fieldMove = avatars.boyFieldMove },
        girl = { label = "GIRL", walk = avatars.girl, bike = avatars.girlBike,
                 surf = avatars.girlSurf,
                 underwater = avatars.girlUnderwater,
                 fieldMove = avatars.girlFieldMove },
      }
      for who, sheet in pairs(sheets) do
        local form = forms[who]
        if type(form) ~= "table" then
          forms[who] = sheet
        else
          for key, value in pairs(sheet) do
            if form[key] == nil then form[key] = value end
          end
        end
      end
    end
  end
  -- SINNOH'S OWN DEFAULTS.
  --
  -- THESE USED TO SIT INSIDE THE GEN 3 BRANCH, which is the whole reason the
  -- two things they set were reported as unchanged after the cache was rebuilt
  -- for them: the branch opens `if self.isGen3Cache or isGen3()`, so on a
  -- Platinum cache neither line ever ran.  Reported from play as *"barry is
  -- also still there no changes really from before, textboxes still not wide
  -- enough"* -- one placement mistake, both symptoms.
  if self.isGen4Cache or require("src.core.GameVersion").isGen4() then
    -- THE FLAGS A NEW GAME STARTS WITH SET.
    --
    -- `FieldSystem_InitNewGameState` runs one script at the start of a new
    -- game and it is 112 `setflag`s -- the actors whose stories have not begun
    -- are hidden, exactly as in Hoenn.  Reported from play as Barry standing
    -- at the top of the stairs and his mother in the doorway before either of
    -- them is due.  Same seam, same shape; the three `setvarfromvalue` rows
    -- the script also carries need one of their own, because a Gen 4 var is
    -- not a flag.
    local sinnoh = (self.constants or {}).gen4NewGame
    if type(sinnoh) == "table" then
      if type(sinnoh.flags) == "table" and boot.initialFlags == nil then
        boot.initialFlags = sinnoh.flags
      end
      if type(sinnoh.vars) == "table" and boot.initialVars == nil then
        boot.initialVars = sinnoh.vars
      end
    end

    -- A GEN 4 SPECIES RECORD IS THE RIGHT DATA UNDER THE WRONG NAMES, and
    -- until this ran, BUILDING ONE RAISED.
    --
    -- Measured offline against the live cache, not reasoned about:
    --
    --     Pokemon.new(data, 387, 5)
    --     -> Stats.lua:68: attempt to perform arithmetic on a nil value
    --     Pokemon.movesAtLevel(def, 5)
    --     -> attempt to index a nil value
    --
    -- So the starter this port now hands over, every wild encounter and every
    -- trainer party would each have taken the game down. Four mismatches, all
    -- of them naming rather than data:
    --
    --   * `baseStats.spAttack` / `spDefense` -- the engine reads `spatk` and
    --     `spdef`, and `Stats.calc`'s Gen 1 path reads `special`.
    --   * `evYields` -- `Stats.isGen3` tests for `evYield`, SINGULAR, and it is
    --     the only reader: it is a presence test that decides which stat model
    --     a record implies. Failing it put Gen 4 Pokemon on the Gen 1 model --
    --     four DVs of 0..15, no natures, no abilities, no EVs -- which is a
    --     worse answer than Gen 3's for a Gen 4 cartridge in every respect.
    --   * `learnset` with no `level1Moves` -- `Pokemon.movesAtLevel` opens with
    --     `ipairs(speciesDef.level1Moves)`, which raises on nil. The moves are
    --     there; a Gen 4 learnset simply carries its level-1 entries inline.
    --   * `expRate`, a NUMBER, against `growthRate`, a curve NAME. The enum is
    --     `generated/exp_rates.txt`, zero-based: 0 MEDIUM_FAST, 1 ERRATIC,
    --     2 FLUCTUATING, 3 MEDIUM_SLOW, 4 FAST, 5 SLOW. Turtwig is 3, and
    --     Turtwig is Medium Slow.
    --
    -- Done HERE rather than in the extractor for the reason the connection
    -- rename above is: it lands without a re-import, and a record that already
    -- carries the engine's spelling is left alone.
    --
    -- ERRATIC and FLUCTUATING are named rather than mapped to a curve that
    -- happens to exist. Neither is closed-form -- `Growth.CURVES` has the six
    -- polynomial ones -- so `Growth.expForLevel` warns once and falls back to
    -- MEDIUM_FAST. The exact answer is a NARC (`poketool/personal/pl_growtbl`,
    -- one 101-entry member per rate) and belongs in the extractor; naming the
    -- curve here means the warning says which one is missing instead of the
    -- game quietly levelling on the wrong curve.
    local EXP_RATE_NAME = {
      [0] = "MEDIUM_FAST", [1] = "ERRATIC", [2] = "FLUCTUATING",
      [3] = "MEDIUM_SLOW", [4] = "FAST", [5] = "SLOW",
    }
    local speciesFixed = 0
    for _, def in pairs(self.pokemon or {}) do
      if type(def) == "table" then
        local changed = false
        local bs = def.baseStats
        if type(bs) == "table" and bs.spatk == nil and bs.spAttack ~= nil then
          bs.spatk, bs.spdef = bs.spAttack, bs.spDefense
          bs.special = bs.special or bs.spAttack
          changed = true
        end
        if def.evYield == nil and type(def.evYields) == "table" then
          local y = def.evYields
          y.spatk = y.spatk or y.spAttack
          y.spdef = y.spdef or y.spDefense
          def.evYield = y
          changed = true
        end
        if def.growthRate == nil and def.expRate ~= nil then
          def.growthRate = EXP_RATE_NAME[tonumber(def.expRate)] or "MEDIUM_FAST"
          changed = true
        end
        if def.level1Moves == nil then
          local first = {}
          for _, row in ipairs(def.learnset or {}) do
            if row.move and (tonumber(row.level) or 0) <= 1 then
              first[#first + 1] = row.move
            end
          end
          def.level1Moves = first
          changed = true
        end
        if changed then speciesFixed = speciesFixed + 1 end
      end
    end
    -- A GEN 4 TRAINER IS ONE PARTY WHERE THE ENGINE EXPECTS A LIST OF THEM.
    --
    -- `BattleState.newTrainer(game, oppClass, partyIndex)` reads
    -- `trainers[key].parties[i]` -- Gen 1 and Gen 2 put SEVERAL trainers in one
    -- CLASS (TrainerGroups: "YOUNGSTER" holds a dozen parties), so the class is
    -- the key and the index picks the person. Gen 4 numbers every trainer
    -- individually and gives each one party. The record is right; it is one
    -- level shallower than the reader.
    --
    -- A VIEW, NOT A CONVERSION: `parties[1]` IS `party`, so nothing is copied
    -- and nothing can drift.
    --
    -- Three things the slots need on the way through, each of them the
    -- cartridge's own rule rather than a guess:
    --
    --   * MOVE SLOT 0 IS EMPTY, not move 0. `trdata` stores four move ids and
    --     pads with zero; `buildTrainerParty` would hand the battler four
    --     moves, one of which does not exist. A party whose moves are ALL zero
    --     is a `TRDATATYPE_BASE` row -- it has no move list at all -- and must
    --     keep nil so the level-up set applies.
    --   * IVS COME FROM ONE BYTE. `TrainerData_BuildParty`:
    --         ivs = trmon[i].ivScale * MAX_IVS_SINGLE_STAT / MAX_IV_SCALE
    --     -- 31/255 of the scale, THE SAME VALUE IN ALL SIX STATS. Written to
    --     `dvs`, which is the parameter `Stats.calc` passes on as `ivs` for a
    --     Gen 3-model species; `buildTrainerParty` already prefers a slot's own
    --     over the fixed fallback.
    --   * A DOUBLE BATTLE IS THE TRAINER'S OWN BYTE.
    --     `Script_IsTrainerDoubleBattle` is `battleType != BATTLE_TYPE_SINGLES`,
    --     and `BattleState` reads `trainer.doubleBattle` -- the same shape Gen 3
    --     uses, so the battle builder needs no Gen 4 branch.
    local trainersFixed = 0
    for _, rec in pairs(self.trainers or {}) do
      if type(rec) == "table" and rec.parties == nil and type(rec.party) == "table"
      then
        for _, slot in ipairs(rec.party) do
          if type(slot) == "table" then
            if type(slot.moves) == "table" then
              local real = {}
              for _, id in ipairs(slot.moves) do
                if (tonumber(id) or 0) ~= 0 then real[#real + 1] = id end
              end
              slot.moves = (#real > 0) and real or nil
            end
            if slot.dvs == nil and slot.ivScale ~= nil then
              local iv = math.floor((tonumber(slot.ivScale) or 0) * 31 / 255)
              slot.dvs = { hp = iv, attack = iv, defense = iv,
                           speed = iv, spatk = iv, spdef = iv,
                           -- the Gen 1/2 formula reads one `special`; harmless
                           -- here and correct if anything ever asks
                           special = iv }
            end
          end
        end
        rec.parties = { rec.party }
        if rec.doubleBattle == nil and rec.battleType ~= nil then
          rec.doubleBattle = (tonumber(rec.battleType) or 0) ~= 0
        end
        trainersFixed = trainersFixed + 1
      end
    end
    if trainersFixed > 0 then
      Logger.info("gen4 trainers: %d record(s) now expose their party the way "
                  .. "BattleState reads one", trainersFixed)
    end

    -- ...AND THE NATURE, AS A NAME RATHER THAN A NUMBER.
    --
    -- The Gen 4 extractor writes `natureOrder = {1..25}` and `natures` as a
    -- LIST of names, so `Pokemon.new`'s `order[(personality % 25) + 1]` put a
    -- bare integer on the mon. Every screen that shows a nature would have
    -- shown "13", and a number is also what made the argument slip below fatal
    -- rather than merely wrong.
    --
    -- Pointing `natureOrder` at the names costs nothing and is what the field
    -- is for: `Stats.calcGen3` looks its modifiers up BY THE VALUE STORED ON
    -- THE MON, so a name is the only form that can ever resolve.
    local natureNames = (self.constants or {}).natures
    local natureOrder = (self.constants or {}).natureOrder
    if type(natureNames) == "table" and type(natureOrder) == "table"
       and type(natureOrder[1]) == "number" and type(natureNames[1]) == "string"
    then
      local named = {}
      for i = 1, 25 do named[i] = natureNames[i] or natureOrder[i] end
      self.constants.natureOrder = named
      Logger.info("gen4 natures: natureOrder now names its 25 rows, so a "
                  .. "Pokemon carries \"%s\" rather than a bare index",
                  tostring(named[1]))
    end

    -- ...AND THE MODIFIERS, WHICH ARE A RULE RATHER THAN A TABLE.
    --
    -- `Data:load` hands `constants.natures` to `Stats.setNatures`, which wants
    -- it keyed BY NAME with a `modifiers` record -- that is the shape Gen 3's
    -- extractor writes, read off `gNatureStatTable`.  Gen 4's extractor writes
    -- a flat LIST of 25 names, so the lookup found nothing and every Sinnoh
    -- Pokemon carried a nature that moved no stat.
    --
    -- The table does not have to be extracted, because it is derivable and the
    -- cartridge derives it the same way.  `sNatureStatAffinities`
    -- (src/pokemon.c) is the 25x5 pattern every generation uses:
    --
    --     raised  = nature / 5      lowered = nature % 5
    --
    -- over [attack, defense, speed, spAtk, spDef], and the two are equal for
    -- the five neutral natures, which is what makes Hardy, Docile, Serious,
    -- Bashful and Quirky move nothing.  `Pokemon_GetNatureStatValue` then
    -- multiplies by 110 or 90 and divides by 100 -- and 110/90/100 is exactly
    -- the percentage `Stats.calcGen3` expects, so no conversion either.
    --
    -- Checked against the cartridge rather than assumed: Lonely is nature 1,
    -- so raised = 0 (attack) and lowered = 1 (defense) -- which is what
    -- `sNatureStatAffinities[NATURE_LONELY]` says, line for line, and the same
    -- for Brave, Adamant, Naughty and Bold.
    local NATURE_STAT = { "attack", "defense", "speed", "spatk", "spdef" }
    local natureRows = (self.constants or {}).natures
    if type(natureRows) == "table" and type(natureRows[1]) == "string" then
      local byName, modified = {}, 0
      for i = 1, 25 do
        local name = natureRows[i]
        if type(name) == "string" and name ~= "" then
          local n = i - 1                        -- the cartridge counts from 0
          local up, down = NATURE_STAT[math.floor(n / 5) + 1], NATURE_STAT[(n % 5) + 1]
          local modifiers = {}
          for _, key in ipairs(NATURE_STAT) do modifiers[key] = 100 end
          if up ~= down then
            modifiers[up], modifiers[down] = 110, 90
            modified = modified + 1
          end
          byName[name] = {
            name = name, index = n, modifiers = modifiers,
            raises = (up ~= down) and up or nil,
            lowers = (up ~= down) and down or nil,
          }
        end
      end
      if next(byName) then
        self.constants.natures = byName
        require("src.pokemon.Stats").setNatures(byName)
        Logger.info("gen4 natures: built the 25 modifier rows from the "
                    .. "cartridge's own index rule (%d move a stat, 5 are "
                    .. "neutral) -- a Sinnoh Pokemon's nature was worth "
                    .. "nothing before this", modified)
      end
    end

    if speciesFixed > 0 then
      Logger.info("gen4 species: gave %d record(s) the field names the engine "
                  .. "reads (spatk/spdef, evYield, level1Moves, growthRate) -- "
                  .. "without these, building any Gen 4 Pokemon raises",
                  speciesFixed)
    end

    -- ...AND THE EDGES OF THE REGION, UNDER THE NAME THE ENGINE READS.
    --
    -- The Gen 4 extractor keyed its connections by the WALKING direction --
    -- up/down/left/right -- and `OverworldState:checkEdgeExit` asks for
    -- `self.map:connection(COMPASS[dir])`, where COMPASS turns "up" into
    -- "north".  So every edge answered nil and every Gen 4 map with a
    -- neighbour ended at an invisible wall.  Reported from play: *"after
    -- talking to my rival I'm supposed to walk out of town but there's an
    -- invisible wall"* -- Twinleaf's north edge, which has carried a perfectly
    -- good connection to Route 201 the whole time.
    --
    -- The extractor writes compass names now, so this is for the caches that
    -- already exist: renaming them here means the fix lands WITHOUT a
    -- re-import, and a cache that already speaks compass is left alone.
    local COMPASS_FOR = { up = "north", down = "south",
                          left = "west", right = "east" }
    local renamed, touched = 0, 0
    for _, def in pairs(self.maps or {}) do
      local conns = type(def) == "table" and def.connections
      if type(conns) == "table" then
        local moved = false
        for walking, compass in pairs(COMPASS_FOR) do
          local row = conns[walking]
          if row ~= nil then
            -- The compass key wins if both somehow exist: it is the one the
            -- engine would have been reading.
            if conns[compass] == nil then conns[compass] = row end
            conns[walking] = nil
            renamed = renamed + 1
            moved = true
          end
        end
        if moved then touched = touched + 1 end
      end
    end
    if renamed > 0 then
      Logger.info("gen4 maps: renamed %d region edge(s) on %d map(s) to the "
                  .. "compass names the engine reads", renamed, touched)
    end

    -- ...AND THE DIALOGUE BOX.
    --
    -- `FieldMessage_AddWindow` puts the text interior at tiles (2,19), 27 wide
    -- and 4 tall.  The port's box is the frame AND the interior, and it starts
    -- its text one tile in, so `tx` is one less than the cartridge's left edge
    -- and `tw` two more than its width; the same for the rows.
    --
    -- `maxPixels` is the part that actually stops the spill: `maxCols` wraps by
    -- COUNTING CHARACTERS, which is right for a fixed-width Game Boy face and
    -- meaningless for the DS's proportional one.  27 tiles is 216 pixels, and
    -- TextBox already knows how to wrap to a pixel width.
    local ds = (self.constants or {}).gen4MessageWindow
    if type(ds) == "table" and ds.width and ds.height then
      self.field.theme = self.field.theme or {}
      if self.field.theme.textBox == nil then
        self.field.theme.textBox = {
          tx = math.max(0, (ds.left or 2) - 1),
          ty = math.max(0, (ds.top or 19) - 1),
          tw = (ds.width or 27) + 2,
          th = (ds.height or 4) + 2,
          maxCols = ds.width or 27,
          maxPixels = (ds.width or 27) * 8,
        }
      end
    end

    -- THE DISTORTION WORLD'S NINE LIFTS, AS WARPS.
    --
    -- MEASURED OVER ALL 593 MAPS, and it is why this had to be read rather than
    -- worked around: the Distortion World has ONE warp event in the whole
    -- dungeon (1F, back out to Turnback Cave's D05R0109), NOTHING anywhere in
    -- Sinnoh warps into it, and nine of its eleven maps share zone_event member
    -- 0 -- the empty one.  There is no door and no walking route between its
    -- floors.  The only way down is the moving platforms.
    --
    -- 18 of the 34 moving platforms pair across floors at IDENTICAL (x, z) --
    -- follow each one's elevator-path chain and there is a platform at the same
    -- coordinates on the altitude it lands on whose index is this platform's
    -- destIndex.  They form NINE SYMMETRIC PAIRS, and a lift between two floors
    -- at the same coordinates is a WARP in a port that walks without height.
    -- Every one of the 18 ends stands on a walkable cell of its own floor's
    -- permission grid, 14 of them on a tile marked CAVE_FLOOR.
    --
    -- HERE RATHER THAN IN THE EXTRACTOR, for the reason the connection rename
    -- above is: the pairing is DERIVED, so it can be recomputed from the
    -- extracted tables on every boot and lands without a re-import of anything
    -- but the Distortion World stage itself.
    --
    -- AND NOTHING IS WRITTEN DOWN HERE.  Every coordinate comes from
    -- `gen4_distortion_world`; a cache imported before that stage existed has
    -- no such record, and then this says so once and leaves the floors alone.
    -- Cartridge data does not belong in the engine.
    local dw = self.gen4_distortion_world
    if type(dw) == "table" and type(dw.shuttles) == "table" and #dw.shuttles > 0
    then
      local defByHeader, keyByHeader = {}, {}
      for key, def in pairs(self.maps or {}) do
        if type(def) == "table" and def.header then
          defByHeader[def.header] = def
          keyByHeader[def.header] = key
        end
      end
      -- IDEMPOTENT, because `seedDefaults` runs again after the mod merge.  A
      -- second pass without this appends all eighteen a second time, and the
      -- duplicates would win or lose the `warpAt` lookup by table order.
      local already = false
      for _, def in pairs(defByHeader) do
        for _, w in ipairs(def.warps or {}) do
          if w.distortionLift then already = true; break end
        end
        if already then break end
      end
      if not already then
        -- TWO PASSES.  A warp's anchor is an INDEX into the DESTINATION map's
        -- own warp list, and on the first pass half of those warps do not exist
        -- yet -- so pass one places them and remembers where, pass two joins
        -- each end to its partner.
        local placed, refused = {}, 0
        for _, s in ipairs(dw.shuttles) do
          local def = defByHeader[s.from]
          local info = dw.maps and dw.maps[s.from]
          local destKey = keyByHeader[s.to]
          if def and info and destKey then
            local id = ("%d|%d|%d|%d"):format(s.from, s.to, s.x, s.z)
            if placed[id] == nil then
              def.warps = def.warps or {}
              local slot = #def.warps + 1
              def.warps[slot] = {
                index = slot,
                x = s.x - (info.offsetX or 0),
                y = s.z - (info.offsetZ or 0),
                destMap = destKey,
                destHeader = s.to,
                -- pass two; 1 is a placeholder that is always overwritten for
                -- a paired end, and a lift that somehow lost its partner is
                -- dropped rather than left pointing at someone else's door.
                destWarp = nil,
                distortionLift = true,
              }
              placed[id] = { def = def, slot = slot }
            end
          else
            refused = refused + 1
          end
        end
        -- SORTED, not `pairs`.  Both loops below depend on order: the slot
        -- numbers this writes are the anchors a save will carry, and the
        -- removal below shifts the indices after it.
        local ids = {}
        for id in pairs(placed) do ids[#ids + 1] = id end
        table.sort(ids)
        local paired, orphans = 0, {}
        for _, id in ipairs(ids) do
          local entry = placed[id]
          local from, to, x, z = id:match("^(%d+)|(%d+)|(%-?%d+)|(%-?%d+)$")
          local partner = placed[("%s|%s|%s|%s"):format(to, from, x, z)]
          if partner then
            entry.def.warps[entry.slot].destWarp = partner.slot
            paired = paired + 1
          else
            orphans[#orphans + 1] = entry
          end
        end
        -- A ONE-WAY LIFT IS A SOFTLOCK, so an unpaired end is removed rather
        -- than shipped with a guessed anchor.  The extractor's own check says
        -- there are none; this is what happens if a different build disagrees.
        -- HIGHEST SLOT FIRST, or removing the first orphan moves the second.
        table.sort(orphans, function(a, b) return a.slot > b.slot end)
        for _, entry in ipairs(orphans) do
          local list = entry.def.warps
          if list[entry.slot] and list[entry.slot].distortionLift then
            table.remove(list, entry.slot)
            for i = entry.slot, #list do list[i].index = i end
          end
        end
        if paired > 0 then
          Logger.info("gen4 distortion world: %d lift(s) wired as warps across "
                      .. "%d floor pairs -- the only route between its floors",
                      paired, math.floor(paired / 2))
        end
        if refused > 0 or #orphans > 0 then
          Logger.warn("gen4 distortion world: %d lift(s) had no map or no "
                      .. "offsets and %d had no partner; those floors stay "
                      .. "unreachable", refused, #orphans)
        end
      end
    elseif self.isGen4Cache then
      -- NAMED, not silent.  Without this record the Distortion World is nine
      -- disconnected floors, which is a stop rather than a blemish, and the
      -- fix is a re-import rather than anything a player can do.
      Logger.info("gen4 distortion world: this cache carries no "
                  .. "`gen4_distortion_world` record, so its floors have no "
                  .. "lifts between them (re-import to add them)")
    end

  end

  if require("src.core.GameVersion").isGen2() then
    sanitizeGen2Text(self.text)
    if boot.startMap == BOOT_DEFAULTS.startMap then
      boot.startMap = "PLAYERS_HOUSE2_F"
      boot.startX = 3
      boot.startY = 3
      boot.startFacing = "down"
    end
    if boot.playerName == BOOT_DEFAULTS.playerName then
      boot.playerName = "GOLD"
    end
    if boot.rivalName == BOOT_DEFAULTS.rivalName then
      -- ResetWRAM's InitializeNPCNames seeds wRivalName with "???" -- which
      -- is why the Cherrygrove rival's own line reads "My name's ???." The
      -- Elm's Lab officer's `special NameRival` is where it becomes SILVER.
      boot.rivalName = "???"
    end
    if boot.screens and (boot.screens.newGame == false
        or boot.screens.newGame == nil
        or boot.screens.newGame == BOOT_DEFAULTS.screens.newGame) then
      -- OakSpeech replays the professor's intro out of the ROM's own text, so
      -- it is only right for a ROM that HAS that text.  Prism writes its own
      -- introduction (engine/intro_menu.asm IntroductionSpeech) and carries no
      -- OakText* at all, so forcing the screen there hands TextBox a nil and
      -- NEW GAME dies partway through the intro.  Gate on the text existing.
      local text = self.text or {}
      local hasOakText = text._OakSpeechText1 or text._OakText1 or text.OakText1
      boot.screens.newGame = hasOakText and "OakSpeech" or false
    end
    if self.tilesets and self.tilesets.HOUSE == nil then
      self.tilesets.HOUSE = self.tilesets.TilesetTraditionalHouse
        or self.tilesets.TilesetHouse
        or self.tilesets.TilesetPlayersHouse
    end
    seedMissingGen2Tilesets(self)
    self:publishGen2Palettes()
    ensureGen2WarpFallbacks(self)
    ensureGen2HomeTextFallbacks(self)
  end
  -- the naming screen presets the importer already extracts but nothing
  -- ever read (field.presetNames)
  if boot.namePresets == nil then
    local presets = self.field.presetNames or {}
    boot.namePresets = {
      player = copy(presets.player) or { "RED", "ASH", "JACK" },
      rival = copy(presets.rival) or { "BLUE", "GARY", "JOHN" },
    }
  end
  -- the overworld's Kanto literals, same fill-if-absent contract; required
  -- here rather than at the top so core keeps out of src/world at load time
  require("src.world.FieldDefaults").seed(self)
  -- Cinnabar's quiz trainers are text_asm (no def_trainers), so the
  -- extractor never writes headers for them.  Seed the EVENT_BEAT_* /
  -- after-battle rows so Blaine's SetEventRange deactivation and talk
  -- after-text work like the other gyms (scripts/CinnabarGym.asm).
  self:seedCinnabarGymTrainerHeaders()
  -- #197: the Fighting Dojo Karate Master is text_asm, so the extractor
  -- writes no header for him -- seed one so he engages on sight and has
  -- his defeat / re-talk lines (same idea as the Cinnabar seed above).
  self:seedFightingDojoKarateMaster()
  -- #189: 1F cabin door order vs rooms map (survey zoom)
  require("src.world.SsAnneLayout").apply(self.maps)
  -- Gen2 scaffold maps use a slightly different naming convention for floor
  -- ids (REDS_HOUSE2_F, ROCK_TUNNEL_B1_F, ROUTE10_POKECENTER1_F, ...).  Add
  -- normalized aliases so every runtime map lookup can resolve the same room.
  aliasAllMaps(self.maps)
  if require("src.core.GameVersion").isGen2() then
    seedMapAliases(self.maps, GEN2_SCAFFOLD_MAP_ALIASES)
    -- Alias text_pointers by each map's camelCase label so resolveText finds
    -- Gen2 entries (text_pointers uses uppercase ID, map.def.label is camelCase)
    local tp = self.text_pointers
    local th = self.trainer_headers
    for _, mapDef in pairs(self.maps) do
      if type(mapDef) == "table" then
        local id = type(mapDef.id) == "string" and mapDef.id
        local lbl = type(mapDef.label) == "string" and mapDef.label
        if id and lbl and id ~= lbl then
          if tp and tp[id] and not tp[lbl] then tp[lbl] = tp[id] end
          if th and th[id] and not th[lbl] then th[lbl] = th[id] end
        end
      end
    end
  end
  if require("src.core.GameVersion").get() == "firered" then
    seedMapAliases(self.maps, FIRERED_STORY_MAP_ALIASES)
    preferMapAliases(self.maps, FIRERED_STORY_MAP_ALIASES)
    for mapId, textConst in pairs(FIRERED_STORY_OBJECT_TEXT) do
      local map = self.maps[mapId]
      if map and map.objects and map.objects[1] then map.objects[1].text = textConst end
    end
    for mapId, name in pairs(FIRERED_STORY_OBJECT_NAMES) do
      local map = self.maps[mapId]
      if map and map.objects and map.objects[1] then map.objects[1].name = name end
    end
    -- FireRed imports the three original Champion parties as separate named
    -- trainer records. The shared story runner selects OPP_RIVAL3 by the
    -- player's starter, so give it those imported parties in that order.
    seedTrainerPartyAlias(self.trainers, "OPP_RIVAL3",
      { "TERRY_438", "TERRY_439", "TERRY_440" })
  end
end

-- The Karate Master (FightingDojo.asm) is a text_asm object: his object has
-- no def_trainers row (DisplayTextID routes to his ASM script), so the
-- extractor emits headers only for the four blackbelts ([2]..[5]).  Seed
-- object index [1] so he behaves like the real leader:
--   * range 0: FightingDojoDefaultScript, not trainer sight, starts his
--     battle from the single tile to his left (#495),
--   * battle = his pre-battle challenge, won = "Hwa! Arrgh! Beaten!",
--   * after = the "Stay and train at Karate with us!" re-talk line.
-- Deliberately NO `event`: EVENT_BEAT_KARATE_MASTER is owned by
-- victories.lua (OPP_BLACKBELT#1) exactly like the gym leaders, and
-- engageTrainer sets header.event *before* checkVictoryRewards runs -- if
-- this header also set it, the reward's flag guard would early-return and
-- swallow the prize dialogue.  trainerDefeated tracks him via
-- defeatedTrainers[npc.id] like the leaders.
function Data:seedFightingDojoKarateMaster()
  local headers = self.trainer_headers
  if not headers then return end
  headers.FightingDojo = headers.FightingDojo or {}
  if headers.FightingDojo[1] then return end
  headers.FightingDojo[1] = {
    range = 0,
    battle = "_FightingDojoKarateMasterText",
    won = "_FightingDojoKarateMasterDefeatedText",
    after = "_FightingDojoKarateMasterStayAndTrainWithUsText",
  }
end

function Data:seedCinnabarGymTrainerHeaders()
  local headers = self.trainer_headers
  if not headers or headers.CinnabarGym then return end
  local gym = {}
  for i = 0, 6 do
    local n = i + 1
    -- object indices 2..8 are SUPER_NERD1..7; range 0 -- they only
    -- engage via talk / wrong quiz answer, never sight lines
    gym[i + 2] = {
      event = "EVENT_BEAT_CINNABAR_GYM_TRAINER_" .. i,
      range = 0,
      battle = "_CinnabarGymSuperNerd" .. n .. "BattleText",
      won = "_CinnabarGymSuperNerd" .. n .. "EndBattleText",
      after = "_CinnabarGymSuperNerd" .. n .. "AfterBattleText",
    }
  end
  headers.CinnabarGym = gym
end

-- POKEPORT_DATA_DIR points a test runner at another dataset root (the
-- ROM-free fixture set, tests/fixture_data); unset -- every shipped build
-- -- the generated modules load exactly as before.  loadfile skips the
-- require cache, so each overridden load hands back fresh tables.
local function loadModule(dir, name)
  if dir then
    local chunk, err = loadfile(dir .. "/" .. name .. ".lua")
    if not chunk then return false, err end
    return pcall(chunk)
  end
  return pcall(require, "data.generated." .. name)
end

-- Which set applies is decided by the CACHE, not by whichever version happens
-- to be selected.  Asking GameVersion works only if the caller set it first,
-- and a loader that silently demands the wrong modules when it was not is an
-- ordering trap -- the kind that works in the launcher and fails in a test, or
-- the other way round.  save_layout is the marker: it is written by the Gen 3
-- extractor and by nothing else.
local function requiredModules(dir)
  -- GEN 4 IS TESTED FIRST, and the marker is a module only its extractor
  -- writes.  A Platinum cache has no save_layout -- that is the Gen 3 marker
  -- and writing one would make it claim to be Gen 3 -- so the two tests cannot
  -- both answer yes, and testing gen4 first says so rather than relying on it.
  local gen4 = loadModule(dir, "gen4_map_headers")
  local gen3 = (not gen4) and loadModule(dir, "save_layout") or false

  local out = {}
  for _, name in ipairs(SHARED_MODULES) do out[#out + 1] = name end
  local set = CLASSIC_MODULES
  if gen4 then set = GEN4_MODULES
  elseif gen3 then set = GEN3_MODULES end
  for _, name in ipairs(set) do out[#out + 1] = name end

  -- The third return is NEW and the first two are unchanged, so every existing
  -- caller keeps the answer it had: a cache with no gen4 marker takes exactly
  -- the path it took before this branch existed.
  return out, gen3 and true or false, gen4 and true or false
end

-- MAP EDITOR OVERLAY, applied LAST and over the top.
--
-- The editor never writes into data/generated_* -- that tree is rebuilt from
-- the cartridge on every import, so an edit stored there would be destroyed by
-- the next one, silently. It keeps its patches in the save directory and they
-- are laid over whatever the load produced, which is what lets a re-import
-- replace the base and keep the edits.
--
-- A METHOD, BECAUSE IT HAS TO RUN TWICE. See Game:load: mods load AFTER this
-- data does, and a content mod may patch the very maps the editor has edits
-- for -- which is not hypothetical, it is what a map pack exported from this
-- editor and installed back into it does by construction. `maps:patch`
-- replaces the def's `objects` wholesale with the snapshot taken at export, so
-- an NPC added after that export was applied here, overwritten there, and gone
-- with every step of the process reporting success.
--
-- The working copy wins. A mod is published content and the edit store is what
-- the reader is editing RIGHT NOW; when the two describe the same map, the one
-- they can still see and change is the one that should be on screen.
--
-- Wrapped whole: a malformed edit file must not be able to stop the game
-- booting. The worst case is the edits do not apply and the log says so.
function Data:applyMapEditorOverlay(why)
  local okEdits, applied, stale = pcall(function()
    local ME = require("tools.map-editor.MapEdits")
    local store = ME.load()
    local game = require("src.core.GameVersion").current
    game = (type(game) == "function" and game()) or game
    -- self.tilesets too: a per-cell tile edit mints a block INTO a tileset,
    -- and a map block patch that names one resolves to a number only after
    -- that append has run. Passing only the maps left every such edit
    -- unresolved and silently dropped.
    -- self.sprites too: a sheet the editor imported has to be on
    -- `data.sprites` before any map's objects resolve, or every NPC using it
    -- falls through NPC.resolveSpriteDef to SPRITE_RED and the import looks
    -- like it never happened.
    -- THE KEY THIS READS UNDER, AND THE KEYS THE FILE ACTUALLY HAS.
    --
    -- These are two different variables set on two different code paths -- the
    -- editor files edits under the version the launcher handed IT, and this
    -- reads `GameVersion.current`, which defaults to "red" and only moves when
    -- something calls `set`. When they disagree the save worked, the load
    -- worked, `applyAll` found no bucket, and the reader's NPC is simply not
    -- in the world with nothing anywhere saying why.
    --
    -- Logged whenever the store has anything at all, so the comparison is
    -- there to be made rather than inferred from a zero.
    pcall(function()
      local keys = {}
      for key, g in pairs(store.games or {}) do
        local maps, added = 0, 0
        for _, m in pairs(g.maps or {}) do
          maps = maps + 1
          added = added + #((m and m.added) or {})
        end
        keys[#keys + 1] = string.format("%s(%d map/%d added)", key, maps, added)
      end
      -- Once, on the boot pass. The second pass reads the same file under the
      -- same key and repeating it would just make the log harder to read.
      if #keys > 0 and (why == nil or why == "boot") then
        Logger.info("map editor: reading as '%s'; store holds %s",
                    tostring(game or ""), table.concat(keys, ", "))
        if (store.games or {})[tostring(game or "")] == nil then
          Logger.warn("map editor: NOTHING IS FILED UNDER '%s' - the edits in "
            .. "this store belong to another game, so none of them will apply",
            tostring(game or ""))
        end
      end
    end)
    local n, stale = ME.applyAll(store, tostring(game or ""), self.maps,
                                 self.tilesets, self.sprites)
    -- WILD ENCOUNTERS ARE THEIR OWN DATASET, keyed by the same map ids but
    -- not carried on a map def -- so they need their own pass. Folded in here
    -- rather than into applyAll because applyAll's contract is "these maps and
    -- these tilesets", and it is handed neither of the things this touches.
    if type(self.encounters) == "table" and ME.applyWilds then
      n = (n or 0) + (ME.applyWilds(store, tostring(game or ""),
                                    self.encounters) or 0)
    end
    return n, stale
  end)
  if okEdits and (applied or 0) > 0 then
    Logger.info("map editor: %d edit(s) applied (%s)", applied,
                tostring(why or "boot"))
    -- STALE EDITS ARE REPORTED, NEVER SWALLOWED. An edit the player made and
    -- can no longer see is the one failure this whole overlay exists to avoid,
    -- and after a re-import an object index really can stop existing.
    for _, entry in ipairs(stale or {}) do
      Logger.warn("map editor: stale edit -- %s", tostring(entry))
    end
  elseif not okEdits then
    Logger.warn("map editor: edits not applied (%s)", tostring(applied))
  end
  return applied or 0
end

function Data:load()
  local dir = os.getenv("POKEPORT_DATA_DIR")
  local required, isGen3Cache, isGen4Cache = requiredModules(dir)
  self.isGen3Cache = isGen3Cache
  self.isGen4Cache = isGen4Cache
  local isRequired = {}
  for _, name in ipairs(required) do isRequired[name] = true end
  -- FRLG: two generated modules cannot be produced for FireRed at all,
  -- and neither is fatal.
  --   scenes -- gen3_discover's scene-loader matching is written against
  --     Emerald's graphics/palette library functions. Per the project
  --     author, Emerald's own scenes were HAND-AUTHORED regardless, so
  --     there is nothing to derive. Gen3Scene already treats a missing
  --     scene as "a screen with no backdrop, not an error".
  --   field -- FireRed's heal-location stage produces nothing yet; Data
  --     builds `field` up itself (`self.field = self.field or {}`).
  -- Degrade to an empty table rather than refusing to boot, which is
  -- what happens today and what sends the user back to Import.
  local OPTIONAL_GEN3 = { scenes = { _roles = {} }, field = {} }
  for _, name in ipairs(required) do
    local ok, mod = loadModule(dir, name)
    if not ok and isGen3Cache and OPTIONAL_GEN3[name] then
      mod, ok = OPTIONAL_GEN3[name], true
    end
    if not ok then
      if dir then
        error(("missing data module '%s/%s.lua' (POKEPORT_DATA_DIR).\n(%s)")
              :format(dir, name, mod))
      end
      error(("missing generated data module 'data/generated/%s.lua'.\n" ..
             "Import the ROM again or rebuild developer data.\n(%s)")
            :format(name, mod))
    end
    self[name] = mod
  end
  local blocked = {}
  -- A GEN 4 CACHE IS BLOCKED FROM THE SAME MODULES AND FOR THE SAME REASON.
  -- The version overlay is additive, so any module Platinum did not write
  -- still resolves -- to the ROOT cache, which is Red's.  That is not
  -- hypothetical: it is exactly how NEW GAME on Emerald opened Red's intro in
  -- Red's house before the Gen 3 block existed, and Gen 4 writes even fewer of
  -- these than Gen 3 does.
  if isGen3Cache or isGen4Cache then
    for _, name in ipairs(CLASSIC_ONLY) do blocked[name] = true end
  end
  for _, name in ipairs(OPTIONAL) do
    if isRequired[name] then goto continue end
    if blocked[name] then
      -- Deliberately not even attempted.  It would very likely SUCCEED -- the
      -- root cache is Red's and the overlay does not hide it -- and the result
      -- would be another game's data wearing this one's name.
      self[name] = nil
      Logger.info("gen3 cache: '%s' is a Gen 1/Gen 2 module and is not read "
                  .. "on this dataset (the un-prefixed cache would have "
                  .. "supplied another game's)", name)
      goto continue
    end
    local ok, mod = loadModule(dir, name)
    if ok and isGen3Cache and GEN3_BORROWED[name] then
      Logger.warn("gen3 cache: '%s' came from the un-prefixed cache -- this "
                  .. "is Gen 1/Gen 2 art standing in until the Gen 3 stage "
                  .. "exists, not this cartridge's", name)
    end
    self[name] = ok and mod or nil
    if not ok then
      -- SAY WHY.  "missing" covered two very different failures: a file that
      -- was never written, and a file that EXISTS but failed to load -- which
      -- is how a constant-table overflow in map_scripts.lua read as a
      -- missing optional feature instead of as the load error it was.
      Logger.warn("optional data module '%s' unavailable (feature disabled): %s",
                  name, tostring(mod))
    end
    ::continue::
  end
  -- THE GEN 4 CACHE'S OWN MODULES, WHICH NOTHING WAS READING.
  --
  -- The Platinum extractor writes these four, and every Gen 4 screen reads
  -- `game.data.gen4_<name>` -- but no list here ever named them, so Data:load
  -- never put one on the table.  Every consumer degrades when its record is
  -- absent, which is why this failed silently and completely: the title drew
  -- its border field with no logo on it (a black screen with PRESS START),
  -- Gen4MainMenu sized its boxes from the engine's defaults instead of the
  -- cartridge's, the bag and the trainer card fell back to the Game Boy frame
  -- ("this cache carries no pocket names", "no badge case art"), the starter
  -- select had no models, and Gen4RowanIntro skipped the opening outright
  -- ("this cache carries no `gen4_intro` record").  One missing list.
  --
  -- Optional, each one, and each says so in the log: a cache imported before
  -- a stage existed must boot and lose that screen's art, not refuse to start.
  if isGen4Cache then
    for _, name in ipairs(GEN4_PREFIXED) do
      local ok, mod = loadModule(dir, name)
      self[name] = ok and mod or nil
      if not ok then
        Logger.warn("gen4 cache: '%s' is missing (%s) -- the screens that "
                    .. "read it fall back to the engine's own art", name,
                    tostring(mod))
      end
    end

    -- ITEM IDS, PUBLISHED AS STRINGS AS WELL -- THE BAG'S KEYS ARE STRINGS.
    --
    -- Measured on a Platinum cache: `items` carries 446 entries keyed 0..445
    -- and **zero** string keys, while the bag is string-keyed throughout
    -- (`Bag.isBadge` does `id:find("BADGE")`).  `itemKey` in `Gen4Commands`
    -- returns the id unchanged when `items[id]` exists -- which on a
    -- numerically-keyed table is the NUMBER -- and `Bag.add` then indexes it:
    --
    --     Bag.lua:59: attempt to index local 'id' (a number value)
    --
    -- Measured through the engine's own path, not a hand call:
    -- `Commands.g4_give_item(ctx, 17, 2)` and `(ctx, 4, 2)` both raised that.
    -- So EVERY pickup, gift and Mart purchase in Sinnoh raised, and the bag
    -- screen's `data.items[id]` found nothing either -- which is the play
    -- report's "no item art or descriptions", from the same one cause.
    --
    -- AN ALIAS RATHER THAN A NUMERIC BAG: those keys are a SAVE format shared
    -- with four other cartridges, and `ITEM_%03d` is the spelling `itemKey`
    -- already reaches for on its second branch -- so this makes that branch
    -- able to succeed rather than inventing a convention.  The alias is the
    -- SAME TABLE, not a copy, so a mod that patches one sees the other.
    --
    -- Collected before it is assigned: adding keys to a table while `pairs`
    -- is walking it is undefined in Lua.
    if type(self.items) == "table" then
      local aliases = {}
      for id, def in pairs(self.items) do
        if type(id) == "number" then
          aliases[("ITEM_%03d"):format(id)] = def
        end
      end
      local added = 0
      for key, def in pairs(aliases) do
        if self.items[key] == nil then
          self.items[key] = def
          added = added + 1
        end
      end
      if added > 0 then
        Logger.info("gen4 items: published %d item(s) under ITEM_nnn as well "
                    .. "as their numeric id -- the bag's keys are strings",
                    added)
      end
    end

    -- THE PARTY ICONS, PUBLISHED UNDER THE NAME EVERY SCREEN ALREADY ASKS FOR.
    --
    -- Reported from play: "in the pokemon party menus the pokemon party sprites
    -- are missing". They were not broken, they were NEVER EXTRACTED -- nothing
    -- had opened pl_poke_icon.narc -- so `data.icons` was nil and
    -- Gen4PartyMenu:iconFor found nothing to draw.
    --
    -- The Gen 4 extractor writes them inside `gen4_species_sprites`, because
    -- that is the stage that already walks the species; `icons` is where the
    -- SCREENS look, and Gen3PartyMenu, the box, the summary page and the
    -- Poketch's party app all look there too. Lifting it here is what lets all
    -- of them work without a Gen 4 branch each.
    --
    -- ...AND IT HAS TO WIN, BECAUSE `icons` ON A GEN 4 CACHE IS RED'S.
    --
    -- Reported from play: "missing pokemon party sprites from the pokemon
    -- start menu". The lift above was right and never ran. `icons` used to sit
    -- in CLASSIC_ONLY, which blocks it; it left when Emerald gained an
    -- icons.lua of its own, and nothing put it back for Gen 4 -- so on a
    -- Sinnoh cache it is not required, not blocked, and merely OPTIONAL, and
    -- the overlay is additive. Platinum writes no icons.lua, so
    -- `require("data.generated.icons")` walks through to the ROOT cache, which
    -- is Red's (its cachePrefix is ""). `self.icons` came back non-nil, the
    -- `== nil` guard declined, and every Sinnoh party drew from Kanto's table:
    -- a wrong icon below 152 and, above it, nothing at all -- which is the
    -- Poke Ball `Gen4PartyMenu:drawIcon` falls back to. Exactly the report.
    --
    -- This is the same shape as the type chart, the abilities, the move
    -- effects and the ball pocket before it: one name, resolved from two
    -- places that never meet.
    --
    -- So on a Gen 4 cache the CARTRIDGE'S OWN table wins outright. Nothing
    -- writes an un-prefixed icons.lua for Sinnoh, so there is no honest
    -- candidate for `self.icons` to already hold here; when a Gen 4 extractor
    -- stage does write one, this is the line that has to learn the difference.
    --
    -- `loadModule` with an explicit dir reads that directory and nothing else,
    -- so the dir case was never wrong -- it is the mounted-overlay path, where
    -- `require` cannot be scoped to one cache, that needed this.
    do
      local sprites = self.gen4_species_sprites
      local icons = sprites and sprites.icons
      if icons and icons.bySpecies then
        self.icons = icons
      end
    end

    -- SINNOH'S TRAINER ART IS ALREADY IN COLOUR, AND NOTHING SAID SO.
    -- `Sprites.markFormsTrueColor` has the whole story; the short version
    -- is that the player's back pic was being repainted with Mew's SGB
    -- palette, which is the reported "red hue overlay".  Stamped here
    -- rather than in the extractor so an existing cache is fixed without a
    -- re-import.
    do
      local marked = require("src.pokemon.Sprites")
                       .markFormsTrueColor(self.field)
      if marked > 0 then
        Logger.info("gen4 player: %d player form(s) marked true-colour, "
                    .. "so the back pic keeps its own palette", marked)
      end
    end

    -- A PLATINUM TM CARRIES NO `machine` RECORD, and that one absent field is
    -- what made every TM and HM answer "This isn't the time to use that!".
    -- `ItemEffects.markGen4Machines` has the whole story; it derives the record
    -- from the cartridge's own `fieldUseFunc` and `constants.tmhmMoves` and
    -- refuses to stamp anything if the two disagree.  Here rather than in the
    -- extractor for the same reason as the line above: an existing cache is
    -- fixed without a re-import.
    do
      local okM, stamped = pcall(function()
        return require("src.inventory.ItemEffects").markGen4Machines(self)
      end)
      if okM and (stamped or 0) > 0 then
        Logger.info("gen4 items: %d TM/HM machine record(s) derived, so the "
                    .. "bag can teach them", stamped)
      elseif not okM then
        Logger.warn("gen4 items: the machine records could not be derived (%s)",
                    tostring(stamped))
      end
    end
  end
  -- Hand the cartridge's own battle tables to the two modules that would
  -- otherwise have to approximate them.  Both are no-ops on a Gen 1/Gen 2
  -- cache, which has neither key: Growth keeps its six polynomials and Stats
  -- keeps the DV/stat-exp path untouched.
  --
  -- This runs BEFORE seedDefaults so a mod that overrides a growth curve or a
  -- nature still wins -- the cartridge is the floor, not the ceiling.
  local constants = self.constants or {}
  if constants.experienceTables then
    require("src.pokemon.Growth").setTables(constants.experienceTables)
  end
  if constants.natures then
    require("src.pokemon.Stats").setNatures(constants.natures)
  end

  -- before the mod loader runs: the deep registries fold over these
  self:seedDefaults()
  -- the top-level keys a pristine load leaves behind, so reloadGenerated can
  -- strip whatever a mod merge added since; kept on self (assigned before the
  -- scan so it counts itself) because tests load other tables through this
  -- method, and a shared upvalue would let them clobber the singleton's set
  local pristine = {}
  self._pristineKeys = pristine
  for key in pairs(self) do pristine[key] = true end
  self:applyMapEditorOverlay("boot")

  -- THE THEME HAS TO BE LOADED, and it was not.
  --
  -- Theme.load is what folds `field.theme` into the shared geometry -- the
  -- dialogue box's corner, its width, the cursor codes -- and the ONLY caller
  -- was the dev hot-reload path.  On a normal boot it never ran, so every
  -- override a dataset ships was dead on arrival and Theme kept Red's
  -- twenty-tile box with its eighteen-column budget.
  --
  -- On Gen 1 and Gen 2 that is invisible, because Red's box IS the default.
  -- On Emerald it is not: the message window derived from the cartridge is
  -- twenty-eight tiles and twenty-six columns, and none of it reached the
  -- screen.  It is also what decides the UI SURFACE (Theme.uiSize), so the
  -- box, the field and the Birch speech were negotiating over a size that had
  -- already been decided by a generation nobody was playing.
  --
  -- It runs here, after the version overrides above have written
  -- field.theme, because loading it before them would merge an empty table.
  do
    local ok, Theme = pcall(require, "src.ui.Theme")
    if ok and Theme and Theme.load then pcall(Theme.load, self) end
  end

  Logger.info("generated data loaded (%d maps, %d species, %d moves)",
              (function() local n = 0 for _ in pairs(self.maps) do n = n + 1 end return n end)(),
              (function() local n = 0 for _ in pairs(self.pokemon) do n = n + 1 end return n end)(),
              (function() local n = 0 for _ in pairs(self.moves) do n = n + 1 end return n end)())
end

-- Drop every namespace the mod merge created and evict the generated modules
-- from package.loaded, so the next load() re-reads them off disk instead of
-- handing back the cached tables.  Two callers:
--   * reloadGenerated below (dev hot reload)
--   * main.lua, when the launcher closes the save editor -- the editor may
--     have loaded the OTHER game's cache, and require would otherwise serve
--     those modules to a subsequent Play (see CacheFs.unmountVersion, which
--     clears the matching read-path overlay).
function Data:unloadGenerated()
  local pristine = self._pristineKeys
  if pristine then
    for key in pairs(self) do
      if not pristine[key] then self[key] = nil end
    end
  end
  -- EVERY name, from all four lists.  This used to iterate one flat MODULES
  -- table; splitting that per generation left this reading a global that no
  -- longer existed, so `ipairs(nil)` threw the moment anything unloaded --
  -- which is on the path the launcher takes when it closes the save editor,
  -- and on every version switch.  A module left in package.loaded is the
  -- other half of that bug: the next Play would be served the PREVIOUS game's
  -- tables, which is exactly what this function exists to prevent.
  for _, list in ipairs({ SHARED_MODULES, CLASSIC_MODULES, GEN3_MODULES,
                          OPTIONAL }) do
    for _, name in ipairs(list) do
      package.loaded["data.generated." .. name] = nil
    end
  end
  -- ...AND THE ONE CACHE THAT LIVES OUTSIDE THIS TABLE.
  --
  -- Gen2Commands memoises field.objectScriptBase in a module upvalue the
  -- first time a script addresses an object, and its own comment says the
  -- cached base belongs to one loaded game.  reloadGenerated cleared it and
  -- nothing else did -- so it was right for a developer hot reload and wrong
  -- for the path every player takes, which is quitting to the launcher and
  -- picking a different cartridge.  Crystal's base standing in Gold's game
  -- is the failure the memo exists to prevent, one game too late.
  --
  -- Here rather than beside reloadGenerated's call because THIS is the choke
  -- point both paths pass through; the duplicate call reloadGenerated now
  -- makes is a second assignment of nil.
  pcall(function()
    require("src.script.Gen2Commands").g2ResetObjectBase()
  end)
  -- ...AND THE HAND-PORTED SCRIPTS, WHICH ARE NOT `data.generated`.
  --
  -- Reported from play: after quitting Emerald to the launcher and loading
  -- FireRed, an NPC said "TEXT 1FC45B" -- a constant that exists in Emerald's
  -- cache and nowhere in FireRed's, on a map id both games have.
  --
  -- data/scripts/init.lua does its work IN ITS CHUNK BODY: it walks the
  -- hand-ported files into MapScripts.attachBase and calls
  -- Gen2ScriptVM.register / Gen3ScriptVM.register on the loaded dataset.  The
  -- loop above evicts `data.generated.*` and stops there, so on the second
  -- boot `require("data.scripts.init")` was served the cached module and the
  -- body never ran again -- the log says so plainly: two "script vm: N maps
  -- attached" lines for the first game and none at all for the second.  The
  -- second cartridge ran on the first one's scripts for the whole session.
  --
  -- Both halves are needed and in this order.  Evicting alone would re-run
  -- the registration INTO a base that still holds the old game's, and
  -- attachBase merges rather than replaces -- so every talk entry the new
  -- game does not redefine would still answer.  Resetting alone would empty
  -- the base and leave nothing to refill it.
  --
  -- By prefix rather than by a list: these files require each other freely
  -- and a named list is a list that goes stale.
  for name in pairs(package.loaded) do
    if type(name) == "string"
       and (name == "data.scripts" or name:sub(1, 13) == "data.scripts.") then
      package.loaded[name] = nil
    end
  end
  pcall(function()
    require("src.script.MapScripts").resetBase()
  end)
end

-- dev-mode hot reload only (src/dev/HotReload.lua): drop every namespace the
-- mod merge created, then re-require the generated modules so base records
-- return to their on-disk values even where a mod edited them in place
function Data:reloadGenerated()
  -- Gen2Commands caches field.objectScriptBase; a reload can change it
  pcall(function()
    require("src.script.Gen2Commands").g2ResetObjectBase()
  end)
  self:unloadGenerated()
  self:load()
end

-- Resolve a dotted target path, creating empty tables on the way.  Only the
-- mod merge calls this; a vanilla boot never does, so an unmodded Data
-- table is byte-identical to a pre-registry-v2 one.
function Data.ensure(data, path)
  local node = data
  for key in path:gmatch("[^%.]+") do
    if node[key] == nil then node[key] = {} end
    node = node[key]
  end
  return node
end

-- Resolve a TEXT_* constant on a map to a plain string (or nil if the text
-- needs a hand-ported script; see data/scripts/).
function Data:resolveText(mapLabel, textConst)
  local entry = self:textEntry(mapLabel, textConst)
  if not entry then return nil end
  if entry.text then
    local s = self.text[entry.text]
    if s then return s, entry.asm end
  end
  -- A text_asm entry names its wrapper label but carries no string, because
  -- the extractor cannot follow asm.  A handful of those wrappers are plain
  -- `text_far <label> / text_end` pairs with no logic at all -- BoulderText
  -- (home/overworld_text.asm:16), MartSignText, PokeCenterSignText -- and
  -- for those the extracted _Label string IS the whole behavior, so the
  -- boulders and signs printed nothing at all (#318).  Wrappers that really
  -- do run logic have no _Label string to find, so they still fall through
  -- to their hand-ported script in data/scripts/.
  -- needsAsm comes back false here on purpose: showMapText's warning tells
  -- the reader to go port a script, and for these there is nothing to port.
  if entry.label then
    local s = self.text["_" .. entry.label]
    if s then return s, false end
  end
  return nil, entry.asm
end

-- The raw text-pointer entry (carries mart/nurse/pc markers and the label).
function Data:textEntry(mapLabel, textConst)
  -- A text id is a CONSTANT NAME.  A lowering that hands over a raw number
  -- instead is a bug in that lowering, but it must not take the script runner
  -- down with it -- the gsub below throws on a number, which killed every
  -- script on the map rather than just the one line.  Answer "no such text"
  -- and let show_text fall through to its literal-string path.
  if type(textConst) ~= "string" then return nil end
  -- same guard as trainerHeader below: text_pointers is a SHARED module and
  -- should always be here, but a bare index is a crash rather than a miss
  local pointers = self.text_pointers
  if not pointers then return nil end
  local perMap = pointers[mapLabel]
  if not perMap then return nil end
  local entry = perMap[textConst]
  if entry then return entry end
  -- Gen2 maps.lua uses TEXT_X_OBJ_NNN constants; text_pointers drops the _OBJ_ part
  local stripped = textConst:gsub("_OBJ_(%d+)$", "_%1")
  return stripped ~= textConst and perMap[stripped] or nil
end

-- Trainer sight/dialogue header for a map object (or nil).
--
-- `trainer_headers` IS A CLASSIC_MODULES TABLE -- Gen 1 and Gen 2 only, and
-- deliberately absent from a Gen 3 cache, because a GBA cartridge has no
-- equivalent structure: Hoenn files a trainer's type, sight range and id on
-- the object event itself (gen3Trainer / sightRange / gen3TrainerId).
--
-- So on Emerald this is called with no table to read, and the bare index
-- raised.  Not on load and not on a script -- on the first frame a trainer
-- sprite came on screen, because checkTrainerSight asks every frame and the
-- object's own range is only preferred OVER the header's, which means the
-- header is still looked up first.  Every other reader in this file already
-- guards the same table (seedFightingDojoKarateMaster,
-- seedCinnabarGymTrainerHeaders); this one did not.
--
-- Answering nil is the right answer rather than a fallback: a Gen 3 object
-- carries its own range, and the caller already treats an absent header as
-- "whatever the cartridge said".
function Data:trainerHeader(mapLabel, objIndex)
  local headers = self.trainer_headers
  if not headers then return nil end
  local perMap = headers[mapLabel]
  return perMap and perMap[objIndex] or nil
end

return Data
