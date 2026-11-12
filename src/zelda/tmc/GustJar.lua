-- Round 13: the Gust Jar, ported from the decomp (replaces the round-2 cone).
--
-- CARTRIDGE BEHAVIOUR (src/item/itemGustJar.c, src/playerItem/
-- playerItemGust.c, playerItemGustBig.c, src/collision.c sub_08017B58,
-- src/physics.c sub_0806F3E4 / sub_0806F4E8 / sub_0806F520):
--   * Using it (sub_08076DF4): ANIM_GUSTJAR_PULLOUT, charge SMALL, state
--     PL_JAR_SUCK; when the pull-out animation ends the first gust
--     (PLAYER_ITEM_GUST type 0) is made and Link plays ANIM_GUSTJAR_SUCK
--     (ANIM_GUSTJAR_WALK while moving, at kWalkSpeedGustJar).
--   * Held (sub_08076EC8): a frame counter raises the charge to MID after
--     $77 frames and BIG after $EF.
--   * The suction is a chain of four PLAYER_ITEM_GUST entities: type 0 sits
--     at Link + gUnk_08126EE4[facing] (the jar's mouth); each type n
--     (1..3) runs out from its parent along the facing until it is
--     gUnk_0812AAE8[n] (12, 16, 16) px away, at (gap * $100) capped at
--     $200 a frame, stopping at walls (ProcessMovement1), and when it gets
--     there it makes type n + 1 (sub_080ACECC).  Sideways it keeps its
--     parent's x (vertical) or parent's y - 3 (horizontal).  Their boxes
--     are 4x4, 9x9, 9x9, 14x14 (half sizes, sHitboxes), hurtType $13.
--   * An entity a gust box overlaps gets contactFlags $93.  Through the
--     collision matrix (gust hurtType $13 against the target's hitType)
--     handler 4 (sub_08017B58) is the grab: the first contact sets
--     gustJarState bit 2 and subAction 0; while it is held the tolerance
--     drops by the charge each contact frame and at 0 the target is
--     pulled (subAction 2).  An enemy's OnGrabbed then runs: subAction 0
--     sets the tolerance (60 for most), 1 wiggles (sub_0806F4E8), 2 is
--     sub_0806F3E4: knockbackSpeed += 64 / 128 / 192 by charge (max
--     $500), straight at the mouth; within 4x4 of it, gustJarFlags 2
--     (catchable) attaches it (PL_JAR_ENT_ATTACHED, SFX_ED, a
--     PLAYER_ITEM_GUST_BIG holding it), gustJarFlags 1 is swallowed
--     (SFX_EF).  Losing contact before that (sub_0806F520) lets it go.
--   * Letting go (sub_08076F64): ANIM_GUSTJAR_BLOW; on its keyframe with
--     flag bit 0 (PL_JAR_BLAST_UPDATE) a PLAYER_ITEM_GUST_BIG goes out:
--     holding an enemy, that enemy flies ($400 a frame, 86 frames,
--     hurtType $1C, damage 6) until it hits something; with no enemy and
--     a charge, a puff of air of size charge - 1 (timer $10 / $20 / $40,
--     damage 2 / 3 / 6, boxes 6 / 8 / 12, hurtType $1B) that blows the
--     tiles it passes (DoTileInteractionHere filter 5).  Link is pushed
--     back at $80 the whole time (UpdatePlayerMovement), then
--     ANIM_GUSTJAR_END.
-- Gust contact is also offered to room objects (GustJar.touching): webs,
-- the barrel's web, lily pads, the Big Green ChuChu.
-- SIMPLIFIED: the GUST_JAR_PARTICLE sprites and the bush objects the gust
-- tears out of grass are not drawn (the tiles still change).
local bit = require("bit")
local band = bit.band

local GJ = {}

local MOUTH = { [0] = { 0, -32 }, [2] = { 22, -6 }, [4] = { 0, 12 }, [6] = { -22, -6 } } -- gUnk_08126EE4
local SEG_DIST = { [0] = 0, 12, 16, 16 }                                               -- gUnk_0812AAE8
local SEG_HALF = { [0] = 4, 9, 9, 14 }                                                 -- sHitboxes
local GUST_HURT, GRAB_HANDLER = 0x13, 4
local SFX_14B, SFX_ED, SFX_EF, SFX_WIND1 = 0x14B, 0xED, 0xEF, 0xE7
local BIG_TIMER, BIG_DMG, BIG_HALF = { [0] = 0x10, 0x20, 0x40 }, { [0] = 2, 3, 6 }, { [0] = 6, 8, 12 }
local ANIM_PULLOUT, ANIM_SUCK, ANIM_END, ANIM_BLOW, ANIM_WALK = 0x500, 0x504, 0x510, 0x514, 0x518
GJ.ANIM = { pullout = ANIM_PULLOUT, suck = ANIM_SUCK, walk = ANIM_WALK, blow = ANIM_BLOW, finish = ANIM_END }
-- gustJarTolerance from the enemies' init code (octorok.c, pesto.c ...)
local TOL = { [0x00] = 60, [0x03] = 60, [0x04] = 60, [0x08] = 60, [0x11] = 60, [0x2B] = 60 }
-- gustJarFlags 2: caught and held (pesto.c, octorok.c, keese.c, peahat.c,
-- rollobite.c, rope.c ...)
local CATCH = { [0x00] = true, [0x03] = true, [0x04] = true, [0x08] = true, [0x11] = true, [0x2B] = true }
local PUFFSTOOL = 0x12

-- the jar's mouth (type 0's place)
function GJ.mouth(p)
  local m = MOUTH[band(p.animationState or 4, 6)]
  return p.x + m[1], p.y + m[2]
end

local function dirv(s)
  if s == 0 then return 0, -1 elseif s == 2 then return 1, 0 elseif s == 4 then return 0, 1 end
  return -1, 0
end

-- ---------------------------------------------------------------------------
-- itemGustJar.c state functions (Link's side)
-- ---------------------------------------------------------------------------
function GJ.start(f, p)
  p.jar = { state = "pullout", count = 0, charge = 1, segs = {}, contacts = {} }
  p.jarKick = nil
  f:sound(SFX_14B)
end

local function charge(j)
  -- sub_08076EC8: timer > $EF -> BIG, ++timer > $77 -> MID, else SMALL
  if j.count > 0xEF then j.charge = 3
  else
    j.count = j.count + 1
    j.charge = j.count > 0x77 and 2 or 1
  end
end

-- PLAYER_ITEM_GUST: sub_080ACDB0 / sub_080ACECC
local function chain(f, p, j)
  local s = band(p.animationState or 4, 6)
  local ux, uy = dirv(s)
  local m = MOUTH[s]
  local segs = j.segs
  segs[0] = segs[0] or { type = 0 }
  segs[0].x, segs[0].y = p.x + m[1], p.y + m[2]
  for t = 1, 3 do
    local par, sg = segs[t - 1], segs[t]
    if not par then break end
    if not sg then
      if par.reached or t == 1 then
        sg = { type = t, x = par.x, y = par.y }
        segs[t] = sg
      else break end
    end
    -- sideways: locked to the parent
    if ux ~= 0 then sg.y = par.y - 3 else sg.x = par.x end
    local gap = (sg.x - par.x) * ux + (sg.y - par.y) * uy
    local want = SEG_DIST[t]
    if gap >= want then
      sg.x, sg.y = par.x + ux * want, ux ~= 0 and sg.y or par.y + uy * want
      sg.reached = true
    else
      local sp = math.min(want - gap, 2)
      local nx, ny = sg.x + ux * sp, sg.y + uy * sp
      if not GJ.wall(f, nx, ny, p.layer or 1) then sg.x, sg.y = nx, ny end
      sg.reached = ((sg.x - par.x) * ux + (sg.y - par.y) * uy) >= want
    end
  end
end

-- ProcessMovement1's tile test for the gust: water does not stop it
-- (its collision is for walkers), walls do
function GJ.wall(f, x, y, layer)
  -- round 22: the cartridge's test is IsTileCollision(collisionType 1)
  -- (CalculateEntityTileCollisions(this, dir, 1)): collision 0-$F never
  -- stops a gust (collisionLookup[2] / [3] = FilledNone), nor pits ($20)
  -- or water; only $23, $27, $40-$4F, $60-$6F, $FF and above $6F do
  if f.room.coll and f.room.tw then
    local r = f.room
    local tx, ty = math.floor(x / 16), math.floor(y / 16)
    if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return true end
    local v = r.coll[(layer == 2) and 2 or 1][ty * r.tw + tx] or 0xFF
    return GJ.type1Solid(v)
  end
  return GJ.wallR21(f, x, y, layer)
end
function GJ.type1Solid(v)
  if v < 0x10 then return false end
  if v == 0x23 or v == 0x27 or v == 0xFF or v > 0x6F then return true end
  return (v >= 0x40 and v <= 0x4F) or (v >= 0x60 and v <= 0x6F)
end
function GJ.wallR21(f, x, y, layer)
  if not f.room:isSolid(x, y, layer) then return false end
  local d = f._dungeon
  local a = d and d:actAt(x, y, layer)
  if a == 0x10 or a == 0x17 or a == 0x11 then return false end
  if layer == 2 and d then
    local a1 = d:actAt(x, y, 1)
    if (a1 == 0x10 or a1 == 0x17) and not f.room:isSolid(x, y, 1) then return false end
  end
  return true
end

-- does any gust box overlap the box (cx, cy, hw, hh) this frame?
function GJ.touching(f, cx, cy, hw, hh)
  local p = f.player
  local j = p and p.jar
  if not (j and j.state == "suck" and j.live) then return false end
  for t = 0, 3 do
    local sg = j.segs[t]
    if sg and math.abs(sg.x - cx) < SEG_HALF[t] + (hw or 4) and math.abs(sg.y - cy) < SEG_HALF[t] + (hh or 4) then return true end
  end
  return false
end

local function hb(e)
  local h = e.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  return e.x + (h.x or 0), e.y + (h.y or 0), h.w or 4, h.h or 4
end

local function grabbable(E, e)
  if not e.enemy or e.dying or e.deleted or e.hidden or e.boss or (e.z or 0) > 8 then return false end
  local HB = require("src.zelda.tmc.Hitboxes")
  if not E.mtx then return false end
  return HB.handler(E.mtx, e.hitType or 0, GUST_HURT) == GRAB_HANDLER
end

-- sub_08017B58 + the enemy's OnGrabbed
local function contactEnemies(f, p, j)
  local E = f:enemies()
  for _, e in ipairs(f.entities) do
    if e.enemy and not e.dying and not e.deleted then
      local x, y, w, h = hb(e)
      local hit = GJ.touching(f, x, y, w, h)
      if hit and e.id == PUFFSTOOL and e.puffInit then
        -- round 12's Puffstool_OnGrabbed (EnemyDeepwood.lua) drains it
        e.gusted = true; e.gustDir = (p.animationState or 0) * 4
      elseif hit and grabbable(E, e) then
        if not e.jarSub then
          e.jarSub, e.jarTol, e.jarKb = 0, TOL[e.id] or 60, 0
        end
        if e.jarSub == 1 and e.jarTol > 0 then
          e.jarTol = e.jarTol - j.charge
          if e.jarTol <= 0 then e.jarTol = 0; e.jarSub = 2; e.jarKb = 0 end
        end
        e.jarSeen = f.frame
      end
    end
  end
end

-- the grabbed enemy's frame (called from Enemies:update instead of its AI)
function GJ.grabbedUpdate(E, e)
  local f = E.field
  local p = f.player
  local j = p.jar
  local held = j and j.held == e
  if not held and (not j or j.state ~= "suck" or (e.jarSeen or 0) < f.frame - 1) and (e.jarSub or 0) < 3 then
    -- sub_0806F520 false: let go (the AI resumes)
    e.jarSub, e.spriteOX = nil, nil
    if e.onJarLost then e.onJarLost(E, e) end -- round 21 (Rollobite_OnGrabbed: rolled up)
    return false
  end
  if e.jarSub == 0 then
    e.jarSub = 1
    if e.onGrabbed then e.onGrabbed(E, e) end -- round 20: the enemy's OnGrabbed subaction 0 (peahat.c)
  elseif e.jarSub == 1 then
    e.spriteOX = ({ [0] = 2, 0, -2, 0 })[band(e.jarTol, 3)] -- sub_0806F4E8
  elseif e.jarSub == 2 then
    e.spriteOX = nil
    -- round 23: an OnGrabbed subaction 2 that is not the pull (helmasaur.c sub_0802BCA8: the mask comes off)
    if e.onJarPull and e.onJarPull(E, e) then e.jarSub = nil return true end
    e.jarKb = math.min(0x500, e.jarKb + 64 * j.charge)
    local mx, my = GJ.mouth(p)
    local dx, dy = mx - e.x, my - e.y
    local d = math.sqrt(dx * dx + dy * dy)
    local sp = e.jarKb / 256
    if d <= sp then e.x, e.y = mx, my else e.x, e.y = e.x + dx / d * sp, e.y + dy / d * sp end
    if math.abs(e.x - mx) < 4 and math.abs(e.y - my) < 4 then
      if CATCH[e.id] then
        e.jarSub = 3
        e.hidden = true
        j.held = e
        j.state = "attached"
        f:sound(SFX_ED)
      else
        f:sound(SFX_EF)
        e.jarSub = 4
      end
    end
  elseif e.jarSub == 3 then
    local mx, my = GJ.mouth(p)
    e.x, e.y = mx, my
  end
  return true
end

-- ---------------------------------------------------------------------------
-- per frame while the button is held (Player state "gust")
-- ---------------------------------------------------------------------------
function GJ.frame(f, p)
  local j = p.jar
  if not j then GJ.start(f, p); j = p.jar end
  if j.state == "pullout" then
    j.pt = (j.pt or 0) + 1
    p:setAnim(ANIM_PULLOUT)
    if p.anim.done or j.pt >= 12 then j.state = "suck"; j.live = true end
    return
  end
  if j.state == "attached" then
    -- PL_JAR_ENT_ATTACHED: the jar holds the enemy, nothing more is drawn in
    j.live = false
    if f.frame % 16 == 0 then f:sound(0xEE) end -- SFX_EE
    return
  end
  charge(j)
  chain(f, p, j)
  contactEnemies(f, p, j)
  require("src.zelda.tmc.PotGust").contact(f, p, j) -- round 14: pots (pot.c Action3)
  -- DoTileInteractionOffset(0xE) on the gusts every other frame (the
  -- offsets cycle through sOffsets[type]); filter 5 is the port's jar row
  if f.frame % 2 == 0 then
    for t = 0, 3 do
      local sg = j.segs[t]
      if sg then f:objects():tileInteraction(5, sg.x, sg.y, p.layer) end
    end
  end
  -- PlayerItemGustJar_Action2: subtimer -= charge a frame, the wind
  -- sound for the charge each time it runs out (reset to 15)
  j.wind = (j.wind or 15) - j.charge
  if j.wind < 0 then f:sound(SFX_WIND1 + j.charge - 1); j.wind = 15 end
end

-- ---------------------------------------------------------------------------
-- letting go: sub_08076F64, PLAYER_ITEM_GUST_BIG
-- ---------------------------------------------------------------------------
local function blowUpdate(p, input)
  local f = p.field
  local j = p.jar
  if not j then p.state = "normal"; p.extUpdate = nil; return end
  j.bt = (j.bt or 0) + 1
  if j.phase == "blow" then
    p:setAnim(ANIM_BLOW)
    p.anim:update(1)
    -- push back at $80 against the facing (UpdatePlayerMovement)
    -- (not on a lily pad: PL_FLAGS2 skips the move; the pad takes the kick)
    local ux, uy = dirv(band(p.animationState, 6))
    if not (f._dungeon and f._dungeon:onLily(p)) then p:moveBy(-ux * 0.5, -uy * 0.5) end
    if not j.fired and (band(p.anim.flags or 0, 1) ~= 0 or j.bt >= 6) then
      j.fired = true
      GJ.fire(f, p, j)
    end
    if (p.anim.done or j.bt >= 24) and j.fired then j.phase = "end"; j.bt = 0; p:setAnim(ANIM_END, true) end
  else
    p.anim:update(1)
    if p.anim.done or j.bt >= 10 then
      p.jar = nil
      p.jarKick = nil
      p.state = "normal"; p.extUpdate = nil
      p:setAnim(p:animFor("idle"), true)
    end
  end
end

function GJ.release(f, p)
  local j = p.jar
  if not j then return end
  j.live = false
  -- lilypadLarge.c reads PL_JAR_3 and the charge on the frame of the
  -- release (Dungeon:updateLily)
  p.jarKick = (j.state ~= "pullout") and j.charge or nil
  j.phase, j.bt, j.fired = "blow", 0, false
  p.state = "ext"
  p.extUpdate = blowUpdate
  p:setAnim(ANIM_BLOW, true)
  -- grabbed but not held ones are let go
  for _, e in ipairs(f.entities) do
    -- (round 14: a pot already pulled breaks: PotGust.tick)
    if e.jarSub and e ~= j.held and not e.potGust then e.jarSub, e.spriteOX = nil, nil end
  end
end

-- the shot: with an enemy held, or a puff of air for the charge
function GJ.fire(f, p, j)
  local s = band(p.animationState, 6)
  local ux, uy = dirv(s)
  local shot = { x = p.x, y = p.y, ux = ux, uy = uy, layer = p.layer or 1 }
  if j.held then
    local e = j.held
    j.held = nil
    shot.child, shot.timer, shot.hurt, shot.half = e, 86, 0x1C, 6
    e.hidden = false
    if e.potGust then e.inShot = true else e.jarSub = 5 end
  elseif j.state == "pullout" then
    return
  else
    local t = j.charge - 1
    shot.timer, shot.dmg, shot.hurt, shot.half, shot.type = BIG_TIMER[t], BIG_DMG[t], 0x1B, BIG_HALF[t], t
  end
  f._gustShots = f._gustShots or {}
  table.insert(f._gustShots, shot)
end

local function endShot(f, sh)
  sh.done = true
  local e = sh.child
  if e and not e.deleted then
    -- round 14: a pot breaks where the shot ends (Pot_Action3 subAction 5)
    if e.potGust then require("src.zelda.tmc.PotGust").breakPot(f, e) return end
    if e.onShotEnd then e.onShotEnd(f, e) return end -- round 21 (EnemyBeetle: the beetle's rock, Rollobite)
    -- Action3: the child gets subAction 5: it is finished (health 0)
    e.jarSub = nil
    if not e.dying then f:enemies():kill(e) end
  end
end

-- Field:update: the shots in flight
function GJ.tick(f)
  require("src.zelda.tmc.PotGust").tick(f) -- round 14: pots in the gust
  local list = f._gustShots
  if not list then return end
  local E = f:enemies()
  for i = #list, 1, -1 do
    local sh = list[i]
    if not sh.done then
      if sh.timer <= 0 then endShot(f, sh) else
        sh.timer = sh.timer - 1
        local nx, ny = sh.x + sh.ux * 4, sh.y + sh.uy * 4
        if sh.child then sh.child.x, sh.child.y = nx, ny end
        if not sh.child then f:objects():tileInteraction(5, sh.x, sh.y, sh.layer) end
        -- the next tile solid: it stops (sub_080040D8)
        if f.room:isSolid(sh.x + sh.ux * 4, sh.y + sh.uy * 4, sh.layer) then endShot(f, sh)
        else
          sh.x, sh.y = nx, ny
          for _, o in ipairs(f.entities) do
            if o.chuchuBoss and o.impl then
              -- round 17: the boss takes the puff by its own rules (BossChuchu:blow);
              -- a puff goes on through (PlayerItemGustBig_Action2 only stops
              -- for contact while it carries a child)
              if not sh.child then o.impl:blow(o, sh) end
            elseif o.enemy and o ~= sh.child and not o.dying and not o.deleted and not o.hidden then
              local x, y, w, h = hb(o)
              if math.abs(x - sh.x) < w + sh.half and math.abs(y - sh.y) < h + sh.half then
                E:hit(o, sh.hurt, sh.x - sh.ux * 8, sh.y - sh.uy * 8)
                if sh.child then endShot(f, sh) break end
              end
            end
          end
        end
      end
    end
    if sh.done then table.remove(list, i) end
  end
end

-- the puff's sprite (spriteIndex $A6, palette 3, animation type + 10)
function GJ.draw(f, camX, camY)
  local list = f._gustShots
  if not list then return end
  local A = f.assets
  for _, sh in ipairs(list) do
    if not sh.child and not sh.done then
      local spr = A:sprite(0xA6)
      local keys = spr and spr.anims and spr.anims[(sh.type or 0) + 10]
      local fr = keys and keys[1] and keys[1][1]
      if fr then
        local img, ox, oy = A:spriteFrame(0xA6, fr, A:objPalette(3), "gustbig", { vram = 0 })
        if img then love.graphics.draw(img, math.floor(sh.x - camX) + ox, math.floor(sh.y - camY) + oy) end
      end
    end
  end
end

return GJ
