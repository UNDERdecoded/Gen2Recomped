-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_moveeffect_check.lua <rom> <pokeplatinum dir>
--
-- WHAT A SINNOH MOVE DOES, checked against two sources that do not know about
-- each other.
--
-- The bug this exists for: `pl_waza_tbl` gives each move an effect NUMBER, the
-- battle engine dispatches on a NAME, and the Gen 4 import wrote the number --
-- so `BattleState:effectRecord` looked a Gen 4 number up among Kanto's names,
-- found nothing, and every Sinnoh move that was not a plain hit printed
-- "But, it failed!". Leer never lowered Defence and Growl never lowered Attack.
--
-- THE TABLE IS DERIVED, NOT TYPED, and this checks the derivation rather than
-- the literals:
--   (1) the cartridge's move table joined to pokeplatinum's `res/moves/*/
--       data.json` BY MOVE NAME -- and the effect-CHANCE byte agreeing on every
--       row, which is a second field confirming the first field's join;
--   (2) Hoenn's own `GEN3_MOVE_EFFECTS`, read out of RomExtractorGen3.lua as
--       source, agreeing with pret on every shared id.
local romPath = arg and arg[1]
local pretDir = arg and arg[2]
if not (romPath and pretDir) then
  io.stderr:write("usage: texlua tools/gen4_moveeffect_check.lua <rom> <pokeplatinum dir>\n")
  os.exit(2)
end
local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local NdsRom = require("src.import.NdsRom")
local Narc   = require("src.import.NarcArchive")
local Moves  = require("src.import.Gen4Moves")
local Text   = require("src.import.Gen4Text")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then
    io.write(("  ok    %-58s %s\n"):format(what, tostring(got)))
  else
    fails = fails + 1
    io.write(("  FAIL  %-58s got %s, expected %s\n")
      :format(what, tostring(got), tostring(want)))
  end
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ---------------------------------------------------------------------------
-- 1: THE CARTRIDGE
-- ---------------------------------------------------------------------------
io.write("the cartridge's own move table\n")
local rom = assert(NdsRom.open(romPath))
local arc = assert(Narc.parse(assert(rom:read("/poketool/waza/pl_waza_tbl.narc"))))
local msg = assert(Narc.parse(assert(rom:read("/msgdata/pl_msg.narc"))))
local bank = assert(Text.bank(msg:get(Moves.NAME_BANK)))
local all = Moves.all(arc, bank, Text)
ok(arc.count == 471, "pl_waza_tbl holds this many members", arc.count, 471)
ok(count(all) == 471, "...and every one parses", count(all), 471)

-- ---------------------------------------------------------------------------
-- 2: THE JOIN TO POKEPLATINUM, which is what licenses the whole table.
-- ---------------------------------------------------------------------------
io.write("\nthe join to pokeplatinum, by move name\n")
local function norm(s)
  return (tostring(s or ""):lower():gsub("[^a-z0-9]", ""))
end
-- `res/moves/<dir>/data.json` -- read with a pattern rather than a JSON parser,
-- because the two fields wanted are both single-line string values.
local pret = {}
local dirs = 0
local list = io.popen('ls "' .. pretDir .. '/res/moves" 2>/dev/null')
for dir in (list and list:lines() or function() return nil end) do
  local f = io.open(pretDir .. "/res/moves/" .. dir .. "/data.json", "rb")
  if f then
    local body = f:read("*a"); f:close()
    dirs = dirs + 1
    local name = body:match('"name"%s*:%s*"([^"]*)"')
    local eff  = body:match('"type"%s*:%s*"(BATTLE_EFFECT_[A-Z0-9_]+)"')
    local ch   = tonumber(body:match('"chance"%s*:%s*(%-?%d+)') or "")
    if name and eff then pret[norm(name)] = { effect = eff, chance = ch or 0 } end
  end
end
if list then list:close() end
ok(dirs >= 460, "pokeplatinum has one data.json per move", dirs, "at least 460")
ok(count(pret) >= 460, "...each naming an effect", count(pret), "at least 460")

