local M = {}
function M.new(root, backend, version, api, format, failing)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  assert(Version.VERSIONS[version], "unsupported fixture version")
  Version.set(version)
  local gen = Version.generation()
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  local pixel = gen >= 3 and 16 or 32
  local defs = {}
  for _, id in ipairs({ "ROOT", "EAST", "NORTH" }) do
    defs[id] = {
      id = id,
      width = 2,
      height = 2,
      blockPx = pixel,
      tileset = "FIX_OUT",
      blocks = { 0, 0, 0, 0 },
      borderBlock = 0,
      objects = {},
      connections = {},
    }
  end
  defs.ROOT.connections.east = { map = "EAST", offset = -1 }
  defs.EAST.connections.north = { map = "NORTH", offset = -3 }
  defs.NORTH.connections.south = { map = "ROOT", offset = 0 }
  data.maps = defs
  data.tilesets = data.tilesets or {}
  data.tilesets.FIX_OUT =
    { blockCells = pixel / 16, blockTiles = pixel / 8, blocks = {}, walkable = {}, id = "FIX_OUT" }
  local files, Json = {}, require("src.link.Json")
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/portable_live_maps/" .. name, "rb"))
    files["mods/portable_live_maps/" .. name] = f:read("*a")
    f:close()
  end
  local manifest = Json.decode(files["mods/portable_live_maps/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_live_maps/manifest.json"] = Json.encode(manifest)
  if failing then
    files["mods/portable_live_maps/main.lua"] = files["mods/portable_live_maps/main.lua"]
      .. '\nerror("intentional entry failure")'
  end
  local result = T.sdk.loadMods({ "mods/portable_live_maps" }, {
    fs = T.sdk.memfs(files),
    generation = gen,
    data = data,
    dev = false,
  })
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local restores = {}
  local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function()
      owner[key] = old
    end
    owner[key] = value
  end
  local function bind(fn, name, value)
    for i = 1, 40 do
      local key, old = debug.getupvalue(fn, i)
      if not key then
        break
      end
      if key == name then
        debug.setupvalue(fn, i, value)
        restores[#restores + 1] = function()
          debug.setupvalue(fn, i, old)
        end
        return
      end
    end
    error("missing native binding: " .. name)
  end
  local game = {
    data = data,
    save = { version = version, options = {}, flags = {}, party = {} },
    renderer = {
      worldViewSize = function()
        return 160, 144
      end,
    },
  }
  local maps = {}
  local Map = require("src.world.Map")
  for id, def in pairs(defs) do
    maps[id] = Map.new(def, data.tilesets.FIX_OUT)
  end
  local world, rebuild, source, loaderCalls = nil, nil, nil, 0
  if backend == "gen1" and gen == 3 then
    local Field, Runtime, Map3 =
      require("src.core.game3.field"), require("src.core.game3.runtime"), require("src.core.game3.map")
    game.phase, game.session = "field", { map = "ROOT" }
    patch(Field, "running", true)
    patch(Runtime, "getSession", function()
      return game.session
    end)
    patch(Map3, "current", "ROOT")
    source = {
      { id = "ROOT", ox = 0, oy = 0 },
      { id = "EAST", ox = 2 * pixel, oy = -pixel },
      { id = "NORTH", ox = -pixel, oy = -3 * pixel },
    }
    patch(Map3, "world", source)
    world = { map = maps.ROOT, neighbors = {} }
    rebuild = function() end -- Gen1 GBA has no producer for these events.
  elseif backend == "gen1" and gen == 2 then
    local World = require("src.world.gen2.World")
    world = setmetatable({
      game = game,
      map = maps.ROOT,
      maps = defs,
      tilesets = data.tilesets,
      npcs = {},
      entities = {},
      npcPool = {},
      neighbors = {},
      ghosts = { "old" },
      pixelZoomScale = function()
        return 1
      end,
      imageFor = function()
        return {}
      end,
    }, { __index = World })
    rebuild = function()
      world:rebuildNeighbors()
      world:rebuildPeople()
    end
  else
    local World, Loader = require("src.world.OverworldController"), require("src.world.MapLoader")
    world = setmetatable({
      game = game,
      map = maps.ROOT,
      npcs = {},
      entities = {},
      npcPool = {},
      neighbors = {},
      ghosts = { "old" },
    }, { __index = World })
    bind(World.rebuildNeighbors, "Game", game)
    patch(Loader, "load", function(_, id)
      loaderCalls = loaderCalls + 1
      return assert(maps[id])
    end)
    patch(Loader, "trim", function() end)
    rebuild = function()
      world:rebuildNeighbors()
    end
  end
  game.world, game.overworld = world, world
  result.loader.game = game
  local phase = {}
  for _, name in ipairs({ "world.live_maps_preparing", "world.live_maps_updated" }) do
    local label = name
    result.loader.events:on(name, function()
      phase[#phase + 1] =
        { name = label, preparing = world.preparingLiveMaps == true, ghosts = #world.ghosts }
    end, 100)
  end
  return {
    T = T,
    game = game,
    world = world,
    result = result,
    e = result.loader.exports.portable_live_maps,
    api = api,
    gen = gen,
    backend = backend,
    pixel = pixel,
    phase = phase,
    rebuild = rebuild,
    commonEvents = gen <= 2,
    source = source,
    patch = patch,
    loaderCalls = function()
      return loaderCalls
    end,
    close = function()
      for i = #restores, 1, -1 do
        restores[i]()
      end
      result.release()
    end,
  }
end
return M
