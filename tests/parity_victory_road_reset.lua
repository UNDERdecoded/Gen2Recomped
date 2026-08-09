-- Regression: Route 23 resets the Victory Road boulder puzzle, and a solved
-- barrier closes again on the next map load (#258).  scripts/Route23.asm:8 and
-- scripts/VictoryRoad2F.asm:19 reset the switch events on entry; neither was
-- ported.  scripts/VictoryRoad1F.asm:14 only ever stamps the OPEN block, but
-- the port's Map:setBlock writes through to the shared Game.data record, so it
-- has to stamp the CLOSED block itself or the barrier stays open all session.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.VICTORY_ROAD_2F) then Data:load() end

local mapScripts = require("data.scripts.init")
local S = require("tests.harness").suite("parity victory road reset")
local check, eq = S.check, S.eq

local SW1F = "EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH"
local SW2A = "EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1"
local SW2B = "EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2"
local SW3A = "EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1"
local SW3B = "EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2"

-- ---- ground truth: the shipped .blk bytes and the object names -----------
-- The closed ids the onEnter hooks stamp back must BE the map's own bytes,
-- so read them out of data/generated rather than typing them in.
local function blockAt(mapId, bx, by)
  local def = Data.maps[mapId]
  return def.blocks[by * def.width + bx + 1]
end

local CLOSED = {
  { "VICTORY_ROAD_1F", 4, 6, 0x25 },
  { "VICTORY_ROAD_2F", 3, 4, 0x37 },
  { "VICTORY_ROAD_2F", 11, 7, 0x25 },
  { "VICTORY_ROAD_3F", 3, 5, 0x25 },
}
for _, b in ipairs(CLOSED) do
  eq(blockAt(b[1], b[2], b[3]), b[4],
     ("%s block (%d,%d) ships closed as 0x%02X"):format(b[1], b[2], b[3], b[4]))
end

-- data/maps/toggleable_objects.asm:202 names the last 2F entry
-- VICTORYROAD2F_BOULDER3 and the last 3F one VICTORYROAD3F_BOULDER4
local function objectNames(mapId)
  local names = {}
  for _, o in ipairs(Data.maps[mapId].objects or {}) do names[o.name or "?"] = true end
  return names
end
local names2F, names3F = objectNames("VICTORY_ROAD_2F"), objectNames("VICTORY_ROAD_3F")
check(names2F.VICTORYROAD2F_BOULDER3,
      "VICTORY_ROAD_2F really has an object named VICTORYROAD2F_BOULDER3")
check(names3F.VICTORYROAD3F_BOULDER4,
      "VICTORY_ROAD_3F really has an object named VICTORYROAD3F_BOULDER4")
check(not names2F.VICTORYROAD2F_BOULDER,
      "and nothing is named VICTORYROAD2F_BOULDER (the old, never-matching key)")

-- Map:setBlock writes into the shared Game.data record, which is the invariant
-- the both-ways stamp exists for.  Restored immediately: every later suite in
-- this process reads the same table.
do
  local def = Data.maps.VICTORY_ROAD_1F
  local MapLoader = require("src.world.MapLoader")
  local map = MapLoader.load(Data, "VICTORY_ROAD_1F")
  local before = blockAt("VICTORY_ROAD_1F", 4, 6)
  map:setBlock(4, 6, 0x1D)
  eq(blockAt("VICTORY_ROAD_1F", 4, 6), 0x1D,
     "replaceBlock/setBlock writes through to the SHARED map record")
  map:setBlock(4, 6, before)
  eq(def.blocks[6 * def.width + 4 + 1], 0x25, "restored for the rest of the run")
end

