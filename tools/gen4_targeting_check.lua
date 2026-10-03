-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHO A SINNOH MOVE HITS.
--
-- `src/battle/Targeting.lua` decides this for every generation, and it was
-- written for Hoenn: it reads `move.target`, the byte at offset 6 of
-- gBattleMoves' 12-byte record. SINNOH HAS NO SUCH FIELD. Platinum's move
-- record carries `range` instead -- 471 of them in the cache and not one
-- `target` -- so before this was wired, `kindOf` read nil for all 467 Sinnoh
-- moves and every one of them came out SELECTED.
--
-- In a single battle that is invisible: there is one foe, SELECTED means "that
-- one", and the effect records do the rest. In a double it is wrong for about
-- a hundred and thirty moves at once -- EXPLOSION sparing your partner,
-- REFLECT asking you to pick a victim, SPIKES aimed at a Pokemon instead of a
-- side, THRASH not locking on.
--
-- AND THE TWO SPELLINGS OVERLAP, which is the dangerous part and the reason
-- this file exists. Both fields are small bitmasks and they agree on 0 and on
-- 0x10, so `target = range` looks correct and is not:
--
--     0x02  Sinnoh RANDOM_OPPONENT     Hoenn USER_OR_SELECTED
--     0x04  Sinnoh ADJACENT_OPPONENTS  Hoenn RANDOM
--     0x08  Sinnoh ALL_ADJACENT        Hoenn BOTH (drops your partner)
--     0x20  Sinnoh USER_SIDE           Hoenn FOES_AND_ALLY (hits three)
--     0x40  Sinnoh FIELD               Hoenn OPPONENTS_FIELD
--
-- This is THE recurring fault in this port -- one concept spelled two ways in
-- two files that never meet -- caught before it shipped rather than after. So
-- section 3 asserts the tables are NOT interchangeable: if someone collapses
-- the translation into an assignment, five masks start lying and this fails.
--
-- Run:  texlua tools/gen4_targeting_check.lua <cache dir> [pokeplatinum dir]
--
-- With pokeplatinum, every mask is re-derived from pret's own per-move
-- `res/moves/<move>/data.json` and `generated/move_ranges.txt`; without it,
-- the cache and the engine are still checked against each other.

