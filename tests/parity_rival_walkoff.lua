-- Parity: Route 22 + Cerulean rival post-battle exits (#154 / #168).
--
-- pokered Route22Rival{1,2}ExitMovementData* and CeruleanCityMovement3/4
-- plus CeruleanCityRivalText's Bill line after EVENT_BEAT_CERULEAN_RIVAL.
--
--   luajit tests/parity_rival_walkoff.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity rival walkoff")
local check, eq = S.check, S.eq

-- restored at the bottom for the suites run after this file
local realMusic = package.loaded["src.core.Music"]
local realCommands = package.loaded["src.script.Commands"]
local realPicBox = package.loaded["src.ui.PicBox"]
package.loaded["src.core.Music"] = {
  play = function() end, playOnce = function() return true end, stop = function() end,
}
package.loaded["src.script.Commands"] = {
  hide_object = function() end,
}
package.loaded["src.ui.PicBox"] = { new = function() return {} end }

local story5 = dofile("data/scripts/story5.lua")
local story = dofile("data/scripts/story.lua")

local function dirsEqual(a, b)
  if type(a) ~= "table" or #a ~= #b then return false end
  for i = 1, #b do if a[i] ~= b[i] then return false end end
  return true
end

local function findWalk(rows)
  for _, r in ipairs(rows) do
    if r[1] == "walk_npc" then return r end
  end
end

local function texts(rows)
  local out = {}
  for _, r in ipairs(rows) do
    if r[1] == "show_text" then out[#out + 1] = r[2] end
  end
  return out
end

local function capture(mapMod, game, x, y)
  local rows
  local ow = {
    runner = {
      isRunning = function() return false end,
      run = function(_, r) rows = r end,
    },
    player = { facing = "down" },
    npcByIndex = function() return { def = { name = "X" } } end,
  }
  check(mapMod.onStep(game, ow, x, y),
        ("onStep fires at (%d,%d)"):format(x, y))
  check(rows ~= nil, "onStep queued rows")
  return rows
end

-- Route22Rival1ExitMovementData1 / Data2, keyed on wSavedCoordIndex (which
-- Route22RivalBattleCoords entry matched, counted from 1) and NOT on the
-- rival's own row: index 1 is the (29,4) tile, where he stops BELOW the
-- player on (29,5) and leaves east; index 2 is the (29,5) tile, where he
-- stops LEFT of him on (28,5) and must step UP to row 4 to get around him.
-- This mapping was backwards until #236 (the y=4 walk began UP into the
-- cliff cell (28,3)), so these constants flipped with the fix.
local R1_Y4 = { "right", "right", "down", "down", "down", "down", "down" }
local R1_Y5 = { "up", "right", "right", "right",
                "down", "down", "down", "down", "down", "down" }
-- Route22Rival2ExitMovementData1 falls through Data2, so index 1 (y=4) is
-- LEFT x4 from (29,5) and index 2 (y=5) LEFT x3 from (28,5)
local R2_Y4 = { "left", "left", "left", "left" }
local R2_Y5 = { "left", "left", "left" }
local CER_X20 = { "right", "down", "down", "down", "down", "down", "down" }
local CER_X21 = { "left", "down", "down", "down", "down", "down", "down" }

do
  local game = { save = { flags = { EVENT_GOT_POKEDEX = true } }, data = {} }
  local w5 = findWalk(capture(story5.ROUTE_22, game, 29, 5))
  local w4 = findWalk(capture(story5.ROUTE_22, game, 29, 4))
  check(dirsEqual(w5[3], R1_Y5), "Rival1 y=5 goes U,R×3,D×6 around the player")
  check(dirsEqual(w4[3], R1_Y4), "Rival1 y=4 exits toward Viridian (R,R,D×5)")
  local rows = capture(story5.ROUTE_22,
    { save = { flags = { EVENT_GOT_POKEDEX = true } }, data = {} }, 29, 5)
  for _, r in ipairs(rows) do
    check(not (r[1] == "move_npc_to" and r[3] == 25 and r[4] == 5),
          "Rival1 must not retreat to spawn (25,5)")
  end
end

do
  local flags = {
    EVENT_BEAT_BROCK = true,
    EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE = true,
    EVENT_BEAT_GIOVANNI = true,
  }
  local w5 = findWalk(capture(story5.ROUTE_22, { save = { flags = flags }, data = {} }, 29, 5))
  local w4 = findWalk(capture(story5.ROUTE_22, { save = { flags = flags }, data = {} }, 29, 4))
  check(dirsEqual(w5[3], R2_Y5), "Rival2 y=5 exits left×3 toward League")
  check(dirsEqual(w4[3], R2_Y4), "Rival2 y=4 exits left×4 toward League")
end

do
  local rows = capture(story5.CERULEAN_CITY, { save = { flags = {} }, data = {} }, 20, 6)
  local t = texts(rows)
  local hasBill = false
  for _, id in ipairs(t) do
    if id == "_CeruleanCityRivalIWentToBillsText" then hasBill = true end
  end
  check(hasBill, "Cerulean post-battle includes Bill dialogue")
  local order = {
    "_CeruleanCityRivalPreBattleText",
    "_CeruleanCityRivalDefeatedText",
    "_CeruleanCityRivalIWentToBillsText",
  }
  local pi = 1
  for _, id in ipairs(t) do
    if pi <= #order and id == order[pi] then pi = pi + 1 end
  end
  eq(pi, #order + 1, "Cerulean text order: pre, defeated, Bill")
  check(dirsEqual(findWalk(rows)[3], CER_X20),
        "Cerulean x=20 exit: right then into town")
  for _, r in ipairs(rows) do
    check(not (r[1] == "move_npc_to" and r[4] == 2),
          "Cerulean must not walk back north to (20,2)")
  end
end

do
  local rows = capture(story5.CERULEAN_CITY, { save = { flags = {} }, data = {} }, 21, 6)
  check(dirsEqual(findWalk(rows)[3], CER_X21),
        "Cerulean x=21 exit: left then into town")
end

do
  local talk = story.CERULEAN_CITY.talk.TEXT_CERULEANCITY_RIVAL
  check(talk ~= nil, "talk script for CERULEANCITY_RIVAL exists")
  local hasBill = false
  for _, r in ipairs(talk) do
    if r[1] == "show_text" and r[2] == "_CeruleanCityRivalIWentToBillsText" then
      hasBill = true
    end
  end
  check(hasBill, "talk path also exposes Bill dialogue")
end

package.loaded["src.core.Music"] = realMusic
package.loaded["src.script.Commands"] = realCommands
package.loaded["src.ui.PicBox"] = realPicBox

S.finish()
