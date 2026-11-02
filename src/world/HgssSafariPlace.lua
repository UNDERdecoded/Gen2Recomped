-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S SAFARI ZONE: PLACING AN OBJECT IN AN AREA -- the
-- field side of the decoration app (the save side is HgssSafariObjects, the
-- app's screen src/ui/HgssSafariDecoration.lua). Read off pokeheartgold
-- asm/overlay_02_02248728.s and asm/overlay_108_021E8850.s:
--
--   * THE PRESS (field_control.c GetInteractedMetatileScript): on foot, after
--     the Surf row, ov02_0224E35C && ov02_0224E4CC(behaviour, collision) ->
--     std_safari_place_object (8800, band `safari` 0); surfing, after the
--     Waterfall / Whirlpool rows, ov02_0224E35C && ov02_0224E4DC -> 8800.
--     Then, either way: the Safari sys flag, area set 0 in play and the faced
--     tile's behaviour TILE_BEHAVIOR_35 (0x23, sub_0205BAEC) ->
--     std_safari_remove_object (8801).
--   * ov02_0224E35C: map header 357 (D47R0102, ov02_0224E308), the Safari
--     game on, area set 0 in play (sub_0202F620), Baoba's unlock level > 0,
--     the faced tile inside x 0x20..0x7F / z 0x20..0x5F, and the faced tile's
--     height equal to the player's (sub_02054774).
--   * ov02_0224E4CC / E4DC (ov02_0224EF6C picks by `water`): the tile is not
--     a collision (sub_020548C0) and is TILE_BEHAVIOR_0 / SAND (0x21) / MUD
--     (0xA4) (sub_0205BAD0) -- or, for water, surfable.
--   * THE FOOTPRINTS (SafariDecoration_CreateArgs): 1x1 the faced tile;
--     1 wide x 2 tall ov02_0224E828, 2 x 1 ov02_0224EB48, 2 x 2 ov02_0224EE4C,
--     each searching the tiles ahead in the cartridge's order (the
--     ov02_02253A4C offsets { -1, 1, -1, 1, 1, -1 }) and answering the
--     object's origin: its LEFT column and its BOTTOM (largest z) row.
--   * ScrCmd_721 (ov02_0224E698): 1 when the player's area holds 30 objects,
--     0 on foot, else (surfing) 2 when the water group is still locked
--     (ov02_0224E640) or 3 when no 2 x 2 of water fits ahead.
--   * THE OBJECT LIST (ov108_021EA63C): Baoba's unlock level counts groups
--     off the row ov108_021EAD28[trainerId % 10]; the four groups are
--     ov108_021EACE8 / EAD00 / EACF8 / EACF0 (plains + 3, forest + 3, rocks +
--     3, water + 3); the list is the union in object-id order, each entry's
--     footprint kind 0 1x1 / 1 1x2 / 2 2x1 / 3 2x2 (ov108_021EA700).
--   * THE REFUSALS (ov108_021EA52C -> msg_0430 4 + n - 1): no room left in
--     the area (7 "Cannot place any more."); the fountain (`isAnimated`, the
--     only Surf-placed object) on foot (5) or a land object from the water
--     (6); no footprint of its kind ahead (4 "No open spaces left.").
--   * THE COMMIT (ov108_021E8C64): { id, x % 32, player height, z % 32 } into
--     area set 0's slot under the PLAYER (not the faced tile), result = id.

local M = {}

M.HEADER = 357
M.BEH_OBJECT = 0x23         -- TILE_BEHAVIOR_35, what a placed object stands on
M.LAND_OK = { [0x00] = true, [0x21] = true, [0xA4] = true } -- 0, SAND, MUD
M.FOUNTAIN = 10
-- ov02_02253A4C
local TBL = { [0] = -1, 1, -1, 1, 1, -1 }
-- ov108_021EAD08's four groups
M.GROUPS = {
  [0] = { 0, 1, 2, 19, 20, 12 },  -- ov108_021EACE8
  [1] = { 3, 4, 5, 13, 14, 17 },  -- ov108_021EAD00
  [2] = { 6, 7, 8, 21, 22, 23 },  -- ov108_021EACF8
  [3] = { 9, 10, 11, 15, 16, 18 },-- ov108_021EACF0
}
-- ov108_021EAD28: the group order by trainer id % 10
M.ORDER = {
  [0] = { 0, 1, 2, 3 }, { 0, 1, 2, 3 }, { 0, 1, 2, 3 }, { 1, 2, 3, 0 }, { 1, 2, 3, 0 },
  { 1, 2, 3, 0 }, { 2, 3, 0, 1 }, { 2, 3, 0, 1 }, { 3, 0, 1, 2 }, { 3, 0, 1, 2 },
}
-- DIR_NORTH 0, SOUTH 1, WEST 2, EAST 3
local DIRS = { up = 0, down = 1, left = 2, right = 3 }
local DX = { [0] = 0, 0, -1, 1 }
local DZ = { [0] = -1, 1, 0, 0 }

