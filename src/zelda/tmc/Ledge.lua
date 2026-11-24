-- Round 12: jumping off a ledge (playerUtils.c sub_08079550, player.c
-- PlayerJump).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Walking in the facing direction, two probe points ahead of Link are
--     looked up: facing east/west at (x + gUnk_0811C100[s].x, y -/+
--     hitbox.unk2[1]), north/south at (x -/+ hitbox.unk2[2], y +
--     gUnk_0811C100[s].y); both act tiles must be keys of
--     gUnk_0811C1E8[facing] (FindValueForKey: the value is the new 8-way
--     animation state + 1); the 6th frame pushing into them starts
--     PLAYER_JUMP.
--   * PlayerJumpInit: ANIM_JUMP (_NOCAP), direction = the 8-way state * 4,
--     zVelocity ((n << 4) - 4) << 12 with n = sub_08079FD4(1) (tiles ahead
--     until the bottom collision is below $F, solid $1D / $23 / $27 /
--     gUnk_080082DC ones go on), speed kJumpSpeedForward, SFX_PLY_JUMP +
--     SFX_PLY_VO4.
--   * sub_08071130: the move happens only on keyframes without flag bit 0
--     (UpdateAnimationSingleFrame), LinearMoveUpdate with no collision,
--     GravityUpdate(kGravityRate); landed: ANIM_LAND for 6 frames,
--     SFX_PLY_LAND, then normal (sub_08071208).
-- The tables are read from the player's ROM (ExtractR12.lua: ledge).
local bit = require("bit")
local band = bit.band

local L = {}

local GRAV = 0.125
local ANIM_JUMP, ANIM_JUMP_NOCAP, ANIM_LAND, ANIM_LAND_NOCAP = 0x810, 0x420, 0x820, 0x424
local SFX_PLY_JUMP, SFX_PLY_LAND, SFX_PLY_VO4 = 0x7C, 0x7D, 0x78

local SIN = {}
for i = 0, 255 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
local function linear(pl, dir, speed)
  local a = (dir * 8) % 256
  pl.x = pl.x + SIN[a] * speed / 65536
  pl.y = pl.y - SIN[(a + 64) % 256] * speed / 65536
end

local function tables(f)
  local r = f.assets and f.assets.manifest and f.assets.manifest.r12
  return r and r.ledge
end

local function actAt(f, x, y, layer)
  local tt = f.room:tileType(layer or 1, math.floor(x / 16), math.floor(y / 16))
  if not tt or tt >= 0x4000 then return nil end
  return f.assets.actTile[tt]
end

local function find(list, key)
  for _, kv in ipairs(list or {}) do if kv[1] == key then return kv[2] end end
  return 0
end

-- sub_08079FD4(this, 1): tiles of ledge ahead (bottom collision)
local STEP = { [0] = { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 } }
function L.count(f, pl, dir8)
  local T = tables(f)
  local tx, ty = math.floor(pl.x / 16), math.floor(pl.y / 16)
  local s = STEP[dir8]
  local coll = f.room.coll and f.room.coll[1]
  local n = 0
  for _ = 1, 8 do
    n = n + 1
    tx, ty = tx + s[1], ty + s[2]
    local c = coll and coll[ty * f.room.tw + tx] or 0
    if c < 0xF then return n end
    -- the port's collision map marks raised floors $F too: a tile Link can
    -- stand on ends the count as the cartridge's open tile would
    if not f.room:isSolidPlayer(tx * 16 + 8, ty * 16 + 8, 1, 0) then return n end -- gMapBottom, as the cartridge
    if c >= 0x10 and c ~= 0x1D and c ~= 0x23 and c ~= 0x27 and (T and T.coll[c - 0x10] or 0) == 0 then return n end
    if c == 0x1D then return n end
  end
  return n
end

