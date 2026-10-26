-- Private native preset builder (CreateMonWithGenderNatureLetter).
-- Unlike an ordinary encounter, this draws only candidate PID words: no
-- random IVs/DVs, learnset moves or shiny-odds roll. Specs use cartridge IDs.
local Stats = require("src.pokemon.Stats")
local Identity = require("src.pokemon.IdentityRolls")
local M = {}

local function resolve(data, registry, orderName, number)
  local rows = data[registry] or {}
  local order = (data.constants or {})[orderName] or {}
  local id = order[number]
  if id ~= nil and rows[id] then
    return id, rows[id]
  end
  local found
  for key, row in pairs(rows) do
    if tonumber(row.index) == number then
      assert(found == nil or rows[found] == row, "ambiguous native " .. registry .. " ID " .. number)
      found = key
    end
  end
  assert(found ~= nil, "missing native " .. registry .. " ID " .. number)
  return found, rows[found]
end

function M.new(data, spec, rng)
  assert(
    type(spec.nature) == "number" and spec.nature % 1 == 0 and spec.nature >= 0 and spec.nature < 25,
    "native preset requires a nature ID in 0..24"
  )
  assert(
    spec.gender == "male" or spec.gender == "female" or spec.gender == "unknown",
    "native preset requires a gender"
  )
  local species, def = resolve(data, "pokemon", "speciesOrder", spec.species)
  assert(Stats.isGen3(def), "native preset requires a Gen-3 species")
  local constants = data.constants or {}
  local nature = (constants.natureOrder or {})[spec.nature + 1]
  if nature == nil then
    for id, row in pairs(constants.natures or {}) do
      if tonumber(row.index) == spec.nature then
        nature = id
        break
      end
    end
  end
  assert(nature ~= nil, "missing native nature ID " .. tostring(spec.nature))
  local ball = resolve(data, "items", "itemOrder", 4)
  local moves = {}
  for _, number in ipairs(spec.moves) do
    if number ~= 0 then
      local id, move = resolve(data, "moves", "moveOrder", number)
      moves[#moves + 1] = { id = id, pp = move.pp, maxPp = move.pp }
    end
  end
  rng = rng or love.math.random
  local mon = {
    species = species,
    level = spec.level,
    metLevel = spec.level,
    nature = nature,
    ball = ball,
    growthRate = def.growthRate,
    catchRate = def.catchRate,
    moves = moves,
    ivs = {},
    evs = {},
    friendship = def.friendship or 70,
    happiness = def.friendship or 70,
  }
  repeat
    -- Random32 consumes the low word first. Gender is evaluated only for
    -- matching natures, including the public hook's rejection/override policy.
    local lo, hi = rng(0, 65535), rng(0, 65535)
    mon.personality = lo + hi * 65536
  until mon.personality % 25 == spec.nature and Identity.gender(data, mon, 3) == spec.gender
  mon.gender = spec.gender
  local abilities = def.abilities or {}
  mon.abilitySlot = abilities[2] and mon.personality % 2 + 1 or 1
  mon.ability = abilities[mon.abilitySlot]
  for _, stat in ipairs(Stats.ORDER_GEN3) do
    mon.ivs[stat], mon.evs[stat] = 0, 0
  end
  -- Native nature effects follow the PID's 0..24 matrix, independently of
  -- global preview state or translated nature registry keys.
  mon.stats = Stats.calcGen3(def, spec.level, mon.ivs, mon.evs)
  local order = { "attack", "defense", "speed", "spatk", "spdef" }
  local up, down = math.floor(spec.nature / 5) + 1, spec.nature % 5 + 1
  if up ~= down then
    mon.stats[order[up]] = math.floor(mon.stats[order[up]] * 1.1)
    mon.stats[order[down]] = math.floor(mon.stats[order[down]] * 0.9)
  end
  mon.stats.special, mon.hp = mon.stats.spatk, mon.stats.hp
  mon.exp = require("src.pokemon.Growth").expForLevel(def.growthRate, spec.level)
  return mon
end
return M
