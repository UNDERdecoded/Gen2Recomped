-- Round 81: ROTATING_TRAPDOOR ($44, src/object/rotatingTrapdoor.c) and Link's two uses of it --
-- the square hatches in the Palace of Winds' grates ($70:21 "GratesTo3F": the east section's
-- hatch drops Link to the floor under the grates, the middle one lifts him back up).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * sub_08077F84 (playerUtils.c), called by ItemRocsCape when a jump starts: Link on the bottom
--     layer ((collisionLayer & 2) == 0) and the TOP layer's tile type at (x, y - 12) one of
--     TILE_TYPE_835 .. 838 ($343 .. $346, the hatch's four quarters) -> sub_0807AA80 (collision
--     layer 2), jump_status |= 8, CreateObject(ROTATING_TRAPDOOR) at (x, y - 12), Link y -= 12.
--   * sub_0807A2B8, called by the landing (sub_08073AD4) before jump_status is cleared: unless
--     PlayerCheckNEastTile (Link over a pit / hole), with (jump_status & $C8) == 0 (not a hole /
--     ledge jump, not the hatch's own jump) and collisionLayer != 1 ->
--     CreateObjectWithParent(ROTATING_TRAPDOOR) at Link's position.
--   * RotatingTrapdoor_Init: collisionLayer 2; the top tile type at its position: $343 -> x + 16,
--     y + 16; $344 -> y + 16; $345 -> x + 16; $346 -> as is; anything else -> DeleteThisEntity;
--     x, y &= ~15 (the hatch's centre); animation 0; sub_0808E354($347): the four tiles
--     (x - 16, y - 16), (x, y - 16), (x - 16, y), (x, y) of the top layer become $347 .. $34A;
--     then Action1 at once.
--   * RotatingTrapdoor_Action1: GetNextFrame; ANIM_DONE -> the tiles back to $343 .. $346 and
--     DeleteThisEntity; a keyframe with flag 1 -> EnqueueSFX(SFX_18B).
--   * The turning tiles' act tile is ACT_TILE_97 ($61) -> SURFACE_1B: SurfaceAction_1B (Link on
--     the ground: not jumping or in the landing state, z 0): collisionLayer != 1 -> y += 12 and,
--     not Minish, z -= 12; sub_0807AABC (collisionLayer 1).  Off the ground, PlayerNormal /
--     sub_08073A94 hand over to sub_08073924: jump_status $40, no direction, DoJump (ANIM_HOP,
--     SFX_PLY_JUMP, gravity) -> the landing on the floor below.
-- The tile types and the animation come from the player's ROM (the room's metatiles, the
-- object's sprite); the module holds the cartridge's numbers only.
-- SIMPLIFIED: the floor type is tested in the hatch's own frame (it only exists while the hatch
--   turns), one frame after the landing as the cartridge's next UpdateFloorType does; the Down
--   Thrust's landing (sub_08073B8C also calls sub_0807A2B8) is not hooked.
local bit = require("bit")
local band, bor = bit.band, bit.bor

local M = {}
M.ID = 0x44                     -- ROTATING_TRAPDOOR
M.TT0, M.TT_TURN = 0x343, 0x347 -- TILE_TYPE_835 (still), TILE_TYPE_839 (turning)
M.ACT_1B = 0x61                 -- ACT_TILE_97 -> SURFACE_1B
M.SFX = 0x18B                   -- SFX_18B
M.LIFT = 12                     -- the 12 px of sub_08077F84 / SurfaceAction_1B
M.NO_HATCH = 0xC8               -- jump_status bits that skip sub_0807A2B8's hatch

function M.isHatch(tt) return tt ~= nil and tt >= M.TT0 and tt <= M.TT0 + 3 end

-- RotatingTrapdoor_Init's position from the tile type under it; nil = DeleteThisEntity
function M.initPos(tt, x, y)
  local dx, dy
  if tt == M.TT0 then dx, dy = 16, 16
  elseif tt == M.TT0 + 1 then dx, dy = 0, 16
  elseif tt == M.TT0 + 2 then dx, dy = 16, 0
  elseif tt == M.TT0 + 3 then dx, dy = 0, 0
  else return nil end
  return band(math.floor(x) + dx, 0xFFF0), band(math.floor(y) + dy, 0xFFF0)
end

-- sub_0808E354: the four top-layer tiles {tx, ty, tile type} around the hatch's centre
function M.quarters(x, y, base)
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  return { { tx - 1, ty - 1, base }, { tx, ty - 1, base + 1 }, { tx - 1, ty, base + 2 }, { tx, ty, base + 3 } }
end

local function topType(f, x, y)
  local r = f.room
  if not (r and r.tileType) then return nil end
  return r:tileType(2, math.floor(x / 16), math.floor(y / 16))
