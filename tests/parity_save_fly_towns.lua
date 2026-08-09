-- Parity test: imported saves keep their FLY town set (#263).  pokered's
-- wTownVisitedFlag (ram/wram.asm:2057) is a NUM_CITY_MAPS = 11 bit array whose
-- bit index IS the town's map number, LSB first: town_map.asm
-- BuildFlyLocationsList does `srl d / rr e` with b counting up from 0, so bit 0
-- is map 0 = PALLET_TOWN.  src/save_convert/GenSave.lua never modeled it, so an
-- imported .sav arrived with save.visited == nil and FLY offered one town.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity save fly towns")
local check, eq = S.check, S.eq

local bit = require("bit")
local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local FlyMenu = require("src.ui.FlyMenu")

-- loadData() hands back the crosswalk set GenSave wants ({pokemon, moves,
-- items, maps, eventFlags}) and installs the charmap as a side effect
local cwData = assert(SaveConvert.loadData(), "save-convert crosswalk data")
local O = GenSave.OFFSETS

-- ------------------------------------------------------------------
-- The wTownVisitedFlag offset, re-derived here rather than read off
-- GenSave.OFFSETS: a suite trusting the codec's own constant cannot fail when
-- that constant is wrong.  O.mainData mirrors wMainDataStart, and the flag sits
-- 1044 bytes in -- 359 past wPlayerCoins (mainData + 685) and 60 before
-- wEventFlags (mainData + 1104), both of which predate this fix.
-- ------------------------------------------------------------------
local TOWN_VISITED = O.mainData + 1044
local NUM_CITY_MAPS = 11

-- Independent re-implementation of CalcCheckSum (complement of the additive
-- byte sum, engine/menus/save.asm), so a hand-poked image can be re-sealed
-- without going back through the encoder under test.
local function rawChecksum(bytes, from, to)
  local sum = 0
  for i = from, to - 1 do sum = bit.band(sum + bytes:byte(i + 1), 0xFF) end
  return bit.band(bit.bnot(sum), 0xFF)
end

local function reseal(bytes)
  local ck = rawChecksum(bytes, O.checksumStart, O.checksumEnd)
  return bytes:sub(1, O.mainChecksum) .. string.char(ck)
         .. bytes:sub(O.mainChecksum + 2)
end

-- write the two wTownVisitedFlag bytes straight into an image, the way a
-- cartridge would have left them, and re-seal so importSav accepts it
local function pokeTownBytes(bytes, b0, b1)
  return reseal(bytes:sub(1, TOWN_VISITED) .. string.char(b0, b1)
                .. bytes:sub(TOWN_VISITED + 3))
end

local function townBytesOf(bytes)
  return bytes:byte(TOWN_VISITED + 1), bytes:byte(TOWN_VISITED + 2)
end

-- ------------------------------------------------------------------
-- 1) the bit-index-is-the-map-index premise, straight off generated data
-- ------------------------------------------------------------------
-- data/generated/maps.lua carries pokered's map constant order, so indices 0..10
-- must be PALLET_TOWN..SAFFRON_CITY, the same 11 the flag_array covers.  An
-- extractor that renumbered them would leave every bit assertion meaningless.
local TOWN_BY_BIT = {}
for id, def in pairs(Data.maps) do
  if type(def.index) == "number" and def.index >= 0
     and def.index < NUM_CITY_MAPS then
    TOWN_BY_BIT[def.index] = id
  end
end
local EXPECTED_ORDER = {
  [0] = "PALLET_TOWN", "VIRIDIAN_CITY", "PEWTER_CITY", "CERULEAN_CITY",
  "LAVENDER_TOWN", "VERMILION_CITY", "CELADON_CITY", "FUCHSIA_CITY",
  "CINNABAR_ISLAND", "INDIGO_PLATEAU", "SAFFRON_CITY",
}
for i = 0, NUM_CITY_MAPS - 1 do
  eq(TOWN_BY_BIT[i], EXPECTED_ORDER[i],
     ("map index %d is %s (wTownVisitedFlag bit %d)"):format(i, EXPECTED_ORDER[i], i))
end

