-- Round 26 (team B, group "pow"): the Palace of Winds' enemies (also met in
-- the Royal Crypt $68 and Dark Hyrule Castle $88), from the decomp.
--
-- BOMBAROSSA ($33, src/enemy/bombarossa.c):
--   OnTick: Init -> action 1, timer Random & $F, animation 0; type != 0:
--     its rail = room property [type] (UpdateRailMovement).  Every frame
--     z = gUnk_080CEB50[((++timer >> 4) & 7) + type2 * 8] (a bob; type2 1 floats
--     18-22 px up), GetNextFrame; with a rail: LinearMoveUpdate unless the
--     direction has bit 7, the next leg when unk_0x76 runs out.
--   OnCollision: contact $81/$8F/$93/$9B/$9D/$9E (Minish Link, ..., the Gust
--     Jar...) -> the generic handlers; anything else (Link's body, the sword,
--     a bomb blast...) -> a SMOKE_PARTICLE (the bomb blast: it hurts Link and
--     sets off the Bombarossas around it) and it is gone.
-- CROW ($31, src/enemy/crow.c):
--   Init (sub_08032928): home, action 1, facing Link, gustJarFlags 1 (it is
--     swallowed), collision layer 3 (over everything), home spot (unk_78/7a);
--     unk_82 keeps the room data's yPos (the EntityData copy at +$78; Init
--     only overwrites +$78..+$81), so the first dive lasts yPos frames.
--   1 (sub_0803298C): perched; every timer (u8) re-aims at Link and redraws
--     when north/south flips; Link inside $88 x $50 and below it (y + 8) ->
--     action 2 (unk_84 0, timer 16, wings anim set 2).
--   2 (sub_08032B38): unk_84 0: rises 1 px every other frame for 16 frames,
--     then COLLISION_ON, 24 frames (set 2); unk_84 1: then speed $1C0, set 4;
--     unk_84 2: unk_82-- -> 0: action 3 (speed $180, turned away south);
--     every 8 frames one step toward Link (sub_08004596), never into the
--     northern half (then it keeps its old heading and leaves next frame).
--   3 (sub_080329F0): flies on (LinearMoveUpdate) until off screen
--     (CheckOnScreen) -> action 4: hidden, collision off, back at its perch,
--     z + 8.  4 (sub_08032A48): waits until the perch is off screen too ->
--     action 1 shown.
--   OnCollision: touching Link -> collision off for 16 frames (subtimer) and
--     it bounces (direction mirrored, +-2 off an axis); any item -> health 0.
--   OnGrabbed: wiggle, then swallowed (GenericDeath); let go -> action 2,
--     unk_84 2, speed $1C0.
-- LAKITU ($47, src/enemy/lakitu.c) + LAKITU_CLOUD_PROJECTILE ($11) +
-- LAKITU_LIGHTNING ($12):
--   Init: the cloud (EnemyCreateProjectile 17) as child, home, HIDDEN, z -2.
--   Every action but 0 / 7 drifts back to its home (sub_0803CAD0,
--   ProcessMovement2).  HIDDEN: faces Link (sub_0803CA84 with 0); Link not
--   within $28 but inside $70 x $50 -> END_HIDE (drawn).  END_HIDE: anim
--   done -> IDLE (timer 60, hit type $42, anim state + 4).  IDLE: timer out
--   -> LIGHTNING_THROW (hit type $A6, unk_78 = facing Link, anim state + 8,
--   the cloud anim state + 4); Link too near / far -> BEGIN_HIDE (hit type
--   $43, anim state + $C) -> hidden (anim state).  LIGHTNING_THROW: anim done
--   -> a LAKITU_LIGHTNING at gUnk_080D0154[state], direction unk_78, SFX_193;
--   LIGHTNING_DELAY 15 frames and another throw (half the time, once) else
--   30 frames -> IDLE for 180.  OnCollision: the Cane's bolt ($9D) -> zVelocity
--   2.0 and CLOUDLESS (sub_0803CBAC: the cloud collides with hit type $43,
--   Lakitu hit type $42, anim state + 16); hit while hit type $43 -> FX_DEATH
--   puff off the cloud.  Gust Jar pull -> CLOUDLESS (the cloud stays behind).
--   CLOUDLESS: GravityUpdate(24/256); landed -> anim state + 20; falling back
--   onto its cloud (within 6 px, z within 2) -> four FX_DEATH, the cloud gone.
--   The cloud projectile sits on Lakitu (y - 1, z -2) with the anim Lakitu
--   gives it; swallowed while hit type $A6: Link loses 2 (SFX_PLY_VO6).
--   The lightning: health 1, 180 frames, ProcessMovement3; a wall / time ->
--   FX_BLUE_EFC; off screen / touching -> gone.
-- LAKITU_CLOUD ($48, src/enemy/lakituCloud.c): rides room property [type]
--   (UpdateRailMovement, anim direction / 8 + 4); Gust Jar: swallowed ->
--   Link loses 2, then it blinks 60 frames at its start (sub_0803CE3C).
-- BALL_CHAIN_SOLIDER ($4C, src/enemy/ballChainSoldier.c) + BALL_AND_CHAIN
-- ($19, src/projectile/ballAndChain.c):
--   Init: home, the ball (type 0) as child, random facing, unk_7e $20
--   (radius), unk_7f $FE (height), anim state * 4, sub_0803E86C.
--   1 stand / 2 walk (unk_78 frames from gUnk_080D0728 / gUnk_080D0730),
--   spinning the ball (unk_7c -= $A, the anim's quadrant = (unk_7c + $20) >>
--   6); Link in its home within $38 -> 3 (spin faster -$10, the radius to
--   $22, a trail of type-4 ghosts); lined up within $4E (sub_0804A044 $12,
--   4 frames in a row) -> 5: reel in (radius - 4) -> 6 (30 frames, anim
--   $20 + state) -> 7: the throw (angle gUnk_080D0724[state], height -10,
--   SFX_15B; the radius grows 5 a frame while the height comes down one per 2
--   frames) -> 8: InitScreenShake(8), 30 frames -> 9: pull it back (- 2;
--   under $12 the ball stops colliding) -> 10: 90 frames, then spin up again.
--   Death: EnemyCreateDeathFX($FF, $57).
--   The ball (type 0) makes three chain links (types 1-3) and sits at the
--   soldier + (sin, -cos) * radius, y - 10 - height, z + height; types 1-3
--   start at the soldier's hand (gUnk_0812A4A8 by its frame byte & $1F, as
--   a byte offset) and move type/4 of the way to the ball; they collide
--   only while the angle changes.  Type 4: a 5-frame ghost (frame 1..4).
-- GOBDO ($3B, src/enemy/gibdo.c):
--   1 stand 30 frames / 2 walk (speed $40, 120-176 frames, home-bound when
--   outside) / 3-4 chase Link (seen within $40 in front: speed $C0, 300
--   frames, re-aimed when he moves $28 away) / 5 the grab lunge (lined up
--   within $18: speed $100, anim + 8, hit type $27 on frame bit 0) / 6
--   holding Link (he is held on it; 5 bites of 8 health (anim frame bit 0);
--   24 presses free him) / 7 recoil (anim + $10) / 8 burning (60 frames,
--   three FLAME type 3, then a STALFOS type 0 in its place).
--   OnCollision: contact $87 (fire) -> 8; hit type $27 + Link's body -> 6;
--   in 1-2 -> it turns to the attacker.  sub_08037A58 frees Link (knocked
--   the way it faces, 4 frames, $180, iframes 30), iframes -12, knocked back.
-- CHUCHU type 2 (the yellow one, chuchu.c gUnk_080CA288):
--   0 home, timer random; 1 puddle until Link is in its home (and seen once
--   or within $48) -> 2 rising (anim 0) -> 3 (subtimer 30, anim 2) -> the
--   lightning (EnemyCreateFX FX_LIGHTNING_STRIKE, hit type $A5, SFX_193) ->
--   4 hop at Link (every 8th frame within $38: 5 the jump, speed $180,
--   zVelocity 2.0, GravityUpdate(64/256), SFX_12B on frame bit 0) -> 6 (60
--   frames, speed $20) -> 4; out of its home / water -> 7 sink (anim 5) ->
--   8 (under water it follows Link; else rises (anim 4) or, Link gone, 9 ->
--   puddle).  Hit (health lost / $94): 10 (hit type $5C, the lightning
--   detached, anim 6) -> 3.  Contact $8E / $95 kill it outright.  The FX
--   follows it at gUnk_080CA2B4[frame & $F] (ROM table), y + 1.
-- SIMPLIFIED: ProcessMovement2/3/5 are EnemyDeepwood.move0; GenericKnockback
--   stops the AI while knocked back (the Ball Chain Soldier keeps spinning in
--   the cartridge); the electrified ChuChu / throwing Lakitu do not shock the
--   sword back (no hurt-back path in Enemies:hit); FX_STARS, EnemySetFXOffset
--   and CreateDrownFx are not drawn; the Crow's flipY sprite flag is not
--   drawn; CLOUD_PIRANHA ($3F) is not in any Palace of Winds room (not ported).
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = {}
M.CHUCHU, M.CROW, M.BOMBAROSSA, M.GOBDO, M.STALFOS = 0x01, 0x31, 0x33, 0x3B, 0x42
M.LAKITU, M.LAKITU_CLOUD, M.BALL_CHAIN_SOLIDER = 0x47, 0x48, 0x4C
M.P_LAKITU_CLOUD, M.P_LAKITU_LIGHTNING, M.P_BALL_AND_CHAIN = 0x11, 0x12, 0x19
local SFX_193, SFX_15B, SFX_12B, SFX_PLY_VO6, SFX_124, SFX_EF = 0x193, 0x15B, 0x12B, 0x7A, 0x124, 0xEF
local SPECIAL_FX, FX_DEATH, FX_LIGHTNING_STRIKE, FX_BLUE_EFC = 0x0F, 0x02, 0x1B, 0x4F
local OBJ_FLAME = 0x2A

