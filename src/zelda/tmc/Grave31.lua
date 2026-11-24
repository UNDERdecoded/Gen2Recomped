-- Round 31: PUSHABLE_GRAVE ($71, src/object/pushableGrave.c) -- the Royal
-- Valley graves.  The port drew them (ObjStatic frame = type) with no tile:
-- Link walked through them.  Collide31.sync runs these every frame; Link's
-- push comes from Push31.full (PushAnim.update).
--
-- CARTRIDGE BEHAVIOUR:
--   * Init: draw, frameIndex = type; the nine tiles round it remembered
--     (unk_6a..unk_7a); pushedFlag = EntityData paramC >> 16.  Type 0 (or a
--     type2 != 0) with the flag set: already moved -- y -= $16 (type 0) /
--     $10, then sub_080977F4.  Else action 1: tile = PushableGrave_Tiles
--     [type2] (SPECIAL_TILE_34, 62, 62); type 0 puts it at its tile and the
--     one left of it and y += 2; type 2 also SetMultipleTiles(gUnk_081232C0:
--     SPECIAL_TILE_61 on the 7 tiles round it but straight below).
--   * Action1 (sub_0809785C): type != 0 with type2 != 0: the flag set or
--     its tile turned SPECIAL_TILE_63 (UpdatePlayerCollision: Link facing
--     north, moving, ANIM frame bit 1, against SPECIAL_TILE_62) -> action
--     3: 64 frames north at $40, the remembered tiles back, SFX_10F.
--     Type 0: the flag -> action 2: RestorePrevTileEntity on both tiles;
--     60 frames, then the camera on it for 120, then action 3 (96 frames,
--     SFX_10F).
--   * Action3: LinearMoveUpdate north; then 20 frames; SFX_SECRET,
--     sub_080977F4: action 4, SPECIAL_TILE_34 at its (new) tile (type 0:
--     and the one left of it), the flag set.
-- Round 32: the big grave's camera pan (camera_target = the grave after 60
--   frames, scrollSpeed 2; back on Link when it settles).
-- SIMPLIFIED: sub_0800445C (pushing Link out of the moving grave) is the
--   port's hitbox push-out of nothing (the grave moves away from Link).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local G = {}
G.ID = 0x71
local S34, S61, S62, S63 = 0x4022, 0x403D, 0x403E, 0x403F
G.S62, G.S63 = S62, S63
local TILES = { [0] = S34, S62, S62 } -- PushableGrave_Tiles
local RING = require("src.zelda.tmc.RomTables").t("Grave31.RING") -- gUnk_081232C0 (SPECIAL_TILE_61)
local SFX_10F, SFX_SECRET = 0x10F, 0x72

local function mapAt(r, L, tx, ty)
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return nil end
  return r.maps[L == 2 and "top" or "bottom"][ty * r.tw + tx]
end
local function put(r, L, tx, ty, mt)
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th or not mt then return end
  r:setTile(L, tx, ty, mt)
end
local function off(o) local dy = math.floor((o + 32) / 64) return o - dy * 64, dy end

local function check(f, flag) return flag ~= 0 and f:dungeon():check(flag) end
local function setFlag(f, flag)
  if flag == 0 then return end
  local d = f:dungeon()
  if d.set then d:set(flag) elseif f.setFlag then f:setFlag("local", flag, true) end
end

-- sub_080977F4
local function settle(f, e)
  local r = f.room
  e.graveAction = 4
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  put(r, e.gL, tx, ty, S34)
  if (e.form or 0) == 0 then put(r, e.gL, tx - 1, ty, S34) end
  setFlag(f, e.graveFlag)
end

function G.init(f, e)
  local r = f.room
  local typ, t2 = e.form or 0, band(e.param or 0, 0xFF)
  e.graveFlag = rshift((e.data and e.data.paramC) or 0, 16)
  local L = (e.layer == 2) and 2 or 1
  e.gL = L
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  e.graveSaved = {}
  for dy = -1, 1 do for dx = -1, 1 do e.graveSaved[dy * 64 + dx] = mapAt(r, L, tx + dx, ty + dy) end end
  if (typ == 0 or t2 ~= 0) and check(f, e.graveFlag) then
    e.y = e.y - (typ == 0 and 0x16 or 0x10)
    settle(f, e)
    return
  end
  e.graveAction = 1
  e.graveTile = { tx, ty }
  local mt = TILES[t2] or S34
  if typ == 0 then
    put(r, L, tx - 1, ty, mt); put(r, L, tx, ty, mt)
    e.y = e.y + 2
  else
    put(r, L, tx, ty, mt)
    if t2 == 2 then for _, o in ipairs(RING) do local dx, dy = off(o); put(r, L, tx + dx, ty + dy, S61) end end
  end
end

local function restoreSaved(f, e, all)
  local r, t = f.room, e.graveTile
  put(r, e.gL, t[1], t[2], e.graveSaved[0])
  if all then
    for o, mt in pairs(e.graveSaved) do
      if o ~= 0 then local dx, dy = off(o); put(r, e.gL, t[1] + dx, t[2] + dy, mt) end
    end
  end
end

function G.update(f, e)
  local typ, t2 = e.form or 0, band(e.param or 0, 0xFF)
  local a = e.graveAction
  if a == 1 then
    local t = e.graveTile
    if typ ~= 0 then
      if t2 ~= 0 and (check(f, e.graveFlag) or mapAt(f.room, e.gL, t[1], t[2]) == S63) then
        e.graveAction, e.graveTimer, e.graveSub = 3, 64, 0
        e.graveSpeed = 0x40
        restoreSaved(f, e, t2 == 2)
        f:sound(SFX_10F)
      end
    elseif check(f, e.graveFlag) then
      e.graveAction, e.graveSubAction, e.graveSub = 2, 0, 60
      e.graveSpeed = 0x40
      put(f.room, e.gL, t[1], t[2], e.graveSaved[0]); put(f.room, e.gL, t[1] - 1, t[2], e.graveSaved[-1])
    end
  elseif a == 2 then
    e.graveSub = e.graveSub - 1
    if e.graveSub <= 0 then
      if e.graveSubAction == 0 then
        e.graveSubAction, e.graveSub = 1, 120
        f.cameraTarget, f.scrollSpeed = e, 2 -- round 32: gRoomControls.camera_target = the grave, scrollSpeed 2
      else e.graveAction, e.graveTimer, e.graveSub = 3, 96, 20; f:sound(SFX_10F) end
    end
  elseif a == 3 then
    if e.graveTimer > 0 then
      e.graveTimer = e.graveTimer - 1
      e.y = e.y - e.graveSpeed / 256
    elseif e.graveSub > 0 then
      e.graveSub = e.graveSub - 1
    else
      f:sound(SFX_SECRET)
      settle(f, e)
      if typ == 0 and f.cameraTarget == e then f.cameraTarget, f.scrollSpeed = nil, nil end -- round 32: back on Link (scrollSpeed 4, the port's default pace)
    end
  end
end

return G
