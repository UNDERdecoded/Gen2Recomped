-- THE POKE RADAR, after pokeplatinum src/pokeradar.c, the radar arms of
-- src/overlay006/wild_encounters.c and src/encounter.c, and
-- item_use_functions.c's CanUsePokeRadar.
--
-- It was a named gap: "Needs the Poke Radar and its chain, which the port does
-- not model". Here is all of it except the patches' 3D model (drawn as a
-- procedural shake, see `draw`).
--
-- USING IT (RefreshRadarChain). Only standing in tall grass, not on the bike,
-- not with a partner. Below 50 steps of charge it says how many are left
-- (`scripts_poke_radar` 0, the count in var 0x8000); at 50 the charge resets
-- and four patches spawn, one per ring around the player -- ring 0 the 9x9
-- border (32 cells), ring 1 the 7x7 (24), ring 2 the 5x5 (16), ring 3 the 3x3
-- (8) -- each on a random cell of its ring that is tall grass, at the player's
-- height and on this map header. None: `scripts_poke_radar` 1. Some: the radar
-- music, and each patch rolls whether it CONTINUES the chain (ring 0..3: 88 /
-- 68 / 48 / 28 in 100, or 98 / 78 / 58 / 38 after a catch); a continuing patch
-- shakes the chain's own way and may be SHINY (1 in max(200, 8200 - 200 x
-- chain), never at chain 0); a breaking one shakes soft or hard at random.
--
-- STEPPING INTO A PATCH is always an encounter (PokeRadar_ShouldDoRadarEncounter):
--   * the first patch of a chain fixes its shake type and starts the chain;
--   * a continuing patch: the chain +1 (to 999), and the SAME species and level
--     come out -- shiny if the patch was;
--   * otherwise an ordinary grass roll (radar-only species in slots 5, 6, 11, 12
--     on a hard shake): the chain's first species is taken as the chain's, the
--     same species continues it, a different one breaks it.
-- An ordinary encounter outside the patches, a roamer, a map change, the bike,
-- a black-out, or walking away from every patch ends the chain; a radar battle
-- that ends in anything but a win or a catch ends it too. After a radar battle
-- that did not, new patches spawn around the player.
--
-- The three best chains are kept (`TryReplaceLowestChainRecord`) for the
-- Poketch's chain counter.

local Gen4Radar = {}

Gen4Radar.ITEM = 431
Gen4Radar.BATTERY = 50
Gen4Radar.SOFT, Gen4Radar.HARD = 0, 1
Gen4Radar.RING_CELLS = { 32, 24, 16, 8 }
Gen4Radar.CONTINUE = { 88, 68, 48, 28 }
Gen4Radar.CONTINUE_CAUGHT = { 98, 78, 58, 38 }
Gen4Radar.CAP = 999

local RNG = function(n) return love.math.random(0, n - 1) end

-- RadarChain_Clear
function Gen4Radar.newChain()
  return { count = 0, shakeType = Gen4Radar.SOFT, species = 0, level = 0,
           active = false, fresh = true, radarBattle = false, patches = {} }
end

