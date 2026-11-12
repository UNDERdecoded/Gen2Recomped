-- Round 19: REMOVABLE_DUST (projectile $14, projectile/removableDust.c).
--
-- Init (RemovableDust_OnTick action 0): frameIndex = type, gustJarFlags 1,
--   its flag from EntityData +$E (unk_86).
--   type 0 (sub_080AA494): type2 = the index of the tile type under it in
--     gUnk_08129FD0 {387, 1018..1025} (9 = not one of them).  Flag set:
--     index 4 (the middle of a 3 x 3 "Minish rock") loads its
--     MINISH_PORTAL_MANAGER (sub_080AA654), then the dust is gone.  Else
--     SPECIAL_TILE_104 on its tile (blocks).
--   other types: collision layer 3, no tile.
-- Grabbed (the Gust Jar's first contact sets gustJarState bit 2 ->
--   GetNextFunction 5 = RemovableDust_OnGrabbed; also OnCollision with
--   contactFlags $80 | $16, the bomb blast's hurt type):
--   type 0 (sub_080AA544): with type2 < 9, the middle tile = its tile +
--     gUnk_08129FF8[type2]; when 8 of the 9 rock tiles are already ACT_TILE_62
--     (cleared) all 9 get gUnk_08129FD0's types again, the portal manager is
--     loaded (EntityData gUnk_0812A004: MANAGER 3 type 1 type2 $102 at the
--     middle tile) and the flag is set; otherwise only its own tile gets
--     gUnk_08129FE4[type2] {388, 1026..1033}.  type2 9: its tile restored
--     (RestorePrevTileEntity) and the flag set.
--   Then DIRT_PARTICLE (object, type 3) and the dust is deleted.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local D = {}

D.ROCK = { [0] = 387, 1018, 1019, 1020, 1021, 1022, 1023, 1024, 1025 }    -- gUnk_08129FD0
D.CLEAR = { [0] = 388, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033 }   -- gUnk_08129FE4
D.OFF = { [0] = 65, 64, 63, 1, 0, -1, -63, -64, -65 }                     -- gUnk_08129FF8 (tile index steps)
local SP104 = 0x4000 + 104
local ACT_62 = 62
local SFX_EF = 0xEF -- the jar swallows it (sub_0806F3E4 gustJarFlags 1)

local function tileOf(x, y) return math.floor(x / 16), math.floor(y / 16) end
-- a TILE_POS step (64 tiles a row) applied to (tx, ty)
local function step(tx, ty, d)
  local i = ty * 64 + tx + d
  return i % 64, math.floor(i / 64)
end
D.step = step

local function actAt(f, tx, ty, layer)
  local tt = f.room:tileType(layer or 1, tx, ty)
  if not tt or tt >= 0x4000 then return nil, tt end
  return f.assets.actTile and f.assets.actTile[tt], tt
end

-- sub_080AA654: the Minish portal at the rock's middle tile
function D.portal(f, tx, ty)
  local d = { kind = 9, id = 3, paramA = 1, paramB = 0x102, x = tx * 16 + 8, y = ty * 16 + 8 }
  for _, p in ipairs(f.portals or {}) do
    if p.rock and p.rtx == tx and p.rty == ty then return p end
  end
  f:objects():addPortal(d)
  local p = f.portals[#f.portals]
  p.rock, p.rtx, p.rty = true, tx, ty
  return p
end

-- spawn: returns the entity, or nil when it is already gone
function D.spawn(dg, e)
  local f = dg.field
  local r = f.room
  e.dust = true
  e.type = e.form or 0
  e.frameIndex = e.type
  e.staticFrame = e.type -- frameIndex = type, no animation (the spikes were not drawn before)
  e.gustJarFlags = 1
  e.tx, e.ty = tileOf(e.x, e.y)
  if e.type ~= 0 then
    e.layer = 3
    return e
  end
  local tt = r:tileType(e.layer or 1, e.tx, e.ty)
  local index = 9
  for i = 0, 8 do if D.ROCK[i] == tt then index = i break end end
  if dg:check(e.flag) then
    if index == 4 then D.portal(f, e.tx, e.ty) end
    return nil
  end
  e.type2 = index
  local name = (e.layer or 1) == 2 and "top" or "bottom"
  e.prevTile = r.maps[name][e.ty * r.tw + e.tx]
  r:setTile(e.layer or 1, e.tx, e.ty, SP104)
  return e
end

-- RemovableDust_OnGrabbed
function D.grabbed(dg, e)
  if e.deleted then return end
  local f = dg.field
  local r = f.room
  local layer = e.layer or 1
  if e.type == 0 then
    if e.type2 < 9 then
      local cx, cy = step(e.tx, e.ty, D.OFF[e.type2])
      local n = 0
      for k = 0, 8 do
        local x, y = step(cx, cy, -D.OFF[k])
        if actAt(f, x, y, layer) == ACT_62 then n = n + 1 end
      end
      local O = f:objects()
      if n == 8 then
        for k = 0, 8 do
          local x, y = step(cx, cy, -D.OFF[k])
          O:setTileType(layer, x, y, D.ROCK[k])
        end
        D.portal(f, cx, cy)
        dg:set(e.flag)
      else
        local x, y = step(cx, cy, -D.OFF[e.type2])
        O:setTileType(layer, x, y, D.CLEAR[e.type2])
      end
    else
      if e.prevTile then r:setTile(layer, e.tx, e.ty, e.prevTile) end
      dg:set(e.flag)
    end
  end
  -- DIRT_PARTICLE type 3 (SIMPLIFIED: the dirt fx, FX_DEATH's puff)
  if f.addFx then f:addFx(e.x, e.y, 0x0F, 0x02) end
  f:sound(SFX_EF)
  e.deleted = true
end

-- every frame: the Gust Jar's boxes (GustJar.touching) or the bomb blast
function D.update(dg, e)
  local f = dg.field
  local p = f.player
  if p.state == "gust" and require("src.zelda.tmc.GustJar").touching(f, e.x, e.y, 8, 8) then
    return D.grabbed(dg, e)
  end
  for _, s in ipairs(f.entities) do
    if s.smoke and s.hitW and not s.deleted and math.abs(s.x - e.x) < s.hitW + 8 and math.abs(s.y - e.y) < s.hitW + 8 then
      return D.grabbed(dg, e)
    end
  end
end

return D
