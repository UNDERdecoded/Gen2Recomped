-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Loads generated data from either the private first-boot cache or the
-- optional source-tree developer build.

local Logger = require("src.core.Logger")

local Data = {}

local MODULES = {
  "constants", "maps", "tilesets", "text", "text_pointers",
  "trainer_headers", "font", "sprites", "pokemon", "moves", "items",
  "type_chart", "trainers", "encounters", "field", "battle_anims",
}

-- Optional for compatibility with developer and stale caches.
-- map_layouts and map_tilesets are the Gen 3 world modules: Gen 1 and Gen 2
-- fold blockdata into maps.lua and tilesets.lua, but a Gen 3 layout is shared
-- between maps and its tilesets come in primary/secondary pairs, so both are
-- their own module and both are absent on a Gen 1/Gen 2 cache.
local OPTIONAL = { "audio", "palettes", "icons", "map_scripts", "unown_puzzle",
                   "unown_dex", "map_layouts", "map_tilesets" }

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
  screens = { splash = "IntroMovie", title = "TitleState", newGame = "OakSpeech" },
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
  for _, name in ipairs(MODULES) do
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
  for _, name in ipairs(OPTIONAL) do
    local ok, mod = loadModule(dir, name)
    self[name] = ok and mod or nil
    if not ok then
      -- SAY WHY.  "missing" covered two very different failures: a file that
      -- was never written, and a file that EXISTS but failed to load -- which
      -- is how a constant-table overflow in map_scripts.lua read as a
      -- missing optional feature instead of as the load error it was.
      Logger.warn("optional data module '%s' unavailable (feature disabled): %s",
                  name, tostring(mod))
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
  for _, name in ipairs(MODULES) do
    package.loaded["data.generated." .. name] = nil
  end
  for _, name in ipairs(OPTIONAL) do
    package.loaded["data.generated." .. name] = nil
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
  local perMap = self.text_pointers[mapLabel]
  if not perMap then return nil end
  local entry = perMap[textConst]
  if entry then return entry end
  -- Gen2 maps.lua uses TEXT_X_OBJ_NNN constants; text_pointers drops the _OBJ_ part
  local stripped = textConst:gsub("_OBJ_(%d+)$", "_%1")
  return stripped ~= textConst and perMap[stripped] or nil
end

-- Trainer sight/dialogue header for a map object (or nil).
function Data:trainerHeader(mapLabel, objIndex)
  local perMap = self.trainer_headers[mapLabel]
  return perMap and perMap[objIndex] or nil
end

return Data
