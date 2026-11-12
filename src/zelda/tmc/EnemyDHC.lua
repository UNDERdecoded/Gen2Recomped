-- Round 26 (team B): Dark Hyrule Castle enemies, from the decomp.
-- R26.lua dispatches here (handles / update / spawnEnemy).
--
-- COMMON: Random() is Drops.random on the shared seed; directions 0-31 (0
--   north, clockwise); DirectionRound (d & $18), DirectionRoundUp ((d + 4)
--   & $18); sub_08049DF4(1) = the enemy target (EnemyDeepwood.target);
--   sub_08049FDC = the target inside the home rectangle, sub_08049FA0 =
--   the enemy inside it, sub_08049EE4 = toward its middle; sub_08049F1C =
--   same layer and within n px; sub_0804A044 = EnemyBeetle.linedUp;
--   ProcessMovement0 = a leading-edge box probe per axis (its blocked axes
--   are the next frame's `collisions`).  super->frame (the keyframe's flags, ANIM_DONE
--   $80) is the Anim's flags; "frame &= ~bit" / "frame = 0" consume bits of
--   that keyframe.  Children (the sword slash) are entities made here
--   (enemy = true, an id that no other port claims, noTouch): their contact
--   with Link (Link's ROM hitbox, gCollisionMtx, the shield) and the sword's
--   contact with them (Enemies:hit -> e.r26hit) are done here.
--
-- DARK_NUT $05 (src/enemy/darkNut.c), types 0-3:
--   all 20 actions (gUnk_080CAAB0): 0 Init (home, unk_78 = health, state
--   $FF -> sub_08021218(0, 2)); 1 waits for Link in its home; 3 walk
--   (sub_08021540: every 30 frames a new direction -- homeward half the time
--   outside its home, else DirectionRound(rand >> 16); unk_76 $F0 frames,
--   then 5 = look round); sub_080214FC (Link in the home and his bearing
--   within the keyframe's look window (frame & $1F) + 2..6) -> 6 (draw the
--   sword) -> 7 (sub_08020E98: inside 56 px it backs off from Link until his
--   distance is beyond the reach of its facing (sub_0802169C: $2C / $24 /
--   $1D / $24) or a wall stops it -> 8 -> 9; outside, it walks at him at
--   $200); 9 (sub_08020F48, speed $60): Link inside $48 and within the
--   strike reach (sub_08021664: $22 / $1A / $13 / $1A) and lined up
--   (sub_0804A044 9) -> 14 = the stab (a slash type 1, SFX_15D on frame
--   bit 0); else sub_08021424 (walk to the point $2C / $24 / $1D / $24 from
--   Link on its facing side; there or blocked -> sub_080212B0: the attack
--   picked from gUnk_080CAB3A / 42 / 4A in turn (types 0/1 reroll the spin
--   with gUnk_080CAB52): 13 = slash combo (slash type 0 while the keyframe
--   flags are set, SFX_10E, hit type 81 on frame 4, gUnk_080CAB68 frames of
--   rest), 15 = charge ($200, $78 frames, a slash type 2 on frame bit 0,
--   moves on frame bit 4 keyframes until a wall / its slash touches), 18 =
--   spin (sub_0802159C: frame 1 hit type $51 + slash type 3 (drawn,
--   animation state + $18), SFX_116; frame 2 slash gone; bit 5 SFX_115),
--   19 = sweep (sub_08021600, slash type 4)); 10 shield block (a hit from
--   the front: unk_7a = gUnk_080CAB04 for hurt types 8-12, gUnk_080CAB00
--   for 4-6), 11/12 stunned (contact $1C / $16: gUnk_080CAB0C / 10 frames,
--   hit type 81), 16 recoil after a parried charge (gUnk_080CAB08 when the
--   shield stopped the slash), 17 looks round.  sub_08021218 / gUnk_080CAB14
--   pick the sprite ($62 / $63) and animation group by state; sub_08021274
--   keeps the facing on diagonals; sub_08021644 SFX_PLY_LAND on frame bit 5.
--   The shield: the matrix entry for hit type $56 vs the sword is handler
--   13 (collision.c sub_08017D6C): a hit within +-5 of its facing ->
--   contact $CB, unk_79 = hurt type, row $52 (Link's sword recoils, sparks
--   FX_REFECT3, no damage); else row $51 (damage).
-- DARK_NUT_SWORD_SLASH (projectile/darkNutSwordSlash.c): types 0-4 follow
--   the Dark Nut (CopyPositionAndSpriteOffset), hit type
--   DarkNutSwordSlash_hitTypes[parent type + type * 4], hitboxes
--   gUnk_081293E0 (by state and (frame & $F) - 1) / F0 / 0400 / 10 / 20;
--   type 3 is drawn (animation state + $18, y + 1).  Touching Link's body
--   gives it iframes $2D; the sword or the shield against it (matrix flags 4)
--   is the Dark Nut's contact $CC (a parried charge).  Gone when its Dark
--   Nut lets go (sub_08021588) or dies.
-- WISP $34 (src/enemy/wisp.c), types 0/1: Init (gustJarFlags 1, home spot
--   kept, animation = type2), sub_080336A8 (bounces off walls, a new heading
--   when its timer runs out: sub_08033744 -- gUnk_080CEBA4 timers, outside
--   its home homeward +-4 (75%)), sub_080336DC (after it touched Link:
--   hidden $27C frames, back at its spot at $24, CreateDeathFx at $18, shown
--   at $C).  Touching Link (matrix handler 14, sub_08017D28): Link pushed
--   back ($280, 12 frames, iframes 16), PL_DRUGGED, gSave.stats.effect =
--   type + 1 for 600 frames; type 1 is gone after.  Hurt types $E / $15
--   kill it, $14 (a blast) puffs it away.  The sword does nothing (handler 1).
-- DOOR_MIMIC $09 (src/enemy/doorMimic.c), types 0-7 (type2 = type & 3):
--   the door tile beside it (gUnk_080B4488[type2], a ROM table) becomes
--   SPECIAL_TILE_35 / 37 / 38 / 36 (gUnk_080CB79C); Link within 16 x 16 of
--   gUnk_080CB764's point -> 18 frames -> the slam (damage 4 on frame bit 0,
--   six FX_DASH at gUnk_080CB76C, SFX_PLACE_OBJ) -> 120 frames pushing Link
--   out -> animation + 8 -> 90 frames idle.  Its hitbox each frame is
--   gUnk_080CB8A4[type2][frameIndex].  Contact (handler 5, sub_08017EB0):
--   only while damage != 0, 8 health, 12 frames at $180, iframes 16.  On
--   death: the door tile back, FX_POT_SHATTER, no respawn, no drop.
-- ENEMY_50 $50 (src/enemy/enemy50.c, the DHC Ghini with clones): Init (type
--   0 reads its room property [timer]: four spawn points), 1 waits for Link
--   in its home (type2 1: the lantern lit, 2: lit room), 2 (15 frames) ->
--   sub_0804122C: three type-1 copies (parent = it, unk_80 0-3) on three of
--   the points, itself on the fourth; 3 rises (collision on, unk_7c =
--   unk_80 * ((R & $30) + $3C) + $78), 4 wanders (ghini.c sub_0803F528:
--   gUnk_080D0974 speeds, gUnk_080D0978 turns, hit type $24; half vertical
--   speed sub_0803F58C) until sub_08041170 (unk_7c out, Link in the home
--   and the lantern near or the room lit and within $70 x $48) -> 5 (hit
--   type $25, gUnk_080D0E18 + $3C with clones) -> 6 chase ($100 at Link,
--   turning by gUnk_080D0E14) -> 7 (30 frames) -> wander; 8 / 9 Link caught
--   (handler 7, sub_08017F40: Link locked, ghost on him; -4 health with
--   SFX_PLY_VO6 on frame bit 0, each button press + 8, $E0 lets go:
--   sub_0803F6EC Link hops off, iframes 60); 10 (60 frames) a copy hit.
--   A copy's hit resets its health to $FF (only type 0 dies); the copies go
--   (FX_DEATH) when it does.
-- SIMPLIFIED: FX_STARS / the FX offsets, GenericConfused, the knockback
--   iframes' sign (negative = no flicker) and OnGrabbed (the Gust Jar) are
--   the port's generic ones; the Dark Nut's combo creates a slash every
--   other frame (and SFX_10E) while its done keyframe ($86) lasts, as the
--   cartridge does; a keyframe with flags & $F = 0 gives index -1 (memory
--   before gUnk_08129460) -- no box here;
--   the Wisp's effect is recorded (f.save.stats.effect / effectTimer,
--   p.drugged) but the Player does not read it yet; ProcessMovement1 is a
--   move without tile collision; the lantern is p.lanternLit, the light
--   level f.lightLevel (missing = lit); Link's "burning" and the item reset
--   on capture are not modelled.
-- NOT HERE: SPEAR_MOBLIN $15 (+ MOBLIN_SPEAR), BOW_MOBLIN $46 (+ ARROW_
--   PROJECTILE) and KEATON $30 (+ KEATON_DAGGER) are ported from the same
--   decomp files by team A (EnemyField1/2.lua); R26 runs before EnemyField
--   in Enemies:update, so this module leaves them alone.
local bit = require("bit")
local band, bor, bxor, bnot, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift

local M = {}
M.DARK_NUT, M.DOOR_MIMIC, M.WISP, M.ENEMY_50 = 0x05, 0x09, 0x34, 0x50
M.SLASH_ID = 0x1E00 -- the slash child's entity id (no other port uses it)

local SFX_15D, SFX_10E, SFX_116, SFX_115, SFX_PLY_LAND = 0x15D, 0x10E, 0x116, 0x115, 0x7D
local SFX_PLACE_OBJ, SFX_PLY_VO6 = 0x104, 0x7A
local SPECIAL_FX, FX_DEATH, FX_POT_SHATTER, FX_DASH, FX_STARS, FX_REFECT3 = 0x0F, 2, 5, 17, 28, 44

M.ROM_RANGES = {
  doorTileOffsets = { 0x080B4488, 0x080B4490 }, -- gUnk_080B4488 (data_080B4410/gUnk_080B4488.bin): s16 tile offset by type2
}

-- ---------------------------------------------------------------------------
-- tables written out in the decomp's .c files
-- ---------------------------------------------------------------------------
M.DN_BLOCK46 = { [0] = 30, 30, 20, 10 }   -- gUnk_080CAB00
M.DN_BLOCK8C = { [0] = 60, 60, 45, 30 }   -- gUnk_080CAB04
M.DN_PARRY = { [0] = 90, 90, 60, 30 }     -- gUnk_080CAB08
M.DN_STUN1C = { [0] = 90, 90, 60, 30 }    -- gUnk_080CAB0C
M.DN_STUN16 = { [0] = 90, 90, 45, 8 }     -- gUnk_080CAB10
M.DN_GROUP = { [0] = { 0x00, 0x62 }, { 0x04, 0x62 }, { 0x08, 0x62 }, { 0x0C, 0x62 }, { 0x10, 0x62 }, { 0x14, 0x62 },
               { 0x18, 0x62 }, { 0x1C, 0x62 }, { 0x20, 0x62 }, { 0x24, 0x62 }, { 0x28, 0x62 }, { 0x2C, 0x62 },
               { 0x00, 0x63 }, { 0x04, 0x63 }, { 0x08, 0x63 }, { 0x0C, 0x63 }, { 0x10, 0x63 }, { 0x14, 0x63 },
               { 0x18, 0x63 } } -- gUnk_080CAB14 {animation base, sprite}
M.DN_PICK1 = { [0] = 0, 1, 1, 0, 3, 0, 1, 0 } -- gUnk_080CAB3A
M.DN_PICK2 = { [0] = 1, 1, 3, 0, 1, 2, 0, 0 } -- gUnk_080CAB42
M.DN_PICK3 = { [0] = 0, 0, 3, 1, 2, 2, 3, 1 } -- gUnk_080CAB4A
M.DN_REROLL = { [0] = 0, 3, 1, 0 }            -- gUnk_080CAB52
M.DN_COMBO = { [0] = 90, 90, 45, 7 }           -- gUnk_080CAB68
M.SLASH_HIT = { [0] = 76, 76, 78, 77, 83, 83, 83, 83, 79, 79, 76, 80, 84, 84, 84, 85, 79, 79, 76, 80 } -- DarkNutSwordSlash_hitTypes
local function hb(x, y, w, h) return { x = x, y = y, w = w, h = h } end
M.SLASH_T0 = { -- gUnk_081293E0: by animation state, (frame & $F) - 1
  [0] = { [0] = hb(-5, -32, 8, 10), hb(2, -37, 8, 10), hb(19, -33, 10, 11), hb(28, -14, 16, 6), hb(34, -18, 8, 4), hb(25, 15, 4, 4) },
  { [0] = hb(21, -6, 12, 8), hb(21, -20, 16, 8), hb(15, -31, 8, 10), hb(3, -39, 8, 12), hb(7, -38, 7, 8), hb(1, -29, 4, 5) },
  { [0] = hb(7, 7, 8, 11), hb(-6, 10, 8, 12), hb(-22, 2, 8, 8), hb(-27, -11, 12, 8), hb(-28, -9, 15, 6), hb(-21, -12, 6, 2) },
  { [0] = hb(-21, -6, 12, 8), hb(-21, -20, 16, 8), hb(-15, -31, 8, 10), hb(-3, -39, 8, 12), hb(-7, -38, 7, 8), hb(-1, -29, 4, 5) },
}
M.SLASH_T2 = { [0] = hb(3, -30, 7, 10), hb(28, -12, 14, 7), hb(-2, 14, 12, 7), hb(-28, -12, 14, 7) }   -- gUnk_081293F0
M.SLASH_T34 = { [0] = hb(4, -37, 7, 10), hb(32, -14, 14, 6), hb(-1, 22, 7, 12), hb(-32, -14, 14, 6) } -- gUnk_08129400
M.SLASH_T34B = { [0] = hb(4, -35, 2, 8), hb(30, -14, 12, 2), hb(-1, 20, 2, 10), hb(-30, -14, 12, 2) } -- gUnk_08129410 (frame bit 4)
M.SLASH_T1 = { [0] = hb(1, -29, 8, 8), hb(19, -8, 8, 8), hb(0, 10, 8, 8), hb(-19, -8, 8, 8) }       -- gUnk_08129420
M.WISP_TIME = { [0] = 30, 45, 60, 75, 1, 90, 105, 120 } -- gUnk_080CEBA4
M.DM_POINT = { [0] = { -8, 0 }, { -16, -8 }, { -8, -16 }, { 0, -8 } } -- gUnk_080CB764
M.DM_DUST = { -- gUnk_080CB76C
  [0] = { { -4, 26 }, { 4, 26 }, { -12, 16 }, { 12, 16 }, { -12, 8 }, { 12, 8 } },
  { { -26, -4 }, { -26, 4 }, { -16, -12 }, { -16, 12 }, { -8, -12 }, { -8, 12 } },
  { { -4, -26 }, { 4, -26 }, { -12, -16 }, { 12, -16 }, { -12, -8 }, { 12, -8 } },
  { { 26, -4 }, { 26, 4 }, { 16, -12 }, { 16, 12 }, { 8, -12 }, { 8, 12 } },
}
M.DM_TILE = { [0] = 0x4023, 0x4025, 0x4026, 0x4024 } -- gUnk_080CB79C: SPECIAL_TILE_35 / 37 / 38 / 36
local DM_V = { [0] = hb(0, -9, 8, 6), hb(0, -5, 6, 4), hb(0, -1, 6, 4), hb(0, 7, 6, 8), hb(0, 11, 8, 12), hb(0, 11, 8, 12),
               hb(0, 8, 8, 8), hb(0, 4, 8, 4), hb(0, 0, 8, 4), hb(0, -8, 8, 8), hb(0, -12, 8, 12), hb(0, -12, 8, 12) } -- gUnk_080CB7F4
