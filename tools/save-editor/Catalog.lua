-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

local Catalog = {}

-- io.popen is NOT a "returns nil when unsupported" API.  LuaJIT and PUC Lua
-- both DEFINE the function on every target and RAISE "'popen' not supported"
-- from inside it when the platform has no fork/exec -- which is the Switch
-- (love-nx / Horizon) and the UWP build.  So an `io.popen and io.popen(...)`
-- guard guards nothing: the call still throws.  Here it threw out of
-- Catalog.scrapeEvents -> App.load -> the launcher's Edit button, so the save
-- editor died on open on the one platform that cannot shell out.
--
-- src/core/HostShell.popen already wraps this in a pcall for exactly this
-- reason (see its comment); the editor was simply not using it.  Loaded
-- defensively because the editor's test harnesses run these modules under
-- plain Lua with no src.* on the require path.
local safePopen
do
  local ok, HostShell = pcall(require, "src.core.HostShell")
  if ok and type(HostShell) == "table" and HostShell.popen then
    safePopen = HostShell.popen
  else
    safePopen = function(command, mode)
      local okp, pipe = pcall(io.popen, command, mode or "r")
      if not okp or not pipe then return nil end
      return pipe
    end
  end
end

-- Whether shelling out is meaningful at all.  A console has no shell, so skip
-- the attempt instead of paying a pcall for a guaranteed failure.  Only a
-- positive love answer is trusted: headless test runs have no love.system, and
-- Platform then reports the OS as "Unknown" -> false, which would silently
-- disable the shell listing those runs depend on.
local function canShell()
  if not (love and love.system) then return true end
  local okp, Platform = pcall(require, "src.core.Platform")
  if okp and type(Platform) == "table" and Platform.canSpawnProcess then
    return Platform.canSpawnProcess()
  end
  return true
end

-- Extracted Gen4 IDs are numeric; merged compatibility/mod entries may use
-- names. Keep native numeric order without comparing unlike Lua types.
function Catalog.keyLess(a,b)
  local ta,tb=type(a),type(b)
  if ta=='number' and tb=='number' then return a<b end
  if ta=='number' then return true end
  if tb=='number' then return false end
  return tostring(a)<tostring(b)
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys,Catalog.keyLess)
  return keys
end

