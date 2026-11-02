-- HEARTGOLD / SOULSILVER'S SAFARI ZONE: six areas, chosen by the player.
--
-- pokeheartgold, transcribed:
--
--   * THE AREAS (safari_zone.c). Two area sets of six areas each; the one in
--     play is `unk5F9_6` (SafariZoneAction 0 <set> picks it on the way in,
--     action 1 puts it back to 1). A new game resets set 0 to one of ten
--     default arrangements, `rand % 10`, where `rand` is also the trainer id
--     (overlay_36.c InitGameStateAfterOakSpeech) -- so the arrangement is a
--     function of the save, not of the moment.
--   * THE MAP (map_matrix.c PlaceSafariZoneAreas). Matrix 212 (D47R0102)
--     ships with 0xFFFF in its six area cells; on every load cell
--     (x + 1, y + 1) becomes land 652 + area. Collision follows the land.
--   * THE ENCOUNTERS (encounter_check.c FieldSystem_GenerateSafariEncounter,
--     unk_02097268.c SafariZoneAreaSet_LoadAreaEncounters). The area under
--     the player is ((z - 32) / 32) * 3 + (x - 32) / 32 (0 off the six); its
--     table is ten equal slots by time of day, the block-unlocked bonus
--     Pokemon written over slot 0 upward.
--   * NO STEP LIMIT: HGSS never counts Safari steps (field_control.c
--     FieldSystem_UpdateSafari checks the balls only).
--
-- The objects, area levels and Baoba's timed calls are
-- src/world/HgssSafariObjects.lua; placing them is HgssSafariPlace and the
-- decoration app (src/ui/HgssSafariDecoration.lua), the area customizer is
-- src/ui/HgssSafariCustomizer.lua, and their props / collision on this map
-- are src/world/HgssSafariProps.lua.

local M = {}

M.LAYOUT = 212          -- NARC_map_matrix_map_matrix_0212_D47R0102_bin
M.LAND_BASE = 652
M.COLS, M.ROWS = 3, 2
M.SETS = 2
M.BALLS = 30
-- sSafariZoneDefaultAreaSets (safari_zone.c), area numbers
M.DEFAULT_SETS = {
  [0] = { 0, 7, 1, 5, 3, 6 }, { 1, 8, 5, 6, 3, 7 }, { 5, 9, 6, 7, 3, 8 },
  { 6, 10, 7, 8, 3, 9 }, { 7, 2, 8, 9, 3, 10 }, { 8, 0, 9, 10, 3, 2 },
  { 9, 1, 10, 2, 3, 0 }, { 10, 5, 2, 0, 3, 1 }, { 2, 6, 0, 1, 3, 5 },
  { 0, 2, 5, 7, 3, 9 },
}
M.AREA_NAMES = { [0] = "Plains", "Meadow", "Savannah", "Peak", "Rocky Beach", "Wetland",
  "Forest", "Swamp", "Marshland", "Wasteland", "Mountain", "Desert" }
-- the two challenges Baoba sets (overlay_03_scrcmds.c)
M.CHALLENGE_SPECIES = { [0] = 74, 27 } -- Geodude, Sandshrew

local function isHgss()
  local ok, GV = pcall(require, "src.core.GameVersion")
  local info = ok and GV.info and GV.info() or nil
  return info and info.family == "hgss" or false
end
M.isHgss = isHgss

-- the save's Safari Zone, seeded the way a new game seeds it
function M.state(save)
  if type(save) ~= "table" then return nil end
  local st = save.hgssSafari
  if st then return st end
  local p = save.player or {}
  local rand = ((tonumber(p.id) or 0) % 65536) + ((tonumber(p.secretId) or 0) % 65536) * 65536
  local default = M.DEFAULT_SETS[rand % 10]
  st = { active = 1, sets = {} }
  for set = 0, M.SETS - 1 do
    local areas = {}
    for i = 1, 6 do areas[i] = { area = (set == 0) and default[i] or 0, objects = {} } end
    st.sets[set] = { areas = areas, levels = {} }
  end
  save.hgssSafari = st
  return st
end

-- SafariZone_GetAreaSet(..., 3): the set in play
function M.activeSet(save)
  local st = M.state(save)
  if not st then return nil end
  return st.sets[st.active] or st.sets[0]
end

function M.isSafariMap(def)
  return type(def) == "table" and def.layout == M.LAYOUT and def.cameraFamily == "hgss"
end