-- ---- fakes ---------------------------------------------------------------
-- The hooks only need a save with flags and an ow that records replaceBlock.
-- Commands.toggleObject returns early once it has written save.objectToggles
-- when the toggle targets another map, which it always does here.
local function world(mapId)
  local game = { data = Data, save = { flags = {}, objectToggles = {} } }
  local ow = {
    -- toggleObject walks these when the toggle names the CURRENT map; empty
    -- lists make that a no-op and leave objectToggles as the assertion surface
    map = { id = mapId, def = Data.maps[mapId] or { objects = {} } },
    npcs = {}, entities = {}, npcPool = {},
    stamped = {},
    replaceBlock = function(self, bx, by, block)
      self.stamped[bx .. "," .. by] = block
    end,
    npcAtCell = function() return nil end,
  }
  return game, ow
end

local function hooks(mapId)
  local h = mapScripts.get(mapId)
  check(h ~= nil, mapId .. " has hand-ported hooks")
  return h or {}
end

local route23 = hooks("ROUTE_23")
local vr1 = hooks("VICTORY_ROAD_1F")
local vr2 = hooks("VICTORY_ROAD_2F")
local vr3 = hooks("VICTORY_ROAD_3F")
check(route23.talk ~= nil, "ROUTE_23's badge-guard talk table survived the merge")

-- A missing hook should read as a wall of failed expectations, not as one
-- traceback that hides every later assertion.
local function hookFn(h, key, label)
  local fn = h[key]
  if check(type(fn) == "function", label .. " exists") then return fn end
  return function() end
end

local r23Enter = hookFn(route23, "onEnter", "ROUTE_23.onEnter (Route23SetVictoryRoadBoulders)")
local vr1Enter = hookFn(vr1, "onEnter", "VICTORY_ROAD_1F.onEnter")
local vr2Enter = hookFn(vr2, "onEnter", "VICTORY_ROAD_2F.onEnter")
local vr3Enter = hookFn(vr3, "onEnter", "VICTORY_ROAD_3F.onEnter")
local vr2Boulder = hookFn(vr2, "onBoulderMoved", "VICTORY_ROAD_2F.onBoulderMoved")
local vr3Boulder = hookFn(vr3, "onBoulderMoved", "VICTORY_ROAD_3F.onBoulderMoved")

-- ---- entering Route 23 resets everything --------------------------------
do
  local game, ow = world("ROUTE_23")
  local f = game.save.flags
  f[SW2A], f[SW2B], f[SW3A], f[SW3B] = true, true, true, true
  f[SW1F] = true
  r23Enter(game, ow)
  check(not f[SW2A], "entering Route 23 clears 2F switch 1")
  check(not f[SW2B], "entering Route 23 clears 2F switch 2")
  check(not f[SW3A], "entering Route 23 clears 3F switch 1")
  check(not f[SW3B], "entering Route 23 clears 3F switch 2")
  check(f[SW1F], "1F's event is NOT reset here (the lobby and 2F own it)")
  local t = game.save.objectToggles
  eq(t.VICTORY_ROAD_3F and t.VICTORY_ROAD_3F.VICTORYROAD3F_BOULDER4, true,
     "the 3F boulder is shown again (ShowObject TOGGLE_VICTORY_ROAD_3F_BOULDER)")
  eq(t.VICTORY_ROAD_2F and t.VICTORY_ROAD_2F.VICTORYROAD2F_BOULDER3, false,
     "the 2F copy is hidden again (HideObject TOGGLE_VICTORY_ROAD_2F_BOULDER)")
end

-- ---- each floor stamps its barrier BOTH ways on entry --------------------
do
  local game, ow = world("VICTORY_ROAD_1F")
  vr1Enter(game, ow)
  eq(ow.stamped["4,6"], 0x25, "1F: no switch solved -> the barrier is solid rock")
  game.save.flags[SW1F] = true
  vr1Enter(game, ow)
  eq(ow.stamped["4,6"], 0x1D, "1F: switch solved -> the barrier is open")
end

