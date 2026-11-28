-- RANDOM DATA: the full randomizer's data side.
--
-- The randomizer options that change what the game IS -- moves, learnsets,
-- TM / tutor compatibility, types, abilities, base stats, evolutions, wild
-- held items, prices, trainer names, items lying in the field -- are applied
-- to the loaded dataset in memory, for the save that asks for them, and
-- taken off again the moment another save (or none) is live.
--
--   RandomData.sync(game)   apply / re-apply / restore, as the save asks;
--                           cheap when nothing changed (called every frame
--                           from RunHooks.tick, and before every pick)
--   RandomData.restore()    put the dataset back exactly as loaded
--
-- NOTHING HERE TOUCHES THE DISK.  Every write goes through a journal that
-- remembers the field's original value the first time it is written, and
-- `restore` plays it back; nested tables are always REPLACED, never edited
-- in place, so the journal's originals stay intact.  The cached ROM import
-- on disk is never read back or written.
--
-- DETERMINISM: every choice is a pure function of the save's seed and what
-- is being replaced (RunModes.hash), each species / move / item drawing from
-- its own stream, and every pool is sorted -- so `pairs` order never leaks
-- in, and the same seed gives the same game on every machine.
--
-- SAFETY (the run can always be finished):
--   * learnsets: level 1 always has an attack, and every other later move is
--     an attack, so the four moves a mon is built with always hold one;
--   * TM compatibility: every species keeps its HM (and tutor) entries;
--   * field items / gifts: key items, HMs and story items stay what they are;
--   * prices stay between half and double, POKé BALLS never above their own;
--   * move power / type changes only touch attacks, status moves stay status.

local RunModes = require("src.runmodes.RunModes")
local RandomOptions = require("src.runmodes.RandomOptions")

local RandomData = {}

RandomData.applied = false
RandomData.state = nil

-- --------------------------------------------------------------- helpers --
local function norm(s)
  return (tostring(s or ""):upper():gsub("É", "E"):gsub("é", "E"):gsub("[^%w]", ""))
end
RandomData._norm = norm

-- THE ENGLISH NAME OF A GEN IV MOVE / ITEM, BY ITS ID.
-- The protected / banned lists below are written as English names.  A Gen IV
-- cache in another language (German Platinum) names everything in that
-- language, so before a pass reads a name it `prime`s the dataset: every
-- Gen IV move and item record is mapped to its English name through the
-- cartridge id (src/pokemon/Gen4EnglishRef.lua).  Other datasets keep the
-- names they have.
local ENGLISH = setmetatable({}, { __mode = "k" })
local primed = setmetatable({}, { __mode = "k" })
local function prime(data)
  if type(data) ~= "table" or primed[data] then return end
  primed[data] = true
  local Ref = require("src.pokemon.Gen4EnglishRef")
  if not Ref.isGen4(data) then return end
  for _, kind in ipairs({ "moves", "items" }) do
    for key, def in pairs(data[kind] or {}) do
      local n = type(def) == "table" and (tonumber(key) or tonumber(tostring(key):match("^ITEM_(%d+)$")))
      local english = n and Ref.englishName(kind, n)
      if english then ENGLISH[def] = english end
    end
  end
end
RandomData._prime = prime
local function englishOf(def, id) return ENGLISH[def] or norm(type(def) == "table" and def.name or id) end
RandomData._english = englishOf

local function sortedKeys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
  end)
  return ks
end
RandomData._sortedKeys = sortedKeys

