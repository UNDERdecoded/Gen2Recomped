-- Round 26 (team A): overworld enemies, part 1, from the decomp
-- (src/enemy/*.c).  EnemyField.lua dispatches here (handles / update).
--
-- COMMON
--   sub_08049FDC (Link inside the home rectangle), sub_08049FA0 (the enemy
--   inside it), sub_08049EE4 (toward the home rectangle's middle),
--   sub_08049F84 (GetFacingDirection to the enemy target, $FF without one),
--   sub_08004596 (one 1/32 step toward a direction), EntityInRectRadius,
--   EntityWithinDistance, CheckOnScreen ($3F margins, the screen 240x160)
--   are ported as local helpers.  COLLISION_ON / OFF are e.noTouch /
--   e.noHit / e.collideOn; spriteSettings.draw is (not e.hidden).
--   super->frame (the keyframe flags byte, ANIM_DONE $80) is the Anim's
--   flags; "frame &= ~bit" consumes the bit for that keyframe.
--
-- LEEVER $02 (leever.c): Leever_Initialize / Idle / DigUp / Attack /
--   DigDown, Leever_PlayerInRange + sub_0801FDE4 (8 steps of 8 px from
--   Link along a random 1/32 direction, every point open and an
--   ACT_TILE_9..12 tile -- the leever is moved to each point that passes,
--   tile-centred, on Link's layer), Leever_Move (speed = keyframe flags &
--   $F * $20, blue + $40; re-aim one step every 16 / 8 frames with
--   sub_0800132C: $FF when within 8 px or on another layer), gLeeverDrift
--   (+-6), OnCollision (Link's body while attacking -> it digs down next
--   frame).  Red attacks 180 frames, blue 110.
--   SIMPLIFIED: the blue one's death FX table ($F1) is the generic drop.
-- ACRO_BANDIT $2E (acroBandits.c): type 0 (the spawner) actions 0-8 --
--   pops up on a random free spot of the 5x5 grid of 16 px round its
--   start when Link is in its home, looks round (timers 2-4 loops), when
--   Link is within $50 of the keyframe's point (gUnk_080CE5C0) it builds
--   the tower: five type 1 bandits (type2 0 bottom .. 4 top, parent = the
--   one below, child = the one above, unk_74 = Random & 3 for the fall
--   pattern), then hides (action 7: its timer counts the tower -- each
--   bandit that leaves takes 1, each one killed adds 15 (sub_08032338);
--   all five killed (80) deletes it, else back to action 1 after 180).
--   Type 1 actions 0-9: rise out of the ground (zVelocity 4.0, - 3/32),
--   drop onto the one below (banditGravity 22/19/16/13/11), the bottom one
--   walks (home / homeward / random every 16 frames, sub_08004596 toward
--   Link every 8th frame), the others follow the one below (LinearMove
--   toward it, the 6-frame flip delay sub_080322E8); when the one above
--   comes down within 8 (sub_080322A4) it falls (action 5/6); the top one
--   releases the whole tower (timer 0) -> they scatter (fallDirections,
--   speed $F0, zVelocity 1.125, BounceUpdate 32), lie, rise and leave.
--   OnCollision: knocked out of the tower (action 9) -> the ones above
--   fall (action 5), the chain is relinked.
--   SIMPLIFIED: a kill (health 0, which the port's Enemies:hit does not
--   pass to OnCollision) is noticed by the spawner's watch the same frame
--   (the collapse + the +15); AcroBandit_OnKnockback's GravityUpdate, the
--   gust jar's sub_08032338 and the entity-count guard are not ported;
--   only bandits within z 8 of the ground touch Link (Enemies:update).
-- GHINI $4E (ghini.c): Init (type 1 starts unseen: action 1, animation
--   9), actions 1-9, sub_0803F51C/528 (wander: gUnk_080D0974 speeds,
--   gUnk_080D0978 turns, hitType $24), sub_0803F58C (half vertical speed),
--   sub_0803F5D4 / 630 (Link in its home and within $70x$48 -> chase:
--   hitType $25, gUnk_080D0980 delay, then speed $100 re-aiming by
--   gUnk_080D0970), the grab (Link's body against hitType $25 -> action 8,
--   then 9: Link held at its place, -4 health on every keyframe flag 1,
--   each button press + $C, $E0 -> it lets go: knockback $14 frames at
--   $180, unk_7c $78 frames before it chases again), the bob
--   (gUnk_080D0984, every 8 frames), OnCollision, OnConfused's end and
--   OnKnockback's end (animation back to the walk), OnGrabbed subaction 0
--   and letting go.
--   SIMPLIFIED: gArea.lightLevel is f.lightLevel (missing = lit); the
--   lantern test (sub_0806FD54) reads p.lanternLit; player clones are not
--   ported (no +60); Link's hop on release does not set a direction speed;
--   ProcessMovement1 moves without tile collision.
-- CROW $31 (crow.c): sub_08032928 (perched, collision off), 98C (faces
--   Link every 8 frames; Link within $88x$50 and > 8 px below -> takes
--   off), sub_08032B38 (rise 8 px over 16 frames, 24 frames hovering with
--   collision on, then the dive at $1C0 steering one step every 8 frames
--   and never upward -- turning up ends it: action 3 flies off at $180),
--   9F0 / A48 (off screen it goes back to its perch, which must itself be
--   off screen before it shows again), OnCollision (Link's body: collision
--   off 16 frames and it glances off (0x20 - direction); any weapon: health
--   0), OnGrabbed's letting go (straight to the dive).
--   SIMPLIFIED: collisionLayer 3 / flipY (it flies over both layers) are
--   not set -- the port's layer stays the spawn layer.
-- KEATON $30 (keaton.c): Init, actions 1-5, sub_080325E8 (Link within
--   $68x$40 in front of the keyframe's direction -> wind up), 650 (walk
--   gUnk_080CE7E0 frames), 69C (diagonal hysteresis), 6FC / 71C (rest
--   timer gUnk_080CE7F0), the charge ($1E0 for $46 frames, FX_DASH every 4
--   / 8 frames at gUnk_080CE810), OnCollision (turns to face the hit and
--   charges; $CC stops it).  KEATON_DAGGER (keatonDagger.c): its hitbox
--   follows Keaton (gUnk_08129998 by animation state); touching Link ends
--   the charge, hurts him through the matrix with the dagger's hitType and
--   steals rupees (StealRupees, takkuri.c: >= 500 -> 5 x 20 for 100, >= 100
--   -> 5 x 5 for 25, else up to 5 x 1).
--   SIMPLIFIED: the dagger is a hitbox test inside Keaton's update (no
--   entity); the stolen rupees are ground items (RUPEE_OBJECT's own toss is
--   not ported).
-- ROCK_CHUCHU $0A (rockChuchu.c): sub_08022368 / 2390 (toward Link every
--   16 frames, a pause of Random & 4), OnCollision: bombs ($16) / $1C, or
--   the sword family with the Rock Breaker (ITEM_SKILL_ROCK_BREAKER $4B)
--   -> FX_ROCK, a CHUCHU type 1 (type2 1, iframes 8, the home rectangle
--   copied) and next frame (sub_080223E4) the ChuChu gets contact $94,
--   iframes 16, a 12-frame knockback the way the hit went; the rock is
--   deleted.  Health 0 -> animation 2.
-- SCISSORS_BEETLE $40 (scissorsBeetle.c) with its MANDIBLES_PROJECTILE
--   (mandiblesProjectile.c): all five beetle actions (walk, attack hold,
--   wait, run in circles without its mandibles), sub_08038BA8 / C2C / C84,
--   OnCollision; the mandibles' Init / actions 1-4 (snap when Link is in
--   front within $40, thrown and homing back -- sub_080AA374 with
--   gUnk_08129D14 --, -2 health on contact while flying), gUnk_08129CA4 /
--   CAC timers, gUnk_08129CF4 hitboxes.
--   SIMPLIFIED: the mandibles sit at the beetle + gUnk_08129D14[state]
--   (the sprite sub-entry offsets are not read); the grass cutting of
--   action 2 (SPECIAL_TILE_0 -> 5) and sub_0800445C are not ported; the
--   mandibles' speed is their projectile definition's (else $200).
-- CUCCO_AGGR $41 (cuccoAggr.c): sub_08038D78, the idle / hop / peck
--   (sub_0803901C with the cartridge's r3 == 3 bug), the flee from Link
--   (sub_08039218: $140 for $384 frames, type 1 $200 for $3C), the revenge
--   (a hit while health <= $BF and room flag 1 clear: every 32 frames a
--   type 2 cucco from gCuccoAggrSpawnPoints at the screen's edge, homing
--   on Link for $B4 frames then flying on until off screen), FX_EGG /
--   FX_WOOD2 puffs.
--   SIMPLIFIED: carrying a cucco (action 2, RegisterCarryEntity) is not
--   ported.
local bit = require("bit")
local band, bor, bxor, bnot, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift

local M = {}
M.LEEVER, M.ROCK_CHUCHU, M.ACRO_BANDIT, M.KEATON, M.CROW = 0x02, 0x0A, 0x2E, 0x30, 0x31
M.SCISSORS_BEETLE, M.CUCCO_AGGR, M.GHINI = 0x40, 0x41, 0x4E
local CHUCHU = 0x01
local HANDLED = { [0x02] = true, [0x0A] = true, [0x2E] = true, [0x30] = true, [0x31] = true,
                  [0x40] = true, [0x41] = true, [0x4E] = true }

local SPECIAL_FX = 0x0F
local FX_ROCK, FX_DASH, FX_EGG, FX_WOOD2 = 0x04, 0x11, 0x3A, 0x4C
local SFX_12B, SFX_15B, SFX_15D, SFX_F2, SFX_PLY_VO6 = 0x12B, 0x15B, 0x15D, 0xF2, 0x7C
local SFX_VO_CUCCO1, SFX_VO_CUCCO4 = 0x1D6, 0x1D9
local ITEM_RUPEE1, ITEM_RUPEE5, ITEM_RUPEE20, ITEM_SKILL_ROCK_BREAKER = 0x54, 0x55, 0x56, 0x4B
local KEATON_DAGGER, MANDIBLES_PROJECTILE = 0x0B, 0x13

-- the decomp's tables (gameplay constants)
M.LEEVER_DRIFT = { [0] = 6, -6 }                                    -- gLeeverDrift
M.LEEVER_TILES = { [9] = true, [10] = true, [11] = true, [12] = true } -- gUnk_080CA4CA (ACT_TILE_10, 9, 12, 11)
M.ACRO_LOOK = { [0] = 2, 2, 2, 3, 3, 3, 3, 4 }                      -- Type0Action2 timers
M.ACRO_HIDE = { [0] = 60, 60, 90, 120, 120, 120, 120, 150 }         -- Type0Action4 timers
M.ACRO_SIGHT = { [0] = -32, 0, 0, 32, 32, 0, 0, 0 }                 -- gUnk_080CE5C0
M.ACRO_GRAVITY = { [0] = 0x1600, 0x1300, 0x1000, 0x0D00, 0x0B00 }  -- banditGravity (Q8.8 22/19/16/13/11)
M.ACRO_FALL = { [0] = 0x8, 0x1c, 0x11, 0x2, 0x15, 0xc, 0x0, 0x15, 0x6, 0x19,
                0x10, 0x4, 0x19, 0xa, 0x1d, 0x14, 0x8, 0x1d, 0xe, 0x1 } -- fallDirections
M.GHINI_TURN_MASK = { [0] = 15, 7, 3, 1 }                           -- gUnk_080D0970
M.GHINI_SPEED = { [0] = 224, 192, 160, 128 }                        -- gUnk_080D0974
M.GHINI_TURN = { [0] = 0, -2, 0, 2, 0, -4, 0, 4 }                   -- gUnk_080D0978
M.GHINI_DELAY = { [0] = 15, 25, 34, 45 }                            -- gUnk_080D0980
M.GHINI_BOB = { [0] = -1, -2, -3, -2 }                              -- gUnk_080D0984
M.KEATON_WALK = { [0] = 60, 60, 90, 90, 90, 90, 120, 120, 120, 120, 120, 120, 120, 120, 150, 150 } -- gUnk_080CE7E0
M.KEATON_REST = { [0] = 0xd2, 0xd2, 0xf0, 0xf0, 0x10e, 0x10e, 0x10e, 0x10e,
                  0x12c, 0x12c, 0x12c, 0x12c, 0x12c, 0x12c, 0x12c, 0x12c } -- gUnk_080CE7F0
M.KEATON_DASH = { [0] = 0, 2, -4, 0, 0, -11, 4, 0 }                 -- gUnk_080CE810
M.DAGGER_HB = { [0] = { x = 4, y = -16, w = 2, h = 3 }, { x = 9, y = -2, w = 3, h = 2 },
                { x = -4, y = 1, w = 2, h = 3 }, { x = -9, y = -2, w = 3, h = 3 } } -- gUnk_08129998
M.SB_WALK = { [0] = 0x2d, 0x5a, 0x3c, 0x2d, 0x5a, 0x4b, 0x3c, 0x5a }  -- gUnk_080CF62C
M.SB_MAND = { [0] = 0x18, 0x24, 0x34, 0x20, 0x3c, 0x1c, 0x2c, 0x28 }  -- gUnk_080CF634
M.SB_TURN = { [0] = 1, 0, 7, 1, 0, 7, 0, 0 }                          -- gUnk_080CF63C
M.MAND_TIME = { [0] = 24, 36, 52, 32, 60, 28, 44, 40 }                -- gUnk_08129CA4
M.MAND_TURN = { [0] = 1, 0, 7, 1, 0, 7, 0, 0 }                        -- gUnk_08129CAC
M.MAND_HB = { [0] = { x = 0, y = -4, w = 6, h = 8 }, { x = 3, y = -3, w = 6, h = 6 }, { x = 4, y = 0, w = 8, h = 6 },
              { x = 3, y = 3, w = 6, h = 6 }, { x = 0, y = 4, w = 6, h = 8 }, { x = -3, y = 3, w = 6, h = 6 },
              { x = -4, y = 0, w = 8, h = 6 }, { x = -3, y = -3, w = 6, h = 6 } } -- gUnk_08129CF4
M.MAND_OFF = { [0] = 0, -16, 6, -10, 0, 4, -6, -10 }                 -- gUnk_08129D14
M.CUCCO_CARRY = { [0] = 0, 0x78 }                                     -- gUnk_080CF7BC
M.CUCCO_IDLE = { [0] = 0x1e, 0x2d, 0x3c, 0x4b }                       -- gUnk_080CF7BE
M.CUCCO_SPEED = { [0] = 0x80, 0xc0 }                                  -- gUnk_080CF7C2
M.CUCCO_FLEE_SPEED = { [0] = 0x140, 0x200 }                           -- gUnk_080CF824
M.CUCCO_FLEE_TIME = { [0] = 0x384, 0x3c }                             -- gUnk_080CF828
M.CUCCO_FX_X = { [0] = 8, -8 }                                        -- gCuccoAggrFxHorizontalOffsets
M.CUCCO_FX = { [0] = FX_EGG, FX_WOOD2, FX_EGG }                       -- gCuccoAggrFx
M.CUCCO_SPAWN = { [0] = { 0x18, -0x8 }, { 0x38, -0x8 }, { 0x58, -0x8 }, { 0x78, -0x8 }, { 0x98, -0x8 }, { 0xB8, -0x8 },
                  { 0xD8, -0x8 }, { 0x18, 0xA8 }, { 0x38, 0xA8 }, { 0x58, 0xA8 }, { 0x78, 0xA8 }, { 0x98, 0xA8 },
                  { 0xB8, 0xA8 }, { 0xD8, 0xA8 }, { -0x8, 0x10 }, { -0x8, 0x30 }, { -0x8, 0x50 }, { -0x8, 0x70 },
                  { -0x8, 0x90 }, { 0xF8, 0x10 }, { 0xF8, 0x30 }, { 0xF8, 0x50 }, { 0xF8, 0x70 }, { 0xF8, 0x90 } } -- gCuccoAggrSpawnPoints

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function D() return require("src.zelda.tmc.Drops") end
local function R(f) return D().random(D().rngOf(f)) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i); e.takeKey = nil end
local function dirTo(ax, ay, bx, by) return DW().dirTo(ax, ay, bx, by) end
local function dirVec(d)
  local a = (d % 32) / 32 * 2 * math.pi
  return math.sin(a), -math.cos(a)
end
-- ProcessMovement0: true when it moved freely; a direction with bit 7 ($FF) does not move
local function move(E, e, dir, spd)
  if not dir or dir >= 0x80 then return true end
  local hx, hy = DW().move0(E, e, band(dir, 0x1F), spd or 0)
  e.lastHit = (hx or hy) and true or false
  return not e.lastHit
end
-- LinearMoveUpdate / ProcessMovement1 (no tile collision)
local function linear(e, dir, spd)
  if not dir or dir >= 0x80 then return end
  local vx, vy = dirVec(band(dir, 0x1F))
  local s = (spd or 0) / 256
  e.x, e.y = e.x + vx * s, e.y + vy * s
end
local function syncZ(e) e.z = -(e.cz or 0) / 65536 end
local function zhi(e) return math.floor((e.cz or 0) / 65536) end
-- GravityUpdate (16.16 z, negative up): true while airborne
local function gravity(e, g)
  local z = (e.cz or 0) - (e.czv or 0)
  if z < 0 then e.cz = z; e.czv = (e.czv or 0) - g; syncZ(e) return true end
  e.cz, e.czv = 0, 0; syncZ(e)
  return false
end
local function bounce(e, g) local r = require("src.zelda.tmc.EnemyCrenel").bounce(e, g); syncZ(e) return r end
local function dec8(v) return band((v or 0) - 1, 0xFF) end

local function colOn(e) e.noTouch, e.noHit, e.collideOn = nil, nil, true end
local function colOff(e) e.noTouch, e.noHit, e.collideOn = true, true, nil end

-- super->frame: the keyframe flags (ANIM_DONE $80 once the last keyframe is
-- reached), minus the bits consumed on this keyframe
local function fflags(e)
  local a = e.anim
  if not a then return 0 end
  local fl = a.flags or 0
  if a.done then fl = bor(fl, 0x80) end
  if e.takeKey == a.key and e.takeIdx == e.animIndex then fl = band(fl, bnot(e.takeMask or 0)) end
  return fl
end
local function take(e, mask)
  local a = e.anim
  if e.takeKey == a.key and e.takeIdx == e.animIndex then e.takeMask = bor(e.takeMask or 0, mask)
  else e.takeKey, e.takeIdx, e.takeMask = a.key, e.animIndex, mask end
end
local function done(e) return band(fflags(e), 0x80) ~= 0 end
local function frames(e, n) if e.anim then e.anim:update(n or 1) end end

-- the enemy target (sub_08049DF4(1) -> sub_08049E4C)
local function target(f) return DW().target(f) end
-- sub_08049DF4(0) (sub_08049E18: Minish Link counts)
local BUSY0 = { fall = true, portal = true, dead = true, climb = true, cart = true, hole = true, drown = true, itemget = true }
local function target0(f)
  local p = f.player
  if not p or BUSY0[p.state or "normal"] or p.portalMode or p.hidden or p.control == false then return nil end
  return p
end
local function layersMeet(a, b) return band(a.layer or 1, b.layer or 1) ~= 0 end
-- sub_08049FDC
local function targetHome(E, e)
  local t = target(E.field)
  if not t then return nil end
  local dx, dy = math.floor(t.x) - e.homeX, math.floor(t.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH and t or nil
end
-- sub_08049FA0
local function selfHome(e)
  local dx, dy = math.floor(e.x) - e.homeX, math.floor(e.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH
end
-- sub_08049EE4
local function homeDir(e) return dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) end
-- sub_08049F84
local function facing(E, e, t)
  t = t or target(E.field)
  if not t then return 0xFF end
  return dirTo(e.x, e.y, t.x, t.y)
end
-- sub_08004596
local function turn(e, want)
  local cur = e.dir or 0
  if cur >= 0x20 then e.dir = band(want, 0x1F) return end
  local d = want - cur
  if d == 0 then return end
  d = band(d, 0x1F)
  e.dir = band(cur + (d < 0x10 and 1 or -1), 0x1F)
end
-- EntityInRectRadius
local function inRect(a, b, rx, ry)
  if not layersMeet(a, b) then return false end
  local dx, dy = math.floor(a.x) - math.floor(b.x), math.floor(a.y) - math.floor(b.y)
  return (rx == 0 or (dx >= -rx and dx <= rx)) and (ry == 0 or (dy >= -ry and dy <= ry))
end
-- EntityWithinDistance (PointInsideRadius)
local function within(e, x, y, d)
  local dx, dy = math.floor(e.x) - math.floor(x), math.floor(e.y) - math.floor(y)
  return d * d >= dx * dx + dy * dy
end
-- CheckOnScreen: x - scroll + $3F < $16E, y - scroll + z + $3F < $11E
local function onScreen(f, e, x, y)
  local sx = math.floor(x or e.x) - math.floor(f.camX or 0) + 0x3F
  local sy = math.floor(y or e.y) - math.floor(f.camY or 0) + zhi(e) + 0x3F
  return sx >= 0 and sx < 0x16E and sy >= 0 and sy < 0x11E
end
local function solidAt(f, x, y, layer) return f.room:isSolid(x, y, layer == 2 and 2 or 1) end
local function actAt(f, x, y, layer)
  local tt = f.room:tileType(layer == 2 and 2 or 1, math.floor(x / 16), math.floor(y / 16))
  if not tt or tt >= 0x4000 then return nil end
  return f.assets.actTile and f.assets.actTile[tt]
end
-- the knockback's direction (Enemies:knock keeps a vector)
local function kbDir(e)
  if (e.kbx or 0) == 0 and (e.kby or 0) == 0 then return e.kbDir or 0 end
  return dirTo(0, 0, e.kbx, e.kby)
end
local function sound(f, id) if f.sound then f:sound(id) end end
local function fx(f, x, y, t) if f.addFx then f:addFx(x, y, SPECIAL_FX, t) end end

-- CreateEnemy (+ EnemyCopyParams' home rectangle): a full enemy entity
local function spawnEnemy(E, src, id, form)
  local f = E.field
  local c
  if E.spawn and E.m then
    local ok, r = pcall(E.spawn, E, { id = id, paramA = form, paramB = 0, paramC = 0,
                                      x = math.floor(src.x), y = math.floor(src.y) })
    if ok then c = r end
  end
  if not c then
    c = { kind = 3, id = id, form = form, x = src.x, y = src.y, z = 0, zv = 0,
          health = src.maxHealth or src.health, maxHealth = src.maxHealth or src.health, speed = src.speed,
          hitType = src.hitType, hitbox = src.hitbox, sprite = src.sprite, palette = src.palette, gfx = src.gfx,
          anim = require("src.zelda.tmc.Anim").new(), animationState = 2, action = 0, timer = 1, iframes = 0, kbt = 0,
          enemy = true, literalAnim = true, field82 = 0, interactType = 0, def = src.def or {}, spawnB = 0, spawnC = 0 }
  end
  c.x, c.y, c.layer = src.x, src.y, src.layer
  c.homeX, c.homeY, c.rangeW, c.rangeH = src.homeX, src.homeY, src.rangeW, src.rangeH
  f.entities[#f.entities + 1] = c
  return c
end

function M.handles(e)
  return HANDLED[e.id] == true or e.mandibles == true
end

-- ===========================================================================
-- LEEVER
-- ===========================================================================
-- sub_0801FDE4
local function leeverSpot(E, e, t, x, y)
  local f = E.field
  local L = t.layer or 1
  if solidAt(f, x, y, L) then return false end
  local a = actAt(f, x, y, L)
  if a and M.LEEVER_TILES[a] then
    e.x = band(x, 0xFFF0) + 8
    e.y = band(y, 0xFFF0) + 8
    e.layer = L
    return true
  end
  return false
end

-- Leever_PlayerInRange: arg 0..31; gSineTable[arg * 8] << 11 per step (8 px)
function M.leeverInRange(E, e, arg)
  local t = targetHome(E, e)
  if not t then return false end
  local a = arg * 8 / 256 * 2 * math.pi
  local sx = math.floor(math.sin(a) * 256 + 0.5) / 32
  local sy = -math.floor(math.cos(a) * 256 + 0.5) / 32
  local x, y = t.x, t.y
  for _ = 1, 8 do
    x, y = x + sx, y + sy
    if not leeverSpot(E, e, t, math.floor(x), math.floor(y)) then return false end
  end
  return true
end

-- sub_0800132C: toward the target unless within 8 px (or on another layer)
local function aimNear(E, e)
  local t = target(E.field)
  if not t or not layersMeet(e, t) then return 0xFF end
  local dx, dy = math.floor(e.x) - math.floor(t.x), math.floor(e.y) - math.floor(t.y)
  if dx + 8 >= 0 and dx + 8 < 0x11 and dy + 8 >= 0 and dy + 8 < 0x11 then return 0xFF end
  return dirTo(e.x, e.y, t.x, t.y)
end

local function leeverMove(E, e) -- Leever_Move
  if not targetHome(E, e) then e.u74 = 1 end
  e.spd = band(e.anim and e.anim.flags or 0, 0xF) * 0x20
  local mask = 0xF
  if (e.form or 0) ~= 0 then e.spd = e.spd + 0x40; mask = 7 end
  local s = e.subtimer or 0
  e.subtimer = band(s + 1, 0xFF)
  if band(s, mask) == 0 then turn(e, aimNear(E, e)) end
  move(E, e, e.dir, e.spd)
end

function M.leeverCollision(E, e, fl)
  if fl == 0x80 and e.action == 3 then e.u74 = 1 end
end

function M.leever(E, e)
  local f = E.field
  e.onCollision = M.leeverCollision
  local a = e.action
  if a == 0 then -- Leever_Initialize
    e.action, e.timer = 1, band(R(f), 0xFF)
    e.dir, e.subtimer = e.dir or 0, 0
    e.hidden = true; colOff(e)
  elseif a == 1 then -- Leever_Idle
    e.timer = dec8(e.timer)
    if e.timer == 0 then
      if M.leeverInRange(E, e, band(R(f), 0x1F)) then
        e.action, e.hidden = 2, false
        e.dir = band(facing(E, e) + M.LEEVER_DRIFT[band(R(f), 1)], 0x1F)
        setAnim(E, e, 0)
      else
        e.timer = band(R(f), 0x18) + 8
      end
    end
  elseif a == 2 then -- Leever_DigUp
    frames(e)
    if done(e) then
      e.action = 3
      e.u74 = (e.form or 0) == 0 and 180 or 110
      setAnim(E, e, 2)
    elseif band(fflags(e), 1) ~= 0 then
      take(e, 1); colOn(e)
    end
  elseif a == 3 then -- Leever_Attack
    leeverMove(E, e)
    frames(e)
    e.u74 = band((e.u74 or 1) - 1, 0xFFFF)
    if e.u74 == 0 then e.action = 4; colOff(e); setAnim(E, e, 1) end
  elseif a == 4 then -- Leever_DigDown
    leeverMove(E, e)
    frames(e)
    if done(e) then e.action, e.timer, e.hidden = 1, 240, true end
  end
end

-- ===========================================================================
-- ACRO_BANDIT
-- ===========================================================================
local function flipBy(e, kd) e.flipX = kd >= 0x10 end -- knockbackDirection < $10 -> flipX 0

-- the knock out of the tower (OnCollision, type 1, action < 7, knockback)
local function acroCollapse(E, e)
  local b = e.child
  if b then
    b.parent = e.parent
    repeat
      b.action = 5
      b.b1 = 1
      if (b.iframes or 0) == 0 then b.iframes = 12 end -- (s8)-12
      b = b.child
    until not b
  end
  if e.parent then e.parent.child = e.child
  elseif e.child then e.parent = e end
  e.action, e.b1 = 9, 1
  flipBy(e, kbDir(e))
  setAnim(E, e, 14)
end

-- sub_08032338 for the kills (the spawner's watch; see the header)
local function acroWatch(E, owner)
  for _, k in ipairs(owner.kids or {}) do
    if k.dying and not k.acroDead then
      k.acroDead = true
      if (k.action or 0) < 7 then acroCollapse(E, k) end
      owner.timer = band((owner.timer or 0) + 15, 0xFF)
      if owner.timer ~= 80 then owner.u6c = 0 end
    end
  end
end

function M.acroCollision(E, e, fl)
  if fl == 0x80 or fl == 0x81 then return end
  if (e.form or 0) == 1 and (e.action or 0) < 7 and (e.kbt or 0) ~= 0 then acroCollapse(E, e) end
  if (e.kbt or 0) ~= 0 and band(fflags(e), 0x10) ~= 0 then
    e.action = (e.form or 0) == 0 and 8 or 9
    flipBy(e, kbDir(e))
    e.b1 = 1
    setAnim(E, e, 14)
  end
end

-- sub_08031E04
local function acroSees(E, e)
  local t = target(E.field)
  if not t then return false end
  local i = band(fflags(e), 6)
  return within(e, math.floor(t.x) + M.ACRO_SIGHT[i], math.floor(t.y) + M.ACRO_SIGHT[i + 1], 0x50)
end

local function acroTower(E, e) -- Type0Action5: the five bandits
  local f = E.field
  local tmp = band(R(f), 3)
  e.kids = {}
  local below
  for t2 = 0, 4 do
    local c = spawnEnemy(E, e, M.ACRO_BANDIT, 1)
    c.type2, c.parent, c.u74lo, c.owner = t2, below, tmp, e
    c.action, c.child = 0, nil
    if below then below.child = c end
    e.kids[#e.kids + 1] = c
    below = c
  end
end

local function acroType0(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then
    e.action = 1
    e.u74, e.u76 = math.floor(e.x), math.floor(e.y)
    e.u79 = band(R(f), 0xFF)
    e.timer = 0
    e.hidden = true; colOff(e)
  elseif a == 1 then
    if e.timer ~= 0 then e.timer = e.timer - 1
    elseif targetHome(E, e) then
      local r = R(f)
      local x = e.u74 + (r % 5) * 0x10 - 0x20
      local y = e.u76 + (rshift(r, 4) % 5) * 0x10 - 0x20
      if not solidAt(f, x, y, e.layer) then
        e.action, e.hidden = 2, false
        e.x, e.y = x, y
        setAnim(E, e, 0)
      end
    end
  elseif a == 2 then
    frames(e)
    if band(fflags(e), 1) ~= 0 then take(e, 0xFF); colOn(e)
    elseif done(e) then
      e.action, e.timer = 3, M.ACRO_LOOK[band(R(f), 7)]
      setAnim(E, e, 1)
    end
  elseif a == 3 then
    if acroSees(E, e) then
      e.action = 5
      local t = target(f)
      e.flipX = not (math.floor(e.x) > math.floor(t.x))
      setAnim(E, e, 3)
    else
      if band(fflags(e), 1) ~= 0 and e.timer ~= 0 then take(e, 1); e.timer = e.timer - 1 end
      frames(e)
      if e.timer == 0 then e.action = 4; colOff(e); setAnim(E, e, 2) end
    end
  elseif a == 4 then
    frames(e)
    if done(e) then e.action, e.timer, e.hidden = 1, M.ACRO_HIDE[band(R(f), 7)], true end
  elseif a == 5 then
    frames(e)
    if done(e) then
      acroTower(E, e)
      e.action, e.timer = 6, 20
      setAnim(E, e, 7)
    elseif band(fflags(e), 1) ~= 0 then
      take(e, 0xFF); colOff(e)
    end
  elseif a == 6 then
    frames(e)
    e.timer = dec8(e.timer)
    if e.timer == 0 then e.action, e.timer, e.hidden = 7, 5, true; colOff(e) end
  elseif a == 7 then
    if band(e.timer, 0xF) == 0 then
      if e.timer == 80 then e.deleted = true
      else e.action, e.timer = 1, 180 end
    end
  elseif a == 8 then
    if done(e) then e.action, e.timer, e.hidden = 1, 180, true
    else
      frames(e)
      if band(fflags(e), 0xF) == 2 then colOff(e) end
    end
  end
end

-- sub_080322E8: the flip follows the direction after 6 frames
local function acroFlipLag(e)
  if (e.u78 or 0) ~= 0 then
    e.u78 = e.u78 - 1
    if e.u78 == 0 then e.flipX = not e.flipX end
  else
    local d = e.dir or 0
    if band(d, 0xF) ~= 0 then
      local want = band(bxor(rshift(band(d, 0xFF), 4), 1), 1) == 1
      if want ~= (e.flipX or false) then e.u78 = 6 end
    end
  end
end

local function acroFall6(E, e) e.action, e.timer = 6, 12; setAnim(E, e, 11) end -- sub_08032290

-- sub_080322A4: the one above has come down onto it
local function acroLanded(E, e)
  local c = e.child
  if c and zhi(c) + 8 >= zhi(e) then
    if zhi(e) ~= 0 then
      e.action = 5
      e.cz = (zhi(c) + 8) * 65536; syncZ(e)
      setAnim(E, e, 11)
    else
      acroFall6(E, e)
    end
    return true
  end
  return false
end

local function acroType1(E, e)
  local f = E.field
  local a = e.action
  local t2 = e.type2 or 0
  if a == 0 then -- AcroBandit_Type1Init
    e.action, e.b1 = 1, 1
    e.czv = 0x40000
    e.cz = (4 - t2) * 0xE * 65536; syncZ(e)
    e.u79 = band(R(f), 0xFF)
    e.u76lo, e.u76hi, e.u78 = 0, 0, 0
    e.hidden = true; colOff(e)
    setAnim(E, e, 4)
  elseif a == 1 then
    e.cz = e.cz - e.czv
    e.czv = e.czv - 0x1800
    syncZ(e)
    if zhi(e) < 1 then
      if e.hidden then sound(f, SFX_12B) end
      e.hidden = false
    end
    if not e.hidden then frames(e) end
    if e.czv <= 0 then e.action = 2; colOn(e); setAnim(E, e, 5) end
  elseif a == 2 then
    gravity(e, M.ACRO_GRAVITY[t2] or 0x1000)
    if t2 * -0xE <= zhi(e) then
      e.action, e.timer = 3, 20
      e.cz = t2 * -0xE * 65536; e.czv = 0; syncZ(e)
      if e.parent then e.b1 = 0 end
      setAnim(E, e, 6)
    end
  elseif a == 3 then
    frames(e)
    if done(e) then
      local go = e.parent ~= nil
      if not go then e.timer = dec8(e.timer); go = e.timer == 0 end
      if go then
        e.action = 4
        e.dir = facing(E, e)
        e.u76lo = 0
        setAnim(E, e, e.child and 9 or 8)
      end
    end
  elseif a == 4 then
    if acroLanded(E, e) then return end
    local p = e.parent
    if not p then
      if targetHome(E, e) then
        e.u79 = band(e.u79 + 1, 0xFF)
        if band(e.u79, 7) == 0 then turn(e, facing(E, e)) end
        e.u76lo = 0
      elseif e.u76lo ~= 0 then
        e.u76lo = e.u76lo - 1
        turn(e, e.u7a or 0)
      else
        e.u76lo = 0x10
        if not selfHome(e) and band(R(f), 1) ~= 0 then e.u7a = homeDir(e)
        else e.u7a = band(R(f), 30) end
      end
      if band(e.dir or 0, 0xF) ~= 0 then e.flipX = band(bxor(rshift(band(e.dir, 0xFF), 4), 1), 1) == 1 end
      move(E, e, e.dir, e.spd or e.speed or 0)
    else
      local spd = e.spd or e.speed or 0
      if e.u76hi == 0 then
        if not within(e, p.x, p.y, 1) then
          e.u76hi = 1
          e.dir = dirTo(e.x, e.y, p.x, p.y)
          acroFlipLag(e)
          linear(e, e.dir, spd)
        end
      else
        e.dir = dirTo(e.x, e.y, p.x, p.y)
        acroFlipLag(e)
        linear(e, e.dir, spd)
        if math.floor(e.x) == math.floor(p.x) and math.floor(e.y) == math.floor(p.y) then e.u76hi = 0 end
      end
    end
    frames(e)
  elseif a == 5 then
    if gravity(e, 0x2000) then return end
    acroFall6(E, e)
  elseif a == 6 then
    if e.timer == 0 then
      e.action = 7
      local d = M.ACRO_FALL[(e.u74lo or 0) * 5 + t2]
      e.dir = d
      e.flipX = d >= 0x10
      e.spd = 0xF0
      e.czv = 0x12000
      e.b1 = 1
      setAnim(E, e, 12)
    end
    if not e.child then
      local q = e.parent
      while q and q ~= e do
        if (q.health or 0) ~= 0 then q.timer = 0 end
        if q.parent == q then break end
        q = q.parent
      end
      e.timer = 0
    end
  elseif a == 7 then
    move(E, e, e.dir, e.spd)
    if bounce(e, 0x2000) == 0 then e.action = 8 end
  elseif a == 8 then
    frames(e)
    if band(fflags(e), 1) ~= 0 then
      take(e, 0xFF)
      if e.anim then e.anim.timer = band(R(f), 0x30) + 30 end -- frameDuration
    elseif done(e) then
      e.action = 9
      setAnim(E, e, 13)
    end
  elseif a == 9 then
    if not gravity(e, 0x1800) then
      if done(e) then
        if e.owner then e.owner.timer = dec8(e.owner.timer) end
        e.deleted = true
      else
        frames(e)
        if band(fflags(e), 0xF) == 2 then colOff(e) end
      end
    end
  end
end

function M.acro(E, e)
  e.onCollision = M.acroCollision
  if (e.form or 0) == 0 then
    acroWatch(E, e)
    return acroType0(E, e)
  end
  if e.owner then acroWatch(E, e.owner) end
  return acroType1(E, e)
end

-- ===========================================================================
-- GHINI
-- ===========================================================================
local function lit(f) return (f.lightLevel or 0x100) >= 0x10 end
local function lantern(f, e) -- sub_0806FD54
  local p = f.player
  if not p.lanternLit then return false end
  return within(e, p.x, p.y - 9, 0x48)
end
local function ghiniSees(E, e) -- sub_0803F5A8
  if not targetHome(E, e) then return false end
  if not lit(E.field) then return lantern(E.field, e) end
  return true
end
local function ghiniFace(E, e) -- sub_0803F66C
  local d = e.dir or 0
  if band(d, 0xF) ~= 0 or e.animState == 0xFF then
    local s = rshift(band(d, 0xFF), 4)
    if s ~= e.animState then e.animState = s; setAnim(E, e, s + 1) end
  end
end
local function ghiniWander(E, e) -- sub_0803F51C / sub_0803F528
  e.action = 4
  local r = R(E.field)
  e.timer = band(r, 8) + 8
  if selfHome(e) then e.dir = band((e.dir or 0) + M.GHINI_TURN[band(r, 7)], 0x1E)
  else e.dir = band(homeDir(e), 0x1E) end
  e.spd = M.GHINI_SPEED[band(rshift(r, 4), 3)]
  e.hitType = 0x24
  ghiniFace(E, e)
end
local function ghiniHide(E, e) e.action = 1; setAnim(E, e, 9) end -- sub_0803F50C
local function ghiniChase(E, e) -- sub_0803F630
  e.action = 5
  e.hitType = 0x25
  e.u78 = M.GHINI_DELAY[band(R(E.field), 3)] + (E.field.playerClones and 0x3C or 0)
end
local function ghiniNotice(E, e) -- sub_0803F5D4
  local f = E.field
  if (e.u7c or 0) ~= 0 then e.u7c = e.u7c - 1
  else
    local t = targetHome(E, e)
    if t and (lantern(f, e) or (lit(f) and inRect(e, t, 0x70, 0x48))) then ghiniChase(E, e) return true end
  end
  return false
end

-- sub_0803F738: Link held at its place
local function ghiniHold(E, e)
  local f = E.field
  local p = f.player
  if p.state ~= "ext" or p.extUpdate ~= e.holdFn then
    e.holdFn = e.holdFn or function(_, input)
      if not input or not input.pressed then return end
      for _, b in ipairs({ "a", "b", "r", "l", "up", "down", "left", "right" }) do
        if input.pressed(b) then f.ghiniPress = true end
      end
    end
    p.state, p.extUpdate = "ext", e.holdFn
  end
  p.ghini = e
  p.x, p.y = e.x, e.y + 1
  e.noTouch = true -- Link's ENT_COLLIDE is off while captured (sub_0803F6EC sets it back)
end
-- sub_0803F6EC: Link let go (a hop)
local function ghiniRelease(E, e)
  local f = E.field
  local p = f.player
  e.noTouch = nil
  if p.ghini ~= e then return end
  p.ghini = nil
  if (f.save.stats.health or 0) ~= 0 then
    p.state, p.extUpdate = "normal", nil
    p.z, p.zv, p.jumping = 2, 1.5, true
    p.invuln = 0x3C
  end
end

function M.ghiniCollision(E, e, fl)
  if (fl == 0x80 or fl == 0x81) and E.field.player.ghini == e then return end -- captured: no body contact
  if e.action == 8 or e.action == 9 then
    e.animState = 0xFF
    setAnim(E, e, bxor(rshift(kbDir(e), 4), 1) + 1)
    ghiniChase(E, e)
    ghiniRelease(E, e)
  end
  if e.hitType == 0x25 and fl == 0x80 then
    e.action = 8
    setAnim(E, e, 3)
  else
    if fl == 0x80 + 0x1D then e.czv = 0x18000 end
    if e.health ~= e.u7a then
      e.u7a = e.health
      if e.action == 1 or e.action == 2 then ghiniWander(E, e) end
      setAnim(E, e, rshift(kbDir(e), 4) + 7)
      e.ghKb = true
    end
  end
end

function M.ghiniGrabbed(E, e) -- Ghini_SubAction0
  local p = E.field.player
  e.jarTol = 0x3C
  setAnim(E, e, rshift(p.animationState or 0, 2) + 5)
end
function M.ghiniJarLost(E, e) -- Ghini_OnGrabbed: sub_0806F520 false
  ghiniWander(E, e)
  setAnim(E, e, rshift(band(e.dir or 0, 0xFF), 4) + 1)
end

function M.ghini(E, e)
  local f = E.field
  e.onCollision = M.ghiniCollision
  e.onGrabbed, e.onJarLost = M.ghiniGrabbed, M.ghiniJarLost
  -- Ghini_OnKnockback's end: the walk animation again
  if e.ghKb and (e.kbt or 0) == 0 then
    e.ghKb = nil
    if (e.health or 0) ~= 0 then
      e.animState = 0xFF
      if e.animIndex == 7 or e.animIndex == 8 then setAnim(E, e, bxor(e.animIndex - 7, 1) + 1) end
    end
  end
  local a = e.action
  if a == 0 then -- Ghini_Init
    local r = R(f)
    e.dir = band(r, 0x1E)
    e.animState = 0xFF
    e.gustJarFlags = 1
    e.u7a = e.health
    e.u7b = band(rshift(r, 4), 0xFF)
    e.u7c = 0
    e.cz, e.czv = 0, 0
    if (e.form or 0) ~= 0 then ghiniHide(E, e)
    else ghiniWander(E, e); setAnim(E, e, rshift(e.dir, 4) + 1) end
  elseif a == 1 then
    if ghiniSees(E, e) then e.action, e.timer = 2, band(R(f), 0x60) + 10 end
  elseif a == 2 then
    if not ghiniSees(E, e) then ghiniHide(E, e)
    else
      e.timer = dec8(e.timer)
      if e.timer == 0 then
        e.action, e.timer = 3, 30
        local t = target(f)
        if t then e.dir = dirTo(e.x, e.y, t.x, t.y) else e.dir = band(R(f), 0x1F) end
        e.animState = rshift(e.dir, 4)
        setAnim(E, e, e.animState + 1)
      end
    end
  elseif a == 3 then
    frames(e)
    e.timer = dec8(e.timer)
    if e.timer == 0 then ghiniWander(E, e) end
  elseif a == 4 then
    if not ghiniNotice(E, e) then
      local y0 = e.y -- sub_0803F58C
      linear(e, e.dir, e.spd)
      e.y = e.y - (e.y - y0) / 2
      frames(e)
      e.timer = dec8(e.timer)
      if e.timer == 0 then ghiniWander(E, e) end
    end
  elseif a == 5 then
    frames(e)
    e.dir = facing(E, e)
    if e.dir ~= 0xFF then
      ghiniFace(E, e)
      e.u78 = band((e.u78 or 1) - 1, 0xFFFF)
      if e.u78 == 0 then e.action, e.spd = 6, 0x100 end
    else
      ghiniWander(E, e)
    end
  elseif a == 6 then
    if not ghiniSees(E, e) then ghiniWander(E, e)
    else
      local t = target(f)
      if t then
        local tmp = band((e.timer or 0) + 1, 0xFF)
        e.timer = tmp
        if band(tmp, M.GHINI_TURN_MASK[rshift(tmp, 6)]) == 0 then turn(e, dirTo(e.x, e.y, t.x, t.y)) end
        ghiniFace(E, e)
        linear(e, e.dir, e.spd)
        frames(e)
      else
        e.action, e.timer = 7, 30
      end
    end
  elseif a == 7 then
    frames(e)
    e.timer = dec8(e.timer)
    if e.timer == 0 then ghiniWander(E, e) end
  elseif a == 8 then
    ghiniHold(E, e)
    frames(e)
    if done(e) then
      e.action = 9
      colOn(e)
      e.noTouch = true -- (still holding Link)
      e.u78 = 0
      setAnim(E, e, 4)
    end
  elseif a == 9 then
    frames(e)
    local p = f.player
    if band(fflags(e), 1) ~= 0 then -- sub_0803F6C0
      take(e, 1)
      p.invuln = 0xC
      if f.modStat then f:modStat("health", -4) end
      sound(f, SFX_PLY_VO6)
    end
    if f.ghiniPress then f.ghiniPress = nil; e.u78 = e.u78 + 0xC end
    if (f.save.stats.health or 0) == 0 then e.u78 = 0xE0 end
    e.u78 = band(e.u78 + 1, 0xFFFF)
    if e.u78 >= 0xE0 then
      e.u7c = 0x78
      e.animState = 0xFF
      e.iframes = 0xC
      local kd = bxor(lshift(p.animationState or 0, 2), 0x10)
      local vx, vy = dirVec(kd)
      local s = 0x180 / 256
      e.kbx, e.kby, e.kbt, e.kbDir = vx * s, vy * s, 0x14, kd
      ghiniWander(E, e)
      ghiniRelease(E, e)
    else
      ghiniHold(E, e)
    end
  end
  -- sub_0803F694: the bob
  e.cz = M.GHINI_BOB[band(rshift(e.u7b or 0, 3), 3)] * 65536; syncZ(e)
  e.u7b = band((e.u7b or 0) + 1, 0xFF)
end

-- ===========================================================================
-- CROW
-- ===========================================================================
local function crowAnim(E, e) setAnim(E, e, rshift(band(e.dir or 0, 0x10), 4) + (e.u81 or 0)) end -- sub_08032AF4

local function crowFly(e) -- sub_08032B10
  linear(e, e.dir, e.spd)
end

function M.crowCollision(E, e, fl)
  if band(fl, 0x80) ~= 0 then
    if band(fl, 0x3F) == 0 then
      colOff(e)
      e.subtimer = 16
      if band(band((e.dir or 0) + 4, 0x18), 0x08) == 0 then
        if band(e.dir or 0, 0x10) ~= 0 then e.dir = (e.dir or 0) + 2 else e.dir = (e.dir or 0) - 2 end
      end
      e.dir = band(0x20 - e.dir, 0xFF)
      crowAnim(E, e)
    elseif band(e.iframes or 0, 0x80) == 0 then
      e.health = 0
      E:kill(e)
    end
  end
  frames(e)
end

function M.crowJarLost(E, e) -- Crow_OnGrabbed: let go
  e.action, e.u84, e.timer, e.spd = 2, 2, 8, 0x1C0
  crowAnim(E, e)
end

local function crowRetarget(E, e) -- sub_08032AB0
  e.timer = dec8(e.timer)
  if e.timer ~= 0 then return end
  e.u80 = e.dir or 0
  local d = facing(E, e)
  if d ~= 0xFF then e.dir = d end
  e.timer = 8
  if band(e.u80, 0x10) ~= band(e.dir or 0, 0x10) then crowAnim(E, e) end
end

local function crowAttack(E, e) -- sub_08032B38
  local u = e.u84 or 0
  if u == 0 then
    if band(e.timer, 1) ~= 0 then e.cz = (e.cz or 0) - 65536; syncZ(e) end
    e.timer = dec8(e.timer)
    if e.timer == 0 then
      e.u84, e.timer = 1, 24
      colOn(e)
      e.u81 = 2
      crowAnim(E, e)
    end
  elseif u == 1 then
    e.timer = dec8(e.timer)
    if e.timer == 0 then
      e.u84, e.timer, e.spd, e.u81 = 2, 8, 0x1C0, 4
      crowAnim(E, e)
    end
  else
    e.u82 = band((e.u82 or 0) - 1, 0xFFFF)
    if e.u82 == 0 then
      e.action, e.u84, e.timer, e.spd = 3, 0, 0, 0x180
      if band((e.dir or 0) + 0x18, 0x10) ~= 0 then e.dir = band(0x10 - e.dir, 0x1F) end
      crowAnim(E, e)
    else
      e.timer = dec8(e.timer)
      if e.timer == 0 then
        e.timer = 8
        e.u80 = e.dir or 0
        turn(e, facing(E, e))
        if band(e.dir + 0x18, 0x10) ~= 0 then
          if e.u80 == 0x10 then
            if band(e.dir, e.u80) ~= 0 then e.u80 = 0x12 else e.u80 = 0xE end
          end
          e.dir = e.u80
          e.u82 = 1
        end
        if rshift(band(e.u80, 0x10), 4) ~= rshift(band(e.dir, 0x10), 4) then
          setAnim(E, e, rshift(band(e.dir, 0x10), 4) + 4)
        end
      end
      crowFly(e)
    end
  end
  frames(e)
end

function M.crow(E, e)
  local f = E.field
  e.onCollision = M.crowCollision
  e.onJarLost = M.crowJarLost
  local a = e.action
  if a == 0 then -- sub_08032928
    e.action, e.subtimer = 1, 0
    e.dir = facing(E, e)
    e.u80, e.u81, e.u82, e.u84 = 0, 0, 0, 0
    e.gustJarFlags = 1
    e.u78, e.u7a = math.floor(e.x), math.floor(e.y)
    e.cz, e.czv = e.cz or 0, 0
    colOff(e)
    crowAnim(E, e)
  elseif a == 1 then -- sub_0803298C
    crowRetarget(E, e)
    frames(e)
    local t = target(f)
    if t and inRect(e, t, 0x88, 0x50) and math.floor(t.y) > math.floor(e.y) + 8 then
      e.action, e.u84, e.timer, e.u81 = 2, 0, 16, 2
      crowAnim(E, e)
    end
  elseif a == 2 then
    crowAttack(E, e)
  elseif a == 3 then -- sub_080329F0
    if not onScreen(f, e) then
      e.action, e.hidden = 4, true
      colOff(e)
      e.x, e.y = e.u78, e.u7a
      e.cz = (e.cz or 0) + 8 * 65536; syncZ(e)
      e.b1 = 1
    else
      crowFly(e)
      frames(e)
    end
  elseif a == 4 then -- sub_08032A48
    if not onScreen(f, e) then
      e.action, e.hidden = 1, false
      colOff(e)
      e.timer = 8
      e.dir = facing(E, e)
      e.u80, e.u81, e.b1 = 0, 0, 3
      crowAnim(E, e)
    end
  end
  -- Crow_OnTick: the glance-off's 16 frames
  if (e.subtimer or 0) ~= 0 then
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then colOn(e) end
  end
end

-- ===========================================================================
-- KEATON
-- ===========================================================================
local function keatonFace(E, e, dir) -- sub_0803269C
  local s = rshift(band(dir + 4, 0x18), 3)
  local base = band(e.animIndex or 0, 0xFC)
  if band(dir - 3, 7) < 3 then
    if band((e.animState or 0) - s, 3) > 1 then e.animState = s; setAnim(E, e, base + s) end
  elseif s ~= e.animState then
    e.animState = s; setAnim(E, e, base + s)
  end
end
local function keatonWalkPick(E, e) -- sub_08032650
  local r = R(E.field)
  e.timer = M.KEATON_WALK[band(r, 0xF)]
  if not (not selfHome(e) and band(rshift(r, 8), 1) == 0) then e.dir = band(rshift(r, 16), 0x18)
  else e.dir = band(homeDir(e) + 4, 0x18) end
  keatonFace(E, e, e.dir)
end
local function keatonRestTime(E, e) e.u74 = M.KEATON_REST[band(R(E.field), 0xF)] end -- sub_080326FC
local function keatonWalk(E, e) -- sub_08032740
  e.action, e.spd = 1, 0x80
  setAnim(E, e, e.animState or 0)
  keatonWalkPick(E, e)
end
local function keatonDrop(e) e.dagger = nil end -- sub_080327E0
local function keatonStop(E, e) -- sub_0803275C
  e.action, e.timer, e.spd = 5, 45, 0x80
  setAnim(E, e, e.animState or 0)
  keatonFace(E, e, e.dir or 0)
  keatonDrop(e)
end
local function keatonRest(E, e) e.action = 2; setAnim(E, e, (e.animState or 0) + 8) end -- sub_08032784
local function keatonSees(E, e) -- sub_080325E8
  local t = targetHome(E, e)
  if selfHome(e) and t and inRect(e, t, 0x68, 0x40) then
    local fd = band(e.anim and e.anim.flags or 0, 0x18)
    if band(dirTo(e.x, e.y, t.x, t.y) - fd + 2, 0x1F) < 5 then
      e.action, e.timer, e.dir = 3, 12, fd
      return true
    end
  end
  return false
end
local function keatonDash(E, e) -- sub_08032794
  local s = (e.animState or 0) * 2
  fx(E.field, e.x + M.KEATON_DASH[s], e.y + M.KEATON_DASH[s + 1], FX_DASH)
end

-- StealRupees (takkuri.c)
function M.stealRupees(f)
  local t = target(f)
  if not t then return 0 end
  local rupees = f.save.stats.rupees or 0
  local item, n, cost
  if rupees >= 500 then item, n, cost = ITEM_RUPEE20, 5, 100
  elseif rupees >= 100 then item, n, cost = ITEM_RUPEE5, 5, 25
  else item = ITEM_RUPEE1; n = math.min(rupees, 5); cost = n end
  if f.modStat then f:modStat("rupees", -cost) else f.save.stats.rupees = rupees - cost end
  local O = f.objects and f:objects()
  for _ = 1, n do
    if O and O.groundItem then O:groundItem(item, 0, t.x, t.y, { drop = true }) end
  end
  return n, item
end

-- the KEATON_DAGGER's contact with Link this frame
local function daggerTouch(E, e)
  local f = E.field
  local p = f.player
  if not p or p.state == "dead" or (p.invuln or 0) > 0 then return false end
  local hb = M.DAGGER_HB[band(e.animState or 0, 3)]
  return math.abs((e.x + hb.x) - p.x) < hb.w + 5 and math.abs((e.y + hb.y) - (p.y - 3)) < hb.h + 6
end
local function daggerHit(E, e)
  local f = E.field
  local p = f.player
  local defs = f.assets and f.assets.manifest and f.assets.manifest.projectileDefs
  local d = defs and defs[KEATON_DAGGER]
  if d and d.multi then d = d.forms[0] end
  local s = d and E.settings and E:settings(d.damageType or 0, 0)
  if p.hurt then p:hurt(math.max(s and s.tgtDmg or 4, 1), e.x, e.y) end
  M.stealRupees(f)
end

function M.keatonCollision(E, e, fl)
  if e.action ~= 3 and e.action ~= 4 then
    e.action, e.timer = 3, 12
    e.dir = bxor(band(kbDir(e) + 4, 0x18), 0x10)
    setAnim(E, e, rshift(e.dir, 3))
  elseif fl == 0xCC then
    keatonStop(E, e)
  end
end

function M.keaton(E, e)
  local f = E.field
  e.onCollision = M.keatonCollision
  local a = e.action
  if a == 0 then -- Keaton_Init
    e.animState = 0
    setAnim(E, e, 0)
    keatonRestTime(E, e)
    keatonWalk(E, e)
  elseif a == 1 then
    if not keatonSees(E, e) then
      e.u74 = band((e.u74 or 1) - 1, 0xFFFF)
      if e.u74 == 0 then keatonRest(E, e) return end
      e.timer = dec8(e.timer)
      if e.timer == 0 then keatonWalkPick(E, e) end
      if not move(E, e, e.dir, e.spd) then e.timer = 1 end
      frames(e)
    end
  elseif a == 2 then
    if not keatonSees(E, e) then
      frames(e)
      if done(e) then keatonRestTime(E, e); keatonWalk(E, e) end
    end
  elseif a == 3 then
    if e.timer ~= 0 then
      e.timer = e.timer - 1
      if e.timer ~= 0 then return end
      e.subtimer = 30
      e.animState = rshift(e.dir, 3)
      setAnim(E, e, e.animState + 4)
    end
    frames(e, 2)
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then
      e.action, e.spd, e.u76, e.u78, e.u7b = 4, 0x1E0, 0x46, 0, 0
      e.dagger = true -- sub_080327C8
    elseif band(e.subtimer, 3) == 0 then
      keatonDash(E, e)
    end
  elseif a == 4 then
    if e.dagger and daggerTouch(E, e) then
      keatonStop(E, e)
      daggerHit(E, e)
      return
    end
    e.u76 = e.u76 - 1
    if e.u76 == 0 or not move(E, e, e.dir, e.spd) then keatonStop(E, e) return end
    frames(e)
    if band(e.u76, 7) == 0 then keatonDash(E, e) end
  elseif a == 5 then
    e.timer = dec8(e.timer)
    if e.timer == 0 and not keatonSees(E, e) then keatonRest(E, e) end
  end
end

-- ===========================================================================
-- ROCK_CHUCHU
-- ===========================================================================
local ROCK_SWORD = { [4] = true, [5] = true, [6] = true, [8] = true, [9] = true, [0xA] = true, [0xB] = true,
                     [0xC] = true, [0xD] = true, [0x10] = true, [0x11] = true, [0x12] = true,
                     [0x18] = true, [0x19] = true, [0x1A] = true }
M.ROCK_SWORD = ROCK_SWORD

function M.rockCollision(E, e, fl)
  local f = E.field
  if (e.health or 0) ~= 0 then
    local k = band(fl, 0x7F)
    local breaks = k == 0x16 or k == 0x1C
    if ROCK_SWORD[k] and f.inventory and f:inventory(ITEM_SKILL_ROCK_BREAKER) ~= 0 then breaks = true end
    if breaks and e.action ~= 2 then
      fx(f, e.x, e.y, FX_ROCK)
      local c = spawnEnemy(E, e, CHUCHU, 1)
      c.spawnB = 1 -- type2 1: straight to action 3 (EnemyCoF3)
      c.iframes = 8
      e.action = 2
      colOff(e)
      e.hidden = true
      e.dir = kbDir(e)
      e.rockChild = c
    end
  elseif e.hitType ~= 0x94 then
    setAnim(E, e, 2)
  end
end

function M.rock(E, e)
  local f = E.field
  e.onCollision = M.rockCollision
  local a = e.action
  if a == 0 then -- sub_08022368
    e.action, e.timer = 1, band(R(f), 0xFF)
    e.dir = facing(E, e)
    e.subtimer = 0
    setAnim(E, e, 0)
  elseif a == 1 then -- sub_08022390
    if targetHome(E, e) then
      local t = e.timer
      e.timer = band(t + 1, 0xFF)
      if band(t, 0xF) == 0 then
        e.dir = facing(E, e)
        e.subtimer = band(R(f), 4)
      end
      if e.subtimer == 0 then move(E, e, e.dir, e.spd or e.speed or 0)
      else e.subtimer = e.subtimer - 1 end
    else
      e.timer = band(R(f), 0xFF)
    end
    frames(e)
  elseif a == 2 then -- sub_080223E4
    local c = e.rockChild
    if c and not c.deleted and not c.dying then
      if (c.action or 0) == 0 then require("src.zelda.tmc.EnemyCoF3").update(E, c) end
      if c.onCollision then c.onCollision(E, c, 0x80 + 0x14) end
      c.iframes = 0x10
      local vx, vy = dirVec(e.dir or 0)
      local s = 24 * 16 / 256 -- (the ChuChu's knockbackSpeed is not set here: the port's default 24)
      c.kbx, c.kby, c.kbt, c.kbDir = vx * s, vy * s, 0xC, e.dir
    end
    e.deleted = true
  end
end

-- ===========================================================================
-- SCISSORS_BEETLE + MANDIBLES_PROJECTILE
-- ===========================================================================
local function sbAnim(E, e, shift) -- sub_08038C84 (beetle: shift; mandibles: none)
  local s = bor(e.animState or 0, lshift(e.u82 or 0, 3))
  if shift then s = rshift(s, 1) end
  setAnim(E, e, s)
end
local function mandPos(m, b) -- sub_080AA1D8's PositionRelative (see the header)
  local i = band(b.animState or 0, 6)
  m.x, m.y, m.layer = b.x + M.MAND_OFF[i], b.y + M.MAND_OFF[i + 1], b.layer
end
local function mandSet(E, m, s) m.animState = s; m.hitbox = M.MAND_HB[s]; sbAnim(E, m, false) end
local function mandPick(E, m) -- sub_080AA270
  local b = m.parent
  m.subtimer = M.MAND_TIME[band(R(E.field), 7)]
  local s = b and b.animState or 0
  if m.animState == 0xFF then mandSet(E, m, s)
  else
    s = band(M.MAND_TURN[band(R(E.field), 7)] + s, 7)
    if s ~= m.animState then mandSet(E, m, s) end
  end
end
local function sbBeetlePick(E, e) -- sub_08038BA8
  e.subtimer = M.SB_WALK[band(R(E.field), 7)]
  e.u82 = 1
  local m = e.child
  if m then m.u82 = 0 end
  if (e.u7a or 0) == 0 then
    e.u7a = 1
    e.dir = lshift(e.animState, 2)
    sbAnim(E, e, true)
    return
  end
  local r3
  local ms = m and m.animState or 0
  if band(ms, 1) ~= 0 then
    r3 = (ms == band(e.animState + 1, 7)) and 2 or 6
    r3 = band(r3 + e.animState, 6)
  else
    r3 = ms
  end
  if r3 ~= e.animState then
    e.animState = r3
    e.dir = lshift(r3, 2)
    sbAnim(E, e, true)
  end
end
local function sbMandPick(E, m) -- sub_08038C2C
  m.subtimer = M.SB_MAND[band(R(E.field), 7)]
  local ps = m.parent and m.parent.animState or 0
  if m.animState == 0xFF then m.animState = ps; sbAnim(E, m, false) return end
  ps = band(M.SB_TURN[band(R(E.field), 7)] + ps, 7)
  if ps ~= m.animState then m.animState = ps; sbAnim(E, m, false) end
end
local function sbStep(E, e) -- sub_08038B90
  frames(e)
  move(E, e, e.dir, e.spd or 0)
end
local function mandAttack(E, m) -- sub_080AA320
  local b = m.parent
  m.action, m.u82, m.subtimer = 2, 1, 0
  b.action, b.subtimer, b.u80, b.spd = 2, 48, 0x50, 0
  local t = target0(E.field)
  b.dir = t and dirTo(b.x, b.y, t.x, t.y) or 0xFF
  local u = band(b.dir + 4, 0x1C)
  m.animState = rshift(u, 2)
  b.animState = rshift(band(u, 0x18), 2)
  sbAnim(E, b, true)
  mandPos(m, b)
end
local function mandSees(E, m) -- sub_080AA2E0
  local t = target0(E.field)
  if not t then return false end
  local a = dirTo(m.x, m.y, t.x, t.y)
  local b = (m.animState or 0) * 4
  if band(a + 4, 0x1C) ~= band(b + 4, 0x1C) then return false end
  if not layersMeet(m, t) then return false end
  return within(m, t.x, t.y, 0x40)
end

function M.mandCollision(E, m, fl)
  if band(fl, 0x80) == 0 then return end
  local f = E.field
  if m.action == 4 then
    m.subtimer = 0
    if f.modStat then f:modStat("health", -2) end
    frames(m)
  elseif m.action == 3 then
    -- (confusion only)
  else
    local b = m.parent
    if b then
      b.iframes = m.iframes
      b.kbx, b.kby, b.kbt, b.kbDir = m.kbx, m.kby, m.kbt, m.kbDir
      if m.action == 1 then mandAttack(E, m) end
    end
  end
  m.kbt = 0
  m.health = 0xFF
end

local function mandibles(E, m)
  local f = E.field
  m.onCollision = M.mandCollision
  m.health = 0xFF
  colOn(m)
  if (m.action or 0) < 3 then -- sub_080AA1D8
    local b = m.parent
    if not b or b.deleted or b.dying then m.deleted = true return end
    mandPos(m, b)
  end
  local a = m.action
  if a == 0 then
    m.action, m.u80, m.animState, m.u82 = 1, 0, 0xFF, 0
    mandPick(E, m)
  elseif a == 1 then
    if (m.u80 or 0) ~= 0 then m.u80 = m.u80 - 1
    else
      m.subtimer = dec8(m.subtimer)
      if m.subtimer == 0 then mandPick(E, m)
      elseif mandSees(E, m) then mandAttack(E, m) end
    end
    frames(m)
  elseif a == 2 then
    frames(m)
    if band(fflags(m), 0x40) ~= 0 then take(m, 0x40); sound(f, SFX_15D) end
  elseif a == 3 then
    local b = m.child
    if not b or b.deleted then m.deleted = true return end
    mandPos(m, b)
    if (m.subtimer or 0) ~= 0 then m.subtimer = m.subtimer - 1
    else
      frames(m)
      if done(m) then
        m.action, m.u82, m.subtimer = 4, 3, 64
        m.dir = lshift(b.animState or 0, 2)
        m.animState = band(b.animState or 0, 0x3F)
        sbAnim(E, m, false)
      end
    end
  elseif a == 4 then
    local b = m.child
    if b then
      if b.deleted then m.child = nil end
      if (m.subtimer or 0) ~= 0 then m.subtimer = m.subtimer - 1
      else
        -- sub_080AA374: home on the beetle's mouth
        local i = band(b.animState or 0, 6)
        local hx, hy = b.x + M.MAND_OFF[i], b.y + M.MAND_OFF[i + 1]
        if m.child and within(m, hx, hy, 8) then
          if (b.health or 0) == 0 or b.dying then m.deleted = true return end
          sound(f, SFX_F2)
          m.action, m.animState, m.u82, m.timer, m.u80 = 1, 0xFF, 0, 0, 0x20
          m.parent, m.child = b, nil
          mandPick(E, m)
          b.action = 1
          b.dir = lshift(b.animState or 0, 2)
          b.spd, b.u82, b.timer, b.subtimer, b.u80 = 0, 1, 0, 120, 0x20
          sbAnim(E, b, true)
        elseif m.child then
          turn(m, dirTo(m.x, m.y, hx, hy))
        end
      end
    elseif not onScreen(f, m) then
      m.deleted = true
      return
    end
    linear(m, m.dir, m.spd)
    frames(m)
  end
end

local function makeMandibles(E, e)
  local f = E.field
  local defs = f.assets and f.assets.manifest and f.assets.manifest.projectileDefs
  local d = defs and defs[MANDIBLES_PROJECTILE]
  if d and d.multi then d = d.forms[0] end
  local m = { kind = 3, id = M.SCISSORS_BEETLE, form = 0, mandibles = true, x = e.x, y = e.y, z = 0, zv = 0,
              layer = e.layer, health = 0xFF, maxHealth = 0xFF, hitType = d and d.damageType or e.hitType,
              hitbox = M.MAND_HB[0], anim = require("src.zelda.tmc.Anim").new(), animationState = 0,
              action = 0, timer = 0, iframes = 0, kbt = 0, enemy = true, literalAnim = true, field82 = 0,
              interactType = 0, def = e.def or {}, spd = d and d.speed or 0x200,
              homeX = e.homeX, homeY = e.homeY, rangeW = e.rangeW, rangeH = e.rangeH, collideOn = true }
  if d and E.A and E.A.objPalette then
    m.sprite = d.sprite
    m.palette = E.A:objPalette(d.palette or 0, f.room.atlas and f.room.atlas.palettes)
    local ok, Assets = pcall(require, "src.zelda.tmc.Assets")
    m.gfx = (ok and (d.gfx or 0) ~= 0) and Assets.gfxSource("enemy", d.gfx) or e.gfx
  else
    m.sprite, m.palette, m.gfx = e.sprite, e.palette, e.gfx
    m.hiddenArt = true
  end
  f.entities[#f.entities + 1] = m
  return m
end

function M.sbCollision(E, e, fl)
  if band(fl, 0x80) == 0 or e.action == 4 then return end
  local m = e.child
  if not m then return end
  m.iframes = e.iframes
  local kd = kbDir(e)
  m.kbDir = kd
  if e.action == 1 then
    m.dir = band(kd + 0x12, 0x1C)
    m.animState = rshift(m.dir, 2)
    e.dir = band(kd + 0x14, 0x18)
    e.animState = rshift(e.dir, 2)
    sbAnim(E, e, true)
    sbAnim(E, m, false)
  end
end

function M.scissors(E, e)
  if e.mandibles then return mandibles(E, e) end
  local f = E.field
  e.onCollision = M.sbCollision
  local a = e.action
  if a == 0 then -- ScissorsBeetle_Init
    local m = makeMandibles(E, e)
    e.action, e.hidden = 1, false
    colOn(e)
    e.child = m
    e.animState = band(R(f), 6)
    e.u80, e.u7a = 0, 0
    e.spd = e.spd or e.speed or 0x80
    m.parent, m.form, m.animState = e, 0, 0xFF
    sbBeetlePick(E, e)
  elseif a == 1 then -- sub_080389E8
    local m = e.child
    if (e.u80 or 0) ~= 0 then
      e.u80 = e.u80 - 1
      if e.u80 == 0 then e.spd = 0x80 end
    else
      e.subtimer = dec8(e.subtimer)
      if e.subtimer == 0 then sbBeetlePick(E, e); if m then sbMandPick(E, m) end
      elseif (e.timer or 0) ~= 0 then e.timer = e.timer - 1
      elseif e.lastHit then
        e.timer = 12
        if m and band(m.animState or 0, 1) == 0 then
          m.animState = band(m.animState + ((band(R(f), 0x20) ~= 0) and 1 or 7), 7)
        end
        sbBeetlePick(E, e)
        if m then sbMandPick(E, m) end
      end
    end
    sbStep(E, e)
  elseif a == 2 then -- sub_08038A70
    local m = e.child
    e.u80 = band((e.u80 or 1) - 1, 0xFFFF)
    if e.u80 == 0 then
      e.action, e.u82, e.spd, e.subtimer = 3, 4, 0x80, 32
      if m then
        m.action, m.u82, m.animState = 3, 2, 0xFF
        sbAnim(E, e, true)
        sbMandPick(E, m)
        m.subtimer = 32
        m.parent, m.child = nil, e
      else
        sbAnim(E, e, true)
      end
    else
      e.subtimer = dec8(e.subtimer)
      if e.subtimer == 0 then
        e.subtimer = 16
        local t = target0(f)
        e.dir = t and dirTo(e.x, e.y, t.x, t.y) or 0xFF
        local d = band(e.dir + 4, 0x1C)
        if m then m.animState = rshift(d, 2) end
        e.animState = rshift(band(d, 0x18), 2)
        sbAnim(E, e, true)
        if m then sbAnim(E, m, false) end
      end
    end
    sbStep(E, e)
  elseif a == 3 then -- sub_08038B08
    if (e.subtimer or 0) ~= 0 then e.subtimer = e.subtimer - 1 return end
    frames(e)
    if done(e) then
      e.action, e.u82, e.timer, e.subtimer = 4, 3, 50, 2
      e.dir = band(lshift(e.animState, 2) + 0x10, 0x1F)
      e.spd = 0x80
      sbAnim(E, e, true)
      sound(f, SFX_15B)
    end
  elseif a == 4 then -- sub_08038B64
    move(E, e, e.dir, e.spd)
    frames(e)
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then
      e.subtimer = 2
      e.dir = band(e.dir + 0x1F, 0x1F)
    end
  end
end

-- ===========================================================================
-- CUCCO_AGGR
-- ===========================================================================
local function cuccoFlip(e) if band(e.dir or 0, 0xF) ~= 0 then e.flipX = rshift(band(e.dir, 0xFF), 4) == 0 end end -- sub_080390F8
local function cuccoFx(E, e) -- CuccoAggr_CreateFx
  fx(E.field, e.x + M.CUCCO_FX_X[e.flipX and 1 or 0], e.y, M.CUCCO_FX[e.form or 0] or FX_EGG)
end
local function cuccoHopDir(E, e) -- sub_080390C0
  local r = R(E.field)
  if selfHome(e) and band(r, 1) ~= 0 then e.dir = band(rshift(r, 16), 0x1C)
  else e.dir = band(homeDir(e) + 2, 0x1C) end
  cuccoFlip(e)
end
local function cuccoNext(E, e) -- sub_0803901C
  local f = E.field
  local r3 = R(f)
  local r5 = band(r3, 3)
  if r3 == 3 then -- the cartridge's bug: r3, not r5
    if e.action == 3 then r5 = 1 elseif e.action == 4 then r5 = 2 else r5 = 0 end
  end
  if r5 == 1 then
    e.action = 3
    e.timer = band(rshift(r3, 8), 3) + 2
    e.czv = 0x8000
    cuccoHopDir(E, e)
    setAnim(E, e, 1)
    if band(R(f), 1) ~= 0 then sound(f, SFX_VO_CUCCO1 + band(R(f), 1)) end
  elseif r5 == 2 then
    e.action = 4
    setAnim(E, e, band(rshift(r3, 16), 1) + 2)
  else
    e.action = 1
    e.timer = M.CUCCO_IDLE[band(rshift(r3, 16), 3)]
    setAnim(E, e, 0)
  end
end
local function cuccoCalm(E, e) -- sub_08039120
  e.spd = M.CUCCO_SPEED[e.form or 0] or 0x80
  e.u7a = 0
  cuccoNext(E, e)
end
local function cuccoFlee(E, e) -- sub_08039218
  e.action = 5
  e.spd = M.CUCCO_FLEE_SPEED[e.form or 0]
  e.u78 = M.CUCCO_FLEE_TIME[e.form or 0]
  if e.animIndex ~= 4 then setAnim(E, e, 4) end
  sound(E.field, SFX_VO_CUCCO4)
end
local function cuccoAttack(E, e) -- sub_08039140 (type 2)
  local f = E.field
  e.action = 6
  e.timer = band(R(f), 0xFF)
  local p = f.player
  e.dir = dirTo(e.x, e.y, p.x, p.y)
  e.cz = -4 * 65536; syncZ(e)
  e.u78 = 0xB4
  e.spd = e.spd or e.speed or 0
  cuccoFlip(e)
  setAnim(E, e, 4)
end
-- CuccoAggr_IsOutsideScroll
local function outsideScroll(f, e)
  local x = math.floor(e.x) - 0xC - math.floor(f.camX or 0)
  local y = math.floor(e.y) - 0xC - math.floor(f.camY or 0)
  return x < 0 or x > 0x108 or y < 0 or y > 0xB8
end

function M.cuccoCollision(E, e, fl)
  local f = E.field
  if (e.form or 0) ~= 2 then
    if (e.u7a or 0) == 0 and not (f.flag and f:flag("room", 1)) then
      if (e.health or 0) <= 0xBF then e.u7a = 1 end
    else
      e.health = 0xFF
    end
    cuccoFlee(E, e)
    cuccoFx(E, e)
  end
end

function M.cucco(E, e)
  local f = E.field
  e.onCollision = M.cuccoCollision
  local a = e.action
  if a == 0 then -- sub_08038D78
    if (e.form or 0) ~= 2 then
      e.type2 = 0
      cuccoCalm(E, e)
    else
      cuccoAttack(E, e)
    end
  elseif a == 1 then
    e.timer = dec8(e.timer)
    if e.timer == 0 then cuccoNext(E, e) end
  elseif a == 3 then
    move(E, e, e.dir, e.spd)
    frames(e)
    if not gravity(e, 0x1C00) then
      e.timer = dec8(e.timer)
      if e.timer == 0 then cuccoNext(E, e) else e.czv = 0x8000 end
    end
  elseif a == 4 then
    frames(e)
    if done(e) then cuccoNext(E, e) end
  elseif a == 5 then
    local p = f.player
    e.dir = dirTo(p.x, p.y, e.x, e.y)
    cuccoFlip(e)
    move(E, e, e.dir, e.spd)
    bounce(e, 0x1800)
    frames(e)
    e.u78 = e.u78 - 1
    if e.u78 == 0 then cuccoCalm(E, e)
    elseif band(e.u78, 0x1F) == 0 then cuccoFx(E, e) end
  elseif a == 6 then
    local t = e.timer or 0
    e.timer = band(t + 1, 0xFF)
    if band(t, 0x1F) == 0 then cuccoFx(E, e) end
    if (e.u78 or 0) ~= 0 then
      local u = e.u78
      e.u78 = u - 1
      if band(u, 7) == 0 then local p = f.player; turn(e, dirTo(e.x, e.y, p.x, p.y)) end
      cuccoFlip(e)
      linear(e, e.dir, e.spd)
      frames(e)
    else
      linear(e, e.dir, e.spd)
      frames(e)
      if outsideScroll(f, e) then e.deleted = true return end
    end
  end
  -- sub_080391B4: the revenge flock
  if (e.u7a or 0) ~= 0 and not e.jarSub then
    local u = e.u7b or 0
    e.u7b = band(u + 1, 0xFF)
    if band(u, 0x1F) == 0 then
      local pt = M.CUCCO_SPAWN[band(R(f), 0x17)]
      local c = spawnEnemy(E, e, M.CUCCO_AGGR, 2)
      c.x = math.floor(f.camX or 0) + pt[1]
      c.y = math.floor(f.camY or 0) + pt[2]
      c.layer = e.layer
    end
  end
end

-- ===========================================================================
function M.update(E, e)
  local id = e.id
  if e.mandibles or id == M.SCISSORS_BEETLE then return M.scissors(E, e) end
  if id == M.LEEVER then return M.leever(E, e) end
  if id == M.ACRO_BANDIT then return M.acro(E, e) end
  if id == M.GHINI then return M.ghini(E, e) end
  if id == M.CROW then return M.crow(E, e) end
  if id == M.KEATON then return M.keaton(E, e) end
  if id == M.ROCK_CHUCHU then return M.rock(E, e) end
  if id == M.CUCCO_AGGR then return M.cucco(E, e) end
end

-- tests
M._turn, M._fflags, M._take, M._onScreen, M._kbDir = turn, fflags, take, onScreen, kbDir

return M
