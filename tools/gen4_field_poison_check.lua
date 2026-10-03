-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FIELD POISON IN SINNOH CANNOT FAINT A POKEMON, AND THIS PORT WAS KILLING THEM.
--
-- `Pokemon_DoPoisonDamage` (pokeplatinum src/unk_02054884.c), entire:
--
--     if (Pokemon_CanBattle(mon) && poisoned) {
--         u32 hp = HP(mon);
--         if (hp > 1) { hp--; }            <-- the whole rule
--         SetHP(mon, hp);
--         if (hp == 1) {
--             numFainted++;
--             UpdateFriendship(FRIENDSHIP_EVENT_POISON_SURVIVE);
--         }
--         numPoisoned++;
--     }
--
-- `if (hp > 1) hp--` means field poison walks a Pokemon down to 1 HP and stops.
-- The counter called `numFainted` is a misnomer -- it counts mons that REACHED
-- 1 -- and the friendship event is named POISON_SURVIVE.
--
-- The other half is the script: FLDPSN_FAINTED hands control to common script 3,
-- which loops `SurvivePoison` over the party, and `Pokemon_TrySurvivePoison` is
-- "if poisoned and HP == 1, clear the status and return TRUE", after which the
-- box says "<MON> survived the poisoning!".
--
-- `OverworldState:applyFieldPoison` was written from Gen 2's
-- `ApplyOutOfBattlePoisonDamage`, where poison DOES kill, and applied that to
-- every cartridge. In Sinnoh that silently cost the player Pokemon and half
-- their money for something the real game cannot do. A rule that DIFFERS rather
-- than a feature that is missing -- nothing errors and nothing logs.
--
-- Run:  texlua tools/gen4_field_poison_check.lua [pokeplatinum dir]
--
-- Needs nothing but the repository; pokeplatinum re-derives the rule and the
-- deltas from source rather than trusting this file's transcription of them.

