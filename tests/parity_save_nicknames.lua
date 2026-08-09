-- Parity: Gen1 has no "is nicknamed" bit, so a declined nickname stores the
-- species' own display name in the slot, and the save codec has to translate
-- that both ways (#257).  engine/menus/naming_screen.asm AskName's
-- .declinedNickname copies wNameBuffer over the nickname field, and
-- engine/pokemon/evos_moves.asm RenameEvolvedMon recovers the distinction by
-- comparing the two.  This port models it as mon.nickname == nil.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity save nicknames")
local check, eq = S.check, S.eq

local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local Evolution = require("src.pokemon.Evolution")

local cwData = assert(SaveConvert.loadData(), "save-convert crosswalk data")
local O = GenSave.OFFSETS
local NAME_LENGTH = 11
local charmap = assert(loadfile("src/save_convert/data/charmap.lua"))()

-- ------------------------------------------------------------------
-- Independent name codec, so the byte assertions below cannot inherit an
-- encoder bug from the module under test.  Same rule as GenSave's encodeName:
-- one charmap byte per game character (UTF-8 aware, since names.asm carries
-- the male/female signs), then a single $50 terminator.
-- ------------------------------------------------------------------
local function charsOf(text)
  local out, pos = {}, 1
  while pos <= #text do
    local b0 = text:byte(pos)
    local len = (b0 < 0x80 and 1) or (b0 < 0xE0 and 2) or (b0 < 0xF0 and 3) or 4
    out[#out + 1] = text:sub(pos, pos + len - 1)
    pos = pos + len
  end
  return out
end

local function expectBytes(text)
  local out = {}
  for _, ch in ipairs(charsOf(text)) do
    out[#out + 1] = string.char(charmap.byToken[ch] or charmap.byToken["?"])
  end
  out[#out + 1] = string.char(0x50)
  return table.concat(out)
end

-- the raw nickname slot of party index i (0-based) up to and including its
-- first $50: what a cartridge or PKHeX would read out of the field
local function partyNickSlot(bytes, i)
  local off = O.partyMonNicks + i * NAME_LENGTH
  local raw = bytes:sub(off + 1, off + NAME_LENGTH)
  local term = raw:find("\80", 1, true)
  return term and raw:sub(1, term) or raw
end

local QUESTION = string.char(charmap.byToken["?"])   -- $E6

-- name slots are raw game bytes, so a failure printed verbatim is mojibake;
-- every byte assertion below compares hex so the diff is readable
local function hex(s)
  return (s:gsub(".", function(c) return ("%02X "):format(c:byte()) end)):gsub("%s+$", "")
end

-- ------------------------------------------------------------------
-- 0) the premise: def.name is byte-for-byte the cartridge's own display
-- name (extracted from data/pokemon/names.asm), and the ROM constant is NOT.
-- ------------------------------------------------------------------
-- UTF-8 for U+2642 MALE SIGN / U+2640 FEMALE SIGN, spelled as bytes because
-- LuaJIT is Lua 5.1 and this file should not depend on \u escapes
eq(Data.pokemon.NIDORAN_M.name, "NIDORAN\226\153\130",
   "NIDORAN_M's display name carries the male sign")
eq(Data.pokemon.NIDORAN_F.name, "NIDORAN\226\153\128",
   "NIDORAN_F's display name carries the female sign")
eq(Data.pokemon.MR_MIME.name, "MR.MIME", "MR_MIME's display name is MR.MIME")
eq(Data.pokemon.FARFETCHD.name, "FARFETCH'D", "FARFETCHD's display name keeps its apostrophe")
-- "_" has no glyph in the charmap, so encoding the ROM constant falls back to
-- "?" ($E6): exactly the corruption the old encode wrote out
check(charmap.byToken["_"] == nil,
      "the charmap has no glyph for \"_\", so a ROM constant cannot encode cleanly")
check(expectBytes("NIDORAN_M"):find(QUESTION, 1, true) ~= nil,
      "encoding the constant NIDORAN_M really does produce a \"?\" byte")
check(expectBytes(Data.pokemon.NIDORAN_M.name):find(QUESTION, 1, true) == nil,
      "encoding the display name NIDORAN(male) produces no \"?\" byte")

-- every species name has to survive the charmap exactly, or the equality test
-- the fix rests on mis-fires on some species
local unmappable = {}
for id, def in pairs(Data.pokemon) do
  for _, ch in ipairs(charsOf(def.name or "")) do
    if not charmap.byToken[ch] then unmappable[#unmappable + 1] = id .. ":" .. ch end
  end
end
eq(#unmappable, 0,
   "every species display name maps to real charmap glyphs (" ..
   table.concat(unmappable, ",") .. ")")

-- ------------------------------------------------------------------
-- 1) decode: a stored name equal to the species name is NOT a nickname
-- ------------------------------------------------------------------
-- the nickname field is set explicitly on every fixture, so encode writes
-- those exact characters and the decode half is tested on its own
local function fixtureMon(species, level, storedName)
  local mon = Pokemon.new(Data, species, level)
  mon.nickname = storedName
  mon.ot = "ASH"
  mon.otId = 12345
  mon.catchRate = Data.pokemon[species].catchRate
  return mon
end

local cart = SaveData.newGame({ playerName = "ASH", rivalName = "GARY" })
cart.party = {
  -- the reported case: an un-nicknamed SQUIRTLE, one level short of evolving
  fixtureMon("SQUIRTLE", 15, "SQUIRTLE"),
  -- the control: a genuinely nicknamed one, same species, same level
  fixtureMon("SQUIRTLE", 15, "SHELLY"),
  -- the awkward display names, stored as the cartridge stores them
  fixtureMon("NIDORAN_M", 10, Data.pokemon.NIDORAN_M.name),
  fixtureMon("MR_MIME", 20, Data.pokemon.MR_MIME.name),
  fixtureMon("FARFETCHD", 20, Data.pokemon.FARFETCHD.name),
  -- the trade-evolution pair from the report
  fixtureMon("GRAVELER", 30, "GRAVELER"),
}
cart.boxes = {}
for i = 1, 12 do cart.boxes[i] = {} end
cart.boxes[3] = {
  fixtureMon("KADABRA", 20, "KADABRA"),
  fixtureMon("PIKACHU", 10, "PIKA"),
}
cart.currentBox = 1

local cartBytes = GenSave.encode(cart, cwData, nil)
local imported = assert(SaveConvert.importSav(cartBytes, 2), "cartridge image imports")
local p = imported.party

eq(p[1] and p[1].species, "SQUIRTLE", "party slot 1 is a SQUIRTLE")
eq(p[1] and p[1].nickname, nil,
   "a stored \"SQUIRTLE\" on a SQUIRTLE imports as NOT nicknamed (#257)")
eq(p[2] and p[2].nickname, "SHELLY",
   "a genuine nickname survives import untouched")
eq(p[3] and p[3].nickname, nil,
   "an un-nicknamed NIDORAN(male) imports as NOT nicknamed")
eq(p[4] and p[4].nickname, nil,
   "an un-nicknamed MR.MIME imports as NOT nicknamed")
eq(p[5] and p[5].nickname, nil,
   "an un-nicknamed FARFETCH'D imports as NOT nicknamed")
eq(p[6] and p[6].nickname, nil,
   "an un-nicknamed GRAVELER imports as NOT nicknamed")

local box = imported.boxes[3]
eq(box[1] and box[1].species, "KADABRA", "box 3 slot 1 is a KADABRA")
eq(box[1] and box[1].nickname, nil,
   "the boxed un-nicknamed KADABRA imports as NOT nicknamed")
eq(box[2] and box[2].nickname, "PIKA",
   "a boxed genuine nickname survives import untouched")

-- ------------------------------------------------------------------
-- 2) the payoff: an imported mon renames itself when it evolves
-- ------------------------------------------------------------------
-- RenameEvolvedMon as this port expresses it: the display name is
-- `mon.nickname or def.name`, so a nil nickname follows the species.
local evoGame = {
  data = Data,
  save = { pokedex = { seen = {}, owned = {} } },
}
local function displayName(mon)
  return mon.nickname or Data.pokemon[mon.species].name
end

local plain, named = p[1], p[2]
eq(displayName(plain), "SQUIRTLE", "the imported un-nicknamed mon reads SQUIRTLE before evolving")
eq(displayName(named), "SHELLY", "the imported nicknamed mon reads SHELLY before evolving")
plain.level, named.level = 16, 16
eq(Evolution.pendingLevelEvo(Data, plain), "WARTORTLE", "SQUIRTLE evolves at 16")
Evolution.apply(evoGame, plain, "WARTORTLE", "LEVEL")
Evolution.apply(evoGame, named, "WARTORTLE", "LEVEL")
eq(displayName(plain), "WARTORTLE",
   "an imported un-nicknamed SQUIRTLE reads WARTORTLE after evolving (#257)")
eq(displayName(named), "SHELLY",
   "an imported nicknamed SQUIRTLE keeps SHELLY after evolving")

-- the trade-evolution half: GRAVELER -> GOLEM and KADABRA -> ALAKAZAM, both
-- un-nicknamed on the cartridge
local grav, kad = p[6], box[1]
-- box_struct stores no computed stats (macros/ram.asm: they are recalculated
-- on withdrawal), so a boxed mon decodes without mon.stats; give the KADABRA
-- the stats it would get out of the PC before evolving it
kad.stats = require("src.pokemon.Stats").calc(Data.pokemon.KADABRA, kad.level,
                                              kad.dvs, kad.statExp)
kad.hp = kad.stats.hp
Evolution.apply(evoGame, grav, "GOLEM", "TRADE")
Evolution.apply(evoGame, kad, "ALAKAZAM", "TRADE")
eq(displayName(grav), "GOLEM", "a trade-evolved imported GRAVELER reads GOLEM")
eq(displayName(kad), "ALAKAZAM", "a trade-evolved imported KADABRA reads ALAKAZAM")

-- ------------------------------------------------------------------
-- 3) encode: a nil nickname writes the DISPLAY name, not the ROM constant
-- ------------------------------------------------------------------
local eng = SaveData.newGame({ playerName = "OAK", rivalName = "BLUE" })
local ENG_PARTY = { "NIDORAN_M", "NIDORAN_F", "MR_MIME", "FARFETCHD", "SQUIRTLE" }
eng.party = {}
for _, species in ipairs(ENG_PARTY) do
  local mon = Pokemon.new(Data, species, 10)
  mon.nickname = nil          -- never nicknamed, the engine's own spelling
  mon.ot = "OAK"
  mon.otId = eng.player.id
  mon.catchRate = Data.pokemon[species].catchRate
  eng.party[#eng.party + 1] = mon
end
-- one real nickname in the same image, so the rule cannot regress into
-- dropping every nickname on export
local nicked = Pokemon.new(Data, "PIKACHU", 10)
nicked.nickname = "SPARKY"
nicked.ot = "OAK"
nicked.otId = eng.player.id
eng.party[#eng.party + 1] = nicked

local engBytes = GenSave.encode(eng, cwData, nil)
for i, species in ipairs(ENG_PARTY) do
  local slot = partyNickSlot(engBytes, i - 1)
  local want = expectBytes(Data.pokemon[species].name)
  eq(hex(slot), hex(want),
     species .. " with no nickname exports the cartridge's display name \"" ..
     Data.pokemon[species].name .. "\"")
  check(slot:find(QUESTION, 1, true) == nil,
        species .. "'s exported nickname field holds no \"?\" byte")
end
eq(hex(partyNickSlot(engBytes, #ENG_PARTY)), hex(expectBytes("SPARKY")),
   "a real nickname is exported verbatim")

-- and the loop closes: those exports read back as un-nicknamed
local engBack = assert(SaveConvert.importSav(engBytes, 2), "engine-origin image re-imports")
for i, species in ipairs(ENG_PARTY) do
  eq(engBack.party[i] and engBack.party[i].species, species,
     "engine-origin party slot " .. i .. " is " .. species)
  eq(engBack.party[i] and engBack.party[i].nickname, nil,
     species .. " round-trips through export and import still un-nicknamed")
end
eq(engBack.party[#ENG_PARTY + 1] and engBack.party[#ENG_PARTY + 1].nickname, "SPARKY",
   "SPARKY round-trips through export and import as a real nickname")

-- ------------------------------------------------------------------
-- 4) the box side of the export, same rule
-- ------------------------------------------------------------------
local boxOut = SaveData.newGame({ playerName = "OAK", rivalName = "BLUE" })
boxOut.boxes = {}
for i = 1, 12 do boxOut.boxes[i] = {} end
local boxMon = Pokemon.new(Data, "NIDORAN_F", 12)
boxMon.nickname = nil
boxMon.ot = "OAK"
boxMon.otId = boxOut.player.id
local boxNamed = Pokemon.new(Data, "MR_MIME", 22)
boxNamed.nickname = "MIMEY"
boxNamed.ot = "OAK"
boxNamed.otId = boxOut.player.id
boxOut.boxes[1] = { boxMon, boxNamed }
boxOut.currentBox = 1

local boxBytes = GenSave.encode(boxOut, cwData, nil)
local boxBack = assert(SaveConvert.importSav(boxBytes, 2), "boxed image re-imports")
eq(boxBack.boxes[1][1] and boxBack.boxes[1][1].species, "NIDORAN_F",
   "boxed slot 1 is a NIDORAN(female)")
eq(boxBack.boxes[1][1] and boxBack.boxes[1][1].nickname, nil,
   "a boxed un-nicknamed NIDORAN(female) round-trips still un-nicknamed")
eq(boxBack.boxes[1][2] and boxBack.boxes[1][2].nickname, "MIMEY",
   "a boxed real nickname round-trips untouched")
-- the raw box nickname slot must hold the display name, "?" free
do
  local base = O.curBoxData
  local off = base + 22 + 20 * (33 + NAME_LENGTH)   -- boxMonNicks, slot 0
  local raw = boxBytes:sub(off + 1, off + NAME_LENGTH)
  local term = raw:find("\80", 1, true)
  eq(hex(term and raw:sub(1, term) or raw), hex(expectBytes(Data.pokemon.NIDORAN_F.name)),
     "the boxed NIDORAN(female)'s stored name is the display name, not NIDORAN_F")
end

S.finish()
