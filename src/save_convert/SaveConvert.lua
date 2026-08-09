-- SaveConvert -- the runtime-facing entry point the launcher UI calls to
-- turn a vanilla battery save into this project's in-memory save table, and
-- back out to a raw .sav image.
--
-- Two codecs sit behind it, picked by the generation of the game the save
-- belongs to: GenSave for Gen1 (Red/Blue/Yellow) and Gen2Save for Gen2
-- (Gold/Silver).  Both battery images are 32768 bytes, so nothing upstream
-- can tell them apart -- routing has to be by version, and before this
-- split a Gold save was decoded with Gen1 offsets, which lost the day-care
-- pens and all sixteen badges outright (they live nowhere Gen1 has a field
-- for).  See src/save_convert/Gen2Save.lua's header.
--
-- This is the ONE place the engine, the tests and the CLI
-- (tools/save_convert/convert.lua) share: the codecs, the crosswalk
-- data loading, the merge over new-game defaults, and the version tag all
-- live here so every consumer behaves identically.
--
-- Pure Lua, no love.* dependency at require time: GenSave and the crosswalk
-- tables load through `require`, exactly how src/core/Data.lua pulls the
-- generated modules -- which resolves under both plain luajit (package.path
-- "./?.lua") for the headless CLI/tests and love.filesystem for a fused
-- build, with an OS-path fallback for odd working directories. `love` is only
-- ever referenced inside guarded fallbacks, so running under stock Lua never
-- touches it.
--
-- When a caller names the game a save belongs to, the generated tables come
-- out of that version's ROM cache through CacheFs instead: the launcher does
-- its importing before the cache is mounted onto the un-prefixed paths, so
-- require alone cannot see them there (#420).

local GenSave = require("src.save_convert.GenSave")
local Gen2Save = require("src.save_convert.Gen2Save")

local SaveConvert = {}

SaveConvert.SAVE_SIZE = GenSave.SAVE_SIZE

-- ------------------------------------------------------------------
-- Crosswalk data loading (cached).  Mirrors src/core/Data.lua: prefer
-- `require` (works headless via package.path and fused via love's package
-- searcher); fall back to love.filesystem.load, then a plain dofile, for
-- the rare case a host has an unusual cwd or module path.
-- ------------------------------------------------------------------

-- { require-module-path, os-relative-file-path } for each table the codec
-- needs.  pokemon/moves/items/maps come from the shared generated data;
-- charmap/event_flags are the save-convert-specific crosswalks.
local DATA_MODULES = {
  pokemon    = { "data.generated.pokemon",          "data/generated/pokemon.lua" },
  moves      = { "data.generated.moves",            "data/generated/moves.lua" },
  items      = { "data.generated.items",            "data/generated/items.lua" },
  maps       = { "data.generated.maps",             "data/generated/maps.lua" },
  charmap    = { "src.save_convert.data.charmap",   "src/save_convert/data/charmap.lua" },
  eventFlags = { "src.save_convert.data.event_flags", "src/save_convert/data/event_flags.lua" },
}

-- Gen2's text table is not Gen1's: it comes out of the ROM cache the same
-- way the other generated tables do (byte -> glyph, keyed by the byte's
-- decimal value as a string -- Gen2Save.setCharmap takes that shape).
local GEN2_CHARMAP = { "data.generated.charmap", "data/generated/charmap.lua" }

-- field.lua carries the two Gen2-only tables the codec needs to import a
-- cartridge save's flags: EngineFlags' row -> (WRAM address, bit) rows, and
-- the wVisitedSpawns bit -> map pairing behind the FLY list.  It is optional:
-- a cache built before the extractor emitted them just decodes fewer flags.
local GEN2_FIELD = { "data.generated.field", "data/generated/field.lua" }

local function loadTable(requirePath, filePath)
  local ok, mod = pcall(require, requirePath)
  if ok and type(mod) == "table" then return mod end
  -- fused build with an unexpected module path: read straight off the
  -- mounted filesystem (love is a global here, only ever touched when it
  -- actually exists -- stock Lua never reaches this branch)
  if love and love.filesystem and love.filesystem.getInfo
     and love.filesystem.getInfo(filePath) then
    local chunk = love.filesystem.load(filePath)
    if chunk then
      local m = chunk()
      if type(m) == "table" then return m end
    end
  end
  local chunk = loadfile(filePath)
  if chunk then
    local m = chunk()
    if type(m) == "table" then return m end
  end
  return nil, ("cannot load save-convert data module %q (tried require %q and file %q)")
    :format(requirePath, requirePath, filePath)
end

-- The four generated tables live in one game's ROM cache, and the launcher
-- reaches this code before that cache is on the un-prefixed read path:
-- CacheFs.mountVersion only runs from main.lua's bootGame (after Play), and
-- Blue/Yellow keep their cache under GameVersion.cachePrefix.  So a bare
-- require sees Red's copy at best, and nothing at all in a fused portable
-- build (the game folder is only readable through CacheFs's PhysFS mount) --
-- read the tables out of the cache whenever the caller names the game the
-- save belongs to, and let the require path above cover everything else
-- (#420).
local function loadCacheTable(gameVersion, filePath)
  if not (gameVersion and love and love.filesystem) then return nil end
  if not filePath:match("^data/generated/") then return nil end
  local okc, CacheFs = pcall(require, "src.import.CacheFs")
  local okg, GameVersion = pcall(require, "src.core.GameVersion")
  if not (okc and okg and type(CacheFs) == "table") then return nil end
  local info = GameVersion.VERSIONS[gameVersion]
  if not info then return nil end
  -- CacheFs.prefix is launcher-owned global state (it points at whatever
  -- import last ran), so borrow it for this read and put it back.
  local saved = CacheFs.prefix
  CacheFs.prefix = info.cachePrefix
  local okr, bytes = pcall(CacheFs.read, filePath)
  CacheFs.prefix = saved
  if not (okr and type(bytes) == "string") then return nil end
  local chunk = loadstring(bytes, "@" .. info.cachePrefix .. filePath)
  if not chunk then return nil end
  local okx, mod = pcall(chunk)
  if okx and type(mod) == "table" then return mod end
  return nil
end

-- Crosswalk sets keyed by the game whose cache they came from ("*" for the
-- require-resolved set): Yellow's tables are not Red's, so one import must
-- never be handed the previous import's data (#420).
local crosswalks = {}   -- [key] = { pokemon=, moves=, items=, maps=, eventFlags= }
local charmapReady
local gen2CharmapKey

-- Which codec a save belongs to.  GameVersion is the single source of truth
-- for a version's generation; a caller that names no version at all falls
-- back to whatever version is currently selected, and Gen1 if even that is
-- unavailable (the headless CLI and the pure-Lua tests).
local function codecFor(gameVersion)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not ok or type(GameVersion) ~= "table" then return GenSave end
  local id = gameVersion or GameVersion.get()
  if GameVersion.generation(id) == 2 then return Gen2Save end
  return GenSave
end
SaveConvert.codecFor = codecFor

local function ensureData(gameVersion)
  local key = gameVersion or "*"
  if not crosswalks[key] then
    local data = {}
    for name, spec in pairs(DATA_MODULES) do
      if name ~= "charmap" then
        local mod = loadCacheTable(gameVersion, spec[2])
        if not mod then
          local e
          mod, e = loadTable(spec[1], spec[2])
          if not mod then return nil, e end
        end
        data[name] = mod
      end
    end
    crosswalks[key] = data
  end
  if codecFor(gameVersion) == Gen2Save then
    -- one game's charmap is not another's, and Gen2Save keeps a single
    -- module-level one, so re-arm it whenever the game changes
    if gen2CharmapKey ~= key then
      local cm = loadCacheTable(gameVersion, GEN2_CHARMAP[2])
      if not cm then
        local e
        cm, e = loadTable(GEN2_CHARMAP[1], GEN2_CHARMAP[2])
        if not cm then return nil, e end
      end
      Gen2Save.setCharmap(cm)
      gen2CharmapKey = key
    end
    if crosswalks[key].field == nil then
      crosswalks[key].field = loadCacheTable(gameVersion, GEN2_FIELD[2])
        or loadTable(GEN2_FIELD[1], GEN2_FIELD[2]) or false
    end
    return crosswalks[key]
  end
  if not charmapReady then
    local cm, err = loadTable(DATA_MODULES.charmap[1], DATA_MODULES.charmap[2])
    if not cm then return nil, err end
    GenSave.setCharmap(cm)
    charmapReady = true
  end
  return crosswalks[key]
end

-- Exposed for the CLI/tests so they can share the exact data set the codec
-- uses (and so a caller can pre-warm the cache).  gameVersion picks whose ROM
-- cache the generated tables come from.  Returns data, err.
function SaveConvert.loadData(gameVersion)
  return ensureData(gameVersion)
end

-- ------------------------------------------------------------------
-- new-game default skeleton the decoded fields merge on top of.  Carried
-- verbatim from tools/save_convert/convert.lua so the CLI and the runtime
-- produce a byte-identical save table for the same input.
-- ------------------------------------------------------------------

local function defaultsSave()
  return {
    meta = { format = "gen1_import", mods = {} },
    defeatedTrainers = {},
    repelSteps = 0,
    modData = {},
    options = {
      textSpeed = 3, animations = true, battleStyle = "shift",
      battleLayout = "og",
      ruleset = "gen1_faithful", musicVol = 7, sfxVol = 7, pikaVol = 7,
      musicFilter = 0,
      speed = 1, colors = "gbc", tilt = 0, gbcfx = 0,
      videoMode = "windowed", mods = {},
    },
  }
end

-- Where an import lands a player whose saved map could not be resolved (a
-- ROM cache built before the extractor started stamping Gen2 map group /
-- number onto every map).  Mirrors src/core/Data.lua's BOOT_DEFAULTS and its
-- Gen2 override, so the save is at least bootable until the ROM is
-- re-imported.
local FALLBACK_SPAWN = {
  [1] = { map = "REDS_HOUSE_2F", x = 3, y = 6 },
  [2] = { map = "PLAYERS_HOUSE2_F", x = 3, y = 3 },
}

-- Merge a GenSave.decode() result over the new-game defaults, exactly the
-- way convert.lua did, then stamp the requested version.  Keep the imported
-- SRAM image with the slot: Pokémon Red restores its saved current-map cache
-- before Continue, and an export needs that unmodeled data to remain bootable.
-- Decode warnings are only import diagnostics and do not belong in the slot.
local function mergeDefaults(decoded, version, generation)
  decoded.warnings = nil
  local save = defaultsSave()
  for k, v in pairs(decoded) do save[k] = v end
  if not save.player.map then
    local spawn = FALLBACK_SPAWN[generation or 1] or FALLBACK_SPAWN[1]
    save.player.map, save.player.x, save.player.y = spawn.map, spawn.x, spawn.y
  end
  save.lastHeal = { map = save.player.map, x = save.player.x, y = save.player.y }
  save.lastOutdoor = save.lastOutdoor or { id = save.player.map }
  if version ~= nil then
    save.meta = save.meta or {}
    save.meta.version = version
  end
  return save
end
SaveConvert.mergeDefaults = mergeDefaults

-- ------------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------------

-- importSav(bytes, version, gameVersion) -> saveTable, err
-- bytes: the raw 32768-byte SRAM string. Validates size and the main-data
-- checksum, decodes through the codec for that game's generation, and returns
-- a save table fully merged over the new-game defaults and tagged with
-- `version`. gameVersion ("red"/"blue"/"yellow"/"gold"/"silver") names the game
-- the save is being imported for, which selects both the crosswalk tables and
-- the codec; omit it to take the currently selected version. On any failure
-- returns nil + a message (never raises).
function SaveConvert.importSav(bytes, version, gameVersion)
  if type(bytes) ~= "string" then
    return nil, "expected raw save bytes as a string"
  end
  if #bytes ~= SaveConvert.SAVE_SIZE then
    return nil, ("save must be %d bytes, got %d"):format(SaveConvert.SAVE_SIZE, #bytes)
  end
  local data, derr = ensureData(gameVersion)
  if not data then return nil, derr end

  local codec = codecFor(gameVersion)
  local ok, decoded = pcall(codec.decode, bytes, data)
  if not ok then return nil, "decode failed: " .. tostring(decoded) end

  -- checksum validation: decode records a warning rather than throwing (so it
  -- can still read a foreign/corrupt save), but for the runtime import path a
  -- bad checksum means the file is not a trustworthy save, so reject it.  A
  -- Gen1 image fed to the Gen2 codec (or the reverse) fails here, which is
  -- exactly the "you picked the wrong game's save" answer the launcher wants.
  for _, w in ipairs(decoded.warnings or {}) do
    if tostring(w):find("checksum") then
      return nil, "save data checksum invalid (" .. tostring(w) .. ")"
    end
  end

  return mergeDefaults(decoded, version, codec == Gen2Save and 2 or 1)
end

-- exportSav(saveTable, gameVersion) -> bytes, err
-- Encodes a save table back to a raw 32768-byte SRAM image. Template-aware:
-- if the table still carries the stashed import template (saveTable.rawImport)
-- the codec reproduces every unmodeled region from it; otherwise those regions
-- are zero-filled. gameVersion selects the codec and crosswalk tables exactly
-- as in importSav. On failure returns nil + a message (never raises).
function SaveConvert.exportSav(saveTable, gameVersion)
  if type(saveTable) ~= "table" then
    return nil, "expected a save table"
  end
  local data, derr = ensureData(gameVersion)
  if not data then return nil, derr end
  local ok, bytes = pcall(codecFor(gameVersion).encode, saveTable, data, nil)
  if not ok then return nil, "encode failed: " .. tostring(bytes) end
  return bytes
end

return SaveConvert
