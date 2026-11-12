-- Round 26 (team B, group "fow"): Fortress of Winds enemies, from the decomp.
-- Dispatched by R26.lua (handles / update / spawnEnemy); fake-data test:
-- tests/zelda_tmc_r26b_fow_test.lua.
--
-- SPARK ($1C, src/enemy/spark.c):
--   Init sub_0802B33C: home, action 1, direction = type2, subtimer 120,
--     animation 0.  Action 1 sub_0802B35C: GetNextFrame, ProcessMovement0
--     (collisions = CalculateEntityTileCollisions before the move); no
--     collision: every 120 frames turn (type 0 east-wise +8, type 1 -8,
--     DirectionRound); a collision: the wall-following switch on the
--     COL_* bits (ported bit for bit).  OnCollision: the Boomerang ($14)
--     -> collision off, hidden, action 2, FX_DEATH, timer 14 -> action 2
--     sub_0802B4A8: GROUND_ITEM $60 four pixels up, deleted.
-- WIZZROBE_WIND / FIRE / ICE ($27 / $28 / $29, wizzrobeWind.c / Fire.c /
--   Ice.c, include/enemy/wizzrobe.h):
--   Init: home, action 1, timer2 $FF, timer1 $28, timer 40, subtimer 96,
--     sub_0802F888 (direction = (facing Link (target 3) + 4) & $18, its
--     tile marked SPECIAL_TILE_113), the type-0 projectile held on it.
--   Action 1: subtimer -> timer2 0; timer 40 -> collision on, timer 16 /
--     14 / 12; that -> action 2, timer 40 / 32 / 32, the held orb shown
--     (timer 1), animation dir>>3 | 4.
--   Action 2: timer2 0: on 8 / 6 / 10 left, Link within $A0 and on screen:
--     a type-1 projectile (direction & $18); 0: timer 56, orb hidden.
--     1: -> timer1 $28, timer 40, collision off, tile back, SFX_156,
--     animation dir>>3.  2: -> hidden, timer (R & $3F) + 32 / 28 / 24.
--     3: -> action 1, SFX_156, sub_0802F8E4 (a random free tile in the
--     home, not SPECIAL_TILE_113, inside the home; re-marked).
--   sub_0802F9C8: subtimer 0: timer1 counts -- blinking (draw = !(t & 1));
--     GetNextFrame.  WIZZROBE_WIND type2 != 0 (action 3, the waypoint
--     glide, sub_0802FA48 / FA88) is ported but no room uses it.
--   OnCollision (Fire / Ice / Wind): health 0 -> its tile back.
-- WIND / FIRE / ICE_PROJECTILE (7 / 8 / 9, src/projectile/*Projectile.c):
--   type 0 (action 1): the orb on its Wizzrobe (CopyPosition while drawn;
--     timer set -> InitializeAnimation(direction >> 3); Wind follows
--     (parent direction + 4) & $18); deleted with its parent.
--   type 1: action 2, animation dir>>3 | 4, SFX_15F / 15E / 160;
--     ProcessMovement3 until a wall (action 3: collision off, the burst
--     animation, then deleted) or off screen (deleted).  Touching Link:
--     gCollisionMtx damage, deleted (GetNextFunction != 0).
-- EYEGORE ($2B, src/enemy/eyegore.c): every action and helper is ported:
--   Init (tile-aligned, x & $FFF0, y | $C, 2x2 SPECIAL_TILE_34 under it,
--   flag = paramB low half), Action1 (wakes on its flag), 2 (timer, Link in
--   its home -> 3), 3 (shake gUnk_080CE2BC, wake animation, collision on),
--   4 (the step cycle driven by the animation's frame flags: 1 = pick a
--   direction sub_08031024 + hop zVelocity 1+3/32 SFX_157, 2 = airborne
--   (sub_08031250 move / home return, GravityUpdate 28) landing
--   sub_08030E70 (two FX_DEATH puffs gUnk_080CE2F4, SFX_158)), 5 (turns
--   back south and sleeps), 6.  OnCollision: an arrow ($15) or $0E from
--   straight in front into its eye (gUnk sizes) -> health - 1 (or 0),
--   iframes, SFX_HIT; asleep (action 1) -> it wakes (SFX_BUTTON_PRESS).
--   OnDeath: 60 frames of gravity, FX_GIANT_EXPLOSION4, the death.
-- ARMOS ($2A, src/enemy/armos.c): Init (armos slot = timer, the saved
--   armos_data position / state (gRoomTransition, kept per field here),
--   unk_84 = (0x47D >> slot) & 1, the room property transition = type2),
--   1 (statue: type 0 wakes when Link touches it, type 1 when he is in its
--   home within $10 on x, slot 2 by its own rule), 2 (the wake animation:
--   flags 1 = shake gUnk_080CE160, 2 = hitType 8 / hitbox gUnk_080FD2F0,
--   its tile freed, SFX_12A), 3 (walk: sub_08030A04 SFX_101, timer 24 ->
--   sub_080306C4 chase: sub_0800132C, gUnk_080CE164 wall test), 4 (back to
--   a tile centre, sub_080305BC), 5 (statue again: hitType 1, gHitbox_15,
--   tile blocked), 6 / 7 (slot 2's slide south), 8 (hit).  Speed by health
--   (sub_080309E8).  Frame $25 shows as $19 when unk_84.  Minish Link at
--   its feet (sub_0803086C): SPECIAL_TILE_73 opens, walking in does the
--   room property's Transition (read from the ROM: ROM_RANGES).
-- STALFOS ($42, src/enemy/stalfos.c): types 0 (jumps at Link within $24)
--   and 1 (throws bones within $48).  Init / every action 1-12 / helpers
--   sub_08039758, 0803981C, 08039858 (gUnk_080CF8F8 turn animations),
--   080398C0, 0803992C (gUnk_080CF900, gUnk_080CF910), 0803998C
--   (gUnk_080CF918), 080399C4 (two FX_DASH), 08039A00 (gUnk_080CF928),
--   08039A20 (BONE_PROJECTILE, SFX_FB), 08039A48 (headless, hitType $47),
--   08039A70 (gUnk_080CF92C), 08039AD4 / 08039B28 (pick up a pot ($4000)
--   or a skull ($4060) in front: gUnk_080CF930 / gUnk_080CF938).  The
--   unk_7c hitType $45 window; OnCollision: the sword (4-6) on hitType
--   $44 with no iframes from the matrix -> the jump back; the Cane ($1D)
--   knocks its head (or the pot it wears) off.  type2 1 (out of a flying
--   skull): starts in the jump (action 4).
-- STALFOS_PROJECTILE ($10, stalfosProjectile.c): the pot (type 0, anim 5)
--   or skull (type 1) on a Stalfos' head: action 1 follows the pick-up
--   frames (gUnk_08129B20), 2 sits on the head (gUnk_08129B50), 3 flips
--   off (zVelocity 2.625, gravity 32) and breaks (FX_POT_SHATTER /
--   FX_BONE).  The Cane ($1D) flips it.
-- BONE_PROJECTILE (2, boneProjectile.c): 60 frames straight
--   (ProcessMovement3), then falls (speed $120, gravity 24), bounces
--   (speed $E0, zVelocity 0.875, blinking) and goes; Link's body -> gone,
--   anything else (the shield) -> knocked back (action 4).
-- FLYING_SKULL ($43, src/enemy/flyingSkull.c): Init sub_08039D74 (y + 3,
--   SPECIAL_TILE_96 under it), action 1 sub_08039DD8 (type 0: liftable,
--   carried and thrown it breaks: FX_BONE; types 1-3 wait for full-size
--   Link within $30: type 1 shakes (action 3, gUnk_080CFBE4), rises
--   (action 4: hitType $A0, gUnk_080FD34C, z -1 a frame to -6), waits 10
--   (action 5) and flies at him (action 6, ProcessMovement2) until it
--   hits something; types 2 / 3 become a STALFOS (type - 2, type2 1)),
--   action 7 (the Cane's flip, gravity 32), sub_0803A100 (a Stalfos took
--   it: SPECIAL_TILE_103).  OnCollision: $1D -> action 7; in the air ->
--   breaks.
-- SIMPLIFIED: ProcessMovement0/2's corner slide is the port's per-axis
--   slide (EnemyDeepwood.move0); the hitbox unk2 probe sizes for
--   CalculateEntityTileCollisions are taken from the hitbox (w, h-2, w-2,
--   h); special tiles (113 / 96 / 103 / 34) are bookkeeping here (34 =
--   Dungeon:block); the Gust Jar's OnGrabbed handlers, the Lantern's FLAME
--   on a Wizzrobe ($87), Fire / Ice projectile burn / freeze, the arrow's
--   sprite stuck in the Eyegore's eye (sub_08031344), DoTileInteraction(9)
--   under the Eyegore's feet, FX offsets / FX_STARS and Stalfos type 0's
--   own death table ($F3) are not ported (the generic death is used).
--   Eyegore: the landing puff fires once per landing.
local bit = require("bit")
local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

local M = {}
local ID = { SPARK = 0x1C, WIND = 0x27, FIRE = 0x28, ICE = 0x29, ARMOS = 0x2A, EYEGORE = 0x2B, STALFOS = 0x42, SKULL = 0x43 }
M.ID = ID
local PROJ = { BONE = 0x02, WIND = 0x07, FIRE = 0x08, ICE = 0x09, STALFOS = 0x10 }
M.PROJ = PROJ

local SFX = { PLY_LAND = 0x7D, S156 = 0x156, S157 = 0x157, S158 = 0x158, S15E = 0x15E, S15F = 0x15F, S160 = 0x160,
              S186 = 0x186, S12B = 0x12B, S14B = 0x14B, FB = 0xFB, HIT = 0xFE, BUTTON_PRESS = 0x10C, S12A = 0x12A,
              S101 = 0x101, SHIELD = 0x118 }
M.SFX = SFX
local FX = { DEATH = 0x02, POT_SHATTER = 0x05, DASH = 0x11, BONE = 0x3C, GIANT_EXPLOSION4 = 0x51 }
M.FX = FX
local SPECIAL_FX = 0x0F

-- collisions (include/collision.h)
local COL = { NORTH_WEST = 0x2, NORTH_EAST = 0x4, NORTH_ANY = 0xE, SOUTH_WEST = 0x20, SOUTH_EAST = 0x40, SOUTH_ANY = 0xE0,
              WEST_SOUTH = 0x200, WEST_NORTH = 0x400, WEST_ANY = 0xE00, EAST_SOUTH = 0x2000, EAST_NORTH = 0x4000, EAST_ANY = 0xE000 }
M.COL = COL

-- small tables written out in the decomp's .c sources
M.STALFOS_TURN = { [0] = 28, 29, 30, 31, 32, 33, 34, 35 }                                          -- gUnk_080CF8F8
M.STALFOS_WALK = { [0] = 60, 60, 90, 90, 90, 90, 120, 120, 120, 120, 120, 120, 120, 120, 150, 150 } -- gUnk_080CF900
M.STALFOS_WALL = { [0] = 8, 32768, 128, 2048 }                                                      -- gUnk_080CF910
M.STALFOS_REST = { [0] = 10, 10, 15, 15, 15, 15, 20, 20, 20, 20, 20, 25, 25, 25, 30, 30 }          -- gUnk_080CF918
M.STALFOS_COOL = { [0] = 30, 60, 60, 90 }                                                           -- gUnk_080CF928
M.STALFOS_HEADLESS = { [0] = 45, 60, 75, 90 }                                                       -- gUnk_080CF92C
M.STALFOS_FRONT = { [0] = 0, -8, 8, 0, 0, 8, -8, 0 }                                               -- gUnk_080CF930 (s8)
M.STALFOS_PICK = { { 0x4000, 0 }, { 0x4060, 1 } }                                                   -- gUnk_080CF938
M.SPROJ_PICK = { [0] = { 0, -9, -1 }, { 0, 5, -25 }, { 0, 3, -20 }, { 0, 0, -14 }, { 10, 0, -1 }, { -5, 0, -24 },
  { -3, 0, -20 }, { 0, 0, -13 }, { 0, 5, -1 }, { 0, -5, -19 }, { 0, -3, -16 }, { 0, 0, -11 },
  { -10, 0, -1 }, { 5, 0, -24 }, { 3, 0, -20 }, { 0, 0, -13 } }                                     -- gUnk_08129B20
M.SPROJ_BOB = { [0] = -15, -13, -14, -15, -13, -14, 0, 0 }                                          -- gUnk_08129B50 (s8)
M.SKULL_SHAKE = { [0] = -1, 1, 1, -1 }                                                              -- gUnk_080CFBE4
M.EYE_SHAKE = { [0] = 0, -1, 0, 1 }                                                                 -- gUnk_080CE2BC (u8 255 = -1 as an offset)
M.EYE_PROBE = { [0] = -8, -10, 8, -10, 16, -4, 16, 4, -8, 10, 8, 10, -16, -4, -16, 4 }               -- gUnk_080CE2C0 (first 16)
M.EYE_PUFF = { [0] = -11, 9, 11, 9, -9, -2, -8, 10, -11, -1, 11, -1, 9, -2, 8, 10 }                 -- gUnk_080CE2F4
M.ARMOS_SHAKE = { [0] = -1, 0, 1, 0 }                                                               -- gUnk_080CE160 (u8 255 = -1)
M.ARMOS_PROBE = { [0] = 0, -7, 7, 0, 0, 7, -7, 0 }                                                  -- gUnk_080CE164
-- per Wizzrobe: Action1 timer after collision on, Action2 cast time, shot tick, hidden base (gUnk in each .c)
M.WIZ = {
  [ID.WIND] = { on = 16, cast = 40, shot = 8, hide = 32, proj = PROJ.WIND, sfx = SFX.S15F },
  [ID.FIRE] = { on = 14, cast = 32, shot = 6, hide = 28, proj = PROJ.FIRE, sfx = SFX.S15E },
  [ID.ICE] = { on = 12, cast = 32, shot = 10, hide = 24, proj = PROJ.ICE, sfx = SFX.S160 },
}
-- hitboxes (src/data/hitbox.c)
local HB_EYE_AWAKE = { x = 0, y = -12, w = 8, h = 8 }   -- gUnk_080FD308
local HB_ARMOS = { x = 0, y = 0, w = 6, h = 6 }         -- gUnk_080FD2F0
local HB_ARMOS_STATUE = { x = 0, y = 0, w = 9, h = 9 }  -- gHitbox_15
local HB_SKULL_FLY = { x = 0, y = 0, w = 4, h = 4 }     -- gUnk_080FD34C
local HB_SKULL_HELD = { x = 0, y = 0, w = 3, h = 3 }    -- gUnk_080FD340
M.HB = { EYE_AWAKE = HB_EYE_AWAKE, ARMOS = HB_ARMOS, ARMOS_STATUE = HB_ARMOS_STATUE, SKULL_FLY = HB_SKULL_FLY }

-- the Armos' room property transitions (FoW EastKeyLever properties 8 / 9:
-- gUnk_additional_8/9_FortressOfWinds_EastKeyLever, two Transition structs)
M.ROM_RANGES = { fowArmosTransitions = { 0x080E1D5C, 0x080E1D84 } }

-- ===========================================================================
-- helpers
-- ===========================================================================
local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function Rnd(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end
M.rand = Rnd
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function fl(e) return e.anim and e.anim.flags or 0 end
local function done(e) return e.anim and (e.anim.done or band(fl(e), 0x80) ~= 0) end
local function eat(e, mask) if e.anim then e.anim.flags = band(fl(e), bit.bnot(mask or 0xFF)) end end
local function target(f) return DW().target(f) end
local function dirTo(ax, ay, bx, by) return DW().dirTo(ax, ay, bx, by) end
local function fx(f, x, y, t) if f.addFx then f:addFx(x, y, SPECIAL_FX, t) end end
local function snd(f, id) if f.sound then f:sound(id) end end
local function L(e) return (e.layer == 2) and 2 or 1 end

-- sub_08049FDC(e, 1): the target inside the home rectangle
local function linkInHome(f, e)
  local t = target(f)
  if not t then return false end
  local dx, dy = math.floor(t.x) - (e.homeX or 0), math.floor(t.y) - (e.homeY or 0)
  return dx >= 0 and dx <= (e.rangeW or 0) and dy >= 0 and dy <= (e.rangeH or 0)
end
M.linkInHome = linkInHome
-- sub_08049FA0: itself inside its home
local function selfInHome(e)
  local dx, dy = math.floor(e.x) - (e.homeX or 0), math.floor(e.y) - (e.homeY or 0)
  return dx >= 0 and dx <= (e.rangeW or 0) and dy >= 0 and dy <= (e.rangeH or 0)
end
-- sub_08049EE4: toward the home's centre
local function homeDir(e) return dirTo(e.x, e.y, (e.homeX or 0) + (e.rangeW or 0) / 2, (e.homeY or 0) + (e.rangeH or 0) / 2) end
-- EntityWithinDistance (layer-free)
local function within(e, x, y, d) return (math.floor(x) - math.floor(e.x)) ^ 2 + (math.floor(y) - math.floor(e.y)) ^ 2 <= d * d end

-- direction (0-31) -> unit vector
local function dirVec(d)
  local a = (d % 32) / 32 * 2 * math.pi
  return math.sin(a), -math.cos(a)
end
M.dirVec = dirVec
local function linear(e, dir, spd) -- LinearMoveUpdate
  if not dir or dir >= 0x20 then return end
  local vx, vy = dirVec(dir)
  e.x, e.y = e.x + vx * (spd or 0) / 256, e.y + vy * (spd or 0) / 256
end

-- CalculateEntityTileCollisions, bit for bit (IsTileCollision = isSolid)
function M.calcCollisions(E, e, direction)
  local room = E.field.room
  local layer = L(e)
  local function col(x, y) return room:isSolid(x, y, layer) and 1 or 0 end
  local hb = e.hitbox or { x = 0, y = 0, w = 6, h = 6 }
  local u0, u1 = hb.w or 6, math.max(1, (hb.h or 6) - 2)
  local u2, u3 = math.max(1, (hb.w or 6) - 2), hb.h or 6
  if e.hbProbe then u0, u1, u2, u3 = e.hbProbe[1], e.hbProbe[2], e.hbProbe[3], e.hbProbe[4] end
  local xm, ym = math.floor(e.x) + (hb.x or 0), math.floor(e.y) + (hb.y or 0)
  local c = 0
  local function three(x0, y0, x1, y1, x2, y2)
    c = bor(c, col(x0, y0)); c = lshift(c, 1)
    c = bor(c, col(x1, y1)); c = lshift(c, 1)
    c = bor(c, col(x2, y2))
  end
  if band(direction, 0xF) ~= 0 then
    if direction <= 0xF then
      three(xm + u0, ym, xm + u0, ym + u1, xm + u0, ym - u1); c = lshift(c, 6)
    else
      three(xm - u0, ym, xm - u0, ym + u1, xm - u0, ym - u1); c = lshift(c, 2)
    end
  else
    three(xm + u0, ym, xm + u0, ym + u1, xm + u0, ym - u1); c = lshift(c, 2)
    three(xm - u0, ym, xm - u0, ym + u1, xm - u0, ym - u1); c = lshift(c, 2)
  end
  local d2 = direction - 8
  if band(d2, 0xF) ~= 0 then
    if d2 >= 0 and d2 < 0x10 then
      three(xm, ym + u3, xm + u2, ym + u3, xm - u2, ym + u3); c = lshift(c, 5)
    else
      c = lshift(c, 4)
      three(xm, ym - u3, xm + u2, ym - u3, xm - u2, ym - u3); c = lshift(c, 1)
    end
  else
    three(xm, ym + u3, xm + u2, ym + u3, xm - u2, ym + u3); c = lshift(c, 2)
    three(xm, ym - u3, xm + u2, ym - u3, xm - u2, ym - u3); c = lshift(c, 1)
  end
  return band(c, 0xFFFF)
end

-- ProcessMovement0: collisions first, then the move; true when it moved
local function move0(E, e, dir, spd)
  dir = dir or e.dir
  if not dir or dir >= 0x20 then e.collisions = 0 return false end
  e.collisions = M.calcCollisions(E, e, dir)
  local hx, hy = DW().move0(E, e, dir, spd or e.speed or 0)
  return not (hx or hy)
end
M.move0 = move0

local function gravity(e, g) return DW().gravity(e, g) end -- z up, zv px/frame; true while airborne

local function onScreen(f, x, y)
  local cx, cy = f.camX or 0, f.camY or 0
  return x >= cx - 16 and x <= cx + 256 and y >= cy - 16 and y <= cy + 176
end

-- a draw-off without dropping collisions (spriteSettings.draw = 0)
local function show(e, on) if on then e.staticFrame = nil else e.staticFrame = 0xFF end end
local function shown(e) return e.staticFrame ~= 0xFF end
local function collide(e, on)
  if on then e.noTouch, e.noHit, e.collideOn = nil, nil, true else e.noTouch, e.noHit, e.collideOn = true, true, nil end
end

-- the room's special-tile bookkeeping (SetTile of a SPECIAL_TILE)
local function marks(f)
  f.room._fowMarks = f.room._fowMarks or {}
  return f.room._fowMarks
end
local function tileKey(tx, ty, layer) return (ty * 64 + tx) * 4 + (layer or 1) end
local function tileOf(x, y) return math.floor(x / 16), math.floor(y / 16) end
local function block(f, tx, ty, layer, on)
  local d = f._dungeon
  if d and d.block then d:block(tx, ty, layer, on) end
end

-- a target's damage from gCollisionMtx (hurtType = Link's)
local function touchLink(E, s)
  local f = E.field
  local p = f.player
  if not p or p.state == "dead" or (p.invuln or 0) > 0 or (s.z or 0) > 12 then return nil end
  local HBm = require("src.zelda.tmc.Hitboxes")
  local hb = s.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  local t = HBm.touches and HBm.data and HBm.data(f) and HBm.touches(f, p, s)
  if t == nil then
    t = math.abs((s.x + (hb.x or 0)) - p.x) < (hb.w or 4) + 5 and math.abs((s.y + (hb.y or 0)) - (p.y - 3)) < (hb.h or 4) + 6
  end
  if not t then return nil end
  if p.blocksFrom and p:blocksFrom(s.x, s.y) then snd(f, SFX.SHIELD) return "shield" end
  local ht = (HBm.data and HBm.data(f) and HBm.hurtType(p)) or 0
  local st = E.settings and E:settings(s.hitType or 0, ht) or nil
  st = st or { tgtDmg = 2, orgIfr = 30, orgKbDur = 8, orgKbSpd = 24 }
  if (st.tgtDmg or 0) > 0 or (st.orgKbDur or 0) > 0 then
    if p.hurt and p:hurt(math.max(st.tgtDmg or 0, 1), s.x, s.y) then
      p.invuln = math.max(st.orgIfr or 30, 30)
      p.timer = math.max(st.orgKbDur or 8, 4)
      local ks = ((st.orgKbSpd or 24) * 16) / 256
      local dx, dy = p.x - s.x, p.y - s.y
      local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.kbx, p.kby = dx / dd * ks, dy / dd * ks
    end
  end
  return "hit"
end
M.touchLink = touchLink

-- ===========================================================================
-- projectiles (EnemyCreateProjectile): entities with their own extUpdate
-- ===========================================================================
local function pdef(f, id, type)
  local d = f.assets and f.assets.manifest and f.assets.manifest.projectileDefs and f.assets.manifest.projectileDefs[id]
  if d and d.multi then d = d.forms[type or 0] or d.forms[0] end
  return d or {}
end
local function panim(E, s, idx)
  s.animIndex, s.objAnim = idx, idx
  if s.sprite and E.A and E.A.sprite then s.anim:set(E.A:sprite(s.sprite), idx, true) end
end
M.panim = panim

function M.projectile(E, parent, id, type)
  local f = E.field
  local d = pdef(f, id, type)
  local Anim = require("src.zelda.tmc.Anim")
  local s = { kind = 4, id = id, type = type or 0, x = parent.x, y = parent.y, z = 0, zv = 0, layer = parent.layer,
              sprite = d.sprite, anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0,
              speed = d.speed or 0x100, hitType = d.damageType or 0, hitbox = d.hitbox or { x = 0, y = 0, w = 4, h = 4 },
              action = 0, parent = parent, timer = 0, subtimer = 0, fowProj = true, E = E }
  if (d.gfx or 0) ~= 0 then
    s.gfx = require("src.zelda.tmc.Assets").gfxSource("enemy", d.gfx)
    s.palette = E.A and E.A.objPalette and E.A:objPalette(d.palette or 0, f.room.atlas and f.room.atlas.palettes)
  else
    s.gfx, s.palette = parent.gfx, parent.palette -- gfx 0: its parent's tiles and palette
  end
  s.def = { palette = (d.gfx or 0) ~= 0 and d.palette or (parent.def and parent.def.palette) }
  if d.draw == 0 then show(s, false) end
  s.extUpdate = function(_, me) M.projUpdate(me.E, me) end
  f.entities[#f.entities + 1] = s
  if f._dungeon and f._dungeon.track then f._dungeon:track(s) end
  return s
end

local function pdelete(s) s.deleted = true end
local function gone(e) return not e or e.deleted or e.dying end
local function offScreen(f, s) return not onScreen(f, s.x, s.y) end
-- ProcessMovement3: false when a wall stops it
local function pmove3(E, s, dir, spd)
  local vx, vy = dirVec(dir)
  local nx, ny = s.x + vx * spd / 256, s.y + vy * spd / 256
  if E.field.room:isSolid(nx, ny, L(s)) then return false end
  s.x, s.y = nx, ny
  return true
end

-- WIND / FIRE / ICE projectiles
local function orbUpdate(E, s)
  local f = E.field
  if s.action == 0 then
    if s.type == 0 then s.action = 1; panim(E, s, rshift(s.dir or 0, 3))
    else
      s.action = 2
      panim(E, s, bor(rshift(s.dir or 0, 3), 4))
      snd(f, (s.id == PROJ.WIND and SFX.S15F) or (s.id == PROJ.FIRE and SFX.S15E) or SFX.S160)
    end
    return
  end
  if s.action == 1 then
    local pa = s.parent
    if gone(pa) then return pdelete(s) end
    if shown(s) then
      s.x, s.y, s.z = pa.x, pa.y, pa.z or 0
      if s.id == PROJ.WIND then
        local dd = band((pa.dir or 0) + 4, 0x18)
        if s.timer ~= 0 then
          s.dir, s.animationState, s.timer = dd, rshift(dd, 2), 0
          panim(E, s, rshift(dd, 3))
        elseif rshift(dd, 2) ~= s.animationState then
          s.dir, s.animationState = dd, rshift(dd, 2)
          panim(E, s, rshift(dd, 3))
        end
      elseif s.timer ~= 0 then
        local dd = band(pa.dir or 0, 0x18)
        s.dir, s.timer = dd, 0
        panim(E, s, rshift(dd, 3))
      end
    end
    s.anim:update(1)
  elseif s.action == 2 then
    s.anim:update(1)
    if touchLink(E, s) then return pdelete(s) end
    if pmove3(E, s, s.dir or 0, s.speed) then
      if offScreen(f, s) then return pdelete(s) end
    else
      s.action, s.speed, s.noTouch = 3, 0, true
    end
  elseif s.action == 3 then
    s.anim:update(1)
    if done(s) then pdelete(s) end
  end
end

-- BONE_PROJECTILE
local function boneBack(s) -- sub_080A82D8
  s.action, s.noTouch = 4, true
  s.zv = 1.0
  s.dir = bxor(s.dir or 0, 0x10)
  s.speed = 0x80
end
local function boneUpdate(E, s)
  local f = E.field
  if s.action == 0 then
    s.action, s.timer, s.z = 1, 60, 2
    panim(E, s, 0)
    return
  end
  if not s.noTouch then
    local r = touchLink(E, s)
    if r == "hit" then return pdelete(s) elseif r then boneBack(s) end
  end
  if s.action == 1 then
    s.anim:update(1)
    if pmove3(E, s, s.dir or 0, s.speed) then
      if offScreen(f, s) then return pdelete(s) end
      s.timer = s.timer - 1
      if s.timer <= 0 then s.action, s.speed = 2, 0x120 end
    else boneBack(s) end
  elseif s.action == 2 then
    s.anim:update(1)
    pmove3(E, s, s.dir or 0, s.speed)
    if not gravity(s, 24 / 256) then
      s.action, s.noTouch, s.speed, s.zv = 3, true, 0xE0, 0.875
      s.bounces = 0
    end
  elseif s.action == 3 then
    if shown(s) then show(s, false) else show(s, true) end
    linear(s, s.dir, s.speed)
    s.anim:update(1)
    if not gravity(s, 24 / 256) then -- BounceUpdate: half the speed up again, done after the last bounce
      s.bounces = (s.bounces or 0) + 1
      if s.bounces >= 2 then return pdelete(s) end
      s.zv = 0.875 / 2
    end
  elseif s.action == 4 then
    s.anim:update(1)
    linear(s, s.dir, s.speed)
    if not gravity(s, 24 / 256) then return pdelete(s) end
  end
end

-- STALFOS_PROJECTILE
local function sprojBreak(E, s) -- sub_080A9BA8
  fx(E.field, s.x, s.y, s.type == 0 and FX.POT_SHATTER or FX.BONE)
  pdelete(s)
end
local function sprojFlip(s) s.action, s.noTouch, s.zv, s.flipY = 3, true, 2.625, nil end
M.sprojFlip = sprojFlip
local function spFrame(pa, bases)
  local st = pa.animationState or 0
  local base = st == 0 and bases[1] or ((st == 1 or st == 3) and bases[2] or bases[3])
  local t = (pa.anim and pa.anim.frame or base) - base
  return t, st
end
local function sprojUpdate(E, s)
  if s.action == 0 then
    if s.type2 == 1 then s.action, s.noTouch = 2, nil
    elseif s.type2 == 2 then s.action, s.zv = 3, 2.625
    else s.action = 1 end
    if s.type == 0 then panim(E, s, 5) else s.staticFrame = s.frameIndex or 0 end
    return
  end
  local pa = s.parent
  if s.action == 1 or s.action == 2 then
    if s.contact == 0x9D then s.contact = nil; return sprojFlip(s) end
    if gone(pa) then return sprojBreak(E, s) end
    if s.action == 1 then
      if pa.action == 11 then -- sub_080A9BD0: the pick-up frames
        local t, st = spFrame(pa, { 0x39, 0x3D, 0x41 })
        t = math.max(0, math.min(3, t))
        local en = M.SPROJ_PICK[t + st * 4] or M.SPROJ_PICK[0]
        s.x, s.y, s.z, s.spriteOY = pa.x + en[1], pa.y + en[2], (pa.z or 0) - en[3], 0
      else
        s.action = 2
        s.x, s.y, s.z, s.spriteOY = pa.x, pa.y + 1, pa.z or 0, -14
      end
    else
      if pa.action == 9 then s.x, s.y, s.z, s.spriteOY = pa.x, pa.y + 1, pa.z or 0, -14 -- sub_080A9C34
      else -- sub_080A9C50
        local t = spFrame(pa, { 0x27, 0x2D, 0x33 })
        t = math.max(0, math.min(7, t))
        s.x, s.y, s.z = pa.x, pa.y + 1, pa.z or 0
        s.spriteOY = M.SPROJ_BOB[t] or -14
      end
    end
    if s.type == 0 then s.anim:update(1) end
  elseif s.action == 3 then
    if s.zv < 0 then s.flipY = true end
    if not gravity(s, 32 / 256) then sprojBreak(E, s) end
  end
end

function M.projUpdate(E, s)
  if s.deleted then return end
  if s.id == PROJ.WIND or s.id == PROJ.FIRE or s.id == PROJ.ICE then return orbUpdate(E, s) end
  if s.id == PROJ.BONE then return boneUpdate(E, s) end
  if s.id == PROJ.STALFOS then return sprojUpdate(E, s) end
end

-- ===========================================================================
-- SPARK
-- ===========================================================================
function M.sparkCollision(E, e, flg)
  if band(flg, 0x80) ~= 0 and band(flg, 0x7F) == 0x14 then
    collide(e, false)
    e.iframes = 0
    show(e, false)
    e.action, e.timer = 2, 14
    fx(E.field, e.x, e.y, FX.DEATH)
  end
end

function M.spark(E, e)
  local f = E.field
  if e.action == 0 then
    e.action = 1
    e.dir = band(e.spawnB or 0, 0xFF)
    e.subtimer = 120
    e.onCollision = M.sparkCollision
    setAnim(E, e, 0)
  elseif e.action == 1 then
    e.anim:update(1)
    move0(E, e, e.dir, e.speed)
    local head = (e.form or 0) == 0
    local c = e.collisions or 0
    if c == 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 then
        e.subtimer = 120
        e.dir = band(e.dir + (head and 8 or 0x18), 0x18)
      end
    else
      e.subtimer = 120
      local d = band(e.dir, 0x18)
      if d == 0 then
        if band(c, COL.NORTH_ANY) ~= 0 then e.dir = head and 0x18 or 8
        else
          if band(c, COL.EAST_ANY) == COL.EAST_NORTH and head then e.dir = 8 end
          if band(c, COL.WEST_ANY) == COL.WEST_NORTH and not head then e.dir = 0x18 end
        end
      elseif d == 0x10 then
        if band(c, COL.SOUTH_ANY) ~= 0 then e.dir = head and 8 or 0x18
        else
          if band(c, COL.EAST_ANY) == COL.EAST_SOUTH and not head then e.dir = 8 end
          if band(c, COL.WEST_ANY) == COL.WEST_SOUTH and head then e.dir = 0x18 end
        end
      elseif d == 0x18 then
        if band(c, COL.WEST_ANY) ~= 0 then e.dir = head and 0x10 or 0
        else
          if band(c, COL.NORTH_ANY) == COL.NORTH_EAST and head then e.dir = 0 end
          if band(c, COL.SOUTH_ANY) == COL.SOUTH_EAST and not head then e.dir = 0x10 end
        end
      elseif d == 8 then
        if band(c, COL.EAST_ANY) ~= 0 then e.dir = head and 0 or 0x10
        else
          if band(c, COL.NORTH_ANY) == COL.NORTH_WEST and not head then e.dir = 0 end
          if band(c, COL.SOUTH_ANY) == COL.SOUTH_WEST and head then e.dir = 0x10 end
        end
      end
    end
  elseif e.action == 2 then
    e.timer = e.timer - 1
    if e.timer <= 0 then
      local O = f.objects and f:objects()
      if O and O.groundItem then O:groundItem(0x60, 0, e.x, e.y - 4, { drop = true }) end
      e.deleted = true
    end
  end
end

-- ===========================================================================
-- WIZZROBES
-- ===========================================================================
local function wizMark(E, e, on)
  local f = E.field
  local tx, ty = tileOf(e.x, e.y)
  if on then
    e.tilePos = { tx, ty }
    marks(f)[tileKey(tx, ty, L(e))] = 0x4071 -- SPECIAL_TILE_113
  elseif e.tilePos then
    marks(f)[tileKey(e.tilePos[1], e.tilePos[2], L(e))] = nil
  end
end
local function wizFace(E, e) -- sub_0802F888
  local f = E.field
  local p = f.player
  local t = (p and not p.minish and p.state ~= "dead") and p or nil -- sub_08049EB0 (target 3)
  local d = t and dirTo(e.x, e.y, t.x, t.y) or 0xFF
  e.dir = band(d + 4, 0x18)
  wizMark(E, e, true)
end
M.wizFace = wizFace
function M.wizRelocate(E, e) -- sub_0802F8E4
  if band(e.spawnB or 0, 0xFF) ~= 0 then return end
  local f = E.field
  local room = f.room
  local rw, rh = e.rangeW or 0, e.rangeH or 0
  if rw <= 0 or rh <= 0 then wizFace(E, e) return end
  local mk = marks(f)
  for _ = 1, 512 do
    local r = Rnd(f)
    local x = bor((e.homeX or 0) + (band(r, 0x7FF0) % rw), 8)
    local y = bor((e.homeY or 0) + (band(rshift(r, 16), 0x7FF0) % rh), 8)
    local tx, ty = tileOf(x, y)
    local c = room.coll and room.coll[L(e)] and room.coll[L(e)][ty * (room.tw or 64) + tx] or 0
    if c == 0 and mk[tileKey(tx, ty, L(e))] ~= 0x4071 then
      local ox, oy = e.x, e.y
      e.x, e.y = x, y
      if selfInHome(e) then break end
      e.x, e.y = ox, oy
    end
  end
  wizFace(E, e)
end
local function wizTick(E, e) -- sub_0802F9C8
  if (e.subtimer or 0) == 0 then
    if e.timer1 ~= 0 then
      e.timer1 = e.timer1 - 1
      show(e, band(e.timer1, 1) == 0)
      if band(e.spawnB or 0, 0xFF) ~= 0 then
        linear(e, e.dir, e.speed)
        if e.timer1 == 0 then collide(e, true) end
      end
    elseif band(e.spawnB or 0, 0xFF) ~= 0 then
      move0(E, e, e.dir, e.speed)
      if (e.collisions or 0) ~= 0 then collide(e, false); e.timer1 = 0x28 end
    end
    e.anim:update(1)
  end
end
function M.wizCollision(E, e, flg)
  if e.health <= 0 then wizMark(E, e, false) end
end
-- WIZZROBE_WIND type2 != 0: the waypoint list (room property e.timer):
-- u16 x, y pairs ending $FFFF (no room in the cartridge uses it)
local function wizTarget(E, e)
  local list = e.waypoints or {}
  local t = list[(e.targetIndex or 0) + 1]
  if not t then e.targetIndex = 0; t = list[1] end
  if t then e.targetX, e.targetY = t[1], t[2] else e.targetX, e.targetY = e.x, e.y end
end
local function wizGlide(E, e) -- sub_0802FA88
  local pa = e.child
  if within(e, e.targetX, e.targetY, 2) then
    e.targetIndex = (e.targetIndex or 0) + 1
    wizTarget(E, e)
    local d = dirTo(e.x, e.y, e.targetX, e.targetY)
    e.dir = d
    e.animationState = rshift(band(d + 4, 0x18), 2)
    if pa and shown(pa) then setAnim(E, e, bor(rshift(d, 3), 4)) else setAnim(E, e, rshift(d, 3)) end
    return true
  end
  local d = dirTo(e.x, e.y, e.targetX, e.targetY)
  e.dir = band(d, 0x1F) -- sub_08004596 (turn toward)
  local st = rshift(band(e.dir + 4, 0x18), 2)
  if st ~= e.animationState then e.animationState = st; setAnim(E, e, rshift(st, 1)) end
  return false
end

function M.wizzrobe(E, e)
  local f = E.field
  local W = M.WIZ[e.id]
  local a = e.action
  if a == 0 then
    e.onCollision = M.wizCollision
    if band(e.spawnB or 0, 0xFF) ~= 0 and e.id == ID.WIND then
      e.action, e.speed = 3, 0xC0
      collide(e, true)
      e.targetIndex, e.timer2, e.timer1 = 0, 0, 0
      wizTarget(E, e); wizGlide(E, e)
    else
      e.action, e.timer2, e.timer1, e.timer, e.subtimer = 1, 0xFF, 0x28, 40, 96
      collide(e, (e.def and e.def.collision or 0) ~= 0)
      if e.def and e.def.draw == 0 then show(e, false) end
      wizFace(E, e)
    end
    local s = M.projectile(E, e, W.proj, 0)
    if s then s.dir = e.dir; e.child = s; show(s, false) end
    setAnim(E, e, rshift(e.dir or 0, 3))
  elseif a == 1 then
    if e.timer2 == 0xFF then
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 then e.subtimer, e.timer2 = 0, 0 end
    elseif e.timer2 == 0 then
      e.timer = e.timer - 1
      if e.timer <= 0 then e.timer2, e.timer = 1, W.on; collide(e, true) end
    elseif e.timer2 == 1 then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.action, e.timer2, e.timer = 2, 0, W.cast
        if e.child and not e.child.deleted then e.child.timer = 1; show(e.child, true) end
        setAnim(E, e, bor(rshift(e.dir or 0, 3), 4))
      end
    end
    wizTick(E, e)
  elseif a == 2 then
    if e.timer2 == 0 then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.timer2, e.timer, e.subtimer = 1, 56, 0
        if e.child then show(e.child, false) end
      elseif e.timer == W.shot then
        local p = f.player
        if p and math.abs(p.x - e.x) <= 0xA0 and math.abs(p.y - e.y) <= 0xA0 and onScreen(f, e.x, e.y) then
          local s = M.projectile(E, e, W.proj, 1)
          if s then s.dir = band(e.dir or 0, 0x18) end
        end
      end
    elseif e.timer2 == 1 then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.timer2, e.timer1, e.timer, e.subtimer = 2, 0x28, 40, 0
        collide(e, false)
        wizMark(E, e, false)
        snd(f, SFX.S156)
        setAnim(E, e, rshift(e.dir or 0, 3))
      end
    elseif e.timer2 == 2 then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.timer2 = 3
        e.timer = band(Rnd(f), 0x3F) + W.hide
        show(e, false)
      end
    elseif e.timer2 == 3 then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.action, e.timer2, e.timer1, e.timer = 1, 0, 0x28, 40
        snd(f, SFX.S156)
        M.wizRelocate(E, e)
        setAnim(E, e, rshift(e.dir or 0, 3))
      end
    end
    wizTick(E, e)
  elseif a == 3 then
    wizGlide(E, e)
    wizTick(E, e)
    local pa = e.child
    if e.timer1 == 0 then
      if e.timer2 == 0 then e.timer2, e.timer = 1, 64
      elseif e.timer2 == 1 then
        e.timer = e.timer - 1
        if e.timer <= 0 then
          e.timer2, e.timer = 2, 40
          if pa then pa.timer = 1; show(pa, true) end
          setAnim(E, e, bor(rshift(e.animationState or 0, 1), 4))
        end
      elseif e.timer2 == 2 then
        e.timer = e.timer - 1
        if e.timer <= 0 then
          e.timer2 = 3
          e.timer = band(Rnd(f), 0x1F) + 48
          if pa then show(pa, false) end
          setAnim(E, e, rshift(e.animationState or 0, 1))
        elseif e.timer == 8 then
          local s = M.projectile(E, e, PROJ.WIND, 1)
          if s then s.dir = band(e.dir or 0, 0x18) end
        end
      end
    elseif e.timer2 ~= 0 then
      e.timer2 = 0
      if pa then show(pa, false) end
    end
  end
end

-- ===========================================================================
-- EYEGORE
-- ===========================================================================
local function eyeTiles(E, e, on)
  local f = E.field
  local tx, ty = tileOf(e.x - 8, e.y - 20)
  if on then
    if e.eyeBlocked then return end
    e.eyeBlocked = { tx, ty }
    for _, o in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do block(f, tx + o[1], ty + o[2], L(e), true) end
  else
    local b = e.eyeBlocked
    if not b then return end
    e.eyeBlocked = nil
    for _, o in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do block(f, b[1] + o[1], b[2] + o[2], L(e), false) end
  end
end
local function eyeWake(E, e) -- sub_08031320
  e.action, e.timer = 2, 30
  collide(e, false)
  e.hitbox = HB_EYE_AWAKE
  setAnim(E, e, 10)
end
local function eyeStep(e) e.action, e.u7a, e.u79, e.u78 = 4, 0, 0, 0 end -- sub_08030E58
local function eyeHop(E, e) -- sub_08030E3C
  eat(e)
  e.zv = 1 + 3 / 32
  e.eyeAir = true
  snd(E.field, SFX.S157)
end
local function eyeLand(E, e) -- sub_08030E70 / sub_08030E80
  local f = E.field
  local t = (e.animationState or 0) * 4
  fx(f, e.x + M.EYE_PUFF[t], e.y + M.EYE_PUFF[t + 1], FX.DEATH)
  fx(f, e.x + M.EYE_PUFF[t + 2], e.y + M.EYE_PUFF[t + 3], FX.DEATH)
  snd(f, SFX.S158)
end
local function solidAt(E, e, x, y) return E.field.room:isSolid(x, y, L(e)) end
function M.eyeDecide(E, e) -- sub_08031024
  local f = E.field
  local home = linkInHome(f, e)
  local t = target(f)
  local hb = e.hitbox or { x = 0, y = 0 }
  if e.u79 == 0 then
    if home then e.dir = dirTo(e.x + (hb.x or 0), e.y + (hb.y or 0), t.x, t.y)
    else
      e.u79, e.u78 = 1, 0
      e.dir = dirTo(e.x, e.y, e.u74, e.u76)
    end
  elseif home then e.u79 = 0
  elseif e.u78 ~= 0 then
    if e.u78 == 1 then
      e.u78 = bor(e.u78, 0x80)
      e.dir = dirTo(e.x, e.y, e.u74, e.u76)
      e.u7b = band(e.dir + 4, 0x18)
      if e.u7b < e.dir then e.dir = band(e.u7b + 8, 0x18) else e.dir = band(e.u7b - 8, 0x18) end
    elseif band(e.u78, 2) ~= 0 then
      e.dir = bxor(e.dir, 0x10)
    end
    local tmp = band(e.u78, 0x70)
    if tmp ~= 0 then
      e.u78 = bor(rshift(tmp, 1), band(e.u78, 0x8F))
      if band(e.u78, 0x10) ~= 0 then e.dir, e.u78 = e.u7b, 0 end
    else
      local t2 = rshift(e.u7b or 0, 1)
      local P = M.EYE_PROBE
      local s1 = solidAt(E, e, e.x + (P[t2] or 0), e.y + (P[t2 + 1] or 0))
      local s2 = solidAt(E, e, e.x + (P[t2 + 2] or 0), e.y + (P[t2 + 3] or 0))
      if s1 or s2 then
        if rshift(e.dir, 3) == e.animationState then e.u78 = bor(e.u78, 0x20) else e.u78 = bor(e.u78, 0x40) end
      else
        e.dir, e.u78 = e.u7b, 0
      end
    end
  else
    e.dir = dirTo(e.x, e.y, e.u74, e.u76)
  end
  if rshift(band(e.dir + 4, 0x18), 3) == e.animationState then
    e.u7a, e.u7f = 1, e.animationState
  else
    e.u7a = 0
    if band(e.dir - e.animationState * 8, 0x1F) >= 0x11 then e.u7f = band(e.animationState - 1, 3)
    else e.u7f = band(e.animationState + 1, 3) end
  end
  e.dir = band(e.dir + 4, 0x18)
  e.x, e.y = math.floor(e.x), math.floor(e.y)
end
local function eyeMove(E, e) -- sub_08031250
  if e.u79 ~= 0 then
    local t2 = 0
    if math.floor(e.x) - e.u74 + 2 >= 0 and math.floor(e.x) - e.u74 + 2 < 5 then e.x, t2 = e.u74, 0x80 end
    if math.floor(e.y) - e.u76 + 2 >= 0 and math.floor(e.y) - e.u76 + 2 < 5 then e.y = e.u76; e.u79 = bor(t2, e.u79) end
    if band(e.u79, 0x80) == 0 and not move0(E, e, e.dir, e.speed) then
      if band(e.u78, 0x80) ~= 0 then e.u78 = 0x82 else e.u78 = 1 end
    end
  else
    move0(E, e, e.dir, e.speed)
  end
end
-- OnCollision: e.contact = { direction, x, y, z } of the arrow ($15) / $0E
function M.eyeCollision(E, e, flg)
  local f = E.field
  if flg == 0x95 or flg == 0x8E then
    local c = e.contact
    if not c then
      local p = f.player
      c = { direction = (p.animationState or 0) * 4, x = p.x, y = p.y, z = 0 }
    end
    e.contact = nil
    local tmp = rshift(bxor(band(c.direction + 4, 0x18), 0x10), 3)
    if tmp == e.animationState then
      if band(tmp, 1) ~= 0 then
        local v = (math.floor(c.y) - math.floor(c.z or 0)) - (math.floor(e.y) - math.floor(e.z or 0)) + 0x14
        if not (v > 0x10 or v < 0) then
          if flg == 0x8E then e.health = 0 else e.health = e.health - 1 end
          e.iframes = 0x10
          snd(f, SFX.HIT)
        end
      elseif math.floor(c.x) - math.floor(e.x) + 8 >= 0 and math.floor(c.x) - math.floor(e.x) + 8 <= 0x10 then
        if e.action == 1 then
          eyeWake(E, e)
          snd(f, SFX.BUTTON_PRESS)
        else
          if flg == 0x8E then e.health = 0 else e.health = e.health - 1 end
          e.iframes = 0x0F
          snd(f, SFX.HIT)
        end
      end
    end
  end
  if e.health <= 0 and not e.deathT then
    collide(e, false)
    e.iframes = 0x78
    e.deathT = 0x3C
  end
end

function M.eyegore(E, e)
  local f = E.field
  if e.deathT then -- Eyegore_OnDeath
    if e.deathT > 0 then e.deathT = e.deathT - 1; gravity(e, 28 / 256)
    else
      fx(f, e.x, e.y, FX.GIANT_EXPLOSION4)
      eyeTiles(E, e, false)
      e.health = 0
      if E.kill then E:kill(e) else e.dying = 18 end
    end
    return
  end
  local a = e.action
  if a == 0 then
    e.onCollision = M.eyeCollision
    e.action, e.animationState = 1, 2
    e.x = band(math.floor(e.x), 0xFFF0)
    e.y = band(math.floor(e.y), 0xFFF0) + 0xC
    e.u74, e.u76, e.u7e = e.x, e.y, 0x3C
    e.u78, e.u79, e.u7a, e.u7b, e.u7f = 0, 0, 0, 0, 0
    e.flag = band(e.spawnB or 0, 0xFFFF)
    eyeTiles(E, e, true)
    if e.flag ~= 0 then collide(e, false); setAnim(E, e, 10)
    else setAnim(E, e, 0xE) end
  elseif a == 1 then
    if e.flag ~= 0 and f._dungeon and f._dungeon:check(e.flag) then eyeWake(E, e) end
  elseif a == 2 then
    if e.timer > 0 then e.timer = e.timer - 1
    elseif linkInHome(f, e) then
      local t = target(f)
      e.action, e.timer = 3, 60
      e.dir = band(dirTo(e.x + e.hitbox.x, e.y + e.hitbox.y, t.x, t.y) + 4, 0x18)
      setAnim(E, e, 10)
    end
  elseif a == 3 then
    if e.timer > 0 then
      e.timer = e.timer - 1
      e.spriteOX = M.EYE_SHAKE[band(e.timer, 3)]
    else
      e.spriteOX = 0
      e.anim:update(1)
      if done(e) then
        collide(e, true)
        e.animationState = 2
        eyeStep(e)
        setAnim(E, e, 2)
        eyeTiles(E, e, false)
      end
    end
  elseif a == 4 or a == 5 then
    e.anim:update(1)
    local k = band(fl(e), 7)
    if k == 1 then
      if a == 4 then M.eyeDecide(E, e)
      elseif e.animationState ~= 2 then
        if e.animationState >= 3 then e.u7f = band(e.animationState - 1, 3) else e.u7f = band(e.animationState + 1, 3) end
      end
      eyeHop(E, e)
    elseif k == 2 then
      if done(e) then e.animationState = e.u7f; setAnim(E, e, e.animationState + 4) end
      if a == 4 and e.u7a ~= 0 then eyeMove(E, e) end
      if not gravity(e, 28 / 256) then
        if e.eyeAir then e.eyeAir = nil; eyeLand(E, e) end
      end
    elseif done(e) then
      setAnim(E, e, e.animationState)
      if a == 4 then
        if band(e.u79, 0x80) ~= 0 then e.action, e.u7a = 5, 0 end
      elseif linkInHome(f, e) then eyeStep(e)
      elseif e.animationState == 2 then
        e.action = 6
        collide(e, false)
        setAnim(E, e, 0xE)
        eyeTiles(E, e, true)
      end
    end
  elseif a == 6 then
    e.anim:update(1)
    if done(e) then e.action = 2 end
  end
end

-- ===========================================================================
-- ARMOS
-- ===========================================================================
local function armosData(f)
  f._fowArmos = f._fowArmos or { mask = 0, data = {}, enter = 0xFF }
  return f._fowArmos
end
M.armosData = armosData
local function aFrame(e) if (e.u84 or 0) ~= 0 and e.anim and e.anim.frame == 0x25 then e.anim.frame = 0x19 end end
local function aAnim(E, e, i) setAnim(E, e, i); aFrame(e) end -- sub_080309C8
local function aNext(e) e.anim:update(1); aFrame(e) end        -- sub_080309A8
local function aSpeed(e) -- sub_080309E8
  if e.health < 5 then e.speed = 0x120 elseif e.health <= 8 then e.speed = 0xE0 end
end
local function aBlock(E, e) -- sub_080307EC
  if e.aTile then return end
  local tx, ty = tileOf(e.x, e.y)
  e.aTile = { tx, ty }
  block(E.field, tx, ty, L(e), true)
end
local function aFree(E, e) -- sub_08030834
  if not e.aTile then return end
  block(E.field, e.aTile[1], e.aTile[2], L(e), false)
  e.aTile = nil
end
local function aSetDir(E, e) -- sub_080307D4
  local s = rshift(e.dir or 0, 3)
  if s ~= e.animationState then e.animationState = s; aAnim(E, e, s) end
end
local function aStatue(E, e) e.action = 1; aAnim(E, e, 4) end -- sub_08030580
function M.armosChase(E, e) -- sub_080306C4
  local f = E.field
  local t = target(f)
  if linkInHome(f, e) and (e.u7a or 0) ~= 0 then
    e.timer = 24
    local u3 = 0xFF -- sub_0800132C
    if band(t.layer or 1, e.layer or 1) ~= 0 then
      local dx, dy = math.floor(e.x) - math.floor(t.x) + 8, math.floor(e.y) - math.floor(t.y) + 8
      if not (dx >= 0 and dx < 0x11 and dy >= 0 and dy < 0x11) then u3 = dirTo(e.x, e.y, t.x, t.y) end
    end
    if u3 ~= 0xFF then
      local var = 0
      if (band(Rnd(f), 7) ~= 0 or e.animationState == 0xFF) and band(e.u82 or 0, 3) ~= 3 then
        e.dir = band(u3 + 4, 0x18); var = 1
      end
      if var == 0 then e.dir = band(4 + u3 + (band(Rnd(f), 2) - 1) * 8, 0x18) end
      local i = rshift(e.dir, 2)
      if solidAt(E, e, e.x + M.ARMOS_PROBE[i], e.y + M.ARMOS_PROBE[i + 1]) then
        e.dir = bor(lshift(bxor(band(u3, 4), 4), 1), band(u3, 0x10))
        var = 0
      end
      aSetDir(E, e)
      e.u82 = band(bor(lshift(e.u82 or 0, 1), var), 0xFF)
    end
  else
    e.action, e.timer, e.speed = 4, 120, 0xA0
  end
end
local function aCentre(E, e) -- sub_080305BC
  local x, y = math.floor(e.x), math.floor(e.y)
  local b = (band(x, 0xF) == 8 and 1 or 0) + (band(y, 0xF) == 8 and 2 or 0)
  if b == 3 then e.x, e.y = x, y return true end
  if e.dir == 8 or e.dir == 0x18 then
    if band(b, 1) == 0 then
      if not move0(E, e, e.dir, math.min(e.speed or 0xA0, 0x100)) then e.dir = bxor(e.dir, 0x10) end
      return false
    end
    e.x = x
    if band(y, 0xF) >= 9 then e.dir = 0x10 else e.dir = 0 end
  end
  if band(b, 2) == 0 then
    if not move0(E, e, e.dir, math.min(e.speed or 0xA0, 0x100)) then e.dir = bxor(e.dir, 0x10) end
  else
    e.y = y
    if band(x, 0xF) >= 9 then e.dir = 0x18 else e.dir = 8 end
  end
  return false
end
local function pin(f, cx, cy, rx, ry) -- CheckPlayerInRegion
  local p = f.player
  local vx = cx - (math.floor(p.x) - rx)
  local vy = cy - (math.floor(p.y) - ry)
  return vx >= 0 and vx < 2 * rx and vy >= 0 and vy < 2 * ry
end
function M.armosTransition(f, k)
  local props = f.room and f.room.maps and f.room.maps.header and f.room.maps.header.props
  local addr = props and props[k]
  if not addr then return nil end
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "fowArmosTransitions")
  local r = M.ROM_RANGES.fowArmosTransitions
  if not T or addr < r[1] or addr + 20 > r[2] then return nil end
  return { warpType = T.u16(addr), endX = T.u16(addr + 6), endY = T.u16(addr + 8), shape = T.u8(addr + 10),
           area = T.u8(addr + 11), room = T.u8(addr + 12), layer = T.u8(addr + 13), kind = T.u8(addr + 14),
           facing = T.u8(addr + 15), sfx = T.u16(addr + 16) }
end
local function aMinish(E, e) -- sub_0803086C
  local f = E.field
  if not e.aTrans then return false end
  local p = f.player
  if p.minish then
    local cx, cy = math.floor(e.x), math.floor(e.y)
    if e.aOpen then
      if pin(f, cx, cy, 2, 0xC) then
        if pin(f, cx, cy - 4, 2, 4) and e.aTrans ~= true then
          local ad = armosData(f)
          ad.enter = e.slot
          if f.startTransition then f:startTransition(e.aTrans) end
          return true
        end
      else
        e.aOpen = nil; aBlock(E, e)
      end
    elseif pin(f, cx, cy + 6, 2, 5) then
      e.aOpen = true; aFree(E, e) -- SPECIAL_TILE_73: Minish Link walks in
    end
  end
  return false
end
local function aWakes(E, e) -- sub_08030650
  local f = E.field
  if (e.form or 0) == 0 then
    if e.aContact then e.aContact = nil return true end
    return false
  elseif e.slot ~= 2 then
    if not linkInHome(f, e) then return false end
    local dx = math.floor(target(f).x) - math.floor(e.x) + 0x10
    return dx >= 0 and dx <= 0x20
  else
    if not linkInHome(f, e) then return false end
    return target(f).x < 0xA8
  end
end
function M.armosCollision(E, e, flg)
  if flg == 0x80 and e.action == 1 then e.aContact = true end -- CONTACT_NOW from Link's body
  if e.health ~= 0 and e.health ~= e.u81 then
    e.action = 8
    aAnim(E, e, 6)
    aSpeed(e)
  end
  e.u81 = e.health
end

function M.armos(E, e)
  local f = E.field
  local a = e.action
  if a ~= 0 then -- sub_08030150: kept across rooms
    local ad = armosData(f)
    ad.mask = bor(band(ad.mask, bit.bnot(lshift(1, e.slot))), lshift(e.u84, e.slot))
    ad.data[e.slot] = { math.floor(e.x), math.floor(e.y) }
  end
  if a == 0 then
    e.onCollision = M.armosCollision
    e.slot = band(rshift(e.spawnB or 0, 8), 0xFF)
    local ad = armosData(f)
    local sv = ad.data[e.slot]
    if sv and sv[1] ~= 0 then
      e.x, e.y = sv[1], sv[2]
      e.u84 = band(rshift(ad.mask, e.slot), 1)
    else
      e.u84 = band(rshift(0x47D, e.slot), 1)
    end
    local t2 = band(e.spawnB or 0, 0xFF)
    if t2 ~= 0 then e.aTrans = M.armosTransition(f, t2) or true end
    e.u81 = e.health
    e.hbProbe = { 6, 4, 4, 6 }
    aStatue(E, e)
    aBlock(E, e)
    if e.slot == 2 and e.y > 0x80 then e.action = 7; aAnim(E, e, 7) end
  elseif a == 1 then
    -- contact with Link's body (CONTACT_NOW): the statue only pushes him, so test it here
    local HBm = require("src.zelda.tmc.Hitboxes")
    local p = f.player
    if p and not p.minish and HBm.touches and HBm.data and HBm.data(f) then
      local hb = e.hitbox
      local big = { x = hb.x, y = hb.y, w = hb.w + 1, h = hb.h + 1 }
      local saved = e.hitbox; e.hitbox = big
      if HBm.touches(f, p, e) then e.aContact = true end
      e.hitbox = saved
    elseif p and not p.minish and math.abs(p.x - e.x) < 16 and math.abs(p.y - e.y) < 17 then e.aContact = true end
    if not aMinish(E, e) and e.u84 ~= 0 and aWakes(E, e) then e.action, e.sub = 2, 0 end
  elseif a == 2 then -- sub_08030338
    if e.slot ~= 2 then aNext(e) else e.anim:update(3); aFrame(e) end
    local k = fl(e)
    if k == 1 then
      if e.sub == 0 then e.sub = 1 end
      e.timer = band((e.timer or 0) + 1, 0xFF)
      if band(e.timer, 1) ~= 0 then e.spriteOX = M.ARMOS_SHAKE[rshift(band(e.timer, 6), 1)] end
    elseif k == 2 then
      eat(e)
      if e.slot ~= 2 then e.hitType, e.hitbox = 8, HB_ARMOS end
      aFree(E, e)
      snd(f, SFX.S12A)
    elseif done(e) then
      e.spriteOX = 0
      if e.slot ~= 2 then
        e.action, e.animationState, e.u7a, e.u82 = 3, 0xFF, 600, 0
        M.armosChase(E, e)
        aSpeed(e)
      else
        e.action, e.timer, e.speed, e.dir = 6, 26, 0x300, 0x10
      end
    else e.spriteOX = 0 end
  elseif a == 3 then -- sub_08030430
    move0(E, e, e.dir, e.speed)
    if band(fl(e), 1) ~= 0 then eat(e, 1); snd(f, SFX.S101) end
    if (e.speed or 0) > 0x100 then e.anim:update(1) end
    aNext(e)
    if (e.u7a or 0) ~= 0 then e.u7a = e.u7a - 1 end
    e.timer = e.timer - 1
    if e.timer <= 0 then M.armosChase(E, e) end
  elseif a == 4 then -- sub_08030474
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.action, e.timer, e.u7a = 3, 1, 0x3C
      aSpeed(e)
    elseif aCentre(E, e) then
      e.action, e.hitType, e.hitbox = 5, 1, HB_ARMOS_STATUE -- sub_08030590
      aAnim(E, e, 5)
      aBlock(E, e)
    else
      aSetDir(E, e); aNext(e)
    end
  elseif a == 5 then -- sub_080304BC
    aNext(e)
    if done(e) then aStatue(E, e)
    elseif fl(e) == 1 then eat(e); snd(f, SFX.S12A) end
  elseif a == 6 then -- sub_080304F4
    linear(e, e.dir, e.speed)
    aNext(e)
    e.timer = e.timer - 1
    if e.timer <= 0 then e.action = 7; aAnim(E, e, 5); aBlock(E, e) end
  elseif a == 7 then -- sub_08030524
    if not done(e) then aNext(e)
    elseif fl(e) == 1 then eat(e); snd(f, SFX.S12A) end
  elseif a == 8 then -- sub_08030554
    aNext(e)
    if done(e) then
      e.action = 3
      aAnim(E, e, e.animationState ~= 0xFF and e.animationState or 0)
      M.armosChase(E, e)
    end
  end
end

-- ===========================================================================
-- STALFOS
-- ===========================================================================
local function sJump(E, e) -- sub_0803981C
  e.zv = 2.0
  if (e.iframes or 0) == 0 then e.iframes = 12 end -- (s8)-$C: invulnerable, no blink
  e.hitType, e.u7d = 0x45, 0x45
  setAnim(E, e, (e.animationState or 0) + 8)
  snd(E.field, SFX.S12B)
end
local function sRest(E, e) -- sub_0803998C
  e.action, e.hitType, e.u7d = 1, 0x44, 0x44
  e.u78 = M.STALFOS_REST[band(Rnd(E.field), 0xF)]
  setAnim(E, e, e.animationState or 0)
end
local function sCool(E, e, add) e.u7a = M.STALFOS_COOL[band(Rnd(E.field), 3)] + add end -- sub_08039A00
local function sHeadless(E, e) -- sub_08039A48
  e.action, e.hitType, e.u7d, e.u78 = 9, 0x47, 0x47, 10
  setAnim(E, e, (e.animationState or 0) + 0x10)
end
M.stalfosHeadless = sHeadless
local function sSees(E, e) -- sub_08039758
  local f = E.field
  if (e.u7a or 0) ~= 0 then e.u7a = e.u7a - 1 end
  if linkInHome(f, e) and e.u7a == 0 then
    local t = target(f)
    if (e.form or 0) == 0 then
      if within(e, t.x, t.y, 0x24) then
        e.action, e.speed = 5, 0x180
        e.dir = dirTo(e.x, e.y, t.x, t.y)
        e.animationState = rshift(band(e.dir + 4, 0x18), 3)
        sJump(E, e)
        e.hitType, e.u7d = 0x46, 0x46
        e.zv = 2.5
        return true
      end
    elseif within(e, t.x, t.y, 0x48) then
      e.action, e.timer = 8, 60
      e.dir = dirTo(e.x, e.y, t.x, t.y)
      setAnim(E, e, (e.animationState or 0) + 0xC)
      return true
    end
  end
  return false
end
local function sPick(E, e) -- sub_080398C0
  local f = E.field
  local r = Rnd(f)
  if (e.form or 0) == 0 and linkInHome(f, e) then
    local t = target(f)
    if within(e, t.x, t.y, 0x58) then return dirTo(e.x, e.y, f.player.x, f.player.y) end
  end
  if not selfInHome(e) and band(r, 7) ~= 0 then return homeDir(e) end
  return band(rshift(r, 16), 0x18)
end
local function sTurn(E, e) -- sub_08039858
  local i = sPick(E, e)
  local u2 = (e.animationState or 0) * 8
  if band(i + 4, 0x18) == u2 then
    if (e.u7b or 0) ~= 3 then return end
    e.u7b = 0
    i = i + (band(Rnd(E.field), 2) - 1) * 8
  end
  local v = bxor(rshift(band(i - u2, 0x1F), 4), 1)
  setAnim(E, e, M.STALFOS_TURN[(e.animationState or 0) * 2 + v])
  e.animationState = band(v * 2 + (e.animationState or 0) - 1, 3)
end
local function sWalk(E, e) -- sub_0803992C
  e.action, e.speed = 3, 0xE0
  e.dir = (e.animationState or 0) * 8
  e.u78 = M.STALFOS_WALK[band(Rnd(E.field), 0xF)]
  e.collisions = M.calcCollisions(E, e, e.dir)
  if band(M.STALFOS_WALL[e.animationState or 0], e.collisions) ~= 0 then setAnim(E, e, e.animationState)
  else setAnim(E, e, e.animationState + 4) end
end
local function sWander(E, e) -- sub_08039A70
  local f = E.field
  e.action, e.speed = 10, 0xE0
  local r = Rnd(f)
  e.u78 = M.STALFOS_HEADLESS[band(r, 3)]
  r = rshift(r, 16)
  if not selfInHome(e) and band(r, 7) ~= 0 then e.dir = band(homeDir(e) + 4, 0x18)
  else e.dir = band(r, 0x18) end
  e.animationState = rshift(e.dir, 3)
  setAnim(E, e, e.animationState + 0x14)
end
-- sub_08039B28: a pot / skull in the tile in front
function M.stalfosFront(E, e)
  local f = E.field
  if e.child and not e.child.deleted then return nil end
  local st = e.animationState or 0
  local x, y = e.x + M.STALFOS_FRONT[st * 2], e.y + M.STALFOS_FRONT[st * 2 + 1]
  local tx, ty = tileOf(x, y)
  for _, o in ipairs(f.entities) do
    if not o.deleted and o ~= e then
      local ox, oy = tileOf(o.x, o.y)
      if ox == tx and oy == ty then
        if o.enemy and o.id == ID.SKULL and o.action == 1 then return o, 1 end -- SPECIAL_TILE_96 ($4060)
        if o.kind == 6 and o.id == 0x05 and o.liftable and (o.z or 0) == 0 then return o, 0 end -- a POT ($4000)
      end
    end
  end
  return nil
end
local function sTake(E, e) -- sub_08039AD4
  local o, t2 = M.stalfosFront(E, e)
  if o then
    e.type2 = t2
    local s = M.projectile(E, e, PROJ.STALFOS, t2)
    if s then
      s.type2 = 0
      e.action, e.child = 11, s
      setAnim(E, e, (e.animationState or 0) + 0x18)
      -- SetTile(SPECIAL_TILE_103): the pot / skull there is taken
      if o.enemy then M.skullFree(E, o); o.deleted = true else o.deleted = true; if o.blockTile then block(E.field, o.blockTile[1], o.blockTile[2], L(o), false) end end
      return
    end
  end
  sHeadless(E, e)
end

function M.stalfosCollision(E, e, flg)
  local f = E.field
  local k = band(flg, 0x7F)
  if e.hitType == 0x44 and k >= 4 and k <= 6 then
    local st = E.settings and E:settings(0x44, k)
    if not st or (st.tgtIfr or 0) < 1 then
      local p = f.player
      e.action = 4
      e.dir = dirTo(p.x, p.y, e.x, e.y) -- knockbackDirection
      e.animationState = rshift(bxor(band(e.dir + 4, 0x18), 0x10), 3)
      e.speed = 0x120
      sJump(E, e)
    end
  end
  if flg == 0x9D and not e.noPacci then
    local c = e.child
    if not c or c.deleted then
      if e.action < 9 then
        local s = M.projectile(E, e, PROJ.STALFOS, 1)
        if s then s.frameIndex = (e.animationState or 0) * 2; s.type2 = 2; snd(f, SFX.S186) end
        sHeadless(E, e)
        e.u78 = e.u78 + 0x5A
      end
    else
      c.contact = 0x9D
      snd(f, SFX.S186)
      e.child = nil
      sHeadless(E, e)
      e.u78 = e.u78 + 0x5A
    end
    e.noPacci = true
  end
end

function M.stalfos(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then
    e.onCollision = M.stalfosCollision
    e.animationState = band(Rnd(f), 3)
    e.u7b, e.u7c, e.u7d = 0, 0, e.hitType
    e.type2 = band(e.spawnB or 0, 0xFF)
    sCool(E, e, 0)
    if e.type2 == 0 then sRest(E, e)
    else
      e.action, e.dir = 4, 0xFF
      local p = f.player
      e.animationState = rshift(band(dirTo(e.x, e.y, p.x, p.y) + 4, 0x18), 3)
      sJump(E, e)
    end
  elseif a == 1 then
    if not gravity(e, 24 / 256) and not sSees(E, e) then
      e.u78 = e.u78 - 1
      if e.u78 <= 0 then e.action, e.timer = 2, 10; sTurn(E, e) end
    end
  elseif a == 2 then
    if not sSees(E, e) then
      e.timer = e.timer - 1
      if e.timer <= 0 then sWalk(E, e) end
    end
  elseif a == 3 then
    if not sSees(E, e) then
      if move0(E, e, e.dir, e.speed) then
        e.anim:update(1)
        e.u78 = e.u78 - 1
        if e.u78 <= 0 then sRest(E, e) end
      else
        e.u7b = band(bor(lshift(e.u7b or 0, 1), 1), 0xFF)
        sRest(E, e)
      end
    end
  elseif a == 4 then
    if e.dir and e.dir < 0x20 then move0(E, e, e.dir, e.speed) end
    if not gravity(e, 24 / 256) then
      sRest(E, e)
      e.u7c = 0x5A
      snd(f, SFX.PLY_LAND)
    end
  elseif a == 5 then
    move0(E, e, e.dir, e.speed)
    gravity(e, 24 / 256)
    if (e.zv or 0) < 0 then e.action, e.timer = 6, 15 end
  elseif a == 6 then
    if e.timer > 0 then e.timer = e.timer - 1; e.zv = 0
    else
      e.z = (e.z or 0) - 4 -- the slam: z.HALF.HI += 4
      e.zv = 0
      if e.z <= 0 then
        e.action, e.timer, e.z = 7, 10, 0
        e.u7a, e.u7c = 0x78, 0x3C
        fx(f, e.x - 4, e.y + 2, FX.DASH); fx(f, e.x + 4, e.y + 2, FX.DASH) -- sub_080399C4
        snd(f, SFX.S14B)
      end
    end
  elseif a == 7 then
    e.timer = e.timer - 1
    if e.timer <= 0 then sRest(E, e) end
  elseif a == 8 then
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then sCool(E, e, 0x3C); sRest(E, e)
    elseif band(e.timer, 0x1F) == 0 then -- sub_08039A20
      local s = M.projectile(E, e, PROJ.BONE, 0)
      if s then s.dir = e.dir; e.u7c = 0x3C; snd(f, SFX.FB) end
    end
  elseif a == 9 then
    if not gravity(e, 24 / 256) then
      e.u78 = e.u78 - 1
      if e.u78 <= 0 then sWander(E, e) end
    end
  elseif a == 10 then -- Stalfos_Action11
    move0(E, e, e.dir, e.speed)
    e.anim:update(1)
    e.u78 = e.u78 - 1
    if e.u78 <= 0 then sTake(E, e) end
  elseif a == 11 then -- Stalfos_Action12
    e.anim:update(1)
    if done(e) then
      if e.type2 == 1 then
        sRest(E, e)
        if e.child then e.child.deleted = true end
        e.child = nil
      else
        sHeadless(E, e)
      end
      e.noPacci = nil
      e.u78 = (e.u78 or 0) + 0x3C
    end
  end
  -- Stalfos_OnTick tail
  if (e.u7c or 0) ~= 0 then
    e.u7c = e.u7c - 1
    if e.u7c ~= 0 then e.hitType = 0x45 else e.hitType = e.u7d end
  end
end

-- ===========================================================================
-- FLYING_SKULL
-- ===========================================================================
function M.skullFree(E, e) -- its SPECIAL_TILE_96 back
  if e.sTile then block(E.field, e.sTile[1], e.sTile[2], L(e), false); e.sTile = nil end
end
local function skullBreak(E, e) -- sub_0803A0E0
  M.skullFree(E, e)
  fx(E.field, e.x, e.y, FX.BONE)
  e.deleted = true
  if e.carriedBy and e.carriedBy.carried and e.carriedBy.carried.ent == e then e.carriedBy.carried = nil end
end
M.skullBreak = skullBreak
local function skullFlip(e)
  e.action, e.zv = 7, 2.625
  collide(e, false)
end
function M.skullCollision(E, e, flg)
  if flg == 0x9D then
    M.skullFree(E, e)
    skullFlip(e)
  elseif (e.z or 0) ~= 0 then
    skullBreak(E, e)
  end
end

-- the carry system (type 0: RegisterCarryEntity)
local carry = {}
function carry.lift(f, p, e)
  M.skullFree(f:enemies(), e)
  e.carriedBy, e.hidden, e.noTouch, e.noHit, e.liftable = p, true, true, true, nil
  e.action = 2
  e.hitbox = HB_SKULL_HELD
  f:objects():lift(p, { obj = e.id, form = 0, ent = e, hook = carry,
    def = { sprite = e.sprite, palette = e.def and e.def.palette, gfxType = "enemy", gfx = e.def and e.def.gfx } })
  return true
end
local function release(f, p, c, vx, vy, z)
  local e = c.ent
  p.carried = nil
  e.carriedBy, e.hidden = nil, false
  e.x, e.y, e.z, e.zv = p.x, p.y, z, 0.5
  e.thrownV = { vx, vy }
  e.action = 2
end
function carry.throw(f, p, c)
  local s = p.animationState
  release(f, p, c, (s == 2 and 1 or s == 6 and -1 or 0) * 2.5, (s == 4 and 1 or s == 0 and -1 or 0) * 2.5, 14)
  f:sound(0x7C)
end
function carry.drop(f, p, c) release(f, p, c, 0, 0, 4) end
M.skullCarry = carry

function M.skull(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- sub_08039D74
    e.onCollision = M.skullCollision
    e.action = 1
    e.y = e.y + 3
    local tx, ty = tileOf(e.x, e.y)
    e.sTile = { tx, ty }
    block(f, tx, ty, L(e), true)
    setAnim(E, e, 0)
    if (e.form or 0) == 0 then
      e.liftable = true
      e.carryHook = function(ff, p, x) return carry.lift(ff, p, x) end
    end
  elseif a == 1 then -- sub_08039DD8
    if (e.form or 0) ~= 0 then
      local p = f.player
      if p and not p.minish and within(e, p.x, p.y, 0x30) then
        if e.form == 1 then e.action, e.timer = 3, 30
        else
          local s = E:spawn({ kind = 3, id = ID.STALFOS, paramA = e.form - 2, paramB = 1, paramC = 0, x = math.floor(e.x), y = math.floor(e.y) })
          if s then
            s.layer = e.layer
            f.entities[#f.entities + 1] = s
          end
          M.skullFree(E, e)
          e.deleted = true
        end
      end
    end
  elseif a == 2 then -- carried / thrown (sub_08039ECC)
    if e.carriedBy then return end
    local v = e.thrownV or { 0, 0 }
    e.x, e.y = e.x + v[1], e.y + v[2]
    e.z = e.z + e.zv; e.zv = e.zv - 0.25
    local hit = f.room:isSolid(e.x, e.y, L(e))
    if not hit then
      for _, o in ipairs(f.entities) do
        if o ~= e and o.enemy and not o.dying and not o.deleted and math.abs(o.x - e.x) < 10 and math.abs(o.y - e.y) < 10 then
          E:hit(o, 4, e.x, e.y, 2); hit = true; break
        end
      end
    end
    if e.z <= 0 or hit then skullBreak(E, e) end
  elseif a == 3 then -- sub_08039FAC
    e.spriteOX = (e.spriteOX or 0) + M.SKULL_SHAKE[band(e.timer, 3)]
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.action = 4
      collide(e, true)
      e.spriteOX = 0
      e.hitType, e.hitbox = 0xA0, HB_SKULL_FLY
      M.skullFree(E, e)
    end
  elseif a == 4 then -- sub_0803A048
    e.anim:update(1)
    e.z = (e.z or 0) + 1
    if e.z >= 6 then
      e.action, e.timer = 5, 10
      local p = f.player
      e.dir = dirTo(e.x, e.y, p.x, p.y)
    end
  elseif a == 5 then
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then e.action = 6 end
  elseif a == 6 then -- sub_0803A09C
    e.anim:update(1)
    move0(E, e, e.dir, e.speed ~= 0 and e.speed or 0x100)
    if (e.collisions or 0) ~= 0 then skullBreak(E, e) end
  elseif a == 7 then -- sub_0803A0B8
    if (e.zv or 0) < 0 then e.flipY = true end
    if not gravity(e, 32 / 256) then skullBreak(E, e) end
  end
end

-- ===========================================================================
-- the R26 hooks
-- ===========================================================================
local MINE = { [ID.SPARK] = true, [ID.WIND] = true, [ID.FIRE] = true, [ID.ICE] = true, [ID.ARMOS] = true,
               [ID.EYEGORE] = true, [ID.STALFOS] = true, [ID.SKULL] = true }
function M.handles(e) return e.enemy and MINE[e.id] == true end

function M.update(E, e)
  local id = e.id
  if id == ID.SPARK then return M.spark(E, e) end
  if id == ID.WIND or id == ID.FIRE or id == ID.ICE then return M.wizzrobe(E, e) end
  if id == ID.EYEGORE then return M.eyegore(E, e) end
  if id == ID.ARMOS then return M.armos(E, e) end
  if id == ID.STALFOS then return M.stalfos(E, e) end
  if id == ID.SKULL then return M.skull(E, e) end
end

return M
