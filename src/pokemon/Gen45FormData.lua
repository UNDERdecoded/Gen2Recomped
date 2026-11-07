-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- ALTERNATE FORMS' MECHANICS, OUT OF BATTLE (Platinum, HGSS, Black / White).
-- The pictures were already imported by form (Gen4Forms / Gen4Otherpoke,
-- def.gen5FormSprites); this module is what makes stats, types, abilities
-- and the field's form changes follow the form too. Battle-side rules live in
-- src/battle/Gen45FormBattle.lua.
--
-- PER-FORM PERSONAL DATA
--   Gen 4: READ pokeplatinum Pokemon_GetFormNarcIndex / pokeheartgold
--     ResolveMonForm -- Deoxys 496-498, Wormadam 499-500, Giratina 501,
--     Shaymin 502, Rotom 503-507 (already imported; Gen4Forms.definition).
--   BW: READ Black arm9 0x0201AFD4 (species, form) -> personal index: the
--     species' record +0x1C (first form row) and +0x20 (form count); form 0,
--     a 0 at +0x1C or form >= count keeps the species, else +0x1C + form - 1.
--     The rows past 649 are the cache's gen5_forms (RomExtractorGen5); tag
--     gen5-form-personal-v1 adds their own learnsets. Rows: Deoxys 650-652,
--     Wormadam 653-654, Shaymin 655, Giratina 656, Rotom 657-661, Castform
--     662-664, Basculin 665, Darmanitan 666, Meloetta 667 (668 = padding).
-- ARCEUS / MULTITYPE
--   READ Pt pokemon.c MON_DATA_TYPE_1/2 + Pokemon_GetArceusTypeOf, HGSS
--   GetArceusTypeByHeldItemEffect, BW arm9 0x020192C4 (species 0x1ED with
--   ability 0x79 -> 0x02019BBC(item - 298) = a BW type id): Arceus with
--   Multitype is its Plate's type, Normal without one. The form is that type
--   id (Pt BoxPokemon_SetArceusForm; BW INFERRED: no form setter located,
--   the form-sprite order Fighting..Dark matches the type ids).
-- GENESECT'S DRIVES
--   READ Black ov093 0x021E324C: item 116 Douse -> Water / form 1, 117 Shock
--   -> Electric / 2, 118 Burn -> Fire / 3, 119 Chill -> Ice / 4. The party
--   form following the held Drive is INFERRED (the field setter was not
--   located).
-- GIRATINA: READ Pt BoxPokemon_SetGiratinaForm (Origin exactly while it
--   holds the Griseous Orb, 112) -- Gen4Forms.giratinaByHeldItem. BW the same
--   item rule (INFERRED: no Distortion World).
-- SHAYMIN
--   READ Pt Party_SetShayminForm (sub_02055B64, the field's minute update;
--   HGSS Party_TryResetShaymin): a Sky Forme party Shaymin turns back to Land
--   Forme when the clock passes 20:00 or 04:00. pc_boxes.c PCBoxes_TryStore*
--   (Land on storing), daycare (Gen4DayCare, already), Gracidea
--   (Pokemon_CanShayminSkyForm: Land, HP > 0, not frozen, 04:00-19:59 --
--   fateful-encounter bit not kept by the port). BW: the same rules
--   INFERRED; the in-battle freeze revert is READ (Gen45FormBattle).

local M = {}

M.ARCEUS, M.GENESECT, M.GIRATINA, M.SHAYMIN = 493, 649, 487, 492
M.GRISEOUS_ORB = 112

-- the Plates, item id -> type name (READ above; same ids on all three games)
M.PLATE_TYPE = {
  [298] = "FIRE", [299] = "WATER", [300] = "ELECTRIC", [301] = "GRASS",
  [302] = "ICE", [303] = "FIGHTING", [304] = "POISON", [305] = "GROUND",
  [306] = "FLYING", [307] = "PSYCHIC", [308] = "BUG", [309] = "ROCK",
  [310] = "GHOST", [311] = "DRAGON", [312] = "DARK", [313] = "STEEL",
}
-- the Drives, item id -> { type, Genesect form } (READ ov093 0x021E324C)
M.DRIVE = {
  [116] = { "WATER", 1 }, [117] = { "ELECTRIC", 2 }, [118] = { "FIRE", 3 }, [119] = { "ICE", 4 },
}
-- type ids: Gen 4 keeps ??? at 9, Black / White has none
M.TYPE_ID4 = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5,
  BUG = 6, GHOST = 7, STEEL = 8, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13,
  PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17 }
M.TYPE_ID5 = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5,
  BUG = 6, GHOST = 7, STEEL = 8, FIRE = 9, WATER = 10, GRASS = 11, ELECTRIC = 12,
  PSYCHIC = 13, ICE = 14, DRAGON = 15, DARK = 16 }