do
  local game, ow = world("VICTORY_ROAD_2F")
  game.save.flags[SW1F] = true
  vr2Enter(game, ow)
  check(not game.save.flags[SW1F],
        "entering 2F clears the 1F switch event (VictoryRoad2FResetBoulderEventScript)")
  eq(ow.stamped["3,4"], 0x37, "2F: switch 1 unsolved -> solid")
  eq(ow.stamped["11,7"], 0x25, "2F: switch 2 unsolved -> solid")
  game.save.flags[SW2A], game.save.flags[SW2B] = true, true
  vr2Enter(game, ow)
  eq(ow.stamped["3,4"], 0x15, "2F: switch 1 solved -> open")
  eq(ow.stamped["11,7"], 0x1D, "2F: switch 2 solved -> open")
end

do
  local game, ow = world("VICTORY_ROAD_3F")
  vr3Enter(game, ow)
  eq(ow.stamped["3,5"], 0x25, "3F: switch unsolved -> solid")
  game.save.flags[SW3A] = true
  vr3Enter(game, ow)
  eq(ow.stamped["3,5"], 0x1D, "3F: switch solved -> open")
end

-- ---- the 3F hole hands its boulder to 2F, once ---------------------------
do
  local game, ow = world("VICTORY_ROAD_3F")
  local boulder = { cellX = 23, cellY = 15, def = { name = "VICTORYROAD3F_BOULDER4" } }
  vr3Boulder(game, ow, boulder)
  check(game.save.flags[SW3B],
        "dropping a boulder down the hole sets switch-2's event (CheckAndSetEvent)")
  local t = game.save.objectToggles
  eq(t.VICTORY_ROAD_3F and t.VICTORY_ROAD_3F.VICTORYROAD3F_BOULDER4, false,
     "the boulder disappears from 3F")
  eq(t.VICTORY_ROAD_2F and t.VICTORY_ROAD_2F.VICTORYROAD2F_BOULDER3, true,
     "and appears on 2F under its REAL object name")

  -- CheckAndSetEvent: the second boulder down the same hole is a no-op
  t.VICTORY_ROAD_2F.VICTORYROAD2F_BOULDER3 = "untouched"
  local second = { cellX = 23, cellY = 15, def = { name = "VICTORYROAD3F_BOULDER3" } }
  vr3Boulder(game, ow, second)
  eq(t.VICTORY_ROAD_2F.VICTORYROAD2F_BOULDER3, "untouched",
     "a second boulder into the already-used hole changes nothing")
end

-- ---- the reporter's round trip ------------------------------------------
-- Solve 2F switch 1, walk out to Route 23, come back: the barrier must be rock
-- again and the fallen boulder must be back upstairs.
do
  local game, ow2 = world("VICTORY_ROAD_2F")
  vr2Enter(game, ow2)
  eq(ow2.stamped["3,4"], 0x37, "arrive on 2F with the puzzle untouched")

  local boulder = { cellX = 1, cellY = 16, def = { name = "VICTORYROAD2F_BOULDER1" } }
  vr2Boulder(game, ow2, boulder)
  check(game.save.flags[SW2A], "pushing the boulder onto the switch solves it")
  eq(ow2.stamped["3,4"], 0x15, "and the barrier opens immediately")

  -- ...and stays open while you are still on the floor
  vr2Enter(game, ow2)
  eq(ow2.stamped["3,4"], 0x15, "re-entering 2F with the switch still set keeps it open")

  local _, ow23 = world("ROUTE_23")
  ow23.map.id = "ROUTE_23"
  r23Enter(game, ow23)
  vr2Enter(game, ow2)
  eq(ow2.stamped["3,4"], 0x37,
     "after a trip through Route 23 the 2F barrier is solid rock again")
  eq(ow2.stamped["11,7"], 0x25, "and so is the other one")

  local _, ow3 = world("VICTORY_ROAD_3F")
  vr3Enter(game, ow3)
  eq(ow3.stamped["3,5"], 0x25, "3F's barrier is closed again too")
end

S.finish()
