-- THE GREAT MARSH'S SAFARI BATTLE, per pokeplatinum
-- src/battle/battle_controller_player.c (the four Safari commands),
-- battle_display.c (`Task_SafariPokemonSetCommandSelection`) and the
-- subscripts subscript_throw_safari_ball / _safari_throw_bait /
-- _safari_throw_rock / _safari_escape.
--
-- It is NOT Kanto's. The port's Safari battle was Red's -- BAIT halves the
-- catch rate, ROCK doubles it, the foe flees on twice its Speed -- and Sinnoh
-- has none of that. Two counters, both starting at 6 of 0..12:
--
--   BAIT  catch stage +1 (easier to catch, always); 9 in 10 the escape count
--         also goes +1 ("is eating!"), 1 in 10 it does not ("is busy eating!")
--   MUD   escape count -1 (always); 9 in 10 the catch stage also goes -1
--         ("is angry!"), 1 in 10 not ("is beside itself with anger!")
--   BALL  one Safari Ball (x1.5), on the species' catch rate times
--         sSafariCatchRate[catch stage] -- 10/40 .. 10/10 .. 40/10
--   then the Pokemon's own turn: it FLEES when rand % 255 <= its species'
--   Safari flee rate times sFleeRateMultipliers[escape count] (the same
--   thirteen fractions), and otherwise "is watching carefully!"
--
-- Running away always works. Out of balls after a miss, the announcer ends the
-- game in the battle and the field takes it from there.

local Gen4Safari = {}

Gen4Safari.START_STAGE = 6
Gen4Safari.MAX_STAGE = 12
Gen4Safari.SAFARI_BALL = 5            -- the item number

-- sSafariCatchRate == sFleeRateMultipliers
Gen4Safari.STAGES = require("src.battle.Gen4Catching").SAFARI_STAGES

-- Battle strings, bank 368.
Gen4Safari.TEXT = {
  usedOne = 857, watching = 849, outOfBalls = 850,
  bait = 851, eating = 852, busyEating = 853,
  mud = 854, angry = 855, besideItself = 856,
  gotAway = 781, wildFled = 784,
  labelBall = 931, labelBait = 932, labelMud = 933, labelRun = 927,
  boxTitle = 950, boxLeft = 951,
}

function Gen4Safari.init()
  return { catchStage = Gen4Safari.START_STAGE, escapeCount = Gen4Safari.START_STAGE }
end

-- BattleControllerPlayer_SafariBaitCommand. `roll` is rand % 10.
function Gen4Safari.bait(state, roll)
  if state.catchStage < Gen4Safari.MAX_STAGE then state.catchStage = state.catchStage + 1 end
  if roll ~= 0 and state.escapeCount < Gen4Safari.MAX_STAGE then
    state.escapeCount = state.escapeCount + 1
  end
  return roll ~= 0 and "eating" or "busyEating"
end

-- BattleControllerPlayer_SafariRockCommand -- MUD.
function Gen4Safari.mud(state, roll)
  if state.escapeCount > 0 then state.escapeCount = state.escapeCount - 1 end
  if roll ~= 0 and state.catchStage > 0 then state.catchStage = state.catchStage - 1 end
  return roll ~= 0 and "angry" or "besideItself"
end

-- Task_SafariPokemonSetCommandSelection: does it flee? `roll` is rand % 255.
function Gen4Safari.flees(state, fleeRate, roll)
  local f = Gen4Safari.STAGES[state.escapeCount] or { 10, 10 }
  local rate = math.floor((tonumber(fleeRate) or 0) * f[1] / f[2])
  return roll <= rate
end

-- A line from the battle-strings bank with its STRVAR slots filled in order,
-- and the cartridge's page/scroll controls turned into this engine's breaks.
function Gen4Safari.text(data, id, ...)
  -- the extractor lowers every bank into `text` as TEXT_B<bank>_<line>
  local s = data and data.text and data.text[("TEXT_B0368_%05d"):format(id)]
  if type(s) ~= "string" then return nil end
  local args, i = { ... }, 0
  s = s:gsub("{STRVAR_1[^}]*}", function()
    i = i + 1
    return args[i] ~= nil and tostring(args[i]) or ""
  end)
  s = s:gsub("{[^}]*}", ""):gsub("\012", "\n"):gsub("\011", "")
  return s
end

return Gen4Safari