package.path = "./?.lua;" .. package.path

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = { getWidth = function() return 256 end, getHeight = function() return 192 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local PP = arg and arg[1]
local fails, checks, reports = 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

-- ---------------------------------------------------------------------------
section("1. the friendship penalty, which the event's NAME gets wrong")
local Evolution = require("src.pokemon.Evolution")
-- FRIENDSHIP_EVENT_POISON_SURVIVE is { -5, -5, -10 } over bands 100 / 200.
-- The name says survive; the numbers say the Pokemon minded being carried
-- around poisoned. Asserting the SIGN as well as the size, because "survive"
-- invites exactly the wrong guess and this check is the record of it.
local function after(h, reason)
  local mon = { happiness = h }
  Evolution.changeHappiness(mon, reason)
  return mon.happiness
end
ok(after(50, "POISON_SURVIVE") == 45,
   "low band: 50 -> %s, expected 45 (-5)", tostring(after(50, "POISON_SURVIVE")))
ok(after(150, "POISON_SURVIVE") == 145,
   "mid band: 150 -> %s, expected 145 (-5)", tostring(after(150, "POISON_SURVIVE")))
ok(after(220, "POISON_SURVIVE") == 210,
   "high band: 220 -> %s, expected 210 (-10)", tostring(after(220, "POISON_SURVIVE")))
-- The band edges, because 100 and 200 are the cartridge's boundaries and an
-- off-by-one there is invisible in the middle of a band.
ok(after(99, "POISON_SURVIVE") == 94, "99 is the low band (-5)")
ok(after(100, "POISON_SURVIVE") == 95, "100 is the MIDDLE band (-5), not the low one")
ok(after(199, "POISON_SURVIVE") == 194, "199 is the middle band (-5)")
ok(after(200, "POISON_SURVIVE") == 190, "200 is the HIGH band (-10), not the middle one")
ok(after(3, "POISON_SURVIVE") == 0, "it clamps at 0 rather than going negative")
-- THE FINDING, asserted: Gen 4 did not change the penalty, only when it fires.
-- Gen 2's row is in a file-local table, so it is read from the source rather
-- than required -- and the MATCH IS ASSERTED, not just its contents. A pattern
-- that stopped matching would otherwise skip the comparison and report clean,
-- which is the failure mode this suite keeps finding in itself.
local pikachu = slurp("src/world/PikachuFollower.lua") or ""
local pa, pb, pc = pikachu:match("PSNFNT%s*=%s*{%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)")
ok(pa ~= nil,
   "could not find Gen 2's PSNFNT row in PikachuFollower.lua -- the comparison "
   .. "below did not happen, which is not the same as passing")
if pa then
  io.write(("   Gen 2 PSNFNT: %s, %s, %s   Gen 4 POISON_SURVIVE: -5, -5, -10\n")
           :format(pa, pb, pc))
  ok(tonumber(pa) == -5 and tonumber(pb) == -5 and tonumber(pc) == -10,
     "Gen 2's PIKAHAPPY_PSNFNT is {%s, %s, %s} and Gen 4's POISON_SURVIVE is "
     .. "{-5, -5, -10}; the two being IDENTICAL is the finding -- Gen 4 changed "
     .. "when the penalty fires, not what it is. If these have diverged, one of "
     .. "the two was transcribed wrong.", pa, pb, pc)
end
-- A mon with no happiness byte (Gen 1) must not gain one.
local gen1 = { }
Evolution.changeHappiness(gen1, "POISON_SURVIVE")
ok(gen1.happiness == nil, "a Gen 1 mon gained a happiness byte it does not have")

-- ---------------------------------------------------------------------------
section("2. `survivepoison`, every arm of it")
local Gen4Commands = require("src.script.Gen4Commands")
local Commands = require("src.script.Commands")
local VAR = 0x4000
local function trySurvive(status, hp)
  local ctx = { save = { gen4Vars = {}, party = { { status = status, hp = hp } } } }
  Commands.g4_survive_poison(ctx, VAR, 0)
  return ctx.save.gen4Vars[VAR], ctx.save.party[1].status
end
local v, st = trySurvive("PSN", 1)
ok(v == 1 and st == nil, "poisoned at 1 HP: got %s/%s, expected 1 and cured",
   tostring(v), tostring(st))
v, st = trySurvive("TOX", 1)
ok(v == 1 and st == nil,
   "BADLY poisoned at 1 HP: got %s/%s, expected 1 and cured -- the cartridge's "
   .. "test is (MON_CONDITION_TOXIC | MON_CONDITION_POISON), not poison alone",
   tostring(v), tostring(st))
v, st = trySurvive("PSN", 2)
ok(v == 0 and st == "PSN",
   "poisoned at 2 HP: got %s/%s, expected 0 and still poisoned -- the cartridge "
   .. "compares HP to the literal 1", tostring(v), tostring(st))
v, st = trySurvive("PSN", 0)
ok(v == 0 and st == "PSN",
   "a fainted poisoned mon: got %s/%s, expected 0 and untouched -- 0 is not 1, "
   .. "and `<= 1` would cure corpses", tostring(v), tostring(st))
v, st = trySurvive(nil, 1)
ok(v == 0 and st == nil, "an unpoisoned mon at 1 HP: got %s, expected 0", tostring(v))
v, st = trySurvive("BRN", 1)
ok(v == 0 and st == "BRN",
   "a BURNED mon at 1 HP: got %s/%s, expected 0 and still burned", tostring(v), tostring(st))
-- An empty slot must not raise.
do
  local ctx = { save = { gen4Vars = {}, party = {} } }
  local okRun = pcall(Commands.g4_survive_poison, ctx, VAR, 3)
  ok(okRun, "`survivepoison` raised on an empty party slot")
  ok(ctx.save.gen4Vars[VAR] == 0,
     "an empty slot answered %s, expected 0", tostring(ctx.save.gen4Vars[VAR]))
end

-- ---------------------------------------------------------------------------
section("3. the overworld rule, and that the other generations keep theirs")
local owc = slurp("src/world/OverworldController.lua") or ""
ok(#owc > 0, "src/world/OverworldController.lua did not open")
local body = owc:match("function OverworldState:applyFieldPoison%(%).-\nend\n")
            or owc:match("function OverworldState:applyFieldPoison%(%).-\r\nend\r\n")
ok(body ~= nil, "could not find `applyFieldPoison` to read")
if body then
  ok(body:find("GameVersion%.isGen4%(%)") ~= nil,
     "the rule is not gated on the cartridge, so one generation's poison rule is "
     .. "being applied to all of them -- which is the fault this check exists for")
  ok(body:find("mon%.hp > 1") ~= nil,
     "nothing in `applyFieldPoison` tests `hp > 1`; that single comparison IS the "
     .. "Gen 4 rule")
  ok(body:find("mon%.hp = 1") ~= nil,
     "nothing clamps HP back up to 1, so Sinnoh poison can still reach 0")
  ok(body:find("POISON_SURVIVE") ~= nil,
     "the survive friendship event is not fired")
  -- AND THE OTHER GENERATIONS MUST STILL FAINT. This is the half that protects
  -- Crystal, Gold/Silver and Prism: the Gen 1/2 path is `mon.hp = 0` plus the
  -- PSNFNT penalty, and a refactor that unified the two branches would take
  -- their rule away silently.
  ok(body:find("mon%.hp = 0") ~= nil,
     "the non-Gen-4 path no longer sets HP to 0 -- Gen 1, Gen 2 and the Crystal "
     .. "hacks must still faint from field poison")
  ok(body:find("PSNFNT") ~= nil,
     "the non-Gen-4 path no longer fires PIKAHAPPY_PSNFNT")
  ok(body:find('"TOX"') ~= nil,
     "badly poisoned mons are not considered; the cartridge's test is "
     .. "(TOXIC | POISON)")
  -- The survived line has to be printed by something.
  ok(owc:find("survived") ~= nil, "nothing prints the survived-the-poisoning line")
end
-- The hatch extraction: one spelling, two doors.
ok(owc:find("function OverworldState:hatchEgg") ~= nil,
   "`hatchEgg` was not extracted, so the script command and `stepEggs` would "
   .. "each need their own copy of the hatch")
ok(owc:find("return self:hatchEgg%(hatched%)") ~= nil,
   "`stepEggs` does not call `hatchEgg`, so the two doors have already drifted")
local stepBody = owc:match("function OverworldState:stepEggs%(%).-hatchEgg%(hatched%)")
ok(stepBody ~= nil and stepBody:find("metLevel") == nil,
   "`stepEggs` still contains the hatch body; the extraction left a copy behind")

-- ---------------------------------------------------------------------------
if PP then
  section("4. the rule and the deltas, re-derived from pokeplatinum")
  local dmg = slurp(PP .. "/src/unk_02054884.c")
  local mon = slurp(PP .. "/src/pokemon.c")
  local limits = slurp(PP .. "/include/constants/pokemon.h")
  if not (dmg and mon and limits) then
    report("pokeplatinum sources not found under %s -- section 4 skipped", PP)
  else
    -- THE RULE, verbatim. If pret ever changes this line, every number in this
    -- file is suspect and should be re-read rather than trusted.
    ok(dmg:find("if %(hp > 1%) {") ~= nil,
       "`if (hp > 1) {` is no longer in Pokemon_DoPoisonDamage -- the clamp this "
       .. "whole check is built on has changed")
    ok(dmg:find("FRIENDSHIP_EVENT_POISON_SURVIVE") ~= nil,
       "Pokemon_DoPoisonDamage no longer fires POISON_SURVIVE")
    ok(dmg:find("MON_CONDITION_TOXIC | MON_CONDITION_POISON") ~= nil,
       "the poisoned test is no longer (TOXIC | POISON)")
    -- `Pokemon_TrySurvivePoison`: the == 1 is the part a reader would soften.
    local sv = dmg:match("BOOL Pokemon_TrySurvivePoison.-\n}")
    ok(sv ~= nil, "could not find Pokemon_TrySurvivePoison")
    if sv then
      ok(sv:find("MON_DATA_HP, NULL%) == 1") ~= nil,
         "Pokemon_TrySurvivePoison no longer compares HP to exactly 1")
    end
    -- THE DELTAS, from the table rather than from this file's comment.
    local row = mon:match("%[FRIENDSHIP_EVENT_POISON_SURVIVE%]%s*=%s*{([^}]*)}")
    ok(row ~= nil, "could not find the POISON_SURVIVE row in sFriendshipChangeTable")
    if row then
      local a, b, c = row:match("(-?%d+)%s*,%s*(-?%d+)%s*,%s*(-?%d+)")
      io.write(("   pret's POISON_SURVIVE deltas: %s, %s, %s\n"):format(a, b, c))
      ok(tonumber(a) == -5 and tonumber(b) == -5 and tonumber(c) == -10,
         "pret's deltas are {%s, %s, %s}; this port uses {-5, -5, -10}",
         tostring(a), tostring(b), tostring(c))
    end
    ok(limits:find("LOW_FRIENDSHIP_LIMIT%s+100") ~= nil,
       "LOW_FRIENDSHIP_LIMIT is no longer 100, so the band split is wrong")
    ok(limits:find("MED_FRIENDSHIP_LIMIT%s+200") ~= nil,
       "MED_FRIENDSHIP_LIMIT is no longer 200, so the band split is wrong")
  end
else
  io.write("\n   (no pokeplatinum dir given -- section 4 skipped)\n")
end

io.write(("\n%d checks, %d failed, %d reported\n"):format(checks, fails, reports))
os.exit(fails == 0 and 0 or 1)