local function bitsFor(set)
  local b0, b1 = 0, 0
  for i = 0, NUM_CITY_MAPS - 1 do
    if set[TOWN_BY_BIT[i]] then
      if i < 8 then b0 = bit.bor(b0, bit.lshift(1, i))
      else b1 = bit.bor(b1, bit.lshift(1, i - 8)) end
    end
  end
  return b0, b1
end

-- ------------------------------------------------------------------
-- 2) decode: the town bits become save.visited
-- ------------------------------------------------------------------

local fresh = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
fresh.flags = { EVENT_GOT_POKEDEX = true, EVENT_GOT_STARTER = true }
fresh.money = 54321
local base = GenSave.encode(fresh, cwData, nil)
eq(#base, GenSave.SAVE_SIZE, "baseline image is 32768 bytes")

-- the reported case: a completed cartridge save, all eleven bits set
local completed = pokeTownBytes(base, 0xFF, 0x07)
local compSave, compErr = SaveConvert.importSav(completed, 2)
check(compSave ~= nil, "a completed-cartridge image imports (" .. tostring(compErr) .. ")")
check(type(compSave and compSave.visited) == "table",
      "an imported save arrives with a visited table, not nil (#263)")
local compVisited = (compSave and compSave.visited) or {}
local compCount = 0
for _ in pairs(compVisited) do compCount = compCount + 1 end
eq(compCount, NUM_CITY_MAPS,
   "all eleven towns come back visited from a full wTownVisitedFlag")
for i = 0, NUM_CITY_MAPS - 1 do
  check(compVisited[EXPECTED_ORDER[i]] == true,
        EXPECTED_ORDER[i] .. " is visited on a completed save")
end
-- decode must stop at bit 10: ROUTE_1 is map index 12 and can never be a
-- FLY town, so a loop that ran past NUM_CITY_MAPS would show up here
check(compVisited.ROUTE_1 == nil,
      "a route never lands in the visited set (the loop stops at NUM_CITY_MAPS)")

-- the reported 3DS VC save: Cerulean and Fuchsia visited, Celadon and Saffron
-- not.  Bits 0,1,2,3,7 -> 0x8F 0x00.
local partialSet = {
  PALLET_TOWN = true, VIRIDIAN_CITY = true, PEWTER_CITY = true,
  CERULEAN_CITY = true, FUCHSIA_CITY = true,
}
local pb0, pb1 = bitsFor(partialSet)
eq(pb0, 0x8F, "bits 0,1,2,3,7 pack LSB-first into byte 0 = 0x8F")
eq(pb1, 0x00, "no town above bit 7 is set, so byte 1 = 0x00")
local partial = pokeTownBytes(base, pb0, pb1)
local partSave = assert(SaveConvert.importSav(partial, 2), "partial image imports")
local partVisited = partSave.visited or {}
for id in pairs(partialSet) do
  check(partVisited[id] == true, id .. " decodes as visited")
end
check(partVisited.CELADON_CITY == nil,
      "CELADON_CITY was never visited and does not come back visited")
check(partVisited.SAFFRON_CITY == nil,
      "SAFFRON_CITY was never visited and does not come back visited")
check(partVisited.INDIGO_PLATEAU == nil,
      "INDIGO_PLATEAU was never visited and does not come back visited")

-- ------------------------------------------------------------------
-- 3) the offset is right: poking the town bytes disturbs nothing else
-- ------------------------------------------------------------------
-- An offset a few bytes off still "works" for the checks above while quietly
-- corrupting a neighbour: wEventFlags starts 60 bytes later, wPlayerCoins 359
-- earlier, so re-decode the poked image and confirm both survived.
local baseDec = GenSave.decode(base, cwData)
local compDec = GenSave.decode(completed, cwData)
eq(#compDec.warnings, 0, "the re-sealed image passes its own checksum")
eq(compDec.money, baseDec.money, "poking wTownVisitedFlag leaves money alone")
check(compDec.flags.EVENT_GOT_POKEDEX and compDec.flags.EVENT_GOT_STARTER,
      "poking wTownVisitedFlag leaves the event flags alone")
local baseFlagCount, compFlagCount = 0, 0
for _ in pairs(baseDec.flags) do baseFlagCount = baseFlagCount + 1 end
for _ in pairs(compDec.flags) do compFlagCount = compFlagCount + 1 end
eq(compFlagCount, baseFlagCount,
   "setting all eleven town bits sets no event flag (the arrays do not overlap)")

-- ------------------------------------------------------------------
-- 4) encode: the set goes back out in pokered's bit layout
-- ------------------------------------------------------------------
-- Hand-picked so an MSB-first writer cannot pass: PALLET is bit 0 and
-- FUCHSIA bit 7 (byte 0 = 0x81), SAFFRON is bit 10 (byte 1 = 0x04).
local outSave = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
outSave.visited = {
  PALLET_TOWN = true, FUCHSIA_CITY = true, SAFFRON_CITY = true,
}
local outBytes = GenSave.encode(outSave, cwData, nil)
local ob0, ob1 = townBytesOf(outBytes)
eq(ob0, 0x81, "PALLET (bit 0) + FUCHSIA (bit 7) write byte 0 = 0x81")
eq(ob1, 0x04, "SAFFRON (bit 10) writes byte 1 = 0x04")

