-- The four Ruins of Alph chamber walls (engine/events/unown_walls.asm).
--
-- Each underground chamber carries a word in Unown script on its wall, and
-- each word is an INSTRUCTION, not decoration -- do the thing it says while
-- standing in that chamber and the wall grinds open on a hidden room:
--
--   ESCAPE  Kabuto      use an ESCAPE ROPE here
--   LIGHT   Aerodactyl  use FLASH here
--   WATER   Omanyte     carry a WATER STONE (bag or held)
--   HO-OH   Ho-Oh       have HO-OH at the head of the party
--
-- The chambers' own scripts already do everything downstream of that: the
-- scene script checks EVENT_WALL_OPENED_IN_<X>_CHAMBER on entry and defers the
-- earthquake-and-open cutscene, and MAPCALLBACK_TILES keeps the wall open on
-- later visits (see maps/RuinsOfAlph*Chamber.asm). Those are ROM scripts the VM
-- already runs. The only missing pieces were the four specials that SET the
-- flag, which is why the writing on the wall read as flavour text.
--
-- Two of the four are script specials the chamber's scene script calls
-- (HoOhChamber, OmanyteChamber -- data/events/special_pointers.asm). The other
-- two are called from the engine's own item and field-move code, because their
-- trigger IS the item: the escape-rope branch of ItemUseEscapeRope farcalls
-- SpecialKabutoChamber (engine/events/overworld.asm:809) and
-- FlashFunction.CheckUseFlash farcalls SpecialAerodactylChamber (:285).
--
-- Flag indices verified against constants/event_flags.asm; the parse that
-- produced them independently reproduces EVENT_MADE_UNOWN_APPEAR_IN_RUINS = 46,
-- which src/script/Gen2Flags.lua already carries at that index.

local Gen2Flags = require("src.script.Gen2Flags")

local RuinsOfAlph = {}

RuinsOfAlph.EVENTS = {
  hooh = 806,        -- EVENT_WALL_OPENED_IN_HO_OH_CHAMBER
  kabuto = 807,      -- EVENT_WALL_OPENED_IN_KABUTO_CHAMBER
  omanyte = 808,     -- EVENT_WALL_OPENED_IN_OMANYTE_CHAMBER
  aerodactyl = 809,  -- EVENT_WALL_OPENED_IN_AERODACTYL_CHAMBER
}

RuinsOfAlph.MAPS = {
  hooh = "RUINS_OF_ALPH_HO_OH_CHAMBER",
  kabuto = "RUINS_OF_ALPH_KABUTO_CHAMBER",
  omanyte = "RUINS_OF_ALPH_OMANYTE_CHAMBER",
  aerodactyl = "RUINS_OF_ALPH_AERODACTYL_CHAMBER",
}

-- Gen 2 item ids are ROM-numbered at runtime (`ITEM_%03d`, see
-- RomExtractorGen2), so the stone is ITEM_024 rather than a name. Matched by
-- the record's own `index` where the data is loaded, so a rebuilt cache or a
-- mod that renames the item still resolves; the literals are the fallback.
RuinsOfAlph.WATER_STONE_INDEX = 24
local WATER_STONE_IDS = { WATER_STONE = true, ITEM_024 = true }

local function isWaterStone(data, id)
  if id == nil then return false end
  if WATER_STONE_IDS[id] then return true end
  local def = data and data.items and data.items[id]
  return def ~= nil and tonumber(def.index) == RuinsOfAlph.WATER_STONE_INDEX
end

function RuinsOfAlph.opened(save, which)
  local index = RuinsOfAlph.EVENTS[which]
  if not (save and save.flags and index) then return false end
  return save.flags[Gen2Flags.eventFlag(index)] == true
end

-- Set the wall flag. The cutscene is NOT played here: the chamber's scene
-- script owns that and runs it the next time the map loads, which is what the
-- cartridge does too (you use the rope, you leave, and the wall has opened when
-- you come back).
function RuinsOfAlph.openWall(save, which)
  local index = RuinsOfAlph.EVENTS[which]
  if not (save and index) then return false end
  save.flags = save.flags or {}
  local key = Gen2Flags.eventFlag(index)
  if save.flags[key] == true then return false end
  save.flags[key] = true
  return true
end

local function currentMap(game)
  local ow = game and game.overworld
  local map = ow and ow.map
  return map and map.id or nil
end

-- HoOhChamber: is HO-OH the FIRST party member (`ld hl, wPartySpecies` reads
-- slot one only -- carrying it in any other slot does nothing).
function RuinsOfAlph.hoOhChamber(game)
  local save = game and game.save
  local lead = save and save.party and save.party[1]
  if not (lead and lead.species == "HO_OH") then return false end
  return RuinsOfAlph.openWall(save, "hooh")
end

-- OmanyteChamber: a WATER STONE in the bag, or held by any party member.
-- Returns early when the wall is already open, as the ROM does.
function RuinsOfAlph.omanyteChamber(game)
  local save = game and game.save
  if not save then return false end
  if RuinsOfAlph.opened(save, "omanyte") then return false end
  local data = game.data
  for id, qty in pairs(save.inventory or {}) do
    if (tonumber(qty) or 0) > 0 and isWaterStone(data, id) then
      return RuinsOfAlph.openWall(save, "omanyte")
    end
  end
  for _, mon in ipairs(save.party or {}) do
    if isWaterStone(data, mon.item) then
      return RuinsOfAlph.openWall(save, "omanyte")
    end
  end
  return false
end

-- SpecialKabutoChamber / SpecialAerodactylChamber: both check that the player
-- is standing in their own chamber and then set the flag. Returns true when
-- this is that chamber -- which for Aerodactyl is the carry flag
-- CheckUseFlash tests to allow FLASH outside a dark cave.
local function chamberHere(game, which)
  if currentMap(game) ~= RuinsOfAlph.MAPS[which] then return false end
  RuinsOfAlph.openWall(game.save, which)
  return true
end

function RuinsOfAlph.kabutoChamber(game)
  return chamberHere(game, "kabuto")
end

function RuinsOfAlph.aerodactylChamber(game)
  return chamberHere(game, "aerodactyl")
end

return RuinsOfAlph