local DM_H = { [0] = hb(-8, 0, 8, 8), hb(-4, 0, 4, 8), hb(0, 0, 4, 8), hb(8, 0, 8, 8), hb(12, 0, 12, 8), hb(12, 0, 12, 8),
               hb(8, 0, 8, 8), hb(4, 0, 4, 8), hb(0, 0, 4, 8), hb(-8, 0, 8, 8), hb(-12, 0, 12, 8), hb(-12, 0, 12, 8) } -- gUnk_080CB874
M.DM_BOX = { [0] = DM_V, DM_H, DM_V, DM_H } -- gUnk_080CB8A4
M.E50_TURN_MASK = { [0] = 15, 7, 3, 1 }     -- gUnk_080D0E14
M.E50_DELAY = { [0] = 15, 25, 34, 45 }      -- gUnk_080D0E18
M.GHINI_SPEED = { [0] = 224, 192, 160, 128 } -- gUnk_080D0974 (ghini.c)
M.GHINI_TURN = { [0] = 0, -2, 0, 2, 0, -4, 0, 4 } -- gUnk_080D0978 (ghini.c)

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function R(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end
local function dirTo(ax, ay, bx, by) return DW().dirTo(ax, ay, bx, by) end
local function target(f) return DW().target(f) end
local function facing(a, b) return dirTo(a.x, a.y, b.x, b.y) end -- GetFacingDirection
local function roundUp(d) return band(d + 4, 0x18) end
local function toState(d) return rshift(roundUp(d), 3) end       -- DirectionToAnimationState
local function inRect(e, x, y)
  local dx, dy = math.floor(x) - (e.homeX or 0), math.floor(y) - (e.homeY or 0)
  return dx >= 0 and dx <= (e.rangeW or 0) and dy >= 0 and dy <= (e.rangeH or 0)
end
local function linkHome(f, e) local t = target(f) return t ~= nil and inRect(e, t.x, t.y) end -- sub_08049FDC
local function selfHome(e) return inRect(e, e.x, e.y) end                                  -- sub_08049FA0
local function homeDir(e) return dirTo(e.x, e.y, (e.homeX or e.x) + (e.rangeW or 0) / 2, (e.homeY or e.y) + (e.rangeH or 0) / 2) end -- sub_08049EE4
local function within(a, b, d) -- sub_08049F1C
  if band(a.layer or 1, b.layer or 1) == 0 then return false end
  local dx, dy = math.floor(b.x) - math.floor(a.x), math.floor(b.y) - math.floor(a.y)
  return d * d >= dx * dx + dy * dy
end
local function turnStep(e, dir) -- sub_08004596
  local cur = e.direction or 0
  if cur >= 0x20 then e.direction = band(dir, 0x1F) return end
  local d = band(dir - cur, 0x1F)
  if d == 0 then return end
  e.direction = band(cur + (d < 0x10 and 1 or -1), 0x1F)
end
M.h = { dirTo = dirTo, target = target, inRect = inRect, within = within, turnStep = turnStep, R = R }

local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i); e.fkey = nil end
-- the keyframe's flag byte, less the bits this keyframe already used
local function fl(e)
  local a = e.anim
  if not a then return 0 end
  local v = a.flags or 0
  if e.fkey == a.key and e.fkeys == a.keys then v = band(v, bnot(e.fmask or 0)) end
  return v
end
local function take(e, bits)
  local a = e.anim
  if e.fkey ~= a.key or e.fkeys ~= a.keys then e.fkey, e.fkeys, e.fmask = a.key, a.keys, 0 end
  e.fmask = bor(e.fmask, bits)
end
local function done(e) return band(fl(e), 0x80) ~= 0 or not (e.anim and e.anim.keys) end
local function step(e) e.anim:update(1) end
M.h.fl, M.h.take, M.h.done = fl, take, done

-- ProcessMovement0: true when it moved freely
-- (like the cartridge's tile probes, only the leading edge of the hitbox is
-- tested, so an entity standing half inside a solid tile can walk out)
local function pm0(E, e, dir, spd)
  if not dir or dir >= 0x20 then e.colX, e.colY = false, false return true end
  local room = E.field.room
  local a = (dir % 32) / 32 * 2 * math.pi
  local s = (spd or 0) / 256
  local vx, vy = math.sin(a) * s, -math.cos(a) * s
  if math.abs(vx) < 1e-6 then vx = 0 end
  if math.abs(vy) < 1e-6 then vy = 0 end
  local b = e.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  local hw, hh = math.max(2, b.w), math.max(2, b.h)
  local L = (e.layer == 2) and 2 or 1
  local hx, hy = false, false
  if vx ~= 0 then
    local nx = e.x + vx
    local ex = nx + b.x + (vx > 0 and hw - 1 or -hw)
    local cy = e.y + b.y
    if room:isSolid(ex, cy - hh, L) or room:isSolid(ex, cy + hh - 1, L) or room:isSolid(ex, cy, L) then hx = true else e.x = nx end
  end
  if vy ~= 0 then
    local ny = e.y + vy
    local ey = ny + b.y + (vy > 0 and hh - 1 or -hh)
    local cx = e.x + b.x
    if room:isSolid(cx - hw, ey, L) or room:isSolid(cx + hw - 1, ey, L) or room:isSolid(cx, ey, L) then hy = true else e.y = ny end
  end
  e.colX, e.colY = hx, hy
  return not (hx or hy)
end
local function linear(e, dir, spd) -- LinearMoveUpdate / ProcessMovement1 (no tiles)
  if not dir or dir >= 0x20 then return end
  local a = (dir % 32) / 32 * 2 * math.pi
  local s = (spd or 0) / 256
  e.x, e.y = e.x + math.sin(a) * s, e.y - math.cos(a) * s
end
M.h.pm0, M.h.linear = pm0, linear

local function fx(f, x, y, t) if f.addFx then f:addFx(x, y, SPECIAL_FX, t) end end
M.h.fx = fx

-- Link pushed back (an attacker's recoil, no damage)
local function knockLink(f, fromX, fromY, spd, dur)
  local p = f.player
  if not p or p.state == "dead" or (dur or 0) <= 0 then return end
  local dx, dy = p.x - fromX, p.y - fromY
  local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
  local s = (spd or 0) * 16 / 256
  p.kbx, p.kby = dx / d * s, dy / d * s
  if p.state == "normal" or p.state == "sword" or p.state == "shield" then p.state, p.timer = "hurt", dur end
end
M.h.knockLink = knockLink

-- Link's body against a box (Link's ROM hitbox; the old approximation without it)
local function touches(f, e, box)
  local p = f.player
  box = box or e.hitbox
  if not p or not box then return false end
  local HB = require("src.zelda.tmc.Hitboxes")
  local t = HB.touches(f, p, { x = e.x, y = e.y, hitbox = box })
  if t == nil then
    t = math.abs((e.x + box.x) - p.x) < box.w + 5 and math.abs((e.y + box.y) - (p.y - 3)) < box.h + 6
  end
  return t
end
local function canTouch(f, e)
  local p = f.player
  return p and p.state ~= "dead" and not e.hidden and (e.z or 0) < 8
end
-- Link's body takes the matrix entry (hitType vs Link's hurtType)
local function hurtLink(E, e, hitType)
  local f = E.field
  local p = f.player
  local HB = require("src.zelda.tmc.Hitboxes")
  local s = E:settings(hitType or e.hitType or 0, HB.data(f) and HB.hurtType(p) or 0)
  if not s then return false end
  if s.tgtDmg > 0 or s.orgKbDur > 0 then
    if p:hurt(math.max(s.tgtDmg, 1), e.x, e.y) then
      p.invuln = math.max(s.orgIfr, 30)
      p.timer = math.max(s.orgKbDur, 4)
      local ks = (s.orgKbSpd * 16) / 256
      local dx, dy = p.x - e.x, p.y - e.y
      local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.kbx, p.kby = dx / d * ks, dy / d * ks
      return true
    end
  end
  return false
end
M.h.touches, M.h.canTouch, M.h.hurtLink = touches, canTouch, hurtLink

local function handler(E, hitType, hurtType)
  if not E.mtx or E.mtx == "" then return nil end
  return require("src.zelda.tmc.Hitboxes").handler(E.mtx, hitType or 0, hurtType)
