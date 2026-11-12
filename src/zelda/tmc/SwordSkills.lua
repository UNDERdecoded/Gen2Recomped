-- Round 26 (team A): the sword beyond the plain swing -- the charge, the
-- spin attack and the Tiger Scroll techniques.  Hooked through ItemsR26
-- (frame / draw); the plain swing stays Player's "sword" state + Items.lua.
--
-- PORTED (zeldaret/tmc):
--   src/item/itemSword.c
--     sub_080754B8  the swing: frameSpriteSettings & 1 makes the sword beam
--                   (GetSwordBeam), the swing's end with the button held and
--                   SKILL_SPIN_ATTACK ($48) starts the charge (sub_08075580)
--     sub_08075580  charge: ANIM_SWORD_CHARGE, timer $50 ($28 SKILL_FAST_SPIN)
--     sub_080755F0  charging: released early -> nothing (sub_080759B8);
--                   timer out -> charged (sword_state | $20)
--     sub_0807564C  charged: release -> sub_08075694, the spin
--     sub_08075694  ANIM_SPINATTACK (ANIM_ROLLATTACK_SPIN after a roll
--                   attack's contact), SFX_PLY_VO2, sword_state | $40
--     sub_08075738  spin: a new press sets timer 2; settings & 2 with
--                   SKILL_GREAT_SPIN and --timer != 0 (u8) -> ANIM_GREATSPIN,
--                   moving at $180 steered by the pad; each frame on the
--                   loop's last keyframe ++subtimer >= 10 (15 LONG_SPIN) or
--                   --timer == 0 ends it
--     sub_08075338 / sub_08075900  roll attack (SKILL_ROLL_ATTACK during a
--                   roll): ANIM_ROLLATTACK_SLIDE $14 frames at $300, then
--                   ANIM_ROLLATTACK_END; a contact turns it into the spin
--     sub_08075338 / sub_08075898  down thrust (SKILL_DOWN_THRUST): see
--                   SwordSkills.downThrust below
--   src/playerItem/playerItemSword.c
--     PlayerItemSword_Init / _Action1 / _Action2 hurt types: charge $D,
--                   spin 8/9/$A (Smith's / others / Four Sword), thrust
--                   $B/$C, down thrust $18/$19/$1A; sub_080A7A54 box table
--                   (manifest.sword.boxes), sub_080A78B8 mirroring (none
--                   while spinning), sub_080A7A84 tile probe (filter 1 with
--                   SKILL_ROCK_BREAKER $4B, else 0), sub_080A7B98 down
--                   thrust's 3x3 tile cut; the charged blade's flash
--                   (frameCount & 4 -> frame (animationState >> 1) + $B1)
--   src/playerItem/playerItemSwordBeam.c  the beam ($4C at full health,
--                   $4F at <= 1 heart: the same PLAYER_ITEM_SWORD_BEAM1):
--                   start offsets, speed $380, 60 frames, hitbox 6x6,
--                   hurtType $20 (gPlayerItemDefinitions), walls / contact /
--                   DoTileInteractionHere($C) end it (FX_SWORD_MAGIC),
--                   palettes 0,4,1,2 every 2 frames, sprite 166 anim 30/29
--   src/playerUtils.c  UpdatePlayerSkills (inventory == 1), GetSwordBeam
--   src/player.c  kWalkSpeedSwordCharge Q_8_8(0.875); sub_080739EC down
--                   thrust hop (zVelocity 2.5 at the apex, ANIM_DOWN_THRUST),
--                   sub_08073A94 the landing waits for ANIM_DONE
--
-- SIMPLIFICATIONS
--   * the swing is taken over from Player's "sword" state (same steps:
--     anim, Items:swordFrame, the 24-frame cap) so the beam and the charge
--     start on the cartridge's frame; Minish swings stay Player's
--   * blade always drawn over Link in the charge/spin (no behind slot);
--     SWORD_PARTICLE, the wall clink / FX_LIGHTNING of a charged blade,
--     ANIM_SWORD_CHARGE_BUMP, FX_DASH dust and Link's hurtType $1E during
--     the spin are not ported (p.swordHurtType is set to $1E for a reader)
--   * a charged blade's contact: any landed enemy hit ends the charge
--     (sub_080A78B8 default case); bosses take only the swing paths
--   * the beam does not hit bosses; the Four Sword's spiral beam
--     (playerItemSpiralBeam.c) and the clones (ChargeState, DeleteClones)
--     are not ported
--   * skills >= 1 / true in the inventory count (cartridge: == 1)

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local S = {}

S.ITEM = { SPIN = 0x48, ROLL = 0x49, DASH = 0x4A, ROCK = 0x4B, BEAM = 0x4C, GREAT = 0x4D,
           DOWN = 0x4E, PERIL = 0x4F, FOURSWORD = 0x06, FAST_SPIN = 0x73, FAST_SPLIT = 0x74, LONG_SPIN = 0x75 }
S.ANIM = { SPIN = 0x124, GREAT = 0x128, ROLL_SPIN = 0x12C, ROLL_SLIDE = 0x130, ROLL_END = 0x134,
           CHARGE = 0x168, CHARGE_WALK = 0x16C, CHARGE_BUMP = 0x170, DOWN_THRUST = 0x174 }
S.CHARGE_SPEED = 0xE0 / 256      -- kWalkSpeedSwordCharge
S.CHARGE_TIME, S.CHARGE_TIME_FAST = 0x50, 0x28
S.GREAT_SPEED = 0x180 / 256
S.GREAT_LOOPS, S.GREAT_LOOPS_LONG = 10, 15
S.ROLL_SPEED, S.ROLL_TIME = 0x300 / 256, 0x14
S.BEAM_SPEED, S.BEAM_LIFE, S.BEAM_HURT, S.BEAM_BOX = 0x380 / 256, 60, 0x20, 6
S.BEAM_ANIM = { [0] = 30, 29, 30, 29 }
S.BEAM_PAL = { 0, 4, 1, 2 }
S.DOWN_HOP = 2.5
S.HURT_CHARGE = 0x0D
S.SFX = { VO2 = 0x76, VO3 = 0x77, BEAM = 0x13F }
S.OBJ_SPECIAL_FX, S.FX_SWORD_MAGIC = 0x0F, 0x19
S.MOVE = { SPIN = 1, ROLL = 2, FULL_BEAM = 5, GREAT_SPIN = 6, DOWN_THRUST = 7, LOW_BEAM = 8 }

local function spinHurt(item) return item == 6 and 0x0A or item == 1 and 0x08 or 0x09 end
local function thrustHurt(item) return item == 6 and 0x0C or 0x0B end
local function downHurt(item) return item == 6 and 0x1A or item == 1 and 0x18 or 0x19 end
S.spinHurt, S.thrustHurt, S.downHurt = spinHurt, thrustHurt, downHurt

local function isSword(item) return item and item >= 1 and item <= 6 end

function S.skill(f, id)
  if require("src.zelda.tmc.Story27Town2").learned(f, id) then return true end -- round 27A: BladeBrothers_LearnSkill's gPlayerState.skills (Story27Town2.lua)
  local v = f:inventory(id)
  return v == true or (type(v) == "number" and v >= 1)
end

-- GetSwordBeam: $F full-health beam, $16 peril beam, 0 none
function S.beamKind(f)
  local st = f.save.stats
  if S.skill(f, S.ITEM.BEAM) and (st.health or 0) == (st.maxHealth or 0) then return 0xF end
  if S.skill(f, S.ITEM.PERIL) and (st.health or 0) <= 8 then return 0x16 end
  return 0
end

local function dirInput(input)
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  return dx, dy
end

local function facingVec(s)
  return (s == 2 and 1 or s == 6 and -1 or 0), (s == 4 and 1 or s == 0 and -1 or 0)
end

-- --------------------------------------------------------------- tiles / hits
-- DoTileInteraction(filter): filter 0 is Objects:cut; other filters (rock
-- breaker 1, beam $C) run the same entry effects
local function tileCut(f, filter, x, y, layer)
  local O = f:objects()
  if filter == 0 then return O:cut(x, y, layer) end
  local entry, cx, cy = O:tileInteraction(filter, x, y, layer)
  if not entry then return false end
  local OBJ = { GROUND_ITEM = 0x00, SPECIAL_FX = 0x0F }
  if entry.obj == OBJ.SPECIAL_FX then
    local Drops = require("src.zelda.tmc.Drops")
    local t = Drops.fxVariant(f, entry.objType)
    f:addFx(cx, cy, entry.obj, t)
    Drops.fxDrop(f, { x = cx, y = cy }, t, O)
  elseif entry.obj == OBJ.GROUND_ITEM then
    O:groundItem(entry.objType, 0, x, y, { drop = true })
  elseif entry.obj ~= 0xFF then
    f:addFx(cx, cy, entry.obj, entry.objType)
  end
  f:sound(0x14C)
  return true
end
S.tileCut = tileCut

local function overlap(e, box)
  local hb = e.hitbox or { x = 0, y = 0, w = 6, h = 6 }
  return math.abs((e.x + hb.x) - box.x) < hb.w + box.w and math.abs((e.y + hb.y) - box.y) < hb.h + box.h
end

-- Enemies:swordHits with the move's hurtType; returns landed hits
function S.hitBox(f, box, hurt, fromX, fromY, noBoss)
  local en = f:enemies()
  local hits = 0
  for _, e in ipairs(f.entities) do
    if e.boss and not e.dying then
      if not noBoss and (e.impl or en.boss):swordHit(e, box) then hits = hits + 1 end
    elseif e.enemy and not e.dying and not e.deleted and overlap(e, box) then
      e.spinAttack = (hurt >= 8 and hurt <= 0x0A) or nil -- round 26A wiring: a spin's contact ($88-$8A + chargeState), read by BossVaati2
      if en:hit(e, hurt, fromX, fromY) then hits = hits + 1 end
    end
  end
  f.swordBoxNow = { x = box.x, y = box.y, w = box.w, h = box.h, t = f.frame }
  return hits
end

-- the PLAYER_ITEM_SWORD for Link's current frame: tile probe + hitbox
-- (sub_080A7A84 / sub_080A78B8 / sub_080A7A54); noMirror while spinning
local function swordPass(p, hurt, noMirror)
  local f = p.field
  local sw = f.assets.manifest.sword
  if not sw then return 0 end
  local filter = S.skill(f, S.ITEM.ROCK) and 1 or 0
  local fl = band(p.anim.flags or 0, 0xF)
  if fl ~= 0 and sw.probes and sw.probes[fl - 1] then
    local pr = sw.probes[fl - 1]
    local px = (not noMirror and p.entFlip) and -pr[1] or pr[1]
    tileCut(f, filter, p.x + px, p.y + pr[2], p.layer)
  end
  local fi = p.anim.frame
  local b = fi and sw.boxes and sw.boxes[fi - 0x6A]
  if not (b and b[3] > 0) then return 0 end
  local flip = false
  if not noMirror then flip = (p.entFlip or false) ~= (band(p.animationState or 0, 2) ~= 0) end
  local bx = flip and -b[1] or b[1]
  return S.hitBox(f, { x = p.x + bx, y = p.y + b[2], w = b[3], h = b[4] }, hurt, p.x, p.y)
end
S.swordPass = swordPass

-- --------------------------------------------------------------- the beam
function S.beamAlive(f)
  for _, e in ipairs(f.entities) do if e.swordBeam and not e.deleted then return true end end
  return false
end

local BEAM_OFF = { [0] = { -3, -8 }, [2] = { 1, -4 }, [4] = { 2, 0 }, [6] = { -1, -4 } }

function S.spawnBeam(p)
  local f = p.field
  local s = band(p.animationState or 4, 6)
  local o = BEAM_OFF[s]
  local Anim = require("src.zelda.tmc.Anim")
  local b = { kind = 8, id = 0x0F, swordBeam = true, x = p.x + o[1], y = p.y + o[2], z = 0, layer = p.layer,
              dir = s, life = S.BEAM_LIFE, palT = 2, palI = 1, palette = 0, flipX = s == 2, flipY = s == 0,
              anim = Anim.new(), field82 = 0, interactType = 0, action = 1, hitbox = { x = 0, y = 0, w = 6, h = 6 } }
  local spr = f.assets.sprite and f.assets:sprite(166)
  if spr then b.anim:set(spr, S.BEAM_ANIM[s / 2], true) end
  b.drawGhost = function(me, field, camX, camY) S.drawBeam(field, me, camX, camY) end
  b.extUpdate = function(_, me) S.updateBeam(f, me) end
  local vx, vy = facingVec(s)
  b.x, b.y = b.x + vx * S.BEAM_SPEED, b.y + vy * S.BEAM_SPEED -- the Init's LinearMoveUpdate
  f.entities[#f.entities + 1] = b
  if f._dungeon then f._dungeon:track(b) end
  S.updateBeam(f, b)
  f:sound(S.SFX.BEAM)
  return b
end

local function beamEnd(f, b, fx)
  if fx then f:addFx(b.x, b.y, S.OBJ_SPECIAL_FX, S.FX_SWORD_MAGIC) end
  b.deleted = true
end

function S.updateBeam(f, b)
  if b.deleted then return end
  if b.life <= 0 then return beamEnd(f, b) end
  b.life = b.life - 1
  b.anim:update(1)
  local vx, vy = facingVec(b.dir)
  b.x, b.y = b.x + vx * S.BEAM_SPEED, b.y + vy * S.BEAM_SPEED
  -- palette cycle (PlayerItemSwordBeam_CyclePalettes)
  b.palT = b.palT - 1
  if b.palT == 0 then
    b.palT = 2
    b.palI = b.palI % #S.BEAM_PAL + 1
    b.palette = S.BEAM_PAL[b.palI]
  end
  if f.room and f.room.isSolid and f.room:isSolid(b.x, b.y, b.layer) then return beamEnd(f, b, true) end
  local en = f:enemies()
  for _, e in ipairs(f.entities) do
    if e.enemy and not e.boss and not e.dying and not e.deleted and overlap(e, { x = b.x, y = b.y, w = S.BEAM_BOX, h = S.BEAM_BOX }) then
      en:hit(e, S.BEAM_HURT, b.x, b.y)
      return beamEnd(f, b, true)
    end
  end
  if f:objects().tileInteraction and tileCut(f, 0xC, b.x, b.y, b.layer) then return beamEnd(f, b) end
end

function S.drawBeam(f, b, camX, camY)
  if b.deleted or not love or not love.graphics or not love.graphics.draw then return end
  local frame = b.anim.frame
  if not frame or frame == 0xFF then return end
  local A = f.assets
  local img, ox, oy = A:spriteFrame(166, frame, A:objPalette(b.palette), "swordbeam")
  if not img then return end
  local x, y = math.floor(b.x - camX), math.floor(b.y - camY)
  love.graphics.draw(img, x + (b.flipX and -ox or ox), y + (b.flipY and -oy or oy), 0, b.flipX and -1 or 1, b.flipY and -1 or 1)
end

-- --------------------------------------------------------------- states
local function extNoop() end

local function finish(p)
  p.ss = nil
  p.swordHurtType = nil
  p.lockFacing = nil
  if p.state == "ext" and p.extUpdate == extNoop then p.state = "normal"; p.extUpdate = nil end
end
S.finish = finish

local function enter(p, ss)
  p.ss = ss
  p.state = "ext"
  p.extUpdate = extNoop
end

local function startCharge(p, item)
  local f = p.field
  enter(p, { mode = "charge", item = item, button = p.swordButton or "b",
             timer = S.skill(f, S.ITEM.FAST_SPIN) and S.CHARGE_TIME_FAST or S.CHARGE_TIME, charged = false })
  p:setAnim(S.ANIM.CHARGE, true)
end

local function startSpin(p, ss, fromRoll)
  ss.mode, ss.timer, ss.great, ss.fromRoll, ss.charged = "spin", 1, false, fromRoll, false
  if fromRoll then
    p:setAnim(S.ANIM.ROLL_SPIN, true)
  else
    p.lastSwordMove = S.MOVE.SPIN
    p:setAnim(S.ANIM.SPIN, true)
  end
  p.swordHurtType = 0x1E
  p.field:sound(S.SFX.VO2)
end

-- the plain swing, as Player's "sword" state, plus sub_080754B8's beam / charge
local function swing(p, input)
  local f = p.field
  p.anim:update(1)
  if S.skill(f, S.ITEM.ROCK) then swordPass(p, 4, false) else f:items():swordFrame(p) end
  if band(p.anim.flip or 0, 1) ~= 0 then
    local k = S.beamKind(f)
    if k ~= 0 and not S.beamAlive(f) then
      S.spawnBeam(p)
      p.lastSwordMove = k == 0xF and S.MOVE.FULL_BEAM or S.MOVE.LOW_BEAM
    end
  end
  p.timer = p.timer - 1
  if p.anim.done or p.timer <= 0 then
    p.state = "normal"
    local btn = p.swordButton or "b"
    if S.skill(f, S.ITEM.SPIN) and input.down(btn) and not p.jumping and (p.z or 0) == 0 then
      startCharge(p, f:equipped(btn))
    end
  end
  return true
end

local function runCharge(p, ss, input)
  local f = p.field
  if not input.down(ss.button) then
    if ss.charged then startSpin(p, ss, false) else finish(p) end
    return true
  end
  if not ss.charged then
    ss.timer = ss.timer - 1
    if ss.timer <= 0 then ss.charged = true end -- sword_state | $20
  end
  local locked = (p.control == false) or (f.inputLocked and f:inputLocked())
  local dx, dy = 0, 0
  if not locked then dx, dy = dirInput(input) end
  p.lockFacing = true
  p:walk(dx, dy, S.CHARGE_SPEED, S.ANIM.CHARGE_WALK, S.ANIM.CHARGE)
  p.lockFacing = nil
  p.anim:update(1)
  if swordPass(p, S.HURT_CHARGE, false) > 0 then finish(p) end
  return true
end

local function runSpin(p, ss, input)
  local f = p.field
  p.anim:update(1)
  if input.pressed(ss.button or "b") then ss.timer = 2 end
  if ss.great then
    local dx, dy = dirInput(input)
    if dx ~= 0 or dy ~= 0 then
      local d = (dx ~= 0 and dy ~= 0) and 0.70710678 or 1
      ss.dx, ss.dy = dx * d, dy * d
    end
    p:moveBy(ss.dx * S.GREAT_SPEED, ss.dy * S.GREAT_SPEED)
    if band(p.anim.flags or 0, 0x80) ~= 0 then
      local loops = S.skill(f, S.ITEM.LONG_SPIN) and S.GREAT_LOOPS_LONG or S.GREAT_LOOPS
      ss.sub = ss.sub + 1
      ss.loops = (ss.loops or 0) + 1
      local stop = loops <= ss.sub
      if not stop then ss.timer = (ss.timer - 1) % 256; stop = ss.timer == 0 end
      if stop then finish(p) return true end
    end
  else
    local set = p.anim.flip or 0
    if band(set, 2) ~= 0 and not ss.fromRoll and S.skill(f, S.ITEM.GREAT) then
      ss.timer = (ss.timer - 1) % 256
      if ss.timer ~= 0 then
        ss.great, ss.timer, ss.sub, ss.loops = true, 1, 1, 0
        ss.dx, ss.dy = facingVec(band(p.animationState or 4, 6))
        p.lastSwordMove = S.MOVE.GREAT_SPIN
        p:setAnim(S.ANIM.GREAT, true)
      end
    end
    if not ss.great and band(p.anim.flags or 0, 0x80) ~= 0 then
      swordPass(p, spinHurt(ss.item), true)
      finish(p)
      return true
    end
  end
  swordPass(p, spinHurt(ss.item), true)
  return true
end

local function runRoll(p, ss, input)
  p.anim:update(1)
  if ss.hit then
    startSpin(p, ss, true)
    return true
  end
  if ss.timer ~= 0 then
    ss.timer = ss.timer - 1
    if ss.timer == 0 then p:setAnim(S.ANIM.ROLL_END, true) end
    local vx, vy = facingVec(band(p.animationState or 4, 6))
    p:moveBy(vx * S.ROLL_SPEED, vy * S.ROLL_SPEED)
  elseif band(p.anim.flags or 0, 0x80) ~= 0 then
    finish(p)
    return true
  end
  if swordPass(p, thrustHurt(ss.item), false) > 0 then ss.hit = true end -- sword_state | $80
  return true
end

local function runLand(p, ss)
  p.anim:update(1)
  if p.anim.done then finish(p) end
  return true
end

-- --------------------------------------------------------------- the hooks
function S.frame(p, input)
  local ss = p.ss
  if ss then
    if p.state ~= "ext" or p.extUpdate ~= extNoop then
      p.ss, p.swordHurtType = nil, nil -- interrupted (hurt, warp, cutscene)
    elseif ss.mode == "charge" then return runCharge(p, ss, input)
    elseif ss.mode == "spin" then return runSpin(p, ss, input)
    elseif ss.mode == "roll" then return runRoll(p, ss, input)
    elseif ss.mode == "land" then return runLand(p, ss)
    end
  end
  if p.minish then return nil end
  local f = p.field
  if p.state == "sword" and isSword(f:equipped(p.swordButton or "b")) then return swing(p, input) end
  if p.state == "roll" and S.skill(f, S.ITEM.ROLL) and not (f.inputLocked and f:inputLocked()) then
    for _, b in ipairs({ "b", "a" }) do
      local item = f:equipped(b)
      if input.pressed(b) and isSword(item) then
        p.swordButton = b
        enter(p, { mode = "roll", item = item, button = b, timer = S.ROLL_TIME })
        p.lastSwordMove = S.MOVE.ROLL
        p:setAnim(S.ANIM.ROLL_SLIDE, true)
        f:sound(S.SFX.VO3)
        return true
      end
    end
  end
  return nil
end

-- ---- the down thrust (for the Roc's Cape module) ------------------------
-- SwordSkills.downThrust(p): the sword pressed while Link is airborne
-- (sub_08075338's jump branch: SKILL_DOWN_THRUST, z != 0, zVelocity < 1.5,
-- not already thrusting).  Returns true when the thrust starts
-- (p.downThrust is set; the Cape keeps running the jump).
function S.downThrust(p)
  local f = p.field
  if p.minish or p.downThrust or not S.skill(f, S.ITEM.DOWN) then return false end
  if not ((p.z or 0) > 0) or (p.zv or 0) >= 1.5 then return false end
  local btn = p.swordButton or "b"
  local item = f:equipped(btn)
  if not isSword(item) then item = f:equipped(btn == "b" and "a" or "b") end
  p.downThrust = { hop = false, item = isSword(item) and item or 2 }
  p.lastSwordMove = S.MOVE.DOWN_THRUST
  return true
end

-- SwordSkills.downThrustFrame(p): each airborne frame while p.downThrust,
-- after the Cape's gravity.  At the apex (zVelocity <= 0) it makes the hop
-- (p.zv = 2.5, ANIM_DOWN_THRUST; the Cape stops horizontal motion while
-- p.downThrust.hop); keyframes with flag 8 hit (hurtType $18/$19/$1A) and
-- cut the 3x3 tiles around Link (sub_080A7B98).  Returns true on the hop.
function S.downThrustFrame(p)
  local d = p.downThrust
  if not d then return nil end
  local hopped
  if not d.hop and (p.zv or 0) <= 0 then
    d.hop = true
    p.zv = S.DOWN_HOP
    p:setAnim(S.ANIM.DOWN_THRUST, true)
    hopped = true
  end
  if d.over then return hopped end
  local fl = p.anim.flags or 0
  if band(fl, 0x80) ~= 0 and d.hop then d.over = true return hopped end
  if d.hop and band(fl, 8) ~= 0 then
    local f = p.field
    local filter = S.skill(f, S.ITEM.ROCK) and 1 or 0
    for yo = -16, 16, 16 do for xo = -16, 16, 16 do tileCut(f, filter, p.x + xo, p.y + yo, p.layer) end end
    local sw = f.assets.manifest.sword
    local b = sw and sw.boxes and sw.boxes[(p.anim.frame or 0) - 0x6A]
    if b and b[3] > 0 then
      S.hitBox(f, { x = p.x + b[1], y = p.y + b[2], w = b[3], h = b[4] }, downHurt(d.item), p.x, p.y)
    end
  end
  return hopped
end

-- SwordSkills.downThrustLand(p): the Cape's landing (sub_08073AD4 with
-- attack_status): Link finishes ANIM_DOWN_THRUST (sub_08073A94) in an ext
-- state.  Returns true when it took over.
function S.downThrustLand(p)
  if not p.downThrust then return false end
  local hop = p.downThrust.hop
  p.downThrust = nil
  if not hop then return false end
  enter(p, { mode = "land" })
  return true
end

-- --------------------------------------------------------------- drawing
local SWORD_SPRITE = { [1] = 14, [2] = 15, [3] = 15, [4] = 15, [5] = 15, [6] = 16 }

function S.draw(p, x, y)
  local ss = p.ss
  local item
  if ss and ss.mode ~= "land" then item = ss.item elseif p.downThrust and p.downThrust.hop then item = p.downThrust.item end
  if not item or p.minish or not love or not love.graphics or not love.graphics.draw then return nil end
  local frame = p.anim.frame
  if not frame or frame == 0xFF then return nil end
  local sf = frame - 0x6A
  if sf < 0 or sf > 0x8A then return nil end
  local f = p.field
  if ss and ss.mode == "charge" and ss.charged and band(f.frame or 0, 4) ~= 0 then
    sf = rshift(band(p.animationState or 4, 6), 1) + 0xB1
  end
  local A = f.assets
  local img, ox, oy = A:spriteFrame(SWORD_SPRITE[item] or 15, sf, A:objPalette(1), "sword")
  if not img then return nil end
  local flip = false
  if not (ss and ss.mode == "spin") then
    flip = p.entFlip or false
    if band(p.animationState or 0, 2) ~= 0 then flip = not flip end
  end
  if flip then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else love.graphics.draw(img, x + ox, y + oy) end
  return nil
end

return S
