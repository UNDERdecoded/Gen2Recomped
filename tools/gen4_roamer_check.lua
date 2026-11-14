-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_roamer_check.lua -- do Sinnoh's six roamers exist, and do they
-- follow PLATINUM'S rules rather than Johto's or Hoenn's.
--
-- `activateroamingpokemon` was unlowered, so nothing was ever released --
-- including MESPRIT, which Verity Cavern releases on the main path. But the
-- reason this file exists is not the missing lowering, it is that THIS PORT
-- ALREADY HAS TWO ROAMER SYSTEMS AND PLATINUM MATCHES NEITHER:
--
--                      Gen 2            Gen 3            GEN 4
--   slots              3                1                6
--   meeting it         75/256 then      1 in 4           1 IN 2
--                      1 of 3 slots
--   moving             every map load   every map load   CONNECTION ONLY
--   graph              none             20 nodes         29 NODES, NOT
--                                                        SYMMETRIC
--   after any wild     --               --               30% THEY ALL LEAVE
--
-- Every row of that table is a way to be wrong with no crash and no log line,
-- so every row is asserted here.
--
-- Run:  texlua tools/gen4_roamer_check.lua [cache dir]
--
-- Without a cache only the port's own tables are checked, and it SAYS so.

local cacheDir = arg and arg[1]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local logged = {}
local logger = {
  warn = function(fmt) logged[#logged + 1] = tostring(fmt) end,
  info = function() end, error = function() end, debug = function() end,
}
local inert = setmetatable({}, { __index = function() return function() end end })
table.insert(package.searchers, 1, function(name)
  if name == "src.world.Gen4Roamers" then return nil end
  if name == "src.pokemon.Stats" then return nil end
  if name == "src.core.Logger" then return function() return logger end end
  if name:sub(1, 4) ~= "src." then return nil end
  return function() return inert end
end)

local Roamers = require("src.world.Gen4Roamers")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-58s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-58s got %s, expected %s\n")
                :format(what, tostring(got), tostring(want))) end
end
local function note(line) io.write("  --    " .. line .. "\n") end