end
local function sparks(f, a, b) fx(f, math.floor((a.x + b.x) / 2), math.floor((a.y + b.y) / 2), FX_REFECT3) end -- sub_08017940

local function projDef(f, id, form)
  local defs = f.assets and f.assets.manifest and f.assets.manifest.projectileDefs
  local d = defs and defs[id]
  if d and d.multi then d = d.forms and (d.forms[form or 0] or d.forms[0]) end
  return d
end
M.h.projDef = projDef

local FAR = { x = 0, y = -4096, w = 0, h = 0 } -- no hitbox this frame
local function child(E, parent, kind, form, def)
  local f = E.field
  local Anim = require("src.zelda.tmc.Anim")
  local c = { kind = 4, id = M.SLASH_ID, projId = kind, form = form, x = parent.x, y = parent.y, z = parent.z or 0,
              layer = parent.layer, enemy = true, r26child = true, parent = parent, action = 0, timer = 0,
              iframes = 0, kbt = 0, health = 1, maxHealth = 1, hitbox = FAR, def = { collision = 1 },
              noTouch = true, anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0, animationState = 0,
              spawnB = 0, spawnC = 0, homeX = 0, homeY = 0, rangeW = 0, rangeH = 0, hidden = true }
  if def and def.draw ~= 0 and def.sprite and def.sprite ~= 0 then
    c.sprite = def.sprite
    c.palette = f.assets:objPalette(def.palette, f.room and f.room.atlas and f.room.atlas.palettes)
    c.gfx = require("src.zelda.tmc.Assets").gfxSource("enemy", def.gfx)
    c.hidden = false
  end
  f.entities[#f.entities + 1] = c
  return c
end
M.h.child = child

function M.handles(e)
  return e.id == M.DARK_NUT or e.id == M.SLASH_ID or e.id == M.WISP or e.id == M.DOOR_MIMIC or e.id == M.ENEMY_50
end

-- ===========================================================================
-- DARK_NUT
-- ===========================================================================
local function group(E, e, g, s) -- sub_08021218
  if e.u74 == g and e.animationState == s then return end
  e.animationState, e.u74 = s, g
  local t = M.DN_GROUP[g]
  e.sprite = t[2]
  setAnim(E, e, t[1] + s)
end
function M.turnState(state, dir) -- sub_08021274
  local lo = band(dir, 7)
  if lo >= 3 and lo <= 5 and (rshift(band(dir, 0x18), 3) == state or rshift(band(dir + 8, 0x18), 3) == state) then
    return 0xFF
  end
  local d = rshift(roundUp(dir), 3)
  if state == d then return 0xFF end
  return d
end
local function faceDir(E, e) -- sub_0802124C
  local s = M.turnState(e.animationState, e.direction or 0)
  if s ~= 0xFF then group(E, e, e.u74, s) else step(e) end
end
local function landSfx(E, e) -- sub_08021644
  if band(fl(e), 0x20) ~= 0 then take(e, 0x20); E.field:sound(SFX_PLY_LAND) end
end
local function dropChild(e) -- sub_08021588
  if e.child then e.child.parent = nil; e.child = nil end
end
local function retreat(E, e) -- sub_08021390
  e.action, e.spd, e.hitType = 7, 0x200, 0x56
  group(E, e, 6, e.animationState)
end
local function walk(E, e) -- sub_080213B0
  e.action, e.timer, e.spd, e.u76 = 3, 1, 0xC0, 0xF0
  group(E, e, 3, e.animationState)
end
local function recoil(E, e, n) -- sub_080213D0
  e.action, e.u7b = 16, n
  group(E, e, 0xF, e.animationState)
  dropChild(e)
end
local function draw(E, e) e.action = 6; group(E, e, 1, e.animationState) end -- sub_080213F0
local function approach(E, e) e.action, e.spd = 9, 0x60; group(E, e, 10, e.animationState) end -- sub_08021400
local function lookRound(E, e) e.action = 17; group(E, e, 5, e.animationState) end -- sub_08021414

local function slash(E, e, typ)
  local f = E.field
  local c = child(E, e, 0x00, typ, projDef(f, 0x00, typ))
  c.r26slash = true
  e.child = c
  return c
end

local function sees(E, e) -- sub_080214FC
  local f = E.field
  if not linkHome(f, e) then return false end
  local t = target(f)
  local dir = facing(e, t)
  local v = dir - band(fl(e), 0x1F) - 2
  if v < 0 or v > 4 then return false end
  e.animationState = toState(dir)
  return true
end
local function newDir(E, e) -- sub_08021540
  local r = R(E.field)
  local d
  if not selfHome(e) and band(r, 1) ~= 0 then d = roundUp(homeDir(e))
  else d = band(rshift(r, 16), 0x18) end
  e.direction = d
  local s = M.turnState(e.animationState, d)
  if s ~= 0xFF then group(E, e, 3, s) end
  e.timer = 30
end
local REACH_BACK = { [0] = 0x2C, 0x24, 0x1D, 0x24 }
local REACH_HIT = { [0] = 0x22, 0x1A, 0x13, 0x1A }
local function farEnough(e, t) return not within(e, t, REACH_BACK[e.animationState] or 0) end -- sub_0802169C
local function inReach(e, t) return within(e, t, REACH_HIT[e.animationState] or 0) end         -- sub_08021664

local ATTACK
local function pick(E, e) -- sub_080212B0
  local f = E.field
  local tmp
  if e.u75 == 1 then e.u75 = 2; tmp = M.DN_PICK2[band(R(f), 7)]
  elseif e.u75 == 2 then e.u75 = 0; tmp = M.DN_PICK3[band(R(f), 7)]
  else e.u75 = 1; tmp = M.DN_PICK1[band(R(f), 7)] end
  if (e.form or 0) < 2 and tmp == 2 then tmp = M.DN_REROLL[band(R(f), 3)] end
  e.child = nil
  ATTACK[tmp](E, e)
end
ATTACK = {
  [0] = function(E, e) e.action, e.u7c = 13, M.DN_COMBO[e.form or 0] or 90; group(E, e, 0xC, e.animationState) end, -- sub_08021328
  function(E, e) -- sub_0802134C
    e.action, e.direction, e.spd, e.u76 = 15, lshift(e.animationState, 3), 0x200, 0x78
    group(E, e, 0xE, e.animationState)
  end,
  function(E, e) e.action = 18; group(E, e, 0x10, e.animationState) end, -- sub_08021370
  function(E, e) e.action = 19; group(E, e, 0x11, e.animationState) end, -- sub_08021380
}
local function reposition(E, e) -- sub_08021424
  local t = target(E.field)
  if not t then return pick(E, e) end
  local dir = facing(e, t)
  local tmp = M.turnState(e.animationState, dir)
  if tmp ~= 0xFF then group(E, e, e.u74, tmp) else tmp = e.animationState end
  local x, y
  if tmp == 0 then x, y = t.x, t.y + 0x2C
  elseif tmp == 1 then x, y = t.x - 0x24, t.y
  elseif tmp == 2 then x, y = t.x, t.y - 0x1D
  else x, y = t.x + 0x24, t.y end
  local dx, dy = math.floor(x) - math.floor(e.x), math.floor(y) - math.floor(e.y)
  if dx + 3 >= 0 and dx + 3 <= 6 and dy + 2 >= 0 and dy + 2 <= 4 then return pick(E, e) end
  e.direction = dirTo(e.x, e.y, x, y)
  if not pm0(E, e, e.direction, e.spd) then pick(E, e) else step(e) end
end
local function spinFrame(E, e) -- sub_0802159C
  local v = fl(e)
  if v == 1 then
    take(e, 0xFF); e.hitType = 0x51
    slash(E, e, 3)
    E.field:sound(SFX_116)
  elseif v == 2 then
    take(e, 0xFF); dropChild(e)
  elseif band(v, 0x20) ~= 0 then
    take(e, 0x20); E.field:sound(SFX_115)
  end
end
local function sweepFrame(E, e) -- sub_08021600
  local v = fl(e)
  if v == 1 then
    take(e, 0xFF); e.hitType = 0x51
    slash(E, e, 4)
    E.field:sound(SFX_10E)
  elseif v == 2 then
    take(e, 0xFF); dropChild(e)
  end
end

function M.darkNutCollision(E, e, cf) -- DarkNut_OnCollision
  local f = E.field
  local k = band(cf, 0x7F)
  local ty = e.form or 0
  if k == 0x1C or k == 0x16 then
    e.action = 11
    e.timer = (k == 0x1C and M.DN_STUN1C or M.DN_STUN16)[ty] or 90
    e.hitType = 81
    group(E, e, 8, toState(bxor(e.kbDir or 0, 0x10)))
    dropChild(e)
    fx(f, e.x, e.y - 22, FX_STARS)
  elseif k == 0x4B then
    local a = e.action
    if a ~= 13 and a ~= 15 and a ~= 19 and a ~= 18 then
      local u = e.u79 or 0
      if u >= 8 and u <= 12 then e.u7a = M.DN_BLOCK8C[ty] or 0
      elseif u >= 4 and u <= 6 then e.u7a = M.DN_BLOCK46[ty] or 0
      else e.u7a = 0 end
      e.action = 10
      group(E, e, 0xB, e.animationState)
      f:sound(SFX_15D)
      dropChild(e)
    end
  elseif k == 0x4C then
    if e.action == 15 then
      if (e.childContact or 0xFF) == 2 then recoil(E, e, M.DN_PARRY[ty] or 0) else recoil(E, e, 0) end
    end
  else
    if e.health ~= e.u78 then dropChild(e); retreat(E, e) end
  end
  e.u78 = e.health
end

-- Enemies:hit -> here first (e.r26hit): matrix handler 13 is the shield
local function hitAs(E, e, row, hurtType, fx_, fy, extra)
  local saved = e.hitType
  e.hitType, e.r26inHit = row, true
  local ok, r = pcall(E.hit, E, e, hurtType, fx_, fy, extra)
  e.r26inHit = nil
  if e.hitType == row then e.hitType = saved end
  if not ok then error(r, 0) end
  return r
end
function M.darkNutHit(E, e, hurtType, fromX, fromY, extra)
  if e.r26inHit then return nil end
  local f = E.field
  fromX, fromY = fromX or e.x, fromY or e.y + 1
  e.kbDir = dirTo(fromX, fromY, e.x, e.y)
  if handler(E, e.hitType, hurtType) ~= 13 then return nil end
  -- sub_08017D6C: within +-5 of the way it faces -> the shield
  local v = band(-band(bxor(e.kbDir, 0x10) - 5, 0x1F) + lshift(e.animationState or 0, 3), 0x1F)
  if v >= 0xB then return hitAs(E, e, 0x51, hurtType, fromX, fromY, extra) end
  e.u79 = hurtType
  local s = E:settings(0x52, hurtType)
  if s then
    knockLink(f, e.x, e.y, s.orgKbSpd, s.orgKbDur)
    if band(s.flags or 0, 1) ~= 0 then sparks(f, e, f.player) end
    local ifr = s.tgtIfr or 0
    e.iframes = math.max(e.iframes or 0, ifr < 0 and -ifr or ifr)
  end
  M.darkNutCollision(E, e, 0xCB)
  return false
end

function M.darkNut(E, e)
  local f = E.field
  e.onCollision = M.darkNutCollision
  e.r26hit = M.darkNutHit
  if e.child and (e.child.deleted or e.child.parent ~= e) then e.child = nil end
  local a = e.action
  if a == 0 then -- sub_08020D70
    e.action, e.u75, e.u78 = 1, 0, e.health
    e.animationState, e.u74 = 0xFF, nil
    e.spd = e.speed or 0x60
    group(E, e, 0, 2)
  elseif a == 1 then -- sub_08020D9C
    if linkHome(f, e) then draw(E, e) end
  elseif a == 2 then -- sub_08020DB4
    step(e); if done(e) then retreat(E, e) end
  elseif a == 3 then -- sub_08020DD4
    if sees(E, e) then draw(E, e)
    else
      e.u76 = band((e.u76 or 1) - 1, 0xFFFF)
      if e.u76 == 0 then e.action = 5; group(E, e, 5, e.animationState)
      else
        e.timer = band((e.timer or 1) - 1, 0xFF)
        if e.timer == 0 then newDir(E, e) end
        pm0(E, e, e.direction, e.spd)
        step(e)
      end
    end
  elseif a == 4 then -- sub_08020E28
    step(e); if done(e) then walk(E, e) end
  elseif a == 5 then -- sub_08020E48
    if sees(E, e) then draw(E, e)
    else step(e); if done(e) then walk(E, e) end end
  elseif a == 6 then -- sub_08020E78
    step(e); if done(e) then retreat(E, e) end
  elseif a == 7 then -- sub_08020E98
    local t = target(f)
    if t and within(e, t, 56) then
      if farEnough(e, t) then e.action = 8; group(E, e, 7, e.animationState)
      else
        e.direction = facing(t, e)
        if not pm0(E, e, e.direction, e.spd) then e.action = 8; group(E, e, 7, e.animationState)
        else
          e.direction = bxor(e.direction, 0x10)
          faceDir(E, e); landSfx(E, e)
        end
      end
    elseif not t then lookRound(E, e)
    else
      e.direction = facing(e, t)
      pm0(E, e, e.direction, e.spd)
      faceDir(E, e); landSfx(E, e)
    end
  elseif a == 8 then -- sub_08020F28
    step(e); if done(e) then approach(E, e) end
  elseif a == 9 then -- sub_08020F48
    local t = target(f)
    if t and within(e, t, 0x48) then
      if inReach(e, t) then
        local d = require("src.zelda.tmc.EnemyBeetle").linedUp(E, e, 9)
        if not d then reposition(E, e)
        else
          e.action = 14
          group(E, e, 13, rshift(d, 3))
          slash(E, e, 1)
        end
      else reposition(E, e) end
    else retreat(E, e) end
  elseif a == 10 then -- sub_08020FAC
    if done(e) then
      if (e.u7a or 0) > 0 then e.u7a = e.u7a - 1
      else e.iframes = math.max(e.iframes or 0, 8); retreat(E, e) end
    else step(e) end
  elseif a == 11 then -- sub_08020FE4
    step(e)
    e.timer = band((e.timer or 1) - 1, 0xFF)
    if e.timer == 0 then e.action = 12; group(E, e, 9, e.animationState) end
  elseif a == 12 then -- sub_08021010
    step(e); if done(e) then e.hitType = 0x56; draw(E, e) end
  elseif a == 13 then -- sub_08021038
    if not e.child and fl(e) ~= 0 then slash(E, e, 0); f:sound(SFX_10E) end
    if done(e) then
      dropChild(e)
      if (e.u7c or 0) > 0 then e.u7c = e.u7c - 1 else retreat(E, e) end
    else
      step(e)
      if fl(e) == 4 then e.hitType = 81 end
    end
  elseif a == 14 then -- sub_080210A8
    step(e)
    if band(fl(e), 1) ~= 0 then take(e, 0xFF); dropChild(e); f:sound(SFX_15D)
    elseif done(e) then retreat(E, e) end
  elseif a == 15 then -- sub_080210E4
    step(e)
    if band(fl(e), 1) ~= 0 then take(e, 1); slash(E, e, 2); f:sound(SFX_10E) end
    landSfx(E, e)
    local c = e.child
    local touched = c and c.contactNow
    if c then c.contactNow = nil end
    if band(fl(e), 0x10) ~= 0 and (not pm0(E, e, e.direction, e.spd) or touched) then recoil(E, e, 0)
    else
      e.u76 = band((e.u76 or 1) - 1, 0xFFFF)
      if e.u76 == 0 then recoil(E, e, 0) end
    end
  elseif a == 16 then -- sub_08021170
    if done(e) then
      if (e.u7b or 0) > 0 then e.u7b = e.u7b - 1 else retreat(E, e) end
    else step(e) end
  elseif a == 17 then -- sub_080211A0
    if sees(E, e) then retreat(E, e)
    else step(e); if done(e) then walk(E, e) end end
  elseif a == 18 then -- sub_080211D0
    step(e); spinFrame(E, e); if done(e) then retreat(E, e) end
  elseif a == 19 then -- sub_080211F4
    step(e); sweepFrame(E, e); if done(e) then retreat(E, e) end
  end
end

-- ---------------------------------------------------------------------------
-- DARK_NUT_SWORD_SLASH
-- ---------------------------------------------------------------------------
local function slashBox(c, p)
  local t, s = c.form or 0, p.animationState or 0
  if t == 0 then
    local row = M.SLASH_T0[s]
    return row and row[band(p.anim and p.anim.flags or 0, 0xF) - 1] or nil
  elseif t == 1 then return M.SLASH_T1[s]
  elseif t == 2 then return M.SLASH_T2[s]
  else
    if band(p.anim and p.anim.flags or 0, 0x10) ~= 0 then return M.SLASH_T34B[s] end
    return M.SLASH_T34[s]
  end
end
M.slashBox = slashBox

-- the parent's contact $CC (matrix flags 4) with the contact's hurt type
local function parry(E, c, hurtType, fromX, fromY, s)
  local p = c.parent
  c.contactNow = true
  if not p or p.dying or p.deleted then return end
  p.childContact = hurtType
  p.kbDir = dirTo(fromX, fromY, p.x, p.y)
  if p.onCollision then p.onCollision(E, p, 0xCC) end
  if s and (s.tgtKbDur or 0) > 0 then E:knock(p, fromX, fromY, s.tgtKbSpd or 24, s.tgtKbDur) end
end

function M.slashHit(E, c, hurtType, fromX, fromY) -- the sword against the slash
  local f = E.field
  local s = E:settings(c.hitType or 0, hurtType)
  if s then
    if band(s.flags or 0, 1) ~= 0 then sparks(f, c, f.player) end
    knockLink(f, c.x, c.y, s.orgKbSpd, s.orgKbDur)
    if band(s.flags or 0, 4) ~= 0 then parry(E, c, hurtType, fromX or c.x, fromY or c.y, s) end
    local ifr = s.tgtIfr or 0
    c.iframes = ifr < 0 and -ifr or (ifr == 0 and 1 or ifr)
  end
  return false
end

local function slashTouch(E, c)
  local f = E.field
  if (c.cool or 0) > 0 then c.cool = c.cool - 1 return end
  if c.hitbox == FAR or not canTouch(f, { z = c.z, hidden = false }) then return end
  if not touches(f, c, c.hitbox) then return end
  local p = f.player
  local par = c.parent
  if p:blocksFrom(par and par.x or c.x, par and par.y or c.y) then -- the shield (hurt type 2)
    local s = E:settings(c.hitType or 0, 2)
    f:sound(0x118)
    if s then
      knockLink(f, c.x, c.y, s.orgKbSpd, s.orgKbDur)
      if band(s.flags or 0, 1) ~= 0 then sparks(f, c, p) end
      if band(s.flags or 0, 4) ~= 0 then parry(E, c, 2, p.x, p.y, s) else c.contactNow = true end
    end
    c.cool = 8
  elseif (p.invuln or 0) == 0 then
    hurtLink(E, c, c.hitType)
    c.contactNow = true
    c.cool = 0x2D -- iframes -$2D
  end
end

function M.slash(E, c)
  local f = E.field
  local p = c.parent
  c.r26hit = M.slashHit
  if c.action == 0 then
    c.action = 1
    c.hitType = M.SLASH_HIT[(p and p.form or 0) + (c.form or 0) * 4] or 76
    if c.form == 3 and p then setAnim(E, c, (p.animationState or 0) + 0x18) end
  end
  if not p or p.deleted or p.dying or (p.health or 0) <= 0 or p.child ~= c then c.deleted = true return end
  c.x, c.y, c.z, c.layer = p.x, p.y, p.z or 0, p.layer
  c.spriteOX, c.spriteOY = p.spriteOX, p.spriteOY
  c.hitbox = slashBox(c, p) or FAR
  if c.form == 3 then c.y = c.y + 1; step(c) end
  slashTouch(E, c)
end

-- ===========================================================================
-- WISP
-- ===========================================================================
local function wispHeading(E, e) -- sub_08033744
  local f = E.field
  local r = band(R(f), 0xFF)
  e.timer = M.WISP_TIME[rshift(band(r, 0x70), 4)]
  local d = band(r, 0xC) * 2
  if not selfHome(e) and band(r, 3) ~= 0 then
    d = homeDir(e)
    if band(r, 0x80) ~= 0 then d = band(d + 4, 0x18) else d = band(d + 0x1C, 0x18) end
  end
  e.direction = d
end
local function bounce(e) -- sub_0800417E
  local d = e.direction or 0
  if e.colX then d = 0x20 - d end
  if e.colY then d = 0x10 - d end
  e.direction = band(d, 0x1F)
end
M.h.bounce = bounce

function M.wispCollision(E, e, cf) -- Wisp_OnCollision
  local f = E.field
  if band(cf, 0x80) == 0 then return end
  local k = band(cf, 0x3F)
  if k == 0 then
    e.action, e.hidden, e.noHit, e.noTouchW = 2, true, true, true
    e.u7c = 0x27C
    f.player.drugged = true -- PL_DRUGGED
    f.save.stats.effect = (e.form or 0) + 1
    f.save.stats.effectTimer = 600
    if (e.form or 0) ~= 0 then e.deleted = true end
  elseif k == 0x0E or k == 0x15 then
    e.health = 0
    E:kill(e)
  elseif k == 0x14 then
    e.noHit, e.noTouchW, e.iframes, e.hidden = true, true, 0, true
    fx(f, e.x, e.y, FX_DEATH)
    e.deleted = true
  end
end
function M.wispHit(E, e, hurtType)
  local h = handler(E, e.hitType, hurtType)
  if hurtType == 0x0E or hurtType == 0x15 or hurtType == 0x14 then M.wispCollision(E, e, 0x80 + hurtType) return true end
  if h == 1 or h == 2 then return false end
  return nil
end

function M.wisp(E, e)
  local f = E.field
  e.onCollision, e.r26hit = M.wispCollision, M.wispHit
  e.noTouch = true -- its contact is matrix handler 14 (sub_08017D28), done below
  local a = e.action
  if a == 0 then -- sub_08033674
    e.timer, e.action = 0, 1
    e.gustJarFlags = 1
    e.u80, e.u82 = math.floor(e.x), math.floor(e.y)
    wispHeading(E, e)
    setAnim(E, e, band(e.spawnB or 0, 0xFF))
  elseif a == 1 then -- sub_080336A8
    e.timer = band((e.timer or 1) - 1, 0xFF)
    if e.timer == 0 then wispHeading(E, e)
    elseif e.colX or e.colY then bounce(e) end
    pm0(E, e, e.direction, e.speed)
    step(e)
    if not e.noTouchW and canTouch(f, e) and (f.player.invuln or 0) == 0 and touches(f, e) then
      -- sub_08017D28: Link pushed back $280 for 12 frames, iframes 16
      local p = f.player
      knockLink(f, e.x, e.y, 0x280 / 16, 12)
      p.invuln = math.max(p.invuln or 0, 16)
      M.wispCollision(E, e, 0x80)
    end
  elseif a == 2 then -- sub_080336DC
    e.u7c = band((e.u7c or 1) - 1, 0xFFFF)
    if e.u7c == 0x24 then e.x, e.y = e.u80, e.u82
    elseif e.u7c == 0x18 then fx(f, e.x, e.y, FX_DEATH)
    elseif e.u7c == 0x0C then e.hidden = false
    elseif e.u7c == 0 then
      e.action, e.noHit, e.noTouchW = 1, nil, nil
      wispHeading(E, e)
    end
  end
end

-- ===========================================================================
-- DOOR_MIMIC
-- ===========================================================================
local function tileOffset(f, t2)
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "doorTileOffsets")
  if not T then return nil end
  return T.s16(0x080B4488 + 2 * t2)
