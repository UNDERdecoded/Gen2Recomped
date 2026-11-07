-- GEN 4 / GEN 5 POKEDEX SIGHTINGS BEYOND SEEN / CAUGHT: which genders were
-- seen (and in which order), Spinda's first-seen spots, and (Black / White)
-- the genders x shininess sighting quartet. Called from Gen4Forms.record, the
-- one hook every "a Pokemon was seen / obtained" path already runs through.
--
-- READ FROM CODE:
--   * pokeplatinum src/pokedex.c Pokedex_Encounter / Pokedex_Capture: on the
--     FIRST sighting SetForm_Spinda (the personality) and UpdateGender(gender,
--     FALSE) -- which writes BOTH recordedGenders[0] and [1]; on a later
--     sighting, if the gender differs from slot 0, UpdateGender(gender, TRUE)
--     writes slot 1 only. GENDER_NONE is recorded as GENDER_MALE.
--   * GetDisplayGender / pokeheartgold Pokedex_SpeciesGetLastSeenGender_
--     Internal: a genderless species shows "genderless" for slot 0 and nothing
--     for slot 1; slot 1 counts only when it differs from slot 0.
--   * pokeheartgold ov18_021E8254 / ov18_021E83D0: the FORMS page of every
--     species without tracked forms lists slot 0's gender, then slot 1's when
--     it differs.
--   * Black (Gen5Save decode, block dex +0x5C + r * 0x54, r = 0..3): the seen
--     bits are kept per male / female / shiny male / shiny female.
-- INFERRED: Black and White record gender the same first / second way for
-- the dex picture (their dex is not disassembled here).

local R = {}

local function speciesId(species)
  return tonumber(species) or tonumber(tostring(species or ''):match('(%d+)$'))
end

-- 0 male, 1 female (GENDER_NONE recorded as male), or nil for no answer.
local function genderBit(data, mon)
  local g = require('src.pokemon.Pokemon').genderOf(data, mon)
  if g == 'female' then return 1 end
  return 0
end

local function genderless(data, id)
  local def = data and data.pokemon and data.pokemon[id]
  local ratio = def and tonumber(def.genderRatio)
  return ratio == 255
end

function R.record(game, species, mon)
  if not (game and game.data and game.save and mon) then return end
  local gen = (game.data.constants or {}).gen
  if gen ~= 4 and gen ~= 5 then return end
  if require('src.pokemon.Party').isEgg(mon) then return end
  local dex = game.save.pokedex
  local id = speciesId(species)
  if not (dex and id) then return end
  dex.genders = dex.genders or {}
  local g = genderBit(game.data, mon)
  local slot = dex.genders[id]
  -- `seen` is already set by the caller on some paths, so the first sighting
  -- is "no gender record yet" rather than "not seen".
  if not slot then
    dex.genders[id] = { g, g }
    if id == 327 and mon.personality then
      dex.spinda = dex.spinda or {}
      dex.spinda[id] = mon.personality
    end
  elseif slot[1] ~= g then
    slot[2] = g
  end
  -- HGSS PICHU (pokeheartgold pokedex.c UpdateForm / Pokedex_SetSeenForm_
  -- 3max): form 0 is recorded as 0 male / 1 female, the Spiky-eared form
  -- (MON_DATA_FORM 1) as 2, each once, in the order first seen
  if gen == 4 and id == 172 then
    local okV, V = pcall(require, "src.core.GameVersion")
    if okV and (V.info() or {}).family == "hgss" then
      local form = tonumber(mon.form) or 0
      local v = form ~= 0 and 2 or g
      dex.hgssPichuForms = dex.hgssPichuForms or {}
      local seen = false
      for _, x in ipairs(dex.hgssPichuForms) do if x == v then seen = true end end
      if not seen and #dex.hgssPichuForms < 3 then table.insert(dex.hgssPichuForms, v) end
    end
  end
  if gen == 5 then
    -- BW forms seen per species, in first-seen order (INFERRED: the BW dex
    -- keeps form bits; their layout is not read). Read by nothing yet.
    local fi = tonumber(mon.form)
    if fi then
      dex.gen5FormsSeen = dex.gen5FormsSeen or {}
      local list = dex.gen5FormsSeen[id] or {}
      dex.gen5FormsSeen[id] = list
      local have = false
      for _, x in ipairs(list) do if x == fi then have = true end end
      if not have then list[#list + 1] = fi end
    end
    dex.gen5Seen = dex.gen5Seen or {}
    local bits = dex.gen5Seen[id] or 0
    local shiny = require('src.pokemon.Pokemon').isShiny(mon) and 2 or 0
    local bit = 2 ^ (g + shiny)
    if math.floor(bits / bit) % 2 == 0 then bits = bits + bit end
    dex.gen5Seen[id] = bits
  end
end

-- The gender the dex shows for slot `idx` (0 the first seen, 1 the other):
-- "male", "female", "none" (genderless species, slot 0), or nil.
function R.displayGender(game, species, idx)
  local id = speciesId(species)
  local data = game and game.data
  local dex = game and game.save and game.save.pokedex
  if not (id and dex) then return nil end
  if genderless(data, id) then return idx == 0 and 'none' or nil end
  local slot = dex.genders and dex.genders[id]
  if not slot then return nil end
  if idx == 1 then
    if slot[2] == nil or slot[2] == slot[1] then return nil end
    return slot[2] == 1 and 'female' or 'male'
  end
  return slot[1] == 1 and 'female' or 'male'
end

-- The genders seen, in the dex's order (ov18_021E8254 default case).
function R.gendersSeen(game, species)
  local out = {}
  for idx = 0, 1 do
    local g = R.displayGender(game, species, idx)
    if g then out[#out + 1] = g end
  end
  return out
end

return R
