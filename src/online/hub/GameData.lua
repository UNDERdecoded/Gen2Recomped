-- Game data for the hub's validation, from the operator's own imported
-- caches (<install>/data/generated).  The hub ships no game data, and with
-- none it refuses to run a GTS (docs/online-design.md 2.9).
--
--   GameData.load(dir, game, mode) -> data | nil, why
--     mode "lean" (GTS): the full load, then everything validation does not
--       read (maps, text, art) is dropped, so a pool costs a few MB.
--     mode "full" (a world): the game's own Data:load, in a FRESH Data table,
--       so several games can sit in one process.
--   GameData.guessGame(dir) -> "platinum" | nil   (from ".../platinum/data/...")
--
-- Validation of one mon reads GameVersion (Pokemon.lua asks it whether this
-- is a Gen 4/5 game, for instance), so whoever validates against a dataset
-- sets GameVersion to that dataset's game first (GameData.use).

local GameData = {}

-- what a lean dataset keeps after the load
GameData.LEAN_KEEP = { "constants", "pokemon", "moves", "items", "type_chart", "statuses",
                       "move_effects", "link_fields", "abilities", "natures", "growth_rates",
                       "_bootKeys" }

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

function GameData.guessGame(dir)
  local GameVersion = require("src.core.GameVersion")
  local clean = tostring(dir or ""):gsub("\\", "/")
  local best
  for part in clean:gmatch("[^/]+") do
    if GameVersion.VERSIONS[part:lower()] then best = part:lower() end
  end
  return best
end

-- set the engine's "current game" to `game` (validation reads it)
function GameData.use(game)
  if game then require("src.core.GameVersion").set(game) end
end

-- a fresh copy of src/core/Data.lua, loaded with POKEPORT_DATA_DIR = dir
local function full(dir, game)
  local path = package.searchpath and package.searchpath("src.core.Data", package.path)
  local chunk, err
  if path then
    chunk, err = loadfile(path)
  elseif love and love.filesystem and love.filesystem.load then
    -- inside the game (the launcher's hub thread): src/ may be inside the
    -- .love archive, where plain loadfile can't see it
    local okL, c, e = pcall(love.filesystem.load, "src/core/Data.lua")
    if okL then chunk, err = c, e else err = c end
  else
    return nil, "can't find src/core/Data.lua (is the game's source tree here?)"
  end
  if not chunk then return nil, err end
  local okM, Data = pcall(chunk)
  if not okM then return nil, Data end
  local realGetenv = os.getenv
  os.getenv = function(k)
    if k == "POKEPORT_DATA_DIR" then return dir end
    return realGetenv(k)
  end
  local ok, why = pcall(Data.load, Data)
  os.getenv = realGetenv
  if not ok then return nil, why end
  return Data
end

function GameData.load(dir, game, mode)
  if type(dir) ~= "string" or dir == "" then return nil, "no data directory" end
  dir = dir:gsub("\\", "/"):gsub("/+$", "")
  if not exists(dir .. "/pokemon.lua") then
    return nil, ("%s has no pokemon.lua (point it at <install>/data/generated)"):format(dir)
  end
  game = game or GameData.guessGame(dir)
  if not game then return nil, "can't tell which game " .. dir .. " is; name it" end
  GameData.use(game)
  local data, why = full(dir, game)
  if not data then return nil, why end
  if mode ~= "full" then
    -- keep what validation reads; maps, text and art go (the load's own
    -- post-processing -- Gen 4 species fields, nature names -- has run)
    local keep = {}
    for _, k in ipairs(GameData.LEAN_KEEP) do keep[k] = true end
    for k in pairs(data) do
      if not keep[k] and type(data[k]) == "table" then data[k] = nil end
    end
    data.hubLean = true
    collectgarbage()
  end
  data.hubGame, data.hubDir = game, dir
  return data
end

return GameData
