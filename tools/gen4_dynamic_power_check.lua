-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SINNOH'S DYNAMIC-POWER MOVES: four effects, five moves, and whether the
-- numbers they produce are the cartridge's.
--
-- Gyro Ball, Wring Out, Crush Grip, Brine and Wake-Up Slap all work out their
-- base power at the moment they are used. A WRONG FORMULA HERE NEVER RAISES:
-- the move hits, for the wrong amount, and reads as a damage-roll quirk. Only
-- arithmetic says otherwise, so every case below is a number taken from
-- pokeplatinum and checked against what `MoveEffects` returns.
--
-- WHERE EACH NUMBER COMES FROM. pokeplatinum names its per-effect battle
-- scripts BY EFFECT ID -- `res/battle/scripts/effects/effect_script_NNNN.s` --
-- so these are transcriptions, not recollections:
--
--   217  effect_script_0217.s  CheckSubstitute, then SLEEP -> POWER_MULTI 20
--                              plus ON_HIT | HEAL_TARGET_SLEEP
--   219  effect_script_0219.s  CalcGyroBallPower
--                              1 + 25 * defSpeed / atkSpeed, capped at 150
--   221  effect_script_0221.s  temp = maxHP / 2; curHP > temp ? 10 : 20
--   237  effect_script_0237.s  CalcWringOutPower
--                              1 + (120 * curHP) / maxHP
--
-- `POWER_MULTI` is in TENTHS: 10 is the move's own power, 20 is double.
--
-- THE CASES THAT EARN THEIR PLACE are the boundaries, because that is where a
-- plausible implementation and the cartridge part company:
--
--   * Brine on EXACTLY half. The script tests `curHP > maxHP / 2` with an
--     integer halving, so a target on exactly half is not above it and takes
--     the DOUBLED hit. `cur < max / 2` would get this backwards, and on every
--     odd maximum as well.
--   * Wake-Up Slap into a SUBSTITUTE. The script's `CheckSubstitute` jumps
--     past the doubling AND the wake, so a sleeping Pokemon behind one takes
--     60 and stays asleep. One branch, two consequences.
--   * Gyro Ball against a zero-speed user, which in C divides by zero.
--   * Wring Out against a target on 0 HP, where the formula's 1 is the floor.
--
-- AND BOTH SIDES OF THE WIRING, because an effect id with no name runs as a
-- plain hit and an effect name with no record does the same: section 1 asserts
-- the id names the effect AND that `MoveEffects` has a record under that name.
-- Either half alone passes while the move does nothing.
--
-- Run:  texlua tools/gen4_dynamic_power_check.lua [pokeplatinum dir]
--
-- With pokeplatinum, section 5 re-reads the four effect scripts and asserts
-- the constants this file was written from are still the ones on disk.