-- a seeded stream: Park-Miller over the save seed and a label
local function Rng(seed, ...)
  local s = RunModes.hash(seed, ...) % 2147483646 + 1
  local r = {}
  function r.float()
    s = (s * 48271) % 2147483647
    return (s - 1) / 2147483646
  end
  function r.int(n) return math.min(n, math.floor(r.float() * n) + 1) end
  function r.range(a, b) return a + math.min(b - a, math.floor(r.float() * (b - a + 1))) end
  function r.pick(list) return list[r.int(#list)] end
  return r
end
RandomData.Rng = Rng

local function shallow(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function genOf(data)
  local g = data and data.constants and tonumber(data.constants.gen)
  if g then return g end
  local ok, GV = pcall(require, "src.core.GameVersion")
  if ok and GV and GV.generation then
    local okG, v = pcall(GV.generation)
    if okG then return tonumber(v) end
  end
  return nil
end
RandomData.genOf = genOf

-- ---------------------------------------------------------------- journal --
local journal = { list = {}, seen = setmetatable({}, { __mode = "k" }) }

local function set(t, k, v)
  if type(t) ~= "table" then return end
  local seen = journal.seen[t]
  if not seen then seen = {}; journal.seen[t] = seen end
  if not seen[k] then
    seen[k] = true
    journal.list[#journal.list + 1] = { t, k, t[k] }
  end
  t[k] = v
end
RandomData._set = set

function RandomData.restore()
  for i = #journal.list, 1, -1 do
    local e = journal.list[i]
    e[1][e[2]] = e[3]
  end
  journal.list = {}
  journal.seen = setmetatable({}, { __mode = "k" })
  RandomData.applied = false
  RandomData.state = nil
end

function RandomData.journalSize() return #journal.list end

-- ------------------------------------------------------------------ moves --
local BAD_ATTACK = {}
for _, n in ipairs({ "SELFDESTRUCT", "EXPLOSION", "COUNTER", "MIRRORCOAT", "METALBURST", "BIDE",
  "DREAMEATER", "SNORE", "SPITUP", "FAKEOUT", "LASTRESORT", "SYNCHRONOISE", "NATURALGIFT",
  "FLING", "FOCUSPUNCH", "SUCKERPUNCH", "FUTURESIGHT", "DOOMDESIRE", "BEATUP", "ENDEAVOR",
  "FINALGAMBIT", "FISSURE", "GUILLOTINE", "HORNDRILL", "SHEERCOLD", "PRESENT", "BELCH",
  "STRUGGLE", "SKYDROP", "MAGNITUDE" }) do BAD_ATTACK[n] = true end

local TYPE_FIXED = {}
for _, n in ipairs({ "STRUGGLE", "CURSE", "HIDDENPOWER", "WEATHERBALL", "NATURALGIFT",
  "JUDGMENT", "TECHNOBLAST", "BEATUP", "REVELATIONDANCE", "MULTIATTACK" }) do TYPE_FIXED[n] = true end

local function validMove(id, m)
  if type(m) ~= "table" then return false end
  if id == 0 or id == "0" or id == "NO_MOVE" or id == "NONE" then return false end
  if (tonumber(m.pp) or 0) <= 0 then return false end
  local n = englishOf(m, id)
  if n == "" or n == "STRUGGLE" then return false end
  return true
end

local function isDamaging(m)
  if type(m) ~= "table" then return false end
  if (tonumber(m.power) or 0) <= 0 then return false end
  local c = m.class or m.category
  if c == "status" or c == "STATUS" then return false end
  return true
end
RandomData.isDamaging = isDamaging

-- the move pools of a dataset: { all = {ids}, attacks = {ids}, good = {ids},
-- damaging = {[id]=true} }; cached per moves table (power / class changes
-- never move a move between the damaging and status sets)
local moveCache = setmetatable({}, { __mode = "k" })
function RandomData.moveInfo(data)
  prime(data)
  local moves = data and data.moves
  if type(moves) ~= "table" then return { all = {}, attacks = {}, good = {}, damaging = {} } end
  local hit = moveCache[moves]
  if hit then return hit end
  local info = { all = {}, attacks = {}, good = {}, damaging = {} }
  for _, id in ipairs(sortedKeys(moves)) do
    local m = moves[id]
    if validMove(id, m) then
      info.all[#info.all + 1] = id
      if isDamaging(m) then
        info.damaging[id] = true
        info.attacks[#info.attacks + 1] = id
        local acc = tonumber(m.accuracy) or 100
        if not BAD_ATTACK[englishOf(m, id)] and (acc == 0 or acc >= 50) then
          info.good[#info.good + 1] = id
        end
      end
    end
  end
  if #info.good == 0 then info.good = info.attacks end
  moveCache[moves] = info
  return info
end

-- a pick from `list` the `used` set has not seen yet (a few tries)
local function pickFresh(rng, list, used)
  if #list == 0 then return nil end
  local id
  for _ = 1, 10 do
    id = list[rng.int(#list)]
    if not used[id] then break end
  end
  used[id] = true
  return id
end

-- four random moves (at least one good attack, two attacks in all)
function RandomData.randomMoves(data, rm, ...)
  local info = RandomData.moveInfo(data)
  if #info.all == 0 then return nil end
  local rng = Rng(rm and rm.seed or 0, "moves", ...)
  local used, out = {}, {}
  out[1] = pickFresh(rng, info.good, used)
  out[2] = pickFresh(rng, info.all, used)
  out[3] = pickFresh(rng, info.attacks, used)
  out[4] = pickFresh(rng, info.all, used)
  return out
end

-- ------------------------------------------------------------------ items --
local PROTECT = { "FRESHWATER", "SODAPOP", "LEMONADE", "FOSSIL", "AMBER", "PARCEL", "SCOPE",
  "TICKET", "PASS", "KEY", "CARD", "EGG", "LETTER", "GOODS", "ORB", "SECRETPOTION",
  "SQUIRTBOTTLE", "PART", "COUPON", "BICYCLE", "BIKE", "ROD", "TEA", "RADIO", "FLUTE",
  "WING", "BELL", "STONE", "SCALE", "GRACIDEA", "JOURNAL", "HONEY", "SHARD", "PLATE",
  "MASTERBALL", "RARECANDY" }
local PROTECT_EXACT = { MOONSTONE = false }

local function itemName(it, id) return englishOf(it, id) end

local function isMachine(it, kind)
  local m = type(it) == "table" and it.machine
  if type(m) ~= "table" then return false end
  if kind then return m.kind == kind end
  return true
end

local function isKey(it)
  if type(it) ~= "table" then return true end
  if it.keyItem == true and not isMachine(it, "TM") then return true end
  if (tonumber(it.importance) or 0) > 0 then return true end
  local pocket = tostring(it.pocket or "")
  if pocket:upper():find("KEY") then return true end
  if tonumber(it.fieldPocket) == 7 then return true end
  if tonumber(it.bwPocket) == 4 then return true end
  return false
end

-- an item the randomizer never replaces (and never hands out)
function RandomData.protectedItem(data, id)
  prime(data)
  local it = data and data.items and data.items[id]
  if not it then return true end
  if isKey(it) or isMachine(it, "HM") then return true end
  local n = itemName(it, id)
  if PROTECT_EXACT[n] ~= nil then return PROTECT_EXACT[n] end
  for _, p in ipairs(PROTECT) do
    if n:find(p, 1, true) then
      -- a stone that is a plain evolution stone is fine; the rest of the
      -- substrings name story items and their kin
      if p == "STONE" or p == "SCALE" or p == "WING" or p == "BELL" or p == "SHARD"
         or p == "PLATE" then
        if (tonumber(it.price) or 0) <= 0 then return true end
      else
        return true
      end
    end
  end
  return false
end

local function isBall(it, id)
  if type(it) ~= "table" then return false end
  local pocket = tostring(it.pocket or ""):upper()
  if pocket:find("BALL") or tonumber(it.fieldPocket) == 2 then return true end
  return itemName(it, id):sub(-4) == "BALL"
end
RandomData.isBall = isBall

local function isMail(it, id)
  local pocket = tostring(it.pocket or ""):upper()
  if pocket:find("MAIL") or tonumber(it.fieldPocket) == 5 then return true end
  return itemName(it, id):sub(-4) == "MAIL"
end

local function junk(it, id)
  local n = itemName(it, id)
  if n == "" or n:find("TERU", 1, true) or n:find("^ITEM%d") or n == "NONE" then return true end
  if tonumber(it.price) == 39321 then return true end
  return false
end

local itemCache = setmetatable({}, { __mode = "k" })
-- { general = {ids}, tms = {ids}, held = {ids}, balls = {[id]=true} }
function RandomData.itemInfo(data)
  prime(data)
  local items = data and data.items
  if type(items) ~= "table" then return { general = {}, tms = {}, held = {}, balls = {} } end
  local hit = itemCache[items]
  if hit then return hit end
  local info = { general = {}, tms = {}, held = {}, balls = {} }
  for _, id in ipairs(sortedKeys(items)) do
    local it = items[id]
    if type(it) == "table" and id ~= 0 and not junk(it, id) then
      local price = tonumber(it.price) or 0
      if isBall(it, id) then info.balls[id] = true end
      if price > 0 and not RandomData.protectedItem(data, id) then
        if isMachine(it, "TM") then
          info.tms[#info.tms + 1] = id
        elseif not isMachine(it) and not isMail(it, id) then
          info.general[#info.general + 1] = id
          local he = it.holdEffect or it.heldEffect
          if not isBall(it, id) and he ~= nil and he ~= 0 and he ~= "" and he ~= "NONE" then
            info.held[#info.held + 1] = id
          end
        end
      end
    end
  end
  if #info.held < 10 then
    info.held = {}
    for _, id in ipairs(info.general) do
      if not info.balls[id] then info.held[#info.held + 1] = id end
    end
  end
  itemCache[items] = info
  return info
end

-- the replacement for item `id` (a field item, a gift, a mart slot): TMs stay
-- TMs, protected items stay themselves.  `...` keys the pick.
function RandomData.pickItem(data, rm, id, ...)
  if id == nil or RandomData.protectedItem(data, id) then return id end
  local info = RandomData.itemInfo(data)
  local it = data.items[id]
  local list = isMachine(it, "TM") and info.tms or info.general
  if #list == 0 then return id end
  local rng = Rng(rm and rm.seed or 0, "item", tostring(id), ...)
  return list[rng.int(#list)]
end

-- a random held item
function RandomData.pickHeld(data, rm, ...)
  local info = RandomData.itemInfo(data)
  if #info.held == 0 then return nil end
  local rng = Rng(rm and rm.seed or 0, "held", ...)
  return info.held[rng.int(#info.held)]
end

-- -------------------------------------------------------- the data passes --
local function evoTarget(e)
  if type(e) ~= "table" then return nil end
  return e.species or e.into or e.target
end

-- pre-evolution roots, so a family shares its types and abilities
local function familyRoots(pokemon)
  local prevo = {}
  for _, id in ipairs(sortedKeys(pokemon)) do
    local rec = pokemon[id]
    if type(rec) == "table" and type(rec.evolutions) == "table" then
      for _, e in ipairs(rec.evolutions) do
        local t = evoTarget(e)
        if t ~= nil and t ~= 0 and t ~= id and prevo[t] == nil then prevo[t] = id end
      end
    end
  end
  local roots = {}
  for id in pairs(pokemon) do
    local cur, n = id, 0
    while prevo[cur] ~= nil and n < 4 do cur = prevo[cur]; n = n + 1 end
    roots[id] = cur
  end
  return roots
end

local function movesPass(data, rm, opt, report)
  local moves = data.moves
  if type(moves) ~= "table" then return end
  local gen = genOf(data) or 1
  -- type pool and the name -> typeId map, from the original attacks
  local typeSet, typeIds = {}, {}
  local classIds, classCats = {}, {}
  for _, id in ipairs(sortedKeys(moves)) do
    local m = moves[id]
    if validMove(id, m) and isDamaging(m) and m.type ~= nil then
      local tn = norm(m.type)
      if tn ~= "" and tn ~= "CURSET" and tn ~= "QQQ" then typeSet[m.type] = true end
      if m.typeId ~= nil then typeIds[m.type] = typeIds[m.type] or m.typeId end
    end
    if type(m) == "table" and m.class then
      if m.classId ~= nil and classIds[m.class] == nil then classIds[m.class] = m.classId end
      if m.category ~= nil and classCats[m.class] == nil then classCats[m.class] = m.category end
    end
  end
  local typePool = sortedKeys(typeSet)
  local n = 0
  local done = {}
  for _, id in ipairs(sortedKeys(moves)) do
    local m = moves[id]
    if validMove(id, m) and not done[m] then
      done[m] = true
      local name = englishOf(m, id)
      local rng = Rng(rm.seed, "move", tostring(id))
      local dmg = isDamaging(m)
      local power = tonumber(m.power) or 0
      local changed = false
      if opt.movePower and dmg and power > 1 then
        local p
        if power <= 25 then p = 5 * rng.range(2, 8)
        else p = 5 * math.floor((rng.range(20, 150) + rng.range(20, 150)) / 10 + 0.5) end
        set(m, "power", math.max(10, math.min(150, p))); changed = true
      end
      local acc = tonumber(m.accuracy)
      if opt.moveAccuracy and acc and acc > 30 and acc <= 100 then
        local a
        if dmg then a = rng.float() < 0.45 and 100 or 5 * rng.range(14, 20)
        else a = 5 * rng.range(11, 20) end
        set(m, "accuracy", a); changed = true
      end
      if opt.movePP and (tonumber(m.pp) or 0) > 0 then
        set(m, "pp", 5 * rng.range(1, 8)); changed = true
      end
      if opt.moveType and dmg and not TYPE_FIXED[name] and #typePool > 0 then
        local t = typePool[rng.int(#typePool)]
        set(m, "type", t)
        if m.typeId ~= nil and typeIds[t] ~= nil then set(m, "typeId", typeIds[t]) end
        changed = true
      end
      if opt.moveCategory and gen >= 4 and dmg and (m.class == "physical" or m.class == "special") then
        local c = rng.float() < 0.5 and "physical" or "special"
        set(m, "class", c)
        if m.classId ~= nil and classIds[c] ~= nil then set(m, "classId", classIds[c]) end
        if m.category ~= nil and classCats[c] ~= nil then set(m, "category", classCats[c]) end
        changed = true
      end
      if changed then n = n + 1 end
    end
  end
  report.moves = n
end

-- one species' new level-up learnset + level-1 moves
local function newLearnset(rec, id, info, rm, keepLv1)
  local rng = Rng(rm.seed, "learnset", tostring(id))
  local used = {}
  local orig = type(rec.learnset) == "table" and rec.learnset or {}
  local lv1 = type(rec.level1Moves) == "table" and rec.level1Moves or {}
  -- the original level-1 moves, in order
  local firstMoves, seenFirst = {}, {}
  for _, m in ipairs(lv1) do
    if m ~= nil and not seenFirst[m] then seenFirst[m] = true; firstMoves[#firstMoves + 1] = m end
  end
  for _, e in ipairs(orig) do
    local lvl = tonumber(e.level or e[1]) or 1
    local m = e.move or e[2]
    if lvl <= 1 and m ~= nil and not seenFirst[m] then seenFirst[m] = true; firstMoves[#firstMoves + 1] = m end
  end
  local keep
  if keepLv1 then
    for _, m in ipairs(firstMoves) do
      if info.damaging[m] then keep = m break end
    end
  end
  local tr = {}
  local attackPlaced = false
  for i, m in ipairs(firstMoves) do
    local new
    if keep ~= nil and m == keep then
      new = keep; used[keep] = true; attackPlaced = true
    elseif not attackPlaced and (keep == nil) then
      new = pickFresh(rng, info.good, used); attackPlaced = true
    elseif i % 2 == 1 then
      new = pickFresh(rng, info.attacks, used)
    else
      new = pickFresh(rng, info.all, used)
    end
    tr[m] = new
  end
  local learnset = {}
  local j = 0
  if #firstMoves == 0 then
    -- no level-1 move at all: give it one attack at level 1
    learnset[1] = { level = 1, move = pickFresh(rng, info.good, used) }
  end
  for _, e in ipairs(orig) do
    local copy = shallow(e)
    local lvl = tonumber(e.level or e[1]) or 1
    local m = e.move or e[2]
    local new
    if lvl <= 1 and tr[m] ~= nil then
      new = tr[m]
    else
      j = j + 1
      new = (j % 2 == 1) and pickFresh(rng, info.attacks, used) or pickFresh(rng, info.all, used)
    end
    if copy.move ~= nil or copy[2] == nil then copy.move = new else copy[2] = new end
    learnset[#learnset + 1] = copy
  end
  local level1 = {}
  for _, m in ipairs(lv1) do level1[#level1 + 1] = tr[m] or m end
  return learnset, level1
end

local function machineMoves(data)
  local tms, hms, tmSet, hmSet = {}, {}, {}, {}
  local rows = {}
  for _, id in ipairs(sortedKeys(data.items or {})) do
    local it = data.items[id]
    local m = type(it) == "table" and it.machine
    if type(m) == "table" and m.move ~= nil and (m.kind == "TM" or m.kind == "HM") then
      rows[#rows + 1] = { kind = m.kind, num = tonumber(m.number) or tonumber(it.index) or 0, move = m.move, id = id }
    end
  end
  table.sort(rows, function(a, b)
    if a.kind ~= b.kind then return a.kind > b.kind end -- TM before HM
    if a.num ~= b.num then return a.num < b.num end
    return tostring(a.id) < tostring(b.id)
  end)
  for _, r in ipairs(rows) do
    if r.kind == "HM" then
      if not hmSet[r.move] then hmSet[r.move] = true; hms[#hms + 1] = r.move end
    elseif not tmSet[r.move] and not hmSet[r.move] then
      tmSet[r.move] = true; tms[#tms + 1] = r.move
    end
  end
  return tms, tmSet, hms, hmSet
end
RandomData.machineMoves = machineMoves

local function statGroups(bs, gen)
  local groups = {}
  local function add(keys)
    local present = {}
    for _, k in ipairs(keys) do if type(bs[k]) == "number" then present[#present + 1] = k end end
    if #present > 0 then groups[#groups + 1] = present end
  end
  add({ "hp" }); add({ "attack" }); add({ "defense" }); add({ "speed" })
  if gen == 1 or (bs.spatk == nil and bs.spAttack == nil) then
    add({ "special" })
  else
    add({ "spatk", "spAttack", "special" })
    add({ "spdef", "spDefense" })
  end
  return groups
end

-- a species' real base stat total (each stat once, whatever its spellings)
function RandomData.statTotal(rec, gen)
  local bs = type(rec) == "table" and rec.baseStats
  if type(bs) ~= "table" then return 0 end
  local t = 0
  for _, g in ipairs(statGroups(bs, gen or 3)) do t = t + (tonumber(bs[g[1]]) or 0) end
  return t
end

local function baseStatsFor(rec, id, rm, mode, gen)
  local bs = rec.baseStats
  if type(bs) ~= "table" then return nil end
  local groups = statGroups(bs, gen)
  if #groups < 4 then return nil end
  local vals, total = {}, 0
  for i, g in ipairs(groups) do vals[i] = bs[g[1]]; total = total + vals[i] end
  if (bs.hp or 0) <= 1 or total <= 0 then return nil end -- Shedinja, blanks
  local rng = Rng(rm.seed, "stats", tostring(id))
  local new = {}
  if mode == "shuffle" then
    for i = 1, #vals do new[i] = vals[i] end
    for i = #new, 2, -1 do
      local k = rng.int(i)
      new[i], new[k] = new[k], new[i]
    end
  else
    local floor = {}
    local rest = total
    for i = 1, #vals do floor[i] = (i == 1) and 20 or 10; rest = rest - floor[i] end
    if rest < 0 then return nil end
    local w, wsum = {}, 0
    for i = 1, #vals do w[i] = 0.3 + rng.float(); wsum = wsum + w[i] end
    local given = 0
    for i = 1, #vals do
      new[i] = floor[i] + math.floor(rest * w[i] / wsum)
      given = given + new[i]
    end
    new[1] = new[1] + (total - given)
    -- cap at 255, handing the excess on
    for _ = 1, 4 do
      local excess = 0
      for i = 1, #new do if new[i] > 255 then excess = excess + new[i] - 255; new[i] = 255 end end
      if excess == 0 then break end
      for i = 1, #new do
        if excess > 0 and new[i] < 255 then
          local add = math.min(255 - new[i], excess)
          new[i] = new[i] + add; excess = excess - add
        end
      end
    end
  end
  local out = shallow(bs)
  for i, g in ipairs(groups) do
    for _, k in ipairs(g) do out[k] = new[i] end
  end
  return out
end

local BANNED_ABILITY = { WONDERGUARD = true, MULTITYPE = true, FORECAST = true, FLOWERGIFT = true,
  ZENMODE = true, ILLUSION = true, IMPOSTER = true, NONE = true, [""] = true }
local BANNED_ABILITY_ID = { [0] = true, [25] = true, [59] = true, [121] = true, [122] = true,
  [149] = true, [150] = true, [161] = true }

local BAD_TYPE = { [""] = true, QQQ = true, CURSET = true, NONE = true, MYSTERY = true, UNKNOWN = true, BIRD = true }

local function pokemonPass(data, rm, opt, report)
  local pokemon = data.pokemon
  if type(pokemon) ~= "table" then return end
  local gen = genOf(data) or 1
  local ids = sortedKeys(pokemon)
  local roots = familyRoots(pokemon)
  local info = RandomData.moveInfo(data)
  local Randomizer = require("src.runmodes.Randomizer")
  local pool = Randomizer.pool(pokemon, gen)

  -- type pool / ids, ability pools, tutor pool, from the original records
  local typeSet, typeIdOf = {}, {}
  local abilSet, abilIdSet = {}, {}
  local tutorSet = {}
  for _, id in ipairs(ids) do
    local rec = pokemon[id]
    if type(rec) == "table" then
      if type(rec.types) == "table" then
        for i, t in ipairs(rec.types) do
          if not BAD_TYPE[norm(t)] then typeSet[t] = true end
          if type(rec.typeIds) == "table" and rec.typeIds[i] ~= nil and typeIdOf[t] == nil then
            typeIdOf[t] = rec.typeIds[i]
          end
        end
      end
      if type(rec.abilities) == "table" then
        for _, a in ipairs(rec.abilities) do
          if type(a) == "string" and not BANNED_ABILITY[norm(a)] then abilSet[a] = true end
        end
      end
      if type(rec.abilityIds) == "table" then
        for _, a in pairs(rec.abilityIds) do
          if tonumber(a) and not BANNED_ABILITY_ID[tonumber(a)] then abilIdSet[tonumber(a)] = true end
        end
      end
      if type(rec.tutorMoves) == "table" then
        for _, m in ipairs(rec.tutorMoves) do tutorSet[m] = true end
      end
    end
  end
  local typePool = sortedKeys(typeSet)
  local abilPool, abilIdPool = sortedKeys(abilSet), sortedKeys(abilIdSet)
  local tutorPool = sortedKeys(tutorSet)
  local tms, tmSet, _, hmSet = machineMoves(data)

  local counts = { learnsets = 0, tm = 0, tutor = 0, types = 0, abilities = 0, stats = 0, evos = 0, held = 0 }
  local done = {}
  for _, id in ipairs(ids) do
    local rec = pokemon[id]
    if type(rec) == "table" and id ~= 0 and not done[rec] and (tonumber(rec.baseStats and rec.baseStats.hp) or 0) > 0 then
      done[rec] = true
      local root = tostring(roots[id] or id)
      -- LEARNSETS
      if opt.learnsets and #info.all > 0 and (type(rec.learnset) == "table" or type(rec.level1Moves) == "table") then
        local ls, l1 = newLearnset(rec, id, info, rm, opt.keepLv1)
        set(rec, "learnset", ls)
        if type(rec.level1Moves) == "table" then set(rec, "level1Moves", l1) end
        counts.learnsets = counts.learnsets + 1
      end
      -- TM / HM COMPATIBILITY: HMs (and tutor rows) kept, TMs dealt again
      if opt.tmCompat and type(rec.tmhm) == "table" and #tms > 0 then
        local rng = Rng(rm.seed, "tm", tostring(id))
        local kept, nTm = {}, 0
        for _, m in ipairs(rec.tmhm) do
          if tmSet[m] and not hmSet[m] then nTm = nTm + 1 else kept[#kept + 1] = m end
        end
        local p = math.max(0.2, math.min(0.8, nTm / #tms))
        local out = {}
        for _, m in ipairs(tms) do if rng.float() < p then out[#out + 1] = m end end
        for _, m in ipairs(kept) do out[#out + 1] = m end
        set(rec, "tmhm", out)
        counts.tm = counts.tm + 1
      end
      -- TUTORS (FireRed / LeafGreen / Emerald species lists)
      if opt.tutorCompat and type(rec.tutorMoves) == "table" and #tutorPool > 0 then
        local rng = Rng(rm.seed, "tutor", tostring(id))
        local p = math.max(0.2, math.min(0.8, #rec.tutorMoves / #tutorPool))
        local out = {}
        for _, m in ipairs(tutorPool) do if rng.float() < p then out[#out + 1] = m end end
        set(rec, "tutorMoves", out)
        counts.tutor = counts.tutor + 1
      end
      -- TYPES: one pair per family; mono stays mono, dual stays dual
      if opt.types and type(rec.types) == "table" and #typePool > 1 and rec.types[1] ~= nil then
        local rng = Rng(rm.seed, "types", root)
        local t1 = typePool[rng.int(#typePool)]
        local t2 = t1
        for _ = 1, 10 do t2 = typePool[rng.int(#typePool)]; if t2 ~= t1 then break end end
        local o = rec.types
        local dual = o[2] ~= nil and o[2] ~= o[1]
        local nt
        if dual then nt = { t1, t2 } elseif o[2] ~= nil then nt = { t1, t1 } else nt = { t1 } end
        set(rec, "types", nt)
        if rec.type1 ~= nil then set(rec, "type1", t1) end
        if rec.type2 ~= nil then set(rec, "type2", dual and t2 or t1) end
        if type(rec.typeIds) == "table" then
          local ti = {}
          for i = 1, #rec.typeIds do
            local t = (i == 1) and t1 or (dual and t2 or t1)
            ti[i] = typeIdOf[t] ~= nil and typeIdOf[t] or rec.typeIds[i]
          end
          set(rec, "typeIds", ti)
        end
        counts.types = counts.types + 1
      end
      -- ABILITIES: one set per family
      if opt.abilities and gen >= 3 then
        local rng = Rng(rm.seed, "abilities", root)
        local picks = {}
        local function nth(i, list)
          if picks[i] == nil then
            local used = {}
            for k = 1, i - 1 do if picks[k] ~= nil then used[picks[k]] = true end end
            picks[i] = pickFresh(rng, list, used)
          end
          return picks[i]
        end
        if type(rec.abilities) == "table" and #abilPool > 0 and rec.abilities[1] ~= nil then
          local out = {}
          for i, a in ipairs(rec.abilities) do
            if type(a) == "string" and norm(a) ~= "NONE" and norm(a) ~= "" then
              out[i] = nth(i, abilPool)
            else
              out[i] = a
            end
          end
          set(rec, "abilities", out)
          counts.abilities = counts.abilities + 1
        elseif type(rec.abilityIds) == "table" and #abilIdPool > 0 then
          local out = {}
          for i, a in ipairs(rec.abilityIds) do
            if (tonumber(a) or 0) ~= 0 then out[i] = nth(i, abilIdPool) else out[i] = a end
          end
          set(rec, "abilityIds", out)
          counts.abilities = counts.abilities + 1
        end
      end
      -- BASE STATS
      if opt.baseStats then
        local bs = baseStatsFor(rec, id, rm, opt.baseStats, gen)
        if bs then set(rec, "baseStats", bs); counts.stats = counts.stats + 1 end
      end
      -- EVOLUTIONS: same method, a target of about the same strength
      if opt.evolutions and type(rec.evolutions) == "table" and #rec.evolutions > 0 then
        local out = {}
        for i, e in ipairs(rec.evolutions) do
          local copy = type(e) == "table" and shallow(e) or e
          local t = evoTarget(e)
          if type(copy) == "table" and t ~= nil and pokemon[t] ~= nil then
            local h = RunModes.hash(rm.seed, "evo", tostring(id), i)
            local new = Randomizer._pickNear(pool, Randomizer._bst(pokemon[t]), h, { [id] = true }, 12) or t
            if copy.species ~= nil then copy.species = new end
            if copy.into ~= nil then copy.into = new end
            if copy.target ~= nil then copy.target = new end
          end
          out[i] = copy
        end
        set(rec, "evolutions", out)
        counts.evos = counts.evos + 1
      end
      -- WILD HELD ITEMS
      if opt.heldItems and gen >= 3 then
        local rng = Rng(rm.seed, "wildheld", tostring(id))
        local function pick(tag) return RandomData.pickHeld(data, rm, "wild", tostring(id), tag) end
        if rec.heldItemCommon ~= nil or rec.heldItemRare ~= nil then
          if rec.heldItemCommon ~= nil then set(rec, "heldItemCommon", pick("c")) end
          if rec.heldItemRare ~= nil then set(rec, "heldItemRare", pick("r")) end
          counts.held = counts.held + 1
        elseif type(rec.heldItems) == "table" and (rec.heldItems.common ~= nil or rec.heldItems.rare ~= nil) then
          local h = shallow(rec.heldItems)
          local had = (tonumber(h.common) or 0) ~= 0 or (tonumber(h.rare) or 0) ~= 0
          if had or rng.float() < 0.25 then
            h.common = pick("c") or h.common
            if had or rng.float() < 0.5 then h.rare = pick("r") or h.rare end
          end
          set(rec, "heldItems", h)
          counts.held = counts.held + 1
        elseif gen == 3 and type(rec.heldItems) == "table" then
          -- Hoenn's records name the pair by field; an empty pair gets one
          -- now and then, through the fields giveWildHeldItem reads first
          if rng.float() < 0.25 then
            set(rec, "heldItemCommon", pick("c"))
            counts.held = counts.held + 1
          end
        end
      end
    end
  end
  -- Platinum / HeartGold / SoulSilver shard tutors (masks per moveset)
  local tut = data.gen4_move_tutor
  if opt.tutorCompat and type(tut) == "table" and type(tut.masks) == "table" and type(tut.moves) == "table" then
    local nMoves = #tut.moves
    local masks = {}
    for _, k in ipairs(sortedKeys(tut.masks)) do
      local hex = tut.masks[k]
      if type(hex) == "string" and nMoves > 0 then
        local rng = Rng(rm.seed, "g4tutor", tostring(k))
        local bytes = {}
        for b = 1, #hex / 2 do bytes[b] = 0 end
        for i = 1, nMoves do
          local byte = math.floor((i - 1) / 8) + 1
          if byte <= #bytes and rng.float() < 0.4 then
            bytes[byte] = bytes[byte] + 2 ^ ((i - 1) % 8)
          end
        end
        local parts = {}
        for b = 1, #bytes do parts[b] = string.format("%02x", bytes[b]) end
        masks[k] = table.concat(parts)
        if hex:upper() == hex then masks[k] = masks[k]:upper() end
      else
        masks[k] = hex
      end
    end
    set(tut, "masks", masks)
    counts.tutor = counts.tutor + 1
  end
  report.species = counts
end

local function pricesPass(data, rm, report)
  local items = data.items
  if type(items) ~= "table" then return end
  local gen = genOf(data) or 1
  local cap = gen <= 2 and 9990 or 99990
  local n = 0
  local done = {}
  for _, id in ipairs(sortedKeys(items)) do
    local it = items[id]
    local price = type(it) == "table" and tonumber(it.price) or 0
    if price > 0 and not done[it] and not junk(it, id) then
      done[it] = true
      local rng = Rng(rm.seed, "price", tostring(id))
      local f = 2 ^ (rng.float() * 2 - 1)   -- 0.5 .. 2
      if isBall(it, id) then f = math.min(f, 1) end
      local p = price * f
      if p >= 100 then p = math.floor(p / 10 + 0.5) * 10 else p = math.floor(p + 0.5) end
      p = math.max(math.floor(price / 2), math.min(price * 2, p))
      p = math.max(1, math.min(math.max(cap, price), p))
      set(it, "price", p)
      n = n + 1
    end
  end
  report.prices = n
end

local KEEP_CLASS = { "LEADER", "ELITE", "CHAMPION", "RIVAL", "BOSS", "ADMIN", "COMMANDER",
  "BRAIN", "FRONTIER", "TRAINER", "PROF", "GALACTIC", "AQUA", "MAGMA", "ROCKET", "PLASMA",
  "SAGE", "KING", "EXECUTIVE", "GRUNT", "TOWER", "TYCOON", "SUBWAY", "MASTER", "KAHUNA",
  "LEGEND", "HEAD", "BOSS", "SCIENTIST" }

local function keepClass(className)
  local n = norm(className)
  for _, k in ipairs(KEEP_CLASS) do if n:find(k, 1, true) then return true end end
  return false
end

-- PLATINUM'S TRAINER CLASSES THE RANDOMIZER KEEPS, BY CLASS ID (the Leaders,
-- Elite Four, Champion, Galactic admins and boss, Tower Tycoon, Factory Head,
-- the Ace Trainers and the Scientist -- what KEEP_CLASS's words pick out of
-- the English class names).  A class id is the same on every cartridge
-- language; the name is not ("Arenaleiter").
local KEEP_CLASS_ID_PLATINUM = {}
for _, id in ipairs({ 0, 24, 25, 41, 53, 54, 62, 63, 64, 65, 66, 67, 68, 69, 72, 73, 74, 75,
  76, 77, 78, 79, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 100 }) do
  KEEP_CLASS_ID_PLATINUM[id] = true
end

local function keepTrainer(data, t)
  local c = data.constants
  if type(c) == "table" and c.gen == 4 and data.gen4_version == nil and tonumber(t.class) then
    return KEEP_CLASS_ID_PLATINUM[tonumber(t.class)] == true
  end
  return keepClass(t.className)
end

local function trainerNamesPass(data, rm, report)
  local trainers = data.trainers
  if type(trainers) ~= "table" then return end
  local n = 0
  -- Gen 3-5: name per trainer record, shuffled within the class
  local groups = {}
  for _, id in ipairs(sortedKeys(trainers)) do
    local t = trainers[id]
    if type(t) == "table" and type(t.name) == "string" and t.className ~= nil and not keepTrainer(data, t) then
      local nm = norm(t.name)
      if nm ~= "" and #t.name > 1 then
        local key = tostring(t.className)
        groups[key] = groups[key] or { names = {}, seen = {}, recs = {} }
        local g = groups[key]
        if not g.seen[t.name] then g.seen[t.name] = true; g.names[#g.names + 1] = t.name end
        if not g.seen[t] then g.seen[t] = true; g.recs[#g.recs + 1] = t end
      end
    end
  end
  for _, key in ipairs(sortedKeys(groups)) do
    local g = groups[key]
    if #g.names >= 3 then
      table.sort(g.names)
      local perm = {}
      for i, v in ipairs(g.names) do perm[i] = v end
      local rng = Rng(rm.seed, "tnames", key)
      for i = #perm, 2, -1 do local k = rng.int(i); perm[i], perm[k] = perm[k], perm[i] end
      local map = {}
      for i, v in ipairs(g.names) do map[v] = perm[i] end
      for _, t in ipairs(g.recs) do
        if map[t.name] and map[t.name] ~= t.name then set(t, "name", map[t.name]); n = n + 1 end
      end
    end
  end
  -- Gen 2: names inside a class (TrainerGroups party headers)
  local doneT = {}
  for _, id in ipairs(sortedKeys(trainers)) do
    local t = trainers[id]
    if type(t) == "table" and not doneT[t] and type(t.partyNames) == "table" and #t.partyNames >= 3 then
      doneT[t] = true
      local distinct, seen = {}, {}
      for _, v in ipairs(t.partyNames) do
        if type(v) == "string" and not seen[v] then seen[v] = true; distinct[#distinct + 1] = v end
      end
      if #distinct >= 3 then
        table.sort(distinct)
        local perm = {}
        for i, v in ipairs(distinct) do perm[i] = v end
        local rng = Rng(rm.seed, "tnames2", tostring(id))
        for i = #perm, 2, -1 do local k = rng.int(i); perm[i], perm[k] = perm[k], perm[i] end
        local map = {}
        for i, v in ipairs(distinct) do map[v] = perm[i] end
        local out = {}
        for i, v in ipairs(t.partyNames) do out[i] = map[v] or v end
        set(t, "partyNames", out)
        n = n + 1
      end
    end
  end
  report.trainerNames = n
end

-- items lying in the field that the DATA names: Game Boy item balls and
-- hidden items (map objects / bg events / field.hiddenItems), Hoenn's
-- hidden items.  Script-given items are picked at the give (RunHooks.giftItem).
local function fieldItemsPass(data, rm, report)
  local n = 0
  local done = {}
  local function swap(o, key)
    if type(o) ~= "table" or done[o] then return end
    done[o] = true
    local item = o.item
    if item == nil or item == 0 or item == "0" then return end
    if data.items == nil or data.items[item] == nil then return end
    local new = RandomData.pickItem(data, rm, item, "field", key)
    if new ~= item then set(o, "item", new); n = n + 1 end
  end
  if type(data.maps) == "table" then
    for _, mid in ipairs(sortedKeys(data.maps)) do
      local m = data.maps[mid]
      if type(m) == "table" then
        for _, field in ipairs({ "objects", "signs" }) do
          local list = m[field]
          if type(list) == "table" then
            for i, o in ipairs(list) do swap(o, tostring(mid) .. ":" .. field .. ":" .. i) end
          end
        end
      end
    end
  end
  local hidden = data.field and data.field.hiddenItems
  if type(hidden) == "table" then
    for _, mid in ipairs(sortedKeys(hidden)) do
      local list = hidden[mid]
      if type(list) == "table" then
        for i, o in ipairs(list) do swap(o, tostring(mid) .. ":hidden:" .. i) end
      end
    end
  end
  report.fieldItems = n
end

-- apply every data-side option of runModes `rm` to `data` (from the
-- original values: restore first)
function RandomData.apply(data, rm)
  prime(data)
  local report = {}
  if type(data) ~= "table" or type(rm) ~= "table" or rm.seed == nil then return report end
  local opt = {}
  for _, k in ipairs(RandomOptions.DATA_KEYS) do opt[k] = RandomOptions.read(rm, k) end
  opt.keepLv1 = RandomOptions.read(rm, "keepLv1")
  -- the move pools from the ORIGINAL moves (before any stat change)
  RandomData.moveInfo(data)
  RandomData.itemInfo(data)
  if opt.movePower or opt.moveAccuracy or opt.movePP or opt.moveType or opt.moveCategory then
    movesPass(data, rm, opt, report)
  end
  if opt.learnsets or opt.tmCompat or opt.tutorCompat or opt.types or opt.abilities
     or opt.baseStats or opt.evolutions or opt.heldItems then
    pokemonPass(data, rm, opt, report)
  end
  if opt.martPrices then pricesPass(data, rm, report) end
  if opt.trainerNames then trainerNamesPass(data, rm, report) end
  if opt.fieldItems then fieldItemsPass(data, rm, report) end
  RandomData.applied = #journal.list > 0
  RandomData.report = report
  return report
end

-- bring the dataset in line with the live save.  Returns true when the data
-- is randomized for it.
function RandomData.sync(game)
  local data = game and game.data
  local save = game and game.save
  local rm = type(save) == "table" and save.runModes or nil
  local st = RandomData.state
  if type(rm) ~= "table" or not data then
    if st or RandomData.applied then RandomData.restore() end
    return false
  end
  RandomData.game = game
  if st and st.rm == rm and st.rev == RandomOptions.rev and st.seed == rm.seed
     and st.data == data and st.pokemon == data.pokemon and st.moves == data.moves then
    return st.on
  end
  local sig = RandomOptions.anyData(rm) and RandomOptions.signature(rm) or nil
  if st and st.sig == sig and st.data == data and st.pokemon == data.pokemon and st.moves == data.moves then
    st.rm, st.rev, st.seed = rm, RandomOptions.rev, rm.seed
    return st.on
  end
  if st or RandomData.applied then RandomData.restore() end
  local on = false
  if sig then
    local ok, err = pcall(RandomData.apply, data, rm)
    if not ok then
      pcall(function() require("src.core.Logger").warn("randomizer: data pass failed: %s", tostring(err)) end)
      RandomData.restore()
    else
      on = true
    end
  end
  RandomData.state = { rm = rm, rev = RandomOptions.rev, seed = rm.seed, sig = sig, data = data,
                       pokemon = data.pokemon, moves = data.moves, on = on }
  return on
end

-- ------------------------------------------------------------ spoiler log --
local function nameOf(tbl, id)
  local r = tbl and tbl[id]
  return type(r) == "table" and r.name and tostring(r.name) or tostring(id)
end

-- the spoiler log for the live save, as text
function RandomData.spoiler(game)
  local data = game and game.data or {}
  local rm = RunModes.get(game)
  RandomData.sync(game)
  local out = {}
  local function w(s) out[#out + 1] = s end
  w("RANDOMIZER SPOILER LOG")
  w(("seed %s   generation %s"):format(tostring(rm.seed), tostring(genOf(data))))
  w("")
  w("OPTIONS")
  for _, o in ipairs(RandomOptions.LIST) do
    local v = RandomOptions.read(rm, o.key)
    if v then w(("  %-24s %s"):format(o.label, RandomOptions.label(o.key, v))) end
  end
  w("")
  local RunHooks = require("src.runmodes.RunHooks")
  if RunModes.on(rm, "randomStarters") then
    w("STARTERS")
    local set = RunHooks.gameStarters(game)
    local Randomizer = require("src.runmodes.Randomizer")
    for _, sp in ipairs(set) do
      local new = Randomizer.starter({ runModes = rm }, data, sp, set, genOf(data))
      w(("  %s -> %s"):format(nameOf(data.pokemon, sp), nameOf(data.pokemon, new)))
    end
    w("")
  end
  local pokemon = data.pokemon or {}
  local moves = data.moves or {}
  w("POKEMON")
  for _, id in ipairs(sortedKeys(pokemon)) do
    local rec = pokemon[id]
    if type(rec) == "table" and id ~= 0 and (tonumber(rec.baseStats and rec.baseStats.hp) or 0) > 0 then
      local line = { ("%s [%s]"):format(nameOf(pokemon, id), tostring(id)) }
      if type(rec.types) == "table" then line[#line + 1] = "types " .. table.concat(rec.types, "/") end
      if type(rec.abilities) == "table" then line[#line + 1] = "abilities " .. table.concat(rec.abilities, "/") end
      if type(rec.abilityIds) == "table" then line[#line + 1] = "abilityIds " .. table.concat(rec.abilityIds, "/") end
      local bs = rec.baseStats
      if type(bs) == "table" then
        line[#line + 1] = ("stats %s/%s/%s/%s/%s/%s"):format(tostring(bs.hp), tostring(bs.attack),
          tostring(bs.defense), tostring(bs.spatk or bs.special), tostring(bs.spdef or bs.special), tostring(bs.speed))
      end
      w("  " .. table.concat(line, "  "))
      if type(rec.evolutions) == "table" and #rec.evolutions > 0 then
        local ev = {}
        for _, e in ipairs(rec.evolutions) do ev[#ev + 1] = nameOf(pokemon, evoTarget(e)) end
        w("    evolves into " .. table.concat(ev, ", "))
      end
      local ls = {}
      for _, m in ipairs(rec.level1Moves or {}) do ls[#ls + 1] = "1 " .. nameOf(moves, m) end
      for _, e in ipairs(rec.learnset or {}) do
        ls[#ls + 1] = tostring(e.level or e[1]) .. " " .. nameOf(moves, e.move or e[2])
      end
      if #ls > 0 then w("    moves: " .. table.concat(ls, ", ")) end
      if type(rec.tmhm) == "table" then
        local tm = {}
        for _, m in ipairs(rec.tmhm) do tm[#tm + 1] = nameOf(moves, m) end
        w("    TM/HM: " .. table.concat(tm, ", "))
      end
    end
  end
  w("")
  w("MOVES (power / accuracy / pp / type / category)")
  for _, id in ipairs(sortedKeys(moves)) do
    local m = moves[id]
    if validMove(id, m) then
      w(("  %-16s %4s %4s %3s %-10s %s"):format(nameOf(moves, id), tostring(m.power), tostring(m.accuracy),
        tostring(m.pp), tostring(m.type), tostring(m.class or "")))
    end
  end
  if RandomOptions.read(rm, "martPrices") then
    w("")
    w("PRICES")
    for _, id in ipairs(sortedKeys(data.items or {})) do
      local it = data.items[id]
      if type(it) == "table" and (tonumber(it.price) or 0) > 0 and not junk(it, id) then
        w(("  %-20s %s"):format(nameOf(data.items, id), tostring(it.price)))
      end
    end
  end
  w("")
  w("Wild POKéMON, trainer teams, starting moves, held items on trainers, mart stock and")
  w("item gifts are picked when they happen (the same picks for this seed every time).")
  return table.concat(out, "\n")
end

-- write the spoiler log to the save directory; returns the path or nil, err
function RandomData.writeSpoiler(game)
  local text = RandomData.spoiler(game)
  local rm = RunModes.get(game)
  local fs = love and love.filesystem
  if not (fs and fs.write) then return nil, "no filesystem" end
  pcall(fs.createDirectory, "randomizer")
  local path = ("randomizer/spoiler_%s.txt"):format(tostring(rm.seed))
  local ok, err = fs.write(path, text)
  if not ok then return nil, err end
  return path
end

return RandomData