M.ROM_RANGES = {
  pow_chuchu_fx = { 0x080CA2B4, 0x080CA2BE }, -- gUnk_080CA2B4 (data/animations/enemy/chuchu.s): the yellow ChuChu's lightning x offsets
}

-- tables written out in the decomp's .c sources
M.BOB = { [0] = 0, -1, -2, -3, -4, -3, -2, -1, -18, -19, -20, -21, -22, -21, -20, -19 } -- gUnk_080CEB50
M.LIGHTNING_AT = { [0] = { 0, -18 }, { 18, 0 }, { 0, 8 }, { -18, 0 } }                       -- gUnk_080D0154
M.BCS_ANGLE = { [0] = 0, 0x44, 0x80, 0xBC }                                                  -- gUnk_080D0724
M.BCS_STAND = { [0] = 0x1E, 0x32, 0x46, 0x5A }                                               -- gUnk_080D0728
M.BCS_WALK = { [0] = 0x3C, 0x5A, 0x78, 0x96 }                                                -- gUnk_080D0730
-- gUnk_0812A4A8 as the s8 bytes it is read as (PosOffset* = table + index bytes)
M.HAND = { [0] = 6, -16, 10, -14, 10, -16, 8, -16, -4, -14, -8, -14, -4, -10, 4, -10,
           -6, -14, -8, -16, -10, -14, -8, -12, 4, -14, 8, -14, 4, -10, -4, -10 }
local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end -- gSineTable ($100 = 1)
M.SIN = SIN

local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function R(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i); e.flagKey = nil end
-- the keyframe's frame byte; take() clears the bits the cartridge writes back
local function fflags(e)
  if not e.anim then return 0 end
  if e.flagKey == e.anim.key then return band(e.anim.flags or 0, 0x80) end
  return e.anim.flags or 0
end
local function take(e) e.flagKey = e.anim and e.anim.key end
local function done(e) return band(fflags(e), 0x80) ~= 0 or (e.anim and e.anim.done) end
local function target(f) return DW().target(f) end
local function dirTo(ax, ay, bx, by) return DW().dirTo(ax, ay, bx, by) end
local function dirVec(d) local a = (d % 32) / 32 * 2 * math.pi return math.sin(a), -math.cos(a) end
local function linear(e, spd) -- LinearMoveUpdate
  local d = e.direction or e.dir
  if not d or band(d, 0x80) ~= 0 then return end
  local vx, vy = dirVec(d)
  local s = (spd or e.speed or 0) / 256
  e.x, e.y = e.x + vx * s, e.y + vy * s
end
-- ProcessMovement0: true when it moved freely
local function move0(E, e, dir, spd)
  if not dir or band(dir, 0x80) ~= 0 then return true end
  local hx, hy = DW().move0(E, e, dir, spd)
  return not (hx or hy)
end
local function roundUp(d) return band(d + 4, 0x18) end
local function within(e, x, y, d) -- EntityWithinDistance
  local dx, dy = math.floor(e.x) - math.floor(x), math.floor(e.y) - math.floor(y)
  return d * d >= dx * dx + dy * dy
end
local function inRect(a, b, rx, ry) -- EntityInRectRadius (layers overlap)
  if band(a.layer or 1, b.layer or 1) == 0 then return false end
  if rx ~= 0 and math.abs(math.floor(a.x) - math.floor(b.x)) > rx then return false end
  if ry ~= 0 and math.abs(math.floor(a.y) - math.floor(b.y)) > ry then return false end
  return true
end
local function targetInHome(f, e) -- sub_08049FDC(e, 1)
  local t = target(f)
  if not t then return nil end
  local dx, dy = math.floor(t.x) - e.homeX, math.floor(t.y) - e.homeY
  if dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH then return t end
  return nil
end
local function selfInHome(e) -- sub_08049FA0
  local dx, dy = math.floor(e.x) - e.homeX, math.floor(e.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH
end
local function homeDir(e) return dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) end -- sub_08049EE4
local function facingLink(f, e) local t = target(f) if not t then return 0xFF end return dirTo(e.x, e.y, t.x, t.y) end -- sub_08049F84
local function turnStep(e, want) -- sub_08004596
  if not want or want == 0xFF then return end
  local d = band(want - e.dir, 0x1F)
  if d == 0 then return end
  if d < 16 then e.dir = band(e.dir + 1, 0x1F) else e.dir = band(e.dir - 1, 0x1F) end
end
local function onScreen(f, e) -- CheckOnScreen
  local cx, cy = f.camX or 0, f.camY or 0
  local x = math.floor(e.x) - cx + 0x3F
  local y = math.floor(e.y) - math.floor(e.z or 0) - cy + 0x3F
  return x >= 0 and x < 0x16E and y >= 0 and y < 0x11E
end
local function lined(E, e, w) -- sub_0804A044(e, gEnemyTarget, w)
  local ok, B = pcall(require, "src.zelda.tmc.EnemyBeetle")
  if ok and B.linedUp then local d = B.linedUp(E, e, w) if d and d ~= 0xFF then return d end end
  return nil
end
local function fx(f, x, y, t) if f.addFx then f:addFx(x, y, SPECIAL_FX, t) end end
M._h = { within = within, inRect = inRect, onScreen = onScreen, turnStep = turnStep, roundUp = roundUp }

-- an enemy-side child (projectile) built from gProjectileDefinitions
local function projDef(f, id)
  local d = f.assets.manifest and f.assets.manifest.projectileDefs and f.assets.manifest.projectileDefs[id]
  if d and d.multi then d = d.forms[0] end
  return d or {}
