-- Parity test: Pokemon Tower 5F purified-zone heal pad (#81).
--
-- pokered scripts/PokemonTower5F.asm PokemonTower5FDefaultScript:
--   coords (10,8)/(11,8)/(10,9)/(11,9); CheckAndSetEvent
--   EVENT_IN_PURIFIED_ZONE so the heal fires once until the player
--   leaves; HealParty -> GBFadeOutToWhite -> Delay3 x2 ->
--   GBFadeInFromWhite -> _PokemonTower5FPurifiedZoneText (no heal jingle).
--
-- Self-contained; run via `luajit tests/parity_tower_heal_pad.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity tower heal pad")
local check, eq = S.check, S.eq

local M = dofile("data/scripts/story3.lua")
local tower = M.POKEMON_TOWER_5F
check(tower ~= nil and type(tower.onStep) == "function",
      "POKEMON_TOWER_5F has an onStep heal-pad trigger")

local function cmds(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = row[1] end
  return out
end

local function gameWith(flags)
  return { save = { flags = flags or {} } }
end

local function owWith()
  local ran = {}
  return {
    runner = {
      isRunning = function() return false end,
      run = function(_, rows) ran[#ran + 1] = rows end,
    },
  }, ran
end

-- ---- 1. pad coords + leave clears latch --------------------------------
do
  local game = gameWith()
  local ow, ran = owWith()
  check(not tower.onStep(game, ow, 9, 8), "off-pad X does not heal")
  check(not tower.onStep(game, ow, 10, 7), "off-pad Y does not heal")
  eq(#ran, 0, "no script off the pad")
end

do
  local game = gameWith()
  local ow, ran = owWith()
  check(tower.onStep(game, ow, 10, 8), "first step on (10,8) heals")
  check(game.save.flags.EVENT_IN_PURIFIED_ZONE, "latches EVENT_IN_PURIFIED_ZONE")
  eq(#ran, 1, "heal script runs once")

  check(tower.onStep(game, ow, 11, 9),
        "staying on the pad still consumes the step (BIT_NO_BATTLES)")
  eq(#ran, 1, "heal does not re-fire while still on the pad")

  check(not tower.onStep(game, ow, 12, 9), "stepping off clears and returns false")
  check(not game.save.flags.EVENT_IN_PURIFIED_ZONE,
        "EVENT_IN_PURIFIED_ZONE resets off the pad")

  check(tower.onStep(game, ow, 11, 8), "re-entering the pad heals again")
  eq(#ran, 2, "a fresh visit runs the heal script again")
end

-- ---- 2. all four pad tiles trigger -------------------------------------
for _, cell in ipairs({ { 10, 8 }, { 11, 8 }, { 10, 9 }, { 11, 9 } }) do
  local game = gameWith()
  local ow, ran = owWith()
  check(tower.onStep(game, ow, cell[1], cell[2]),
        ("pad tile (%d,%d) heals"):format(cell[1], cell[2]))
  eq(#ran, 1, ("pad tile (%d,%d) queued a script"):format(cell[1], cell[2]))
end

-- ---- 3. heal sequence matches pokered order ----------------------------
do
  local game = gameWith()
  local ow, ran = owWith()
  tower.onStep(game, ow, 10, 9)
  local rows = ran[1]
  check(rows ~= nil, "heal rows captured")
  local sequence = table.concat(cmds(rows), ",")
  eq(sequence, "heal_party,fade,wait,wait,fade,show_text",
     "Tower pad sequence is heal → fade out → Delay3×2 → fade in → text")
  eq(rows[2][3], "white", "fades out to white")
  eq(rows[3][2], 3, "first Delay3 is 3 frames")
  eq(rows[4][2], 3, "second Delay3 is 3 frames")
  eq(rows[5][3], "white", "fades in from white")
  eq(rows[6][2], "_PokemonTower5FPurifiedZoneText",
     "shows the purified-zone text")
  for _, row in ipairs(rows) do
    check(row[1] ~= "play_once", "no Music_PkmnHealed on the Tower pad")
  end
end

S.finish()
