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

local function aliasMap(maps, source)
  local alias = normalizeMapId(source)
  if alias == source or maps[alias] or not maps[source] then return end
  local mapped = copy(maps[source])
  mapped.id = alias
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
      }
    end
    if type(avatars) == "table" and self.field.playerForms == nil then
      self.field.playerForms = {
        order = { "boy", "girl" },
        boy = { label = "BOY", walk = avatars.boy, bike = avatars.boyBike,
                surf = avatars.boySurf, underwater = avatars.boyUnderwater },
        girl = { label = "GIRL", walk = avatars.girl, bike = avatars.girlBike,
                 surf = avatars.girlSurf,
                 underwater = avatars.girlUnderwater },
      }
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
  local gen3 = loadModule(dir, "save_layout")
  local out = {}
  for _, name in ipairs(SHARED_MODULES) do out[#out + 1] = name end
  for _, name in ipairs(gen3 and GEN3_MODULES or CLASSIC_MODULES) do
    out[#out + 1] = name
  end
  return out, gen3 and true or false
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
  local required, isGen3Cache = requiredModules(dir)
  self.isGen3Cache = isGen3Cache
  local isRequired = {}
  for _, name in ipairs(required) do isRequired[name] = true end
  for _, name in ipairs(required) do
    local ok, mod = loadModule(dir, name)
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
  if isGen3Cache then
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
