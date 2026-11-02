-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S SAFARI ZONE: THE PLACED OBJECTS ON THE MAP -- their
-- build-model props and the collision under them. pokeheartgold:
--
--   * WHICH PROPS (asm/overlay_01_021F4704.s ov01_021F4B1C): a chunk of the
--     Safari matrix in cells x 1..3, y 1..2 does NOT load its land's props
--     (MapPropManager_LoadFromNARC); it loads its area slot's objects instead
--     (MapPropManager_LoadFromSafariZone), slot (y - 1) * 3 + (x - 1) of the
--     set in play (sub_0202F620), the player's gender for set 0 and the link
--     leader's for set 1 (SafariZone_GetLinkLeaderGender -- no link here, so
--     the player's).
--   * WHERE (map_prop_manager.c MapPropManager_LoadFromSafariZone): the
--     object's build model (GetSafariObjectConfig: BUILD_MODEL_SAF_GO01 189 ..
--     SAF_EO12 214, the statue / flag one higher for a girl) at
--     x = 16 x + 8 width - 256, y = the stored y, z = 16 z + 8 (2 - height) -
--     256 in the chunk's own centred units, no rotation, scale 1.
--   * THE COLLISION: every footprint tile's attribute word becomes 0x8023 --
--     collision plus TILE_BEHAVIOR_35, which is what std_safari_remove_object
--     answers. ScrCmd_720 puts the land's own words back (sp8 <- sp4) and culls
--     the prop (MapProp_SetCulled); here both are re-derived from the save, so
--     the removed object's prop and collision go together.
--
-- Read by Gen4Ground:objectsFor (the props) and HgssSafariZone.applyToDef
-- (the collision). `M.changed()` is what a command calls after it edits the
-- objects, so the live map's collision and drawn props follow at once (the
-- cartridge restores the whole overworld after the decoration app).

local M = {}

M.version = 0
M.COLS, M.ROWS = 3, 2
M.CHUNK = 32
M.BLOCKED, M.BEHAVIOUR = 255, 0x23
-- GetSafariObjectConfig's build models, by object id
M.MODELS = {
  [0] = 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200,
  201, 202, 203, 204, 205, 206, 207, 209, 211, 212, 213, 214,
}
M.GENDERED = { [18] = true, [19] = true }   -- your statue / your flag

local function Zone() return require("src.world.HgssSafariZone") end
local function Obj() return require("src.world.HgssSafariObjects") end

function M.buildModel(id, female)
  id = math.floor(tonumber(id) or 0)
  if not M.MODELS[id] then id = 0 end
  local m = M.MODELS[id]
  if M.GENDERED[id] and female then m = m + 1 end
  return m
end

local function female(save)
  local p = (save or {}).player or {}
  local g = p.gender
  return g == 1 or g == "female" or g == "girl"
end

-- the objects of slot idx (0..5) of the set in play, in their area's own tiles
function M.slotObjects(save, idx)
  local set = Zone().activeSet(save)
  local area = set and set.areas[(tonumber(idx) or 0) + 1]
  local list = area and area.objects or {}
  if #list > Obj().MAX_OBJECTS then return {} end
  return list
end

-- MapPropManager_LoadFromSafariZone, for one slot: Gen4Ground prop records
function M.props(save, idx)
  local out = {}
  local girl = female(save)
  for _, o in ipairs(M.slotObjects(save, idx)) do
    local c = Obj().config(o.id)
    out[#out + 1] = {
      model = M.buildModel(o.id, girl),
      x = 16 * (tonumber(o.x) or 0) + 8 * c.width - 256,
      y = tonumber(o.y) or 0,
      z = 16 * (tonumber(o.z) or 0) + 8 * (2 - c.height) - 256,
      scaleX = 1, scaleY = 1, scaleZ = 1, safariObject = o.id,
    }
  end
  return out
end

-- the slot a matrix cell holds, or nil outside the six
function M.slotOfCell(cx, cy)
  if not (cx and cy) then return nil end
  if cx < 1 or cx > M.COLS or cy < 1 or cy > M.ROWS then return nil end
  return (cy - 1) * M.COLS + (cx - 1)
