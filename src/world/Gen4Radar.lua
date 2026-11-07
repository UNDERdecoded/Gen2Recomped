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
           active = false, fresh = true, radarBattle = false, patches = {},
           recordSlot = false }
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

-- THE THREE CHAIN RECORDS, the cartridge's way (pokeplatinum pokeradar.c,
-- radar_chain_records.c): three fixed slots { species, count } (species 0 =
-- empty, which the Poketch skips). A chain takes its slot when it starts
-- (GetLowestChainRecordSlot: the first empty slot, else the lowest count with
-- its exact tie rules) and, each time it grows, TryReplaceLowestChainRecord
-- writes it there only when that slot's count is STRICTLY lower, sorts the
-- three (SortChainRecords' branch order, so equal counts keep their order),
-- and follows the chain to the LAST slot holding its count.
local function records(save)
  local recs = save.gen4RadarRecords
  if type(recs) ~= "table" then recs = {} save.gen4RadarRecords = recs end
  for i = 1, 3 do
    local r = recs[i]
    if type(r) ~= "table" then recs[i] = { species = 0, count = 0 }
    else r.species, r.count, r.id = tonumber(r.species) or r.species or 0, tonumber(r.count) or 0, nil end
  end
  while #recs > 3 do table.remove(recs) end
  return recs
end
Gen4Radar.records = records

function Gen4Radar.lowestSlot(save)
  local r = records(save)
  for i = 1, 3 do if (r[i].species or 0) == 0 then return i end end
  local slot = (r[1].count < r[2].count) and 1 or 2
  if not (r[slot].count < r[3].count) then slot = 3 end
  return slot
end

local function sortRecords(r)
  local a, b, c = r[1], r[2], r[3]
  local o
  if a.count < b.count then
    if b.count < c.count then o = { c, b, a }
    elseif a.count < c.count then o = { b, c, a }
    else o = { b, a, c } end
  else
    if a.count < c.count then o = { c, a, b }
    elseif b.count < c.count then o = { a, c, b }
    else o = { a, b, c } end
  end
  r[1], r[2], r[3] = o[1], o[2], o[3]
end
Gen4Radar.sortRecords = sortRecords

function Gen4Radar.record(save, chain)
  if not (save and chain) then return end
  local r = records(save)
  local slot = chain.recordSlot or Gen4Radar.lowestSlot(save)
  chain.recordSlot = slot
  if r[slot].count < chain.count then
    r[slot] = { species = chain.species, count = chain.count }
    sortRecords(r)
    if r[slot].count <= chain.count then
      for k = 3, 1, -1 do
        if r[k].count == chain.count then chain.recordSlot = k return end
      end
    end
  end
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
    -- (unk_14) the first patch of a chain picks the record slot it will use
    chain.recordSlot = save and Gen4Radar.lowestSlot(save) or false
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
  -- (kept: the cartridge's unk_18 stays set until RadarChain_Clear)
  return true
end

-- PokeRadar_ClearIfAllOutOfView: a patch more than a screen away is gone, and
-- with all four gone the chain is. Answers whether the chain lives on.
-- PokeRadar_ClearIfAllOutOfView: GFXBoxTest_IsBoxAtPositionInView on a
-- 16 x 8 x 16 box (RadarChain_Init) at the patch's position (16 x tile, the
-- tile's corner, at its terrain height) against the cartridge's field camera
-- -- the map header's camera type, aimed at the player, on the DS's 4:3
-- screen with the type's own fov, near and far -- every frame no field task
-- runs. `view` = { cfg, tx, ty, tz } (the target in world units); without it
-- the old box (8 x 6 cells) stands in.
local function inView(view, x, y, z)
  local cfg = view.cfg
  local pr = math.rad(cfg.pitch or 59)
  local d = cfg.distance or 667
  local sp, cp = math.sin(pr), math.cos(pr)
  -- the eye: south of and above the target; forward (0, -sin, -cos), up (0, cos, -sin)
  local vx, vy, vz = x - view.tx, y - (view.ty + d * sp), z - (view.tz + d * cp)
  local depth = -vy * sp - vz * cp
  local up = vy * cp - vz * sp
  local th = math.tan(math.rad(cfg.halfFov or 8))
  local hy, hx
  if cfg.projection == "orthographic" then hy = th * d else hy = th * depth end
  hx = hy * 256 / 192
  return depth >= (cfg.near or 0) and depth <= (cfg.far or 1e9)
         and math.abs(up) <= hy and math.abs(vx) <= hx
end
function Gen4Radar.patchInView(view, p)
  local x0, y0, z0 = p.x * 16, p.h or view.ty, p.y * 16
  for i = 0, 7 do
    local x = x0 + ((i % 2 == 1) and 16 or 0)
    local y = y0 + ((math.floor(i / 2) % 2 == 1) and 8 or 0)
    local z = z0 + ((i >= 4) and 16 or 0)
    if inView(view, x, y, z) then return true end
  end
  return false
end

function Gen4Radar.trimOutOfView(chain, px, py, view)
  if not (chain and chain.active) then return false end
  local live = 0
  for _, p in ipairs(chain.patches) do
    if p.active then
      if view and view.cfg then
        if p.h == nil then p.h = view.ty end
        if not Gen4Radar.patchInView(view, p) then p.active = false end
      elseif math.abs(p.x - px) > 8 or math.abs(p.y - py) > 6 then
        p.active = false
      end
    end
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