package.path = "./?.lua;" .. package.path

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = { getWidth = function() return 256 end, getHeight = function() return 192 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local PP = arg and arg[1]

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-54s %s\n"):format(what, tostring(got)))
  else
    fails = fails + 1
    io.write(("  FAIL  %-54s got %s, expected %s\n")
             :format(what, tostring(got), tostring(want)))
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local MoveEffects = require("src.battle.MoveEffects")
local Gen4Moves = require("src.import.Gen4Moves")

-- ---------------------------------------------------------------------------
section("1. both halves of the wiring: the id names it, and the name has a record")
-- ---------------------------------------------------------------------------
local WIRED = {
  { 217, "DOUBLE_POWER_HEAL_SLEEP", "Wake-Up Slap" },
  { 219, "POWER_BASED_ON_LOW_SPEED",    "Gyro Ball" },
  { 221, "DOUBLE_POWER_WHEN_BELOW_HALF",        "Brine" },
  { 237, "INCREASE_POWER_WITH_MORE_HP",    "Wring Out / Crush Grip" },
}
for _, row in ipairs(WIRED) do
  local id, name, moves = row[1], row[2], row[3]
  local got = Gen4Moves.EFFECTS[id] and Gen4Moves.EFFECTS[id][1]
  ok(got == name, ("effect %d (%s) is named"):format(id, moves), got or "nothing", name)
  ok(MoveEffects.full[name] ~= nil,
     ("...and %s has a record"):format(name),
     MoveEffects.full[name] ~= nil, true)
  ok(MoveEffects.full[name] and MoveEffects.full[name].chooseDamage ~= nil,
     "...which computes its own damage",
     MoveEffects.full[name] and MoveEffects.full[name].chooseDamage ~= nil, true)
end

-- ---------------------------------------------------------------------------
-- THE FIXTURE. `variablePower` hands its number to `battle:computeDamage`, so
-- stubbing that to return the move's power reads the chosen power straight
-- back out -- after `withPower`'s floor and its minimum of 1, which are part
-- of the answer rather than something to bypass.
-- ---------------------------------------------------------------------------
local said = {}
local function ctxFor(move, user, target)
  return {
    move = move, user = user, target = target,
    battle = {
      rng = function(_, n) return n or 1 end,
      computeDamage = function(_, _, _, mv) return mv.power end,
      applyDamage = function() end,
      sayNext = function() end,
    },
    say = function(t) said[#said + 1] = tostring(t) end,
  }
end
local function mon(hp, maxHP, status) return { hp = hp, maxHP = maxHP, status = status } end
local function battler(speed, m, substituteHP)
  return { mon = m, curStats = { speed = speed }, stages = {},
           substituteHP = substituteHP, name = "SNORLAX", isPlayer = false }
end
local function powerOf(name, move, user, target)
  local record = MoveEffects.full[name]
  if not (record and record.chooseDamage) then return nil end
  return record.chooseDamage(ctxFor(move, user, target))
end

-- ---------------------------------------------------------------------------
section("2. Gyro Ball: 1 + 25 * defSpeed / atkSpeed, capped at 150")
-- ---------------------------------------------------------------------------
local GB = { power = 1 }
local function gyro(atk, def) return powerOf("POWER_BASED_ON_LOW_SPEED", GB, battler(atk, mon(10, 10)), battler(def, mon(10, 10))) end
ok(gyro(100, 200) == 51, "a slow user against a fast target", gyro(100, 200), 51)
ok(gyro(200, 100) == 13, "a fast user against a slow target", gyro(200, 100), 13)
ok(gyro(100, 100) == 26, "equal speeds", gyro(100, 100), 26)
-- THE CAP, which is in the command and not in the move's data.
ok(gyro(1, 1000) == 150, "a huge ratio stops at the cap", gyro(1, 1000), 150)
-- C WOULD HAVE DIVIDED BY ZERO HERE. A paralysed Pokemon on a speed floor is
-- enough to reach it, so the engine answers "as slow as possible" instead.
ok(gyro(0, 100) == 150, "a zero-speed user does not divide by zero", gyro(0, 100), 150)
-- A CONTROL: the formula must actually depend on BOTH speeds. A function that
-- ignored the attacker would return the same number for these two.
ok(gyro(100, 200) ~= gyro(200, 200),
   "...and the result depends on the attacker's speed too",
   ("%s vs %s"):format(tostring(gyro(100, 200)), tostring(gyro(200, 200))), "different")

-- ---------------------------------------------------------------------------
section("3. Wring Out and Crush Grip: 1 + 120 * curHP / maxHP")
-- ---------------------------------------------------------------------------
local WO = { power = 1 }
local function wring(hp, maxHP) return powerOf("INCREASE_POWER_WITH_MORE_HP", WO, battler(100, mon(10, 10)), battler(100, mon(hp, maxHP))) end
ok(wring(100, 100) == 121, "a target at full health", wring(100, 100), 121)
ok(wring(50, 100) == 61, "a target at half", wring(50, 100), 61)
ok(wring(1, 100) == 2, "a target on its last point", wring(1, 100), 2)
ok(wring(0, 100) == 1, "a target on zero floors at 1", wring(0, 100), 1)
-- IT DECAYS. Reversal does the opposite, and this is the assertion that says
-- which way round this one goes.
ok(wring(100, 100) > wring(25, 100),
   "...and it is STRONGEST on a healthy target, unlike Reversal",
   ("full %d > quarter %d"):format(wring(100, 100), wring(25, 100)), "decreasing")

-- ---------------------------------------------------------------------------
section("4. Brine: doubled unless curHP is ABOVE floor(maxHP / 2)")
-- ---------------------------------------------------------------------------
local BR = { power = 65 }
local function brine(hp, maxHP) return powerOf("DOUBLE_POWER_WHEN_BELOW_HALF", BR, battler(100, mon(10, 10)), battler(100, mon(hp, maxHP))) end
ok(brine(100, 100) == 65, "a healthy target takes the move's own power", brine(100, 100), 65)
ok(brine(51, 100) == 65, "one point above half", brine(51, 100), 65)
-- THE BOUNDARY. `curHP > maxHP / 2` is false at exactly half, so this doubles.
ok(brine(50, 100) == 130, "EXACTLY half is doubled, because the test is >", brine(50, 100), 130)
-- ...AND THE HALVING FLOORS. 21 / 2 is 10, so 10 doubles and 11 does not.
ok(brine(10, 21) == 130, "an odd maximum: 21 halves to 10, and 10 doubles", brine(10, 21), 130)
ok(brine(11, 21) == 65, "...while 11 is above it and does not", brine(11, 21), 65)
-- AND IT READS THE MOVE'S POWER rather than a hardcoded 130, so the day the
-- cartridge's base power changes this still agrees with it.
ok(powerOf("DOUBLE_POWER_WHEN_BELOW_HALF", { power = 40 }, battler(100, mon(10, 10)), battler(100, mon(10, 100))) == 80,
   "...and the doubling is of the MOVE's power, not a constant",
   powerOf("DOUBLE_POWER_WHEN_BELOW_HALF", { power = 40 }, battler(100, mon(10, 10)), battler(100, mon(10, 100))), 80)

-- ---------------------------------------------------------------------------
section("5. Wake-Up Slap: doubled on a sleeping target, and it wakes it")
-- ---------------------------------------------------------------------------
local WS = { power = 60 }
local function slap(m, sub) return powerOf("DOUBLE_POWER_HEAL_SLEEP", WS, battler(100, mon(10, 10)), battler(100, m, sub)) end
ok(slap(mon(50, 100)) == 60, "an awake target takes the move's own power", slap(mon(50, 100)), 60)
ok(slap(mon(50, 100, "SLP")) == 120, "a sleeping target takes double", slap(mon(50, 100, "SLP")), 120)
-- THE SUBSTITUTE BRANCH, which skips the doubling as well as the wake.
ok(slap(mon(50, 100, "SLP"), 20) == 60,
   "a sleeping target BEHIND a substitute takes neither", slap(mon(50, 100, "SLP"), 20), 60)

local record = MoveEffects.full.DOUBLE_POWER_HEAL_SLEEP
local function afterHit(m, sub, dealt)
  local target = battler(100, m, sub)
  said = {}
  record.afterDamage(ctxFor(WS, battler(100, mon(10, 10)), target), dealt)
  return target
end
local woken = afterHit(mon(50, 100, "SLP"), nil, 30)
ok(woken.mon.status == nil, "...and a landed hit wakes it", tostring(woken.mon.status), "nil")
ok(#said == 1 and said[1]:find("woke up", 1, true) ~= nil,
   "...and says so", said[1] or "nothing said", "a wake message")
-- ON HIT, so a move that dealt nothing leaves the sleep alone.
ok(afterHit(mon(50, 100, "SLP"), nil, 0).mon.status == "SLP",
   "a hit that dealt nothing leaves it asleep",
   tostring(afterHit(mon(50, 100, "SLP"), nil, 0).mon.status), "SLP")
ok(afterHit(mon(50, 100, "SLP"), 20, 30).mon.status == "SLP",
   "a substitute leaves it asleep too",
   tostring(afterHit(mon(50, 100, "SLP"), 20, 30).mon.status), "SLP")
-- A CONTROL: an awake target must not acquire a message. Without this, an
-- afterDamage that said "woke up!" unconditionally would pass everything above.
local awake = afterHit(mon(50, 100), nil, 30)
ok(#said == 0, "...and an awake target is not told it woke up",
   said[1] or "nothing said", "nothing said")

-- ---------------------------------------------------------------------------
if PP then
  section("6. the four effect scripts still say what this was written from")
  -- Re-read from pret rather than trusting the comments above. The scripts are
  -- named by effect id, so there is no matching to get wrong.
  local function script(id)
    local f = io.open(("%s/res/battle/scripts/effects/effect_script_%04d.s"):format(PP, id), "rb")
    if not f then return nil end
    local t = f:read("*a"); f:close(); return t
  end
  local s219 = script(219)
  ok(s219 ~= nil, "effect_script_0219.s is present", s219 ~= nil, true)
  ok(s219 and s219:find("CalcGyroBallPower", 1, true) ~= nil,
     "...and Gyro Ball still calls CalcGyroBallPower",
     s219 and s219:find("CalcGyroBallPower", 1, true) ~= nil, true)
  local s237 = script(237)
  ok(s237 and s237:find("CalcWringOutPower", 1, true) ~= nil,
     "Wring Out still calls CalcWringOutPower",
     s237 and s237:find("CalcWringOutPower", 1, true) ~= nil, true)
  local s221 = script(221)
  -- THE HALVING, THE `>` AND THE TWO MULTIPLIERS -- the three things Brine's
  -- boundary case rests on.
  ok(s221 and s221:find("OPCODE_DIV", 1, true) and s221:find("OPCODE_GT", 1, true),
     "Brine still halves the maximum and compares with >",
     s221 and (s221:find("OPCODE_DIV", 1, true) ~= nil
               and s221:find("OPCODE_GT", 1, true) ~= nil), true)
  ok(s221 and s221:find("BTLVAR_POWER_MULTI, 20", 1, true) ~= nil
     and s221:find("BTLVAR_POWER_MULTI, 10", 1, true) ~= nil,
     "...and still sets the multiplier to 20 and 10 (tenths)",
     s221 and (s221:find("BTLVAR_POWER_MULTI, 20", 1, true) ~= nil), true)
  local s217 = script(217)
  ok(s217 and s217:find("CheckSubstitute", 1, true) ~= nil,
     "Wake-Up Slap still checks for a substitute FIRST",
     s217 and s217:find("CheckSubstitute", 1, true) ~= nil, true)
  ok(s217 and s217:find("MON_CONDITION_SLEEP", 1, true) ~= nil,
     "...and still tests for sleep",
     s217 and s217:find("MON_CONDITION_SLEEP", 1, true) ~= nil, true)
  ok(s217 and s217:find("HEAL_TARGET_SLEEP", 1, true) ~= nil,
     "...and still heals the sleep as an ON_HIT side effect",
     s217 and s217:find("HEAL_TARGET_SLEEP", 1, true) ~= nil, true)
  -- AND THE SUBSTITUTE JUMP GOES PAST BOTH. In the script the substitute jumps
  -- to the label that the not-asleep arm also reaches, which is why one branch
  -- skips the doubling and the wake together.
  local subTarget = s217 and s217:match("CheckSubstitute%s+BTLSCR_DEFENDER,%s*(_%d+)")
  local gotoTarget = s217 and s217:match("POWER_MULTI,%s*10%s*\n%s*GoTo%s+(_%d+)")
  ok(subTarget ~= nil and subTarget == gotoTarget,
     "...and the substitute jumps where the awake arm goes, skipping both",
     ("substitute -> %s, awake -> %s"):format(tostring(subTarget), tostring(gotoTarget)),
     "the same label")
else
  io.write("\n   (no pokeplatinum dir given -- section 6 skipped)\n")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
