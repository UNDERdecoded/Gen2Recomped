-- A Pokémon instance (plain table so it serializes straight into the save).

local Growth = require("src.pokemon.Growth")
local Stats = require("src.pokemon.Stats")

local Pokemon = {}

-- Starting moves: level-1 moves plus learnset entries at or below the level,
-- keeping the most recent four (engine/pokemon/learn_move.asm behavior).
function Pokemon.movesAtLevel(speciesDef, level)
  local moves = {}
  local function add(id)
    for _, existing in ipairs(moves) do
      if existing == id then return end
    end
    table.insert(moves, id)
  end
  for _, m in ipairs(speciesDef.level1Moves) do
    add(m)
  end
  for _, entry in ipairs(speciesDef.learnset) do
    if entry.level <= level then
      add(entry.move)
    end
  end
  while #moves > 4 do
    table.remove(moves, 1)
  end
  return moves
end

-- Day Care retrieve (pokered WriteMonMoves + wLearningMovesFromDayCare):
-- grant learnset moves with startLevel < moveLevel <= newLevel, shifting
-- the oldest slot out when full. Silent -- no LearnMove prompts.
function Pokemon.learnMovesFromDayCare(data, mon, speciesDef, startLevel, newLevel)
  if not (speciesDef and speciesDef.learnset and mon) then return end
  mon.moves = mon.moves or {}
  for _, entry in ipairs(speciesDef.learnset) do
    local moveLevel = entry.level
    if moveLevel > newLevel then break end
    if moveLevel > startLevel then
      local known = false
      for _, mv in ipairs(mon.moves) do
        if mv.id == entry.move then known = true break end
      end
      if not known then
        local mdef = data.moves[entry.move]
        local slot = { id = entry.move, pp = mdef and mdef.pp or 0 }
        if #mon.moves < 4 then
          mon.moves[#mon.moves + 1] = slot
        else
          table.remove(mon.moves, 1)
          mon.moves[#mon.moves + 1] = slot
        end
      end
    end
  end
end

function Pokemon.new(data, species, level, rng)
  local def = data.pokemon[species]
  assert(def, "unknown species " .. tostring(species))
  local dvs = Stats.randomDVs(rng)
  local stats = Stats.calc(def, level, dvs)
  local moves = {}
  for _, id in ipairs(Pokemon.movesAtLevel(def, level)) do
    local mdef = data.moves[id]
    table.insert(moves, { id = id, pp = mdef and mdef.pp or 0 })
  end
  return {
    species = species,
    level = level,
    exp = Growth.expForLevel(def.growthRate, level),
    dvs = dvs,
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = stats,
    hp = stats.hp,
    -- Gen2 party mons carry a happiness byte (BASE_HAPPINESS, seeded by
    -- GivePoke); Gen1 has no such field, so leave it nil there and the
    -- HAPPINESS evolution method simply never fires.
    happiness = require("src.core.GameVersion").isGen2()
      and require("src.pokemon.Evolution").BASE_HAPPINESS or nil,
    -- the Gen1 catch-rate byte freezes at catch time: evolution does NOT
    -- update it, so PKHeX expects a preevolution's rate on an evolved mon
    -- (#206).  Evolution.apply mutates in place and never touches this.
    catchRate = def.catchRate,
    status = nil, -- "SLP"|"PSN"|"BRN"|"FRZ"|"PAR"
    moves = moves,
  }
end

-- LoadEnemyMon .InitDVs (engine/battle/core.asm): a BATTLETYPE_SHINY
-- encounter skips the random roll and writes the two fixed DV bytes
-- ATKDEFDV_SHINY ($EA) and SPDSPCDV_SHINY ($AA) -- Attack 14, Defense 10,
-- Speed 10, Special 10 -- which is the lowest-numbered DV set CheckShininess
-- (02:$5040) accepts.  That, and nothing else, is the Lake of Rage Gyarados:
-- an ordinary level 30 GYARADOS whose DVs make GetMonNormalOrShinyPalettePointer
-- hand back the red half of its palette row.  The HP DV is derived from the
-- other four's low bits exactly as Stats.randomDVs derives it (all even, so 0).
Pokemon.SHINY_DVS = { attack = 14, defense = 10, speed = 10, special = 10, hp = 0 }

function Pokemon.forceShiny(data, mon)
  if type(mon) ~= "table" then return mon end
  local dvs = {}
  for k, v in pairs(Pokemon.SHINY_DVS) do dvs[k] = v end
  mon.dvs = dvs
  local def = data and data.pokemon and data.pokemon[mon.species]
  if def then
    local full = mon.stats and mon.stats.hp
    mon.stats = Stats.calc(def, mon.level or 1, dvs, mon.statExp)
    -- the mon is being built for a battle, so it comes in at full health
    -- unless it was already damaged (nothing in the ROM path does that)
    mon.hp = (full and mon.hp and mon.hp < full) and math.min(mon.hp, mon.stats.hp)
             or mon.stats.hp
  end
  return mon
end

function Pokemon.isShiny(mon)
  return type(mon) == "table" and Stats.isShiny(mon.dvs)
end

-- Pokémon Center / blackout heal (engine/events/heal_party.asm
-- HealParty): full HP, status cleared, and every move's PP restored to
-- its base plus the PP-Up bonus (RestoreBonusPP adds maxPP/5 per PP UP).
function Pokemon.heal(mon)
  mon.hp = mon.stats.hp
  mon.status = nil
  local moves = require("src.core.Data").moves
  if moves then
    for _, mv in ipairs(mon.moves) do
      local mdef = moves[mv.id]
      if mdef then
        mv.pp = mdef.pp + (mv.ppUps or 0) * math.floor(mdef.pp / 5)
      end
    end
  end
end

function Pokemon.isFainted(mon)
  return mon.hp <= 0
end

return Pokemon