local function gen(data) return ((data or {}).constants or {}).gen end
local function speciesId(s)
  return tonumber(s) or tonumber(tostring(s or ""):match("(%d+)$"))
end
M.speciesId = speciesId
local function itemOf(mon)
  local id = mon and (mon.item or mon.heldItem)
  if type(id) ~= "number" then id = tonumber(tostring(id or ""):match("(%d+)$")) end
  if id == 0 then return nil end
  return id
end
M.itemOf = itemOf
local function isEgg(mon) return mon and (mon.isEgg or mon.egg) and true or false end

-- the type a Plate / Drive gives (Judgment, Techno Blast, Multitype)
function M.heldType(itemId)
  local d = M.DRIVE[itemId]
  return M.PLATE_TYPE[itemId] or (d and d[1]) or nil
end

-- ---------------------------------------------------------------------------
-- BW form rows
-- ---------------------------------------------------------------------------
-- the BW ability NAMES Abilities.lua dispatches on (as Gen5MoveEffects'
-- prepareSpecies names the species' own)
local function abilityName(id)
  id = tonumber(id)
  if not id or id == 0 then return nil end
  if id <= 123 then
    local ok, G4A = pcall(require, "src.import.Gen4Abilities")
    if ok and G4A.NAMES then return G4A.NAMES[id] end
  end
  local ok, G5 = pcall(require, "src.battle.Gen5MoveEffects")
  return ok and G5.ABILITIES_5 and G5.ABILITIES_5[id] or nil
end
M.abilityName = abilityName

-- READ arm9 0x0201AFD4
function M.bwPersonalIndex(base, species, form)
  form = tonumber(form) or 0
  local first = tonumber(base and base.formStatsIndex) or 0
  local count = tonumber(base and base.formCount) or 0
  if first == 0 or form == 0 or form >= count then return species end
  return first + form - 1
end

local BW_KEYS = { "baseStats", "types", "typeIds", "abilityIds", "evYield", "evYields",
  "heldItems", "weight", "height", "machineBits", "tmhm", "learnset", "baseExp",
  "catchRate", "genderRatio", "expRate", "growthRate" }
local bwCache = setmetatable({}, { __mode = "k" })

local function bwView(data, base, mon)
  local id = speciesId(mon.species)
  local index = M.bwPersonalIndex(base, id, mon.form)
  if index == id then return base end
  local rows = data.gen5_forms
  local alt = type(rows) == "table" and rows[index]
  if type(alt) ~= "table" then return base end
  local perBase = bwCache[base]
  if not perBase then perBase = {}; bwCache[base] = perBase end
  local view = perBase[index]
  if view then return view end
  view = {}
  for k, v in pairs(base) do view[k] = v end
  for _, k in ipairs(BW_KEYS) do if alt[k] ~= nil then view[k] = alt[k] end end
  if type(alt.abilityIds) == "table" then
    local a, b = abilityName(alt.abilityIds[1]), abilityName(alt.abilityIds[2])
    if a then view.abilities = { a, b or a, abilityName(alt.abilityIds[3]) } end
  end
  view.formPersonalIndex = index
  perBase[index] = view
  return view
end

-- ---------------------------------------------------------------------------
-- Arceus: its type is its Plate's while it has Multitype
-- ---------------------------------------------------------------------------
local function hasMultitype(def, mon)
  local list = def and def.abilities
  local slot = tonumber(mon and mon.abilitySlot) or 1
  local a = type(list) == "table" and (list[slot] or list[1]) or nil
  if a == "MULTITYPE" then return true end
  local ids = def and def.abilityIds
  return type(ids) == "table" and tonumber(ids[slot] or ids[1]) == 121 or false
end
M.hasMultitype = hasMultitype

local arceusCache = setmetatable({}, { __mode = "k" })
local function arceusView(def, mon)
  if not hasMultitype(def, mon) then return def end
  local t = M.PLATE_TYPE[itemOf(mon) or -1] or "NORMAL"
  local cur = def.types
  if type(cur) == "table" and #cur == 1 and cur[1] == t then return def end
  local per = arceusCache[def]
  if not per then per = {}; arceusCache[def] = per end
  if per[t] then return per[t] end
  local view = {}
  for k, v in pairs(def) do view[k] = v end
  view.types = { t }
  per[t] = view
  return view
end

-- Gen4Forms.definition's post-step (installed at the foot of Gen4Forms.lua):
-- `plain` is the Gen 4 lookup it had before.
function M.definition(data, mon, plain)
  local def = plain(data, mon)
  if not (def and mon) then return def end
  local g = gen(data)
  if g == 5 then
    local id = speciesId(mon.species)
    local registry = data and data.pokemon or {}
    local base = registry[mon.species] or registry[id]
    if base and tonumber(mon.form) and mon.form > 0 then def = bwView(data, base, mon) or def end
  end
  if (g == 4 or g == 5) and speciesId(mon.species) == M.ARCEUS then def = arceusView(def, mon) end
  return def
end

-- ---------------------------------------------------------------------------
-- held-item forms: Giratina, Arceus, Genesect
-- ---------------------------------------------------------------------------
function M.arceusForm(data, mon)
  local t = M.PLATE_TYPE[itemOf(mon) or -1] or "NORMAL"
  return (gen(data) == 5 and M.TYPE_ID5 or M.TYPE_ID4)[t] or 0
end

-- re-applied wherever a held item can have changed (Bag give / take, the box)
function M.heldItem(data, mon)
  if type(mon) ~= "table" or isEgg(mon) then return nil end
  local g = gen(data)
  if g ~= 4 and g ~= 5 then return nil end
  local Forms = require("src.pokemon.Gen4Forms")
  local id = speciesId(mon.species)
  local want
  if id == M.GIRATINA then
    want = itemOf(mon) == M.GRISEOUS_ORB and 1 or 0
  elseif id == M.ARCEUS then
    local def = (data.pokemon or {})[mon.species] or (data.pokemon or {})[id]
    if not hasMultitype(def, mon) then return nil end
    want = M.arceusForm(data, mon)
  elseif id == M.GENESECT and g == 5 then
    local d = M.DRIVE[itemOf(mon) or -1]
    want = d and d[2] or 0
  else
    return nil
  end
  if (tonumber(mon.form) or 0) ~= want then Forms.setForm(data, mon, want) end
  return want
end

-- ---------------------------------------------------------------------------
-- Shaymin
-- ---------------------------------------------------------------------------
local function landAll(data, list)
  local n = 0
  for _, mon in pairs(list or {}) do
    if type(mon) == "table" and speciesId(mon.species) == M.SHAYMIN
       and (tonumber(mon.form) or 0) ~= 0 and not isEgg(mon) then
      require("src.pokemon.Gen4Forms").setForm(data, mon, 0)
      n = n + 1
    end
  end
  return n
end
M.landAll = landAll

-- Pokemon_CanShayminSkyForm (the Gracidea)
function M.canSky(mon, hour)
  hour = hour or tonumber(os.date("%H")) or 12
  return mon and speciesId(mon.species) == M.SHAYMIN and (tonumber(mon.form) or 0) == 0
    and (tonumber(mon.hp) or 0) > 0 and not isEgg(mon)
    and not (mon.status == "FRZ" or mon.status == "freeze")
    and hour >= 4 and hour < 20 or false
end

-- did the clock pass 20:00 or 04:00 in (from, to] (epoch seconds)?
function M.crossedBoundary(from, to)
  if not (from and to) or to <= from then return false end
  if to - from >= 86400 then return true end
  local d = os.date("*t", from)
  for day = 0, 2 do
    for _, h in ipairs({ 4, 20 }) do
      local t = os.time({ year = d.year, month = d.month, day = d.day + day, hour = h, min = 0, sec = 0 })
      if t > from and t <= to then return true end
    end
  end
  return false
end

-- the field's minute update: Sky Forme back to Land at 20:00 / 04:00, and
-- (pc_boxes.c) no Sky Forme kept in a box
function M.poll(game, now)
  local data, save = game and game.data, game and game.save
  local g = gen(data)
  if not save or (g ~= 4 and g ~= 5) then return end
  now = now or os.time()
  local last = tonumber(save.g45FormClock)
  if last and M.crossedBoundary(last, now) then landAll(data, save.party) end
  -- a clock set back only moves the stamp (inline_020559DC)
  save.g45FormClock = now
  for _, box in pairs(save.boxes or {}) do
    if type(box) == "table" then landAll(data, box) end
  end
end

-- ---------------------------------------------------------------------------
-- Burmy's cloak: the terrain of the battle it took part in
-- ---------------------------------------------------------------------------
-- READ Pt BattleSystem_SetBurmyForm (battle_system.c), at the end of every
-- battle but link / frontier / safari / Pal Park, for each party Burmy whose
-- participation bit is set
M.BURMY = 412
M.BURMY_FORM = {
  grass = 0,
  plain = 1, sand = 1, mountain = 1, cave = 1, distortion_world = 1, giratina = 1,
  building = 2, bridge = 2, aaron = 2, bertha = 2, flint = 2, lucian = 2, cynthia = 2,
  battle_tower = 2, battle_factory = 2, battle_arcade = 2, battle_castle = 2, battle_hall = 2,
}
function M.burmyForm(terrain) return M.BURMY_FORM[terrain or ""] or 0 end
-- Black / White: key -> cloak, READ ov010 0x02172554 (25 { u16 key, u16 form })
M.BW_BURMY_KEY = { [0] = 1, 1, 2, 2, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0, 2, 2, 2, 2, 2, 2, 2, 1, 0, 0, 2 }

return M
