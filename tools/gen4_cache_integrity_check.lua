-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE EXTRACTED CARTRIDGE, CHECKED AGAINST ITSELF AND AGAINST THE ENGINE.
--
-- THE RECURRING BUG IN THIS PORT is one thing spelled two ways in two files
-- that never meet.  It has cost a whole feature at least six times: the Gen 4
-- type chart, the abilities, the move effects, the ball pocket, the item
-- `key`, the party icons.  Every one of them passed every check that existed,
-- because each file was internally consistent and nothing compared them.
--
-- This compares them.  Two directions, and the second is the one that bites:
--
--   DANGLING REFERENCE -- the cache names something the cache does not have.
--     A learnset move that is not in `moves`, an evolution target that is not
--     a species.  Loud when it happens, and it does not happen today.
--
--   DEAD HANDLER -- the ENGINE dispatches on a name the cartridge never
--     produces.  Silent, total, and the shape of every bug listed above: the
--     handler is correct, the data is correct, and the two never meet.  A
--     Platinum species whose ability the engine spells differently simply has
--     no ability.
--
-- WHAT IT IS NOT.  It does not check that a value is RIGHT -- that the
-- cartridge's Bulbasaur really learns Vine Whip at 13.  It checks that every
-- name and id the dataset and the engine exchange is one the other side
-- knows.  Those are different questions and this is the cheap one.
--
-- ON THE PINS.  Reference COUNTS are floors, not equalities: a re-import that
-- extracts more data should not fail a check.  What is pinned exactly is the
-- structure -- eighteen types, eight pockets, two hundred effect rows -- and
-- what is pinned at zero is every dangling reference.  The floors exist so
-- that an EMPTY cache cannot pass: a measurement that cannot fail says
-- nothing, and "0 dangling references out of 0 references" is that.
--
-- Usage: texlua tools/gen4_cache_integrity_check.lua <cache dir>
--    or: python tools/run_lua_check.py tools/gen4_cache_integrity_check.lua <cache dir>

package.path = "./?.lua;" .. package.path