end
M.tileOffset = tileOffset

local function mimicDoor(E, e) -- sub_080221C0
  local f = E.field
  local off = tileOffset(f, e.type2)
  if not off then return end
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  local pos = tx + ty * 64 + off
  local px, py = pos % 64, math.floor(pos / 64)
  local r = f.room
  local name = (e.layer == 2) and "top" or "bottom"
  if not (r and r.maps and r.maps[name]) or px < 0 or py < 0 or px >= r.tw or py >= r.th then return end
  e.u7e = { px, py }
  e.u7c = r.maps[name][py * r.tw + px] -- GetTileIndex
  r:setTile(e.layer == 2 and 2 or 1, px, py, M.DM_TILE[e.type2])
end

function M.mimicDeath(E, e) -- DoorMimic_OnDeath
  local f = E.field
  if e.u7e and e.u7c then f.room:setTile(e.layer == 2 and 2 or 1, e.u7e[1], e.u7e[2], e.u7c) end
  fx(f, e.x, e.y, FX_POT_SHATTER)
  e.deleted = true -- EnemyDisableRespawn, DeleteThisEntity (no drop)
end
function M.mimicHit(E, e, hurtType, fromX, fromY, extra)
  if e.r26inHit then return nil end
  e.r26inHit = true
  local ok, r = pcall(E.hit, E, e, hurtType, fromX, fromY, extra)
  e.r26inHit = nil
  if not ok then error(r, 0) end
  if e.dying or (e.health or 1) <= 0 then M.mimicDeath(E, e) end
  return r