end

local function save()
  local G = package.loaded["src.core.Game"]
  return G and G.save or nil
end

-- the key the props are cached under: the save's zone, the set in play and
-- every edit this module was told about
function M.key(sv)
  local st = sv and sv.hgssSafari
  return tostring(st) .. ":" .. tostring(st and st.active) .. ":" .. M.version
end

-- Gen4Ground:objectsFor's hook. nil leaves the land's own props (a cell
-- outside the six, or not the Safari map); otherwise the slot's objects,
-- which REPLACE the land's (the six area lands carry none anyway).
-- `cx, cy` are the matrix cell; without them (a per-land bake) the first
-- area cell holding that land answers.
function M.objectsFor(ground, land, cx, cy)
  local def = ground and ground.def
  if not Zone().isSafariMap(def) then return nil end
  local sv = save()
  if not sv then return nil end
  local slot = M.slotOfCell(cx, cy)
  if cx == nil then
    local grid = ground.grid
    for y = 1, M.ROWS do
      for x = 1, M.COLS do
        if grid and grid.land and grid.land[y * grid.width + x + 1] == land then
          slot = M.slotOfCell(x, y)
          break
        end
      end
      if slot then break end
    end
  end
  if slot == nil then return nil end
  local key = M.key(sv)
  if ground.hgssSafariPropsKey ~= key then
    ground.hgssSafariPropsKey = key
    ground.hgssSafariProps = {}
  end
  local hit = ground.hgssSafariProps[slot]
  if not hit then
    hit = M.props(sv, slot)
    ground.hgssSafariProps[slot] = hit
  end
  return hit
end

-- the footprint cells of every object of the set in play, in MAP tiles:
-- { [i] = true } with i = my * w + mx + 1
function M.collisionCells(def, sv)
  local out = {}
  local w, h = def.width or 0, def.height or 0
  local ox, oy = def.originX or 0, def.originY or 0
  for slot = 0, 5 do
    local cx, cy = slot % M.COLS + 1, math.floor(slot / M.COLS) + 1
    for _, o in ipairs(M.slotObjects(sv, slot)) do
      local c = Obj().config(o.id)
      local ox0, oz0 = tonumber(o.x) or 0, tonumber(o.z) or 0
      for j = oz0, oz0 - c.height + 1, -1 do
        for k = ox0, ox0 + c.width - 1 do
          if j >= 0 and j < M.CHUNK and k >= 0 and k < M.CHUNK then
            local mx, my = cx * M.CHUNK + k - ox, cy * M.CHUNK + j - oy
            if mx >= 0 and my >= 0 and mx < w and my < h then out[my * w + mx + 1] = true end
          end
        end
      end
    end
  end
  return out
end

-- a key of the objects' footprints, for HgssSafariZone.key
function M.objectsKey(sv)
  local set = Zone().activeSet(sv)
  if not set then return "" end
  local parts = {}
  for i = 1, 6 do
    for _, o in ipairs((set.areas[i] or {}).objects or {}) do
      parts[#parts + 1] = ("%d:%d:%d:%d"):format(i, tonumber(o.id) or 0, tonumber(o.x) or 0, tonumber(o.z) or 0)
    end
  end
  return table.concat(parts, ";")
end

-- after an edit: the live Safari map's collision and its drawn props
function M.changed(game)
  M.version = M.version + 1
  local G = game or package.loaded["src.core.Game"]
  local ow = G and G.overworld
  local map = ow and ow.map
  local def = map and map.def
  if not (def and Zone().isSafariMap(def)) then return end
  pcall(function()
    Zone().applyToDef(G.data, def, G.save)
  end)
  if map.blocksDirty ~= nil then map.blocksDirty = true end
  local ground = map.renderer and map.renderer.gen4Ground
  if ground then
    ground.hgssSafariPropsKey = nil
    if ground.dropBakes then pcall(ground.dropBakes, ground) end
  end
end

return M
