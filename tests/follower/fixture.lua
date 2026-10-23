local M = {}
function M.new(root, backend, version, api, format, failing)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local gen = Version.generation()
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  data.tilesets = data.tilesets or {}
  data.tilesets.FIX_OUT = data.tilesets.FIX_OUT or T.fixtures.fresh().tilesets.FIX_OUT
  data.sprites = data.sprites or {}
  local sheet = T.fixtures.fresh().sprites.SPRITE_FIX_NPC
  data.sprites.SPRITE_PIKACHU = sheet
  data.gen2Sprites = data.gen2Sprites or {}
  data.gen2Sprites.SPRITE_PIKACHU = sheet
  local Json, files = require("src.link.Json"), {}
  for _, name in ipairs({ "manifest.json", "main.lua" }) do
    local file = assert(io.open(root .. "/examples/portable_follower/" .. name, "rb"))
    files["mods/portable_follower/" .. name] = file:read("*a")
    file:close()
  end
  local manifest = Json.decode(files["mods/portable_follower/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_follower/manifest.json"] = Json.encode(manifest)
  if failing then
    files["mods/portable_follower/main.lua"] = files["mods/portable_follower/main.lua"]
      .. '\nerror("entry rollback probe")'
  end
  local result = T.sdk.loadMods(
    { "mods/portable_follower" },
    { fs = T.sdk.memfs(files), data = data, dev = false }
  )
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local game = {
    data = data,
    save = {
      version = version,
      options = {},
      flags = { EVENT_GOT_STARTER = true, EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true },
      player = { id = 7, name = "PROBE" },
      party = { { species = "PIKACHU", hp = 10, otId = 7, ot = "PROBE" } },
    },
  }
  local def = {
    id = "FIX_TOWN",
    width = 12,
    height = 12,
    tileset = "FIX_OUT",
    blocks = {},
    objects = {},
    connections = {},
  }
  for i = 1, 144 do
    def.blocks[i] = 1
  end
  data.tilesets.FIX_OUT.walkable = { 0, 1, 2 }
  data.tilesets.FIX_OUT._walkableSet = nil
  if backend == "gen1" and gen == 2 then
    data.tilesets.FIX_OUT.collision = { {}, { 0, 0, 0, 0 } }
  end
  -- Gen1 GBA's real follower reads the Field session map ID, not a GB Map.
  local map = backend == "gen1" and gen == 3 and { id = def.id }
    or require("src.world.Map").new(def, data.tilesets.FIX_OUT)
  local player = {
    cellX = 4,
    cellY = 4,
    px = 64,
    py = 64,
    facing = "down",
    stepFrames = 4,
    stepFramesCur = 4,
    moving = false,
    spriteDef = sheet,
    elevation = 3,
  }
  local world = { map = map, player = player, npcs = {}, entities = { player }, sprites = data.gen2Sprites }
  local restores = {}
  local function patch(owner, name, value)
    local old = owner[name]
    restores[#restores + 1] = function()
      owner[name] = old
    end
    owner[name] = value
  end
  local controller
  if backend == "gen1" and gen == 3 then
    controller = require("src.world.game3.Follower")
    local Field = require("src.core.game3.field")
    player = require("src.core.game3.player")
    for name, value in pairs(world.player) do
      patch(player, name, value)
    end
    for _, name in ipairs({ "targetX", "targetY", "surfing" }) do
      patch(player, name, nil)
    end
    world.player = player
    patch(Field, "running", true)
    patch(Field, "getSession", function()
      return { map = world.map.id }
    end)
    controller.reset()
  elseif backend == "gen1" and gen == 2 then
    controller = require("src.world.gen2.Follower")
  else
    controller = require("src.world.PikachuFollower")
  end
  game.world, game.overworld, result.loader.game = world, world, game
  local function current()
    return controller.current(world)
  end
  local function tick()
    local npc = current()
    if npc and npc.moving and not (backend == "gen1" and gen == 3) then
      npc:update(world.map, world.entities)
    end
    controller.update(game, world)
  end
  return {
    T = T,
    e = result.loader.exports.portable_follower,
    result = result,
    game = game,
    world = world,
    player = player,
    controller = controller,
    current = current,
    tick = tick,
    gen = gen,
    version = version,
    backend = backend,
    api = api,
    patch = patch,
    enter = function(opts)
      if backend == "gen1" and gen == 3 then
        controller.onMapEntered()
        tick()
      else
        controller.onMapEntered(game, world, opts, gen == 2)
      end
    end,
    close = function()
      if backend == "gen1" and gen == 3 then
        controller.reset()
      end
      for i = #restores, 1, -1 do
        restores[i]()
      end
      result.release()
    end,
  }
end
return M
