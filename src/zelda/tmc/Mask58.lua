-- Round 58: the wall masks -- MASK, object $5C (src/object/mask.c), and the Mayor's room code that loads them
-- (roomInit.c sub_StateChange_HouseInteriors1_Mayor).  Listed in R37.MODULES.
--
-- The port drew the masks as a fixed frame (ObjStatic) and never loaded the Mayor's: they could not be knocked
-- down, and the Mayor's mask over his house's Minish entrance (the book-3 way) was missing.
--
-- CARTRIDGE BEHAVIOUR:
--   * sub_StateChange_HouseInteriors1_Mayor ($21:00): (u16) gRoomTransition.player_status.start_pos_y > $40 ->
--     LoadRoomEntityList(Entities_HouseInteriors1_Mayor_080D6210) (the four masks).
--   * Mask_Init: type2 & $C0 with its flag set: $40 -> deleted when gRoomTransition.stairs_idx is $44D .. $44F or
--     $182, else ClearFlag (it hangs again); $80 -> deleted.  Then action 1, zVelocity Q_16_16(1.5), unk_78 =
--     ((Random & 7) << 10) | $2000 (the bounce's gravity), subtimer = timer >> 1, timer 0, frameIndex = type2 & $3F;
--     unk_7e = its tile, unk_7c / unk_7a = that tile's bottom-layer index / collision; SetTile(SPECIAL_TILE_34).
--   * Mask_Action1: Link in PLAYER_BOUNCE (the Pegasus Boots' bonk) with animationState 0 (facing up), at most
--     40 px below it (mask y + 40 >= Link's y) and |mask x - Link x| < subtimer -> the tile back (SetTile(unk_7c),
--     SetCollisionData(unk_7a)), action 2, z - $20, y + $20 (it falls from where it hung), spriteRendering.b3 2.
--   * Mask_Action2: timer 1 -> action 3, type2 & $C0: $80 -> SFX_SECRET and SetFlag, $40 -> SetFlag; FX_POT_SHATTER;
--     CreateRandomItemDrop(3).  Else BounceUpdate(unk_78), z 0 -> timer + 1.  Mask_Delete: DeleteThisEntity.
-- SIMPLIFIED: gRoomTransition.stairs_idx is read from f.stairsIdx (0 when the port has none); spriteRendering.b3.
local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local M = {}
M.MASK = 0x5C
M.SPECIAL_TILE_34 = 0x4022
M.SFX_SECRET = 0x72
M.FX_POT_SHATTER, M.SPECIAL_FX = 0x05, 0x0F
M.MAYOR_ROOM = 0x2100 -- HouseInteriors1_Mayor
M.A_MAYOR_MASKS = 0x080D6210 -- Entities_HouseInteriors1_Mayor_080D6210

local function rand(f)
  if M.random then return M.random(f) end -- tests
  local D = require("src.zelda.tmc.Drops")
  return D.random(D.rngOf(f))
end

-- BounceUpdate (cz px, negative up; czv px a frame, positive up) -- BossVaati.H.bounce
local function bounce(e, acc)
  local nz = (e.cz or 0) - (e.czv or 0)
  if nz < 0 then e.cz, e.czv = nz, (e.czv or 0) - acc return 2 end
  e.cz = 0
  local v = -((e.czv or 0) - acc)
  v = v / 2 + v / 8
  if v >= 0.75 then e.czv = v return 1 end
  e.czv = 0
  return 0
end
M.bounce = bounce

-- Mask_Init: returns false when it deletes itself
function M.init(d, e)
  local f = d.field
  local t2 = e.type2 or 0
  local kind = band(t2, 0xC0)
  if kind ~= 0 and d:check(e.flag) then
    if kind == 0x40 then
      local s = f.stairsIdx or 0
      if (s >= 0x44D and s <= 0x44F) or s == 0x182 then return false end
      d:set(e.flag, false)
    elseif kind == 0x80 then
      return false
    end
  end
  e.action = 1
  e.cz, e.czv = 0, 1.5
  e.unk78 = bor(lshift(band(rand(f), 7), 10), 0x2000) / 65536
  e.subtimer = rshift(e.timer0 or 0, 1)
  e.timer = 0
  e.maskFrame = band(t2, 0x3F)
  local r = f.room
  local tx, ty = rshift(math.floor(e.x), 4), rshift(math.floor(e.y), 4)
  e.unk7e = { tx, ty }
  e.unk7c = r and r.maps and r.maps.bottom and r.maps.bottom[ty * r.tw + tx]
  e.unk7a = r and r.coll and r.coll[1] and r.coll[1][ty * r.tw + tx] -- GetCollisionDataAtTilePos (the merged top kept)
  if r and r.setTile then r:setTile(1, tx, ty, M.SPECIAL_TILE_34) end
  return true
end

-- Mask_Action1: the bonk test
function M.bonked(e, p)
  if not p or not p.bounce then return false end -- PLAYER_BOUNCE
  if (p.animationState or 0) ~= 0 then return false end
  if math.floor(e.y) + 40 < math.floor(p.y) then return false end
  local dx = math.floor(e.x) - math.floor(p.x)
  if dx >= e.subtimer or dx <= -e.subtimer then return false end
  return true
end

function M.update(d, e)
  local f = d.field
  if e.action == 1 then
    if not M.bonked(e, f.player) then return end
    local r = f.room
    if e.unk7c and r and r.setTile then r:setTile(1, e.unk7e[1], e.unk7e[2], e.unk7c) end
    if e.unk7a and r and r.coll and r.coll[1] then r.coll[1][e.unk7e[2] * r.tw + e.unk7e[1]] = e.unk7a end -- SetCollisionData(unk_7a)
    e.action = 2
    e.cz = (e.cz or 0) - 0x20
    e.y = e.y + 0x20
  elseif e.action == 2 then
    if e.timer == 1 then
      e.action, e.timer = 3, 0
      local kind = band(e.type2 or 0, 0xC0)
      if kind == 0x80 then f:sound(M.SFX_SECRET); d:set(e.flag, true)
      elseif kind == 0x40 then d:set(e.flag, true) end
      if f.addFx then f:addFx(e.x, e.y, M.SPECIAL_FX, M.FX_POT_SHATTER) end
      pcall(require("src.zelda.tmc.Drops").randomDrop, f, { x = e.x, y = e.y, z = 0, layer = 1 }, 3, f:objects())
    else
      bounce(e, e.unk78)
      if (e.cz or 0) == 0 then e.timer = e.timer + 1 end
    end
  elseif e.action == 3 then
    e.deleted, e.hidden = true, true -- Mask_Delete
  end
  e.z = -(e.cz or 0)
end

function M.spawnObject(d, e)
  if e.id ~= M.MASK then return nil end
  local f = d.field
  if not M.init(d, e) then e.deleted, e.hidden = true, true return e end
  local def = f:objects():def(M.MASK, e.form or 0)
  if def then
    f:objects():dress(e, def, 0)
    e.objAnim = 0
    require("src.zelda.tmc.ObjStatic").apply(f, e, e.data or {})
  end
  e.extUpdate = function(dd, me) if not me.deleted then M.update(dd, me) end end
  d:track(e)
  return e
end

-- sub_StateChange_HouseInteriors1_Mayor
function M.roomInit(f)
  local r = f.room
  if not r or (r.area or 0) * 256 + (r.room or 0) ~= M.MAYOR_ROOM then return end
  local p = f.player
  if p and math.floor(p.y) > 0x40 then f:loadEntityList(M.A_MAYOR_MASKS) end
end

return M
