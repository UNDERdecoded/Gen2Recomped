-- Loading the voxel mod's OWN shape resolver and asking it.
--
-- WHY, and it is the lesson tools/map-editor already paid for once.  An
-- editor that works out for itself how tall a tile is has written a SECOND
-- implementation of a rule, and a second implementation of a rule is a
-- second answer to it.  Where the two differ the editor shows a world the
-- game does not build -- and the differences are never subtle: trees come
-- out as walls and a height set in a panel moves a number and nothing else.
--
-- So this loads the mod's real lib/TileShape.lua and asks IT.  The answer is
-- then not "close to" what the game draws; it is what the game draws, by
-- construction, including every conditional pin, hop lip and cell rule that
-- has been written into that file since.
--
-- HOW A MOD'S MODULES LOAD.  They are not on package.path -- a mod folder
-- never is -- so they are read as source and called with the mod's namespace
-- `V` as their vararg, exactly the way the mod's own main.lua does it
-- (`local V = ...`).  `V.require` loads a sibling from lib/, `V.data` a file
-- from data/; both memoise.  Honouring that contract is what lets those
-- files load unchanged.
--
-- NOTHING HERE IS LOAD-BEARING.  The mod may be absent, half-installed, or
-- new enough to want a seam this editor has not got.  Any of those must
-- leave the editor open with the built-in vocabulary rather than a blank
-- window -- and the REASON IS KEPT, in `bridge.warnings`, because a caught
-- error thrown away is the single most expensive mistake a codebase makes.

local Fs = require("core.Fs")
local Paths = require("core.Paths")
local Classes = require("core.Classes")

local ModBridge = {}