-- and the full loop the reporter cares about: cartridge -> port -> cartridge
local rtBytes = GenSave.encode(compSave, cwData, nil)
local r0, r1 = townBytesOf(rtBytes)
eq(r0, 0xFF, "a completed save exports byte 0 = 0xFF")
eq(r1, 0x07, "a completed save exports byte 1 = 0x07")
local rtSave = assert(SaveConvert.importSav(reseal(rtBytes), 2),
                      "the exported image re-imports")
local rtVisited = rtSave.visited or {}
for i = 0, NUM_CITY_MAPS - 1 do
  check(rtVisited[EXPECTED_ORDER[i]] == true,
        EXPECTED_ORDER[i] .. " survives export and re-import")
end

-- A save with no `visited` key says nothing about the set, so encoding over a
-- template keeps the template's bits rather than un-flying it on the way back
-- to hardware.
local silent = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
silent.visited = nil
local kept = GenSave.encode(silent, cwData, completed)
local k0, k1 = townBytesOf(kept)
eq(k0, 0xFF, "a save with no visited key keeps the template's byte 0")
eq(k1, 0x07, "a save with no visited key keeps the template's byte 1")

-- ------------------------------------------------------------------
-- 5) the payoff: the real FLY picker lists them
-- ------------------------------------------------------------------
-- src/ui/FlyMenu.lua walks data.field.flyOrder and keeps the entries in
-- save.visited, so this is the list the player sees under FLY.  Before #263 an
-- imported save reached it with visited == nil and the list came back empty.
local function flyLabels(save)
  local menu = FlyMenu.new({ data = Data, save = save })
  local out = {}
  for _, item in ipairs(menu.items or {}) do out[#out + 1] = item.value end
  return out
end

local compList = flyLabels(compSave)
eq(#compList, NUM_CITY_MAPS,
   "FLY on a completed imported save lists all eleven destinations")
-- flyOrder puts the towns in map-constant order after the dungeon escape
-- spots, which is the order the picker shows
for i = 0, NUM_CITY_MAPS - 1 do
  eq(compList[i + 1], EXPECTED_ORDER[i],
     ("FLY entry %d is %s"):format(i + 1, EXPECTED_ORDER[i]))
end

local partList = flyLabels(partSave)
eq(#partList, 5, "FLY on the partial save lists exactly the five visited towns")
local partSeen = {}
for _, id in ipairs(partList) do partSeen[id] = true end
check(partSeen.CERULEAN_CITY and partSeen.FUCHSIA_CITY,
      "Cerulean AND Fuchsia are both offered (the reported 3DS VC case)")
check(not partSeen.CELADON_CITY and not partSeen.SAFFRON_CITY,
      "unvisited towns stay out of the FLY list")

-- negative control, the pre-#263 shape: no visited table is an empty picker
local blank = SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
blank.visited = nil
eq(#flyLabels(blank), 0, "a save with no visited set has no FLY destinations")

S.finish()