local function Zone() return require("src.world.HgssSafariZone") end
local function Obj() return require("src.world.HgssSafariObjects") end

-- PlayerProfile_GetTrainerID: the full 32-bit id
function M.trainerId(save)
  local p = (save or {}).player or {}
  return ((tonumber(p.id) or 0) % 65536) + ((tonumber(p.secretId) or 0) % 65536) * 65536
end

-- ov02_0224E31C (the C's truncating divide)
function M.areaIndex(x, z)
  local function div(n) return n >= 0 and math.floor(n / 32) or -math.floor(-n / 32) end
  local idx = div(x - 32) + div(z - 32) * 3
  if idx < 0 or idx >= 6 then idx = 0 end
  return idx
end

-- ------------------------------------------------------------- the field

-- the player, in the cartridge's global matrix tiles
function M.where(ow)
  local p = ow and ow.player
  local map = ow and ow.map
  if not (p and map) then return nil end
  local def = map.def or {}
  local ox, oz = def.originX or 0, def.originY or 0
  local lx = p.cellX or math.floor((p.px or 0) / 16)
  local lz = p.cellY or math.floor((p.py or 0) / 16)
  local dir = DIRS[p.facing or p.dir] or 1
  return { x = ox + lx, z = oz + lz, dir = dir, ox = ox, oz = oz, map = map,
           surfing = p.surfing and true or false,
           ground = map.renderer and map.renderer.gen4Ground or nil }
end

-- sub_02054774: the height at a tile, nil off the plates
local function heightAt(w, x, z)
  local g = w.ground
  if not (g and g.heightAt) then return 0 end
  local ok, h = pcall(g.heightAt, g, x - w.ox, z - w.oz)
  return ok and tonumber(h) or nil
end
M.heightAt = heightAt

local function sameHeight(w, x, z)
  local here, there = heightAt(w, w.x, w.z), heightAt(w, x, z)
  if here == nil or there == nil then return false end
  return math.abs(here - there) < 0.5
end

-- ov02_0224EF6C: the tile is free and of the right kind
local function tileOk(w, x, z, water)
  local map = w.map
  local lx, lz = x - w.ox, z - w.oz
  if not (map.inBounds and map:inBounds(lx, lz)) then return false end
  if map.gen4TerrainBlocked and map:gen4TerrainBlocked(lx, lz) then return false end
  local b = map.cellBehaviour and map:cellBehaviour(lx, lz)
  if b == nil then return false end
  if water then return require("src.world.Map").G4_SURFABLE[b] and true or false end
  return M.LAND_OK[b] and true or false
end

local function ok(w, x, z, water) return tileOk(w, x, z, water) and sameHeight(w, x, z) end

-- ov02_0224E828: 1 wide, 2 tall
function M.fit12(w, x, z, dir, water)
  if dir == 0 or dir == 1 then
    local step = TBL[1 + (dir ~= 0 and 1 or 0)]
    local n = 0
    for i = 1, 2 do if ok(w, x, z + step * i, water) then n = n + 1 end end
    if n ~= 2 then return nil end
    return x, (dir == 0) and z - 1 or z + 2
  end
  local x5 = x + TBL[dir == 2 and 1 or 2]
  if not ok(w, x5, z, water) then return nil end
  for i = 0, 1 do
    if ok(w, x5, z + TBL[1 + i], water) then return x5, z + i end
  end
  return nil
end

-- ov02_0224EB48: 2 wide, 1 tall
function M.fit21(w, x, z, dir, water)
  if dir == 0 or dir == 1 then
    local z5 = z + TBL[dir == 0 and 1 or 2]
    if not ok(w, x, z5, water) then return nil end
    for i = 0, 1 do
      if ok(w, x - TBL[1 + i], z5, water) then return x - i, z5 end
    end
    return nil
  end
  local x0 = dir == 2 and x - 2 or x + 1
  if ok(w, x0, z, water) and ok(w, x0 + 1, z, water) then return x0, z end
  return nil
end

-- ov02_0224EE4C: 2 x 2
function M.fit22(w, x, z, dir, water)
  if dir == 0 or dir == 1 then
    if not M.fit12(w, x, z, dir, water) then return nil end
    for i = 0, 1 do
      if M.fit12(w, x + TBL[4 + i], z, dir, water) then
        return x - i, (dir == 0) and z - 1 or z + 2
      end
    end
    return nil
  end
  if not M.fit21(w, x, z, dir, water) then return nil end
  for i = 0, 1 do
    if M.fit21(w, x, z - TBL[4 + i], dir, water) then
      return dir == 2 and x - 2 or x + 1, z + i
    end
  end
  return nil
end

local function isSafari(ow)
  local def = ow and ow.map and ow.map.def
  return def and (def.header == M.HEADER or Zone().isSafariMap(def)) or false
end

local function inGame(save) return save and save.safari and save.safari.hgss and true or false end

-- ov02_0224E35C
function M.canPlaceAhead(ow, save)
  if not isSafari(ow) or not inGame(save) then return false end
  local st = Zone().state(save)
  if not st or (tonumber(st.active) or 0) ~= 0 then return false end
  if Obj().unlockLevel(st) == 0 then return false end
  local w = M.where(ow)
  if not w then return false end
  local fx, fz = w.x + DX[w.dir], w.z + DZ[w.dir]
  if fx < 0x20 or fx >= 0x80 or fz < 0x20 or fz >= 0x60 then return false end
  if heightAt(w, w.x, w.z) == nil then return false end
  return sameHeight(w, fx, fz), w, fx, fz
end

-- the place / remove rows of GetInteractedMetatileScript, after the
-- field-move rows: { band = "safari", index = 0 | 1 } or nil
function M.fieldRow(ow, behaviour)
  local G = package.loaded["src.core.Game"]
  local save = G and G.save
  if not (save and isSafari(ow)) then return nil end
  local can, w, fx, fz = M.canPlaceAhead(ow, save)
  if can then
    if tileOk(w, fx, fz, w.surfing) then
      return { behaviour = "SAFARI_PLACE", band = "safari", index = 0 }
    end
  end
  if inGame(save) then
    local st = Zone().state(save)
    if st and (tonumber(st.active) or 0) == 0 and behaviour == M.BEH_OBJECT then
      return { behaviour = "SAFARI_REMOVE", band = "safari", index = 1 }
    end
  end
  return nil
end

-- ov02_0224E640: whether the water group is unlocked
function M.waterUnlocked(save)
  local st = Zone().state(save)
  local unlock = Obj().unlockLevel(st)
  local r = M.trainerId(save) % 10
  local q = r < 6 and math.floor(r / 3) or (math.floor((r - 6) / 2) + 2)
  return unlock >= (3 - q) + 1
end

-- ov02_0224E698 (ScrCmd_721)
function M.precheck(ow, save)
  local w = M.where(ow)
  local st = Zone().state(save)
  if not (w and st) then return 0 end
  local area = st.sets[0].areas[M.areaIndex(w.x, w.z) + 1]
  if #((area and area.objects) or {}) >= Obj().MAX_OBJECTS then return 1 end
  if not w.surfing then return 0 end
  if not M.waterUnlocked(save) then return 2 end
  if M.fit22(w, w.x, w.z, w.dir, true) then return 0 end
  return 3
end

-- ov108_021EA700
function M.footprintKind(width, height)
  if width == 1 then return height == 1 and 0 or 1 end
  return height == 1 and 2 or 3
end

-- ov108_021EA63C: the objects Baoba has unlocked, in id order
function M.objectList(save)
  local st = Zone().state(save)
  local unlock = Obj().unlockLevel(st)
  local row = M.ORDER[M.trainerId(save) % 10]
  local have = {}
  for i = 1, math.min(4, unlock) do
    for _, id in ipairs(M.GROUPS[row[i]]) do have[id] = true end
  end
  local out = {}
  for id = 0, 23 do
    if have[id] then
      local c = Obj().config(id)
      out[#out + 1] = { id = id, kind = M.footprintKind(c.width, c.height), type = c.type,
                        animated = id == M.FOUNTAIN }
    end
  end
  return out
end

-- SafariDecoration_CreateArgs
function M.decorationArgs(ow, save)
  local w = M.where(ow)
  local args = { surfing = w and w.surfing or false, area = 0, y = 0, fits = {} }
  if not w then return args end
  args.area = M.areaIndex(w.x, w.z)
  local h = heightAt(w, w.x, w.z)
  if h == nil then return args end
  args.y = math.floor(h)
  local water = w.surfing
  args.fits[0] = { x = w.x + DX[w.dir], z = w.z + DZ[w.dir] }
  local x, z = M.fit12(w, w.x, w.z, w.dir, water)
  if x then args.fits[1] = { x = x, z = z } end
  x, z = M.fit21(w, w.x, w.z, w.dir, water)
  if x then args.fits[2] = { x = x, z = z } end
  x, z = M.fit22(w, w.x, w.z, w.dir, water)
  if x then args.fits[3] = { x = x, z = z } end
  return args
end

-- objects still free in the args' area (0x435)
function M.remaining(save, args)
  local st = Zone().state(save)
  local area = st and st.sets[0].areas[(args.area or 0) + 1]
  return Obj().MAX_OBJECTS - #((area and area.objects) or {})
end

-- ov108_021EA52C: nil, or the msg_0430 line that refuses the entry
function M.refusal(save, args, entry)
  if M.remaining(save, args) <= 0 then return 7 end
  if (args.surfing and true or false) ~= (entry.animated and true or false) then
    return args.surfing and 6 or 5
  end
  if not args.fits[entry.kind] then return 4 end
  return nil
end

-- ov108_021E8C64: into set 0
function M.commit(save, args, entry)
  local at = args.fits[entry.kind]
  if not at then return false end
  local okAdd = Obj().addObject(save, 0, args.area or 0,
    { id = entry.id, x = at.x % 32, y = args.y or 0, z = at.z % 32 })
  if okAdd then pcall(function() require("src.world.HgssSafariProps").changed() end) end
  return okAdd
end

return M