package.path = "./?.lua;" .. package.path

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = { getWidth = function() return 256 end, getHeight = function() return 192 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local CACHE = arg and arg[1]
local PP = arg and arg[2]
if not CACHE then
  io.write("usage: texlua tools/gen4_targeting_check.lua <cache dir> [pokeplatinum dir]\n")
  os.exit(2)
end

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local Targeting = require("src.battle.Targeting")

-- The cache's moves, by name and by range.
local chunk, why = loadfile(CACHE .. "/moves.lua")
ok(chunk ~= nil, "%s/moves.lua did not load: %s", CACHE, tostring(why))
if not chunk then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end
local moves = chunk()
ok(type(moves) == "table", "moves.lua did not return a table")

local byName, withRange, withTarget, total = {}, 0, 0, 0
for _, m in pairs(moves) do
  if type(m) == "table" and m.name then
    total = total + 1
    byName[m.name] = m
    if m.range ~= nil then withRange = withRange + 1 end
    if m.target ~= nil then withTarget = withTarget + 1 end
  end
end

section("1. Sinnoh carries `range` and no `target`, which is why this is needed")
ok(total >= 467, "only %d moves in the cache (was 468)", total)
ok(withRange >= 467, "only %d move(s) carry a range (was 468)", withRange)
-- THE PREMISE. If Sinnoh ever grew a `target` field, `kindOf` would take it
-- first and this whole translation would be bypassed -- silently, because
-- `target` wins by design. That must be a failure, not a surprise.
ok(withTarget == 0,
   "%d Sinnoh move(s) now carry a `target` field; `kindOf` takes that FIRST, so "
   .. "the range translation is being bypassed -- decide which field is the "
   .. "source of truth before shipping both", withTarget)

section("2. every range in the cache is translated, none falls to the default")
local seen, untranslated = {}, {}
for name, m in pairs(byName) do
  local r = tonumber(m.range)
  if r then
    seen[r] = (seen[r] or 0) + 1
    if Targeting.GEN4_RANGE[r] == nil then
      untranslated[#untranslated + 1] = ("%s (range %d)"):format(name, r)
    end
  end
end
ok(#untranslated == 0,
   "%d move(s) have a range with no entry in GEN4_RANGE, so they fall to "
   .. "SELECTED without saying so: %s", #untranslated,
   table.concat(untranslated, ", ", 1, math.min(#untranslated, 6)))
-- The buckets, as floors: a cartridge revision may move a move between them,
-- but a bucket EMPTYING means the mask stopped being produced and whatever
-- maps it is now untested.
local WANT = { [0]=335, [1]=11, [2]=4, [4]=24, [8]=8, [16]=62, [32]=8, [64]=10,
               [128]=3, [256]=1, [512]=1, [1024]=1 }
local parts = {}
for mask, n in pairs(WANT) do
  ok((seen[mask] or 0) > 0,
     "no move in the cache has range %d any more, so its translation is untested",
     mask)
  parts[#parts + 1] = ("%d:%d"):format(mask, seen[mask] or 0)
end
table.sort(parts)
io.write("   masks seen -> " .. table.concat(parts, " ") .. "\n")
ok((seen[0] or 0) >= 300, "only %d move(s) are plain single-target (was 335)", seen[0] or 0)
ok((seen[16] or 0) >= 60, "only %d move(s) target the user (was 62)", seen[16] or 0)

section("3. the two encodings are NOT interchangeable")
-- Five masks where `target = range` would be a different move. If the
-- translation is ever collapsed into an assignment, these five start lying.
local COLLIDE = {
  { 0x02, "RANDOM_OPPONENT",    Targeting.RANDOM,          "USER_OR_SELECTED" },
  { 0x04, "ADJACENT_OPPONENTS", Targeting.BOTH,            "RANDOM" },
  { 0x08, "ALL_ADJACENT",       Targeting.FOES_AND_ALLY,   "BOTH" },
  { 0x20, "USER_SIDE",          Targeting.USER,            "FOES_AND_ALLY" },
  { 0x40, "FIELD",              Targeting.USER,            "OPPONENTS_FIELD" },
}
for _, row in ipairs(COLLIDE) do
  local mask, sinnoh, want, hoenn = row[1], row[2], row[3], row[4]
  local got = Targeting.GEN4_RANGE[mask]
  ok(got == want,
     "range 0x%02X (%s) translates to %s, not 0x%02X -- Hoenn's byte reads "
     .. "that mask as %s, which is a different move",
     mask, sinnoh, got and ("0x%02X"):format(got) or "nothing", want, hoenn)
  ok(Targeting.GEN4_RANGE[mask] ~= mask,
     "range 0x%02X (%s) translates to ITSELF, which means the translation has "
     .. "been collapsed into `target = range`; Hoenn reads that mask as %s",
     mask, sinnoh, hoenn)
end
-- ...and the two the tables DO agree on, stated so the five above read as a
-- measurement rather than a selection.
ok(Targeting.GEN4_RANGE[0] == Targeting.SELECTED,
   "range 0 no longer means the ordinary single target")
ok(Targeting.GEN4_RANGE[16] == Targeting.USER,
   "range 16 no longer means the user, which is the one mask both spellings share")

section("4. what each kind actually resolves to, in a double")
-- A FIXTURE RATHER THAN A REAL BATTLE: Targeting asks for exactly four things
-- -- foesOf, partnerOf, isDouble and rng -- so the whole surface can be stood
-- up here and the answers read back as lists.
local function mon() return { mon = { hp = 10 } } end
local user, ally = mon(), mon()
local foeL, foeR = mon(), mon()
user.isPlayer, ally.isPlayer = true, true
local battle = {
  isDouble = function() return true end,
  foesOf = function() return { foeL, foeR } end,
  partnerOf = function(_, who) return who == user and ally or user end,
  rng = function(_, hi) return hi end,
}
local function names(list)
  local out = {}
  for _, b in ipairs(list or {}) do
    out[#out + 1] = (b == user and "user") or (b == ally and "ally")
      or (b == foeL and "foeL") or (b == foeR and "foeR") or "?"
  end
  return table.concat(out, "+")
end
local function resolved(range, chosen)
  return names(Targeting.resolve(battle, user, { range = range }, chosen))
end
ok(resolved(16) == "user", "range 16 resolves to %s, not the user", resolved(16))
-- BOTH FOES AND NOT YOUR PARTNER. BLIZZARD hitting your own Pokemon would be
-- a different game, and the mask it uses is the one Hoenn reads as RANDOM.
ok(resolved(4) == "foeL+foeR",
   "range 4 (BLIZZARD, ROCK SLIDE) resolves to %s, not both foes", resolved(4))
-- AND YOUR PARTNER IS IN EXPLOSION'S BLAST. This is the difference the 0x08
-- vs 0x20 collision would silently erase.
ok(resolved(8) == "foeL+foeR+ally",
   "range 8 (EARTHQUAKE, EXPLOSION) resolves to %s, not the foes AND your ally",
   resolved(8))
ok(resolved(128) == "", "range 128 (SPIKES) resolves to %s; a side is not a Pokemon",
   resolved(128))
ok(resolved(256) == "ally", "range 256 (HELPING HAND) resolves to %s, not your partner",
   resolved(256))
ok(resolved(0, foeR) == "foeR", "range 0 ignored the chosen target and gave %s",
   resolved(0, foeR))
-- HELPING HAND WITH NOBODY THERE IS NO TARGET, not a foe. A single battle must
-- not turn it into an attack.
local solo = {
  isDouble = function() return false end,
  foesOf = function() return { foeL } end,
  partnerOf = function() return nil end,
  rng = function(_, hi) return hi end,
}
ok(names(Targeting.resolve(solo, user, { range = 256 }, foeL)) == "",
   "HELPING HAND with no partner resolved to %s instead of nothing",
   names(Targeting.resolve(solo, user, { range = 256 }, foeL)))

section("5. Hoenn is untouched: `target` still wins")
-- The guard that keeps this change out of Gen 1/2/3. A move carrying both must
-- take `target`, or wiring Sinnoh would have quietly re-aimed Hoenn.
ok(Targeting.kindOf({ target = Targeting.BOTH, range = 16 }) == Targeting.BOTH,
   "a move with both fields took its range instead of its target")
ok(Targeting.kindOf({ target = Targeting.SELECTED, range = 8 }) == Targeting.SELECTED,
   "target 0 lost to range 8; `tonumber(0)` is not nil and must still win")
ok(Targeting.kindOf({}) == Targeting.SELECTED,
   "a move with neither field is no longer SELECTED, which is Gen 1/2's whole path")
ok(Targeting.kindOf({ range = 16 }) == Targeting.USER,
   "a Sinnoh move with only a range no longer translates")

if PP then
  section("6. every mask re-derived from pokeplatinum")
  -- `move_ranges.txt` is the enum in order, so line N is id N, and the cache
  -- stores 1 << (id - 1) with id 0 staying 0. Checked move by move against
  -- pret's own JSON rather than trusting the formula.
  local order = {}
  local f = io.open(PP .. "/generated/move_ranges.txt", "rb")
  ok(f ~= nil, "%s/generated/move_ranges.txt is missing", PP)
  if f then
    for line in f:lines() do
      line = line:gsub("%s+$", "")
      if line ~= "" then order[#order + 1] = line end
    end
    f:close()
    ok(#order >= 17, "the range enum has %d entries, not 17", #order)
    local id = {}
    for i, n in ipairs(order) do id[n] = i - 1 end
    local agree, disagree, missing, bad = 0, 0, 0, {}
    for name, m in pairs(byName) do
      local dir = name:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
      local jf = io.open(PP .. "/res/moves/" .. dir .. "/data.json", "rb")
      if not jf then missing = missing + 1
      else
        local text = jf:read("*a"); jf:close()
        local rname = text:match('"range"%s*:%s*"([A-Z0-9_]+)"')
        local rid = rname and id[rname]
        if not rid then missing = missing + 1
        else
          local want = (rid == 0) and 0 or (2 ^ (rid - 1))
          if tonumber(m.range) == want then agree = agree + 1
          else
            disagree = disagree + 1
            if #bad < 6 then
              bad[#bad + 1] = ("%s: cache %s, pret %s (id %d -> %d)")
                :format(name, tostring(m.range), rname, rid, want)
            end
          end
        end
      end
    end
    io.write(("   %d agree, %d disagree, %d not matched by name\n")
             :format(agree, disagree, missing))
    ok(disagree == 0, "%d move(s) disagree with pret: %s", disagree,
       table.concat(bad, "; "))
    -- A FLOOR ON THE COMPARISON ITSELF: a name-slug change could leave this
    -- section matching three moves and reporting a clean zero.
    ok(agree >= 440, "only %d move(s) were actually compared against pret (was 466)",
       agree)
  end
else
  io.write("\n   (no pokeplatinum dir given -- section 6 skipped)\n")
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
