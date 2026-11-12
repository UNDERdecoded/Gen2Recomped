-- Round 26 (team B): Temple of Droplets enemies, from the decomp.
--
-- PESTO ($11, src/enemy/pesto.c), types 0 / 1 (claimed everywhere: the
--   generic STYLE model in Enemies.lua no longer runs for it).
--   Init (sub_080240B8): $20 px off in a random cardinal, hovering at z -16
--   (type 1: -48, carrying a DIRT_BALL_PROJECTILE type 0 16 px under it),
--   unk_81 = Random & $40, unk_83 $80, subtimer 32.  Every frame
--   (sub_08024940): bounce off walls (sub_0800417E), bob (z + 2 on 7 frames
--   in 8 by Random & $70), back toward the home centre when outside its home,
--   ProcessMovement1 at its speed, GetNextFrame; animation = 8-way facing
--   ((direction + 2) & $1C) >> 2.
--   1 (sub_080241C0): Link (not Minish) within $40 ($A0 while he blinks
--     from a dirt ball) and in its home -> stop, face him 10 frames, then
--     type 0: 2 (circle him: sub_08024C94); type 1 with its ball: 3.
--     Else every 32 frames a turn toward home (sub_08024A14: one step,
--     sub_08004596; a random direction when outside its home 3 in 4).
--   2 (sub_08024D00): zig-zags round Link (unk_81 picks the turn side,
--     timers 32-47 / 32-63, a step every 16 frames); after a hit (Link's
--     body: unk_86 $30) it only animates; Link out of $50 or its home ->
--     1.  unk_83 bit $40 set: looks for a target (sub_08024B38: Link while
--     he blinks within $A0, else a bomb on the ground, else a resting pot)
--     -> 6.
--   3 / 4 / 5 (type 1): approach (timers / speeds gUnk_080CBF10 / 18 / 20),
--     within $20 -> 4 (wait 16, then $100), 5 ($140, 192 frames) drops the
--     dirt ball within $E of Link (the ball hurts 2 and makes him blink
--     $F0 frames), then 6.
--   6 (sub_080244E8): unk_80 0 flies over the target, 1 comes down to -16,
--     2 picks it up (bomb: dirt ball type 1 carries it; pot: the pot object
--     goes, dirt ball type 2 = the pot; Link: touching him (OnCollision)
--     grabs him), 3 / 4 / 5 rises to -60 and back to -48; carrying Link
--     (unk_83 3): button presses (+1 / +2 at random) free him at $30, else
--     2 damage every 32 frames, freed after 4 (sub_08024E4C / sub_08024F50);
--     6 carries the bomb / pot after Link (the ball drops it: the pot near
--     him, the bomb when its fuse is nearly out), 7 waits for Link to land.
-- DIRT_BALL_PROJECTILE ($06) types 0 / 1 / 2: hangs under its Pesto; dropped
--   it falls (BounceUpdate 40) and bursts (type 0: animation 1,
--   SFX_WATER_SPLASH; type 2: FX_POT_SHATTER); type 0 touching Link: 2
--   damage, Link blinks ($F0).
-- SCISSORS_BEETLE ($40, scissorsBeetle.c) + MANDIBLES_PROJECTILE ($13,
--   mandiblesProjectile.c) -- claimed in areas $60-$62 only (team A ports
--   the overworld ones).  Body: wanders on 8-way headings for
--   gUnk_080CF62C frames, the jaws (own entity) swing round it
--   (gUnk_080CF634 / 3C, gUnk_08129CA4 / AC), a wall -> 12 frames and a new
--   heading; the body is solid (sub_0800445C).  Link in front of the jaws
--   within $40 -> they snap (action 2: SFX_15D on frame bit $40, the body
--   stops $50 frames facing him), then the jaws fly off (body action 3 ->
--   4 circling, SFX_15B; jaws action 3 at the body's sprite attachment
--   point (gExtraFrameOffsets), then 4: straight 64 frames at $180, then
--   home on the body (gUnk_08129D14), SFX_F2, reattached).  A hit on the
--   body turns it (and the jaws) to the attacker; a hit on the jaws knocks
--   the body back and makes them snap; flying jaws touching Link: 2 damage.
-- FLYING_POT ($3A, flyingPot.c): sits on SPECIAL_TILE_0 (the tile below
--   kept), Link within $40 -> 30 frames shaking (+-1), hit type $A0, it
--   rises to z 6, aims at Link 10 frames and flies (ProcessMovement2, speed
--   $280) until anything stops it -> FX_POT_SHATTER.  The Pacci cane's bolt
--   ($1D) flips it (zVelocity 2.625).  Lifted (SPECIAL_TILE_103) it is gone.
-- BIG BLUE CHUCHU: CHUCHU_BOSS ($13) type 4, loaded by the light-ray manager
--   ($15 type 1) of room $60:10 (gUnk_080E4C08).  It runs BossChuchu.lua (the
--   decomp's code) with the type-4 differences: forms 4-7 (palette $2C),
--   the splash palette $2C, and sub_080262A8's type2 branch: no walk-in,
--   the drops start at once (unk_03 3), the camera on it, Link faces up,
--   SPECIAL_TILE_34 at tile (8, 11).
-- SIMPLIFIED: the Gust Jar on a Pesto / a flying pot uses the port's
--   generic gust; Link carried by a Pesto is drawn under it at its z - 26
--   and dropped at z 0; the jaws' sprite attachment needs the menu data
--   (NpcParts readers), else the jaws sit on the body; the pot / bomb
--   Pesto pick-ups use the port's pot objects (kind 6, id 5) and bombs.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local T = {}
T.PESTO, T.SCISSORS_BEETLE, T.FLYING_POT, T.CHUCHU_BOSS = 0x11, 0x40, 0x3A, 0x13
local DIRT_BALL, MANDIBLES = 0x06, 0x13
local SFX = { SPLASH = 0x84, VO6 = 0x7A, S15B = 0x15B, S15D = 0x15D, F2 = 0xF2, S1B5 = 0x1B5 }
local SPECIAL_FX, FX_POT_SHATTER, FX_WATER_SPLASH = 0x0F, 0x05, 0x0B

-- tables written out in the .c files
T.PESTO_TIMER = { [0] = 30, 60, 50, 90, 70, 100, 90, 120 }                       -- gUnk_080CBF10
T.PESTO_SPEED = { [0] = 0x80, 0xC0, 0x100, 0x140 }                               -- gUnk_080CBF18
T.PESTO_IDX = { [0] = 0, 2, 1, 1, 3, 1, 2, 0, 1, 1, 2, 3, 2, 2, 1, 2 }           -- gUnk_080CBF20
T.BEETLE_T1 = { [0] = 0x2D, 0x5A, 0x3C, 0x2D, 0x5A, 0x4B, 0x3C, 0x5A }           -- gUnk_080CF62C
T.BEETLE_T2 = { [0] = 0x18, 0x24, 0x34, 0x20, 0x3C, 0x1C, 0x2C, 0x28 }           -- gUnk_080CF634
T.BEETLE_SW = { [0] = 1, 0, 7, 1, 0, 7, 0, 0 }                                   -- gUnk_080CF63C
T.MAND_T = { [0] = 24, 36, 52, 32, 60, 28, 44, 40 }                              -- gUnk_08129CA4
T.MAND_SW = { [0] = 1, 0, 7, 1, 0, 7, 0, 0 }                                     -- gUnk_08129CAC
T.MAND_PT = { [0] = 0, -16, 6, -10, 0, 4, -6, -10 }                              -- gUnk_08129D14
T.MAND_HB = { [0] = { 0, -4, 6, 8 }, { 3, -3, 6, 6 }, { 4, 0, 8, 6 }, { 3, 3, 6, 6 }, -- gUnk_08129CB4..CEC {x, y, w, h}
              { 0, 4, 6, 8 }, { -3, 3, 6, 6 }, { -4, 0, 8, 6 }, { -3, -3, 6, 6 } }
local POT_SHAKE = { [0] = -1, 1, 1, -1 }                                          -- FlyingPot_Action2 offsets

local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function R(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end
local function dirTo(ax, ay, bx, by) return DW().dirTo(ax, ay, bx, by) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function inHome(e, x, y)
  if not e.homeX then return true end
  return x - e.homeX >= 0 and x - e.homeX <= e.rangeW and y - e.homeY >= 0 and y - e.homeY <= e.rangeH
end
local function homeDir(e)
  if not e.homeX then return e.dir or 0 end
  return dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2)
end
local function dist2(a, b) local dx, dy = math.floor(b.x) - math.floor(a.x), math.floor(b.y) - math.floor(a.y) return dx * dx + dy * dy end
local function within(a, b, d) return dist2(a, b) <= d * d end -- sub_08049F1C
local function turn1(e, want) -- sub_08004596: one step toward
  local dd = band(want - (e.dir or 0), 0x1F)
  if dd ~= 0 then e.dir = band((e.dir or 0) + (dd < 0x10 and 1 or -1), 0x1F) end
end
local function areaOf(f) return f and f.room and f.room.area or 0 end

-- the enemy target (sub_08049EB0: not Minish, not captured)
local function target3(f)
  local p = f.player
  if p.state == "dead" or p.minish or p.pestoHeld or p.hidden then return nil end
  return p
end

-- ===========================================================================
-- spawning: the base entity comes from Enemies:spawn (re-entered once)
-- ===========================================================================
local inner = false
function T.spawnEnemy(E, dat, def)
  if inner then return nil end
  local f = E.field
  if dat.id == T.CHUCHU_BOSS and band(dat.paramA or 0, 0xFF) == 4 then return T.blueChuchu(E, dat, def) end
  local mine = dat.id == T.PESTO or dat.id == T.FLYING_POT
            or (dat.id == T.SCISSORS_BEETLE and areaOf(f) >= 0x60 and areaOf(f) <= 0x62)
  if not mine then return nil end
  inner = true
  local ok, e = pcall(E.spawn, E, dat)
  inner = false
  if not ok then error(e, 0) end
  if not e then return false end
  e.todOwn = true
  e.type2 = band(dat.paramB or 0, 0xFF)
  return e
end
function T.handles(e) return e.todOwn == true end

function T.update(E, e)
  if e.id == T.PESTO then return T.pesto(E, e)
  elseif e.id == T.SCISSORS_BEETLE then return T.beetle(E, e)
  elseif e.id == T.FLYING_POT then return T.flyingPot(E, e) end
end

-- ===========================================================================
-- PESTO
-- ===========================================================================
local function pAnimSet(E, e) e.animationState = rshift(band(e.dir + 2, 0x1C), 2); setAnim(E, e, e.animationState) end -- sub_080249DC
local function pAnimUpd(E, e) -- sub_080249F4
  local s = rshift(band(e.dir + 2, 0x1F), 2)
  if s ~= e.animationState then e.animationState = s; setAnim(E, e, s) end
end
local function syncZ(e) e.z = -(e.zh or 0) end

local function validChild(e)
  local c = e.child
  if not c or c.deleted then e.child = nil return false end
  if c ~= e.field_p and (c.z or 0) > 0 and not c.carriedByPesto then e.child = nil return false end
  return true
end
function T.c48(E, e, unk) -- sub_08024C48
  if unk then return target3(E.field) ~= nil end
  return validChild(e)
end
function T.a14(E, e, mode, t) -- sub_08024A14
  local f = E.field
  local ok = false
  if mode == 0 then turn1(e, homeDir(e)); ok = true
  elseif mode == 1 then if T.c48(E, e, false) then turn1(e, dirTo(e.x, e.y, e.child.x, e.child.y)); ok = true end
  elseif mode == 2 then if T.c48(E, e, true) then local p = f.player; turn1(e, dirTo(e.x, e.y, p.x, p.y)); ok = true end
  elseif mode == 3 then if T.c48(E, e, true) then local p = f.player; e.dir = dirTo(e.x, e.y, p.x, p.y); ok = true end end
  if mode ~= 0 and not inHome(e, e.x, e.y) and band(R(f), 3) ~= 0 then ok = false end
  if not ok then return T.a14(E, e, 0, t) end
  pAnimSet(E, e)
  e.subtimer = t
end
local function pTick(E, e) -- sub_08024940
  local f = E.field
  local rnd = band(R(f), 0x70)
  if e.colX or e.colY then
    local d = e.dir
    if e.colX then d = 0x20 - d end
    if e.colY then d = 0x10 - d end
    e.dir = band(d, 0x1F)
    pAnimUpd(E, e)
  end
  if e.u82 == 0 then
    e.zh = e.u78
    if rnd ~= 0 then e.zh = e.zh + 2 end
  end
  if not inHome(e, e.x, e.y) then e.dir = homeDir(e); pAnimUpd(E, e) end
  e.spritePriority = (e.zh < -0x20) and 0 or 1
  e.colX, e.colY = T.move1(E, e, e.dir, e.speed or 0x40)
  e.anim:update(1)
  syncZ(e)
end
-- ProcessMovement1 (a flyer: water and pits do not stop it; walls do, unless
-- it already hovers over one)
function T.move1(E, e, dir, speed)
  local room = E.field.room
  local a = (dir % 32) * math.pi / 16
  local vx, vy = math.sin(a) * speed / 256, -math.cos(a) * speed / 256
  local L = e.layer == 2 and 2 or 1
  local here = room:isSolid(e.x, e.y, L)
  local hx, hy = false, false
  local nx = e.x + vx
  if nx < 8 or nx > room.width - 8 or (not here and room:isSolid(nx + (vx > 0 and 6 or -6), e.y, L)) then hx = vx ~= 0 else e.x = nx end
  local ny = e.y + vy
  if ny < 8 or ny > room.height - 8 or (not here and room:isSolid(e.x, ny + (vy > 0 and 6 or -6), L)) then hy = vy ~= 0 else e.y = ny end
  return hx, hy
end
local function pTimer(E, e, unk) e.timer = T.PESTO_TIMER[T.PESTO_IDX[rshift(band(R(E.field), 0x3C), 2)] * 2 + unk] end -- sub_08024E00
local function pSpeed(E, e) e.speed = T.PESTO_SPEED[T.PESTO_IDX[rshift(band(R(E.field), 0x3C), 2)]] end   -- sub_08024E1C
local function pToIdle(E, e) e.action, e.speed, e.timer = 1, 0x40, 0; T.a14(E, e, 0, 0x20) end           -- sub_08024C7C
local function pChase(E, e) -- sub_08024C94
  e.action, e.u80, e.timer, e.subtimer, e.speed, e.u83 = 2, 0, 64, 0, 0xC0, 0x80
  T.a14(E, e, 3, e.subtimer)
end
local function pNear(E, e) -- sub_08024CC0
  if not T.c48(E, e, true) then return false end
  local p = E.field.player
  if not within(e, p, 0x50) or not inHome(e, p.x, p.y) then pToIdle(E, e) return false end
  return true
end
-- sub_08024B38: Link blinking, a bomb, a pot
function T.findTarget(E, e)
  local f = E.field
  local p = f.player
  if (p.r26Blink or 0) > 0 then
    if T.c48(E, e, true) and within(e, p, 0xA0) then
      e.child = p; e.field_p = p
      e.u83 = band(bor(e.u83, 3), bit.bnot(0x40))
      return true
    end
    e.child = nil
    return false
  end
  for _, b in ipairs(f.entities) do
    if b.bomb and not b.deleted and b.action ~= 2 and (b.z or 0) == 0 and within(e, b, 0xA0) then
      e.child = b
      e.u83 = band(bor(e.u83, 1), bit.bnot(0x40))
      return true
    end
  end
  for _, o in ipairs(f.entities) do
    if o.kind == 6 and o.id == 5 and not o.deleted and not o.thrown and (o.z or 0) == 0 and within(e, o, 0xA0) then
      e.child = o
      e.u83 = band(bor(e.u83, 2), bit.bnot(0x40))
      return true
    end
  end
  e.child = nil
  return false
end
local function pValid(E, e) -- sub_08024AD8
  if band(e.u83, 0x40) == 0 then
    local unk = false
    if band(e.u83, 0x3F) == 3 then
      if (E.field.player.r26Blink or 0) == 0 then e.child = nil; e.u83 = 0xC0 return false end
      unk = true
    end
    if not T.c48(E, e, unk) then e.child = nil; e.u83 = 0xC0 return false end
    return true
  end
  return T.findTarget(E, e)
end

function T.pestoCollision(E, e, fl)
  if e.hitType ~= 0x6E then
    if fl == 0x80 then
      e.u86 = 0x30
      if band(e.u83, 0xF) == 3 and e.action == 6 then
        if e.u80 == 1 then e.zh, e.u82, e.u78, e.u80 = -0x10, 0, -0x10, 2 end
        if e.u80 == 2 then e.u83 = band(e.u83, bit.bnot(0x80)) end
      end
    end
  else e.health = 0 end
end

-- the dirt ball (DIRT_BALL_PROJECTILE)
function T.dirtBall(E, e, type)
  local f = E.field
  local defs = f.assets.manifest.projectileDefs
  local d = defs and defs[DIRT_BALL]
  if d and d.multi then d = d.forms[type] or d.forms[0] end
  d = d or {}
  local b = { kind = 4, id = DIRT_BALL, type = type, x = e.x, y = e.y - 1, z = 0, parent = e, action = 1, zv = 0.5,
              sprite = d.sprite, gfx = Assets.gfxSource("enemy", d.gfx or 0), anim = Anim.new(), literalAnim = true,
              hitType = d.damageType or 0x78, hitbox = { x = 0, y = -3, w = 6, h = 6 }, field82 = 0, interactType = 0, layer = e.layer or 1,
              timer = 0, subtimer = 0 }
  b.palette = E.A:objPalette(d.palette or 1, f.room.atlas and f.room.atlas.palettes)
  local idx = type == 2 and 5 or 0
  b.objAnim, b.animIndex = idx, idx
  if b.sprite and E.A.sprite then b.anim:set(E.A:sprite(b.sprite), idx, true) end
  if type == 1 then b.sprite = nil end
  b.extUpdate = function(_, me) T.dirtUpdate(E, me) end
  f.entities[#f.entities + 1] = b
  if f._dungeon then f._dungeon:track(b) end
  return b
end
function T.dirtUpdate(E, b)
  local f = E.field
  local par = b.parent
  if b.deleted then return end
  if b.type == 1 and (not b.child or b.child.deleted) then b.deleted = true return end
  local p = f.player
  if b.action == 1 then
    if not par or par.deleted or par.dying then b.action = 2
    else
      b.x, b.y = par.x, par.y - 1
      b.z = (par.z or 0) - (b.type == 0 and 16 or 14)
      if b.type == 1 then
        local bomb = b.child
        bomb.x, bomb.y, bomb.z, bomb.carriedByPesto = b.x, b.y, b.z, true
        b.timer = band(b.timer + 1, 0xFF)
        if b.timer > 0xF and (bomb.timer or 0) == 0 then
          if band(b.timer, 2) ~= 0 then bomb.subtimer = (bomb.subtimer or 0) + 1 end
          if (bomb.subtimer or 0) < 0x20 and band(bomb.subtimer or 0, 3) == 3 then par.u83 = 0xC0; b.action = 2 end
        end
      elseif b.type == 2 then
        if math.abs(b.x - p.x) <= 0xE and math.abs(b.y - p.y) <= 0xE then b.action = 2; par.u83 = 0xC0 end
      end
    end
    if b.type == 0 and b.action == 1 and T.touch(E, b) then -- OnCollision type 0
      if par then par.child = nil end
      p.r26Blink = 0xF0
      b.deleted = true
    end
  elseif b.action == 2 then
    if b.type == 1 and b.child then b.child.x, b.child.y, b.child.z = b.x, b.y, b.z end
    b.z = b.z + b.zv; b.zv = b.zv - 40 / 256 -- BounceUpdate(40)
    if b.z > 0 then return end
    b.z = 0
    if b.type == 0 then
      b.action = 3
      b.objAnim = 1; b.animIndex = 1
      if b.sprite then b.anim:set(E.A:sprite(b.sprite), 1, true) end
      f:sound(SFX.SPLASH)
      if par then par.child = nil end
      if T.touch(E, b) then p.r26Blink = 0xF0 end
      return
    end
    if b.type == 1 and b.child then b.child.carriedByPesto = nil end
    if b.type == 2 then f:addFx(b.x, b.y, SPECIAL_FX, FX_POT_SHATTER); T.touch(E, b) end
    b.deleted = true
  elseif b.action == 3 then
    b.anim:update(1)
    if b.anim.done then b.deleted = true end
  end
end
-- Link touched by a small entity: the collision matrix
function T.touch(E, s)
  local f = E.field
  local p = f.player
  if p.hidden or p.state == "dead" or (p.invuln or 0) > 0 or (s.z or 0) > 12 then return false end
  local hb = s.hitbox
  if math.abs((s.x + (hb.x or 0)) - p.x) < (hb.w or 6) + 5 and math.abs((s.y + (hb.y or 0)) - (p.y - 3)) < (hb.h or 6) + 6 then
    local st = E.settings and E:settings(s.hitType or 0, p.minish and 1 or 0) or nil
    local dmg = st and st.tgtDmg or 2
    if dmg > 0 and p:hurt(dmg, s.x, s.y) then p.invuln = math.max(st and st.orgIfr or 30, 30) end
    return true
  end
  return false
end

-- Link held by the Pesto
local function holdLink(E, e)
  local f = E.field
  local p = f.player
  p.pestoHeld, p.state = e, "ext"
  p.extUpdate = function(pl, input)
    if input and input.pressed then
      for _, k in ipairs({ "a", "b", "r", "l", "up", "down", "left", "right", "return" }) do
        if input.pressed(k) then e.u84 = e.u84 + 1 + band(R(f), 1) break end
      end
    end
    pl.anim:update(1)
  end
end
function T.releaseLink(E, e) -- sub_08024F50
  local p = E.field.player
  if p.pestoHeld == e then
    p.pestoHeld = nil
    if p.state == "ext" then p.state, p.extUpdate, p.animId = "normal", nil, -1 end
    p.x, p.y, p.z, p.spriteOY = e.x, e.y, 0, nil
    p.invuln = 60
  end
  e.u83, e.u80, e.u84, e.speed = 0xC0, e.u80 + 2, 0, 0x80
end
local function carryLink(E, e) -- sub_08024E4C
  local f = E.field
  local p = f.player
  e.subtimer = band(e.subtimer + 1, 0x1F)
  if (f.save.stats.health or 1) <= 0 or e.u87 == 4 then
    e.u84, e.u87 = 0x30, 0
    T.releaseLink(E, e)
    e.u80, e.speed, e.timer, e.subtimer = 0, 0x40, 64, 8
    T.a14(E, e, 0, 8)
    return
  end
  if p.pestoHeld ~= e then holdLink(E, e) end
  p.x, p.y = e.x, e.y + 1
  p.z = (e.z or 0) - 26
  p.animationState = 4
  if e.subtimer == 0 then
    e.u87 = e.u87 + 1
    if f.modStat then f:modStat("health", -2) else f.save.stats.health = (f.save.stats.health or 0) - 2 end
    f:sound(SFX.VO6)
  end
end

function T.pesto(E, e)
  local f = E.field
  local p = f.player
  -- the blink a dirt ball gave Link (gPlayerState.hurtBlinkSpeed) runs down once a frame
  if (p.r26Blink or 0) > 0 and p.r26BlinkF ~= f.frame then p.r26BlinkF = f.frame; p.r26Blink = p.r26Blink - 1 end
  local a = e.action
  if a == 0 then -- sub_080240B8
    local dir = rshift(band(R(f), 0xC0), 3)
    e.action, e.u80 = 1, 0
    if band(dir, 8) ~= 0 then e.y = e.y + (band(dir, 0x10) ~= 0 and -0x20 or 0x20)
    else e.x = e.x + (band(dir, 0x10) ~= 0 and -0x20 or 0x20) end
    if e.form == 1 then e.u78 = -0x30 else e.u78 = -0x10 end
    e.zh = e.u78
    e.u81, e.u82, e.u83, e.u84, e.u86, e.u87 = band(R(f), 0x40), 0, 0x80, 0, 0, 0
    e.timer, e.subtimer = 0, 32
    e.dir = dir
    e.speed = e.speed ~= 0 and e.speed or 0x40
    e.onCollision = T.pestoCollision
    pAnimSet(E, e)
    syncZ(e)
    if e.form == 1 then
      e.u83 = 0
      e.child = T.dirtBall(E, e, 0)
    end
  elseif a == 1 then -- sub_080241C0
    pTick(E, e)
    if e.u80 == 0 then
      local t = target3(f)
      if t and within(e, t, (p.r26Blink or 0) > 0 and 0xA0 or 0x40) and inHome(e, t.x, t.y) then
        e.u80, e.speed = 1, 0
        T.a14(E, e, 3, 10)
      else
        e.subtimer = e.subtimer - 1
        if e.subtimer <= 0 then T.a14(E, e, 0, 0x20) end
      end
    else
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 then
        if e.form ~= 0 then
          if band(e.u83, 0x80) ~= 0 then pChase(E, e); e.u83 = bor(e.u83, 0x40)
          else
            e.action, e.u80, e.subtimer = 3, 0, 10
            pTimer(E, e, 0); pSpeed(E, e)
            T.a14(E, e, 3, e.subtimer)
          end
        else pChase(E, e) end
      end
    end
  elseif a == 2 then -- sub_08024D00
    if e.u86 > 0 then e.u86 = e.u86 - 1; e.anim:update(1) else pTick(E, e) end
    if band(e.u83, 0x40) ~= 0 and T.findTarget(E, e) then
      e.action, e.u80 = 6, 2
    elseif pNear(E, e) then
      if e.u80 == 0 then
        e.timer = e.timer - 1
        if e.timer <= 0 then
          e.u80 = 1
          e.timer = band(R(f), 0xF) + 32
          e.dir = band(e.dir + (e.u81 ~= 0 and 4 or 0x1C), 0x1F)
          e.u81 = bxor(e.u81, 0x40)
          T.a14(E, e, 3, 0x10)
        end
      else
        e.timer = e.timer - 1
        if e.timer <= 0 then e.u80 = 0; e.timer = band(R(f), 0x1F) + 32
        else
          e.subtimer = e.subtimer - 1
          if e.subtimer <= 0 then
            e.dir = band(e.dir + (e.u81 ~= 0 and 1 or 0x1F), 0x1F)
            e.subtimer = 16
            pAnimSet(E, e)
          end
        end
      end
    end
  elseif a == 3 then -- sub_080242A0
    pTick(E, e)
    if pNear(E, e) then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.dir = dirTo(e.x, e.y, p.x, p.y)
        pTimer(E, e, 1)
        if e.speed ~= 0 then e.speed = 0 else pSpeed(E, e) end
      else
        e.subtimer = e.subtimer - 1
        if e.subtimer <= 0 then T.a14(E, e, 3, 10) end
      end
      if within(e, p, 0x20) and inHome(e, p.x, p.y) then e.action, e.u80, e.timer, e.speed = 4, 0, 16, 0 end
    end
  elseif a == 4 then -- sub_0802433C
    pTick(E, e)
    e.timer = e.timer - 1
    if e.u80 == 0 then
      if e.timer <= 0 then e.u80, e.speed, e.subtimer = 1, 0x100, 8; pTimer(E, e, 1) end
    elseif e.timer <= 0 then e.action, e.u80, e.speed, e.timer, e.subtimer = 5, 0, 0x140, 192, 8
    else
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 then T.a14(E, e, 2, 4) end
    end
  elseif a == 5 then -- sub_080243B8
    pTick(E, e)
    if e.u80 == 0 then
      if T.c48(E, e, true) then
        if not e.child or e.child.deleted then e.u80, e.timer, e.speed, e.u83 = 2, 32, 0x80, 0x80
        elseif within(e, p, 0xE) then
          e.u80, e.timer, e.speed, e.u83 = 1, 30, 0x100, 0x80
          e.child.action = 2
        else
          e.timer = e.timer - 1
          if e.timer ~= 0 then
            e.subtimer = e.subtimer - 1
            if e.subtimer <= 0 then T.a14(E, e, 2, rshift(e.timer, 6) + 1) end
          else pToIdle(E, e) end
        end
      else pToIdle(E, e) end
    elseif e.u80 == 1 then
      e.timer = e.timer - 1
      if e.timer <= 0 then e.u80, e.timer, e.speed = 2, 32, 0x80 end
    else
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.action, e.u80, e.speed = 6, 0, 0x80
        T.findTarget(E, e)
        if band(e.u83, 0x40) == 0 then
          local k = band(e.u83, 0x3F)
          e.timer = (k == 3) and 4 or (k == 1) and 20 or 48
          T.a14(E, e, 2, 8)
        else e.timer = 64; T.a14(E, e, 0, 8) end
      end
    end
  elseif a == 6 then
    T.pestoGrab(E, e)
  end
  -- hovering above 8 px the shared contact code (z < 8) skips it: the
  -- cartridge's collision has no height cut-off for it
  if (e.z or 0) >= 8 and e.action >= 1 and not p.pestoHeld and (p.invuln or 0) == 0 then
    local zz = e.z; e.z = 0
    local hit = T.touch(E, e)
    e.z = zz
    if hit then T.pestoCollision(E, e, 0x80) end
  end
end

function T.pestoGrab(E, e) -- sub_080244E8
  local f = E.field
  local p = f.player
  pTick(E, e)
  local u = e.u80
  if u == 0 then
    e.timer = e.timer - 1
    if e.timer <= 0 then
      if not f.room:isSolid(e.x, e.y, e.layer or 1) then e.u80, e.u82, e.subtimer, e.speed = 1, e.u82 + 1, 0, 0
      else e.timer, e.subtimer = 48, 4 end
    else
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 then T.a14(E, e, 1, 8) end
    end
  elseif u == 1 then
    e.zh = e.zh + 1; syncZ(e)
    if e.zh >= -0x10 then
      e.u82, e.u78 = 0, -16
      if pValid(E, e) then e.u80 = 2 else pChase(E, e); e.u83 = bor(e.u83, 0x40) end
    end
  elseif u == 2 then
    if pValid(E, e) then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        if e.speed ~= 0 then e.speed = 0 else pSpeed(E, e) end
        if e.child then e.dir = dirTo(e.x, e.y, e.child.x, e.child.y) end
        pTimer(E, e, 0)
        pAnimSet(E, e)
      else
        e.subtimer = e.subtimer - 1
        if e.subtimer <= 0 then T.a14(E, e, 1, 8) end
      end
      local k = band(e.u83, 0x3F)
      if k == 3 then
        if band(e.u83, 0x80) == 0 then
          e.u80, e.timer, e.dir, e.speed, e.u84 = 3, 12, 0x10, 0, 0
          pAnimSet(E, e)
          holdLink(E, e)
        end
      elseif (k == 1 or k == 2) and e.child and math.abs(e.x - e.child.x) <= 6 and math.abs(e.y - e.child.y) <= 6 then
        e.u80, e.timer = 3, 12
        e.u83 = band(e.u83, bit.bnot(0x80))
        local c = e.child
        e.x, e.y = c.x, c.y
        e.zh, e.u78 = e.zh - 0xE, e.u78 - 0xE
        syncZ(e)
        if k == 1 then
          local b = T.dirtBall(E, e, 1)
          b.child = c
          e.child = b
        else
          c.deleted = true -- (the pot's tile is restored by its own object code in the port)
          e.child = T.dirtBall(E, e, 2)
        end
      end
    else pChase(E, e); e.u83 = bor(e.u83, 0x40) end
  elseif u == 3 then
    e.timer = e.timer - 1
    if e.timer <= 0 then e.u80, e.subtimer, e.speed, e.u82 = 4, 0, 0, e.u82 + 1 end
  elseif u == 4 then
    e.zh = e.zh - 2; syncZ(e)
    if -60 > e.zh then e.u80 = 5 end
  elseif u == 5 then
    if e.zh < -0x30 then e.zh = e.zh + 1; syncZ(e)
    else
      if e.u82 ~= 0 then e.u82, e.u78 = 0, -0x30 end
      if e.u83 == 3 then
        if e.u84 > 0x2F then T.releaseLink(E, e) end
      elseif e.u83 == 1 or e.u83 == 2 then
        e.u80, e.timer, e.subtimer, e.speed = 6, 192, 8, 0x80
        pAnimSet(E, e)
      else pToIdle(E, e) end
    end
  elseif u == 6 then
    e.timer = e.timer - 1
    if e.timer <= 0 then
      if band(e.u83, 0x80) ~= 0 then
        e.u83, e.u80, e.speed, e.timer, e.subtimer = 0xC0, 0, 0x40, 64, 8
        T.a14(E, e, 0, 8)
      else e.timer, e.subtimer = 64, 8 end
    else
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 then T.a14(E, e, 2, 8) end
    end
  elseif u == 7 then
    if (p.z or 0) == 0 then e.u80, e.speed = 0, 0x80; T.findTarget(E, e) end
  end
  if e.u83 == 3 and e.action == 6 then carryLink(E, e) end
end

-- ===========================================================================
-- SCISSORS BEETLE + MANDIBLES
-- ===========================================================================
local function bAnim(E, e, shift) -- sub_08038C84 / sub_080AA3E0
  local idx = bor(e.animationState, lshift(e.u82 or 0, 3))
  if shift then idx = rshift(idx, 1) end
  if e.mand then
    e.animIndex = idx
    if e.sprite then e.anim:set(E.A:sprite(e.sprite), idx, true) end
  else
    e.animIndex = nil
    E:setAnim(e, idx)
  end
end
local function heading(E, e) -- sub_08038BA8
  local f = E.field
  local m = e.child
  e.subtimer = T.BEETLE_T1[band(R(f), 7)]
  e.u82 = 1
  if m then m.u82 = 0 end
  if e.u7a == 0 then
    e.u7a = 1
    e.dir = e.animationState * 4
    bAnim(E, e, true)
    return
  end
  local r3
  if m and band(m.animationState, 1) ~= 0 then
    r3 = (m.animationState == band(e.animationState + 1, 7)) and 2 or 6
    r3 = band(r3 + e.animationState, 6)
  else r3 = m and m.animationState or e.animationState end
  if r3 ~= e.animationState then
    e.animationState = r3
    e.dir = r3 * 4
    bAnim(E, e, true)
  end
end
local function jawSwing(E, m, tbl, ttbl) -- sub_08038C2C / sub_080AA270
  local f = E.field
  local par = m.parent
  m.subtimer = ttbl[band(R(f), 7)]
  local ps = par and par.animationState or 0
  if m.animationState == 0xFF then
    m.animationState = ps
  else
    ps = band(tbl[band(R(f), 7)] + ps, 7)
    if ps == m.animationState then return end
    m.animationState = ps
  end
  local hb = T.MAND_HB[m.animationState]
  m.hitbox = { x = hb[1], y = hb[2], w = hb[3], h = hb[4] }
  bAnim(E, m, false)
end
T.jawSwing = jawSwing

-- GetSpriteSubEntryOffsetDataPointer(the body's sprite, frame): the jaws' point
local function attach(E, body)
  local NP = require("src.zelda.tmc.NpcParts")
  local Rd = E.A and E.A.manifest and NP.readers(E.A)
  local fr = body.anim and body.anim.frame
  if not Rd or not fr or fr == 0xFF or not body.sprite then return 0, 0 end
  local X = Rd.x
  local EFO = 0x089FB770
  local v = X.u16(EFO + 0x10 + 2 * body.sprite) + EFO
  local idx = X.u8(v + band(fr, 0xFF)) * 4
  local pa = EFO + X.u32(EFO) + idx
  local ox, oy = X.u8(pa), X.u8(pa + 1)
  if ox >= 128 then ox = ox - 256 end
  if oy >= 128 then oy = oy - 256 end
  if band(body.animationState or 0, 4) ~= 0 then ox = -ox end
  return ox, oy
end

function T.makeJaws(E, e)
  local f = E.field
  local defs = f.assets.manifest.projectileDefs
  local d = defs and defs[MANDIBLES]
  if d and d.multi then d = d.forms[0] end
  d = d or {}
  local m = { kind = 4, id = MANDIBLES, mand = true, boss = true, impl = T.JawImpl(E), x = e.x, y = e.y, z = 0, parent = e,
              action = 1, u80 = 0, u82 = 0, animationState = 0xFF, sprite = d.sprite, gfx = Assets.gfxSource("enemy", d.gfx or 0),
              anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0, layer = e.layer or 1, hitType = d.damageType or 3,
              hitbox = { x = 0, y = -4, w = 6, h = 8 }, speed = d.speed or 0x180, subtimer = 0, timer = 0, iframes = 0, health = 1,
              spritePriority = 4 }
  m.palette = E.A:objPalette(d.palette or 0x120, f.room.atlas and f.room.atlas.palettes)
  jawSwing(E, m, T.MAND_SW, T.MAND_T)
  m.extUpdate = function(_, me) T.jaws(E, me) end
  f.entities[#f.entities + 1] = m
  if f._dungeon then f._dungeon:track(m) end
  return m
end

local function jawAttack(E, m) -- sub_080AA320
  local par = m.parent
  m.action, m.u82, m.subtimer = 2, 1, 0
  par.action, par.subtimer, par.u80, par.speed = 2, 48, 0x50, 0
  local p = E.field.player
  par.dir = dirTo(par.x, par.y, p.x, p.y)
  local d8 = band(par.dir + 2, 0x1C)
  m.animationState = rshift(d8, 2)
  par.animationState = rshift(band(d8 + 4, 0x18), 2)
  bAnim(E, par, true)
  bAnim(E, m, false)
end

function T.jaws(E, m)
  local f = E.field
  if m.deleted then return end
  local p = f.player
  if m.action < 3 then -- sub_080AA1D8
    local par = m.parent
    if not par or par.deleted or par.dying then m.deleted = true return end
    if band(par.anim.frame or 0, 0x20) == 0 then
      local ox, oy = attach(E, par)
      m.x, m.y = par.x + ox, par.y + oy
    end
  end
  if m.iframes > 0 then m.iframes = m.iframes - 1 end
  if m.action == 1 then
    if m.u80 ~= 0 then m.u80 = m.u80 - 1
    else
      m.subtimer = m.subtimer - 1
      if m.subtimer <= 0 then jawSwing(E, m, T.MAND_SW, T.MAND_T)
      else -- sub_080AA2E0: Link in front within $40
        local t = target3(f)
        if t and band(dirTo(m.x, m.y, t.x, t.y) + 4 + 2, 0x1C) == band(m.animationState * 4 + 4 + 2, 0x1C) and within(m, t, 0x40) then
          jawAttack(E, m)
        end
      end
    end
    m.anim:update(1)
    T.touch(E, m)
  elseif m.action == 2 then
    m.anim:update(1)
    if band(m.anim.flags or 0, 0x40) ~= 0 and m.sfxKey ~= m.anim.key then m.sfxKey = m.anim.key; f:sound(SFX.S15D) end
    T.touch(E, m)
  elseif m.action == 3 then
    local body = m.child
    if not body or body.deleted then m.deleted = true return end
    local ox, oy = attach(E, body)
    m.x, m.y = body.x + ox, body.y + oy
    if m.subtimer ~= 0 then m.subtimer = m.subtimer - 1
    else
      m.anim:update(1)
      if m.anim.done then
        m.action, m.u82, m.subtimer = 4, 3, 64
        m.dir = body.animationState * 4
        m.animationState = body.animationState
        m.hitbox = { x = 0, y = 0, w = 1, h = 1 } -- gHitbox_0
        bAnim(E, m, false)
      end
    end
  elseif m.action == 4 then
    local body = m.child
    if body then
      if body.deleted then m.child = nil end
      if m.subtimer ~= 0 then m.subtimer = m.subtimer - 1
      elseif m.child then -- sub_080AA374
        local st = band(body.animationState, 6) -- gUnk_08129D14[animationState] (x, y)
        local px, py = body.x + T.MAND_PT[st], body.y + T.MAND_PT[st + 1]
        if (m.x - px) ^ 2 + (m.y - py) ^ 2 <= 64 then
          if body.health <= 0 then m.deleted = true return end
          f:sound(SFX.F2)
          m.action, m.animationState, m.u82, m.timer, m.u80 = 1, 0xFF, 0, 0, 0x20
          m.parent, m.child = body, nil
          jawSwing(E, m, T.MAND_SW, T.MAND_T)
          body.action, body.dir, body.speed, body.u82, body.timer, body.subtimer, body.u80 = 1, body.animationState * 4, 0, 1, 0, 120, 0x20
          bAnim(E, body, true)
          return
        else turn1(m, dirTo(m.x, m.y, px, py)) end
      end
    elseif m.x < f.camX - 16 or m.x > f.camX + 256 or m.y < f.camY - 16 or m.y > f.camY + 176 then m.deleted = true return end
    local a = (m.dir % 32) * math.pi / 16
    m.x, m.y = m.x + math.sin(a) * m.speed / 256, m.y - math.cos(a) * m.speed / 256 -- LinearMoveUpdate
    m.anim:update(1)
    if T.touch(E, m) then m.subtimer = 0 end -- OnCollision case 4 (ModHealth(-2) by the matrix here)
  end
end

-- the jaws' sword hit (OnCollision default: the body copies the knockback; action 1 -> snap)
function T.JawImpl(E)
  local J = {}
  function J:update() end
  function J:swordHit(m, box)
    if m.deleted or m.action >= 3 or m.iframes > 0 then return false end
    local hb = m.hitbox
    if math.abs((m.x + hb.x) - box.x) < hb.w + box.w and math.abs((m.y + hb.y) - box.y) < hb.h + box.h then
      local p = E.field.player
      local s = E:settings(m.hitType or 3, 4) or { tgtIfr = 12, tgtKbSpd = 24, tgtKbDur = 12 }
      local par = m.parent
      m.iframes = (s.tgtIfr and s.tgtIfr > 0) and s.tgtIfr or 12
      if par then par.iframes = m.iframes; E:knock(par, p.x, p.y, s.tgtKbSpd or 24, s.tgtKbDur or 12) end
      E.field:sound(0x118)
      if m.action == 1 then jawAttack(E, m) end
      return true
    end
    return false
  end
  function J:draw(m, camX, camY)
    local fr = m.anim.frame
    if not m.sprite or not fr or fr == 0xFF then return end
    local img, ox, oy = E.A:spriteFrame(m.sprite, fr, m.palette, "jaws", m.gfx)
    if not img then return end
    local x, y = math.floor(m.x - camX), math.floor(m.y - camY)
    if m.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
  end
  return J
end

function T.beetleCollision(E, e, fl)
  local m = e.child
  if not m or e.action == 4 then return end
  m.iframes = e.iframes
  if e.action == 1 then
    local p = E.field.player
    local kd = dirTo(p.x, p.y, e.x, e.y)
    m.dir = band(kd + 0x12, 0x1C)
    m.animationState = rshift(m.dir, 2)
    e.dir = band(kd + 0x14, 0x18)
    e.animationState = rshift(e.dir, 2)
    bAnim(E, e, true)
    bAnim(E, m, false)
  end
end

function T.beetle(E, e)
  local f = E.field
  local m = e.child
  if e.action == 0 then -- ScissorsBeetle_Init
    e.action, e.hidden = 1, false
    e.collideOn = true
    e.animationState = band(R(f), 6)
    e.u80, e.u7a = 0, 0
    e.speed = e.speed ~= 0 and e.speed or 0x80
    e.onCollision = T.beetleCollision
    e.child = T.makeJaws(E, e)
    heading(E, e)
    return
  end
  if e.action == 1 then -- sub_080389E8
    if e.u80 ~= 0 then
      e.u80 = e.u80 - 1
      if e.u80 == 0 then e.speed = 0x80 end
    else
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 then heading(E, e); if m then jawSwing(E, m, T.BEETLE_SW, T.BEETLE_T2) end
      elseif (e.timer or 0) > 0 then e.timer = e.timer - 1
      elseif e.colX or e.colY then
        e.timer = 12
        if m and band(m.animationState, 1) == 0 then
          m.animationState = band(m.animationState + (band(R(f), 0x20) ~= 0 and 1 or 7), 7)
        end
        heading(E, e)
        if m then jawSwing(E, m, T.BEETLE_SW, T.BEETLE_T2) end
      end
    end
  elseif e.action == 2 then -- sub_08038A70
    e.u80 = e.u80 - 1
    if e.u80 == 0 and m then
      e.action, e.u82, e.speed, e.subtimer = 3, 4, 0x80, 32
      m.action, m.u82, m.animationState = 3, 2, 0xFF
      bAnim(E, e, true)
      jawSwing(E, m, T.BEETLE_SW, T.BEETLE_T2)
      m.subtimer, m.parent, m.child = 32, nil, e
    else
      e.subtimer = e.subtimer - 1
      if e.subtimer <= 0 and m then
        e.subtimer = 16
        local p = f.player
        e.dir = dirTo(e.x, e.y, p.x, p.y)
        local d = band(e.dir + 4, 0x1C)
        m.animationState = rshift(d, 2)
        e.animationState = rshift(band(d, 0x18), 2)
        bAnim(E, e, true); bAnim(E, m, false)
      end
    end
  elseif e.action == 3 then -- sub_08038B08
    if e.subtimer ~= 0 then e.subtimer = e.subtimer - 1 return end
    e.anim:update(1)
    if e.anim.done then
      e.action, e.u82, e.timer, e.subtimer = 4, 3, 50, 2
      e.dir = band(e.animationState * 4 + 0x10, 0x1F)
      e.speed = 0x80
      bAnim(E, e, true)
      f:sound(SFX.S15B)
    end
    return
  elseif e.action == 4 then -- sub_08038B64
    e.colX, e.colY = DW().move0(E, e, e.dir, e.speed)
    e.anim:update(1)
    e.subtimer = e.subtimer - 1
    if e.subtimer <= 0 then e.subtimer = 2; e.dir = band(e.dir + 0x1F, 0x1F) end
    return
  end
  -- sub_08038B90
  e.anim:update(1)
  e.colX, e.colY = DW().move0(E, e, e.dir, e.speed or 0x80)
  local HBm = require("src.zelda.tmc.Hitboxes")
  if HBm.data(f) then HBm.pushOut(f, e, e.hitbox) end
end

-- ===========================================================================
-- FLYING POT
-- ===========================================================================
local function potTile(f, e)
  local r = f.room
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  return tx, ty, ty * r.tw + tx
end
local function potGone(E, e) -- sub_08037408
  E.field:addFx(e.x, e.y, SPECIAL_FX, FX_POT_SHATTER)
  e.deleted = true
end
local function potLifted(E, e) -- sub_08037418
  local f = E.field
  local tx, ty, i = potTile(f, e)
  if f.room.maps.bottom[i] == 0x4067 then f.room:setTile(1, tx, ty, e.tileIndex); e.deleted = true return true end
  return false
end
function T.potCollision(E, e, fl)
  local f = E.field
  if fl == 0x80 + 0x1D then -- the cane's bolt flips it
    e.action, e.noTouch, e.zv = 6, true, 2.625
    local tx, ty = potTile(f, e)
    f.room:setTile(1, tx, ty, e.tileIndex)
  elseif (e.z or 0) ~= 0 then potGone(E, e) end
end
function T.flyingPot(E, e)
  local f = E.field
  local p = f.player
  local a = e.action
  if a == 0 then
    e.action, e.y = 1, e.y + 3
    local tx, ty, i = potTile(f, e)
    e.tileIndex = f.room.maps.bottom[i]
    f.room:setTile(1, tx, ty, 0x4000) -- SPECIAL_TILE_0
    e.onCollision = T.potCollision
    e.noHit, e.noTouch = true, true
    setAnim(E, e, 5)
    return
  end
  if a <= 2 and potLifted(E, e) then return end
  if a == 1 then
    local tx, ty, i = potTile(f, e)
    if f.room.maps.bottom[i] ~= 0x4000 then f.room:setTile(1, tx, ty, e.tileIndex); potGone(E, e) return end
    if p.state ~= "dead" and within(e, p, 0x40) then e.action, e.timer = 2, 30 end
  elseif a == 2 then
    e.spriteOX = (e.spriteOX or 0) + POT_SHAKE[band(e.timer, 3)]
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.spriteOX, e.hitType = 3, 0, 0xA0
      e.noHit, e.noTouch = nil, nil
      e.collideOn = true
      local tx, ty = potTile(f, e)
      f.room:setTile(1, tx, ty, e.tileIndex)
    end
  elseif a == 3 then
    e.z = (e.z or 0) + 1
    if e.z >= 6 then e.action, e.timer = 4, 10; e.dir = dirTo(e.x, e.y, p.x, p.y) end
  elseif a == 4 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.action = 5 end
  elseif a == 5 then
    local hx, hy = DW().move0(E, e, e.dir, 0x280) -- ProcessMovement2 (the definition's speed $280)
    if hx or hy then potGone(E, e) return end
    -- touching Link breaks it (OnCollision with z != 0); the matrix hurts him
    if T.touch(E, e) then potGone(E, e) end
  elseif a == 6 then
    if e.zv < 0 then e.flipY = true end
    e.z = e.z + e.zv; e.zv = e.zv - 32 / 256
    if e.z <= 0 then e.z = 0; potGone(E, e) end
  end
end

-- ===========================================================================
-- the Big Blue ChuChu (CHUCHU_BOSS type 4) on BossChuchu.lua
-- ===========================================================================
function T.blueChuchu(E, dat, def)
  local f = E.field
  local C = require("src.zelda.tmc.BossChuchu")
  local impl = C.new(f, E)
  local e = impl:spawn(dat, E:def(dat.id, 4) or def)
  if not e then return e end
  e.type2, e.form = 4, 4 -- super->type2 = super->type (4)
  for _, pp in ipairs({ e, e.low, e.mid, e.head }) do
    local t = (pp == e) and 4 or (4 + pp.type)
    local d = E:def(dat.id, t)
    if d then
      pp.sprite = d.sprite or pp.sprite
      pp.gfx = Assets.gfxSource("enemy", d.gfx or 0) or pp.gfx
      pp.palette = E.A:objPalette(d.palette or 0x2C, f.room.atlas and f.room.atlas.palettes)
    end
  end
  impl.splash = function(self, ee) -- sub_08027D20: LoadObjPalette $2C when type2 != 0
    local pt = C.splash(self, ee)
    pt.palette = self.A:objPalette(0x2C, self.field.room.atlas and self.field.room.atlas.palettes)
    return pt
  end
  -- sub_080262A8 (type2 != 0): no walk-in, the drops at once
  e.minS, e.maxS, e.rate, e.btimer = 0x90, 0xB0, 8, 1
  impl:swingSet(e, 6, 1)
  e.c7c, e.c7d, e.sub = 0, 0x1E, 3
  f.player.animationState = 0
  f.cameraTarget = e
  f.scrollSpeed = 1
  if f.room.setTile then f.room:setTile(1, 8, 11, 0x4022) end -- SPECIAL_TILE_34 at TILE_POS(8, 11)
  return e
end

return T
