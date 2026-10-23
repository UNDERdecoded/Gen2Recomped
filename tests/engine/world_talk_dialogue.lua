package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/world_talk/fixture.lua")
local Version = require("src.core.GameVersion")
local World = require("src.world.OverworldController")
local Stack = require("src.core.StateStack")
local NPC = require("src.world.NPC")
local TextBox = require("src.render.TextBox")
local originalVersion = Version.get()
-- Bind the same module-local dependencies that enter() installs, without
-- loading an imported map/GPU. Neither interact nor talkTo is replaced.
local function bind(fn, name, value)
  for i = 1, 100 do
    local key, old = debug.getupvalue(fn, i)
    if not key then
      break
    end
    if key == name then
      debug.setupvalue(fn, i, value)
      return function()
        debug.setupvalue(fn, i, old)
      end
    end
  end
  error("missing native fixture binding " .. name)
end
for _, version in ipairs(Version.ORDER) do
  local f = Fixture.new(".", "gen2", version, 3, "unified")
  local game, ow = f.game, f.world
  game.stack = setmetatable({}, { __index = Stack })
  game.stack:init()
  game.stack.states = { ow }
  f.result.loader.game = game
  game.world, game.overworld = ow, ow
  game.save.flags, game.save.party = {}, {}
  local mapId = ow.map.id
  ow.map.def = game.data.maps[mapId]
  ow.map.def.objects = {}
  ow.map.def.label = mapId
  ow.entities, ow.npcPool, ow.npcs = {}, {}, {}
  local restoreGame = bind(World.enter, "Game", game)
  local restoreScripts = bind(World.enter, "mapScripts", require("src.script.MapScripts"))
  -- Exercise the native public world adapter and real runtime NPC constructor.
  local api = require("src.world.WorldAPI").new(game, "portable_world_talk")
  local id, why = api:spawnNpc(mapId, {
    name = "GUIDE",
    x = 4,
    y = 5,
    sprite = "SPRITE_YOUNGSTER",
    movement = "STAY",
    facing = "UP",
    text = "A native conversation.",
  })
  T.check(type(id) == "string", version .. " runtime spawn: " .. tostring(why))
  local npc = ow.npcs[1]
  assert(npc, "native runtime actor materialized")
  T.eq(getmetatable(npc), NPC, "real NPC constructor")
  T.eq(npc.def.owner, "portable_world_talk", "runtime ownership preserved")
  ow.talkTo = nil
  f.exports.claim(id)
  ow:interact()
  T.eq(game.stack:top(), ow, "claimed runtime actor opens no native dialogue")
  T.eq(npc.frozen, false, "claim does not acquire native freeze")
  f.exports.claim(nil)
  ow:interact()
  local box = game.stack:top()
  T.eq(getmetatable(box), TextBox, "fallthrough opens actual native TextBox")
  T.eq(npc.frozen, true, "native conversation freezes actor")
  T.eq(npc.facing, "down", "native conversation faces player")
  box.done = true
  box:advance()
  T.eq(game.stack:top(), ow, "native confirmation closes dialogue")
  T.eq(npc.frozen, false, "native completion unfreezes actor")
  f.exports.stop()
  ow:interact()
  box = game.stack:top()
  T.eq(getmetatable(box), TextBox, "unsubscribe preserves native dialogue")
  box.done = true
  box:advance()
  T.eq(api:removeNpc(id), true, "runtime owner can remove its actor")
  T.eq(#ow.npcs, 0, "runtime actor removed from interaction pool")
  restoreScripts()
  restoreGame()
  f.close()
end
Version.set(originalVersion)
T.finish("world.talk native runtime NPC dialogue")