end

function M.doorMimic(E, e)
  local f = E.field
  e.r26hit = M.mimicHit
  e.noTouch = true -- matrix handler 5 (sub_08017EB0): below
  local a = e.action
  if a == 0 then -- sub_08022034
    e.action = 1
    e.type2 = band(e.form or 0, 3)
    e.spritePriority = 5
    e.damage = 0
    local pt = M.DM_POINT[e.type2]
    e.u78, e.u7a = pt[1] + math.floor(e.x), pt[2] + math.floor(e.y)
    setAnim(E, e, e.type2)
    mimicDoor(E, e)
    e.timer = 0
  elseif a == 1 then -- sub_0802209C
    if (e.timer or 0) == 0 then
      local p = f.player
      local dx, dy = math.floor(p.x) - e.u78, math.floor(p.y) - e.u7a
      if dx >= 0 and dx < 0x10 and dy >= 0 and dy < 0x10 then
        e.action, e.timer = 2, 18
        setAnim(E, e, e.type2 + 4)
      end
    else e.timer = e.timer - 1 end
  elseif a == 2 then -- sub_080220D8
    e.timer = e.timer - 1
    if e.timer <= 0 then e.action = 3 end
  elseif a == 3 then -- sub_080220F0
    step(e)
    if done(e) then
      e.action, e.timer, e.damage = 4, 120, 0
      for _, o in ipairs(M.DM_DUST[e.type2]) do fx(f, math.floor(e.x) + o[1], math.floor(e.y) + o[2], FX_DASH) end
      f:sound(SFX_PLACE_OBJ)
    elseif band(fl(e), 1) ~= 0 then e.damage = 4 end
  elseif a == 4 then -- sub_08022174
    require("src.zelda.tmc.Hitboxes").pushOut(f, e, e.hitbox)
    e.timer = e.timer - 1
    if e.timer <= 0 then e.action = 5; setAnim(E, e, e.type2 + 8) end
  elseif a == 5 then -- sub_08022198
    require("src.zelda.tmc.Hitboxes").pushOut(f, e, e.hitbox)
    step(e)
    if done(e) then e.action, e.timer = 1, 90 end
  end
  -- DoorMimic: hitbox = gUnk_080CB8A4[type2][frameIndex]
  local tab = M.DM_BOX[e.type2 or 0]
  local fi = e.anim and e.anim.frame
  if tab and fi and tab[fi] then e.hitbox = tab[fi] end
  -- sub_08017EB0: only while damage != 0; Link takes 8, 12 frames at $180, iframes 16
  if (e.damage or 0) ~= 0 and canTouch(f, e) and (f.player.invuln or 0) == 0 and touches(f, e) then
    local p = f.player
    if p:hurt(8, e.x, e.y) then
      p.invuln, p.timer = 16, 12
      local dx, dy = p.x - e.x, p.y - e.y
      local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.kbx, p.kby = dx / d * 1.5, dy / d * 1.5
    end
  end