local joined, unmatched, chanceDiff = 0, {}, 0
local byId = {}
for id, m in pairs(all) do
  local p = pret[norm(m.name)]
  if p then
    joined = joined + 1
    if p.chance ~= m.effectChance then chanceDiff = chanceDiff + 1 end
    byId[m.gen4Effect] = byId[m.gen4Effect] or {}
    byId[m.gen4Effect][p.effect] = (byId[m.gen4Effect][p.effect] or 0) + 1
  elseif m.name and m.name ~= "-" then
    unmatched[#unmatched + 1] = m.name
  end
end
ok(joined == 471, "every cartridge row joins to a pret move by name", joined, 471)
ok(#unmatched == 0, "...with nothing unmatched",
   #unmatched == 0 and "none" or table.concat(unmatched, ","), "none")
-- THE SECOND FIELD. A join on names alone could be right by luck on a handful;
-- the effect-CHANCE byte agreeing on all 471 is an independent column saying the
-- same pairing.
ok(chanceDiff == 0, "...and the effect-chance byte agrees on every one",
   chanceDiff, 0)
-- AND THE ID DETERMINES THE EFFECT. If one id carried two pret names the whole
-- table would be a guess.
local ambiguous = 0
for _, names in pairs(byId) do if count(names) > 1 then ambiguous = ambiguous + 1 end end
ok(count(byId) == 257, "the cartridge uses this many distinct effect ids",
   count(byId), 257)
ok(ambiguous == 0, "...and not one of them carries two pret names", ambiguous, 0)

-- ---------------------------------------------------------------------------
-- 3: HOENN'S TABLE, read as a claim about NUMBERING.
-- ---------------------------------------------------------------------------
io.write("\nGen 4 inherited Gen 3's effect numbering\n")
local g3 = {}
do
  local f = io.open((root ~= "" and root or "./") .. "../src/import/RomExtractorGen3.lua", "rb")
  local src = f and f:read("*a")
  if f then f:close() end
  ok(src ~= nil, "RomExtractorGen3.lua is readable from here", "read", "read")
  if src then
    local at = src:find("local GEN3_MOVE_EFFECTS = {", 1, true)
    local stop = at and src:find("\n}", at, true)
    ok(at ~= nil and stop ~= nil, "...and carries GEN3_MOVE_EFFECTS", "found", "found")
    if at and stop then
      for id, first in src:sub(at, stop):gmatch('%[(%d+)%]%s*=%s*{%s*"([A-Z0-9_]+)"') do
        g3[tonumber(id)] = first
      end
    end
  end
end
ok(count(g3) == 198, "Hoenn's table covers this many ids", count(g3), 198)

-- THE AGREEMENT, and it is asserted as a count of DISAGREEMENTS rather than of
-- matches -- a matcher that accepted everything would pass the other way round.
-- Hoenn names an effect after its MOVE and pret after its BEHAVIOUR, so the test
-- cannot be string equality: it is that the port's own table (which takes Hoenn's
-- name for every shared id) covers exactly the ids pret says exist.
local shared, portHasHoenns = 0, 0
for id, name in pairs(g3) do
  if byId[id] then
    shared = shared + 1
    local row = Moves.EFFECTS[id]
    if row and row[1] == name then portHasHoenns = portHasHoenns + 1 end
  end
end
ok(shared == 195, "this many of Gen 4's ids are in Hoenn's table", shared, 195)
ok(portHasHoenns == shared,
   "...and the port takes Hoenn's own name for every one of them",
   ("%d of %d"):format(portHasHoenns, shared), shared)
-- ...AND NOTHING WAS INVENTED. An id the port names that Hoenn does not is a
-- Gen 4-only naming decision, and the rule for those is the port's own: a name
-- claims `MoveEffects` has a record, while an id with no name logs itself
-- through `missing()` instead. So the test is that EVERY such id is IMPLEMENTED.
--
-- THIS USED TO BE A HARDCODED LIST of five ids -- 255, 256, 261, 263, 272 --
-- which is the hardcoded twin of a fact in `Gen4Moves`, and it went stale the
-- moment a sixth arrived: four implemented effects were reported as inventions
-- while the invariant actually worth having (a name means a handler) was never
-- being checked at all. Derived, it holds for nine and fails on a name with no
-- handler, which is the thing worth preventing.
local okME, Effects = pcall(require, "src.battle.MoveEffects")
ok(okME and type(Effects) == "table", "src.battle.MoveEffects did not load",
   tostring(Effects), "a table")
local gen4Own, unimplemented = {}, {}
for id, row in pairs(Moves.EFFECTS) do
  if not g3[id] then
    gen4Own[#gen4Own + 1] = id
    local name = row and row[1]
    local has = okME and name and (Effects.full[name] or Effects.primary[name]
                                   or Effects.secondary[name] or Effects.special[name])
    if not has then
      unimplemented[#unimplemented + 1] = ("%d (%s)"):format(id, tostring(name))
    end
  end
end
table.sort(gen4Own)
ok(#unimplemented == 0,
   "...and every Gen 4-only id the port names is implemented",
   #unimplemented == 0 and "all" or table.concat(unimplemented, ", "), "all")
-- The count is pinned so a tenth has to be acknowledged here, but it is the
-- assertion above that makes adding one safe rather than merely noticed.
ok(#gen4Own == 9,
   "...and there are nine: five semi-invulnerable/bind rows, four dynamic-power",
   ("%d (%s)"):format(#gen4Own, table.concat(gen4Own, ",")), 9)
ok(count(Moves.EFFECTS) == 204, "so the table is Hoenn's 195 plus nine",
   count(Moves.EFFECTS), 204)

-- THE TWO PLACES THE SOURCES DIFFER, asserted so a future reader does not have
-- to take the comment's word for either.
do
  local magnitude, psywave = nil, nil
  for id, m in pairs(all) do
    if norm(m.name) == "magnitude" then magnitude = m end
    if norm(m.name) == "psywave" then psywave = m end
  end
  ok(magnitude and magnitude.gen4Effect == 126,
     "id 126 is Magnitude's, whatever pret calls it",
     magnitude and magnitude.gen4Effect, 126)
  ok(psywave and psywave.gen4Effect ~= 126,
     "...and Psywave's is a different id entirely",
     psywave and psywave.gen4Effect, "not 126")
  local users126 = 0
  for _, m in pairs(all) do if m.gen4Effect == 126 then users126 = users126 + 1 end end
  ok(users126 == 1, "...and exactly one move uses it", users126, 1)
  local prio = 0
  for _, m in pairs(all) do if m.gen4Effect == 103 then prio = prio + 1 end end
  ok(prio == 8, "id 103 is the eight priority-1 moves", prio, 8)
end

-- ---------------------------------------------------------------------------
-- 4: WHAT THE PORT NOW HANDS THE BATTLE
-- ---------------------------------------------------------------------------
io.write("\nwhat the battle receives\n")
local named, numbered, crit = 0, 0, 0
for _, m in pairs(all) do
  if type(m.effect) == "string" then named = named + 1 else numbered = numbered + 1 end
  if m.highCrit then crit = crit + 1 end
end
-- 417 and 54, not 412 and 59: Gyro Ball, Wring Out, Crush Grip, Brine and
-- Wake-Up Slap moved across when their handlers were written.
ok(named == 417, "moves carrying an effect NAME", named, 417)
ok(numbered == 54, "...and moves whose id has no name, left as numbers", numbered, 54)
-- THE SUM, because two pins that move together could both be bumped wrongly
-- and still agree with each other.
ok(named + numbered == 471, "...and every move is in exactly one of the two",
   named + numbered, 471)
-- A NUMBER MUST STILL SAY WHAT IT IS, or the gap report is a column of integers.
local labelled = 0
for _, m in pairs(all) do
  if type(m.effect) == "number" and m.gen4EffectName then labelled = labelled + 1 end
end
ok(labelled == numbered, "...every one of which carries pret's name as a label",
   ("%d of %d"):format(labelled, numbered), numbered)

-- THE FOUR THE REPORT WAS ABOUT, by name and not by id.
local want = {
  Leer = "DEFENSE_DOWN1_EFFECT", Growl = "ATTACK_DOWN1_EFFECT",
  Thunderbolt = "PARALYZE_SIDE_EFFECT1", Thunder = "THUNDER_EFFECT",
  Dig = "FLY_EFFECT", Dive = "FLY_EFFECT", Bounce = "FLY_EFFECT",
  Fly = "FLY_EFFECT", Whirlpool = "TRAPPING_EFFECT",
  ["Karate Chop"] = "HIGH_CRITICAL_EFFECT",
}
local wrong = {}
for _, m in pairs(all) do
  local w = want[m.name]
  if w and m.effect ~= w then
    wrong[#wrong + 1] = ("%s=%s"):format(m.name, tostring(m.effect))
  end
end
ok(#wrong == 0, "the ten named moves land on the effect they should",
   #wrong == 0 and "all ten" or table.concat(wrong, " "), "all ten")

-- THE ODDS SPLIT IS RESOLVED BY THE CARTRIDGE'S OWN BYTE, both sides of it.
do
  local lo, hi = nil, nil
  for _, m in pairs(all) do
    if m.name == "Thunderbolt" then lo = m end
    if m.name == "Body Slam" then hi = m end
  end
  ok(lo and lo.effectChance == 10 and lo.effect == "PARALYZE_SIDE_EFFECT1",
     "a one-in-ten paralyse takes the first name",
     lo and ("%d -> %s"):format(lo.effectChance, tostring(lo.effect)), "10 -> ..._1")
  ok(hi and hi.effectChance > 10 and hi.effect == "PARALYZE_SIDE_EFFECT2",
     "...and a three-in-ten takes the second",
     hi and ("%d -> %s"):format(hi.effectChance, tostring(hi.effect)), ">10 -> ..._2")
end

-- THE CRIT RATE, DERIVED AND THEN CHECKED AGAINST HOENN'S HAND-WRITTEN THREE.
do
  local ids = {}
  for id in pairs(Moves.HIGH_CRIT) do ids[#ids + 1] = id end
  table.sort(ids)
  ok(table.concat(ids, ",") == "43,200,209",
     "the three high-crit ids are the three Hoenn hardcodes",
     table.concat(ids, ","), "43,200,209")
  ok(crit == 17, "...and this many Sinnoh moves raise the crit rate", crit, 17)
  -- AND A NAMED ONE EACH SIDE OF THE LIST, because a count passes a table that
  -- happens to total seventeen.
  local ok43, ok209 = false, false
  for _, m in pairs(all) do
    if m.name == "Night Slash" and m.highCrit then ok43 = true end
    if m.name == "Cross Poison" and m.highCrit then ok209 = true end
  end
  ok(ok43 and ok209, "...including Night Slash and Cross Poison",
     tostring(ok43) .. "/" .. tostring(ok209), "true/true")
  -- THE CONTROL: a plain hit must NOT carry it.
  local plain = false
  for _, m in pairs(all) do if m.name == "Pound" then plain = m.highCrit end end
  ok(not plain, "...and Pound does not", tostring(plain), "nil")
end

-- ---------------------------------------------------------------------------
-- 5: THE OTHER THREE CARTRIDGES ARE UNTOUCHED
-- ---------------------------------------------------------------------------
io.write("\nand Kanto, Johto and Hoenn are untouched\n")
do
  local hits = {}
  local p = io.popen('grep -rl "Gen4Moves" "' .. (root ~= "" and root or "./")
                     .. '../src" 2>/dev/null')
  for line in (p and p:lines() or function() return nil end) do
    -- CASE-INSENSITIVE, because the Gen 4 ruleset's own file is
    -- `rulesets/gen4_platinum.lua` and a match on "Gen4" alone reported it as a
    -- Kanto file requiring a Sinnoh module.
    if not line:lower():match("gen4") then hits[#hits + 1] = line end
  end
  if p then p:close() end
  ok(#hits == 0, "nothing but Gen 4 code requires Gen4Moves",
     #hits == 0 and "none" or table.concat(hits, " "), "none")
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