-- A deterministic stand-in for love.math.random(lo, hi), so every rule below
-- is asserted against a KNOWN sequence rather than against luck. A check on a
-- probabilistic rule that uses a real RNG is a check that passes most days.
local function feeder(values)
  local i = 0
  return function(lo, hi)
    i = i + 1
    local v = values[((i - 1) % #values) + 1]
    if hi == nil then lo, hi = 1, lo end
    -- clamp into range the way a real rng result already is
    if v < lo then v = lo end
    if v > hi then v = hi end
    return v
  end
end

-- ------------------------------------------------------------- the slots --

io.write("RoamingPokemon_ActivateSlot, transcribed\n")

local slots = 0
for _ in pairs(Roamers.SLOTS) do slots = slots + 1 end
ok(slots == 6, "six slots, as ROAMING_SLOT_MAX has", slots, 6)
ok(Roamers.SLOTS[0].species == 481 and Roamers.SLOTS[0].level == 50,
   "slot 0 is Mesprit at 50",
   Roamers.SLOTS[0].species .. "/" .. Roamers.SLOTS[0].level, "481/50")
ok(Roamers.SLOTS[2].species == 491 and Roamers.SLOTS[2].level == 40,
   "slot 2 is Darkrai at 40 -- the one no script releases",
   Roamers.SLOTS[2].species .. "/" .. Roamers.SLOTS[2].level, "491/40")
local birds = Roamers.SLOTS[3].level == 60 and Roamers.SLOTS[4].level == 60
              and Roamers.SLOTS[5].level == 60
ok(birds, "...and the three Kanto birds are all 60",
   birds and "60/60/60" or "mixed", "60/60/60")
-- THE LEVELS ARE NOT ONE NUMBER, which is the difference from both older
-- generations: Gen 2's beasts are all 40 and Hoenn's one is 40. Sinnoh has
-- three different levels across its six slots.
local levels = {}
for _, d in pairs(Roamers.SLOTS) do levels[d.level] = true end
local distinct = 0
for _ in pairs(levels) do distinct = distinct + 1 end
ok(distinct == 3, "three distinct levels, not one", distinct, 3)

-- ------------------------------------------------------------ the places --

io.write("\nRoamingPokemonRoutes, 29 places\n")

local routes = 0
for _ in pairs(Roamers.ROUTES) do routes = routes + 1 end
ok(routes == 29 and Roamers.ROUTE_COUNT == 29,
   "twenty-nine, as RI_MAX has", routes, 29)
local contiguous = true
for i = 0, 28 do if not Roamers.ROUTES[i] then contiguous = false end end
ok(contiguous, "...indexed 0..28 with no hole", contiguous and "solid" or "holed",
   "solid")
local headers, dupes = {}, 0
for _, row in pairs(Roamers.ROUTES) do
  if headers[row.header] then dupes = dupes + 1 end
  headers[row.header] = true
end
ok(dupes == 0, "no header id appears twice", dupes, 0)

-- ---------------------------------------------------------- the adjacency --

io.write("\nsNearbyRoutes, and the two edges that go one way\n")

local edges, maxOut = 0, 0
for i = 0, 28 do
  local l = Roamers.NEARBY[i] or {}
  edges = edges + #l
  if #l > maxOut then maxOut = #l end
end
ok(edges == 78, "seventy-eight directed edges", edges, 78)
ok(maxOut <= 5, "...and no row exceeds the struct's five slots", maxOut, "<= 5")

local selfLoops = 0
for i = 0, 28 do
  for _, j in ipairs(Roamers.NEARBY[i] or {}) do
    if j == i then selfLoops = selfLoops + 1 end
    if not Roamers.ROUTES[j] then
      note(("row %d names %s, which is not a place"):format(i, tostring(j)))
    end
  end
end
ok(selfLoops == 0, "no place is its own neighbour", selfLoops, 0)

-- !! THE ASYMMETRY IS REAL AND MUST NOT BE TIDIED.
local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end
local oneWay = {}
for i = 0, 28 do
  for _, j in ipairs(Roamers.NEARBY[i] or {}) do
    if not has(Roamers.NEARBY[j], i) then oneWay[#oneWay + 1] = { i, j } end
  end
end
table.sort(oneWay, function(a, b)
  if a[1] ~= b[1] then return a[1] < b[1] end
  return a[2] < b[2]
end)
local want = Roamers.ONE_WAY
local same = #oneWay == #want
if same then
  for k, pair in ipairs(oneWay) do
    if pair[1] ~= want[k][1] or pair[2] ~= want[k][2] then same = false end
  end
end
local function pairsText(list)
  local out = {}
  for _, p in ipairs(list) do out[#out + 1] = p[1] .. "->" .. p[2] end
  return table.concat(out, " ")
end
ok(same, "exactly the two one-way edges the cartridge has",
   pairsText(oneWay), pairsText(want))
note("6->9 is written in pret as a bare `9`, not RI_ROUTE_208 -- the easiest")
note("edge in the table to lose. Symmetrising would invent two; reading one")
note("direction only would drop two. Neither would crash.")

-- ...AND THE GRAPH HAS TO BE TRAVERSABLE, or a roamer can be stranded.
local seen, stack = { [0] = true }, { 0 }
local reached = 1
while #stack > 0 do
  local n = table.remove(stack)
  for _, m in ipairs(Roamers.NEARBY[n] or {}) do
    if not seen[m] then seen[m] = true; reached = reached + 1; stack[#stack + 1] = m end
  end
end
ok(reached == 29, "every place reachable from Route 201", reached .. "/29", "29/29")

local singles = {}
for i = 0, 28 do
  if #(Roamers.NEARBY[i] or {}) == 1 then singles[#singles + 1] = i end
end
ok(#singles == 4, "four dead ends, which the movement must not loop on",
   #singles .. " (" .. table.concat(singles, ",") .. ")", 4)

-- --------------------------------------------------------------- the odds --

io.write("\nthe rules, against a known RNG\n")

ok(Roamers.MEET_ONE_IN == 2, "a roamer on your map is met one encounter in two",
   Roamers.MEET_ONE_IN, 2)
ok(Roamers.LONG_HOP_ONE_IN == 16, "one move in sixteen leaves the graph",
   Roamers.LONG_HOP_ONE_IN, 16)
ok(Roamers.LEAVE_AFTER_WILD_PERCENT == 30,
   "...and 30% of ORDINARY wild battles scare them off this map",
   Roamers.LEAVE_AFTER_WILD_PERCENT, 30)

-- `check` spends its FIRST roll on the coin and its second on which roamer.
-- Asserted both ways: a coin of 0 is a miss and anything else is a hit, which
-- is `LCRNG_RandMod(2) == 0 -> return FALSE`.
local data = { maps = {} }
for i = 0, 28 do
  data.maps[Roamers.ROUTES[i].map] = { header = Roamers.ROUTES[i].header }
end

local function saveWith(rows)
  local save = { gen4Roamers = {} }
  for slot, map in pairs(rows) do
    save.gen4Roamers[slot] = {
      slot = slot, name = Roamers.SLOTS[slot].name,
      species = Roamers.SLOTS[slot].species, level = Roamers.SLOTS[slot].level,
      active = true, map = map, route = nil, hp = 100,
    }
    for i = 0, 28 do
      if Roamers.ROUTES[i].map == map then save.gen4Roamers[slot].route = i end
    end
  end
  return save
end

local s = saveWith({ [0] = "R209" })
ok(Roamers.check(data, s, "R209", feeder({ 0 })) == nil,
   "a coin of 0 is a MISS even with a roamer standing there",
   tostring(Roamers.check(data, s, "R209", feeder({ 0 }))), "nil")
local slot = Roamers.check(data, s, "R209", feeder({ 1, 0 }))
ok(slot == 0, "...and a coin of 1 meets it", tostring(slot), 0)
ok(Roamers.check(data, s, "R210A", feeder({ 1, 0 })) == nil,
   "never on a map it is not on",
   tostring(Roamers.check(data, s, "R210A", feeder({ 1, 0 }))), "nil")

-- THE ORDER OF THE TWO ROLLS IS THE WHOLE DIFFERENCE FROM GEN 2. With three
-- birds on one route the coin is spent ONCE and then splits three ways, so
-- every one of the three is reachable from the same first roll.
local three = saveWith({ [3] = "R209", [4] = "R209", [5] = "R209" })
local got = {}
for pick = 0, 2 do
  local sl = Roamers.check(data, three, "R209", feeder({ 1, pick }))
  got[sl] = true
end
local reachable = 0
for _ in pairs(got) do reachable = reachable + 1 end
ok(reachable == 3, "three roamers on one route split ONE coin three ways",
   reachable, 3)
ok(Roamers.check(data, three, "R209", feeder({ 0 })) == nil,
   "...and that coin still decides for all three at once",
   tostring(Roamers.check(data, three, "R209", feeder({ 0 }))), "nil")

-- ------------------------------------------------------------ the moving --

io.write("\nmoving\n")

-- A nearby step must land on a neighbour of where it stood, and must refuse
-- the map the player just left.
local m = saveWith({ [0] = "R209" })            -- route index 10, nearby {9,11,15}
m.gen4Roamers.recent = { current = "R209", previous = "R208" } -- 9
-- ASSERTED AS ONE STATEMENT, because the two halves can pass separately for
-- the wrong reason: a step that gives up and STAYS PUT satisfies "did not go to
-- the forbidden map" while doing nothing at all. That is precisely what the
-- first version of `stepNearby` did, and how it was caught.
local function stepped(mapId, from, feed)
  local it = { }
  local sv = saveWith({ [0] = mapId })
  sv.gen4Roamers.recent = { current = mapId, previous = from }
  local dest = Roamers.stepNearby(data, sv, 0, feeder(feed))
  local here
  for i = 0, 28 do if Roamers.ROUTES[i].map == mapId then here = i end end
  local isNeighbour = false
  for _, j in ipairs(Roamers.NEARBY[here] or {}) do
    if Roamers.ROUTES[j].map == dest then isNeighbour = true end
  end
  return dest, isNeighbour
end
-- Route 209 is index 10, neighbours {9 R208, 11 R210A, 15 R212A}; forbid R208
-- and only two are legal, so EVERY roll must land on one of those two.
local landedAll = true
local seenDest = {}
for roll = 0, 2 do
  local dest, isNeighbour = stepped("R209", "R208", { roll })
  seenDest[tostring(dest)] = true
  if not (isNeighbour and dest ~= "R208" and dest ~= "R209") then
    landedAll = false
    note(("roll %d gave %s"):format(roll, tostring(dest)))
  end
end
local distinctDest = 0
for _ in pairs(seenDest) do distinctDest = distinctDest + 1 end
ok(landedAll, "every step lands on a neighbour that is not the forbidden map",
   landedAll and "R210A/R212A only" or "see above", "R210A/R212A only")
ok(distinctDest == 2,
   "...and BOTH legal neighbours are reachable (no silent stay-put)",
   distinctDest, 2)

-- A DEAD END WHOSE ONLY NEIGHBOUR IS THE FORBIDDEN MAP MUST NOT LOOP. Route
-- 217's single neighbour is Route 216; stand the player on 216 and the step has
-- to fall through to the long hop, which is the cartridge's own branch.
local d = saveWith({ [0] = "R217" })            -- index 21, nearby {20}
d.gen4Roamers.recent = { current = "R216", previous = "R216" }
local out = Roamers.stepNearby(data, d, 0, feeder({ 3, 7, 11 }))
ok(out ~= nil and out ~= "R216",
   "a dead end pointing at the forbidden map takes the long hop",
   tostring(out), "anything but R216")

-- The long hop must leave the place it stood.
local h = saveWith({ [0] = "R201" })
local hopped = Roamers.hop(data, h, 0, feeder({ 0, 5 }))
ok(hopped ~= nil and hopped ~= "R201", "a long hop never stays put",
   tostring(hopped), "not R201")

-- moveAll: a roll of 0 on the sixteen takes the long hop, anything else steps.
local a = saveWith({ [0] = "R209", [1] = "R214" })
ok(Roamers.moveAll(data, a, feeder({ 1, 0 })) == 2,
   "moveAll moves every active slot", Roamers.moveAll(data, a, feeder({ 1, 0 })), 2)
local none = { gen4Roamers = {} }
ok(Roamers.moveAll(data, none, feeder({ 1 })) == 0,
   "...and nothing at all when none is loose",
   Roamers.moveAll(data, none, feeder({ 1 })), 0)

-- The recent-route memory only shifts when the map CHANGES.
local r = saveWith({ [0] = "R209" })
Roamers.noteMap(r, "R210A")
Roamers.noteMap(r, "R210A")
Roamers.noteMap(r, "R211A")
ok(Roamers.previousMap(r) == "R210A",
   "walking in and out of a door does not consume the memory",
   tostring(Roamers.previousMap(r)), "R210A")
local q = { gen4Roamers = {} }
ok(Roamers.noteMap(q, "R201") == false,
   "...and the memory is not kept while nothing is roaming",
   tostring(Roamers.noteMap(q, "R201")), "false")

-- -------------------------------------------------------- after a battle --

io.write("\nafter a wild battle\n")

local b = saveWith({ [0] = "R209" })
local left = Roamers.afterBattle(data, b, "R209", 0, 7, "par", false,
                                 feeder({ 1, 4 }))
ok(left == 1 and b.gen4Roamers[0].map ~= "R209",
   "meeting one writes its HP back AND clears it off this map",
   ("left=%s hp=%s"):format(tostring(left), tostring(b.gen4Roamers[0].hp)),
   "left=1 hp=7")
ok(b.gen4Roamers[0].hp == 7 and b.gen4Roamers[0].status == "par",
   "...damage and status carry between meetings",
   tostring(b.gen4Roamers[0].hp) .. "/" .. tostring(b.gen4Roamers[0].status),
   "7/par")

local c = saveWith({ [0] = "R209" })
Roamers.afterBattle(data, c, "R209", 0, 0, nil, true, feeder({ 1 }))
ok(Roamers.active(c, 0) == nil, "catching or beating one retires the slot",
   tostring(Roamers.active(c, 0)), "nil")

-- THE 30% THAT IS NOT GUESSABLE, both sides of it.
local w = saveWith({ [0] = "R209" })
local n1 = Roamers.afterBattle(data, w, "R209", nil, 0, nil, false,
                               feeder({ 29, 3 }))
ok(n1 == 1 and w.gen4Roamers[0].map ~= "R209",
   "an ORDINARY wild battle scares it off on a roll under 30",
   tostring(n1), 1)
local w2 = saveWith({ [0] = "R209" })
local n2 = Roamers.afterBattle(data, w2, "R209", nil, 0, nil, false,
                               feeder({ 30 }))
ok(n2 == 0 and w2.gen4Roamers[0].map == "R209",
   "...and leaves it alone on 30 itself (`< 30`, not `<=`)",
   tostring(n2), 0)
local elsewhere = saveWith({ [0] = "R214" })
local n3 = Roamers.afterBattle(data, elsewhere, "R209", nil, 0, nil, false,
                               feeder({ 0, 3 }))
ok(n3 == 0 and elsewhere.gen4Roamers[0].map == "R214",
   "...and never touches one on another route", tostring(n3), 0)

-- ---------------------------------------------------------------- a cache --

if not cacheDir then
  io.write("\n(no cache was checked -- pass a cache dir as the first argument\n"
           .. " to verify the 29 header ids and their encounter tables)\n")
  io.write(("\n%d checks, %d failures\n"):format(checks, fails))
  os.exit(fails == 0 and 0 or 1)
end

local chunk = loadfile(cacheDir .. "/maps.lua")
local maps = chunk and chunk() or nil
if not maps then
  io.write("\ncannot read maps.lua from " .. cacheDir .. "\n")
  os.exit(2)
end

io.write("\nthe 29 places, against a cache\n")

local byHeader = {}
for id, def in pairs(maps) do
  if def.header then byHeader[def.header] = id end
end

local named, labelled, encountered = 0, 0, 0
for i = 0, 28 do
  local row = Roamers.ROUTES[i]
  local id = byHeader[row.header]
  local def = id and maps[id]
  if id == row.map then named = named + 1
  else note(("index %d: the table says %s, the cache says %s")
            :format(i, row.map, tostring(id))) end
  -- THE LABEL IS THE INDEPENDENT CHECK. `what` is written from the enum's own
  -- name; the cache's label comes from the cartridge's message bank. They have
  -- to agree on the route number, and a transposed id would not.
  local label = def and def.label
  if label and row.what:find(label, 1, true) == 1 then labelled = labelled + 1
  elseif label and row.what:lower():find(label:lower(), 1, true) then
    labelled = labelled + 1
  else
    note(("%s: the table calls it %q, the cache labels it %q")
         :format(row.map, row.what, tostring(label)))
  end
  if def and def.encounters then encountered = encountered + 1
  else note(("%s has no wild-encounter table -- a roamer there could never "
             .. "be met"):format(tostring(id))) end
end
ok(named == 29, "every header id lands on the map it names", named .. "/29",
   "29/29")
ok(labelled == 29, "...and on the route the cartridge labels it",
   labelled .. "/29", "29/29")
ok(encountered == 29, "...and every one has wild encounters",
   encountered .. "/29", "29/29")

-- Resolving through the cache rather than the table's own `map` field is what a
-- renamed map needs, so that path is exercised too.
local live = { maps = maps }
local resolved = 0
for i = 0, 28 do
  if Roamers.mapOf(live, i) == Roamers.ROUTES[i].map then resolved = resolved + 1 end
end
ok(resolved == 29, "mapOf resolves all 29 through the cache's headers",
   resolved .. "/29", "29/29")

-- ------------------------------------- and the games that share the hooks --

io.write("\nGold, Crystal, Prism and Emerald, which share the same three hooks\n")

-- ALL FIVE GEN 4 ROAMER CALL SITES ARE IN SHARED CODE: the map-change step,
-- the encounter roll and the after-battle pass all live in
-- OverworldController.lua beside Johto's and Hoenn's. The cheap way for this
-- work to break the older games is for one of them to run unguarded -- Gen 2's
-- beasts would then answer to Sinnoh's coin, or a Crystal wild battle would
-- walk a table that has no roamers in it.
--
-- Read from the source rather than exercised, deliberately: the guards are the
-- claim, and a harness that could run OverworldController would need a graphics
-- device and a whole save. What matters is that no call reaches a Gen 1-3
-- session at all.
local owc = io.open(root .. "../src/world/OverworldController.lua", "rb")
if not owc then
  ok(false, "OverworldController.lua is readable from here", "missing", "found")
else
  local src = owc:read("*a"):gsub("\r\n", "\n")
  owc:close()
  local lines = {}
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  local sites, guarded = 0, 0
  for i, line in ipairs(lines) do
    if line:find("src.world.Gen4Roamers", 1, true) then
      sites = sites + 1
      -- THE NEAREST GENERATION TEST ABOVE IT, not merely "an isGen4 somewhere
      -- above". The second question passes when a Gen 4 call has drifted under
      -- a Gen 2 guard that happens to sit below a Gen 4 one, which is the
      -- mistake worth catching. A long comment can separate a guard from its
      -- call, so the window is generous -- what it must not do is skip past an
      -- intervening guard for another generation.
      local nearest
      for back = i, math.max(1, i - 60), -1 do
        local g = lines[back]:match("GameVersion%.isGen(%d)%(%)")
        if g then nearest = g break end
      end
      if nearest == "4" then guarded = guarded + 1
      else note(("line %d calls Gen4Roamers under %s")
                :format(i, nearest and ("isGen" .. nearest .. "()")
                        or "no generation guard")) end
    end
  end
  ok(sites == 5, "five Gen 4 roamer call sites, as written", sites, 5)
  ok(guarded == sites and sites > 0,
     "...and every one of them is behind GameVersion.isGen4()",
     guarded .. "/" .. sites, sites .. "/" .. sites)
  -- ...AND THE OLDER ARMS ARE STILL REACHED. A guard that excluded everything
  -- would pass the test above and silently retire Johto's beasts.
  ok(src:find('require("src.world.RoamMons")', 1, true) ~= nil,
     "Johto's beasts are still called", "present", "present")
  ok(src:find('require("src.world.Gen3Roamers")', 1, true) ~= nil,
     "...and Hoenn's one too", "present", "present")
  ok(src:find('battle.roamer ~= "gen4"', 1, true) ~= nil,
     "the older after-battle arm excludes only the Gen 4 case",
     "present", "present")
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