function Catalog.build(data)
  local species=sortedKeys(data.pokemon)
  local moves=sortedKeys(data.moves)
  if data.isGen4Cache or (data.constants or {}).gen==4 then
    local selectable={}
    for _,key in ipairs(species) do
      local id=tonumber(key) or tonumber(tostring(key):match('^SPECIES_(%d+)$'))
      -- Personal rows 0 and 494..507 are sentinels, eggs and alternate
      -- stat records. Forms belong to their base species, not this picker.
      if id~=0 and not (id and id>=494 and id<=507) then
        selectable[#selectable+1]=key
      end
    end
    species=selectable
    local selectableMoves={}
    for _,key in ipairs(moves) do
      local id=tonumber(key) or tonumber(tostring(key):match('^MOVE_(%d+)$'))
      -- Native MAX_MOVES is 468. The archive has three additional unnamed
      -- internal records; named mod moves beyond the native range remain valid.
      local entry=data.moves[key]
      local internal=id and id>=468 and id<=470 and not (type(entry.name)=='string' and entry.name~='')
      if id~=0 and not internal then selectableMoves[#selectableMoves+1]=key end
    end
    moves=selectableMoves
  end
  return {
    species = species,
    items = sortedKeys(data.items),
    moves = moves,
  }
end

-- Directory listing / file reading go through love.filesystem when it is
-- available, and only fall back to shelling out.  That is what makes the
-- Events tab work in a packaged build: data/scripts is inside the .love
-- archive, data/generated is mounted from the save directory, and mods live
-- under the save directory too -- none of which io.open can reach by relative
-- path.  The io.popen path stays for headless runs (tests/, plain lua) where
-- love.filesystem does not exist.
-- nil means "love.filesystem cannot see this directory", which is the signal
-- to fall through to the shell -- headless runs mount a stub filesystem that
-- knows nothing about the checkout, but their io.* can still read it.
local function loveListLua(dir)
  local fs = love and love.filesystem
  if not (fs and fs.getDirectoryItems and fs.getInfo) then return nil end
  if not fs.getInfo(dir) then return nil end
  local out = {}
  for _, name in ipairs(fs.getDirectoryItems(dir)) do
    if name:sub(-4) == ".lua" then out[#out + 1] = dir .. "/" .. name end
  end
  return out
end

local function shellListLua(dir)
  local out = {}
  if not canShell() then return out end
  if package.config:sub(1, 1) == "\\" then
    -- cmd has no ls; dir /b prints bare names, so re-attach the directory
    local p = safePopen(string.format('dir /b "%s\\*.lua" 2>nul', dir))
    if p then
      -- p:lines() itself can raise on a pipe the platform half-supports, so
      -- the drain is protected too: an unreadable listing is "no files here",
      -- never a crash out of the editor's load path.
      pcall(function()
        for line in p:lines() do
          if line ~= "" then table.insert(out, dir .. "/" .. line) end
        end
      end)
      pcall(function() p:close() end)
    end
    return out
  end
  local p = safePopen(string.format('ls "%s"/*.lua 2>/dev/null', dir))
  if p then
    pcall(function()
      for line in p:lines() do
        table.insert(out, line)
      end
    end)
    pcall(function() p:close() end)
  end
  return out
end

local function readText(path)
  local fs = love and love.filesystem
  if fs and fs.read and fs.getInfo and fs.getInfo(path) then
    local body = fs.read(path)
    if body then return body end
  end
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

-- extraDirs: loaded mods' roots, so MOD_-prefixed flags defined in mod
-- scripts show up beside the vanilla EVENT_ ones
function Catalog.scrapeEvents(scriptDir, headerPath, listFiles, extraDirs)
  listFiles = listFiles or function(dir)
    return loveListLua(dir) or shellListLua(dir)
  end

  local found = {}
  local function eat(text)
    for name in text:gmatch("EVENT_[A-Z0-9_]+") do
      found[name] = true
    end
    for name in text:gmatch("MOD_[A-Z0-9_]+") do
      found[name] = true
    end
  end

  local dirs = { scriptDir }
  for _, dir in ipairs(extraDirs or {}) do
    dirs[#dirs + 1] = dir
  end
  for _, dir in ipairs(dirs) do
    for _, path in ipairs(listFiles(dir)) do
      local body = readText(path)
      if body then eat(body) end
    end
  end

  if headerPath then
    local body = readText(headerPath)
    if body then eat(body) end
  end

  -- Gen2 stores story bits as EVENT_G2_%04d (see Gen2Flags.eventFlag).  The
  -- hand-ported data/scripts tree only has Gen1 EVENT_* strings, so without
  -- this pass the Events tab is empty / shows raw EVENT_G2_ ids with no
  -- pret names.  Include both the storage id and the pret constant so the
  -- filter can match either spelling.
  local ok, Gen2Flags = pcall(require, "src.script.Gen2Flags")
  if ok and Gen2Flags and Gen2Flags.EVENT_FLAG_NAMES then
    for index, name in pairs(Gen2Flags.EVENT_FLAG_NAMES) do
      found[name] = true
      found[string.format("EVENT_G2_%04d", index)] = true
    end
  end
  if ok and Gen2Flags and Gen2Flags.ENGINE_FLAG_NAMES then
    for _, name in pairs(Gen2Flags.ENGINE_FLAG_NAMES) do
      found[name] = true
    end
  end

  return sortedKeys(found)
end

-- Friendly item label for the save editor.  Gen2 keeps inventory keys as
-- ITEM_nnn (RomExtractorGen2); after a real ROM extract, data.items[id].name
-- is the ROM ItemNames string and .key is POTION / TM_01 / etc.
function Catalog.itemLabel(data, id)
  local entry = data and data.items and data.items[id]
  if type(entry) == "table" then
    local name = entry.name
    if type(name) == "string" and name ~= "" and not name:match("^Item %d+$") then
      return name
    end
    if type(entry.key) == "string" and entry.key ~= "" then
      return entry.key
    end
  end
  return tostring(id or "?")
end

-- Friendly event flag label.  Storage stays EVENT_G2_%04d / FLAG_G3_%04X;
-- every name here is display-only so existing saves and extracted scripts
-- keep matching on the key.
--
-- `data` is optional and only Hoenn needs it: a Gen 3 flag has no name
-- anywhere -- pokeemerald's FLAG_* constants were compiled away -- so
-- Gen3Names derives a label from what the flag is USED for in the extracted
-- data (a badge, a trainer, an object it hides, a hidden item, the maps whose
-- scripts touch it).  Callers that do not have `data` in hand get the Gen 2
-- behaviour unchanged.
function Catalog.flagLabel(id, data)
  local ok, Gen2Flags = pcall(require, "src.script.Gen2Flags")
  if ok and Gen2Flags and Gen2Flags.eventFlagDisplay then
    local pretty = Gen2Flags.eventFlagDisplay(id)
    if pretty and pretty ~= id then
      return pretty
    end
  end
  if data and type(id) == "string" and id:match("^FLAG_G3_") then
    local okG, Gen3Names = pcall(require, "Gen3Names")
    local label = okG and Gen3Names.flag(data, id) or nil
    if label then return label end
  end
  return tostring(id or "?")
end

-- WHAT A MAP IS CALLED IN THE GAME, for every list that shows a map id.
--
-- Reported from play: "ensure the save manager lists emerald maps by in game
-- map name".  MAP_G01_N03 is this port's storage key (the cartridge's map
-- group and number); the name on the sign is the header's region map section,
-- which Gen3Names reads.  Gen 1 and Gen 2 map ids are already words
-- (PALLET_TOWN), so they are their own label and fall straight through.
function Catalog.mapLabel(data, id)
  local def=data and data.maps and data.maps[id]
  if def and type(def.label)=='string' and def.label~='' then return def.label end
  if def and type(def.name)=='string' and def.name~='' then return def.name end
  if type(id) ~= "string" then return tostring(id) end
  if id:match("^MAP_G%d+_N%d+$") then
    local ok, Gen3Names = pcall(require, "Gen3Names")
    local label = ok and Gen3Names.map(data, id) or nil
    if label then return label end
  end
  return tostring(id or "?")
end

-- Every Hoenn flag this dataset can put a name to, sorted.
--
-- scrapeEvents finds Gen 1 and Gen 2 flags by reading the ported script tree
-- for EVENT_ strings; Hoenn has no script tree to read -- its scripts are
-- extracted IR -- so without this the Events tab could only list the flags a
-- save had already WRITTEN, and a flag you want to set is by definition one
-- the save has not got.  Gen3Names has already worked out which flags exist
-- and what each is for, so the catalog is its keys.
function Catalog.gen3Flags(data)
  local ok, Gen3Names = pcall(require, "Gen3Names")
  if not ok then return {} end
  return sortedKeys(Gen3Names.index(data).flags)
end

-- The map half of a save key shaped "<MAP>_obj_<n>" (defeatedTrainers,
-- itemsTaken), named the same way.  Keys that are not that shape come back
-- unchanged.
function Catalog.mapKeyLabel(data, key)
  if type(key) ~= "string" then return tostring(key) end
  local mapId, rest = key:match("^(MAP_G%d+_N%d+)(.*)$")
  if not mapId then return key end
  local label = Catalog.mapLabel(data, mapId)
  if label == mapId then return key end
  -- "_obj_3" welded to the end of a name reads as part of the name, so the
  -- remainder is spaced out and the join is visible
  return label .. " / " .. (rest:gsub("^_", ""):gsub("_", " "))
end

-- Friendly species label.  Gen2 keys are SPECIES_nnn; after a ROM extract
-- data.pokemon[id].name is the PokemonNames string (BULBASAUR, …).
function Catalog.speciesLabel(data, id)
  local entry = data and data.pokemon and data.pokemon[id]
  if type(entry) == "table" then
    local name = entry.name
    if type(name) == "string" and name ~= ""
      and not name:match("^[Ss]pecies%s*%d+$")
      and name ~= id then
      return name
    end
  end
  return tostring(id or "?")
end

function Catalog.moveLabel(data, id)
  if id==nil then return '-- --' end
  local entry=data and data.moves and data.moves[id]
  if type(entry)=='table' and type(entry.name)=='string' and entry.name~='' then return entry.name end
  return tostring(id)
end

return Catalog
