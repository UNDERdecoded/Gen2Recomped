-- Round 26 (team A): overworld enemies, part 2, from the decomp's own code.
-- EnemyField.lua dispatches here (handles / update).
--
-- COMMON (as the other ports): Random() is the cartridge's (Drops.random on
--   the shared seed); directions 0-31 (0 north, clockwise); DirectionRound
--   (d & $18), DirectionRoundUp ((d + 4) & $18); sub_08049DF4(1) is the
--   enemy target (EnemyDeepwood.target); sub_08049F84 its facing direction
--   or $FF; sub_08049FA0 = the enemy in its home rectangle, sub_08049FDC =
--   the target in it, sub_08049EE4 = toward its middle; sub_0806FC80 =
--   within n px (CalcDistance); EntityInRectRadius(a, b, rx, ry) = |dx| <= rx
--   and |dy| <= ry; CheckOnScreen = x - scroll + $3F < $16E, y - scroll +
--   z + $3F < $11E; ProcessMovement0/2/3 move with the port's box test
--   (EnemyDeepwood.move0), its blocked axes kept as the next frame's
--   `collisions`; LinearMoveUpdate moves without collision.  Projectiles
--   and the Spear Moblin's spear are entities made here (enemy = true,
--   f2 = their kind, noHit, noTouch): their contact with Link is done here
--   (linkContact: Link's ROM hitbox, gCollisionMtx damage, the shield),
--   like Enemies:update's own.  Drawing off (spriteSettings.draw 0) with the
--   collision still on is staticFrame $FF.
--
-- SPEAR_MOBLIN ($15, src/enemy/spearMoblin.c)
--   sub_08028314 (Init): unk_82 1; timer (EntityData) set -> animation
--     state type2 << 1, 30 frames at $80 that way; else state $10 and
--     sub_08028604; a MOBLIN_SPEAR child.
--   1 sub_08028378 (walk): unk_81 counts down; timer out: 16 walks ->
--     sub_08028728 (look around, unk_82 2) else sub_08028604 (a new walk);
--     else sub_080286CC (sees Link) sets unk_7b bit 1, and running into a
--     wall on the facing side (gUnk_080CC7D8) bounces (sub_0800417E),
--     unk_83++; after 12 frames a sighting -> sub_08028754.
--   2 sub_08028420 (look around): timer -> action 3 (unk_82 0); sighting
--     after 12 frames -> sub_08028754.
--   3 sub_08028488 (stand, 32 frames; 64 after a hit while charging): unk_82
--     3 -> action 4 (charge: $180 at Link, SFX_EM_MOBLIN_SPEAR); 2 ->
--     action 2 ((R & 7) * 3 + 64); 4 -> turned round, then 1/default ->
--     action 1 ((R & 7) * 3 + $22 at $80).
--   4 sub_08028528 (charge): no target -> sub_08028728; every $20 frames
--     re-aim when within sub_08028828's window; every 8 frames SFX_F0 and
--     a dust FX_DEATH; moves after $20 frames; $80 frames or Link's body ->
--     sub_08028784 (stand, then turn round).
--   sub_08028604 (gUnk_080CC7BC walk times, gUnk_080CC7D0 turns in its home,
--     gUnk_080CC7C0 offsets homeward), sub_080286CC (Link within $30 while
--     looking around, or within $40 in the facing quarter), sub_080287E0
--     (animation (state >> 1) + 0 / 4 / 8 / $C by unk_82).
--   OnCollision: any contact (CONTACT_NOW) -> sub_08028754 (face Link,
--     then charge); while charging, Link's body -> sub_08028784.
--   MOBLIN_SPEAR (projectile/moblinSpear.c): follows its moblin
--     (CopyPosition); its hitbox each frame from gUnk_0812966C[frame]
--     (x mirrored by the frame's flip), hit type $8B (gProjectileDefinitions
--     [3]); a hit on the spear knocks the moblin back (iframes $10, $C
--     frames at $180) and is the moblin's contact too.
--   SIMPLIFIED: the per-facing body hitbox gUnk_080CC944 is binary-only in
--     the decomp (spearMoblin/*.bin): the definition's hitbox is kept;
--     GenericConfused / the spear's confusion off-switch are not ported.
-- BOW_MOBLIN ($46, src/enemy/bowMoblin.c)
--   the same walk / look / stand machine (sub_0803C1E0 .. sub_0803C344,
--     gUnk_080CFFA4 walk times, gUnk_080CFFAC offsets, gUnk_080CFFBC wall
--     sides); every 16th walk 1 in 2 (R & $10) a shot without seeing Link
--     (sub_0803C624, unk_82 5); action 4 sub_0803C400: frame 1 an
--     ARROW_PROJECTILE (type state >> 1, direction (dir + 4) & $18) held at
--     gUnk_080CFFC4; frame 24 -> released (subtimer 32); then up to 3 more
--     shots (R & $C0) while it saw Link, else sub_0803C634 (turn round).
--     OnCollision: -> sub_0803C5F0 and the nocked arrow is dropped.
--   ARROW_PROJECTILE (projectile/arrowProjectile.c): Init 106 frames,
--     gUnk_081299F8 (flips, animation, hitbox gUnk_08129A18 / A20); 1 held
--     until its moblin's subtimer, then 2 (collision on, SFX_FC): flies at
--     $300 (ProcessMovement3); a wall -> 3 (stuck 32 frames, animation + 2,
--     SFX_18A); Link's body -> deleted (the matrix damage, hit type $1A);
--     any other contact (the shield) -> ModHealth(-2) and sub_080A9488 (4:
--     knocked off spinning, zVelocity 1.5, GravityUpdate($2800), SFX_METAL_
--     CLINK, then CreateDeathFx).
-- TAKKURI ($45, src/enemy/takkuri.c)
--   Init: facing Link; 1 perches (every 8 frames re-aim, sub_0803BEE8);
--     Link within $88 x $50 and more than 8 px below -> 2: sub_0803BF70
--     (rise 8 px in 16 frames, collision on, 24 frames, then the swoop at
--     $1C0 turning one step toward him every 8 frames until it heads up
--     again (unk_82), then 3: off at $180 (mirrored up); off screen -> 4:
--     8 frames, then Link and itself in the home rectangle -> it comes back
--     across the screen top (x scroll - $20 / + $110, y scroll + 8, $1C0,
--     unk_82 $12C), else sub_0803C120 (5: back on its perch, hidden, waits
--     to be off screen, then 1 again).
--   OnCollision: Link's body -> StealRupees (>= 500: -100 and 5 RUPEE20;
--     >= 100: -25 and 5 RUPEE5; else up to 5 RUPEE1, each a RUPEE_OBJECT:
--     zVelocity 2.5, direction (R >> 16) & $1F, speed R & 480), collision
--     off, it bounces away (0x20 - direction, nudged off the vertical);
--     any other contact kills it (health 0); unk_82 -= $C when >= $11.
--   SIMPLIFIED: the shield's contact uses the port's block (no kill: the
--     matrix entry is not known); OnGrabbed (the Gust Jar) is the port's
--     generic grab; spriteOrientation / collisionLayer 3 are not modelled.
-- LAKITU ($47, src/enemy/lakitu.c) + its cloud (LAKITU_CLOUD_PROJECTILE $11)
--   Init: the cloud child (follows it 1 px up, z -2), z -2, home (unk_74/
--     76) to drift back to (sub_0803CAD0, ProcessMovement2) every frame.
--   1 HIDDEN: faces Link (sub_0803CA84); Link not within $28 but within
--     $70 x $50 (sub_0803CA4C) -> 2 END_HIDE (drawn, animation); done ->
--     3 IDLE (60 frames, hit type $42, animation + 4).  IDLE: timer out ->
--     sub_0803CB34 (5: hit type $A6, the throw direction, animation + 8,
--     the cloud + 4); Link too near / far -> 4 BEGIN_HIDE (hit type $43,
--     animation + $C) -> hidden.  5: done -> Lakitu_SpawnLightning
--     (gUnk_080D0154 offset, SFX_193), 6 with 15 frames (1 in 2, once: a
--     second bolt) or 30 frames -> IDLE (180 frames).
--   OnCollision: the Cane ($1D) -> zVelocity 2.0 and sub_0803CBAC (7
--     CLOUDLESS: hit type $42, the cloud collides with hit type $43,
--     animation + $10; GravityUpdate($1800), landed animation + $14;
--     falling back into its cloud within 6 px (sub_0803CC08) pops it with
--     four FX_DEATH); hit type $43 -> a puff (FX_DEATH).  OnGrabbed
--     subaction 2 (sub_0803C86C) -> cloudless, the cloud gone.
--   LAKITU_LIGHTNING ($12, projectile/lakituLightning.c): 180 frames at $80
--     (ProcessMovement3); a wall or the time -> FX_BLUE_EFC; off the room
--     -> gone; Link's body -> gone (the matrix damage, hit type $A4).
-- LAKITU_CLOUD ($48, src/enemy/lakituCloud.c): rides room property [type]
--   (UpdateRailMovement, CoFObjects.railNext), z -2, animation direction /
--   8 + 4; knockback ignored (OnKnockback).  Pulled into the Gust Jar
--   (sub_0803CD40): ModHealth(-2), SFX_PLY_VO6, then sub_0803CE3C (FX_DEATH,
--   back to its start blinking 60 frames, the rail restarted).
--   SIMPLIFIED: the pull itself is skipped (onJarPull swallows it at once);
--   sub_08079D84 (Link's hurt reaction) is not ported.
-- CLOUD_PIRANHA ($3F, src/enemy/cloudPiranha.c)
--   Init: direction R & $1C (8-way), turn sense R & 1, hit type $72.  1:
--     every 32 frames a 45 degree turn in its home (homeward outside);
--     Link within $80 -> 2 (16-frame legs at $40 facing him); within $60 ->
--     3 (speeds up by $40 every 10 frames to $200, then down by $50); within
--     $14 or slowed to $100 -> sub_08038754 (4: jumps, zVelocity 2.0, hit
--     type $5A, speed $C0, palette $71, SFX_12B, animation 8 / 9 + side);
--     landed (BounceUpdate($1800) INIT_NEXT) -> 1 (palette $70, SFX_124,
--     128 frames before chasing).  sub_080387F0: cloud-edge collision data
--     ($0F / $2A) under it -> $20 frames of free flight, ahead
--     (gUnk_080CF520) -> turn round; a wall -> bounce.
--   OnCollision (hit type $5A): $14 -> action 5 (jump again); $15 / $0E ->
--     health 0; the Cane ($1D) otherwise -> sub_08038754.
-- ARMOS ($2A, src/enemy/armos.c)
--   Init (sub_0803026C): unk_80 = timer (its slot), the bit (0x47D >> slot)
--     & 1 (armos_data's saved place / bit only survive the Minish entrance's
--     transition, not ported); SPECIAL_TILE_34 under it (sub_080307EC);
--     slot 2 below origin + $80 -> action 7.  1: type 0 wakes on Link's
--     contact, other types when Link is in its home within 16 px across
--     (slot 2: left of origin + $A8), only with the bit set.  2 (waking):
--     frame flag 1 shakes (gUnk_080CE160), flag 2: hit type 8, hitbox
--     gUnk_080FD2F0, the tile back, SFX_12A; done -> 3 (600 frames of
--     hunting) / slot 2: 6 (jumps south 26 frames at $300).  3:
--     sub_080306C4 (every 24 frames toward Link (sub_0800132C), the other
--     axis 1 in 8 / after three straight, a wall ahead (gUnk_080CE164) ->
--     the other axis), speed by health (sub_080309E8); out of the home or
--     the hunt over -> 4 ($A0, 120 frames, back to a tile's centre:
--     sub_080305BC) -> 5 (statue again: hit type 1, gHitbox_15, the tile)
--     -> 1.  Hurt -> 8 (animation 6) -> 3.  Frame $25 shows $19 when the
--     bit is set.
--   SIMPLIFIED / NOT PORTED: the Minish entrance under a type2 Armos
--     (sub_0803086C, DoExitTransition) and sub_080300E8's placement of Link
--     after it; the contact iframes -$1E.
-- BOMB_PEAHAT ($1B): NOT PORTED (keeps the generic model).
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = {}
M.SPEAR_MOBLIN, M.BOW_MOBLIN, M.TAKKURI, M.LAKITU, M.LAKITU_CLOUD = 0x15, 0x46, 0x45, 0x47, 0x48
M.CLOUD_PIRANHA, M.ARMOS = 0x3F, 0x2A
local HANDLED = { [0x15] = true, [0x46] = true, [0x45] = true, [0x47] = true, [0x48] = true, [0x3F] = true, [0x2A] = true }

-- projectile ids (include/projectile.h)
local P_MOBLIN_SPEAR, P_ARROW, P_LAKITU_CLOUD, P_LAKITU_LIGHTNING = 0x03, 0x0D, 0x11, 0x12
-- sounds / effects
local SFX_F0, SFX_FC, SFX_101, SFX_124, SFX_12A, SFX_12B = 0xF0, 0xFC, 0x101, 0x124, 0x12A, 0x12B
local SFX_18A, SFX_193, SFX_METAL_CLINK, SFX_PLY_VO6, SFX_MOBLIN_SPEAR = 0x18A, 0x193, 0x74, 0x7A, 0x11E
local SFX_SHIELD = 0x118
local SPECIAL_FX, FX_DEATH, FX_STARS, FX_BLUE_EFC = 0x0F, 0x02, 0x1C, 0x50
local SPECIAL_TILE_34 = 0x4022
local ITEM_RUPEE1, ITEM_RUPEE5, ITEM_RUPEE20 = 0x54, 0x55, 0x56

-- tables from the decomp's C sources
local SM_WALK = { [0] = 0x30, 0x60, 0x6C, 0x91 }                                      -- gUnk_080CC7BC
local SM_HOME = { [0] = -8, 12, -12, 8, 4, -6, 6, -4, 0, -3, 1, 3, -1, 2, 0, -2 }     -- gUnk_080CC7C0
local SM_TURN = { [0] = 8, 16, 8, 0, 16, 8, 16, 0 }                                   -- gUnk_080CC7D0
local SPEAR_HB = {                                                                    -- gUnk_0812966C
  { 6, 11, 2, 4 }, { -12, 2, 3, 3 }, { -13, -15, 1, 2 }, { 5, 12, 1, 3 }, { 7, 10, 1, 2 },
  { 8, 9, 1, 3 }, { 7, 10, 1, 2 }, { -22, 1, 4, 2 }, { -12, 1, 3, 2 }, { -6, 2, 4, 2 },
  { -12, 1, 3, 2 }, { -1, -19, 1, 1 }, { -4, -19, 1, 1 }, { -4, -20, 1, 1 }, { -4, -19, 1, 1 },
  { 6, 9, 1, 2 }, { 6, 10, 1, 2 }, { 6, 9, 1, 2 }, { 6, 10, 1, 2 }, { -29, -11, 3, 2 },
  { -29, -9, 3, 2 }, { -29, -11, 3, 2 }, { -29, -9, 3, 2 }, { -5, -25, 1, 2 }, { -5, -24, 1, 2 },
  { -5, -25, 1, 2 }, { -5, -24, 1, 2 }, { 7, 12, 1, 2 }, { 7, 11, 1, 2 }, { -12, 3, 3, 1 },
  { -12, 2, 3, 1 }, { -13, -16, 1, 2 }, { -13, -15, 1, 2 },
}
local BM_WALK = { [0] = 24, 32, 48, 64, 96, 108, 120, 145 }                           -- gUnk_080CFFA4
local BM_HOME = SM_HOME                                                               -- gUnk_080CFFAC (the same bytes)
local BM_ARROW = { [0] = -5, -20, 15, -12, 4, -4, -15, -12 }                          -- gUnk_080CFFC4
local ARROW = { [0] = { fx = false, fy = false, anim = 1, hb = { x = 0, y = 0, w = 4, h = 6 } }, -- gUnk_081299F8
                { fx = true, fy = false, anim = 0, hb = { x = 0, y = 0, w = 6, h = 4 } },
                { fx = false, fy = true, anim = 1, hb = { x = 0, y = 0, w = 4, h = 6 } },
                { fx = false, fy = false, anim = 0, hb = { x = 0, y = 0, w = 6, h = 4 } } }
local LK_BOLT = { [0] = { 0, -18 }, { 18, 0 }, { 0, 8 }, { -18, 0 } }                 -- gUnk_080D0154
local CP_AHEAD = { [0] = 0, -12, 8, -8, 12, 0, 8, 8, 0, 12, -8, 8, -12, 0, -8, -8 }  -- gUnk_080CF520 (s8)
local AR_SHAKE = { [0] = -1, 0, 1, 0 }                                                -- gUnk_080CE160
local AR_AHEAD = { [0] = 0, -7, 7, 0, 0, 7, -7, 0 }                                   -- gUnk_080CE164
M.SM_WALK, M.SM_HOME, M.SM_TURN, M.SPEAR_HB = SM_WALK, SM_HOME, SM_TURN, SPEAR_HB
M.BM_WALK, M.BM_ARROW, M.ARROW, M.LK_BOLT, M.CP_AHEAD = BM_WALK, BM_ARROW, ARROW, LK_BOLT, CP_AHEAD
M.AR_SHAKE, M.AR_AHEAD = AR_SHAKE, AR_AHEAD

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function R(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end
local function u8(v) return band(v, 0xFF) end
local function round(d) return band(d, 0x18) end            -- DirectionRound
local function roundUp(d) return band(d + 4, 0x18) end      -- DirectionRoundUp
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i); e.flagKey = nil end
local function fflags(e)
  if e.flagKey == e.anim.key then return band(e.anim.flags or 0, 0x80) end
  return e.anim.flags or 0
end
local function take(e) e.flagKey = e.anim.key end -- super->frame = 0 (the keyframe's flags consumed)
local function done(e) return band(fflags(e), 0x80) ~= 0 or e.anim.done == true end
local function frame(e) e.anim:update(1) end      -- GetNextFrame
local function draw(e, on) e.staticFrame = (not on) and 0xFF or nil end -- spriteSettings.draw
local function syncZ(e) e.z = -(e.cz or 0) / 65536 end
local function target(f) return DW().target(f) end
local function dirTo(ax, ay, bx, by) return DW().dirTo(ax, ay, bx, by) end
local function facing(E, e) -- sub_08049F84(e, 1)
  local t = target(E.field)
  if not t then return 0xFF end
  return dirTo(e.x, e.y, t.x, t.y)
end
local function selfHome(e) -- sub_08049FA0
  local dx, dy = math.floor(e.x) - e.homeX, math.floor(e.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH
end
local function targetHome(E, e) -- sub_08049FDC(e, 1)
  local t = target(E.field)
  if not t then return nil end
  local dx, dy = math.floor(t.x) - e.homeX, math.floor(t.y) - e.homeY
  return (dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH) and t or nil
end
local function homeDir(e) return dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) end -- sub_08049EE4
local function within(e, x, y, d) -- EntityWithinDistance / sub_0806FC80
  local dx, dy = math.floor(e.x) - math.floor(x), math.floor(e.y) - math.floor(y)
  return dx * dx + dy * dy <= d * d
end
local function inRect(e, o, rx, ry) -- EntityInRectRadius
  local dx, dy = math.floor(e.x) - math.floor(o.x), math.floor(e.y) - math.floor(o.y)
  return dx >= -rx and dx <= rx and dy >= -ry and dy <= ry
end
local function onScreen(E, e) -- CheckOnScreen
  local f = E.field
  local x = math.floor(e.x) - math.floor(f.camX or 0) + 0x3F
  local y = math.floor(e.y) - math.floor(f.camY or 0) - math.floor(e.z or 0) + 0x3F
  return x >= 0 and x < 0x16E and y >= 0 and y < 0x11E
end
-- ProcessMovement0/2/3: the blocked axes become `collisions`
local function move0(E, e, dir, spd)
  if not dir or band(dir, 0x80) ~= 0 or (spd or 0) == 0 then e.colX, e.colY = false, false return end
  local hx, hy = DW().move0(E, e, band(dir, 0x1F), spd)
  e.colX, e.colY = hx or false, hy or false
end
local function linear(e, dir, spd) -- LinearMoveUpdate
  if not dir or band(dir, 0x80) ~= 0 then return end
  local a = band(dir, 0x1F) / 32 * 2 * math.pi
  local s = (spd or 0) / 256
  e.x, e.y = e.x + math.sin(a) * s, e.y - math.cos(a) * s
end
local function bounceDir(e) -- sub_0800417E(e, collisions)
  local d = e.dir
  if e.colX then d = 0x20 - d end
  if e.colY then d = 0x10 - d end
  e.dir = band(d, 0x1F)
end
local function turnStep(e, want) -- sub_08004596
  if not want or band(want, 0x80) ~= 0 then return end
  local d = band(want - e.dir, 0x1F)
  if d == 0 then return end
  e.dir = band(e.dir + (d < 16 and 1 or -1), 0x1F)
end
-- GravityUpdate (16.16 z, negative up): true while airborne
local function gravity(e, g)
  local z = (e.cz or 0) - (e.czv or 0)
  if z < 0 then e.cz = z; e.czv = (e.czv or 0) - g; syncZ(e) return true end
  e.cz, e.czv = 0, 0; syncZ(e)
  return false
end
local function bounce(e, g) local r = require("src.zelda.tmc.EnemyCrenel").bounce(e, g); syncZ(e) return r end
local function fx(E, x, y, t) if E.field.addFx then E.field:addFx(x, y, SPECIAL_FX, t) end end
local function sound(E, id) if E.field.sound then E.field:sound(id) end end
local function setPalette(E, e, pal) -- ChangeObjPalette
  if e.palId == pal then return end
  e.palId = pal
  e.baseDef = e.baseDef or e.def
  if E.A and E.A.objPalette then e.palette = E.A:objPalette(pal, E.field.room.atlas and E.field.room.atlas.palettes) end
  e.def = setmetatable({ palette = pal }, { __index = e.baseDef })
end
-- COLLISION_ON / OFF.  The children (f2) always do their own contact and
-- never take the sword (except the spear, which forwards it to its moblin).
local function collide(e, on)
  e.collideF, e.collideOn = on, on or nil
  if e.f2 then e.noTouch = true; e.noHit = (e.f2 ~= "spear") or nil
  else e.noTouch = (not on) or nil; e.noHit = (not on) or nil end
end

-- Link's contact with an entity box (Enemies:update's own test and damage);
-- "hit" (Link's body: the matrix damage dealt), "block" (the shield), or nil
local DEFAULT_TOUCH = { orgKbSpd = 24, orgIfr = 30, orgKbDur = 8, tgtDmg = 2 }
local function linkContact(E, e, hb, hitType)
  local f = E.field
  local p = f.player
  if not p or p.state == "dead" or (p.invuln or 0) ~= 0 then return nil end
  local HBm = require("src.zelda.tmc.Hitboxes")
  hb = hb or e.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  local probe = { x = e.x, y = e.y, hitbox = hb }
  local touch = HBm.touches(f, p, probe)
  if touch == nil then
    touch = math.abs((e.x + (hb.x or 0)) - p.x) < (hb.w or 4) + 5 and math.abs((e.y + (hb.y or 0)) - (p.y - 3)) < (hb.h or 4) + 6
  end
  if not touch then return nil end
  local hurtType = HBm.hurtType(p)
  local handler = HBm.data(f) and E.mtx and E.mtx ~= "" and HBm.handler(E.mtx, hitType or 0, hurtType)
  if handler == 1 or handler == 2 or handler == 16 then return nil end
  if p.blocksFrom and p:blocksFrom(e.x, e.y) then sound(E, SFX_SHIELD) return "block" end
  local s = (E.settings and E:settings(hitType or 0, HBm.data(f) and hurtType or 0)) or DEFAULT_TOUCH
  if (s.tgtDmg or 0) > 0 or (s.orgKbDur or 0) > 0 then
    if p.hurt and p:hurt(math.max(s.tgtDmg or 0, 1), e.x, e.y) then
      p.invuln = math.max(s.orgIfr or 0, 30)
      p.timer = math.max(s.orgKbDur or 0, 4)
      local ks = ((s.orgKbSpd or 0) * 16) / 256
      local dx, dy = p.x - e.x, p.y - e.y
      local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.kbx, p.kby = dx / d * ks, dy / d * ks
    end
  end
  return "hit"
end
M.linkContact = linkContact

-- a projectile (or the spear) as an entity: gProjectileDefinitions[id]
local function projDef(f, id, form)
  local defs = f.assets and f.assets.manifest and f.assets.manifest.projectileDefs
  local d = defs and defs[id]
  if d and d.multi then d = d.forms[form or 0] or d.forms[0] end
  return d
end
local function makeChild(E, parent, projId, form, kind)
  local f = E.field
  local d = projDef(f, projId, form) or {}
  local hb = d.hitbox and { x = d.hitbox.x or 0, y = d.hitbox.y or 0, w = d.hitbox.w or 0, h = d.hitbox.h or 0 }
              or { x = 0, y = 0, w = 2, h = 2 }
  local c = { kind = 4, id = parent.id, f2 = kind, form = form or 0, x = parent.x, y = parent.y, z = parent.z or 0,
              cz = parent.cz, layer = parent.layer, health = 0xFF, maxHealth = 0xFF, hitType = d.damageType or 0,
              hitbox = hb, sprite = d.sprite, anim = require("src.zelda.tmc.Anim").new(), animationState = 0,
              action = 0, timer = 0, subtimer = 0, iframes = 0, kbt = 0, enemy = true, literalAnim = true,
              field82 = 0, interactType = 0, def = { collision = 0, palette = d.palette }, parent = parent,
              noTouch = true, noHit = true, spd = d.speed or 0, dir = 0,
              homeX = parent.homeX or 0, homeY = parent.homeY or 0, rangeW = parent.rangeW or 0, rangeH = parent.rangeH or 0 }
  if (d.gfx or 0) == 0 then c.gfx, c.palette = parent.gfx, parent.palette
  else
    c.gfx = require("src.zelda.tmc.Assets").gfxSource("enemy", d.gfx)
    if E.A and E.A.objPalette then c.palette = E.A:objPalette(d.palette or 0, f.room.atlas and f.room.atlas.palettes) end
  end
  f.entities[#f.entities + 1] = c
  return c
end
M.makeChild = makeChild
local function alive(x) return x and not x.deleted and not x.dying end

function M.handles(e) return HANDLED[e.id] == true end

-- ===========================================================================
-- SPEAR_MOBLIN / BOW_MOBLIN: the shared walk / look / stand helpers
-- ===========================================================================
local function sees(E, e) -- sub_080286CC / sub_0803C568
  if (e.u81 or 0) ~= 0 then return false end
  local t = target(E.field)
  if not t then return false end
  if e.u82 == 2 and within(e, t.x, t.y, 0x30) then return true end
  if within(e, t.x, t.y, 0x40) and rshift(roundUp(dirTo(e.x, e.y, t.x, t.y)), 2) == e.animationState then return true end
  return false
end

local function mobAnim(E, e) -- sub_080287E0 / sub_0803C690
  local s = rshift(e.animationState, 1)
  local k = e.u82
  if k == 1 or k == 4 then s = s + 4
  elseif k == 3 or (k == 5 and e.id == M.BOW_MOBLIN) then s = s + 8
  elseif k == 2 then s = s + 0xC end
  setAnim(E, e, s)
end

local function mobStand(E, e) -- sub_080287B4 / sub_0803C664
  e.action, e.timer, e.subtimer = 3, 32, 0
  e.u80, e.u7b, e.spd, e.u82 = 0, 0, 0, 0
  mobAnim(E, e)
end

local function mobLook(E, e) -- sub_08028728 / sub_0803C5C4
  e.animationState = rshift(roundUp(e.dir), 2)
  e.dir = lshift(e.animationState, 2)
  e.u83 = rshift(e.u83, 1)
  mobStand(E, e)
  e.u82 = 2
end

local function mobSpot(E, e) -- sub_08028754 / sub_0803C5F0
  e.dir = facing(E, e)
  e.animationState = rshift(roundUp(e.dir), 2)
  e.u83 = 0
  if e.id == M.BOW_MOBLIN then e.u7a = 0 end
  mobStand(E, e)
  e.u82 = 3
end

local function mobBack(E, e) -- sub_08028784 / sub_0803C634
  e.animationState = rshift(roundUp(e.dir), 2)
  e.dir = lshift(e.animationState, 2)
  e.u83 = 0
  mobStand(E, e)
  e.timer = u8(e.timer * 2)
  e.u82 = 4
end

local function mobMove(E, e) -- sub_08028858 / sub_0803C6DC
  if e.u82 == 0 then e.spd = 0 end
  move0(E, e, e.dir, e.spd)
  frame(e)
end

local function mobWallAhead(e) -- gUnk_080CC7D8 / gUnk_080CFFBC: the facing side blocked
  local s = band(rshift(e.animationState, 1), 3)
  if s == 0 or s == 2 then return e.colY == true end
  return e.colX == true
end

-- ===========================================================================
-- SPEAR_MOBLIN
-- ===========================================================================
local function smPick(E, e) -- sub_08028604
  local f = E.field
  e.subtimer = 0
  local st
  if e.u82 == 1 then
    e.timer = SM_WALK[band(R(f), 3)]
    e.spd = 0x80
    if selfHome(e) then
      local tmp = SM_TURN[band(R(f), 7)] + 0x18
      e.dir = round(tmp + e.dir)
      st = rshift(e.dir, 2)
    else
      st = homeDir(e)
      if e.u83 == 0 then st = st + SM_HOME[band(R(f), 0xF)]
      else
        st = st + SM_HOME[band(R(f), 7)]
        e.timer = e.timer + 0x10
        e.u83 = e.u83 - 1
      end
      e.dir = band(st + 4, 0x18)
      st = rshift(e.dir, 2)
    end
  else
    e.timer, e.spd = 12, 0
    st = rshift(band(e.dir, 0x1F), 2)
  end
  if st ~= e.animationState then e.animationState = st; mobAnim(E, e) end
end

function M.smWindow(a0, a1) -- sub_08028828
  if roundUp(a1) == roundUp(a0) then
    return band(a1 + 5, 7) < 3 and band(a0 + 5, 7) < 3
  end
  return false
end

function M.spearCollision(E, e, flags)
  if band(flags, 0x80) == 0 then return end
  if e.action ~= 4 then mobSpot(E, e)
  elseif band(flags, 0x3F) == 0 then
    e.u7a = u8(e.u7a + 1)
    e.u81 = 0x16
    mobBack(E, e)
  end
end

local function spearMoblin(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- sub_08028314
    e.onCollision = M.spearCollision
    e.action, e.animationState = 1, 0
    e.u7b, e.u80, e.u83, e.u81, e.u7a, e.u82 = 0, 0, 0, 0, 0, 1
    e.timer = band(rshift(e.spawnB or 0, 8), 0xFF)
    e.dir, e.spd, e.subtimer = e.dir or 0, 0, 0
    if e.timer ~= 0 then
      e.animationState = lshift(band(e.spawnB or 0, 0xFF), 1)
      e.timer, e.spd = 30, 0x80
      e.dir = band(lshift(e.animationState, 2), 0x1F)
      mobAnim(E, e)
    else
      e.animationState = 0x10
      smPick(E, e)
    end
    local s = makeChild(E, e, P_MOBLIN_SPEAR, 0, "spear")
    s.sprite = nil -- (the spear is drawn by the moblin's own frames)
    s.noHit = nil
    s.onCollision = M.spearHit
    e.child = s
    return
  elseif a == 1 then -- sub_08028378
    if e.u81 ~= 0 then e.u81 = e.u81 - 1 end
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      e.u80 = u8(e.u80 + 1)
      if e.u80 >= 0x10 then mobLook(E, e) else smPick(E, e) end
    else
      if sees(E, e) then e.u7b = bor(e.u7b, 1) end
      if mobWallAhead(e) then
        bounceDir(e)
        e.animationState = rshift(roundUp(e.dir), 2)
        e.u83 = u8(e.u83 + 1)
        mobAnim(E, e)
      end
    end
    if e.subtimer >= 0xC then
      if e.u7b ~= 0 then mobSpot(E, e) end
    else e.subtimer = e.subtimer + 1 end
    mobMove(E, e)
  elseif a == 2 then -- sub_08028420
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      e.action, e.u82, e.u80 = 3, 0, 0
      e.animationState = 0x10
      smPick(E, e)
    elseif sees(E, e) then e.u7b = bor(e.u7b, 1) end
    if e.subtimer >= 0xC then
      if e.u7b ~= 0 then mobSpot(E, e) end
    else e.subtimer = e.subtimer + 1 end
    mobMove(E, e)
  elseif a == 3 then -- sub_08028488
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      local k = e.u82
      if k == 3 then
        e.action, e.spd = 4, 0x180
        e.dir = facing(E, e)
        sound(E, SFX_MOBLIN_SPEAR)
      elseif k == 2 then
        e.action, e.spd = 2, 0
        e.timer = band(R(f), 7) * 3 + 64
      else
        if k == 4 then e.dir = band(e.dir + 0x10, 0x18) end
        e.action, e.u82, e.spd = 1, 1, 0x80
        e.timer = band(R(f), 7) * 3 + 0x22
      end
      e.subtimer = 0
      e.animationState = rshift(roundUp(e.dir), 2)
      mobAnim(E, e)
    end
    mobMove(E, e)
  elseif a == 4 then -- sub_08028528
    local t = target(f)
    if not t then
      e.subtimer = 0
      mobLook(E, e)
    else
      if e.u7a ~= 0 then
        e.u7a, e.u81 = 0, 0x16
        mobBack(E, e)
      else
        e.timer = u8(e.timer + 1)
        if e.timer == 0x20 then
          e.timer = 0
          local d = dirTo(e.x, e.y, t.x, t.y)
          if M.smWindow(e.dir, d) then e.dir = d end
        end
        if band(e.timer, 7) == 0 then
          sound(E, SFX_F0)
          fx(E, e.x, e.y, FX_DEATH)
        end
        e.u7b = u8(e.u7b + 1)
        if e.u7b == 0x80 then e.u7a = u8(e.u7a + 1) end
      end
      if e.u7b > 0x20 then move0(E, e, e.dir, e.spd) end
      frame(e)
    end
  end
end

-- MOBLIN_SPEAR
function M.spearHit(E, s, flags) -- MoblinSpear_OnCollision: the moblin takes the knockback
  local par = s.parent
  s.health, s.kbt = 0xFF, 0
  if not alive(par) or band(flags, 0x80) == 0 then return end
  local p = E.field.player
  par.iframes = 0x10
  if E.knock then E:knock(par, p.x, p.y, 0x180 / 16, 0xC) end -- knockbackSpeed $180 (Enemies:knock takes it >> 4)
  if par.onCollision then par.onCollision(E, par, flags) end
end

local function spear(E, s)
  local par = s.parent
  if not alive(par) then s.deleted = true return end
  s.x, s.y, s.z, s.layer = par.x, par.y, par.z, par.layer -- CopyPosition (SpearMoblin)
  s.health, s.kbt = 0xFF, 0
  if s.action == 0 then s.action = 1 return end -- MoblinSpear_Init
  local i = band(par.anim and par.anim.flags or 0, 0x3F) -- parent->frame * 4 (u8) / 4
  local b = SPEAR_HB[i + 1] or SPEAR_HB[1]
  local ox = b[1]
  if par.anim and par.anim.hflip and par.anim:hflip() then ox = -ox end
  s.hitbox.x, s.hitbox.y, s.hitbox.w, s.hitbox.h = ox, b[2], b[3], b[4]
  if (par.kbt or 0) > 0 or (par.iframes or 0) > 0 then return end
  local r = linkContact(E, s, s.hitbox, s.hitType ~= 0 and s.hitType or 0x8B)
  if r == "block" then M.spearHit(E, s, 0x82)
  elseif r == "hit" and par.onCollision then par.onCollision(E, par, 0x80) end
end

-- ===========================================================================
-- BOW_MOBLIN
-- ===========================================================================
local function bmPick(E, e) -- sub_0803C4B0
  local f = E.field
  e.subtimer = 0
  local st
  if e.u82 == 1 then
    e.timer = BM_WALK[band(R(f), 7)]
    e.spd = 0x80
    if selfHome(e) then
      st = band(R(f), 6)
      e.dir = lshift(st, 2)
    else
      local d = homeDir(e)
      if e.u83 == 0 then d = d + BM_HOME[band(R(f), 0xF)]
      else
        d = d + BM_HOME[band(R(f), 7)]
        e.timer = u8(e.timer + 16)
        e.u83 = e.u83 - 1
      end
      e.dir = band(d + 4, 0x18)
      st = rshift(e.dir, 2)
    end
  else
    e.timer = 12
    e.spd = e.subtimer
    st = rshift(band(e.dir, 0x1F), 2)
  end
  if st ~= e.animationState then e.animationState = st; mobAnim(E, e) end
end

function M.bowCollision(E, e, flags)
  if band(flags, 0x80) == 0 then return end
  mobSpot(E, e)
  if e.child then e.child.subtimer = (e.child.subtimer or 0) + 1 end
end

local function bowMoblin(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- sub_0803C1E0
    e.onCollision = M.bowCollision
    e.action = 1
    e.u7b, e.u80, e.u83, e.u81, e.u7a, e.u82 = 0, 0, 0, 0, 0, 1
    e.timer = band(rshift(e.spawnB or 0, 8), 0xFF)
    e.dir, e.spd, e.subtimer = 0, 0, 0
    if e.timer ~= 0 then
      local t2 = band(e.spawnB or 0, 0xFF)
      e.animationState = lshift(t2, 1)
      e.timer, e.spd = 30, 0x80
      e.dir = band(lshift(t2, 3), 0x1F)
      mobAnim(E, e)
    else
      e.animationState = 0x10
      bmPick(E, e)
    end
  elseif a == 1 then -- sub_0803C234
    if e.u81 ~= 0 then e.u81 = e.u81 - 1 end
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      e.u80 = u8(e.u80 + 1)
      if e.u80 > 0xF then mobLook(E, e)
      elseif band(e.u80, 3) == 0 and band(R(f), 0x10) ~= 0 then mobStand(E, e); e.u82 = 5 -- sub_0803C624
      else bmPick(E, e) end
    elseif mobWallAhead(e) then
      bounceDir(e)
      e.animationState = rshift(band(e.dir + 4, 0x18), 2)
      e.u83 = u8(e.u83 + 1)
      mobAnim(E, e)
    elseif sees(E, e) then mobSpot(E, e) end
    mobMove(E, e)
  elseif a == 2 then -- sub_0803C2DC
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      e.action, e.u82, e.u80 = 3, 0, 0
      e.animationState = 0x10
      bmPick(E, e)
    elseif sees(E, e) then e.u7b = bor(e.u7b, 1) end
    if e.subtimer > 11 then
      if e.u7b ~= 0 then mobSpot(E, e) end
    else e.subtimer = e.subtimer + 1 end
    mobMove(E, e)
  elseif a == 3 then -- sub_0803C344
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      local k = e.u82
      if k == 3 then e.action, e.spd = 4, 0x80; e.dir = facing(E, e)
      elseif k == 5 then e.action, e.spd = 4, 0x80
      elseif k == 2 then e.action, e.spd = 2, 0; e.timer = 3 * band(R(f), 7) + 64
      else
        if k == 4 then e.dir = band(e.dir + 0x10, 0x18) end
        e.action, e.u82, e.spd = 1, 1, 0x80
        e.timer = 3 * band(R(f), 7) + 34
      end
      e.subtimer = 0
      e.animationState = rshift(band(e.dir + 4, 0x18), 2)
      mobAnim(E, e)
    end
    mobMove(E, e)
  elseif a == 4 then -- sub_0803C400
    if e.subtimer ~= 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then
        if e.u82 == 3 then
          e.u7a = u8(e.u7a + 1)
          if e.u7a <= 2 and band(R(f), 0xC0) ~= 0 then
            e.timer = 0
            mobAnim(E, e)
            mobMove(E, e)
            return
          end
        end
        mobBack(E, e)
      end
    else
      e.timer = u8(e.timer + 1)
      if e.timer == 1 then
        e.dir = lshift(e.animationState, 2)
        local c = makeChild(E, e, P_ARROW, rshift(e.animationState, 1), "arrow")
        c.dir = band(e.dir + 4, 0x18)
        e.child = c
      elseif e.timer == 24 then
        e.timer, e.subtimer = 0, 32
      end
      mobMove(E, e)
      local c = e.child
      if c and not c.deleted then -- sub_0803C714
        local i = band(e.animationState, 7)
        c.x, c.y, c.z = e.x + BM_ARROW[i], e.y + BM_ARROW[bor(i, 1)], e.z
      end
    end
  end
end

-- ARROW_PROJECTILE
local function arrowSet(E, c, s) -- sub_080A94C0
  local en = ARROW[band(s, 3)]
  c.flipX, c.flipY = en.fx, en.fy
  c.animIdx = en.anim
  c.hitbox = { x = en.hb.x, y = en.hb.y, w = en.hb.w, h = en.hb.h }
  setAnim(E, c, en.anim)
end

local function arrowKnocked(E, c) -- sub_080A9488
  local p = E.field.player
  c.action, c.timer = 4, 2
  collide(c, false)
  c.cz, c.czv = c.cz or 0, 0x18000
  c.animationState = rshift(band(dirTo(p.x, p.y, c.x, c.y), 0x18), 3) -- knockbackDirection
  sound(E, SFX_METAL_CLINK)
  arrowSet(E, c, c.animationState)
end

local function arrow(E, c)
  local f = E.field
  local par = c.parent
  if c.action == 0 then -- ArrowProjectile_Init
    c.action, c.timer, c.subtimer = 1, 106, 0
    collide(c, false)
    c.czv = 0x0A00
    arrowSet(E, c, c.form or 0)
    return
  elseif c.action == 1 then
    if not alive(par) or (c.subtimer or 0) ~= 0 then c.deleted = true return end
    if (par.subtimer or 0) ~= 0 then
      c.action = 2
      collide(c, true)
      if par.child == c then par.child = nil end
      sound(E, SFX_FC)
    end
    return
  elseif c.action == 2 then
    if c.colX or c.colY then
      c.action, c.timer = 3, 32
      collide(c, false)
      setAnim(E, c, (c.animIdx or 0) + 2)
      sound(E, SFX_18A)
      linear(c, c.dir, c.spd)
    else
      c.timer = c.timer - 1
      if c.timer == 0 then c.deleted = true return end
    end
    move0(E, c, c.dir, c.spd ~= 0 and c.spd or 0x300) -- ProcessMovement3
    if c.action == 2 and c.collideF then
      local r = linkContact(E, c, c.hitbox, c.hitType ~= 0 and c.hitType or 0x1A)
      if r == "hit" then c.deleted = true
      elseif r == "block" then
        if f.modStat then f:modStat("health", -2) end -- ModHealth(-2) (ArrowProjectile_OnCollision)
        arrowKnocked(E, c)
      end
    end
  elseif c.action == 3 then
    c.timer = c.timer - 1
    if c.timer == 0 then c.deleted = true return end
    frame(c)
  elseif c.action == 4 then
    if not gravity(c, 0x2800) then
      fx(E, c.x, c.y, FX_DEATH) -- CreateDeathFx
      c.deleted = true
    else
      c.timer = c.timer - 1
      if c.timer == 0 then
        c.timer = 2
        c.animationState = band(c.animationState + 1, 3)
        arrowSet(E, c, c.animationState)
      end
    end
  end
end

-- ===========================================================================
-- TAKKURI
-- ===========================================================================
local function tkAnim(E, e) setAnim(E, e, rshift(band(e.dir, 0x10), 4) + e.u81) end -- sub_0803BF2C

function M.stealRupees(E, e) -- StealRupees
  local f = E.field
  local t = target(f)
  if not t then return 0 end
  local rupees = f.save and f.save.stats and f.save.stats.rupees or 0
  local kind, n
  if rupees >= 500 then kind, n = ITEM_RUPEE20, 5; f:modStat("rupees", -100)
  elseif rupees >= 100 then kind, n = ITEM_RUPEE5, 5; f:modStat("rupees", -25)
  else
    kind = ITEM_RUPEE1
    n = rupees >= 5 and 5 or rupees
    f:modStat("rupees", -n)
  end
  local O = f.objects and f:objects()
  for _ = 1, n do
    -- RUPEE_OBJECT (object/rupee.c sub_08086A6C): a GROUND_ITEM bouncing out
    local r = R(f)
    if O and O.groundItem then
      O:groundItem(kind, 0, t.x, t.y, { drop = true, zVelocity = 2.5, direction = band(rshift(r, 16), 0x1F), speed = band(r, 480) })
    end
  end
  return n
end

function M.takkuriCollision(E, e, flags)
  if band(flags, 0x80) ~= 0 then
    if band(flags, 0x7F) == 0 then
      M.stealRupees(E, e)
      collide(e, false)
      local d = e.dir
      if band(roundUp(d), 8) == 0 then
        if band(d, 0x10) ~= 0 then d = d + 2 else d = d - 2 end
      end
      e.dir = band(0x20 - d, 0x1F)
      tkAnim(E, e)
    else
      e.health = 0 -- (iframes & $80) == 0: any other contact kills it
    end
    if (e.u82 or 0) >= 0x11 then e.u82 = e.u82 - 0xC end
  end
  frame(e)
end

local function tkAim(E, e) -- sub_0803BEE8
  e.timer = u8(e.timer - 1)
  if e.timer == 0 then
    e.u80 = e.dir
    local d = facing(E, e)
    if d ~= 0xFF then e.dir = d end
    e.timer = 8
    if band(e.u80, 0x10) ~= band(e.dir, 0x10) then tkAnim(E, e) end
  end
end

local function tkMove(E, e) linear(e, e.dir, e.spd) end -- sub_0803BF48

local function tkSwoop(E, e) -- sub_0803BF70
  local k = e.u84
  if k == 0 then
    if band(e.timer, 1) ~= 0 then e.z = e.z + 1 end -- z.HALF.HI-- (up)
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      e.u84, e.timer = 1, 24
      collide(e, true)
      e.u81 = 2
      tkAnim(E, e)
    end
  elseif k == 1 then
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      e.u84, e.timer, e.spd, e.u81 = 2, 8, 0x1C0, 4
      tkAnim(E, e)
    end
  elseif k == 2 then
    e.u82 = band((e.u82 or 0) - 1, 0xFFFF)
    if e.u82 == 0 then
      e.action, e.u84, e.timer, e.spd = 3, 0, 0, 0x180
      if band(e.dir + 0x18, 0x10) ~= 0 then e.dir = band(0x10 - e.dir, 0x1F) end
      tkAnim(E, e)
    else
      e.timer = u8(e.timer - 1)
      if e.timer == 0 then
        e.timer = 8
        e.u80 = e.dir
        turnStep(e, facing(E, e))
        if band(e.dir + 0x18, 0x10) ~= 0 then
          if e.u80 == 0x10 then
            if band(e.u80, e.dir) ~= 0 then e.u80 = 0x12 else e.u80 = 0xE end
          end
          e.dir = e.u80
          e.u82 = 1
        end
        if rshift(band(e.u80, 0x10), 4) ~= rshift(band(e.dir, 0x10), 4) then
          setAnim(E, e, rshift(band(e.dir, 0x10), 4) + 4)
        end
      end
    end
    tkMove(E, e)
  end
  frame(e)
end

local function tkHome(E, e) -- sub_0803C120
  e.action = 5
  e.hidden = true
  collide(e, false)
  e.x, e.y = e.x78, e.y7a
  e.z = e.z - 8 -- z.HALF.HI += 8
end

local function takkuri(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- sub_0803BCA4
    e.onCollision = M.takkuriCollision
    e.action, e.subtimer = 1, 0
    e.timer = band(rshift(e.spawnB or 0, 8), 0xFF)
    e.dir = band(facing(E, e), 0xFF)
    e.u80, e.u81, e.u82, e.u84 = 0, 0, 0, 0
    e.spd = e.speed or 0
    e.gustJarFlags = 1
    e.x78, e.y7a = math.floor(e.x), math.floor(e.y)
    collide(e, e.def and e.def.collision ~= 0 or false)
    tkAnim(E, e)
    return
  elseif a == 1 then -- sub_0803BD08
    if e.subtimer ~= 0 then
      if not onScreen(E, e) then e.subtimer = 0; e.hidden = false
      else return end
    end
    tkAim(E, e)
    frame(e)
    local t = target(f)
    if t and inRect(e, t, 0x88, 0x50) and math.floor(t.y) > math.floor(e.y) + 8 then
      e.action, e.u84, e.timer, e.u81 = 2, 0, 16, 2
      tkAnim(E, e)
    end
  elseif a == 2 then tkSwoop(E, e)
  elseif a == 3 then -- sub_0803BD90
    if not onScreen(E, e) then
      e.action = 4
      e.hidden = true -- spriteSettings.draw = 4 (the 2-bit field: 0)
      collide(e, false)
      e.timer = 8
    else
      tkMove(E, e)
      frame(e)
    end
  elseif a == 4 then -- sub_0803BDD8
    e.timer = u8(e.timer - 1)
    if e.timer ~= 0 then return end
    if not targetHome(E, e) or not selfHome(e) then tkHome(E, e)
    else
      if band(e.dir, 0x10) ~= 0 then e.dir = 8; e.x = math.floor(f.camX or 0) - 0x20
      else e.dir = 0x18; e.x = math.floor(f.camX or 0) + 0x110 end
      e.y = math.floor(f.camY or 0) + 8
      e.hidden = false
      collide(e, true)
      e.action, e.u84, e.timer, e.u82 = 2, 1, 24, 0x12C
      e.spd, e.u81 = 0x12C + 0x94, 4
    end
    tkAnim(E, e)
  elseif a == 5 then -- sub_0803BE7C
    if onScreen(E, e) then return end
    e.action = 1
    e.hidden = false
    collide(e, false)
    e.timer, e.subtimer = 8, 1
    e.dir = band(facing(E, e), 0xFF)
    e.u80, e.u81 = 0, 0
    tkAnim(E, e)
  end
end

-- ===========================================================================
-- LAKITU (+ its cloud, its lightning) and LAKITU_CLOUD
-- ===========================================================================
local function lkFace(E, e, k) -- sub_0803CA84
  local p = E.field.player
  local a = dirTo(e.x, e.y, p.x, p.y)
  if band(a - 3, 7) > 2 or band(e.animationState - rshift(a, 3), 3) > 1 then
    local s = rshift(roundUp(a), 3)
    if s ~= e.animationState then
      e.animationState = s
      setAnim(E, e, s + k)
      if alive(e.child) then setAnim(E, e.child, s) end
    end
  end
end

local function lkSees(E, e) -- sub_0803CA4C
  local p = E.field.player
  return not within(e, p.x, p.y, 0x28) and inRect(e, p, 0x70, 0x50)
end

local function lkThrow(E, e) -- sub_0803CB34
  local p = E.field.player
  e.action, e.hitType = 5, 0xA6
  e.u78 = dirTo(e.x, e.y, p.x, p.y)
  setAnim(E, e, e.animationState + 8)
end

local function lkCloudless(E, e) -- sub_0803CBAC
  local c = e.child
  if alive(c) then collide(c, true); c.hitType = 0x43 end
  e.action = 7
  draw(e, true)
  e.hitType = 0x42
  setAnim(E, e, e.animationState + 16)
end

local function lkBolt(E, e) -- Lakitu_SpawnLightning
  local b = makeChild(E, e, P_LAKITU_LIGHTNING, 0, "bolt")
  local o = LK_BOLT[band(e.animationState, 3)]
  b.dir = e.u78 or 0
  b.x, b.y, b.z, b.cz = e.x + o[1], e.y + o[2], e.z, e.cz
  sound(E, SFX_193)
  return b
end

local function lkPop(E, e) -- sub_0803CC08
  local c = e.child
  if not alive(c) then return end
  local dz = math.floor(-(c.z or 0) + 0.5) - math.floor(-(e.z or 0) + 0.5) -- cloud.z.HI - z.HI
  if dz < 0 or dz > 2 then return end
  if (e.czv or 0) >= 0 then return end
  if not within(e, c.x, c.y, 6) then return end
  local d = 6 -- Q_8_8(3.0 / 128.0) = 6, added to x.HALF.HI / y.HALF.HI
  fx(E, e.x + d, e.y + d, FX_DEATH); fx(E, e.x - d, e.y + d, FX_DEATH)
  fx(E, e.x + d, e.y - d, FX_DEATH); fx(E, e.x - d, e.y - d, FX_DEATH)
  e.child = nil
  c.deleted = true
end

function M.lakituCollision(E, e, flags)
  if band(flags, 0x7F) == 0x1D then
    e.czv = 0x20000
    lkCloudless(E, e)
  elseif e.hitType == 0x43 then
    local p = E.field.player
    local a = band(dirTo(p.x, p.y, e.x, e.y), 0x1F) -- knockbackDirection
    local ang = band(bxor(a, 0x10), 0x1F) / 32 * 2 * math.pi -- gSineTable[(dir ^ $10) << 3] >> 5: 8 px
    fx(E, e.x + math.floor(math.sin(ang) * 8), e.y - math.floor(math.cos(ang) * 8), FX_DEATH)
  end
end

function M.lakituJarPull(E, e) -- Lakitu_OnGrabbed subaction 2 (sub_0803C86C)
  lkCloudless(E, e)
  local c = e.child
  if alive(c) then fx(E, c.x, c.y, FX_DEATH); c.deleted = true end -- the cloud is swallowed
  e.child = nil
  return true
end

local function lakitu(E, e)
  local f = E.field
  local a = e.action
  if a ~= 0 and a ~= 7 then -- sub_0803CAD0
    if not within(e, e.u74, e.u76, 1) then
      e.dir = dirTo(e.x, e.y, e.u74, e.u76)
      move0(E, e, e.dir, e.speed ~= 0 and e.speed or 0x80)
    end
  end
  if a == 0 then -- Lakitu_Initialize
    e.onCollision = M.lakituCollision
    e.onJarPull = M.lakituJarPull
    e.action = 1
    e.animationState = 0
    e.cz, e.czv = -0x20000, 0; syncZ(e)
    e.spriteOY = -1
    e.u74, e.u76 = math.floor(e.x), math.floor(e.y)
    e.u79 = 0
    draw(e, false)
    local c = makeChild(E, e, P_LAKITU_CLOUD, 0, "cloud")
    e.child = c
  elseif a == 1 then -- Lakitu_Hide
    lkFace(E, e, 0)
    if lkSees(E, e) then e.action = 2; draw(e, true) end
  elseif a == 2 then -- Lakitu_EndHide
    frame(e)
    if done(e) then
      e.action, e.timer, e.hitType = 3, 60, 0x42
      setAnim(E, e, e.animationState + 4)
    end
  elseif a == 3 then -- Lakitu_Idle
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then -- sub_0803CB04
      lkThrow(E, e)
      e.u79 = 0
      if alive(e.child) then setAnim(E, e.child, e.animationState + 4) end
      return
    end
    if not lkSees(E, e) then
      e.action, e.hitType = 4, 0x43
      setAnim(E, e, e.animationState + 0xC)
    else lkFace(E, e, 4) end
  elseif a == 4 then -- Lakitu_BeginHide
    frame(e)
    if done(e) then
      e.action = 1
      draw(e, false)
      setAnim(E, e, e.animationState)
    end
  elseif a == 5 then -- Lakitu_Lightning
    frame(e)
    if not done(e) then return end
    lkBolt(E, e)
    e.action, e.hitType = 6, 0x42
    if band(R(f), 1) ~= 0 and e.u79 == 0 then
      e.timer, e.u79 = 15, 1
    else
      e.timer, e.u79 = 30, 0
      if alive(e.child) then setAnim(E, e.child, e.animationState) end
    end
  elseif a == 6 then -- Lakitu_LightningDelay
    e.timer = u8(e.timer - 1)
    if e.timer ~= 0 then return end
    if e.u79 == 1 then lkThrow(E, e)
    else
      e.action, e.timer = 3, 180
      setAnim(E, e, e.animationState + 4)
    end
  elseif a == 7 then -- Lakitu_Cloudless
    if not gravity(e, 0x1800) and (e.animIndex or 0) <= 19 then setAnim(E, e, e.animationState + 20) end
    frame(e)
    lkPop(E, e)
  end
end

-- LAKITU_CLOUD_PROJECTILE: on its Lakitu, 1 px up, z -2
local function lkCloud(E, c)
  local par = c.parent
  if not alive(par) then c.deleted = true return end
  if c.action == 0 then
    c.action = 1
    c.animationState = par.animationState or 0
    setAnim(E, c, c.animationState)
  end
  c.x, c.y = par.x, par.y - 1
  c.cz = -0x20000; syncZ(c)
  frame(c)
  if c.collideF then linkContact(E, c, c.hitbox, c.hitType) end
end

-- LAKITU_LIGHTNING
local function bolt(E, b)
  local f = E.field
  if b.action == 0 then
    b.action, b.timer, b.health = 1, 180, 1
    collide(b, true)
    setAnim(E, b, 0)
    return
  end
  frame(b)
  move0(E, b, b.dir, b.spd ~= 0 and b.spd or 0x80) -- ProcessMovement3
  b.timer = b.timer - 1
  if b.colX or b.colY or b.timer == 0 then
    fx(E, b.x, b.y, FX_BLUE_EFC)
    b.deleted = true
    return
  end
  local room = f.room
  if b.x < 0 or b.y < 0 or (room.width and b.x > room.width) or (room.height and b.y > room.height) then b.deleted = true return end
  if linkContact(E, b, b.hitbox, b.hitType ~= 0 and b.hitType or 0xA4) == "hit" then b.deleted = true end
end

-- LAKITU_CLOUD ($48)
local function railProp(f, k)
  local props = f.room and f.room.maps and f.room.maps.header and f.room.maps.header.props
  return props and props[k]
end
local function lcRail(E, e) -- sub_0803CE14
  local saveDir, saveSpd = e.direction, e.speed
  require("src.zelda.tmc.CoFObjects").railNext(E.field, e) -- UpdateRailMovement
  if e.railPtr == nil and e.direction == saveDir and e.speed == saveSpd then e.direction, e.speed = 0xFF, 0 end
  e.legT = e.u76 or 0
  local d = e.direction or 0xFF
  if band(d, 0x80) ~= 0 then return end
  setAnim(E, e, rshift(d, 3) + 4)
end

local function lcReset(E, e) -- sub_0803CE3C
  fx(E, e.x, e.y, FX_DEATH)
  e.action, e.timer = 2, 60
  collide(e, false)
  e.x, e.y = e.u78, e.u7a
  e.railPtr = e.railStart
  lcRail(E, e)
end

function M.cloudJarPull(E, e) -- sub_0803CD40 (the pull itself skipped)
  local f = E.field
  if f.modStat then f:modStat("health", -2) end
  sound(E, SFX_PLY_VO6)
  lcReset(E, e)
  return true
end

local function lakituCloud(E, e)
  local f = E.field
  if e.action == 0 then -- sub_0803CD6C
    e.onCollision = function(_, me) me.kbt = 0 end -- LakituCloud_OnKnockback
    e.onJarPull = M.cloudJarPull
    e.action = 1
    e.cz = -0x20000; syncZ(e)
    e.railStart = railProp(f, e.form or 0)
    e.railPtr = e.railStart
    e.u78, e.u7a = math.floor(e.x), math.floor(e.y)
    collide(e, true)
    setAnim(E, e, 4)
    lcRail(E, e)
  elseif e.action == 1 then -- sub_0803CDA8
    e.kbt = 0
    frame(e)
    if band(e.direction or 0xFF, 0x80) == 0 then linear(e, e.direction, e.speed) end
    e.legT = band((e.legT or 0) - 1, 0xFFFF)
    if e.legT == 0 then lcRail(E, e) end
  elseif e.action == 2 then -- sub_0803CDD8
    e.hidden = not e.hidden
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then e.action = 1; collide(e, true); e.hidden = false end
  end
end

-- ===========================================================================
-- CLOUD_PIRANHA
-- ===========================================================================
local function collAt(E, e, x, y) -- GetCollisionDataAtTilePos
  local room = E.field.room
  if not room.coll or not room.tw then return 0 end
  local tx, ty = rshift(math.floor(x), 4), rshift(math.floor(y), 4)
  if tx < 0 or ty < 0 or tx >= room.tw or (room.th and ty >= room.th) then return 0 end
  local c = room.coll[e.layer == 2 and 2 or 1] or room.coll[1]
  return c and c[ty * room.tw + tx] or 0
end
local function cloudEdge(v) return v == 0x0F or v == 0x2A end -- COLLISION_DATA_15 / 42

local function cpMove(E, e) -- sub_080387F0
  if e.action ~= 4 and e.u82 == 0 then
    if cloudEdge(collAt(E, e, e.x, e.y)) then e.u82 = 0x20 end
    local i = rshift(band(e.dir, 0x1F), 1) -- &gUnk_080CF520[direction >> 1]
    local before = e.dir
    if cloudEdge(collAt(E, e, e.x + (CP_AHEAD[i] or 0), e.y + (CP_AHEAD[i + 1] or 0))) then
      e.dir = band(e.dir + 0x10, 0x1F)
    elseif e.colX or e.colY then bounceDir(e) end
    if before ~= e.dir then
      e.animationState = rshift(e.dir, 2)
      setAnim(E, e, e.animationState)
    end
  end
  frame(e)
  if e.u82 == 0 then move0(E, e, e.dir, e.spd)
  else
    e.u82 = e.u82 - 1
    linear(e, e.dir, e.spd)
  end
end

local function cpNear(E, e, d) -- sub_0803872C
  local t = target(E.field)
  e.childT = t
  return t ~= nil and within(e, t.x, t.y, d)
end

local STATE8 = { [0] = 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5, 6, 6, 6, 6, 6, 7, 7, 7, 0, 0 } -- gMapDirectionToAnimationState8
M.STATE8 = STATE8
local function cpFace(e) -- sub_0806FCAC
  local t = e.childT
  return STATE8[dirTo(e.x, e.y, t.x, t.y)]
end

local function cpJump(E, e) -- sub_08038754
  e.action = 4
  collide(e, true)
  e.hitType = 0x5A
  e.spd = 0xC0
  e.cz, e.czv = e.cz or 0, 0x20000
  e.u81 = 0
  sound(E, SFX_12B)
  setPalette(E, e, 0x71)
  local base = rshift(band(e.dir, 0x10), 3)
  setAnim(E, e, base + (band(e.dir, 0xF) ~= 0 and 9 or 8))
  fx(E, e.x, e.y, FX_DEATH)
end

function M.piranhaCollision(E, e, flags)
  if band(flags, 0x80) == 0 then return end
  local k = band(flags, 0x3F)
  if e.hitType == 0x5A then
    if k == 0x14 then e.action = 5
    elseif k == 0x15 or k == 0x0E then e.health = 0 end
  elseif k == 0x1D then cpJump(E, e) end
end

local function cloudPiranha(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- CloudPiranha_Init
    e.onCollision = M.piranhaCollision
    e.action = 1
    e.dir = band(R(f), 0x1C)
    e.animationState = rshift(e.dir, 2)
    collide(e, true)
    e.timer, e.subtimer = 0, 32
    e.u82 = 0
    e.u80 = band(R(f), 1)
    e.u81 = 0
    e.hitType = 0x72
    e.spd = e.speed or 0
    e.cz, e.czv = 0, 0
    setAnim(E, e, e.animationState)
  elseif a == 1 then -- CloudPiranha_Action1
    cpMove(E, e)
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then
      e.timer, e.subtimer = 0, 32
      if selfHome(e) then
        local s = e.animationState + (e.u80 ~= 0 and 7 or 1)
        e.animationState = band(s, 7)
        e.dir = lshift(e.animationState, 2)
      else
        e.dir = band(homeDir(e) + 2, 0x1C)
        e.animationState = rshift(e.dir, 2)
      end
      setAnim(E, e, e.animationState)
    elseif e.timer == 0 and cpNear(E, e, 0x80) then
      e.action, e.subtimer, e.spd = 2, 16, 0x40
      e.animationState = cpFace(e)
      e.dir = lshift(e.animationState, 2)
      setAnim(E, e, e.animationState)
    end
  elseif a == 2 then -- sub_080385CC
    cpMove(E, e)
    if cpNear(E, e, 0x60) then
      e.action, e.subtimer, e.spd = 3, 12, 0x80
      e.animationState = cpFace(e)
      e.dir = lshift(e.animationState, 2)
      setAnim(E, e, e.animationState)
    else
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then
        e.subtimer = 16
        if e.childT then e.animationState = cpFace(e)
        else
          local s = e.animationState
          e.animationState = band(R(f), 0x10) ~= 0 and band(s + 2, 7) or band(s + 6, 7)
        end
        e.dir = lshift(e.animationState, 2)
        setAnim(E, e, e.animationState)
      end
    end
  elseif a == 3 then -- CloudPiranha_Action3
    cpMove(E, e)
    if cpNear(E, e, 0x14) then cpJump(E, e)
    else
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then
        e.subtimer = 10
        if e.u81 == 0 then
          e.spd = e.spd + 0x40
          if e.spd > 0x200 then e.u81 = 1 end
        elseif e.spd > 0x100 then e.spd = e.spd - 0x50
        else cpJump(E, e) end
      end
    end
  elseif a == 4 then -- CloudPiranha_Action4
    cpMove(E, e)
    if bounce(e, 0x1800) == 1 then -- BOUNCE_INIT_NEXT
      e.action, e.hitType, e.timer, e.subtimer, e.spd = 1, 0x72, 1, 128, 0x80
      sound(E, SFX_124)
      setPalette(E, e, 0x70)
      e.animationState = rshift(band(e.dir, 0x1F), 2)
      setAnim(E, e, e.animationState)
      fx(E, e.x, e.y, FX_DEATH)
    end
  elseif a == 5 then cpJump(E, e) end
end

-- ===========================================================================
-- ARMOS
-- ===========================================================================
local function arFrameFix(e) -- frame $25 shows $19 when unk_84 is set
  if (e.u84 or 0) ~= 0 and e.anim.frame == 0x25 then e.anim.frame = 0x19 end
end
local function arAnim(E, e, i) setAnim(E, e, i); arFrameFix(e) end   -- sub_080309C8
local function arFrame(e) frame(e); arFrameFix(e) end                 -- sub_080309A8
local function arSpeed(e) -- sub_080309E8
  if e.health < 5 then e.spd = 0x120 elseif e.health <= 8 then e.spd = 0xE0 end
end
local function tileXY(e) return rshift(math.floor(e.x), 4), rshift(math.floor(e.y), 4) end
local function arTileSet(E, e) -- sub_080307EC
  local room = E.field.room
  local tx, ty = tileXY(e)
  local L = e.layer == 2 and 2 or 1
  local name = L == 2 and "top" or "bottom"
  e.u78 = room.maps and room.maps[name] and room.maps[name][ty * room.tw + tx]
  e.u78at = { tx, ty, L }
  if room.setTile then room:setTile(L, tx, ty, SPECIAL_TILE_34) end
end
local function arTileBack(E, e) -- sub_08030834
  local room = E.field.room
  local tx, ty = tileXY(e)
  local L = e.layer == 2 and 2 or 1
  if e.u78 and room.setTile then room:setTile(L, tx, ty, e.u78) end
end
local function arDirAnim(E, e) -- sub_080307D4
  local s = rshift(band(e.dir, 0x1F), 3)
  if s ~= e.animationState then e.animationState = s; arAnim(E, e, s) end
end
local function arStatue(E, e) e.action = 1; arAnim(E, e, 4) end -- sub_08030580
local function arFreeze(E, e) -- sub_08030590
  e.action = 5
  e.hitType = 1
  e.hitbox = { x = 0, y = 0, w = 9, h = 9 } -- gHitbox_15
  arAnim(E, e, 5)
  arTileSet(E, e)
end

local function arSeek(E, e) -- sub_0800132C: Link's direction unless within 8 px on both axes
  local t = target(E.field)
  if not t then return 0xFF end
  if band(t.layer or 1, e.layer or 1) == 0 then return 0xFF end
  local dx, dy = math.floor(e.x) - math.floor(t.x), math.floor(e.y) - math.floor(t.y)
  if dx + 8 >= 0 and dx + 8 < 0x11 and dy + 8 >= 0 and dy + 8 < 0x11 then return 0xFF end
  return dirTo(e.x, e.y, t.x, t.y)
end

local function arChoose(E, e) -- sub_080306C4
  local f = E.field
  if targetHome(E, e) and e.u7a ~= 0 then
    e.timer = 24
    local d = arSeek(E, e)
    if d ~= 0xFF then
      local var = 0
      if (band(R(f), 7) ~= 0 or e.animationState == 0xFF) and band(e.u82, 3) ~= 3 then
        e.dir = band(d + 4, 0x18)
        var = 1
      end
      if var == 0 then e.dir = band(4 + d + (band(R(f), 2) - 1) * 8, 0x18) end
      local i = rshift(e.dir, 2)
      if f.room:isSolid(e.x + AR_AHEAD[i], e.y + AR_AHEAD[i + 1], e.layer == 2 and 2 or 1) then
        e.dir = bor(lshift(bxor(band(d, 4), 4), 1), band(d, 0x10))
        var = 0
      end
      arDirAnim(E, e)
      e.u82 = u8(bor(lshift(e.u82, 1), var))
    end
  else
    e.action, e.timer, e.spd = 4, 120, 0xA0
  end
end

local function arCentre(E, e) -- sub_080305BC: true once on a tile's centre
  local ax = band(math.floor(e.x), 0xF) == 8 and 1 or 0
  local ay = band(math.floor(e.y), 0xF) == 8 and 2 or 0
  local b = bor(ax, ay)
  if b == 3 then return true end
  local function step()
    move0(E, e, e.dir, e.spd)
    return not (e.colX or e.colY)
  end
  if band(e.dir, 8) ~= 0 then
    if band(b, 1) == 0 then
      if not step() then e.dir = bxor(e.dir, 0x10) end
      return false
    end
    if band(math.floor(e.y), 0xF) >= 9 then e.dir = 0x10 else e.dir = 0 end
    if band(e.dir, 8) ~= 0 then return false end
  end
  if band(b, 2) == 0 then
    if not step() then e.dir = bxor(e.dir, 0x10) end
  elseif band(math.floor(e.x), 0xF) >= 9 then e.dir = 8
  else e.dir = 0x18 end
  return false
end

local function arWakes(E, e) -- sub_08030650
  local f = E.field
  if (e.form or 0) == 0 then
    return e.touchedAt ~= nil and e.touchedAt >= (f.frame or 0) - 1
  elseif e.u80 ~= 2 then
    local t = targetHome(E, e)
    if not t then return false end
    local d = math.floor(t.x) - math.floor(e.x) + 0x10
    return d >= 0 and d <= 0x20
  else
    local t = targetHome(E, e)
    if not t then return false end
    return math.floor(t.x) < 0xA8
  end
end

function M.armosCollision(E, e, flags)
  if band(flags, 0x7F) <= 1 and band(flags, 0x80) ~= 0 then e.touchedAt = E.field.frame or 0 end
  if e.health ~= 0 and e.health ~= e.u81 then
    e.action = 8
    arAnim(E, e, 6)
    arSpeed(e)
  end
  e.u81 = e.health
end

local function armos(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- sub_0803026C
    e.onCollision = M.armosCollision
    e.u80 = band(rshift(e.spawnB or 0, 8), 0xFF)
    -- armos_data is cleared on every room change (sub_080300C4) unless the
    -- Minish entrance's transition is pending (not ported): no saved place
    e.u84 = band(rshift(0x47D, e.u80), 1)
    e.u81 = e.health
    e.u7a, e.u82, e.timer, e.subtimer = 0, 0, 0, 0
    e.spd = e.speed or 0
    e.dir = 0
    arStatue(E, e)
    arTileSet(E, e)
    if e.u80 == 2 and 0x80 < e.y then e.action = 7; arAnim(E, e, 7) end
  elseif a == 1 then -- sub_0803030C (sub_0803086C: the Minish entrance, not ported)
    if e.u84 ~= 0 and arWakes(E, e) then e.action, e.subAction = 2, 0 end
  elseif a == 2 then -- sub_08030338
    if e.u80 ~= 2 then arFrame(e) else e.anim:update(3); arFrameFix(e) end
    local fl = fflags(e)
    if fl == 1 then
      if e.subAction == 0 then e.subAction = 1 end
      e.timer = u8(e.timer + 1)
      if band(e.timer, 1) == 0 then return end
      e.spriteOX = AR_SHAKE[rshift(band(e.timer, 6), 1)]
    elseif fl == 2 then
      take(e)
      if e.u80 ~= 2 then
        e.hitType = 8
        e.hitbox = { x = 0, y = 0, w = 6, h = 6 } -- gUnk_080FD2F0
      end
      arTileBack(E, e)
      sound(E, SFX_12A)
    elseif band(fl, 0x80) ~= 0 or e.anim.done then
      e.spriteOX = nil
      if e.u80 ~= 2 then
        e.action = 3
        e.animationState = 0xFF
        e.u7a, e.u82 = 600, 0
        arChoose(E, e)
        arSpeed(e)
      else
        e.action, e.timer, e.spd, e.dir = 6, 26, 0x300, 0x10
      end
    else
      e.spriteOX = nil
    end
  elseif a == 3 then -- sub_08030430
    move0(E, e, e.dir, e.spd) -- sub_08030A04
    if band(fflags(e), 1) ~= 0 then take(e); sound(E, SFX_101) end
    if e.spd > 0x100 then frame(e) end
    arFrame(e)
    if e.u7a ~= 0 then e.u7a = e.u7a - 1 end
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then arChoose(E, e) end
  elseif a == 4 then -- sub_08030474
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      e.action, e.timer, e.u7a = 3, 1, 0x3C
      arSpeed(e)
    elseif arCentre(E, e) then arFreeze(E, e)
    else
      arDirAnim(E, e)
      arFrame(e)
    end
  elseif a == 5 then -- sub_080304BC
    arFrame(e)
    local fl = fflags(e)
    if band(fl, 0x80) ~= 0 or e.anim.done then arStatue(E, e)
    elseif fl == 1 then take(e); sound(E, SFX_12A) end
  elseif a == 6 then -- sub_080304F4
    linear(e, e.dir, e.spd)
    arFrame(e)
    e.timer = u8(e.timer - 1)
    if e.timer == 0 then
      e.action = 7
      arAnim(E, e, 5)
      arTileSet(E, e)
    end
  elseif a == 7 then -- sub_08030524
    local fl = fflags(e)
    if band(fl, 0x80) == 0 and not e.anim.done then arFrame(e)
    elseif fl == 1 then take(e); sound(E, SFX_12A) end
  elseif a == 8 then -- sub_08030554
    arFrame(e)
    if done(e) then
      e.action = 3
      arAnim(E, e, band(e.animationState, 0xFF))
      arChoose(E, e)
    end
  end
end

-- ===========================================================================
function M.update(E, e)
  local k = e.f2
  if k == "spear" then return spear(E, e)
  elseif k == "arrow" then return arrow(E, e)
  elseif k == "cloud" then return lkCloud(E, e)
  elseif k == "bolt" then return bolt(E, e) end
  local id = e.id
  if id == M.SPEAR_MOBLIN then spearMoblin(E, e)
  elseif id == M.BOW_MOBLIN then bowMoblin(E, e)
  elseif id == M.TAKKURI then
    takkuri(E, e)
    -- its contact (z can reach 8: the port's z < 8 rule would drop it)
    e.noTouch = true
    if e.collideF and not e.dying and (e.kbt or 0) == 0 then
      local r = linkContact(E, e, e.hitbox, e.hitType)
      if r == "hit" then M.takkuriCollision(E, e, 0x80); if e.health <= 0 and E.kill then E:kill(e) end end
    end
  elseif id == M.LAKITU then lakitu(E, e)
  elseif id == M.LAKITU_CLOUD then lakituCloud(E, e)
  elseif id == M.CLOUD_PIRANHA then cloudPiranha(E, e)
  elseif id == M.ARMOS then armos(E, e) end
end

return M