-- Mod files reach for engine modules by name (`src.render.Assets`,
-- `src.world.Map`).  The engine is not here.  TileShape wraps every one of
-- those in pcall and degrades, but a sibling it loads might not -- so a
-- searcher answers with an inert stub instead of letting the require raise.
-- The stub is EMPTY on purpose: a caller that pcalls a missing function gets
-- its nil-index error and degrades, which is the behaviour it was written
-- for.  A stub that guessed at implementations would be a third answer.
local stubbed = {}
local function installEngineStubs()
  if ModBridge._stubsInstalled then return end
  ModBridge._stubsInstalled = true
  local searchers = package.searchers or package.loaders
  if not searchers then return end
  searchers[#searchers + 1] = function(name)
    if type(name) ~= "string" or name:sub(1, 4) ~= "src." then return nil end
    return function()
      stubbed[name] = true
      return setmetatable({}, {
        __index = function() return nil end,
        __call = function() return nil end,
        __tostring = function() return "stub:" .. name end,
      })
    end
  end
end

function ModBridge.stubbedModules()
  local out = {}
  for k in pairs(stubbed) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- Build the namespace one mod install answers to.  `roots` is the overlay,
-- most authoritative first (see core/Paths.lua): every file is resolved
-- across it individually, because that is what PhysFS does and an install
-- really can be half save-directory and half game folder.
local function namespaceFor(roots, id, warn)
  local V = { id = id, path = roots[1], roots = roots }
  local modules, datas = {}, {}
  local origin = {}

  local function chunkFor(rel)
    local path, idx, root = Paths.overlayFile(roots, rel)
    if not path then
      error(id .. ": " .. rel .. " is missing from every install root", 0)
    end
    origin[rel] = { path = path, root = root, index = idx }
    local src, rerr = Fs.read(path)
    if not src then error(id .. ": " .. rel .. ": " .. tostring(rerr), 0) end
    local loader = (_VERSION == "Lua 5.1") and loadstring or load
    local chunk, cerr = loader(src, "@" .. rel)
    if not chunk then
      error(id .. ": " .. rel .. " did not compile: " .. tostring(cerr), 0)
    end
    return chunk
  end

  V.origin = origin

  function V.require(name)
    local hit = modules[name]
    if hit ~= nil then
      if hit == false then return nil end
      return hit
    end
    local ok, value = pcall(function() return chunkFor("lib/" .. name .. ".lua")(V) end)
    if not ok then
      -- A sibling that will not load is reported and then absent.  Gen3 is
      -- the one TileShape requires unguarded at file scope, and a stub is a
      -- complete substitute for it on every Gen 1 and Gen 2 tileset: every
      -- other Gen3 call in that file sits behind `Gen3.isGen3(tileset)`.
      warn(("lib/%s.lua did not load (%s)"):format(name, tostring(value)))
      if name == "Gen3" then
        value = { isGen3 = function() return false end }
        modules[name] = value
        return value
      end
      modules[name] = false
      return nil
    end
    modules[name] = value == nil and false or value
    return value
  end

  function V.data(name)
    local hit = datas[name]
    if hit ~= nil then
      if hit == false then return nil end
      return hit
    end
    local ok, value = pcall(function() return chunkFor("data/" .. name .. ".lua")(V) end)
    if not ok then
      warn(("data/%s.lua did not load (%s)"):format(name, tostring(value)))
      datas[name] = false
      return nil
    end
    datas[name] = value == nil and false or value
    return value
  end

  -- REPLACE A DATA FILE IN PLACE.  This is how the editor's authoring
  -- reaches the resolver: it merges its pins into the profile and hands the
  -- merged table back through the same seam the mod reads its own file
  -- through, then calls TileShape.invalidate().  The resolver then applies
  -- the editor's pins with ITS OWN rules -- conditional order, cell
  -- fallbacks, per-tileset heights, the lot -- instead of the editor
  -- applying them with a second set that would drift.
  function V.setData(name, value)
    datas[name] = value == nil and false or value
  end

  V.mod = {
    id = id,
    path = roots[1],
    read = function(_, rel)
      local path = Paths.overlayFile(roots, rel)
      return path and Fs.read(path) or nil
    end,
  }
  V.log = {
    info = function() end,
    warn = function(_, fmt, ...) warn((fmt or ""):format(...)) end,
    error = function(_, fmt, ...) warn((fmt or ""):format(...)) end,
  }
  return V
end

-- Open the mod.  Returns a bridge table -- never nil, never raises.  When
-- the mod could not be loaded the bridge still answers every question, from
-- core/Classes.lua's mirror, and `bridge.live` is false.
function ModBridge.open(roots, id)
  installEngineStubs()
  local bridge = {
    id = id or "DRAMATIC_SHAPE",
    roots = roots or {},
    warnings = {},
    live = false,
  }
  local function warn(msg)
    bridge.warnings[#bridge.warnings + 1] = tostring(msg)
  end

  if #bridge.roots == 0 then
    warn("no install found; using the built-in class table")
    bridge.classInfo = Classes.FALLBACK
    return bridge
  end

  local V = namespaceFor(bridge.roots, bridge.id, warn)
  bridge.V = V

  local ok, TS = pcall(V.require, "TileShape")
  if not (ok and type(TS) == "table" and type(TS.forMap) == "function"
          and type(TS.at) == "function") then
    warn(ok and "lib/TileShape.lua is not a shape resolver"
            or tostring(TS))
    bridge.classInfo = Classes.FALLBACK
    return bridge
  end

  bridge.TileShape = TS
  bridge.live = true
  bridge.classInfo = (type(TS.CLASS_INFO) == "table"
                      and next(TS.CLASS_INFO) ~= nil)
                     and TS.CLASS_INFO or Classes.FALLBACK

  local okH, heights = pcall(TS.heights)
  bridge.heights = (okH and type(heights) == "table") and heights or nil

  -- The profile itself, for the keys TileShape does not expose through a
  -- function: `buildings`, `prop_ground`, the per-tileset side tables the
  -- exporter has to round-trip rather than drop.
  bridge.profile = V.data("voxel_heights")
  if type(bridge.profile) ~= "table" then
    warn("data/voxel_heights.lua did not load; starting from an empty profile")
    bridge.profile = nil
  end

  -- Structures is optional here and always has been: every pin, conditional
  -- and class height comes from TileShape alone.  It is loaded only so the
  -- editor can say whether the install is complete.
  bridge.hasStructures = Paths.overlayFile(bridge.roots, "lib/Structures.lua") ~= nil
  bridge.hasMesher = Paths.overlayFile(bridge.roots, "lib/ChunkMesher.lua") ~= nil

  local mpath = Paths.overlayFile(bridge.roots, "manifest.json")
  if mpath then
    local raw = Fs.read(mpath)
    bridge.version = raw and raw:match('"version"%s*:%s*"([^"]+)"') or nil
    bridge.modName = raw and raw:match('"name"%s*:%s*"([^"]+)"') or nil
  end

  return bridge
end

-- Which install root a given file actually came from, for the UI.  Answering
-- "which copy of TileShape is this?" out loud is the whole reason the
-- overlay is modelled instead of assumed.
function ModBridge.overlayReport(bridge)
  local rows = {}
  for _, rel in ipairs({ "lib/TileShape.lua", "lib/ChunkMesher.lua",
                         "lib/Structures.lua", "lib/Gen3.lua",
                         "data/voxel_heights.lua", "manifest.json" }) do
    local path, idx, root = Paths.overlayFile(bridge.roots or {}, rel)
    rows[#rows + 1] = {
      rel = rel,
      found = path ~= nil,
      root = root,
      index = idx,
      shadowed = (idx or 1) > 1,
    }
  end
  return rows
end

function ModBridge.invalidate(bridge)
  if bridge and bridge.TileShape and bridge.TileShape.invalidate then
    pcall(bridge.TileShape.invalidate)
  end
end

return ModBridge