-- the six matrix cells: { x, y, land }
function M.patches(save)
  local set = M.activeSet(save)
  if not set then return {} end
  local out = {}
  for y = 0, M.ROWS - 1 do
    for x = 0, M.COLS - 1 do
      local a = set.areas[y * M.COLS + x + 1]
      out[#out + 1] = { x + 1, y + 1, M.LAND_BASE + ((a and a.area) or 0) }
    end
  end
  return out
end

function M.key(save)
  local set = M.activeSet(save)
  if not set then return "none" end
  local parts = {}
  for i = 1, 6 do parts[i] = tostring(set.areas[i] and set.areas[i].area or 0) end
  -- ...and the placed objects, whose footprints are collision
  -- (src/world/HgssSafariProps.lua)
  local okP, P = pcall(require, "src.world.HgssSafariProps")
  local objects = okP and P.objectsKey(save) or ""
  return table.concat(parts, ",") .. "|" .. objects
end

-- the terrain grid (Gen4Ground): the six cells' land swapped in
function M.grid(def, grid, altitudes, save)
  if not (M.isSafariMap(def) and grid and grid.land) then return grid, altitudes end
  local land = {}
  for i, v in ipairs(grid.land) do land[i] = v end
  for _, p in ipairs(M.patches(save)) do
    if p[1] < grid.width and p[2] < grid.height then
      land[p[2] * grid.width + p[1] + 1] = p[3]
    end
  end
  local out = {}
  for k, v in pairs(grid) do out[k] = v end
  out.land = land
  return out, altitudes
end

-- the collision (MapLoader): each patched cell's permissions, as
-- Gen4HiddenPaths does for Platinum's paths
local CHUNK, BLOCKED, COLLISION = 32, 255, 0x8000
function M.applyToDef(data, def, save)
  if not M.isSafariMap(def) then return false end
  if type(def.blocks) ~= "string" or type(def.behaviorCells) ~= "string" then return false end
  local key = M.key(save)
  if def.hgssSafariKey == key then return false end
  if not def.hgssSafariBase then
    def.hgssSafariBase = { blocks = def.blocks, behaviorCells = def.behaviorCells }
  end
  local blocks, behav = def.hgssSafariBase.blocks, def.hgssSafariBase.behaviorCells
  local perms = data and data.gen4_map_permissions
  local w, h = def.width or 0, def.height or 0
  local ox, oy = def.originX or 0, def.originY or 0
  if perms then
    local cells, bytes = {}, {}
    for i = 1, w * h do
      cells[i] = blocks:sub(i * 2 - 1, i * 2)
      bytes[i] = behav:sub(i, i)
    end
    for _, p in ipairs(M.patches(save)) do
      local block = perms[p[3]]
      if type(block) == "string" then
        for ty = 0, CHUNK - 1 do
          for tx = 0, CHUNK - 1 do
            local mx, my = p[1] * CHUNK + tx - ox, p[2] * CHUNK + ty - oy
            if mx >= 0 and my >= 0 and mx < w and my < h then
              local at = (ty * CHUNK + tx) * 2
              local lo, hi = block:byte(at + 1, at + 2)
              local word = lo and hi and (lo + hi * 256) or nil
              local v = (word == nil or word >= COLLISION) and BLOCKED or (word % 256)
              local i = my * w + mx + 1
              cells[i] = string.char(v % 256, math.floor(v / 256))
              bytes[i] = string.char(word and word % 256 or 255)
            end
          end
        end
      end
    end
    -- MapPropManager_LoadFromSafariZone: 0x8023 under every placed object
    local okP, P = pcall(require, "src.world.HgssSafariProps")
    if okP then
      for i in pairs(P.collisionCells(def, save)) do
        cells[i] = string.char(P.BLOCKED % 256, math.floor(P.BLOCKED / 256))
        bytes[i] = string.char(P.BEHAVIOUR)
      end
    end
    blocks, behav = table.concat(cells), table.concat(bytes)
  end
  def.blocks, def.behaviorCells = blocks, behav
  def._blockArray = nil
  def.hgssSafariKey = key
  return true
end

-- ov02_0224E31C, in the map's own tiles (its origin is (32, 32))
function M.areaAt(def, lx, ly)
  local gx = (def and def.originX or 32) + (tonumber(lx) or 0)
  local gz = (def and def.originY or 32) + (tonumber(ly) or 0)
  local function div(n) return n >= 0 and math.floor(n / 32) or -math.floor(-n / 32) end
  local idx = div(gz - 32) * 3 + div(gx - 32)
  if idx < 0 or idx >= 6 then idx = 0 end
  return idx
end

-- SafariZoneAreaSet_GetObjectsInArea: the type levels an area's placed
-- objects add up to (src/world/HgssSafariObjects.lua)
local function objectLevels(set, idx)
  return require("src.world.HgssSafariObjects").levelsInArea(set, idx)
end

-- the ten slots of one area for one encounter type (0 land, 1 surf, 2..4
-- the rods) at one time of day (0 morning, 1 day, 2 night); `setOverride`
-- reads another area set than the one in play (the day check reads set 0)
function M.slots(data, save, idx, kind, tod, setOverride)
  local set = setOverride or M.activeSet(save)
  local enc = data and data.gen4_hgss_safari
  local out = {}
  for i = 1, 10 do
    out[i] = { species = kind == 0 and 19 or 129, level = 5, minLevel = 5, maxLevel = 5, chance = 10 }
  end
  local area = set and set.areas[idx + 1]
  local rec = area and enc and enc.areas and enc.areas[area.area]
  if not rec then return out end
  local types = rec.types or {}
  -- an area with no water answers the defaults for every water table
  if kind > 0 and ((types[1] or {}).bonusCount or 0) == 0 then return out end
  local t = types[kind]
  if not t then return out end
  for i, slot in ipairs((t.base or {})[tod] or {}) do
    out[i] = { species = slot.species, level = slot.level, minLevel = slot.level, maxLevel = slot.level, chance = 10 }
  end
  local levels = objectLevels(set, idx)
  local n = 0
  for i, cond in ipairs(t.unlock or {}) do
    local ok = (levels[cond[1]] or 0) >= cond[2]
    if ok and cond[3] ~= 0 then ok = (levels[cond[3]] or 0) >= cond[4] end
    if ok then
      local b = ((t.bonus or {})[tod] or {})[i]
      if b then
        n = n + 1
        out[n] = { species = b.species, level = b.level, minLevel = b.level, maxLevel = b.level, chance = 10 }
      end
      if n >= 10 then break end
    end
  end
  return out
end

-- the wild view Encounter.forMap hands out while a Safari game is on:
-- the area under the player, now
function M.view(data, save, mapDef, base, hour)
  if not (M.isSafariMap(mapDef) and save and save.safari and save.safari.hgss) then return nil end
  local G = package.loaded["src.core.Game"]
  local ow = G and G.overworld
  local p = ow and ow.player
  local idx = p and M.areaAt(mapDef, p.cellX or math.floor((p.px or 0) / 16),
                                       p.cellY or math.floor((p.py or 0) / 16)) or 0
  local band = require("src.import.Gen4Encounters").timedBand(hour or tonumber(os.date("%H")))
  local tod = band == "day" and 1 or band == "night" and 2 or 0
  return idx, tod
end

-- SafariZoneAction <action> <set>
function M.action(save, action, set)
  local st = M.state(save)
  if not st then return end
  if action == 0 then
    st.active = (tonumber(set) or 0) % M.SETS
    save.safari = { balls = M.BALLS, steps = 0, caught = 0, gen4 = true, hgss = true }
  else
    if save.safari then save.gen4SafariLastCaught = save.safari.caught or 0 end
    save.safari = nil
    st.active = 1
    -- the days banked in the zone level while the game was on
    pcall(function() require("src.world.HgssSafariObjects").gameEnded(save) end)
  end
end

-- CheckSafariZoneChallengeCompleted <n> <dest>: a party member of the
-- challenge species, the player's own, not hatched, met in the Safari Zone
function M.challengeDone(data, save, n)
  local want = M.CHALLENGE_SPECIES[tonumber(n) or 0]
  if not want then return false end
  local sections = {}
  for _, id in ipairs({ "D47", "D47R0101", "D47R0102" }) do
    local def = data and data.maps and data.maps[id]
    if def and def.regionMapSection then sections[def.regionMapSection] = true end
  end
  local tid = tonumber(save.player and save.player.id) or -1
  for _, mon in ipairs(save.party or {}) do
    local species = require("src.pokemon.Gen4DayCare").speciesOf(mon)
    local ot = tonumber(mon.otId) or tid
    if not mon.isEgg and species == want and (ot % 65536) == tid % 65536
       and not mon.eggLocation and sections[mon.metLocation] then
      return true
    end
  end
  return false
end

return M