-- each frame of normal walking (Player:update, after the move)
function L.check(pl, dx, dy)
  local f = pl.field
  local T = tables(f)
  -- round 41: Minish Link jumps ledges too (PlayerMinish's walk,
  -- sub_08073D20, calls sub_08079550 as PlayerNormal does): the Cave of
  -- Flames' $50:09 walkway is left only that way
  if not T or pl.state ~= "normal" or (pl.z or 0) ~= 0 or pl.carrying then pl.ledgePush = 0 return end
  -- round 42: hidden in a Minish crack / log (type2 $80) the surface
  -- action wrote the collisions word (COL_NORTH_FULL | COL_SOUTH_FULL for an
  -- east-west tunnel): sub_08079550 sees no ledge ahead.  $50:10's crack
  -- (376,152) -> (296,152) has a west ledge tile (ACT $2D) inside it: Link
  -- jumped out of the tunnel still hidden and walked through the blocks
  if pl.tunnel then pl.ledgePush = 0 return end
  local s = pl.animationState or 4
  local held = (dx ~= 0 or dy ~= 0) and ((s == 0 and dy < 0) or (s == 4 and dy > 0) or (s == 2 and dx > 0) or (s == 6 and dx < 0))
  if not held then pl.ledgePush = 0 return end
  local hb = require("src.zelda.tmc.Hitboxes").player(f, pl)
  local u = hb and hb.u or { 5, 5, 5, 5 }
  local o = T.offsets[band(s, 6) / 2]
  local x, y = math.floor(pl.x), math.floor(pl.y)
  local ax, ay, bx, by
  if band(s, 2) ~= 0 then ax, ay, bx, by = x + o[1], y + u[2], x + o[1], y - u[2]
  else ax, ay, bx, by = x + u[3], y + o[2], x - u[3], y + o[2] end
  local list = T.jump[band(s, 6) / 2]
  local v = find(list, actAt(f, ax, ay, pl.layer))
  if v == 0 or find(list, actAt(f, bx, by, pl.layer)) == 0 then pl.ledgePush = 0 return end
  pl.ledgePush = (pl.ledgePush or 0) + 1
  if pl.ledgePush <= 5 then return end
  pl.ledgePush = 0
  -- PLAYER_JUMP / PlayerJumpInit
  local s8 = v - 1
  pl.state = "ext"
  pl.extUpdate = L.update
  pl.ledge = { dir = s8 * 4, sub = 1 }
  pl.animationState = band(s8, 6)
  local n = L.count(f, pl, s8)
  pl.zv, pl.z = ((n * 16) - 4) / 16, 0
  pl.ledge.minish = pl.minish or nil
  -- PlayerJumpInit: the jump animation is not set for PL_MINISH (he keeps
  -- his walk animation)
  if not pl.minish then pl:setAnim(pl.hasCap and ANIM_JUMP or ANIM_JUMP_NOCAP, true) end
  f:sound(SFX_PLY_JUMP); f:sound(SFX_PLY_VO4)
end

function L.update(pl, input)
  local j = pl.ledge
  local f = pl.field
  if j.sub == 1 then
    -- sub_08071130
    pl.anim:update(1)
    if band(pl.anim.flags or 0, 1) ~= 0 then return end
    linear(pl, j.dir, 0x100)
    local nz = (pl.z or 0) + pl.zv
    if nz > 0 then pl.z, pl.zv = nz, pl.zv - GRAV return end
    pl.z, pl.zv = 0, 0
    -- round 54: ResetCollisionLayer ($0800455E) stores collisionLayer 1 -- it
    -- is not ResolveCollisionLayer (the top map's tile under Link put him on
    -- layer 2 inside Lake Hylia's canopy, stuck); the per-frame surface
    -- check (Layers.surface, sub_0807A8D8) moves him up where the tile says
    local Lay = require("src.zelda.tmc.Layers")
    pl.layer = 1
    Lay.update(f, pl)
    j.sub, j.timer = 2, 6
    if not j.minish then pl:setAnim(pl.hasCap and ANIM_LAND or ANIM_LAND_NOCAP, true) end
    f:sound(SFX_PLY_LAND)
  else
    -- sub_08071208 (no animation step for PL_MINISH)
    if not j.minish then pl.anim:update(1) end
    if j.timer == 0 then
      pl.x, pl.y = math.floor(pl.x), math.floor(pl.y)
      pl.state = "normal"
      pl.extUpdate = nil
      pl.ledge = nil
      return
    end
    j.timer = j.timer - 1
  end
end

return L