end

-- ===========================================================================
-- ENEMY_50
-- ===========================================================================
local function e50Face(E, e) -- sub_0803F66C
  local d = e.direction or 0
  if band(d, 0xF) ~= 0 or e.animationState == 0xFF then
    local s = rshift(d, 4)
    if s ~= e.animationState then e.animationState = s; setAnim(E, e, s + 1) end
  end
end
local function e50Wander(E, e) -- sub_08041128 -> action 4, sub_0803F528
  local f = E.field
  e.action = 4
  local r = R(f)
  e.timer = band(r, 8) + 8
  if selfHome(e) then e.direction = band((e.direction or 0) + M.GHINI_TURN[band(r, 7)], 0x1E)
  else e.direction = band(homeDir(e), 0x1E) end
  e.spd = M.GHINI_SPEED[band(rshift(r, 4), 3)]
  e.hitType = 0x24
  e.noTouch = nil
  e50Face(E, e)
end
local function e50Chase(E, e) -- sub_08041134
  local f = E.field
  e.action, e.hitType = 5, 0x25
  e.noTouch = true -- hit type $25 against Link is the capture (handler 7), done here
  e.u78 = M.E50_DELAY[band(R(f), 3)] + ((f.playerClones and #f.playerClones > 0) and 0x3C or 0)
end
local function lit(f) return (f.lightLevel or 0x100) > 0xF end
local function lantern(f, e) -- sub_0806FD54
  local p = f.player
  if not p.lanternLit then return false end
  local dx, dy = math.floor(e.x) - math.floor(p.x), math.floor(e.y) - (math.floor(p.y) - 9)
  return dx * dx + dy * dy <= 0x48 * 0x48
end
local function rectNear(e, t, rx, ry) return math.abs(math.floor(t.x) - math.floor(e.x)) <= rx and math.abs(math.floor(t.y) - math.floor(e.y)) <= ry end
local function e50Notice(E, e) -- sub_08041170
  local f = E.field
  if (e.u7c or 0) ~= 0 then e.u7c = e.u7c - 1 return false end
  local t = target(f)
  if linkHome(f, e) and (lantern(f, e) or (lit(f) and t and rectNear(e, t, 0x70, 0x48))) then
    e50Chase(E, e)
    return true
  end
  return false
end
local function e50Sees(E, e) -- sub_0803F5A8
  local f = E.field
  if not linkHome(f, e) then return false end
  if not lit(f) then return lantern(f, e) end
  return true
end
local function e50Rise(E, e) e.action, e.hidden = 3, false; setAnim(E, e, 0) end -- sub_080411CC
local function e50Wakes(E, e) -- sub_080411E8
  local f = E.field
  if not linkHome(f, e) then return false end
  local t2 = band(e.spawnB or 0, 0xFF)
  if t2 == 1 then return f.player.lanternLit == true end
  if t2 == 2 then return lit(f) end
  return true
end
local function propPoints(f, k) -- GetCurrentRoomProperty(k): four (x, y) s16 pairs
  local props = f.room and f.room.maps and f.room.maps.header and f.room.maps.header.props
  local addr = props and props[k]
  if not addr then return nil end
  local rd = require("src.zelda.tmc.CoFObjects")._rd
  local pts = {}
  for i = 0, 7 do
    local v = rd.u16(f, addr + 2 * i)
    if not v then return nil end
    pts[i] = v >= 0x8000 and v - 0x10000 or v
  end
  return pts
end
M.propPoints = propPoints
local function e50Split(E, e) -- sub_0804122C
  local f = E.field
  local pts = e.points
  local r = R(f)
  local b, ia = band(r, 6), band(rshift(r, 8), 3)
  for _ = 1, 3 do
    if pts then
      local c = E:spawn({ kind = 3, id = M.ENEMY_50, paramA = 1, paramB = 0, paramC = 0, x = pts[b], y = pts[b + 1], pool = 0 })
      if c then
        c.parent, c.u80 = e, ia
        c.homeX, c.homeY, c.rangeW, c.rangeH = e.homeX, e.homeY, e.rangeW, e.rangeH
        c.layer = e.layer
        f.entities[#f.entities + 1] = c
        e.clones = e.clones or {}
        e.clones[#e.clones + 1] = c
      end
    end
    b, ia = band(b + 2, 6), band(ia + 1, 3)
  end
  if pts then e.x, e.y = pts[b], pts[b + 1] end
end

-- Link caught (sub_08017F40 / sub_0803F738) and let go (sub_0803F6EC)
local function e50Hold(E, e)
  local f = E.field
  local p = f.player
  if p.e50 ~= e then
    p.e50 = e
    p.state = "ext"
    p.extUpdate = function(pp, input)
      for _, k in ipairs({ "a", "b", "r", "l", "up", "down", "left", "right" }) do
        if input.pressed and input.pressed(k) then f.e50Press = true end
      end
      if pp.anim then pp.anim:update(1) end
    end
  end
  e.x, e.y = p.x, p.y + 1 -- sub_0806FA90(Link, ghost, 0, 1)
  e.spriteOY = -2
end
local function e50Release(E, e)
  local f = E.field
  local p = f.player
  e.spriteOY = nil
  if p.e50 ~= e then return end
  p.e50 = nil
  if p.state == "ext" then p.state, p.extUpdate = "normal", nil end
  if (f.save.stats.health or 0) > 0 then
    p.z, p.zv, p.jumping = 2, 1.5, true
    p.invuln = math.max(p.invuln or 0, 60)
  end
end
M.e50Release = e50Release

function M.e50Collision(E, e, cf) -- Enemy50_OnCollision
  local f = E.field
  if e.action == 8 or e.action == 9 then
    e.animationState = 0xFF
    setAnim(E, e, bxor(rshift(e.kbDir or 0, 4), 1) + 1)
    e50Chase(E, e)
    e50Release(E, e)
  end
  if e.hitType == 0x25 and cf == 0x80 then
    e.action = 8
    setAnim(E, e, 3)
  else
    if cf == 0x80 then e.u7c = 0x78; e50Wander(E, e) end
    if cf == 0x80 + 0x1D then e.zv = 1.5 end
    if e.health ~= e.u7a then
      if (e.form or 0) == 0 then
        e.animationState = rshift(e.kbDir or 0, 4)
        setAnim(E, e, e.animationState + 7)
      else
        e.health, e.action, e.timer = 0xFF, 10, 60
      end
      e.u7a = e.health
    end
  end
end
function M.e50Hit(E, e, hurtType, fromX, fromY)
  e.kbDir = dirTo(fromX or e.x, fromY or e.y + 1, e.x, e.y)
  local h = handler(E, e.hitType, hurtType)
  if h == 1 or h == 2 then return false end
  return nil
end

function M.enemy50(E, e)
  local f = E.field
  e.onCollision, e.r26hit = M.e50Collision, M.e50Hit
  if (e.form or 0) == 1 and e.parent and (e.parent.deleted or e.parent.dying) then
    if e.action == 8 or e.action == 9 then e50Release(E, e) end
    fx(f, e.x, e.y, FX_DEATH)
    e.deleted = true
    return
  end
  local a = e.action
  if a == 0 then -- Enemy50_Init
    local r = R(f)
    e.direction = band(r, 0x1E)
    e.animationState = 0xFF
    e.gustJarFlags = 1
    e.u7a, e.u7b, e.u7c = e.health, band(rshift(r, 4), 0xFF), 0
    e.u80 = e.u80 or 0
    if (e.form or 0) == 0 then
      e.action, e.hidden, e.noTouch, e.noHit = 1, true, true, true
      e.points = propPoints(f, band(rshift(e.spawnB or 0, 8), 0xFF))
    else e50Rise(E, e); e.noTouch, e.noHit = true, true end
  elseif a == 1 then
    if e50Wakes(E, e) then e.action, e.timer = 2, 15 end
  elseif a == 2 then
    e.timer = e.timer - 1
    if e.timer <= 0 then e50Rise(E, e); e50Split(E, e) end
  elseif a == 3 then
    step(e)
    if done(e) then
      e.noTouch, e.noHit, e.collideOn = nil, nil, true -- flags |= ENT_COLLIDE
      e.u7c = (e.u80 or 0) * (band(R(f), 0x30) + 0x3C) + 0x78
      e50Wander(E, e)
    end
  elseif a == 4 then
    if not e50Notice(E, e) then
      local y0 = e.y
      linear(e, e.direction, e.spd) -- sub_0803F58C: half the vertical speed
      e.y = e.y - (e.y - y0) / 2
      step(e)
      e.timer = e.timer - 1
      if e.timer <= 0 then e50Wander(E, e) end
    end
  elseif a == 5 then
    step(e)
    local t = target(f)
    if t then
      e.direction = facing(e, t)
      e50Face(E, e)
      e.u78 = e.u78 - 1
      if e.u78 <= 0 then
        local r = R(f)
        e.action, e.timer, e.spd = 6, band(r, 0xE0), 0x100
        e.u7e = band(rshift(r, 8), 0x78) + 0x3C
      end
    else e50Wander(E, e) end
  elseif a == 6 then
    step(e)
    if not e50Sees(E, e) then e50Wander(E, e)
    else
      local t = target(f)
      e.u7e = (e.u7e or 1) - 1
      if t and e.u7e ~= 0 then
        e.timer = band((e.timer or 0) + 1, 0xFF)
        if band(e.timer, M.E50_TURN_MASK[rshift(e.timer, 6)]) == 0 then turnStep(e, facing(e, t)) end
        e50Face(E, e)
        linear(e, e.direction, e.spd)
      else e.action, e.timer = 7, 30 end
    end
  elseif a == 7 then
    step(e)
    e.timer = e.timer - 1
    if e.timer <= 0 then e.u7c = band(R(f), 0xF8) + 0xB4; e50Wander(E, e) end
  elseif a == 8 then
    e50Hold(E, e)
    step(e)
    if done(e) then e.action, e.u78 = 9, 0; setAnim(E, e, 4) end
  elseif a == 9 then
    step(e)
    if band(fl(e), 1) ~= 0 then -- sub_0803F6C0
      take(e, 1)
      local p = f.player
      f:modStat("health", -4)
      p.invuln = 0xC
      f:sound(SFX_PLY_VO6)
    end
    if f.e50Press then f.e50Press = nil; e.u78 = e.u78 + 8 end
    if (f.save.stats.health or 0) <= 0 then e.u78 = 0xE0 end
    e.u78 = e.u78 + 1
    if e.u78 >= 0xE0 then
      e.u7c, e.animationState = 0x78, 0xFF
      e.iframes = math.max(e.iframes or 0, 12)
      E:knock(e, f.player.x, f.player.y, 0x180 / 16, 0x14)
      e50Wander(E, e)
      e50Release(E, e)
    else e50Hold(E, e) end
  elseif a == 10 then
    step(e)
    e.timer = e.timer - 1
    if e.timer <= 0 then e50Wander(E, e) end
  end
  -- hit type $25 against Link's body: caught (sub_08017F40)
  if e.hitType == 0x25 and (e.action == 5 or e.action == 6 or e.action == 7) and canTouch(f, e) then
    local p = f.player
    if (p.invuln or 0) == 0 and not p.minish and not p.swimming and p.state == "normal" and touches(f, e) then
      e.iframes = math.max(e.iframes or 0, 8)
      M.e50Collision(E, e, 0x80)
      e50Hold(E, e)
    end
  end
end

-- ===========================================================================
function M.update(E, e)
  if e.id == M.SLASH_ID then return M.slash(E, e) end
  if e.id == M.DARK_NUT then return M.darkNut(E, e) end
  if e.id == M.WISP then return M.wisp(E, e) end
  if e.id == M.DOOR_MIMIC then return M.doorMimic(E, e) end
  if e.id == M.ENEMY_50 then return M.enemy50(E, e) end
end

return M
