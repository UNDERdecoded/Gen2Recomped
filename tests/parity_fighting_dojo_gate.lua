-- FightingDojoDefaultScript gates the Karate Master at the one tile to his
-- left.  He is not a regular sight-line trainer (#495).

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not Data.maps then Data:load() end

local S = require("tests.harness").suite("parity Fighting Dojo gate")
local check, eq = S.check, S.eq
local script = require("data.scripts.story4").FIGHTING_DOJO.onStep

local function scene()
  local master = {
    def = { name = "FIGHTINGDOJO_KARATE_MASTER" },
    facing = "down",
    facePlayer = function(self, player)
      self.facing = player.cellX < 5 and "left" or "right"
    end,
  }
  local ow = {
    npcs = { master },
    player = { cellX = 4, cellY = 3, facing = "down" },
    trainerDefeated = function() return false end,
    engageTrainer = function(self, npc) self.engaged = npc end,
  }
  return { save = { flags = {} } }, ow, master
end

local header = Data:trainerHeader("FightingDojo", 1)
eq(header and header.range, 0,
   "Karate Master has no generic trainer sight range")

do
  local game, ow = scene()
  check(not script(game, ow, 5, 4),
        "standing below the downward-facing Master does not trigger him")
  check(ow.engaged == nil, "the below tile does not begin a battle")
end

do
  local game, ow, master = scene()
  check(script(game, ow, 4, 3),
        "the tile immediately left of the Master triggers his script")
  eq(ow.engaged, master, "the Master starts the battle")
  eq(master.facing, "left", "the Master turns toward the player")
  eq(ow.player.facing, "right", "the player turns toward the Master")
end

do
  local game, ow = scene()
  game.save.flags.EVENT_BEAT_KARATE_MASTER = true
  check(not script(game, ow, 4, 3),
        "the gate stays inactive after the Karate Master is beaten")
end

S.finish()
