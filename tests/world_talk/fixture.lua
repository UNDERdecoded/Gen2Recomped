local M = {}
function M.new(root, backend, version, api, format, noMod, failing)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local gen = Version.generation()
  local Json, files = require("src.link.Json"), {}
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_world_talk/" .. name, "rb"))
    files["mods/portable_world_talk/" .. name] = file:read("*a")
    file:close()
  end
  local manifest = Json.decode(files["mods/portable_world_talk/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_world_talk/manifest.json"] = Json.encode(manifest)
  if failing then
    files["mods/portable_world_talk/main.lua"] = files["mods/portable_world_talk/main.lua"]
      .. '\nerror("intentional talk entry failure")'
  end
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_world_talk" }, {
    data = data,
    generation = gen,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local restores, calls, events, counter = {}, {}, {}, false
  local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function()
      owner[key] = old
    end
    owner[key] = value
  end
  local npc = {
    id = "GUIDE",
    localId = 1,
    cellX = 4,
    cellY = 5,
    targetX = 4,
    targetY = 5,
    moving = false,
    visible = true,
    facing = "down",
    def = { scriptKey = "TALK", index = 0 },
  }
  local player = {
    cellX = 4,
    cellY = 6,
    facing = "up",
    moving = false,
    facingCell = function()
      return 4, 5
    end,
  }
  local game = { data = data, save = { version = version, map = "FIX_ROUTE", options = {} } }
  local world, owner, interact
  if backend == "gen1" and gen == 3 then
    local Objects = require("src.core.game3.objects")
    local Field = require("src.core.game3.field")
    local Player = require("src.core.game3.player")
    local Collision = require("src.core.game3.collision")
    local CollisionStd = require("src.core.game3.scripting.collision_std")
    local Space = require("src.core.game3.scripting.space")
    game.session = game.save
    for key, value in pairs({
      cellX = 4,
      cellY = 6,
      targetX = 4,
      targetY = 6,
      facing = "up",
      moving = false,
      surfing = false,
    }) do
      patch(Player, key, value)
    end
    patch(Player, "boulderPush", nil)
    patch(Objects, "_byId", { [1] = npc })
    patch(Objects, "_order", { 1 })
    patch(Objects, "_mapId", "FIX_ROUTE")
    patch(Field, "running", true)
    patch(Field, "_game", game)
    patch(Field, "_session", game.save)
    patch(Field, "_locks", {})
    patch(Space, "active", true)
    patch(Space, "vm", {
      ctx = {},
      isRunning = function()
        return false
      end,
    })
    patch(Space, "startScript", function(key)
      assert(key == "TALK")
      calls[#calls + 1] = npc
      return true
    end)
    patch(require("src.core.game3.runtime"), "uiBusy", function()
      return false
    end)
    patch(Collision, "cell", function()
      return counter and 1 or 0
    end)
    patch(CollisionStd, "isCounter", function(cell)
      return cell == 1
    end)
    owner, world = game, { player = player, npcs = { npc } }
    interact = function()
      return Field.interact(game)
    end
  elseif backend == "gen1" and gen == 2 then
    local World = require("src.world.gen2.World")
    world = setmetatable({
      game = game,
      player = player,
      npcs = { npc },
      map = { id = "FIX_ROUTE" },
      vm = {
        running = function()
          return false
        end,
        start = function(_, key)
          assert(key == "TALK")
          calls[#calls + 1] = npc
          return true
        end,
      },
      facingObjectCell = function()
        return 4, counter and 4 or 5
      end,
    }, { __index = World })
    owner = world
    interact = function()
      return world:interactBody()
    end
  else
    local World = require("src.world.OverworldController")
    world = setmetatable({
      game = game,
      player = player,
      npcs = { npc },
      map = {
        id = "FIX_ROUTE",
        def = {},
        isCounterCell = function()
          return counter
        end,
      },
      talkTo = function(_, target)
        calls[#calls + 1] = target
      end,
    }, { __index = World })
    owner = world
    interact = function()
      return world:interact()
    end
  end
  local off = result.loader.events:on("world.interacted", function(event)
    events[#events + 1] = event
  end)
  local exports = result.loader.exports.portable_world_talk
  return {
    T = T,
    result = result,
    exports = exports,
    public = exports and exports.api,
    game = game,
    world = world,
    owner = owner,
    npc = npc,
    calls = calls,
    events = events,
    api = api,
    gen = gen,
    backend = backend,
    patch = patch,
    counter = function(value)
      counter = value
      npc.cellY, npc.targetY = value and 4 or 5, value and 4 or 5
    end,
    interact = interact,
    close = function()
      off()
      for i = #restores, 1, -1 do
        restores[i]()
      end
      result.release()
    end,
  }
end
return M