-- LuaJIT has `bit` and its own is the one to use; texlua has not got it.
if not pcall(require, "bit") then
  package.preload["bit"] = function()
    local function tou32(v) return math.floor(v) % 4294967296 end
    local function op(a, b, f)
      a, b = tou32(a), tou32(b)
      local r, m = 0, 1
      for _ = 1, 32 do
        r = r + f(a % 2, b % 2) * m
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
      end
      return r
    end
    local M = {}
    function M.band(a, b) return op(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end
    function M.bor(a, b) return op(a, b, function(x, y) return (x == 1 or y == 1) and 1 or 0 end) end
    function M.bxor(a, b) return op(a, b, function(x, y) return (x ~= y) and 1 or 0 end) end
    function M.bnot(a) return 4294967295 - tou32(a) end
    function M.lshift(a, n) return tou32(tou32(a) * 2 ^ n) end
    function M.rshift(a, n) return math.floor(tou32(a) / 2 ^ n) end
    function M.arshift(a, n) return M.rshift(a, n) end
    function M.tobit(a) local v = tou32(a) return v >= 2147483648 and v - 4294967296 or v end
    function M.tohex(a) return ("%08x"):format(tou32(a)) end
    return M
  end
end

love = love or {
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  graphics = { getWidth = function() return 240 end, getHeight = function() return 160 end },
  timer = { getTime = function() return 0 end },
  system = { getOS = function() return "Linux" end },
}

local DIR = arg and arg[1]
if not DIR then
  io.write("Pass the Gen 4 cache's generated data root as the first argument.\n")
  os.exit(2)
end
DIR = DIR:gsub("[/\\]+$", "")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- IS THIS EVEN A GEN 4 CACHE?  Asked FIRST, and answered off the engine's own
-- marker (`constants.gen`, which is what `Bag.gen4Pockets` tests), because
-- everything below is Sinnoh-shaped.  Pointed at Hoenn this used to assert
-- ninety times and then throw on a type chart of a different shape -- noise
-- that buries the one line worth reading.  The other tools in this directory
-- skip an input they are not for; so does this.
do
  local chunk = loadfile(DIR .. "/constants.lua")
  local good, constants = false, nil
  if chunk then good, constants = pcall(chunk) end
  local gen = good and type(constants) == "table" and constants.gen or nil
  if gen ~= 4 then
    io.write(("%s is a gen %s cache; this check is Gen 4 only -- skipped.\n")
             :format(DIR, tostring(gen)))
    os.exit(0)
  end
end

-- ---------------------------------------------------------------------------
section("1. the cache loads, and it is not empty")
-- ---------------------------------------------------------------------------
local function load(name)
  local chunk = loadfile(DIR .. "/" .. name .. ".lua")
  if not chunk then return nil, "no such module" end
  local good, value = pcall(chunk)
  if not good then return nil, tostring(value) end
  if type(value) ~= "table" then return nil, "did not return a table" end
  return value
end

local MODULES = { "pokemon", "moves", "items", "type_chart", "encounters",
                  "trainers" }
local D = {}
for _, name in ipairs(MODULES) do
  local value, why = load(name)
  ok(value ~= nil, "%s.lua did not load from %s: %s", name, DIR, tostring(why))
  D[name] = value
end
if not (D.pokemon and D.moves and D.items and D.type_chart and D.encounters
        and D.trainers) then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

-- A GEN 4 CACHE AND NOT SOME OTHER ONE.  Pointing this at Red's would
-- otherwise "pass" most of what follows while measuring nothing about Sinnoh.
ok(count(D.pokemon) >= 490, "only %d species -- not a Platinum cache",
   count(D.pokemon))
ok(count(D.moves) >= 460, "only %d moves -- not a Platinum cache",
   count(D.moves))
ok(count(D.items) >= 430, "only %d items", count(D.items))
ok(count(D.trainers) >= 900, "only %d trainers", count(D.trainers))
ok(count(D.encounters) >= 170, "only %d encounter tables", count(D.encounters))
io.write(("  %d species, %d moves, %d items, %d trainers, %d encounter tables\n")
         :format(count(D.pokemon), count(D.moves), count(D.items),
                 count(D.trainers), count(D.encounters)))

-- ---------------------------------------------------------------------------
section("2. the eighteen type names, in all three places that spell them")
-- ---------------------------------------------------------------------------
-- The bug this replaces: three spellings of the eighteen types in three files
-- that never met, which made EVERY Platinum move typeless -- no STAB, no
-- effectiveness, no immunity.
local ids = D.type_chart.ids
ok(type(ids) == "table", "type_chart has no `ids`")
if type(ids) ~= "table" then
  -- no point walking every move against a chart that is not there, and
  -- indexing it would throw rather than report
  ids = nil
end
ok(ids == nil or count(ids) == 18,
   "the type chart names %d types, not 18", ids and count(ids) or 0)

local moveTypes, moveTypeBad, moveIdBad = 0, 0, 0
for _, m in pairs(D.moves) do
  if ids and type(m) == "table" and m.type ~= nil then
    moveTypes = moveTypes + 1
    if ids[m.type] == nil then
      moveTypeBad = moveTypeBad + 1
      if moveTypeBad <= 3 then
        io.write(("  %s has type %q, which the type chart does not name\n")
                 :format(tostring(m.name), tostring(m.type)))
      end
    elseif type(m.typeId) == "number" and ids[m.type] ~= m.typeId then
      moveIdBad = moveIdBad + 1
      if moveIdBad <= 3 then
        io.write(("  %s is %s/%d and the chart says %d\n")
                 :format(tostring(m.name), m.type, m.typeId, ids[m.type]))
      end
    end
  end
end
ok(moveTypes >= 460, "only %d move type references", moveTypes)
ok(moveTypeBad == 0, "%d move(s) carry a type the chart does not name",
   moveTypeBad)
ok(moveIdBad == 0, "%d move(s) disagree with the chart about their own type id",
   moveIdBad)

local monSlots, monTypeBad, monIdBad = 0, 0, 0
for _, p in pairs(D.pokemon) do
  if ids and type(p) == "table" then
    for i, name in ipairs(p.types or {}) do
      monSlots = monSlots + 1
      if ids[name] == nil then
        monTypeBad = monTypeBad + 1
        if monTypeBad <= 3 then
          io.write(("  %s has type %q, which the type chart does not name\n")
                   :format(tostring(p.name), tostring(name)))
        end
      elseif p.typeIds and type(p.typeIds[i]) == "number"
             and ids[name] ~= p.typeIds[i] then
        monIdBad = monIdBad + 1
      end
    end
  end
end
ok(monSlots >= 700, "only %d species type slots", monSlots)
ok(monTypeBad == 0, "%d species type slot(s) name a type the chart does not",
   monTypeBad)
ok(monIdBad == 0, "%d species type slot(s) disagree with the chart", monIdBad)
io.write(("  %d move types and %d species type slots resolve\n")
         :format(moveTypes, monSlots))

-- ---------------------------------------------------------------------------
section("3. what a species points at")
-- ---------------------------------------------------------------------------
local evo, evoBad = 0, 0
local evoItem, evoItemBad, evoMove, evoMoveBad = 0, 0, 0, 0
local learn, learnBad, held, heldBad = 0, 0, 0, 0
for _, p in pairs(D.pokemon) do
  if type(p) == "table" then
    for _, e in ipairs(p.evolutions or {}) do
      -- the species is `target`; `param` is the level, item, move or species
      -- the method needs, and `paramKind` says which
      if type(e.target) == "number" and e.target ~= 0 then
        evo = evo + 1
        if D.pokemon[e.target] == nil then
          evoBad = evoBad + 1
          if evoBad <= 3 then
            io.write(("  %s evolves into species %d, which does not exist\n")
                     :format(tostring(p.name), e.target))
          end
        end
      end
      if e.paramKind == "item" and type(e.param) == "number" and e.param ~= 0 then
        evoItem = evoItem + 1
        if D.items[e.param] == nil then evoItemBad = evoItemBad + 1 end
      elseif e.paramKind == "move" and type(e.param) == "number" and e.param ~= 0 then
        evoMove = evoMove + 1
        if D.moves[e.param] == nil then evoMoveBad = evoMoveBad + 1 end
      elseif e.paramKind == "species" and type(e.param) == "number" and e.param ~= 0 then
        if D.pokemon[e.param] == nil then evoBad = evoBad + 1 end
      end
    end
    for _, e in ipairs(p.learnset or {}) do
      if type(e) == "table" and type(e.move) == "number" then
        learn = learn + 1
        if D.moves[e.move] == nil then
          learnBad = learnBad + 1
          if learnBad <= 3 then
            io.write(("  %s learns move %d, which does not exist\n")
                     :format(tostring(p.name), e.move))
          end
        end
      end
    end
    for _, item in pairs(p.heldItems or {}) do
      if type(item) == "number" and item ~= 0 then
        held = held + 1
        if D.items[item] == nil then heldBad = heldBad + 1 end
      end
    end
  end
end
ok(evo >= 240, "only %d evolution targets", evo)
ok(evoBad == 0, "%d evolution(s) point at a species that does not exist", evoBad)
ok(evoItem >= 40, "only %d item-method evolutions", evoItem)
ok(evoItemBad == 0, "%d evolution(s) need an item that does not exist",
   evoItemBad)
ok(evoMove >= 5, "only %d move-method evolutions", evoMove)
ok(evoMoveBad == 0, "%d evolution(s) need a move that does not exist",
   evoMoveBad)
ok(learn >= 6000, "only %d learnset entries", learn)
ok(learnBad == 0, "%d learnset entr(ies) name a move that does not exist",
   learnBad)
ok(held >= 200, "only %d held-item references", held)
ok(heldBad == 0, "%d held item(s) do not exist", heldBad)
io.write(("  %d evolutions, %d learnset entries, %d held items resolve\n")
         :format(evo, learn, held))

-- ...AND `tmLearnset` IS A MASK, NOT A LIST OF MOVES.  Gen 4 stores the
-- machines a species can learn as a 128-bit bitmask rather than a move list
-- (see the Gen 4 TM notes), so reading it as move ids produces nonsense that
-- happens not to raise.  This is the pin that stops a future pass "fixing"
-- the check by treating it as ids: every word in it is far outside move range.
local maskWords, maskInMoveRange = 0, 0
for _, p in pairs(D.pokemon) do
  if type(p) == "table" then
    for _, word in pairs(p.tmLearnset or {}) do
      if type(word) == "number" and word ~= 0 then
        maskWords = maskWords + 1
        if word > 0 and word <= count(D.moves) then
          maskInMoveRange = maskInMoveRange + 1
        end
      end
    end
  end
end
ok(maskWords >= 1000, "only %d tmLearnset mask words", maskWords)
ok(maskInMoveRange < maskWords / 2,
   "%d of %d tmLearnset words land in move-id range -- is it a list after all?",
   maskInMoveRange, maskWords)

-- ---------------------------------------------------------------------------
section("4. every wild encounter names a species that exists")
-- ---------------------------------------------------------------------------
-- The water blocks are NOT lists: `waterBlock` returns { rate, slots }, and a
-- check that walked them with ipairs would silently measure nothing -- which
-- is how this section first reported that Sinnoh had no surfing encounters.
local WATER = { "surf", "unused", "oldRod", "goodRod", "superRod" }
local VARIANT = { "day", "night", "swarm", "radar" }
local refs, dangling, byField = 0, 0, {}
local function note(field, species, where)
  refs = refs + 1
  byField[field] = (byField[field] or 0) + 1
  if D.pokemon[species] == nil then
    dangling = dangling + 1
    if dangling <= 4 then
      io.write(("  %s names species %d, which does not exist (%s)\n")
               :format(field, species, where))
    end
  end
end
local waterSlots, waterRates = 0, 0
for id, e in pairs(D.encounters) do
  if type(e) == "table" then
    for _, s in ipairs(e.grass or {}) do
      if type(s) == "table" and type(s.species) == "number" and s.species ~= 0 then
        note("grass", s.species, tostring(id))
      end
    end
    for _, field in ipairs(WATER) do
      local block = e[field]
      if type(block) == "table" and type(block.slots) == "table" then
        if (block.rate or 0) > 0 then waterRates = waterRates + 1 end
        for _, s in ipairs(block.slots) do
          waterSlots = waterSlots + 1
          if type(s) == "table" and type(s.species) == "number" and s.species ~= 0 then
            note(field, s.species, tostring(id))
          end
        end
      end
    end
    for _, field in ipairs(VARIANT) do
      for _, species in ipairs(e[field] or {}) do
        if type(species) == "number" and species ~= 0 then
          note(field, species, tostring(id))
        end
      end
    end
    if type(e.dualSlot) == "table" then
      for game, list in pairs(e.dualSlot) do
        for _, species in ipairs(list or {}) do
          if type(species) == "number" and species ~= 0 then
            note("dualSlot", species, tostring(id) .. "/" .. tostring(game))
          end
        end
      end
    end
  end
end
ok(refs >= 6000, "only %d encounter species references", refs)
ok(dangling == 0, "%d encounter species reference(s) dangle", dangling)
-- the shape pin: water slots are reached through `.slots`, and some of them
-- are real.  Without this the whole water half can go missing unnoticed.
ok(waterSlots >= 900, "only %d water slots -- are they being reached at all?",
   waterSlots)
ok((byField.surf or 0) >= 200, "only %d surf species -- Sinnoh cannot be surfed",
   byField.surf or 0)
ok((byField.superRod or 0) >= 200, "only %d super rod species",
   byField.superRod or 0)
ok(waterRates >= 40, "only %d water blocks carry a rate", waterRates)
local order = {}
for f in pairs(byField) do order[#order + 1] = f end
table.sort(order)
local parts = {}
for _, f in ipairs(order) do parts[#parts + 1] = f .. "=" .. byField[f] end
io.write("  " .. table.concat(parts, " ") .. "\n")

-- ---------------------------------------------------------------------------
section("5. every trainer's party is made of things that exist")
-- ---------------------------------------------------------------------------
local tSpecies, tSpeciesBad = 0, 0
local tMoves, tMovesBad, tItems, tItemsBad = 0, 0, 0, 0
for _, t in pairs(D.trainers) do
  if type(t) == "table" then
    for _, mon in ipairs(t.party or {}) do
      if type(mon.species) == "number" and mon.species ~= 0 then
        tSpecies = tSpecies + 1
        if D.pokemon[mon.species] == nil then
          tSpeciesBad = tSpeciesBad + 1
          if tSpeciesBad <= 3 then
            io.write(("  trainer %s carries species %d, which does not exist\n")
                     :format(tostring(t.name), mon.species))
          end
        end
      end
      for _, move in ipairs(mon.moves or {}) do
        if type(move) == "number" and move ~= 0 then
          tMoves = tMoves + 1
          if D.moves[move] == nil then tMovesBad = tMovesBad + 1 end
        end
      end
      if type(mon.item) == "number" and mon.item ~= 0 then
        tItems = tItems + 1
        if D.items[mon.item] == nil then tItemsBad = tItemsBad + 1 end
      end
    end
    for _, item in ipairs(t.items or {}) do
      if type(item) == "number" and item ~= 0 then
        tItems = tItems + 1
        if D.items[item] == nil then tItemsBad = tItemsBad + 1 end
      end
    end
  end
end
ok(tSpecies >= 1800, "only %d trainer party species", tSpecies)
ok(tSpeciesBad == 0, "%d trainer party species do not exist", tSpeciesBad)
ok(tMoves >= 2500, "only %d trainer party moves", tMoves)
ok(tMovesBad == 0, "%d trainer party moves do not exist", tMovesBad)
ok(tItems >= 190, "only %d trainer items", tItems)
ok(tItemsBad == 0, "%d trainer items do not exist", tItemsBad)
io.write(("  %d party species, %d party moves, %d items resolve\n")
         :format(tSpecies, tMoves, tItems))

-- ---------------------------------------------------------------------------
section("6. DEAD HANDLER: abilities the engine acts on")
-- ---------------------------------------------------------------------------
-- The bug this replaces: the engine dispatched on ability NAMES while a Gen 4
-- cache carried ids, so not one ability in Sinnoh did anything.  The ids are
-- fixed; what this guards is the next spelling drift, in the direction that
-- cannot be seen from either file alone.
local okA, A = pcall(require, "src.battle.Abilities")
ok(okA and type(A) == "table", "src.battle.Abilities did not load: %s",
   tostring(A))
if okA and type(A) == "table" then
  local named = {}
  for _, p in pairs(D.pokemon) do
    if type(p) == "table" then
      for _, a in ipairs(p.abilities or {}) do
        if type(a) == "string" then named[a] = true end
      end
    end
  end
  ok(count(named) >= 100, "the cache names only %d abilities", count(named))

  -- WHICH EXPORTED TABLES ARE KEYED BY AN ABILITY, pinned by name.  A new one
  -- added later fails here rather than going unchecked, which is the whole
  -- point: an unclassified dispatch table is an unchecked one.
  local ABILITY_KEYED = { "CONTACT_STATUS", "ENCOUNTER_RATE", "IMMUNE",
                          "PINCH", "REFUSES", "SWITCH_IN_WEATHER" }
  -- ...and this one is keyed by WEATHER, not by an ability.  It is named so
  -- that the set below is exhaustive.
  local NOT_ABILITY_KEYED = { FORECAST_TYPE = true }
  local exported = {}
  for k, v in pairs(A) do if type(v) == "table" then exported[k] = true end end
  local classified = {}
  for _, k in ipairs(ABILITY_KEYED) do classified[k] = true end
  for k in pairs(NOT_ABILITY_KEYED) do classified[k] = true end
  for k in pairs(exported) do
    ok(classified[k],
       "Abilities exports a table %q that this check does not classify -- "
         .. "say whether it is keyed by an ability", k)
  end
  for _, k in ipairs(ABILITY_KEYED) do
    ok(exported[k], "Abilities no longer exports %q", k)
  end

  local handlers, dead = 0, 0
  for _, table_ in ipairs(ABILITY_KEYED) do
    for key in pairs(A[table_] or {}) do
      if type(key) == "string" then
        handlers = handlers + 1
        if not named[key] then
          dead = dead + 1
          io.write(("  DEAD: %s.%s -- no species in this cache has it, so the "
                      .. "handler can never fire\n"):format(table_, key))
        end
      end
    end
  end
  ok(handlers >= 20, "only %d ability handlers found", handlers)
  ok(dead == 0, "%d ability handler(s) name an ability this cartridge does not",
     dead)
  -- the weather table really is weather: if an ability name appeared here it
  -- would be a handler filed under the wrong key
  local misfiled = 0
  for key in pairs(A.FORECAST_TYPE or {}) do
    if named[key] then misfiled = misfiled + 1 end
  end
  ok(misfiled == 0,
     "%d FORECAST_TYPE key(s) are ability names -- filed under the wrong key",
     misfiled)
  io.write(("  %d ability handlers over %d cache ability names\n")
           :format(handlers, count(named)))
end

-- ---------------------------------------------------------------------------
section("7. DEAD HANDLER: the bag's pockets")
-- ---------------------------------------------------------------------------
-- The bug this replaces: no Platinum item could be used, because the ball
-- pocket was spelled one way by the cartridge and another by the bag.
local pockets = {}
for _, item in pairs(D.items) do
  if type(item) == "table" and type(item.pocket) == "string" then
    pockets[item.pocket] = true
  end
end
ok(count(pockets) == 8, "the cartridge uses %d pockets, not 8", count(pockets))

local bagSrc = nil
do
  local fh = io.open("src/inventory/Bag.lua", "rb")
  if fh then bagSrc = fh:read("*a") fh:close() end
end
ok(bagSrc ~= nil, "src/inventory/Bag.lua could not be read")
if bagSrc then
  local body = bagSrc:match("GEN4_POCKET_CAP%s*=%s*{(.-)\n}")
             or bagSrc:match("GEN4_POCKET_CAP%s*=%s*{(.-)}")
  ok(body ~= nil, "Bag.lua has no GEN4_POCKET_CAP table to compare against")
  if body then
    local engine = {}
    for key in body:gmatch("([A-Z][A-Z0-9_]*)%s*=") do engine[key] = true end
    ok(count(engine) == 8, "the bag names %d Gen 4 pockets, not 8",
       count(engine))
    -- BOTH DIRECTIONS.  A pocket the bag does not know holds items the player
    -- cannot reach; a pocket the cartridge never uses is a tab that is always
    -- empty.
    for name in pairs(pockets) do
      ok(engine[name], "the cartridge puts items in %q and the bag has no "
                         .. "such pocket", name)
    end
    for name in pairs(engine) do
      ok(pockets[name], "the bag has a %q pocket and no cartridge item is in "
                          .. "it", name)
    end
    io.write(("  %d pockets, matched both ways\n"):format(count(pockets)))
  end
end

-- ---------------------------------------------------------------------------
section("8. DEAD HANDLER: move effects, and the gap they leave")
-- ---------------------------------------------------------------------------
-- The bug this replaces: every Sinnoh move that was not a plain hit said
-- "But, it failed!", because the effect id and the effect name were two
-- spellings that never met.
--
-- The extractor's rule is deliberate: `effect` carries the NAME where there
-- is a handler row and the NUMBER where there is not, and `gen4EffectName`
-- carries the human name beside it so the gap can be reported rather than
-- merely suffered.  This checks that rule holds in every case.
local okM, M = pcall(require, "src.import.Gen4Moves")
ok(okM and type(M) == "table", "src.import.Gen4Moves did not load: %s",
   tostring(M))
if okM and type(M) == "table" then
  local rows, names = M.EFFECTS or {}, M.EFFECT_NAMES or {}
  -- 204: Hoenn's 195 inherited ids, the four semi-invulnerable rows plus
  -- Whirlpool's bind, and the four dynamic-power effects (217, 219, 221,
  -- 237) whose handlers were written in pass 161. `gen4_moveeffect_check`
  -- owns the argument for each; this is the count agreeing with it.
  ok(count(rows) == 204, "there are %d effect handler rows, not 204",
     count(rows))
  ok(count(names) >= 50, "only %d fallback effect names", count(names))

  -- an id cannot have both a handler and a fallback name: the fallback exists
  -- precisely because there is no handler, so an overlap means one of the two
  -- tables is wrong about which effects are implemented
  local both = 0
  for id in pairs(names) do if rows[id] then both = both + 1 end end
  ok(both == 0, "%d effect id(s) have both a handler row and a fallback name",
     both)

  local used, fellThrough, unnamed, numericWithRow = {}, 0, 0, 0
  local namedEffects = 0
  for _, m in pairs(D.moves) do
    if type(m) == "table" then
      if type(m.gen4Effect) == "number" then used[m.gen4Effect] = true end
      local numeric = type(m.effect) == "number"
                      or (type(m.effect) == "string" and tonumber(m.effect) ~= nil)
      if numeric then
        fellThrough = fellThrough + 1
        -- BOTH SIDES, not just the cache's own copy.  The name is written
        -- at import time out of `EFFECT_NAMES`, so checking only that the
        -- cache has one would pass against an engine table that had lost the
        -- entry -- and the next re-import would drop the name silently.
        local engineName = names[m.gen4Effect]
        if not m.gen4EffectName then
          unnamed = unnamed + 1
          io.write(("  %s falls through to the number %s and carries no name, "
                      .. "so the gap cannot be reported\n")
                   :format(tostring(m.name), tostring(m.effect)))
        elseif rows[m.gen4Effect] then
          -- IMPLEMENTED SINCE THIS CACHE WAS WRITTEN, which is not a naming
          -- fault at all: the id has a handler row now, so `EFFECT_NAMES` is
          -- required NOT to carry it -- the two tables are asserted disjoint
          -- above -- and the cache is simply behind. `numericWithRow` below
          -- reports that once, with the remedy, so comparing names here as
          -- well would turn one stale cache into two different-looking faults.
          --
          -- Four effects crossed this line when the dynamic-power handlers
          -- were written, and without this arm each of them read as "the
          -- engine lost a name", which is the opposite of what happened. The
          -- arm below still fires when a name goes missing with nothing to
          -- replace it, which is the fault it is actually for.
        elseif engineName == nil then
          unnamed = unnamed + 1
          io.write(("  %s is named %q in this cache and the engine's "
                      .. "EFFECT_NAMES no longer has id %s\n")
                   :format(tostring(m.name), tostring(m.gen4EffectName),
                           tostring(m.gen4Effect)))
        elseif engineName ~= m.gen4EffectName then
          unnamed = unnamed + 1
          io.write(("  %s is %q in this cache and %q in the engine\n")
                   :format(tostring(m.name), tostring(m.gen4EffectName),
                           tostring(engineName)))
        end
        if rows[m.gen4Effect] then
          numericWithRow = numericWithRow + 1
          io.write(("  %s kept the number %s although a handler row exists\n")
                   :format(tostring(m.name), tostring(m.effect)))
        end
      else
        namedEffects = namedEffects + 1
      end
    end
  end
  ok(namedEffects >= 400, "only %d moves carry a named effect", namedEffects)
  -- EVERY HANDLER IS REACHED.  A row no move uses is dead weight that reads
  -- as coverage.
  local unreached = {}
  for id in pairs(rows) do
    if not used[id] then unreached[#unreached + 1] = id end
  end
  table.sort(unreached)
  ok(#unreached == 0, "%d effect handler row(s) no Platinum move reaches: %s",
     #unreached, table.concat(unreached, ", "))
  ok(unnamed == 0, "%d move(s) fall through to a number with no name", unnamed)
  -- A STALE CACHE SHOWS UP HERE, and that is the point rather than a flaw:
  -- the extractor writes the NAME wherever a handler row exists, so a move
  -- still carrying a number means this cache was written before that row.
  -- Reported as what it is, with the remedy, because the alternative is a
  -- reader concluding the engine is broken.
  ok(numericWithRow == 0,
     "%d move(s) kept a number although a handler row exists -- this cache "
     .. "predates those rows and needs a re-extract; the engine is right and "
     .. "the data is behind it", numericWithRow)

  -- THE GAP ITSELF, pinned as a number so that it can only move deliberately.
  -- These are the Gen 4 effects (ids 214 and up) with no handler: the move
  -- hits and does nothing else. Lowering this is the work; when a handler
  -- lands, this line is what says so.
  -- 59 -> 54 ON THE PASS-167 RE-IMPORT, and the five that left are named here
  -- because "the number went down" is not on its own evidence of anything.
  -- Pass 161 added four dynamic-power handlers and the cache was written
  -- before them, so five moves across those four effects were still marked
  -- unimplemented:
  --
  --     Wake-Up Slap  (217)  DOUBLE_POWER_HEAL_SLEEP
  --     Gyro Ball     (219)  POWER_BASED_ON_LOW_SPEED
  --     Brine         (221)  DOUBLE_POWER_WHEN_BELOW_HALF
  --     Wring Out     (237)  INCREASE_POWER_WITH_MORE_HP
  --     Crush Grip    (237)  INCREASE_POWER_WITH_MORE_HP
  --
  -- Four effect names, five moves -- `Wring Out` and `Crush Grip` share one
  -- effect id, which is why the two counts differ by one and why a reader
  -- checking "did four handlers land?" against a drop of five would conclude
  -- something was wrong.  All four are in `MoveEffects.full`; the same import
  -- also cleared this check's `numericWithRow` arm from 5 to 0, which is the
  -- same fact arriving by the other door.
  ok(fellThrough == 54,
     "%d move(s) have no effect handler, and the recorded figure is 54 -- "
       .. "if a handler was added, lower the pin AND name the moves that left; "
       .. "if this grew, something regressed", fellThrough)
  io.write(("  %d handler rows, all reached; %d move(s) still have no "
              .. "effect handler\n"):format(count(rows), fellThrough))
end

-- ---------------------------------------------------------------------------
section("9. the maps: does every door go somewhere")
-- ---------------------------------------------------------------------------
-- A warp pointing at a map that does not exist is a DEAD END, which is the
-- same bug class as the lifts that went nowhere -- and it cannot be seen from
-- either map alone.
local maps = load("maps")
local layouts = load("map_layouts")
local events4 = load("gen4_events")
local text4 = load("gen4_text")
local headers4 = load("gen4_map_headers")
local tilesets = load("tilesets")
local scripts = load("map_scripts")
ok(maps ~= nil, "maps.lua did not load")
ok(layouts ~= nil, "map_layouts.lua did not load")
ok(scripts ~= nil, "map_scripts.lua did not load")

if maps and layouts and events4 and text4 and headers4 and tilesets and scripts then
  local byId = {}
  for id, m in pairs(maps) do if type(m) == "table" then byId[id] = m end end
  ok(count(byId) >= 580, "only %d maps", count(byId))

  -- THE ONE NON-MAP WARP TARGET, named rather than pattern-matched.  Sinnoh's
  -- department-store lifts warp through a sentinel resolved at runtime from the
  -- special-location save slot, and there are exactly six cars.  Naming it and
  -- pinning the count means a SEVENTH has to be argued for on this line
  -- instead of joining a wildcard.
  local SENTINEL = { GEN4_SPECIAL_LOCATION = true }
  local warps, unknownMap, badWarp, headerMismatch = 0, 0, 0, 0
  local sentinelWarps, reciprocal, oneWay = 0, 0, 0
  local unnamedSentinel = {}
  for id, m in pairs(byId) do
    for _, w in ipairs(m.warps or {}) do
      warps = warps + 1
      local target = w.destMap and byId[w.destMap] or nil
      if not target then
        if w.destMap and SENTINEL[w.destMap] then
          sentinelWarps = sentinelWarps + 1
        else
          unknownMap = unknownMap + 1
          unnamedSentinel[tostring(w.destMap)] = true
          if unknownMap <= 3 then
            io.write(("  %s warp %s leads to %q, which is not a map\n")
                     :format(id, tostring(w.index), tostring(w.destMap)))
          end
        end
      else
        -- THE DESTINATION WARP HAS TO BE THERE TOO.  A warp landing on an
        -- index the far map has not got puts the player at 0,0 or nowhere.
        local landed = nil
        for _, x in ipairs(target.warps or {}) do
          if x.index == w.destWarp then landed = x break end
        end
        if not landed then
          badWarp = badWarp + 1
          if badWarp <= 3 then
            io.write(("  %s warp %s lands on %s warp %s, and that map has %d\n")
                     :format(id, tostring(w.index), w.destMap,
                             tostring(w.destWarp), #(target.warps or {})))
          end
        elseif landed.destMap == id then
          reciprocal = reciprocal + 1
        else
          oneWay = oneWay + 1
        end
        -- ...AND THE HEADER THE WARP CARRIES HAS TO BE THE FAR MAP'S OWN.
        -- Two numbers written by two different stages about the same map; this
        -- is the one assertion here that cannot agree by accident.
        if type(w.destHeader) == "number" and type(target.header) == "number"
           and w.destHeader ~= target.header then
          headerMismatch = headerMismatch + 1
          if headerMismatch <= 3 then
            io.write(("  %s warp %s says header %d and %s carries header %d\n")
                     :format(id, tostring(w.index), w.destHeader, w.destMap,
                             target.header))
          end
        end
      end
    end
  end
  ok(warps >= 1200, "only %d warps -- are they being read at all?", warps)
  ok(unknownMap == 0, "%d warp(s) lead to something that is not a map", unknownMap)
  ok(badWarp == 0, "%d warp(s) land on a warp index the far map has not got",
     badWarp)
  ok(headerMismatch == 0,
     "%d warp(s) disagree with their destination about its own header",
     headerMismatch)
  ok(sentinelWarps == 6,
     "%d warp(s) use the special-location sentinel and six lift cars use it -- "
       .. "if a seventh is real, say so here", sentinelWarps)
  -- ONE-WAY WARPS ARE REAL (the Distortion World has them), so this is a
  -- census and not an equality -- but a collapse either way means the
  -- reciprocity test stopped measuring anything.
  ok(reciprocal >= 1000, "only %d reciprocal warps", reciprocal)
  ok(oneWay >= 100 and oneWay <= 200,
     "%d one-way warps, which is outside the recorded 136 by too much to be "
       .. "a re-import", oneWay)
  io.write(("  %d warps: %d reciprocal, %d one-way, %d through the lift "
              .. "sentinel\n"):format(warps, reciprocal, oneWay, sentinelWarps))

  -- EVERY INDEX A MAP HOLDS INTO ANOTHER MODULE
  local function resolves(field, module, moduleName, floor)
    local n, bad = 0, 0
    for id, m in pairs(byId) do
      local v = m[field]
      if type(v) == "number" then
        n = n + 1
        if module[v] == nil then
          bad = bad + 1
          if bad <= 2 then
            io.write(("  %s has %s = %d, which %s has not got\n")
                     :format(id, field, v, moduleName))
          end
        end
      end
    end
    ok(n >= floor, "only %d %s references", n, field)
    ok(bad == 0, "%d map(s) carry a %s index %s does not have", bad, field,
       moduleName)
    return n
  end
  resolves("layout", layouts, "map_layouts", 580)
  resolves("events", events4, "gen4_events", 580)
  resolves("messages", text4, "gen4_text", 580)
  resolves("header", headers4, "gen4_map_headers", 580)

  local tsRefs, tsBad = 0, 0
  for id, m in pairs(byId) do
    if type(m.tileset) == "string" then
      tsRefs = tsRefs + 1
      if tilesets[m.tileset] == nil then tsBad = tsBad + 1 end
    end
  end
  ok(tsRefs >= 580, "only %d tileset references", tsRefs)
  ok(tsBad == 0, "%d map(s) name a tileset that does not exist", tsBad)
  io.write(("  %d maps resolve layout, events, messages, header and tileset\n")
           :format(count(byId)))

  -- ---- THE SCRIPTS BEHIND THE EVENTS -----------------------------------
  -- The pool is keyed by a COMPOSITE STRING (`M0190/S000B`), not by the
  -- numeric `script` an object carries -- that number is provenance, and
  -- nothing at runtime reads it.  The live path is
  -- `map_scripts.maps[<map>].objects[<n>]` -> a pool key -> a block, so that
  -- is what is walked here.  Looking the number up in the pool finds nothing
  -- and would report every object broken.
  local pool, perMap = scripts.scripts, scripts.maps
  ok(type(pool) == "table" and count(pool) >= 8000,
     "the script pool holds %d blocks", pool and count(pool) or 0)
  ok(type(perMap) == "table" and count(perMap) >= 500,
     "map_scripts.maps holds %d entries", perMap and count(perMap) or 0)
  if type(pool) == "table" and type(perMap) == "table" then
    -- the key shape, pinned: every block, not most of them
    local shaped = 0
    for key in pairs(pool) do
      if type(key) == "string" and key:match("^M%d+/S%x+$") then
        shaped = shaped + 1
      end
    end
    ok(shaped == count(pool),
       "%d of %d pool keys are not the M<n>/S<hex> shape the lookups build",
       count(pool) - shaped, count(pool))

    local refs, unresolved = 0, 0
    for id, t in pairs(perMap) do
      if type(t) == "table" then
        -- objects / signs / coords hold the key directly; a callback holds it
        -- under `.script` beside its name and type
        for _, field in ipairs({ "objects", "signs", "coords" }) do
          for slot, key in pairs(t[field] or {}) do
            if type(key) == "string" then
              refs = refs + 1
              if pool[key] == nil then
                unresolved = unresolved + 1
                if unresolved <= 3 then
                  io.write(("  %s.%s[%s] names script %q, which is not in the "
                              .. "pool\n"):format(id, field, tostring(slot), key))
                end
              end
            end
          end
        end
        for _, callback in pairs(t.callbacks or {}) do
          if type(callback) == "table" and type(callback.script) == "string" then
            refs = refs + 1
            if pool[callback.script] == nil then unresolved = unresolved + 1 end
          end
        end
      end
    end
    ok(refs >= 2300, "only %d script references from map events", refs)
    ok(unresolved == 0, "%d map event(s) name a script block that is not there",
       unresolved)

    -- ...AND A MAP WITH A SCRIPTED EVENT HAS A SCRIPT TABLE AT ALL.
    -- Two Sunyshore maps have objects and NO table, and both are right: every
    -- object on them is `scriptKind = "none"`, a decorative passer-by. So the
    -- test is not "has objects" but "has an object that wants a script",
    -- which is the distinction that makes this assertion true rather than
    -- merely passing.
    local scriptedWithout, sample = 0, {}
    for id, m in pairs(byId) do
      local wants = false
      for _, list in ipairs({ m.objects, m.signs, m.coordEvents }) do
        for _, e in ipairs(list or {}) do
          if e.scriptKind and e.scriptKind ~= "none" then wants = true end
        end
      end
      if wants and perMap[id] == nil then
        scriptedWithout = scriptedWithout + 1
        if #sample < 3 then sample[#sample + 1] = id end
      end
    end
    ok(scriptedWithout == 0,
       "%d map(s) have a scripted event and no script table at all: %s",
       scriptedWithout, table.concat(sample, ", "))
    io.write(("  %d script references from map events, over %d pool blocks\n")
             :format(refs, count(pool)))
  end
end

-- ---------------------------------------------------------------------------
section("10. the map headers, a level below the maps")
-- ---------------------------------------------------------------------------
-- A map carries indices; so does the header it points at, and the two overlap.
-- Where they overlap they must AGREE -- two stages writing one number about one
-- map, which is the same shape as the warp/destHeader check and the same reason
-- it is worth making.
local matrices = load("gen4_map_matrices")
ok(matrices ~= nil, "gen4_map_matrices.lua did not load")
if maps and headers4 and matrices and events4 and text4 then
  local function resolvesHeader(field, module, moduleName)
    local n, bad = 0, 0
    for id, h in pairs(headers4) do
      if type(h) == "table" and type(h[field]) == "number" then
        n = n + 1
        if module[h[field]] == nil then
          bad = bad + 1
          if bad <= 2 then
            io.write(("  header %s has %s = %d, which %s has not got\n")
                     :format(tostring(id), field, h[field], moduleName))
          end
        end
      end
    end
    ok(n >= 580, "only %d header %s references", n, field)
    ok(bad == 0, "%d header(s) carry a %s index %s does not have", bad, field,
       moduleName)
  end
  resolvesHeader("matrix", matrices, "gen4_map_matrices")
  resolvesHeader("events", events4, "gen4_events")
  resolvesHeader("messages", text4, "gen4_text")

  -- THE AGREEMENT, which is the assertion this section exists for.
  local compared, disagree = 0, 0
  for id, m in pairs(maps) do
    if type(m) == "table" and type(m.header) == "number" then
      local h = headers4[m.header]
      if type(h) == "table" then
        for _, field in ipairs({ "events", "messages" }) do
          if type(m[field]) == "number" and type(h[field]) == "number" then
            compared = compared + 1
            if m[field] ~= h[field] then
              disagree = disagree + 1
              if disagree <= 3 then
                io.write(("  %s says %s = %d and its header %d says %d\n")
                         :format(id, field, m[field], m.header, h[field]))
              end
            end
          end
        end
      end
    end
  end
  ok(compared >= 1100, "only %d map-against-header comparisons", compared)
  ok(disagree == 0,
     "%d time(s) a map and its own header disagree about the same index",
     disagree)

  -- `labelWindow` picks one of the name-plate frames, and an out-of-range one
  -- would index nothing at draw time.
  local windows, outside = 0, 0
  for id, h in pairs(headers4) do
    if type(h) == "table" and type(h.labelWindow) == "number" then
      windows = windows + 1
      if h.labelWindow < 1 or h.labelWindow > 9 then
        outside = outside + 1
        if outside <= 3 then
          io.write(("  header %s has labelWindow %d, outside 1..9\n")
                   :format(tostring(id), h.labelWindow))
        end
      end
    end
  end
  ok(windows >= 580, "only %d labelWindow values", windows)
  ok(outside == 0, "%d header(s) name a label window outside 1..9", outside)
  io.write(("  %d headers resolve matrix, events and messages; %d indices "
              .. "agree with the maps that point at them\n")
           :format(count(headers4), compared))

  -- WHAT IS NOT CHECKED HERE, named rather than quietly skipped.  `areaData`
  -- (0..74), `scripts` (2..1123) and `initScripts` (502..1050) are member
  -- indices into cartridge ARCHIVES that no cache module enumerates --
  -- `gen4_arealight` holds the four light members actually used, not the
  -- seventy-five area-data entries, so comparing against it reports 590 false
  -- faults.  Checking these needs the ROM, which this file deliberately does
  -- not take.
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
