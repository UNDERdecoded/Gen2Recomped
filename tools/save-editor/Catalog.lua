local Catalog = {}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

function Catalog.build(data)
  return {
    species = sortedKeys(data.pokemon),
    items = sortedKeys(data.items),
    moves = sortedKeys(data.moves),
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
  if package.config:sub(1, 1) == "\\" then
    -- cmd has no ls; dir /b prints bare names, so re-attach the directory
    local p = io.popen(string.format('dir /b "%s\\*.lua" 2>nul', dir))
    if p then
      for line in p:lines() do
        if line ~= "" then table.insert(out, dir .. "/" .. line) end
      end
      p:close()
    end
    return out
  end
  local p = io.popen(string.format('ls "%s"/*.lua 2>/dev/null', dir))
  if p then
    for line in p:lines() do
      table.insert(out, line)
    end
    p:close()
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
  if type(id) ~= "string" then return tostring(id) end
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
  return id
end

-- Friendly event flag label.  Storage stays EVENT_G2_%04d; pret names are
-- display-only so existing saves / extracted scripts keep matching.
function Catalog.flagLabel(id)
  local ok, Gen2Flags = pcall(require, "src.script.Gen2Flags")
  if ok and Gen2Flags and Gen2Flags.eventFlagDisplay then
    local pretty = Gen2Flags.eventFlagDisplay(id)
    if pretty and pretty ~= id then
      return pretty
    end
  end
  return id
end

-- Friendly species label.  Gen2 keys are SPECIES_nnn; after a ROM extract
-- data.pokemon[id].name is the PokemonNames string (BULBASAUR, …).
function Catalog.speciesLabel(data, id)
  if type(id) ~= "string" then return tostring(id or "?") end
  local entry = data and data.pokemon and data.pokemon[id]
  if type(entry) == "table" then
    local name = entry.name
    if type(name) == "string" and name ~= ""
      and not name:match("^[Ss]pecies%s*%d+$")
      and name ~= id then
      return name
    end
  end
  return id
end

return Catalog
