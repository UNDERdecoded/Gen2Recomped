-- Gold/Silver battery save import.
--
-- src/save_convert/GenSave.lua is Gen1-only -- its own header says Day Care is
-- "intentionally not modeled", and its badge table is the eight Kanto badges
-- written into save.inventory.  SaveConvert had no generation branch, so a
-- Gold save was decoded with Red's offsets and the two things Gen2 keeps
-- somewhere else entirely went missing: the DAY-CARE pens (wBreedMon1 /
-- wBreedMon2 / the pending EGG) and all sixteen badges (wJohtoBadges /
-- wKantoBadges, which this port spells as save.flags entries).
--
-- This builds a Gold SRAM image byte by byte at the documented offsets --
-- independently of the codec, so decode() is checked against real addresses
-- and not against its own encoder -- then imports it and round-trips it.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; U.log("FAIL " .. name) end
  end

  local Gen2Save = require("src.save_convert.Gen2Save")
  local SaveConvert = require("src.save_convert.SaveConvert")
  local DayCare = require("src.pokemon.DayCare")
  local O = Gen2Save.OFFSETS

  ok(SaveConvert.codecFor("gold") == Gen2Save, "gold routes to the Gen2 codec")
  ok(SaveConvert.codecFor("silver") == Gen2Save, "silver routes to the Gen2 codec")
  ok(SaveConvert.codecFor("red") ~= Gen2Save, "red still routes to the Gen1 codec")

  -- ---------------------------------------------------------------
  -- hand-build a 32768-byte Gold save
  -- ---------------------------------------------------------------
  local buf = {}
  for i = 1, Gen2Save.SAVE_SIZE do buf[i] = "\0" end
  local function put8(off, v) buf[off + 1] = string.char(v % 256) end
  local function put16be(off, v)
    put8(off, math.floor(v / 256)); put8(off + 1, v % 256)
  end
  local function put24be(off, v)
    put8(off, math.floor(v / 65536)); put16be(off + 1, v % 65536)
  end
  -- Gen2 text: "A" is $80, and $50 terminates
  local function putName(off, text)
    local i = 0
    for c in text:gmatch(".") do
      put8(off + i, 0x80 + (c:byte() - ("A"):byte()))
      i = i + 1
    end
    for j = i, 10 do put8(off + j, 0x50) end
  end
  -- box_struct: +0 species, +27 happiness, +31 level
  local function putBoxMon(off, speciesIdx, level, happiness)
    put8(off, speciesIdx)
    put8(off + 27, happiness or 0)
    put8(off + 31, level)
  end

  put8(O.checkValue1, 0x99)
  put8(O.checkValue2, 0x27)
  putName(O.playerName, "GOLD")
  putName(O.rivalName, "SILVER")
  put16be(O.playerId, 0x1234)
  put24be(O.money, 12345)

  -- badges.  Johto bits 0,1,2,3,5 and Kanto bits 0,1 -- deliberately NOT a
  -- solid run, so a decoder that mixed the two bytes up would show it.
  put8(O.johtoBadges, 0x2F)
  put8(O.kantoBadges, 0x03)

  -- EngineFlags rows that are NOT badges and NOT wEventFlags bits:
  -- wPokegearFlags bit 1 (RADIO CARD) + bit 7 (the gear itself), and
  -- wStatusFlags bit 0 (the POKeDEX).  Nothing but the generic row walk
  -- carries these.  Note the bit order: EngineFlags row $00 is the RADIO
  -- card at POKEGEAR_RADIO_CARD_F = 1 and row $01 is the MAP card at
  -- POKEGEAR_MAP_CARD_F = 0, so bit 0 must stay clear here.
  put8(O.pokegearFlags, 0x82)
  put8(O.statusFlags, 0x01)

  -- one party mon: BULBASAUR (species index 1) at level 5
  put8(O.partyCount, 1)
  put8(O.partySpecies, 1)
  put8(O.partySpecies + 1, 0xFF)
  putBoxMon(O.partyMons, 1, 5, 70)
  put16be(O.partyMons + 34, 19)  -- current HP
  put16be(O.partyMons + 36, 20)  -- max HP
  putName(O.partyMonOT, "GOLD")
  putName(O.partyMonNicks, "BULBASAUR")

  -- DAY CARE: the MAN holds PIKACHU (25), the LADY CHARMANDER (4), and an
  -- EGG is waiting.  wDayCareMan bit 0 HAS_MON, bit 6 HAS_EGG, bit 7 ACTIVE.
  put8(O.dayCareMan, 0xC1)
  put8(O.dayCareLady, 0x81)
  put8(O.stepsToEgg, 42)
  putBoxMon(O.breedMon1, 25, 10, 120)
  putName(O.breedMon1Nick, "SPARKY")
  putName(O.breedMon1OT, "GOLD")
  putBoxMon(O.breedMon2, 4, 12, 120)
  putName(O.breedMon2Nick, "CHARMANDER")
  putName(O.breedMon2OT, "GOLD")
  putBoxMon(O.eggMon, 1, 5, 5)   -- 5 remaining cycles = 1280 steps
  putName(O.eggMonNick, "EGG")
  putName(O.eggMonOT, "GOLD")

  -- a saved location, when the cache is new enough to know group/number.
  -- Pick it out of the same table the codec crosswalks against: game.data.maps
  -- carries extra alias keys (ROUTE_2 alongside ROUTE2) that would make an id
  -- comparison ambiguous.
  local mapId, mapDef
  local convData = SaveConvert.loadData("gold")
  for id, def in pairs((convData or {}).maps or {}) do
    if type(def) == "table" and def.group and def.number and not mapId then
      mapId, mapDef = id, def
    end
  end
  if mapDef then
    put8(O.mapGroup, mapDef.group)
    put8(O.mapNumber, mapDef.number)
    put8(O.xCoord, 7)
    put8(O.yCoord, 9)
  end

  -- wVisitedSpawns: mark the first two SpawnPoints rows visited and leave
  -- the third clear, so a decoder that lost the bit -> map pairing shows it
  local spawnFlags = (convData or {}).field and convData.field.spawnFlags
  local flownTo, notFlownTo = {}, nil
  if type(spawnFlags) == "table" then
    for i, entry in ipairs(spawnFlags) do
      if i <= 2 then
        flownTo[#flownTo + 1] = entry.map
        local off = O.visitedSpawns + math.floor(entry.bit / 8)
        buf[off + 1] = string.char(buf[off + 1]:byte()
                                   + 2 ^ (entry.bit % 8))
      elseif not notFlownTo then
        notFlownTo = entry.map
      end
    end
  end

  -- checksum LAST: a plain 16-bit sum of sGameData..sGameDataEnd-1, stored
  -- little-endian at sChecksum
  local sum = 0
  for i = O.checksumStart, O.checksumEnd - 1 do sum = sum + buf[i + 1]:byte() end
  sum = sum % 65536
  put8(O.checksum, sum % 256)
  put8(O.checksum + 1, math.floor(sum / 256))

  local bytes = table.concat(buf)
  ok(#bytes == 32768, "the fixture is 32768 bytes")

  -- ---------------------------------------------------------------
  -- import
  -- ---------------------------------------------------------------
  local save, err = SaveConvert.importSav(bytes, "gold", "gold")
  ok(save ~= nil, "a Gold save imports (" .. tostring(err) .. ")")
  if not save then
    U.log(("driver RESULT pass=%d fail=%d"):format(pass, fail))
    return fail == 0
  end

  ok(save.meta.format == "gen2_import", "it is tagged as a Gen2 import")
  ok(save.player.name == "GOLD", "the player name (" .. tostring(save.player.name) .. ")")
  ok(save.player.rival == "SILVER", "the rival name (" .. tostring(save.player.rival) .. ")")
  ok(save.player.id == 0x1234, "the trainer id")
  ok(save.money == 12345, "money is binary, not BCD (" .. tostring(save.money) .. ")")

  local flags = save.flags or {}
  ok(flags.ZEPHYRBADGE, "ZEPHYRBADGE imported")
  ok(flags.HIVEBADGE, "HIVEBADGE imported")
  ok(flags.PLAINBADGE, "PLAINBADGE imported")
  ok(flags.FOGBADGE, "FOGBADGE imported")
  ok(not flags.MINERALBADGE, "MINERALBADGE (bit 4, clear) stayed clear")
  ok(flags.STORMBADGE, "STORMBADGE imported")
  ok(not flags.GLACIERBADGE, "GLACIERBADGE stayed clear")
  ok(flags.BOULDERBADGE and flags.CASCADEBADGE, "the Kanto badges imported")
  ok(not flags.THUNDERBADGE, "THUNDERBADGE stayed clear")
  local Badges = require("src.inventory.Badges")
  ok(Badges.has(save, { id = "ZEPHYRBADGE" }), "Badges.has agrees")

  local manMon = DayCare.mon(save, DayCare.MAN)
  local ladyMon = DayCare.mon(save, DayCare.LADY)
  ok(manMon ~= nil, "the DAY-CARE MAN's Pokemon imported")
  ok(manMon and manMon.species == "SPECIES_025",
     "it is the right species (" .. tostring(manMon and manMon.species) .. ")")
  ok(manMon and manMon.level == 10, "at the right level")
  ok(manMon and manMon.nickname == "SPARKY", "with its nickname")
  ok(ladyMon ~= nil, "the DAY-CARE LADY's Pokemon imported")
  ok(ladyMon and ladyMon.species == "SPECIES_004", "it is the right species")
  -- an un-nicknamed mon stores its species name, which this port spells as nil
  ok(ladyMon and ladyMon.nickname == nil, "an un-nicknamed mon has no nickname")
  local egg = save.daycare and save.daycare.breed and save.daycare.breed.egg
  ok(egg ~= nil and egg.isEgg == true, "the pending EGG imported")
  ok(egg and egg.eggSteps == 5 * 256, "with its remaining incubation steps")
  ok(save.daycare.breed.steps == 42, "and the shared breeding counter")

  -- the three EngineFlags rows the Route 34 callbacks read
  ok(flags[DayCare.FLAG_MAN_HAS_MON], "FLAG_G2_0006 staged for the MAN")
  ok(flags[DayCare.FLAG_LADY_HAS_MON], "FLAG_G2_0007 staged for the LADY")
  ok(flags[DayCare.FLAG_HAS_EGG], "FLAG_G2_0005 staged for the EGG")

  -- the rest of EngineFlags, which only the generic row walk can carry
  if (convData or {}).field and convData.field.engineFlags then
    ok(#convData.field.engineFlags > 80,
       "the EngineFlags table extracted (" .. #convData.field.engineFlags .. " rows)")
    ok(flags.EVENT_GOT_RADIO_CARD, "the RADIO CARD flag imported")
    ok(flags.EVENT_GOT_POKEGEAR, "the POKeGEAR flag imported")
    ok(flags.EVENT_GOT_POKEDEX, "the POKeDEX flag imported")
    ok(not flags.EVENT_GOT_MAP_CARD, "and a clear Pokegear bit stayed clear")
  else
    U.log("note: this ROM cache predates field.engineFlags, skipping")
  end

  -- the FLY set
  if #flownTo > 0 then
    local visited = save.visited or {}
    ok(visited[flownTo[1]] and visited[flownTo[2]],
       "wVisitedSpawns decoded into save.visited (" .. tostring(flownTo[1])
       .. ", " .. tostring(flownTo[2]) .. ")")
    ok(notFlownTo == nil or not visited[notFlownTo],
       "and an unvisited spawn stayed unvisited")
  else
    U.log("note: this ROM cache predates field.spawnFlags, skipping")
  end

  ok(#save.party == 1, "the party imported")
  ok(save.party[1] and save.party[1].species == "SPECIES_001", "with the right species")
  ok(save.party[1] and save.party[1].hp == 19, "and its current HP")

  if mapId then
    ok(save.player.map == mapId,
       "the saved map resolved from (group, number) -> " .. tostring(save.player.map)
       .. " (expected " .. tostring(mapId) .. " at group " .. tostring(mapDef.group)
       .. ", number " .. tostring(mapDef.number) .. ")")
    ok(save.player.x == 7 and save.player.y == 9, "and the saved coordinates")
  else
    U.log("note: this ROM cache predates map group/number, skipping the map check")
  end

  -- ---------------------------------------------------------------
  -- round trip
  -- ---------------------------------------------------------------
  local out, eerr = SaveConvert.exportSav(save, "gold")
  ok(type(out) == "string" and #out == 32768, "it exports (" .. tostring(eerr) .. ")")
  if type(out) == "string" then
    local back, berr = SaveConvert.importSav(out, "gold", "gold")
    ok(back ~= nil, "the export re-imports, so the checksum is right (" ..
       tostring(berr) .. ")")
    if back then
      ok(back.flags.ZEPHYRBADGE and back.flags.STORMBADGE and back.flags.BOULDERBADGE,
         "badges survive the round trip")
      ok(not back.flags.MINERALBADGE and not back.flags.THUNDERBADGE,
         "and cleared badges stay cleared")
      ok(DayCare.mon(back, DayCare.MAN) ~= nil
         and DayCare.mon(back, DayCare.MAN).species == "SPECIES_025",
         "the MAN's Pokemon survives the round trip")
      ok(DayCare.mon(back, DayCare.LADY) ~= nil
         and DayCare.mon(back, DayCare.LADY).species == "SPECIES_004",
         "the LADY's Pokemon survives the round trip")
      local backEgg = back.daycare and back.daycare.breed and back.daycare.breed.egg
      ok(backEgg ~= nil and backEgg.eggSteps == 5 * 256,
         "the EGG survives the round trip")
      ok(back.money == 12345 and back.player.name == "GOLD",
         "and so do the plain fields")
      if (convData or {}).field and convData.field.engineFlags then
        ok(back.flags.EVENT_GOT_RADIO_CARD and back.flags.EVENT_GOT_POKEDEX,
           "the non-badge EngineFlags survive the round trip")
        ok(not back.flags.EVENT_GOT_MAP_CARD,
           "and a clear one stays clear")
      end
      if #flownTo > 0 then
        ok((back.visited or {})[flownTo[1]] and (back.visited or {})[flownTo[2]],
           "the FLY destinations survive the round trip")
        ok(notFlownTo == nil or not (back.visited or {})[notFlownTo],
           "and an unvisited spawn stays unvisited")
      end
    end
  end

  U.log(("driver RESULT pass=%d fail=%d"):format(pass, fail))
  return fail == 0
end
