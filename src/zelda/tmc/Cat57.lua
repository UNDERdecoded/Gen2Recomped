-- Round 57: the town cats -- CAT, NPC $2C (src/npc/cat.c), ported function by function.
--
-- The port drew the cats but ran none of their code (no script; Field's entity loop only animated them), so they stood
-- still; the cat at the garden's south row stood in the only lane to the bench and the vine.
--
-- CARTRIDGE BEHAVIOUR (cat.c, USA addresses):
--   * Cat (main): actionFuncs[action]; sub_08067C44 (the interaction); then, while COLLISION_OFF and type ~= 5,
--     sub_0806ED78 (sub_0800445C: Link pushed out of the cat's current hitbox).
--   * sub_080677EC (action 0, init): draw, direction 8 (east), speed $80, collisionFlags 7, hurtType $48,
--     hitType -$58, collisionMask 1, unk_69 = $FF, flipX = (x < Link's x), fusionOffer, hitbox gUnk_08110EF0;
--     unk_6c = sub_0805ACC0 (the DELAYED_ENTITY_LOAD record's x, i.e. the spawn x) else x; unk_6e = unk_6c + timer
--     (the record's / entity data's timer); timer 0; unk_75 0; unk_74 = (Random & $7F) + $1E; sub_08067B08.
--   * sub_08067B08: action 1 (sitting), unk_72 = gUnk_08111104[Random & 3]; sub_08067B34: animation 0
--     (sub_08067DCC), frameDuration = (Random & $30) + $B4, SetInteractableObjectCollision(0,
--     gUnk_0811110C[flipX], gUnk_0811110F).
--   * sub_080678AC (action 1): sub_08067D20 -> sub_08067B80(5); else unk_72 counts down; frame == 1 and unk_72 0 ->
--     sub_08067AAC (walk); else the animation steps, ANIM_DONE -> sub_08067B34.
--   * sub_08067AAC: action 2, unk_72 = gUnk_081110FC[Random & 3], flipX = (direction >> 4) ^ 1, animation 3,
--     SetInteractableObjectCollision(0, gUnk_0811110C[2], gUnk_0811110F).
--   * sub_08067904 (action 2, the walk): sub_08067D20 -> sub_08067B80(8); --unk_72 == 0 -> sub_08067B70 (action 3,
--     animation 4); east past unk_6e -> west (direction $18, flipX 0); west before unk_6c -> east (direction 8,
--     flipX 1); LinearMoveUpdate (speed $80: 1/2 px a frame, no tile test); the animation steps.
--   * sub_0806797C (action 3): the animation to its end -> sub_08067B08.  sub_0806799C (action 4, talking): the
--     animation steps; message gone -> sub_08067B08.
--   * sub_08067B80(anim): action 5 (watching Minish Link), timer 20, unk_74 = (Random & $7F) + $1E, the animation,
--     sub_08067DDC (COLLISION_OFF, hitbox gUnk_08110EF0), flipX = (x < Link's x).
--   * sub_080679C4 (action 5): unk_74 0 / --unk_74 0 / Link out of the watch rect -> sub_08067C24 (action 7, unk_75
--     $14, collision off, animation 7); else the animation steps, sub_08067BD4 (turn to Link past 4 px), and
--     sub_08067D74 (Link in the strike rect, timer 0) -> sub_08067C18 (action 6, animation 6).
--   * sub_08067A0C (action 6, the scratch): the animation steps; ANIM_DONE -> still watching: sub_08067B80(5) and
--     timer + 20, else sub_08067C24; while it runs, frame & 7 = n ~= 0 -> COLLISION_ON, hitbox
--     gUnk_08111154[n - 1 + flipX * 4]; else sub_08067DDC.
--   * sub_08067A78 (action 7): the animation to its end -> sub_08067AAC.  sub_08067A98 (action 8): the fusion until
--     UpdateFuseInteraction ends -> sub_08067B08.
--   * sub_08067D20 (the watch rect): unk_75 counts down first (no watch while it runs); target sub_08049DF4(2)
--     (sub_08049E80: Link only while PL_MINISH); w = flipX ? $10 : $28; (u32)(tx - (x - w)) < $31 and
--     (u32)(ty - (y - 4)) < $39.  sub_08067D74 (the strike rect; never for type 5): timer counts down;
--     w = flipX ? 8 : $18; (u32)(tx - (x - w)) < $1F, (u32)(ty - y) < $17 and timer 0.
--   * sub_08067C44: Minish or not changed -> AddInteractableWhenBigObject / AddInteractableAsMinishFuser (both make
--     the cat answer A); on an interaction: animation by sub_0806FCA0 (Link below -> 2, else 1; walking: Link to
--     the east -> flipX 1), then INTERACTION_FUSE -> action 8 (InitializeNPCFusion), else action 4 and
--     sub_08067790 (ShowNPCDialogue(dialogs[type][global_progress])), SetEntityPriority(PRIO_MESSAGE);
--     interactType none; SoundReq(SFX_VO_CAT).
-- The tables (gUnk_08110EF0, the dialogs, gUnk_081110FC, gUnk_08111104, gUnk_0811110C, gUnk_0811110F, gUnk_08111154)
-- are read from the player's ROM (RomTablesCat "Cat57.*").
-- SIMPLIFIED: gEnemyTarget (an enemy's earlier pick of the frame) is not cached -- the town has no enemies;
--   SetEntityPriority is not modelled; the scratch's contact uses the enemy contact rules of Enemies.lua
--   (gCollisionMtx row hitType $A8, Link's hurtType) without the cat's own contactFlags.
local bit = require("bit")
local band, bxor, rshift = bit.band, bit.bxor, bit.rshift

local M = {}
M.ID = 0x2C
M.SFX_VO_CAT = 0xD2
M.HIT_TYPE = 0xA8 -- -$58 as a u8
M.HURT_TYPE = 0x48
M.SPEED = 0x80

local RT = require("src.zelda.tmc.RomTables")
local BOX = RT.t("Cat57.BOX")         -- gUnk_08110EF0 (Hitbox)
local DIALOG = RT.t("Cat57.DIALOG")   -- sub_08067790's dialogs[6][10] (Dialog)
local WALK_T = RT.t("Cat57.WALK_T")   -- gUnk_081110FC (u16[4])
local SIT_T = RT.t("Cat57.SIT_T")     -- gUnk_08111104 (u16[4])
local DIRS = RT.t("Cat57.DIRS")       -- gUnk_0811110C (u8[3])
local IBOX = RT.t("Cat57.IBOX")       -- gUnk_0811110F (the interact box)
local SCRATCH = RT.t("Cat57.SCRATCH") -- gUnk_08111154 (Hitbox*[8])
M.tables = { BOX = BOX, DIALOG = DIALOG, WALK_T = WALK_T, SIT_T = SIT_T, DIRS = DIRS, IBOX = IBOX, SCRATCH = SCRATCH }

local function S27() return require("src.zelda.tmc.Story27Town") end
local function rand(f)
  if M.random then return M.random(f) end -- tests
  return S27().rand(f)
end
local function hb(b) return { x = b.x, y = b.y, w = b.w, h = b.h } end
local function ix(e) return math.floor(e.x) end
local function iy(e) return math.floor(e.y) end

-- InitAnimationForceUpdate(e, i) on the cat (its own animation, stepped here)
local function anim(f, e, i)
  e.objAnim, e.animIndex, e.catAnim = i, i, i
  if e.anim and e.sprite and f.assets and f.assets.sprite then e.anim:set(f.assets:sprite(e.sprite), i, true) end
end
M.anim = anim
-- UpdateAnimationSingleFrame
local function step(e) if e.anim then e.anim:update(1) end end
-- the cartridge's frame byte (the keyframe's flags; $80 = ANIM_DONE)
local function frameByte(e) return e.anim and (e.anim.flags or 0) or 0 end
local function done(e) return band(frameByte(e), 0x80) ~= 0 end
M.frameByte = frameByte

local function flipX(e) return e.flipX and 1 or 0 end
local function setFlip(e, v) e.flipX = (v ~= 0) end

-- SetInteractableObjectCollision(e, 0, dirs, gUnk_0811110F)
local function interact(e, dirs)
  e.interactBox = { x = IBOX.x, y = IBOX.y, w = IBOX.w, h = IBOX.h, dirs = dirs }
end
-- sub_08067DDC
local function collisionOff(e)
  e.catCollide = false
  e.hitbox = hb(BOX)
end
M.collisionOff = collisionOff

-- sub_08049DF4(2) = sub_08049E80: Link while Minish (not killed)
function M.target(f)
  local p = f.player
  if not p or p.state == "dead" or not p.minish then return nil end
  return p
end

-- sub_08067D20
function M.watch(f, e)
  local c = e.cat
  if c.unk75 ~= 0 then
    c.unk75 = c.unk75 - 1
    return false
  end
  local t = M.target(f)
  if not t then return false end
  local w = flipX(e) ~= 0 and 0x10 or 0x28
  local dx = ix(t) - (ix(e) - w)
  local dy = iy(t) - (iy(e) - 4)
  return dx >= 0 and dx < 0x31 and dy >= 0 and dy < 0x39
end
-- sub_08067D74
function M.strike(f, e)
  if (e.form or 0) == 5 then return false end
  if (e.timer or 0) ~= 0 then e.timer = e.timer - 1 end
  local t = M.target(f)
  if not t then return false end
  local w = flipX(e) ~= 0 and 8 or 0x18
  local dx = ix(t) - (ix(e) - w)
  local dy = iy(t) - iy(e)
  return dx >= 0 and dx < 0x1F and dy >= 0 and dy < 0x17 and e.timer == 0
end

-- sub_08067DCC
local function setAnim71(f, e, i) e.cat.unk71 = i; anim(f, e, i) end
-- sub_08067B34
local function sitAnim(f, e)
  setAnim71(f, e, 0)
  if e.anim then e.anim.timer = band(rand(f), 0x30) + 0xB4 end -- frameDuration
  interact(e, DIRS[flipX(e)])
end
-- sub_08067B08
local function sit(f, e)
  e.action = 1
  e.cat.unk72 = SIT_T[band(rand(f), 3)]
  sitAnim(f, e)
end
M.sit = sit
-- sub_08067AAC
local function walk(f, e)
  e.action = 2
  e.cat.unk72 = WALK_T[band(rand(f), 3)]
  setFlip(e, bxor(rshift(e.direction, 4), 1))
  setAnim71(f, e, 3)
  interact(e, DIRS[2])
end
M.walk = walk
-- sub_08067B70
local function stop(f, e) e.action = 3; setAnim71(f, e, 4) end
-- sub_08067B80
local function watchStart(f, e, i)
  e.action = 5
  e.timer = 20
  e.cat.unk74 = band(rand(f), 0x7F) + 0x1E
  anim(f, e, i)
  collisionOff(e)
  setFlip(e, ix(e) < ix(f.player) and 1 or 0)
end
M.watchStart = watchStart
-- sub_08067BD4
local function turn(f, e)
  local px = ix(f.player)
  if flipX(e) > 0 then
    if ix(e) - 4 > px then setFlip(e, 0) end
  else
    if ix(e) + 4 < px then setFlip(e, 1) end
  end
end
-- sub_08067C18
local function scratch(f, e) e.action = 6; anim(f, e, 6) end
-- sub_08067C24
local function leave(f, e)
  e.action = 7
  e.cat.unk75 = 0x14
  collisionOff(e)
  anim(f, e, 7)
end

-- sub_080677EC
local function init(f, e)
  e.direction = 8
  e.speed = M.SPEED
  e.hitType, e.hurtType = M.HIT_TYPE, M.HURT_TYPE
  e.literalAnim = true
  e.noHitbox = true -- Hitboxes.update: the cat pushes Link out itself (its own hitbox)
  e.talkable = true
  local c = { unk69 = 0xFF }
  e.cat = c
  setFlip(e, ix(e) < ix(f.player) and 1 or 0)
  e.hitbox = hb(BOX)
  e.catCollide = false
  -- sub_0805ACC0: the DELAYED_ENTITY_LOAD record's x = the spawn x
  local d = e.data or {}
  local x0 = d.x or ix(e)
  local tmr = d.timer or band(rshift(e.param or 0, 8), 0xFF)
  c.unk6c = x0
  c.unk6e = band(tmr, 0xFF) + x0
  e.timer = 0
  c.unk75 = 0
  c.unk74 = band(rand(f), 0x7F) + 0x1E
  sit(f, e)
end
M.init = init

local ACTIONS = {}
ACTIONS[1] = function(f, e) -- sub_080678AC
  local c = e.cat
  if M.watch(f, e) then watchStart(f, e, 5) return end
  if c.unk72 ~= 0 then c.unk72 = c.unk72 - 1 end
  if frameByte(e) == 1 and c.unk72 == 0 then walk(f, e)
  else
    step(e)
    if done(e) then sitAnim(f, e) end
  end
end
ACTIONS[2] = function(f, e) -- sub_08067904
  local c = e.cat
  if M.watch(f, e) then watchStart(f, e, 8) return end
  c.unk72 = band(c.unk72 - 1, 0xFFFF)
  if c.unk72 == 0 then stop(f, e) return end
  if e.direction == 8 then
    if ix(e) > c.unk6e then e.direction = 0x18; setFlip(e, 0) end
  else
    if ix(e) < c.unk6c then e.direction = 8; setFlip(e, 1) end
  end
  -- LinearMoveUpdate: directions 8 / $18 only (east / west), speed $80
  e.x = e.x + (e.direction == 8 and 1 or -1) * e.speed / 256
  step(e)
end
ACTIONS[3] = function(f, e) step(e) if done(e) then sit(f, e) end end -- sub_0806797C
ACTIONS[4] = function(f, e) -- sub_0806799C
  step(e)
  if not f.textbox then sit(f, e) end
end
ACTIONS[5] = function(f, e) -- sub_080679C4
  local c = e.cat
  local out = c.unk74 == 0
  if not out then c.unk74 = c.unk74 - 1; out = c.unk74 == 0 end
  if out or not M.watch(f, e) then leave(f, e)
  else
    step(e)
    turn(f, e)
    if M.strike(f, e) then scratch(f, e) end
  end
end
ACTIONS[6] = function(f, e) -- sub_08067A0C
  step(e)
  if done(e) then
    if M.watch(f, e) then watchStart(f, e, 5); e.timer = e.timer + 20
    else leave(f, e) end
  else
    local n = band(frameByte(e), 7)
    if n ~= 0 then
      e.catCollide = true
      local b = SCRATCH[n - 1 + flipX(e) * 4]
      if b then e.hitbox = hb(b) end
    else
      collisionOff(e)
    end
  end
end
ACTIONS[7] = function(f, e) step(e) if done(e) then walk(f, e) end end -- sub_08067A78
ACTIONS[8] = function(f, e) -- sub_08067A98 (the fusion itself runs in Field's loop: Fusers.update)
  if not e.fusing then sit(f, e) end
end
M.ACTIONS = ACTIONS

-- sub_08067C44 (the interaction)
function M.interaction(f, e)
  local c = e.cat
  local minish = f.player and f.player.minish and 1 or 0
  if minish ~= c.unk69 then e.talkable = true end -- AddInteractableWhenBigObject / AddInteractableAsMinishFuser
  c.unk69 = minish
  if e.fusing and e.action ~= 8 then e.action = 8 end -- INTERACTION_FUSE (Fusers.tryFuse -> InitializeNPCFusion)
  if (e.interactType or 0) == 0 then return end
  local S = S27()
  local d4 = S.state4(S.dir32(ix(e), iy(e), ix(f.player), iy(f.player)))
  if (e.catAnim or 0) == 3 and d4 == 1 then setFlip(e, 1) end
  anim(f, e, d4 == 2 and 2 or 1)
  e.action = 4
  local t = (e.form or 0) * 10 + math.max(0, math.min(9, f.save and f.save.progress or 1))
  local dg = DIALOG[t]
  if dg then S.dialogue(f, e, dg.w, dg.a, dg.b) end
  e.interactType = 0
  if f.sound then f:sound(M.SFX_VO_CAT) end
end

-- the scratch's contact with Link (COLLISION_ON with a gUnk_08111154 box)
function M.contact(f, e)
  if not e.catCollide then return end
  local p = f.player
  if not p or p.state == "dead" or (p.invuln or 0) > 0 then return end
  local HBm = require("src.zelda.tmc.Hitboxes")
  local touch = HBm.touches(f, p, e)
  if not touch then return end
  local E = f._enemies
  local handler = E and E.mtx and E.mtx ~= "" and HBm.handler(E.mtx, M.HIT_TYPE, HBm.hurtType(p))
  if handler == 1 or handler == 2 then return end
  local s = E and E.mtx and E.mtx ~= "" and E:settings(M.HIT_TYPE, HBm.hurtType(p))
  if not s then return end
  if s.tgtDmg > 0 or s.orgKbDur > 0 then
    if p:hurt(math.max(s.tgtDmg, 1), e.x, e.y) then
      p.invuln = math.max(s.orgIfr, 30)
      p.timer = math.max(s.orgKbDur, 4)
      local ks = (s.orgKbSpd * 16) / 256
      local dx, dy = p.x - e.x, p.y - e.y
      local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.kbx, p.kby = dx / dd * ks, dy / dd * ks
    end
  end
end

-- Cat (main), once per frame from Field's entity loop
function M.update(f, e)
  if e.deleted or e.script then return end
  if not e.cat then
    if not RT.attached() then return end
    init(f, e)
  end
  local a = ACTIONS[e.action]
  if a then a(f, e) end
  M.interaction(f, e)
  M.contact(f, e)
  if not e.catCollide and (e.form or 0) ~= 5 then
    require("src.zelda.tmc.Hitboxes").pushOut(f, e, e.hitbox) -- sub_0806ED78
  end
end

return M
