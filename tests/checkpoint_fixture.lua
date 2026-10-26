-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Owned ROM-free content over actual native services; no player profile.
local F = {}
function F.boot(edition, api)
  local SDK = require("tests.modkit.sdk")
  local Json = require("src.link.Json")
  local GV = require("src.core.GameVersion")
  GV.set(edition)
  local id = "checkpoint_fixture"
  local fs = SDK.memfs({
    ["mods/" .. id .. "/manifest.json"] = Json.encode({ id = id, name = id, version = "1.0.0", api = api or 3, entry = "main.lua" }),
    ["mods/" .. id .. "/main.lua"] = "return function(mod) mod.exports.checkpoints=mod.checkpoints;mod.exports.api=mod end",
  })
  local loaded = SDK.loadMods({ "mods/" .. id }, { fs = fs })
  assert(#loaded.errors == 0)
  local Game = require("src.core.Game")
  local Stack = require("src.core.StateStack")
  Stack:init()
  local World = require("src.world.OverworldController")
  local Save = require("src.core.SaveData")
  Game.stack, Game.data, Game.renderer = Stack, loaded.data, require("src.render.Renderer")
  Game.input = {
    isDown = function()
      return false
    end,
    pressed = function()
      return false
    end,
    wasPressed = function()
      return false
    end,
  }
  Game.save = Save.newGame({ version = edition, noHooks = true, pcItems = { FIX_POTION = 1 } })
  Save.validate(Game.save, Game.data)
  Game.save.party = { require("src.pokemon.Pokemon").new(Game.data, "FIXMON_A", 15) }
  Game.save.meta.playthroughId = "owned-checkpoint-fixture"
  Game.save.player.map, Game.save.player.x, Game.save.player.y = "FIX_TOWN", 2, 3
  Game.overworld, Game.world, Game.mods = World, World, loaded.loader
  loaded.loader.game, loaded.loader.modSave = Game, Game.save.modData
  Stack.states = { World }
  require("src.world.MapLoader").invalidateAll()
  World:_checkpointRebuild({ map = "FIX_TOWN", x = 2, y = 3, facing = "down" })
  return {
    game = Game,
    world = World,
    stack = Stack,
    loaded = loaded,
    checkpoints = loaded.loader.exports[id].checkpoints,
    close = loaded.release,
  }
end
return F