end

local function setTiles(f, e, base)
  local O = f.objects and f:objects()
  if not O then return end
  for _, q in ipairs(M.quarters(e.x, e.y, base)) do O:setTileType(2, q[1], q[2], q[3]) end
end

-- CreateObject(ROTATING_TRAPDOOR) at (x, y) + its Init (+ Action1)
function M.create(f, x, y)
  local d = f.dungeon and f:dungeon()
  if not d then return nil end
  local nx, ny = M.initPos(topType(f, x, y), x, y)
  if not nx then return nil end
  local e = { kind = 6, id = M.ID, form = 0, x = nx, y = ny, z = 0, animationState = 0, field80 = 0, field82 = 0,
              interactType = 0, layer = 2, trapdoor81 = true, literalAnim = true, objAnim = 0 }
  local O = f:objects()
  local def = O and O.def and O:def(M.ID, 0)
  if def then
    O:dress(e, def, 0)
    e.objAnim = 0
    if f.assets and f.assets.sprite and e.anim then e.anim:set(f.assets:sprite(e.sprite), 0, true); e.animIndex = 0 end
  end
  setTiles(f, e, M.TT_TURN)
  e.extUpdate = function(dd, me) M.update(dd.field, me) end
  f.entities[#f.entities + 1] = e
  d:track(e)
  M.update(f, e)
  return e
end

-- RotatingTrapdoor_Action1 (+ the player's floor this frame while the hatch turns)
function M.update(f, e)
  if e.deleted then return end
  if e.seen81 then M.floor(f) end
  e.seen81 = true
  local a = e.anim
  if not (a and a.keys) then setTiles(f, e, M.TT0); e.deleted = true; return end -- no animation: nothing to turn
  a:update(1)
  local fl = a.flags or 0
  if a.done or band(fl, 0x80) ~= 0 then
    setTiles(f, e, M.TT0)
    e.deleted = true
    return
  end
  if band(fl, 1) ~= 0 and f.sound then f:sound(M.SFX) end
end

-- sub_080741C4 == 0: on the ground (no jump, or the landing state) and z 0
function M.onGround(p)
  if (p.z or 0) ~= 0 then return false end
  if p.jump and p.jump.phase ~= 3 then return false end
  return true
end

-- SurfaceAction_1B for Link's floor
function M.floor(f)
  local p = f.player
  if not p or p.hidden or p.state == "dead" then return end
  if (p.layer or 1) == 1 or not M.onGround(p) then return end
  local d = f.dungeon and f:dungeon()
  local act = d and d:actAt(math.floor(p.x), math.floor(p.y), p.layer)
  if act ~= M.ACT_1B then return end
  M.drop(p)
end

function M.drop(p)
  p.y = p.y + M.LIFT
  if not p.minish then p.z = M.LIFT end
  p.layer = 1 -- sub_0807AABC
  if (p.z or 0) > 0 then M.fall(p) end
end

-- sub_08073924: jump_status $40, no direction -> DoJump from sub_08073968 (ANIM_HOP, SFX_PLY_JUMP)
function M.fall(p)
  local IC = require("src.zelda.tmc.ItemCape")
  p.airVx, p.airVy = 0, 0
  p.jump = { phase = 1, stage = 1, button = nil, cape = false, status = 0x40 }
  p.jumping = true
  p.zv = 0
  p.state = "ext"
  p.extUpdate = function(pl) IC.step(pl, nil) end
end

-- sub_08077F84 (the cape's jump starts)
function M.jumpStart(p)
  local f = p.field
  if not f or band(p.layer or 1, 2) ~= 0 then return false end
  if not M.isHatch(topType(f, p.x, p.y - M.LIFT)) then return false end
  p.layer = 2 -- sub_0807AA80
  if p.jump then p.jump.status = bor(p.jump.status or 0, 8) end
  M.create(f, p.x, p.y - M.LIFT)
  p.y = p.y - M.LIFT
  return true
end

-- sub_0807A2B8 (the landing)
function M.landed(p, j)
  if band(j and j.status or 0, M.NO_HATCH) ~= 0 then return nil end
  if (p.layer or 1) == 1 then return nil end
  return M.create(p.field, p.x, p.y)
end

function M.install(IC)
  if IC._trap81 then return end
  IC._trap81 = true
  local use0, step0 = IC.use, IC.step
  IC.use = function(p, item, button, input)
    local r = use0(p, item, button, input)
    if r and p.jump then M.jumpStart(p) end
    return r
  end
  IC.step = function(p, input)
    local j = p.jump
    local ph = j and j.phase
    step0(p, input)
    if j and ph == 2 and p.jump == j and j.phase == 3 then M.landed(p, j) end
  end
end

return M
