-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- tools/gen4_party_check.lua -- can a TM be used in Sinnoh at all.
--
-- THE FAULT THIS EXISTS FOR WAS NOT COSMETIC. The Gen 4 PartyMenu alias did
-- not list `tmhm`, so BagMenu's push was declined; `Screens.resolveId` then
-- returned the GAME BOY id, because a Platinum cache is not a Hoenn one; and
-- whichever screen served it called ItemEffects.use, which scans
-- `speciesDef.tmhm` with a bare `ipairs`. A Gen 4 cache had no such list.
-- USING A TM RAISED.
--
-- So there are three separate things to check and they fail in three different
-- ways: the ALIAS (wrong screen), the LIST (a crash), and the WORDS (the right
-- screen saying Emerald's "NOT ABLE" where Platinum says "UNABLE!").
--
-- Run:  texlua tools/gen4_party_check.lua [cache dir]
--
-- Without a cache only the port's own constants are checked, and it SAYS so.

local cacheDir = arg and arg[1]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

-- A stand-in for everything the screens drag in, EXCEPT the two modules under
-- test. `new` is a real function on purpose: `resolveId` refuses an alias whose
-- module has none, and what is under test here is whether the alias ACCEPTS
-- THE PUSH -- not whether a screen module loads without a graphics device,
-- which it cannot do in a harness and which no player ever asks it to.
local inert = setmetatable({}, { __index = function() return function() end end })
local screenStub = { new = function() return {} end }
table.insert(package.searchers, 1, function(name)
  if name == "src.ui.Screens" then return nil end
  if name == "src.import.Gen4Menus" then return nil end
  if name == "src.import.Gen4Trades" then return nil end
  if name == "src.ui.MenuStyle" then return nil end   -- resolveId calls its real isMenuScreen
  if name:sub(1, 7) == "src.ui." then return function() return screenStub end end
  if name:sub(1, 4) ~= "src." then return nil end
  return function() return inert end
end)

local Screens = require("src.ui.Screens")
local Menus = require("src.import.Gen4Menus")
local Trades = require("src.import.Gen4Trades")

local fails, checks = 0, 0
local function ok(cond, what, got, want)
  checks = checks + 1
  if cond then io.write(("  ok    %-56s %s\n"):format(what, tostring(got)))
  else fails = fails + 1
       io.write(("  FAIL  %-56s got %s, expected %s\n")
                :format(what, tostring(got), tostring(want))) end
end
local function note(line) io.write("  --    " .. line .. "\n") end

-- ------------------------------------------------------------- the alias --

io.write("the party screen on a Gen 4 cache\n")

local gen4Game = { data = { isGen4Cache = true } }

-- THE EXACT PUSH BagMenu.useOn BUILDS FOR A MACHINE. Not a reduced one: the
-- alias declines on ANY unlisted key, so a check that pushes `{tmhm=...}`
-- alone would pass while the real four-key push still fell to Kanto.
local teachPush = {
  pickOnly = true,
  keepOpen = false,
  onSwitch = function() end,
  tmhm = { move = 15, kind = "TM" },
}
local id = Screens.resolveId(gen4Game, "PartyMenu", teachPush)
ok(id == "Gen4PartyMenu", "a TM push opens Platinum's party screen",
   tostring(id), "Gen4PartyMenu")

-- ...and the three pushes that were already served, so a change to the alias
-- cannot fix one by breaking another.
local plain = Screens.resolveId(gen4Game, "PartyMenu", { onCancel = function() end })
ok(plain == "Gen4PartyMenu", "...and so does the plain field push",
   tostring(plain), "Gen4PartyMenu")
local inBattle = Screens.resolveId(gen4Game, "PartyMenu",
                                   { battle = true, onSwitch = function() end })
ok(inBattle == "Gen4PartyMenu", "...and the in-battle one",
   tostring(inBattle), "Gen4PartyMenu")

-- ...and the one the in-game trades push, which is the same two keys the bag's
-- pickers use. If this were declined, Oreburgh's trade would open Kanto's list
-- to choose the Machop on.
local forTrade = Screens.resolveId(gen4Game, "PartyMenu",
                                   { pickOnly = true, onSwitch = function() end })
ok(forTrade == "Gen4PartyMenu", "...and the one the in-game trades open",
   tostring(forTrade), "Gen4PartyMenu")

-- THE CANARY. An alias that served EVERYTHING would pass all three above and
-- would be a different bug: `chooseOrder` has no Gen 4 screen behind it, and
-- serving it would open a party menu that cannot answer the question.
local order = Screens.resolveId(gen4Game, "PartyMenu",
                                { chooseOrder = { most = 3, least = 1 },
                                  onOrder = function() end })
ok(order == "PartyMenu", "...while a team-order push is still declined",
   tostring(order), "PartyMenu")

-- ------------------------------------------------------------- the words --

ok(Menus.PARTY_BANK == 453, "the party words are bank 453",
   Menus.PARTY_BANK, 453)
ok(Menus.PARTY_ENTRIES == 205, "...which is 205 entries",
   Menus.PARTY_ENTRIES, 205)
local T = Menus.PARTY_TEXT
ok(T.able == 175 and T.unable == 176 and T.learned == 177,
   "ABLE! / UNABLE! / LEARNED are 175..177",
   ("%s/%s/%s"):format(tostring(T.able), tostring(T.unable),
                       tostring(T.learned)), "175/176/177")
ok(T.teachWhich == 33, "...and the question is 33", T.teachWhich, 33)
-- The six place words are a RUN, which is the only reason one index and a
-- count can stand in for six named keys.
ok(Menus.PARTY_ORDER_FIRST == 169 and Menus.PARTY_ORDER_WORDS == 6,
   "FIRST..SIXTH are six consecutive entries from 169",
   ("%s+%s"):format(tostring(Menus.PARTY_ORDER_FIRST),
                    tostring(Menus.PARTY_ORDER_WORDS)), "169+6")
-- ...and they must not collide with the three words a panel shows instead.
local clash = false
for _, index in pairs(T) do
  if index >= Menus.PARTY_ORDER_FIRST
     and index < Menus.PARTY_ORDER_FIRST + Menus.PARTY_ORDER_WORDS then
    clash = true
  end
end
ok(not clash, "...and no named word sits inside that run",
   clash and "overlap" or "clear", "clear")

-- ------------------------------------------------------ the machine lists --

if not cacheDir then
  io.write("\n(no cache was checked -- pass a cache dir as the first argument\n"
           .. " to verify the machine lists against real species data)\n")
  io.write(("\n%d checks, %d failures\n"):format(checks, fails))
  os.exit(fails == 0 and 0 or 1)
end

local function load(name)
  local chunk = loadfile(cacheDir .. "/" .. name .. ".lua")
  return chunk and chunk() or nil
end

local mons = load("pokemon")
local consts = load("constants")
local menus = load("gen4_menus")
if not (mons and consts) then
  io.write("\ncannot read pokemon.lua / constants.lua from " .. cacheDir .. "\n")
  os.exit(2)
end

io.write("\nwhich machines each species can learn\n")

local tmhmMoves = consts.tmhmMoves
ok(type(tmhmMoves) == "table" and #tmhmMoves == 100,
   "the cache pairs 100 machines with their moves",
   type(tmhmMoves) == "table" and #tmhmMoves or "nil", 100)

-- The rule, written from CanPokemonFormLearnTM rather than copied from the
-- extractor: bit b of word w is machine w * 32 + b, zero-based. What makes
-- this a check and not a second copy of the same mistake is that its OUTPUT is
-- asserted against species facts nobody's code chose.
local function machinesOf(def)
  local out = {}
  for word = 1, 4 do
    local v = (def.tmLearnset or {})[word] or 0
    for bit = 0, 31 do
      if v % 2 == 1 then out[#out + 1] = (word - 1) * 32 + bit end
      v = math.floor(v / 2)
    end
  end
  return out
end

local highest, stray, walked = -1, 0, 0
for id = 1, 493 do
  local def = mons[id]
  if def and def.tmLearnset then
    walked = walked + 1
    for _, m in ipairs(machinesOf(def)) do
      if m > highest then highest = m end
      if m >= 100 then stray = stray + 1 end
    end
  end
end
ok(walked >= 490, "every species carries a machine mask", walked, ">= 490")
-- 100 MACHINES IN 128 BITS leaves 28 spare, and they are spare in the
-- cartridge too. A wrong word order or a flipped bit order scatters set bits
-- into that tail; a right one leaves it empty.
ok(highest == 99, "the highest machine bit set anywhere is HM08", highest, 99)
ok(stray == 0, "...and nothing is set in the 28 spare bits", stray, 0)

-- THE TWO SPECIES THAT LEARN NOTHING. "Exactly zero" is not a result a wrong
-- reading produces -- it produces a plausible handful.
local function count(id) return #machinesOf(mons[id] or {}) end
ok(count(129) == 0 and count(132) == 0,
   "MAGIKARP and DITTO come out with no machines at all",
   ("%d/%d"):format(count(129), count(132)), "0/0")
ok(count(1) > 20 and count(25) > 20,
   "...while BULBASAUR and PIKACHU come out with a full sheet",
   ("%d/%d"):format(count(1), count(25)), "> 20 each")
-- ...ending in the three HMs Bulbasaur actually learns, which is the tail a
-- one-off word swap would move.
local bulba = machinesOf(mons[1] or {})
local tail = {}
for _, m in ipairs(bulba) do if m >= 92 then tail[#tail + 1] = m - 91 end end
ok(#tail == 3 and tail[1] == 1 and tail[2] == 4 and tail[3] == 6,
   "...and BULBASAUR's are HM01, HM04 and HM06",
   #tail > 0 and table.concat(tail, ",") or "none", "1,4,6")

-- STORED VERSUS DERIVED. A cache imported before the extractor learned to
-- unpack the mask has no `tmhm` at all, and that is REPORTED rather than
-- failed -- it is the state every cache was in until this was written.
local stored, mismatched = 0, 0
for id = 1, 493 do
  local def = mons[id]
  if def and type(def.tmhm) == "table" then
    stored = stored + 1
    local want = machinesOf(def)
    if #want ~= #def.tmhm then mismatched = mismatched + 1
    else
      for i, m in ipairs(want) do
        if tmhmMoves[m + 1] ~= def.tmhm[i] then mismatched = mismatched + 1 break end
      end
    end
  end
end
if stored == 0 then
  note("this cache predates the machine-list stage: no species carries `tmhm`,")
  note("so ItemEffects falls back to \"cannot learn\". One more import fixes it.")
else
  ok(mismatched == 0, "every stored list matches the mask it came from",
     ("%d of %d"):format(stored - mismatched, stored), "all")
end

-- ---------------------------------------------------------- the words, live --

local record = menus and menus.partyMenu
if not record then
  note("this cache predates the party-word stage: the screen falls back to")
  note("the engine's own English until the next import.")
else
  local said = record.text or {}
  ok(said.able == "ABLE!" and said.unable == "UNABLE!"
     and said.learned == "LEARNED",
     "the cache says Platinum's three words, not Emerald's",
     ("%s/%s/%s"):format(tostring(said.able), tostring(said.unable),
                         tostring(said.learned)),
     "ABLE!/UNABLE!/LEARNED")
  ok(type(said.teachWhich) == "string" and said.teachWhich:find("each"),
     "...and asks the cartridge's own question",
     tostring(said.teachWhich), "Teach which ...?")
  ok(#(record.order or {}) == 6 and record.order[1] == "FIRST"
     and record.order[6] == "SIXTH",
     "...and carries FIRST..SIXTH for the day something needs them",
     #(record.order or {}), 6)
end

io.write("\nthe four in-game trades\n")

-- THE RECORD IS TWENTY WORDS AND NOTHING ELSE SAYS SO. There is no length
-- field, no terminator and no name in the archive; the only thing that makes
-- 80 bytes the right stride is that the struct has twenty u32 in it. Counting
-- the field list against the byte count is the whole check on the layout.
ok(#Trades.FIELDS == 20, "struct NPCTradeMon is twenty fields",
   #Trades.FIELDS, 20)
ok(Trades.RECORD_BYTES == #Trades.FIELDS * 4,
   "...which is exactly the record's byte count",
   Trades.RECORD_BYTES, #Trades.FIELDS * 4)
ok(Trades.COUNT == 4, "MAX_NPC_TRADES is four", Trades.COUNT, 4)
ok(#Trades.IV_FIELDS == 6, "six IVs, in Pokemon_SetValue's order",
   #Trades.IV_FIELDS, 6)
-- Every IV field must be one of the twenty, or the IV list is naming something
-- the record does not have.
local haveField = {}
for _, f in ipairs(Trades.FIELDS) do haveField[f] = true end
local strayIV = {}
for _, f in ipairs(Trades.IV_FIELDS) do
  if not haveField[f] then strayIV[#strayIV + 1] = f end
end
ok(#strayIV == 0, "...and every one of them is a field of the record",
   #strayIV == 0 and "all six" or table.concat(strayIV, ", "), "all six")

-- THE OT NAME IS THE SAME BANK PLUS THE TRADE COUNT, which is one line in
-- NPCTrade_GetOTName and the reason eight entries serve four trades. Asserted
-- as the RULE rather than as four numbers, and then checked for overlap --
-- an off-by-one here would hand a Pokemon its own nickname as its OT.
local overlap = false
for id = 0, Trades.COUNT - 1 do
  if Trades.otNameEntry(id) ~= Trades.COUNT + id then overlap = true end
  if Trades.otNameEntry(id) < Trades.COUNT then overlap = true end
  if Trades.nicknameEntry(id) >= Trades.COUNT then overlap = true end
end
ok(not overlap, "the OT names sit past the nicknames, four apart",
   overlap and "overlap" or "0..3 then 4..7", "0..3 then 4..7")

ok(Trades.otGender(1) == "girl" and Trades.otGender(0) == "boy",
   "otGender 1 is FEMALE, the way TrainerInfo_SetGender takes it",
   ("%s/%s"):format(Trades.otGender(1), Trades.otGender(0)), "girl/boy")
-- ...and a canary, because a converter that answered one value for everything
-- would pass every line that only checks one side.
ok(Trades.otGender(1) ~= Trades.otGender(0),
   "...and it still has two answers", "two", "two")

-- A short record is REFUSED rather than read as nils. A truncated member means
-- the archive is not this one, and a trade with no species would be offered
-- and silently refuse itself.
local short = Trades.parse(string.rep("\0", Trades.RECORD_BYTES - 1))
ok(short == nil, "a short record is refused, not read", tostring(short), "nil")
local full = Trades.parse(string.rep("\1", Trades.RECORD_BYTES))
ok(type(full) == "table" and full.requestedSpecies ~= nil,
   "...and a full one reads the last field",
   type(full) == "table" and tostring(full.requestedSpecies) or "nil",
   "a number")

local rows = consts.gen4Trades
if type(rows) ~= "table" or #rows == 0 then
  note("this cache predates the trade stage: constants.gen4Trades is absent,")
  note("so the four trades refuse themselves until the next import.")
else
  ok(#rows == Trades.COUNT, "the cache carries all four", #rows, Trades.COUNT)
  -- THE PAIRS READ AS THEMSELVES, which is the check that the twenty-word
  -- layout is right: a wrong field order does not produce Platinum's four
  -- trades, it produces four plausible-looking numbers.
  local mons = load("pokemon") or {}
  local function nameOf(id)
    local d = mons[id]
    return (d and d.name) or ("#" .. tostring(id))
  end
  local WANT = {
    { give = "ABRA", want = "MACHOP", nick = "Kazza", ot = "Hilary" },
    { give = "CHATOT", want = "BUIZEL", nick = "Charap", ot = "Norton" },
    { give = "HAUNTER", want = "MEDICHAM", nick = "Gaspar", ot = "Mindy" },
    { give = "MAGIKARP", want = "FINNEON", nick = "Foppa", ot = "Meister" },
  }
  local wrong = {}
  for i, w in ipairs(WANT) do
    local r = rows[i] or {}
    if nameOf(r.species) ~= w.give or nameOf(r.request) ~= w.want then
      wrong[#wrong + 1] = ("%d gives %s for %s"):format(i - 1,
        nameOf(r.species), nameOf(r.request))
    end
    if r.nickname ~= w.nick or r.otName ~= w.ot then
      wrong[#wrong + 1] = ("%d is %s of %s"):format(i - 1,
        tostring(r.nickname), tostring(r.otName))
    end
  end
  ok(#wrong == 0, "...and every one is the trade the cartridge has",
     #wrong == 0 and "4 of 4" or table.concat(wrong, " | "), "4 of 4")
  -- The IVs are the record's, and they are GEN 3 RANGE. Data.lua puts Gen 4
  -- species on the Gen 3 stat model, so a traded Pokemon carries `ivs` at
  -- 0..31; a value above 31 would mean the field order slipped and an OT id
  -- or a personality landed in an IV slot.
  local badIV = 0
  for _, r in ipairs(rows) do
    for _, v in ipairs(r.ivs or {}) do
      if type(v) ~= "number" or v < 0 or v > 31 then badIV = badIV + 1 end
    end
  end
  ok(badIV == 0, "...with all 24 IVs inside 0..31", badIV, 0)
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