end
local function child(E, parent, id, extra)
  local f = E.field
  local d = projDef(f, id)
  local A = E.A
  local c = { kind = 4, id = 0x100 + id, projId = id, x = parent.x, y = parent.y, z = parent.z or 0, zv = 0,
              health = 1, maxHealth = 1, speed = d.speed or 0, hitType = d.damageType or 0,
              hitbox = d.hitbox or { x = 0, y = 0, w = 4, h = 4 }, sprite = d.sprite,
              gfx = d.gfx and require("src.zelda.tmc.Assets").gfxSource("enemy", d.gfx) or parent.gfx,
              anim = require("src.zelda.tmc.Anim").new(), animationState = parent.animationState or 0,
              action = 0, timer = 0, subtimer = 0, iframes = 0, kbt = 0, enemy = true, literalAnim = true,
              field82 = 0, interactType = 0, layer = parent.layer or 1, parent = parent, powChild = true,
              homeX = parent.homeX or 0, homeY = parent.homeY or 0, rangeW = parent.rangeW or 0, rangeH = parent.rangeH or 0,
              noHit = true, collideOn = true, spritePriority = d.priority }
  if A and A.objPalette then c.palette = A:objPalette(d.palette or 0, f.room and f.room.atlas and f.room.atlas.palettes) end
  c.def = setmetatable({ collision = 1, palette = d.palette }, { __index = d })
  for k, v in pairs(extra or {}) do c[k] = v end
  f.entities[#f.entities + 1] = c
  return c
end
M._child = child
local function parentGone(e) local p = e.parent return not p or p.deleted or p.dying end

function M.handles(e)
  if e.powChild then return true end
  local id = e.id
  if e.kind ~= 3 then return false end
  if (id == M.CROW or id == M.LAKITU or id == M.LAKITU_CLOUD) and M.lastArea and M.lastArea ~= 0x70 and M.lastArea ~= 0x71 then return false end -- round 27A: outside the Palace of Winds, EnemyField1/2 run them
  return id == M.BOMBAROSSA or id == M.CROW or id == M.LAKITU or id == M.LAKITU_CLOUD
      or id == M.BALL_CHAIN_SOLIDER or id == M.GOBDO or (id == M.CHUCHU and e.form == 2)
end

-- ===========================================================================
-- BOMBAROSSA
-- ===========================================================================
local BOMB_PASS = { [1] = true, [15] = true, [19] = true, [27] = true, [29] = true, [30] = true }
function M.bombCollision(E, e, fl)
  if BOMB_PASS[band(fl, 0x7F)] then return end
  -- CreateObject(SMOKE_PARTICLE) at its place, DeleteThisEntity
  if e.exploded then return end
  local f = E.field
  e.deleted = true -- gone before the blast (its own smoke must not set it off again)
  e.exploded = true
  local ok, B = pcall(require, "src.zelda.tmc.Bombs")
  if ok and B.smoke and f.assets and f.assets.manifest then pcall(B.smoke, f, e.x, e.y, e.layer) end
end

function M.bombarossa(E, e)
  local f = E.field
  if e.action == 0 then
    e.action = 1
    e.timer = band(R(f), 0xF)
    e.onCollision = M.bombCollision
    e.type2 = band(e.spawnB or 0, 0xFF)
    setAnim(E, e, 0)
    if (e.form or 0) ~= 0 then
      local props = f.room and f.room.maps and f.room.maps.header and f.room.maps.header.props
      e.railPtr = props and props[e.form]
      e.direction, e.speed = 0xFF, 0
      require("src.zelda.tmc.CoFObjects").railNext(f, e)
    end
  end
  e.timer = band((e.timer or 0) + 1, 0xFF)
  local v = M.BOB[band(rshift(e.timer, 4), 7) + (e.type2 or 0) * 8] or 0
  e.z = -v
  e.anim:update(1)
  if (e.form or 0) ~= 0 then
    if band(e.direction or 0xFF, 0x80) == 0 then linear(e, e.speed) end
    e.u76 = (e.u76 or 0) - 1
    if e.u76 == 0 then require("src.zelda.tmc.CoFObjects").railNext(f, e) end
  end
end

-- ===========================================================================
-- CROW
-- ===========================================================================
local function crowAnim(E, e) setAnim(E, e, rshift(band(e.dir or 0, 0x10), 4) + (e.u81 or 0)) end -- sub_08032AF4

function M.crowCollision(E, e, fl)
  if band(fl, 0x80) == 0 then return end
  if band(fl, 0x3F) == 0 then -- Link's body
    e.noTouch, e.noHit = true, true
    e.subtimer = 16
    local d = e.dir or 0
    if band(roundUp(d), 0x08) == 0 then
      if band(d, 0x10) ~= 0 then d = d + 2 else d = d - 2 end
    end
    e.dir = band(0x20 - d, 0xFF)
    crowAnim(E, e)
  else
    if band(e.iframes or 0, 0x80) == 0 then e.health = 0 end
  end
end

local function crowPull(E, e) -- sub_08032914: swallowed -> GenericDeath
  local f = E.field
  local p = f.player
  local j = p and p.jar
  if not j then return false end
  local GJ = require("src.zelda.tmc.GustJar")
  e.jarKb = math.min(0x500, (e.jarKb or 0) + 64 * (j.charge or 1))
  local mx, my = GJ.mouth(p)
  local dx, dy = mx - e.x, my - e.y
  local d = math.sqrt(dx * dx + dy * dy)
  local sp = e.jarKb / 256
  if d <= sp then e.x, e.y = mx, my else e.x, e.y = e.x + dx / d * sp, e.y + dy / d * sp end
  if math.abs(e.x - mx) < 4 and math.abs(e.y - my) < 4 then
    f:sound(SFX_EF)
    E:kill(e)
  end
  return true
end

function M.crow(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- sub_08032928
    e.action, e.subtimer = 1, 0
    e.dir = facingLink(f, e)
    e.u80, e.u81 = 0, 0
    e.gustJarFlags = 1
    e.layer = 3
    e.u78, e.u7a = e.x, e.y
    e.u82 = band(math.floor(e.spawnY or e.y), 0xFFFF)
    e.onCollision = M.crowCollision
    e.onJarPull = crowPull
    e.onJarLost = function(EE, x) -- Crow_OnGrabbed: sub_0806F520 false
      x.action, x.subAction, x.u84, x.timer, x.speed = 2, 0, 2, 8, 0x1C0
      crowAnim(EE, x)
    end
    crowAnim(E, e)
  elseif a == 1 then -- sub_0803298C
    e.timer = band((e.timer or 0) - 1, 0xFF)
    if e.timer == 0 then -- sub_08032AB0
      e.u80 = e.dir
      local d = facingLink(f, e)
      if d ~= 0xFF then e.dir = d end
      e.timer = 8
      if band(e.u80 or 0, 0x10) ~= band(e.dir or 0, 0x10) then crowAnim(E, e) end
    end
    e.anim:update(1)
    local t = target(f)
    if t and inRect(e, t, 0x88, 0x50) and math.floor(t.y) > math.floor(e.y) + 8 then
      e.action, e.u84, e.timer, e.u81 = 2, 0, 16, 2
      crowAnim(E, e)
    end
  elseif a == 2 then -- sub_08032B38
    if e.u84 == 0 then
      if band(e.timer, 1) ~= 0 then e.z = (e.z or 0) + 1 end
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.u84, e.timer, e.u81 = 1, 24, 2
        e.noTouch, e.noHit = nil, nil
        crowAnim(E, e)
      end
    elseif e.u84 == 1 then
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.u84, e.timer, e.speed, e.u81 = 2, 8, 0x1C0, 4
        crowAnim(E, e)
      end
    else
      e.u82 = band((e.u82 or 0) - 1, 0xFFFF)
      if e.u82 == 0 then
        e.action, e.u84, e.timer, e.speed = 3, 0, 0, 0x180
        if band(e.dir + 0x18, 0x10) ~= 0 then e.dir = band(0x10 - e.dir, 0x1F) end
        crowAnim(E, e)
      else
        e.timer = e.timer - 1
        if e.timer == 0 then
          e.timer = 8
          e.u80 = e.dir
          turnStep(e, facingLink(f, e))
          if band(e.dir + 0x18, 0x10) ~= 0 then
            if e.u80 == 0x10 then e.u80 = band(e.dir, e.u80) ~= 0 and 0x12 or 0x0E end
            e.dir = e.u80
            e.u82 = 1
          end
          if rshift(band(e.u80, 0x10), 4) ~= rshift(band(e.dir, 0x10), 4) then
            setAnim(E, e, rshift(band(e.dir, 0x10), 4) + 4)
          end
        end
        linear(e, e.speed) -- sub_08032B10
        e.layer = 3
      end
    end
    e.anim:update(1)
  elseif a == 3 then -- sub_080329F0
    if not onScreen(f, e) then
      e.action = 4
      e.staticFrame = 0xFF
      e.noTouch, e.noHit = true, true
      e.x, e.y = e.u78, e.u7a
      e.z = (e.z or 0) - 8
    else
      linear(e, e.speed)
      e.layer = 3
      e.anim:update(1)
    end
  elseif a == 4 then -- sub_08032A48
    if onScreen(f, e) then return end
    e.action = 1
    e.staticFrame = nil
    e.noTouch, e.noHit = true, true -- COLLISION_OFF (on again after the rise)
    e.timer = 8
    e.dir = facingLink(f, e)
    e.u80, e.u81 = 0, 0
    e.layer = 3
    crowAnim(E, e)
  end
  if (e.subtimer or 0) ~= 0 then
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then e.noTouch, e.noHit = nil, nil end
  end
end

-- ===========================================================================
-- LAKITU, its cloud and lightning
-- ===========================================================================
local function cloudAnim(E, c, i) if c and not c.deleted then setAnim(E, c, i) end end
local function lakFace(E, e, extra) -- sub_0803CA84
  local f = E.field
  local p = f.player
  local alt = dirTo(e.x, e.y, p.x, p.y)
  if band(alt - 3, 7) > 2 or band((e.animationState or 0) - rshift(alt, 3), 3) > 1 then
    alt = rshift(roundUp(alt), 3)
    if alt ~= e.animationState then
      e.animationState = alt
      setAnim(E, e, alt + extra)
      cloudAnim(E, e.child, alt)
    end
  end
end
local function lakSees(E, e) -- sub_0803CA4C
  local p = E.field.player
  return not within(e, p.x, p.y, 0x28) and inRect(e, p, 0x70, 0x50)
end
local function lakThrow(E, e) -- sub_0803CB34
  local p = E.field.player
  e.action, e.hitType = 5, 0xA6
  e.u78 = dirTo(e.x, e.y, p.x, p.y)
  setAnim(E, e, e.animationState + 8)
end
local function cloudless(E, e) -- sub_0803CBAC
  local c = e.child
  if c and not c.deleted then c.noTouch, c.noHit, c.hitType = nil, true, 0x43 end
  e.action = 7
  e.staticFrame = nil
  e.lakHidden = false
  e.hitType = 0x42
  e.noHit = nil
  setAnim(E, e, e.animationState + 16)
end
M.lakCloudless = cloudless

function M.lakituCollision(E, e, fl)
  local f = E.field
  if band(fl, 0x7F) == 0x1D then
    e.zv = 2.0
    cloudless(E, e)
  elseif e.hitType == 0x43 then
    -- a puff off the cloud, (knockbackDirection ^ $10) << 3 along the sine table, >> 5
    local p = f.player
    local kd = dirTo(p.x, p.y, e.x, e.y)
    local ang = band(lshift(bxor(kd, 0x10), 3), 0xFF)
    local function q(v) if v < 0 then v = v + 0x1F end return math.floor(v / 32) end
    fx(f, e.x + q(SIN[ang]), e.y - q(SIN[ang + 0x40]), FX_DEATH)
  end
end

function M.lakitu(E, e)
  local f = E.field
  if e.action ~= 0 and e.action ~= 7 then -- sub_0803CAD0: back home
    if not within(e, e.u74, e.u76, 1) then
      e.dir = dirTo(e.x, e.y, e.u74, e.u76)
      move0(E, e, e.dir, e.speed ~= 0 and e.speed or 0x80)
    end
  end
  local a = e.action
  if a == 0 then -- Lakitu_Initialize
    e.child = child(E, e, M.P_LAKITU_CLOUD, { cloud = true, noTouch = true, noHit = true })
    e.action = 1
    e.z = 2
    e.spriteOY = -1
    e.u74, e.u76 = e.x, e.y
    e.staticFrame, e.lakHidden = 0xFF, true -- the definition's draw 0
    e.onCollision = M.lakituCollision
    e.onJarPull = function(EE, x) cloudless(EE, x); x.child = nil; return true end -- sub_0803C86C
    e.onGrabbed = function(EE, x) end
  elseif a == 1 then -- Lakitu_Hide
    lakFace(E, e, 0)
    if lakSees(E, e) then e.action, e.staticFrame, e.lakHidden = 2, nil, false end
  elseif a == 2 then -- Lakitu_EndHide
    e.anim:update(1)
    if done(e) then
      e.action, e.timer, e.hitType = 3, 60, 0x42
      setAnim(E, e, e.animationState + 4)
    end
  elseif a == 3 then -- Lakitu_Idle
    e.timer = band((e.timer or 0) - 1, 0xFF)
    if e.timer == 0 then -- sub_0803CB04
      lakThrow(E, e)
      e.u79 = 0
      cloudAnim(E, e.child, e.animationState + 4)
      return
    end
    if not lakSees(E, e) then
      e.action, e.hitType = 4, 0x43
      setAnim(E, e, e.animationState + 0xC)
    else lakFace(E, e, 4) end
  elseif a == 4 then -- Lakitu_BeginHide
    e.anim:update(1)
    if done(e) then
      e.action, e.staticFrame, e.lakHidden = 1, 0xFF, true
      setAnim(E, e, e.animationState)
    end
  elseif a == 5 then -- Lakitu_Lightning
    e.anim:update(1)
    if not done(e) then return end
    local o = M.LIGHTNING_AT[e.animationState or 0] or M.LIGHTNING_AT[0]
    local l = child(E, e, M.P_LAKITU_LIGHTNING, { lightning = true, x = e.x + o[1], y = e.y + o[2], dir = e.u78, parent = nil, lakitu = e })
    l.z = e.z or 0
    f:sound(SFX_193)
    e.action, e.hitType = 6, 0x42
    if band(R(f), 1) ~= 0 and (e.u79 or 0) == 0 then
      e.timer, e.u79 = 15, 1
    else
      e.timer, e.u79 = 30, 0
      cloudAnim(E, e.child, e.animationState)
    end
  elseif a == 6 then -- Lakitu_LightningDelay
    e.timer = e.timer - 1
    if e.timer ~= 0 then return end
    if e.u79 == 1 then lakThrow(E, e)
    else
      e.action, e.timer = 3, 180
      setAnim(E, e, e.animationState + 4)
    end
  elseif a == 7 then -- Lakitu_Cloudless
    if not DW().gravity(e, 24 / 256) and (e.animIndex or 0) <= 19 then
      setAnim(E, e, e.animationState + 20)
      e.spritePriority = nil
    end
    e.anim:update(1)
    -- sub_0803CC08: back down onto its cloud -> the cloud is blown away
    local c = e.child
    if c and not c.deleted and (e.zv or 0) < 0 then
      local dz = (e.z or 0) - (c.z or 0) -- cloud.z - lakitu.z in the cartridge's (negative-up) z
      if dz >= 0 and dz <= 2 and within(e, c.x, c.y, 6) then
        local o = 3 / 128 * 256 / 256 -- Q_8_8(3/128): 0 whole pixels
        fx(f, e.x + o, e.y + o, FX_DEATH); fx(f, e.x - o, e.y + o, FX_DEATH)
        fx(f, e.x + o, e.y - o, FX_DEATH); fx(f, e.x - o, e.y - o, FX_DEATH)
        e.child = nil
        c.deleted = true
      end
    end
  end
end

-- LAKITU_CLOUD_PROJECTILE: on Lakitu, y - 1, z -2
function M.lakCloud(E, e)
  if parentGone(e) then e.deleted = true return end
  local par = e.parent
  if e.action == 0 then
    e.action = 1
    e.animationState = par.animationState or 0
    setAnim(E, e, e.animationState)
    e.onJarPull = function(EE, x) -- SubAction2: swallowed
      local f = EE.field
      if x.hitType == 0xA6 then f:modStat("health", -2); f:sound(SFX_PLY_VO6) end
      fx(f, x.x, x.y, FX_DEATH)
      x.deleted = true
      if par.child == x then par.child = nil end
      return true
    end
  end
  e.x, e.y, e.layer = par.x, par.y - 1, par.layer
  e.z = 2
  e.anim:update(1)
end

-- LAKITU_LIGHTNING
function M.lightning(E, e)
  local f = E.field
  if e.action == 0 then
    e.action, e.timer, e.health = 1, 180, 1
    e.onCollision = function(EE, x, fl) if (x.health or 0) == 0 or fl == 0x80 then x.deleted = true end end
    setAnim(E, e, 0)
  end
  e.anim:update(1)
  local free = move0(E, e, e.dir, e.speed ~= 0 and e.speed or 0x80) -- ProcessMovement3
  e.timer = e.timer - 1
  if not free or e.timer == 0 then
    fx(f, e.x, e.y, FX_BLUE_EFC)
    e.deleted = true
    return
  end
  if not onScreen(f, e) then e.deleted = true end -- IsProjectileOffScreen
end

-- LAKITU_CLOUD ($48)
local function lcRail(E, e) -- sub_0803CE14
  require("src.zelda.tmc.CoFObjects").railNext(E.field, e)
  if band(e.direction or 0xFF, 0x80) ~= 0 then return end
  setAnim(E, e, math.floor(e.direction / 8) + 4)
end
local function lcReset(E, e) -- sub_0803CE3C
  local f = E.field
  fx(f, e.x, e.y, FX_DEATH)
  e.action, e.timer = 2, 60
  e.noTouch, e.noHit = true, true
  e.x, e.y = e.u78, e.u7a
  e.railPtr = e.railStart
  lcRail(E, e)
end
function M.lakituCloud(E, e)
  local f = E.field
  if e.action == 0 then -- sub_0803CD6C
    e.action = 1
    e.z = 2
    local props = f.room and f.room.maps and f.room.maps.header and f.room.maps.header.props
    e.railStart = props and props[e.form or 0]
    e.railPtr = e.railStart
    e.u78, e.u7a = e.x, e.y
    e.direction, e.speed = 0xFF, 0
    e.onJarPull = function(EE, x) -- sub_0803CD40: swallowed
      local GJ = require("src.zelda.tmc.GustJar")
      local p = EE.field.player
      local mx, my = GJ.mouth(p)
      x.jarKb = math.min(0x500, (x.jarKb or 0) + 64 * ((p.jar and p.jar.charge) or 1))
      local dx, dy = mx - x.x, my - x.y
      local d = math.sqrt(dx * dx + dy * dy)
      local sp = x.jarKb / 256
      if d <= sp then x.x, x.y = mx, my else x.x, x.y = x.x + dx / d * sp, x.y + dy / d * sp end
      if math.abs(x.x - mx) < 4 and math.abs(x.y - my) < 4 then
        EE.field:modStat("health", -2)
        EE.field:sound(SFX_PLY_VO6)
        lcReset(EE, x)
      end
      return true
    end
    e.onJarLost = function(EE, x) if x.subAction == 2 then lcReset(EE, x) end end
    setAnim(E, e, 4)
    lcRail(E, e)
  elseif e.action == 1 then -- sub_0803CDA8
    e.anim:update(1)
    if band(e.direction or 0xFF, 0x80) == 0 then linear(e, e.speed) end
    e.u76 = band((e.u76 or 0) - 1, 0xFFFF)
    if e.u76 == 0 then lcRail(E, e) end
  elseif e.action == 2 then -- sub_0803CDD8: blinks
    e.staticFrame = (e.staticFrame == 0xFF) and nil or 0xFF
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.noTouch, e.noHit, e.staticFrame = 1, nil, nil, nil end
  end
end

-- ===========================================================================
-- BALL_CHAIN_SOLIDER and BALL_AND_CHAIN
-- ===========================================================================
local function bcsNear(f, e, d) -- sub_0803EAD0
  local t = target(f)
  if not t then return false end
  return within(e, t.x, t.y - 4, d)
end
local function bcsAnim(E, e, arg) -- sub_0803E94C
  local st = rshift(roundUp(e.dir or 0), 3)
  local ai = e.animIndex or 0
  if band(ai, 0x10) == arg then
    local cur = e.animationState or 0
    if band(e.dir or 0, 7) == 4 and band(cur - rshift(e.dir or 0, 3), 3) <= 1 then return end
    if st == cur then return end
  end
  e.animationState = st
  setAnim(E, e, arg + band(ai, 3) + st * 4)
end
local function bcsSpinAnim(E, e) -- sub_0803E9A4
  local v = rshift(band(e.u7c + 0x20, 0xFF), 6)
  local ai = e.animIndex or 0
  if band(ai, 3) == v then return end
  setAnim(E, e, v + band(ai, bit.bnot(3)))
end
local function bcsStand(E, e) -- sub_0803E86C
  local f = E.field
  local t = targetInHome(f, e)
  if t and bcsNear(f, e, 0x50) then e.dir = roundUp(dirTo(e.x, e.y, t.x, t.y)) end
  e.action = 1
  e.u78 = M.BCS_STAND[band(R(f), 3)]
  e.u7a = 4
  bcsAnim(E, e, 0)
end
local function bcsWalk(E, e) -- sub_0803E8CC
  local f = E.field
  local r = R(f)
  local dir
  if not selfInHome(e) and band(r, 3) ~= 0 then dir = homeDir(e) + 4 else dir = r end
  e.dir = band(dir, 0x18)
  e.action = 2
  e.u78 = M.BCS_WALK[band(rshift(r, 16), 3)]
  e.u7a = 4
  bcsAnim(E, e, 0x10)
end
local function bcsLook(E, e) -- sub_0803E9D4
  local f = E.field
  local t = targetInHome(f, e)
  if t then
    if bcsNear(f, e, 0x38) then
      e.action = 3
      e.dir = roundUp(dirTo(e.x, e.y, t.x, t.y))
      e.u7b = 1
      bcsAnim(E, e, 0)
      return true
    elseif bcsNear(f, e, 0x4E) then
      local d = lined(E, e, 0x12)
      if d then
        e.u7a = e.u7a - 1
        if e.u7a ~= 0 then return false end
        e.action, e.dir, e.u7a = 5, d, 4
        bcsAnim(E, e, 0)
        return true
      end
    end
  end
  e.u7a = 4
  return false
end
local function bcsKeep(E, e) -- sub_0803EA64
  local f = E.field
  local t = targetInHome(f, e)
  if t then
    if bcsNear(f, e, 0x4E) then
      local d = lined(E, e, 0x12)
      if d then
        e.u7a = e.u7a - 1
        if e.u7a ~= 0 then return true end
        e.action, e.dir = 5, d
        bcsAnim(E, e, 0)
        return true
      end
    end
    if bcsNear(f, e, 0x38) then return true end
  end
  e.u7a = 4
  return false
end
local function s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end

function M.ballChainSoldier(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- BallChainSoldier_Init
    e.ball = child(E, e, M.P_BALL_AND_CHAIN, { ballType = 0 })
    e.child = e.ball
    e.collideOn = true
    e.staticFrame = nil
    e.animationState = band(R(f), 3)
    e.u7b, e.u7c, e.u7e, e.u7f = 0, 0, 0x20, 0xFE
    e.dir = e.animationState * 8
    setAnim(E, e, lshift(e.animationState, 2))
    bcsStand(E, e)
  elseif a == 1 then -- sub_0803E5E8
    e.u7c = band(e.u7c - 0xA, 0xFF); bcsSpinAnim(E, e)
    if not bcsLook(E, e) then
      e.u78 = e.u78 - 1
      if e.u78 == 0 then bcsWalk(E, e) end
    end
  elseif a == 2 then -- sub_0803E61C
    e.u7c = band(e.u7c - 0xA, 0xFF); bcsSpinAnim(E, e)
    if not bcsLook(E, e) then
      if (e.kbt or 0) == 0 and not move0(E, e, e.dir, e.speed ~= 0 and e.speed or 0x80) then bcsStand(E, e) return end
      e.u78 = e.u78 - 1
      if e.u78 == 0 then if band(R(f), 1) ~= 0 then bcsStand(E, e) else bcsWalk(E, e) end end
    end
  elseif a == 3 then -- sub_0803E66C
    e.u7c = band(e.u7c - 0x10, 0xFF); bcsSpinAnim(E, e)
    if e.u7e <= 0x21 then e.u7e = e.u7e + 1 end
    if not targetInHome(f, e) or not bcsKeep(E, e) then e.action, e.u7b = 4, 0 end
  elseif a == 4 then -- sub_0803E6B4
    e.u7c = band(e.u7c - 0xA, 0xFF); bcsSpinAnim(E, e)
    if e.u7e > 0x20 then e.u7e = e.u7e - 1 else bcsStand(E, e) end
  elseif a == 5 then -- sub_0803E6E0
    e.u7c = band(e.u7c - 0xC, 0xFF); bcsSpinAnim(E, e)
    e.u7e = band(e.u7e - 4, 0xFF)
    if s8(e.u7e) <= 0 then
      e.u7e, e.action, e.timer = 0, 6, 30
      setAnim(E, e, e.animationState + 0x20)
    end
  elseif a == 6 then -- sub_0803E71C
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.timer = 7, 1
      e.u7c = M.BCS_ANGLE[e.animationState or 0]
      e.u7b, e.u7f = 0, 0xF6
      f:sound(SFX_15B)
    end
  elseif a == 7 then -- sub_0803E75C
    if band(fflags(e), 0x80) == 0 and not e.anim.done then e.anim:update(1)
    else
      e.timer = e.timer - 1
      if e.timer == 0 then e.timer = 2; e.u7f = band(e.u7f + 1, 0xFF) end
      if e.u7f ~= 0 then e.u7e = band(e.u7e + 5, 0xFF)
      else
        e.action, e.timer = 8, 30
        if f.shake then pcall(f.shake, f, 8, 0) end -- InitScreenShake(8, 0)
        f.screenShake = 8
      end
    end
  elseif a == 8 then -- sub_0803E7B4
    e.timer = e.timer - 1
    if e.timer == 0 then e.action = 9 end
  elseif a == 9 then -- sub_0803E7CC
    e.u7e = band(e.u7e - 2, 0xFF)
    if e.u7e <= 0xA then
      e.action, e.timer = 10, 90
      e.dir = (e.animationState or 0) * 8
      e.u7c, e.u7f = 0, 0xFE
      bcsAnim(E, e, 0x10)
    elseif e.u7e <= 0x12 then
      if e.ball then e.ball.noTouch = true end
    end
  elseif a == 10 then -- sub_0803E818
    if e.timer ~= 0 then
      e.timer = e.timer - 1
      if e.timer == 0 then
        if e.ball then e.ball.noTouch = nil end
        bcsAnim(E, e, 0)
      end
    else
      e.u7c = band(e.u7c - 0xA, 0xFF); bcsSpinAnim(E, e)
      e.u7e = e.u7e + 1
      if e.u7e > 0x1F then bcsStand(E, e) end
    end
  end
end

-- the ball (type 0), the links (1-3), the ghosts (4)
function M.ballAndChain(E, e)
  local f = E.field
  local t = e.ballType or 0
  if t == 0 then -- sub_080AB074
    local s = e.parent
    if parentGone(e) then e.deleted = true return end
    if e.action == 0 then
      for k = 1, 3 do child(E, e, M.P_BALL_AND_CHAIN, { ballType = k, parent = e, soldier = s, hitbox = { x = 0, y = 0, w = 2, h = 2 } }) end
      e.action = 1
      e.staticFrame = 0
      e.spritePriority = 3
    end
    local h7f = s8(s.u7f or 0)
    local r = s.u7e or 0
    e.x = s.x + SIN[band(s.u7c or 0, 0xFF)] * r / 256
    e.y = s.y - 10 - h7f - SIN[band(s.u7c or 0, 0xFF) + 0x40] * r / 256
    e.layer = s.layer
    e.cz = -(s.z or 0) + h7f -- the cartridge's z (negative up)
    e.z = -e.cz
    if (s.u7b or 0) ~= 0 then
      local g = child(E, e, M.P_BALL_AND_CHAIN, { ballType = 4, parent = e, noTouch = true, x = e.x, y = e.y, z = e.z })
      g.timer, g.staticFrame, g.action = 5, 0, 1
    end
  elseif t == 4 then -- sub_080AB26C
    e.timer = (e.timer or 5) - 1
    if e.timer <= 0 then e.deleted = true else e.staticFrame = (e.staticFrame or 0) + 1 end
  else -- sub_080AB170
    local b = e.parent
    if parentGone(e) then e.deleted = true return end
    local s = b.parent
    if not s then e.deleted = true return end
    if e.action == 0 then e.action, e.staticFrame, e.spritePriority = 1, 5, 3 end
    e.noTouch = (e.u7c == s.u7c) or nil
    e.u7c = s.u7c
    local fl = s.anim and s.anim.flags or 0
    local ox, oy = 0, -10
    if band(fl, 0x20) == 0 then
      local i = band(fl, 0x1F)
      ox, oy = M.HAND[i] or 0, M.HAND[i + 1] or 0
    end
    local x, y = math.floor(s.x) + ox, math.floor(s.y) + oy
    local cz = -math.floor(s.z or 0)
    local function step(from, to) local v = (math.floor(to) - from) * t if v < 0 then v = v + 3 end return from + math.floor(v / 4) end
    e.x = step(x, b.x)
    e.y = step(y, b.y)
    e.cz = step(cz, b.cz or 0)
    e.z = -e.cz
    e.layer = s.layer
  end
end

-- ===========================================================================
-- GOBDO (gibdo.c)
-- ===========================================================================
local function gibStand(E, e) -- sub_08037794
  e.action, e.u74, e.hitType = 1, 30, 0x26
  setAnim(E, e, e.animationState)
end
local function gibSees(E, e) -- sub_08037810
  local f = E.field
  if (e.u76 or 0) == 0 then
    local t = targetInHome(f, e)
    if t and within(e, t.x, t.y, 0x40) then
      local dir = dirTo(e.x, e.y, t.x, t.y)
      if band(dir - (e.dir or 0) + 6, 0x1F) <= 0xC then
        e.action, e.timer, e.subtimer, e.speed = 3, 24, 8, 0xC0
        e.dir = roundUp(dir)
        e.animationState = rshift(e.dir, 3)
        e.u74 = 300
        e.u78, e.u7a = math.floor(t.x), math.floor(t.y)
        setAnim(E, e, e.animationState)
        return true
      end
    end
  else e.u76 = e.u76 - 1 end
  return false
end
local function gibLunge(E, e) -- sub_080378B0
  local f = E.field
  if (e.u77 or 0) == 0 then
    local t = target(f)
    if t and lined(E, e, 0xA) == e.dir and within(e, t.x, t.y, 0x18) then
      e.action, e.speed = 5, 0x100
      setAnim(E, e, e.animationState + 8)
      return true
    end
  else e.u77 = e.u77 - 1 end
  return false
end
local function gibWalk(E, e) -- sub_080377B0
  local f = E.field
  e.action, e.subtimer = 2, 8
  e.u74 = band(R(f), 0x38) + 120
  e.speed = 0x40
  local r2 = R(f)
  if not selfInHome(e) and band(r2, 3) ~= 0 then e.dir = roundUp(homeDir(e)) else e.dir = band(r2, 0x18) end
  e.animationState = math.floor(e.dir / 8)
  setAnim(E, e, e.animationState + 4)
end
local function gibAim(E, e) -- sub_0803797C
  e.timer, e.subtimer = 24, 8
  local m = band(dirTo(e.x, e.y, e.u78, e.u7a) + 4, 0x18)
  e.dir = m
  m = rshift(m, 3)
  if m ~= e.animationState then e.animationState = m; setAnim(E, e, m + 4) end
end
local function gibTurn(E, e) -- sub_080379BC
  local r = R(E.field)
  e.timer, e.subtimer = 24, 8
  e.animationState = band((e.animationState or 0) + band(r, 2) - 1, 3)
  e.dir = e.animationState * 8
  setAnim(E, e, e.animationState + 4)
end
local function gibFollow(E, e) -- sub_08037914
  local f = E.field
  local t = targetInHome(f, e)
  if t then
    local tx, ty = math.floor(t.x), math.floor(t.y)
    if not within(t, e.u78, e.u7a, 0x28) then
      e.u78, e.u7a = tx, ty
      gibAim(E, e)
      return false
    end
    if not within(e, e.u78, e.u7a, 8) then return false end
    e.u76 = 60
  end
  gibStand(E, e)
  return true
end
local function freeLink(E, e) -- sub_08037ACC
  local f = E.field
  local p = f.player
  if p.gibdo == e then
    p.gibdo = nil
    if p.state == "ext" and p.extUpdate == e.holdFn then p.state, p.extUpdate = "normal", nil end
  end
  p.invuln = 30
  local vx, vy = dirVec((e.animationState or 0) * 8)
  p.kbx, p.kby, p.timer = vx * 0x180 / 256, vy * 0x180 / 256, 4
  if p.state == "normal" then p.state = "hurt" end -- knockbackDuration 4 (the port's knockback state)
end
local function gibRelease(E, e) -- sub_08037A58
  freeLink(E, e)
  e.action = 7
  e.spritePriority = 4
  e.hitType = 0x26
  e.noTouch = nil
  e.iframes = 12 -- (s8)$F4
  local vx, vy = dirVec(bxor((e.animationState or 0) * 8, 0x10))
  e.kbx, e.kby, e.kbt = vx * 0x180 / 256, vy * 0x180 / 256, 8
  e.u76 = 60
  setAnim(E, e, e.animationState + 0x10)
end
M.gibRelease = gibRelease
local function gibBite(E, e) -- sub_08037B10
  local f = E.field
  local p = f.player
  p.invuln = 0xC
  f:modStat("health", -8)
  f:sound(SFX_PLY_VO6)
  if (f.save.stats.health or 0) <= 0 then
    gibRelease(E, e)
    e.u76 = 240
  end
end
local function gibGrab(E, e) -- sub_08037A14
  local f = E.field
  local p = f.player
  e.action, e.timer = 6, 24
  e.spritePriority = 3
  e.noTouch = true -- collisionMask &= $FE
  e.u7c = 5
  e.x, e.y = p.x, p.y -- CopyPosition(super, contactedEntity)
  p.gibdo = e
  e.holdFn = function(pp, input) -- PlayerInputPressed
    for _, b in ipairs({ "a", "b", "r", "l", "up", "down", "left", "right" }) do
      if input and input.pressed and input.pressed(b) then e.pressCount = (e.pressCount or 0) + 1 end
    end
  end
  p.state, p.extUpdate = "ext", e.holdFn
  setAnim(E, e, e.animationState + 0xC)
end
local function gibFlames(E, e) -- Gibdo_CreateObjects
  local f = E.field
  local O = f.objects and f:objects()
  local def = O and O.def and O:def(OBJ_FLAME, 3)
  local offs = { { 0, -4 }, { -3, -8 }, { 5, -11 } }
  e.flames = {}
  for i = 1, 3 do
    local fl = { kind = 6, id = OBJ_FLAME, form = 3, x = e.x, y = e.y, z = 0, timer = e.timer, spritePriority = 3,
                 spriteOX = offs[i][1], spriteOY = offs[i][2], parent = e, animationState = 0, field82 = 0,
                 interactType = 0, layer = e.layer, powFlame = true }
    if def then O:dress(fl, def, 0); fl.objAnim = 0 end
    fl.extUpdate = function(d, me) -- Flame type 3
      local par = me.parent
      if not par or par.deleted then me.deleted = true return end -- parent->next == NULL
      if me.anim then me.anim:update(1) end
      me.timer = (me.timer or 1) - 1
      if me.timer <= 0 then me.deleted = true return end
      me.x, me.y = par.x, par.y -- CopyPosition
    end
    f.entities[#f.entities + 1] = fl
    if f._dungeon and f._dungeon.track then f._dungeon:track(fl) end
    e.flames[i] = fl
  end
  f:sound(SFX_124)
end

function M.gibdoCollision(E, e, fl)
  local f = E.field
  if fl == 0x87 then
    if e.action == 6 then freeLink(E, e) end
    e.action, e.timer = 8, 60
    e.noTouch, e.noHit = true, true
    gibFlames(E, e)
    return
  end
  if e.action ~= 6 then
    if e.hitType == 0x27 and fl == 0x80 then gibGrab(E, e)
    elseif e.action == 1 or e.action == 2 then
      e.action = 1
      local p = f.player
      local d = roundUp(dirTo(e.x, e.y, p.x, p.y)) -- DirectionTurnAround(knockbackDirection)
      e.dir = d
      e.animationState = rshift(d, 3)
      setAnim(E, e, e.animationState)
      if gibSees(E, e) then e.timer = 4 end
    end
  else gibRelease(E, e) end
end

function M.gibdo(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then -- sub_08037558
    e.onCollision = M.gibdoCollision
    e.animationState = band(R(f), 3)
    e.dir = e.animationState * 8
    e.u76, e.u77 = 0, 0
    gibStand(E, e)
  elseif a == 1 then -- sub_08037580
    if not gibSees(E, e) then
      e.u74 = e.u74 - 1
      if e.u74 == 0 then gibWalk(E, e) end
    end
  elseif a == 2 then -- sub_080375A4
    if not gibLunge(E, e) and not gibSees(E, e) then
      e.u74 = e.u74 - 1
      if e.u74 == 0 then gibStand(E, e)
      else
        e.anim:update(1)
        if not move0(E, e, e.dir, e.speed) then
          e.subtimer = e.subtimer - 1
          if e.subtimer == 0 then gibTurn(E, e) end
        end
      end
    end
  elseif a == 3 then -- sub_080375F8
    if not gibLunge(E, e) then
      e.timer = e.timer - 1
      if e.timer == 0 then e.action, e.timer = 4, 24; setAnim(E, e, e.animationState + 4) end
    end
  elseif a == 4 then -- sub_08037624
    if not gibLunge(E, e) and not gibFollow(E, e) then
      e.u74 = e.u74 - 1
      if e.u74 == 0 then gibStand(E, e)
      else
        e.anim:update(1); e.anim:update(1)
        if not move0(E, e, e.dir, e.speed) then
          e.subtimer = e.subtimer - 1
          if e.subtimer == 0 then gibTurn(E, e) end
        else
          e.timer = e.timer - 1
          if e.timer == 0 then gibAim(E, e) end
        end
      end
    end
  elseif a == 5 then -- sub_08037690
    e.anim:update(1)
    if done(e) then e.u77 = 20; gibStand(E, e)
    elseif band(fflags(e), 1) ~= 0 then
      e.hitType = 0x27
      move0(E, e, e.dir, e.speed)
    end
  elseif a == 6 then -- sub_080376D0
    local p = f.player
    if (e.pressCount or 0) > 0 then -- sub_080379EC
      e.pressCount = e.pressCount - 1
      e.timer = e.timer - 1
      if e.timer == 0 then gibRelease(E, e) return end
    end
    -- ResetActiveItems, mobility locked: Link stays held
    if p.state ~= "ext" or p.extUpdate ~= e.holdFn then p.state, p.extUpdate = "ext", e.holdFn end
    e.x, e.y = p.x, p.y
    e.anim:update(1)
    if band(fflags(e), 1) ~= 0 then
      e.u7c = e.u7c - 1
      if e.u7c == 0 then gibRelease(E, e)
      else take(e); gibBite(E, e) end
    end
  elseif a == 7 then -- sub_0803773C
    e.anim:update(1)
    if done(e) then gibStand(E, e) end
  elseif a == 8 then -- sub_0803775C: Stalfos
    e.timer = e.timer - 1
    if e.timer == 0 then
      local st = E:spawn({ kind = 3, id = M.STALFOS, paramA = 0, paramB = e.spawnB or 0, paramC = e.spawnC or 0,
                           x = math.floor(e.x), y = math.floor(e.y), collision = 0, pool = 0 })
      if st then
        st.homeX, st.homeY, st.rangeW, st.rangeH = e.homeX, e.homeY, e.rangeW, e.rangeH -- EnemyCopyParams
        st.layer = e.layer
        f.entities[#f.entities + 1] = st
        e.successor = st
        for _, fl in ipairs(e.flames or {}) do fl.timer = 15; fl.parent = st end -- Gibdo_MoveObjectsToStalfos
      end
      e.deleted = true
    end
  end
end

-- ===========================================================================
-- CHUCHU type 2 (yellow)
-- ===========================================================================
local function water(E, e) -- CheckWaterTile (ACT_TILE_16)
  local f = E.field
  local tt = f.room.tileType and f.room:tileType(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16))
  return tt and tt < 0x4000 and f.assets.actTile and f.assets.actTile[tt] == 0x10 or false
end
local function detach(e) if e.zap then e.zap.deleted = true; e.zap = nil end end -- EnemyDetachFX
local function yUp(E, e) -- sub_0801FB14
  e.action, e.subtimer = 3, 30
  e.dir = facingLink(E.field, e)
  setAnim(E, e, 2)
end
local function ySink(E, e) e.action = 7; e.noTouch, e.noHit = true, true; setAnim(E, e, 5) end -- sub_0801FAE0 / sub_0801F730
local function yHit(E, e) e.action, e.hitType, e.zv = 10, 92, 0; detach(e) end -- sub_0801FB68 (type 2)
local function zapFx(E, e) -- EnemyCreateFX(FX_LIGHTNING_STRIKE), type2 64
  local f = E.field
  local O = f.objects and f:objects()
  local def = O and O.def and O:def(SPECIAL_FX, FX_LIGHTNING_STRIKE)
  if not def then return { kind = 6, id = SPECIAL_FX, form = FX_LIGHTNING_STRIKE, type2 = 64, x = e.x, y = e.y, z = 0 } end
  local z = { kind = 6, id = SPECIAL_FX, form = FX_LIGHTNING_STRIKE, type2 = 64, x = e.x, y = e.y, z = e.z or 0,
              animationState = 0, field82 = 0, interactType = 0, layer = e.layer, powZap = true }
  O:dress(z, def, FX_LIGHTNING_STRIKE)
  z.objAnim = 0
  f.entities[#f.entities + 1] = z
  return z
end
local function zapFollow(E, e) -- sub_0801FB34
  local z = e.zap
  if not z then return end
  local T = require("src.zelda.tmc.ExtractR26").tables(E.field, "pow_chuchu_fx")
  local i = band(fflags(e), 0xF)
  local ox = T and T.s8(0x080CA2B4 + i) or 0
  z.x, z.y, z.z, z.layer = e.x + ox, e.y + 1, e.z or 0, e.layer
  z.spriteOY = (e.spriteOY or 0) - 1
  if z.anim and z.anim.update then z.anim:update(1) end
end

function M.yellowCollision(E, e, fl)
  if fl == 0x8E or fl == 0x95 then e.noTouch, e.noHit = true, true; e.health = 0 end
  if e.health > 0 then
    if fl == 0x94 then yHit(E, e); setAnim(E, e, 6)
    elseif (e.u80 or e.health) ~= e.health then yHit(E, e); setAnim(E, e, 6) end
  else
    detach(e)
    e.zv = 0
    setAnim(E, e, 9)
    E:kill(e)
  end
  e.u80 = e.health
end

function M.yellow(E, e)
  local f = E.field
  local a = e.action
  e.onCollision = M.yellowCollision
  if a == 0 then -- sub_0801F7D8
    e.action, e.timer = 1, band(R(f), 0xFF)
    e.u80, e.u82 = e.health, 0
    e.hidden, e.noTouch, e.noHit = true, true, true
  elseif a == 1 then -- sub_0801F7FC
    if targetInHome(f, e) and ((e.u82 or 0) ~= 0 or (function() local t = target(f) return t and within(e, t.x, t.y, 0x48) and band(t.layer or 1, e.layer or 1) ~= 0 end)()) then
      e.action, e.hidden, e.u82 = 2, false, 1
      setAnim(E, e, 0)
    end
  elseif a == 2 then -- sub_0801F840
    e.anim:update(1)
    if done(e) then
      yUp(E, e)
      e.noTouch, e.noHit = nil, nil
      e.spritePriority = 4
    end
  elseif a == 3 then -- sub_0801F884
    e.anim:update(1)
    if (e.subtimer or 0) ~= 0 then e.subtimer = e.subtimer - 1
    else
      local z = zapFx(E, e)
      if z then
        e.zap = z
        e.action, e.hitType = 4, 165
        f:sound(SFX_193)
      end
    end
  elseif a == 4 then -- sub_0801F8C0
    if water(E, e) then ySink(E, e)
    elseif not targetInHome(f, e) then ySink(E, e)
    else
      e.timer = band((e.timer or 0) + 1, 0xFF)
      local t8 = band(e.timer, 7)
      local t = target(f)
      if t8 == 0 and t and within(e, t.x, t.y, 0x38) and band(t.layer or 1, e.layer or 1) ~= 0 then
        e.action = 5
        e.speed, e.zv = 0x180, 2.0 -- Chuchu_JumpAtPlayer
        e.dir = facingLink(f, e)
        setAnim(E, e, 3)
      else
        if t8 == 4 and t then e.dir = dirTo(e.x, e.y, t.x, t.y) end
        move0(E, e, e.dir, e.speed)
        e.anim:update(1)
      end
    end
  elseif a == 5 then -- sub_0801F940
    local fl = fflags(e)
    if band(fl, 0x10) ~= 0 then
      if band(fl, 1) ~= 0 then take(e); f:sound(SFX_12B) end
      move0(E, e, e.dir, e.speed)
      if not DW().gravity(e, 64 / 256) then e.anim:update(1) end
    else e.anim:update(1) end
    if done(e) then
      if water(E, e) then ySink(E, e)
      else e.action, e.subtimer, e.speed = 6, 60, 0x20; setAnim(E, e, 2) end
    end
  elseif a == 6 then -- sub_0801F9C4
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then e.action = 4 end
    e.anim:update(1)
  elseif a == 7 then -- sub_0801F9E0
    e.anim:update(1)
    if done(e) then
      e.action, e.subtimer = 8, 30
      e.dir = facingLink(f, e)
      e.spritePriority = 6
      setAnim(E, e, 1)
    end
  elseif a == 8 then -- sub_0801FA30
    if water(E, e) then
      e.dir = facingLink(f, e)
      move0(E, e, e.dir, e.speed) -- ProcessMovement5
      e.anim:update(1)
    elseif not targetInHome(f, e) then e.action = 9; setAnim(E, e, 7)
    else e.action, e.hidden = 2, false; setAnim(E, e, 4) end -- sub_0801FAF8
  elseif a == 9 then -- sub_0801FA78
    e.anim:update(1)
    if done(e) then
      e.action, e.hidden = 1, true
      setAnim(E, e, 4)
      detach(e)
    end
  elseif a == 10 then -- sub_0801FAAC
    DW().gravity(e, 24 / 256)
    e.anim:update(1)
    if done(e) then yUp(E, e); e.speed = 0x20; detach(e) end
  end
  zapFollow(E, e)
end

-- ===========================================================================
function M.spawnEnemy(E, dat, def)
  M.lastArea = E and E.field and E.field.room and E.field.room.area -- round 27A: the area for M.handles
  return nil -- the definitions build them (Enemies:spawn); the AI is here
end

function M.update(E, e)
  if e.powChild then
    if e.cloud then return M.lakCloud(E, e) end
    if e.lightning then return M.lightning(E, e) end
    if e.ballType then return M.ballAndChain(E, e) end
    return
  end
  if e.spawnY == nil and e.spawnC ~= nil then e.spawnY = e.y end
  local id = e.id
  if id == M.BOMBAROSSA then return M.bombarossa(E, e) end
  if id == M.CROW then return M.crow(E, e) end
  if id == M.LAKITU then return M.lakitu(E, e) end
  if id == M.LAKITU_CLOUD then return M.lakituCloud(E, e) end
  if id == M.BALL_CHAIN_SOLIDER then return M.ballChainSoldier(E, e) end
  if id == M.GOBDO then return M.gibdo(E, e) end
  if id == M.CHUCHU and e.form == 2 then return M.yellow(E, e) end
end

return M