-- The (dx, dy) of cell `pick` of ring `ring` (RadarSpawnPatches' arithmetic),
-- relative to the player, -4..4.
function Gen4Radar.ringCell(ring, pick)
  local side = 9 - ring * 2
  local row = math.floor(pick / side)
  local x, z
  if row == 0 then
    x, z = ring + pick % side, ring
  elseif row == 1 then
    x, z = ring + pick % side, ring + side - 1
  else
    local rest = pick - side * 2
    z = ring + math.floor(rest / 2) + 1
    x = (rest % 2 == 0) and ring or (ring + side - 1)
  end
  return x - 4, z - 4
end

-- RadarSpawnPatches. `isGrass(x, y)` answers whether a cell qualifies (tall
-- grass, same height, same header).
function Gen4Radar.spawn(chain, px, py, isGrass, rng)
  rng = rng or RNG
  local any = 0
  for ring = 0, 3 do
    local dx, dy = Gen4Radar.ringCell(ring, rng(Gen4Radar.RING_CELLS[ring + 1]))
    local x, y = px + dx, py + dy
    local p = { x = x, y = y, active = isGrass(x, y) and true or false,
                shakeType = Gen4Radar.SOFT }
    chain.patches[ring + 1] = p
    if p.active then any = any + 1 end
  end
  chain.active = any > 0
  if not chain.active then
    local fresh = Gen4Radar.newChain()
    for k, v in pairs(fresh) do chain[k] = v end
  end
  return chain.active
end

-- CheckPatchShiny
function Gen4Radar.shinyRoll(count, rng)
  if not count or count == 0 then return false end
  local rate = math.max(200, 8200 - count * 200)
  return (rng or RNG)(rate) == 0
end

-- SetupGrassPatches. `caught` picks the boosted continue rates.
function Gen4Radar.setup(chain, caught, rng)
  rng = rng or RNG
  local rates = caught and Gen4Radar.CONTINUE_CAUGHT or Gen4Radar.CONTINUE
  for ring = 1, 4 do
    local p = chain.patches[ring]
    if p and p.active then
      p.continueChain = rng(100) < rates[ring]
      if not p.continueChain then
        p.shakeType = (rng(100) < 50) and Gen4Radar.SOFT or Gen4Radar.HARD
        p.shiny = false
      else
        p.shakeType = chain.shakeType
        p.shiny = Gen4Radar.shinyRoll(chain.count, rng)
      end
    end
  end
end

function Gen4Radar.patchAt(chain, x, y)
  if not (chain and chain.active) then return nil end
  for _, p in ipairs(chain.patches) do
    if p.active and p.x == x and p.y == y then return p end
  end
  return nil
end

local function bump(chain)
  chain.count = math.min(Gen4Radar.CAP, chain.count + 1)
end

-- The three best chains, best first.
function Gen4Radar.record(save, chain)
  if not (save and chain and chain.species ~= 0) then return end
  save.gen4RadarRecords = save.gen4RadarRecords or {}
  local recs = save.gen4RadarRecords
  for _, r in ipairs(recs) do
    if r.id == chain.recordId then r.count = math.max(r.count, chain.count) goto sort end
  end
  chain.recordId = (save.gen4RadarRecordSerial or 0) + 1
  save.gen4RadarRecordSerial = chain.recordId
  recs[#recs + 1] = { id = chain.recordId, species = chain.species, count = chain.count }
  ::sort::
  table.sort(recs, function(a, b) return a.count > b.count end)
  while #recs > 3 do table.remove(recs) end
end

-- PokeRadar_ShouldDoRadarEncounter + TryGenerateGrassEncounter_WithRadar.
-- `roll(slots)` is the ordinary grass roll over `slots` (answers
-- { species, level }). Answers the encounter { species, level, shiny } or nil.
function Gen4Radar.encounter(chain, patch, slots, radarSpecies, roll, save)
  chain.radarBattle = true
  local keep = false
  local shiny = false
  if not chain.fresh then
    if patch.continueChain then
      bump(chain)
      keep, shiny = true, patch.shiny == true
      Gen4Radar.record(save, chain)
    end
  else
    chain.fresh = false
  end
  if not keep then chain.shakeType = patch.shakeType end
  if keep then
    return { species = chain.species, level = chain.level, shiny = shiny }
  end
  -- a hard shake puts the radar's own species in slots 5, 6, 11 and 12
  local table_ = slots
  if chain.shakeType == Gen4Radar.HARD and radarSpecies then
    table_ = {}
    for i, s in ipairs(slots or {}) do
      table_[i] = { species = s.species, level = s.level, chance = s.chance,
                    minLevel = s.minLevel, maxLevel = s.maxLevel }
    end
    local map = { [5] = 1, [6] = 2, [11] = 3, [12] = 4 }
    for slot, k in pairs(map) do
      local sp = tonumber(radarSpecies[k])
      if table_[slot] and sp and sp > 0 then table_[slot].species = sp end
    end
  end
  local enc = roll(table_)
  if not enc then return nil end
  if chain.species == 0 then
    chain.species, chain.level = enc.species, enc.level
    bump(chain)
    Gen4Radar.record(save, chain)
  elseif enc.species == chain.species then
    enc.level = chain.level
    bump(chain)
    Gen4Radar.record(save, chain)
  else
    local fresh = Gen4Radar.newChain()
    for k, v in pairs(fresh) do chain[k] = v end
  end
  return enc
end

-- After the battle (encounter.c). Answers whether the chain lives on.
function Gen4Radar.afterBattle(chain, result)
  if not (chain and chain.active) then return false end
  local won = result == "win" or result == "caught"
  if not (chain.radarBattle and won) then
    local fresh = Gen4Radar.newChain()
    for k, v in pairs(fresh) do chain[k] = v end
    return false
  end
  chain.radarBattle = false
  return true
end

-- PokeRadar_ClearIfAllOutOfView: a patch more than a screen away is gone, and
-- with all four gone the chain is. Answers whether the chain lives on.
function Gen4Radar.trimOutOfView(chain, px, py)
  if not (chain and chain.active) then return false end
  local live = 0
  for _, p in ipairs(chain.patches) do
    if p.active and (math.abs(p.x - px) > 8 or math.abs(p.y - py) > 6) then p.active = false end
    if p.active then live = live + 1 end
  end
  if live == 0 then
    local fresh = Gen4Radar.newChain()
    for k, v in pairs(fresh) do chain[k] = v end
    return false
  end
  return true
end

-- RadarChargeStep: a step charges it while the bag holds one.
function Gen4Radar.charge(save, hasRadar)
  if not hasRadar then return end
  save.gen4RadarCharge = math.min(Gen4Radar.BATTERY, (save.gen4RadarCharge or 0) + 1)
end

-- The patch, drawn: blades of grass rocking -- gently for a soft shake, hard
-- for a hard one -- and a white glint over a shiny patch. (`x`, `y`) is the
-- cell's top-left in the caller's space; `t` is a frame counter.
function Gen4Radar.drawPatch(p, x, y, t)
  local g = love.graphics
  local amp = (p.shakeType == Gen4Radar.HARD) and 3 or 1.5
  local speed = (p.shakeType == Gen4Radar.HARD) and 0.6 or 0.35
  for i = 0, 3 do
    local phase = math.sin(t * speed + i * 1.7) * amp
    local bx = x + 2 + i * 4
    g.setColor(0.18, 0.55, 0.22, 1)
    g.polygon("fill", bx, y + 14, bx + 3, y + 14, bx + 1.5 + phase, y + 4)
    g.setColor(0.35, 0.78, 0.35, 1)
    g.line(bx + 1.5, y + 13, bx + 1.5 + phase, y + 5)
  end
  if p.shiny then
    local a = 0.5 + 0.5 * math.sin(t * 0.3)
    g.setColor(1, 1, 1, a)
    local cx, cy = x + 8, y + 4
    g.polygon("fill", cx, cy - 4, cx + 1.2, cy - 1.2, cx + 4, cy, cx + 1.2, cy + 1.2,
              cx, cy + 4, cx - 1.2, cy + 1.2, cx - 4, cy, cx - 1.2, cy - 1.2)
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4Radar
