-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HOENN CATCHES POKEMON WITH A DIFFERENT SUM.
--
-- Gen 1's ItemUseBall rolls a random byte against a ceiling that the ball
-- itself sets (255 / 200 / 150) and works the HP in afterwards.  Emerald's
-- Cmd_handleballthrow does neither: the ball contributes a MULTIPLIER, the HP
-- and the status scale the result, and what comes out is compared against a
-- fixed 254 before four shake rolls decide the rest.  This file is that sum,
-- and every number in it comes off the cartridge through extractBalls -- the
-- bonuses, which balls compute their own, and the two status groups.
--
-- THE SUM, in the order 080564D2 does it:
--
--   odds = catchRate * bonus / 10
--   odds = odds * (3*maxHP - 2*curHP) / (3*maxHP)
--   asleep or frozen              -> odds * 2
--   poisoned, burned or paralysed -> odds * 15 / 10
--   odds > 254                    -> caught, three shakes and no roll
--   otherwise
--       odds = 1048560 / Sqrt(Sqrt(16711680 / odds))
--       four rolls: Random() < odds or the ball breaks open there
--
-- THE TWO SQUARE ROOTS ARE NOT DECORATION.  They are what makes the shake
-- count read as tension: a catch that fails at three shakes was close, and
-- one that fails at none was never going to happen.  Rounding them away --
-- or reaching for Gen 1's wobble table, which answers a different question --
-- gives a ball that catches at the right rate and LIES about it every time.
--
-- WHAT THIS FILE DOES NOT DECIDE: whether the ball is thrown at all, what it
-- looks like, or what a caught Pokemon does next.  Catching.attempt is the
-- seam (a ball record may carry its own `attempt`), so this is registered as
-- twelve records and the battle code is unchanged.

local Gen3Catching = {}

-- the cartridge's own two constants, and they are not round numbers by
-- accident: 16711680 is 0xFF0000 and 1048560 is 0xFFFF0, which is how the
-- driver gets a fixed-point fourth root out of two integer square roots
local ODDS_NUMERATOR = 16711680
local SHAKE_NUMERATOR = 1048560
local CAUGHT_OUTRIGHT = 254
local SHAKES = 4
local SCALE = 10

-- Sqrt (082E70C4) is an integer square root: the largest n with n*n <= x.
-- math.sqrt's float is the same answer for every value this sees, but the
-- floor has to be explicit or a catch sitting exactly on a boundary can fall
-- the wrong side of it.
local function isqrt(x)
  if x <= 0 then return 0 end
  local n = math.floor(math.sqrt(x))
  -- walk back onto the integer answer, because a float sqrt of a large
  -- integer can land a unit either side of it
  while n * n > x do n = n - 1 end
  while (n + 1) * (n + 1) <= x do n = n + 1 end
  return n
end

Gen3Catching.isqrt = isqrt

local function has(list, want)
  for _, v in ipairs(list or {}) do if v == want then return true end end
  return false
end

-- WHAT THE BALL IS WORTH, in tenths.  Five of the twelve compute it rather
-- than carry it, and each one asks a different question of the world -- which
-- is why the record carries a `rule` and this reads it rather than switching
-- on the ball's name.
function Gen3Catching.bonus(record, ball, ctx)
  if type(record) ~= "table" then return SCALE end
  local rule = record.rule and record.rule[ball]
  if not rule then
    return math.floor(tonumber(record.bonus and record.bonus[ball]) or SCALE)
  end
  local otherwise = math.floor(tonumber(rule.otherwise) or SCALE)
  if rule.kind == "type" then
    local def = ctx and ctx.targetDef
    local types = def and def.types
    for _, t in ipairs(types or {}) do
      if has(rule.types, t) then
        return math.floor(tonumber(rule.bonus) or otherwise)
      end
    end
    return otherwise
  elseif rule.kind == "underwater" then
    return ctx and ctx.underwater
       and math.floor(tonumber(rule.bonus) or otherwise) or otherwise
  elseif rule.kind == "level" then
    -- 40 minus the level, and never below the plain ball's own worth: a
    -- level-40 Pokemon is exactly where the NEST BALL stops being special
    local level = math.floor(tonumber(ctx and ctx.level) or 1)
    local from = math.floor(tonumber(rule.from) or 40)
    return math.max(math.floor(tonumber(rule.floor) or SCALE), from - level)
  elseif rule.kind == "caught" then
    return (ctx and ctx.alreadyCaught)
       and math.floor(tonumber(rule.bonus) or otherwise) or otherwise
  elseif rule.kind == "turns" then
    -- the turn counter, not the turn number: a ball thrown on the first turn
    -- is worth exactly a POKe BALL
    local turns = math.floor(tonumber(ctx and ctx.turns) or 0)
    local value = turns + math.floor(tonumber(rule.add) or SCALE)
    return math.max(math.floor(tonumber(rule.floor) or SCALE),
                    math.min(math.floor(tonumber(rule.cap) or value), value))
  end
  return otherwise
end

-- The odds before the shake maths, which is the number the cartridge compares
-- against 254.  Kept separate because it is the half a test can check without
-- a random number in it.
function Gen3Catching.odds(record, ball, ctx)
  local rate = math.max(0, math.floor(tonumber(ctx.catchRate) or 0))
  local scale = math.floor(tonumber(record and record.scale) or SCALE)
  local odds = math.floor(rate * Gen3Catching.bonus(record, ball, ctx) / scale)
  local maxHP = math.max(1, math.floor(tonumber(ctx.maxHP) or 1))
  local hp = math.max(0, math.floor(tonumber(ctx.hp) or maxHP))
  odds = math.floor(odds * (3 * maxHP - 2 * hp) / (3 * maxHP))
  local status = ctx.status
  if status then
    if has(record and record.statusDouble, status) then
      odds = odds * 2
    elseif has(record and record.statusHalf, status) then
      odds = math.floor(odds * 15 / 10)
    end
  end
  return odds
end

-- ...and how many times it shakes.  Answers `caught, shakes` the way
-- Catching.attempt's callers expect.
function Gen3Catching.attempt(record, ball, ctx, rng)
  rng = rng or math.random
  if ball == (record and record.master) then return true, 3 end
  local odds = Gen3Catching.odds(record, ball, ctx)
  if odds > CAUGHT_OUTRIGHT then return true, 3 end
  if odds <= 0 then return false, 0 end
  local shake = SHAKE_NUMERATOR
                / math.max(1, isqrt(isqrt(math.floor(ODDS_NUMERATOR / odds))))
  shake = math.floor(shake)
  for i = 1, SHAKES do
    if rng(0, 65535) >= shake then return false, i - 1 end
  end
  return true, SHAKES - 1
end

return Gen3Catching
