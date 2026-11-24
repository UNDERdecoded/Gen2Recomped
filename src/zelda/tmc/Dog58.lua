-- Round 58: the dogs -- DOG, NPC $35 (src/npc/dog.c), ported function by function.
--
-- The port drew the dogs (NpcParts: the head, Dog_Head) but ran none of their code: they stood still, no one
-- answered a talk, MACHI_02_DOG was never set, and the town's type-2 dog (the foot of the west stairs) stood in
-- full-size Link's only lane between the town's south-west and its north for good.
--
-- CARTRIDGE BEHAVIOUR (dog.c, USA addresses):
--   * Dog ($08069B1C): gUnk_08111D88[action]; sub_0806ED78 (Link pushed out of the dog's hitbox -- Hitboxes.update
--     does it for every solid NPC); sub_08069FE8.
--   * sub_08069B44 (action 0): sub_08069EF0 (LoadExtraSpriteData(gUnk_08111D58[type * 3]) -- NpcParts --, action 1,
--     unk_68 = gUnk_08111E30[type]); the wander box from sub_0805ACC0 (the DELAYED_ENTITY_LOAD record's x / y, else
--     the entity's): r = timer or $20, unk_6e = x - r, unk_6c = x + r, unk_70 = y - 8, unk_72 = y + 8; speed $100,
--     timer 30, animationState 2, unk_6a $FF, unk_74 = GetFusionToOffer, InitAnimationForceUpdate(10);
--     ENT_SCRIPTED -> InitScriptForNPC; type 0, Link full size and ITEM_QST_DOGFOOD ~= 2 -> action 4; type 2 and
--     MACHI_02_DOG clear -> SetTile(SPECIAL_TILE_114, TILE(x, y - 8), layer).
--   * sub_08069C40 (action 1): the animation steps; sub_08069F90 -> Minish: sub_08069CB8, else animationState =
--     GetAnimationState and sub_08069D00; timer 30; else --timer 0 -> action 2, timer (R & $1F) + 30, direction
--     gUnk_08111DA8[R & 7], sub_08069F6C.
--   * sub_08069CB8: v = gUnk_08111DB0[GetFacingDirection(dog, Link) + animationState * $20]; animationState = v >> 6,
--     unk_6b = v & $3F; sub_0806A028; animation unk_6b.
--   * sub_08069D00: unk_6b 8; sub_0806A028; an animation past $1F runs to ANIM_DONE first (then unk_6b 8);
--     (R & $1FF) < 3 -> sub_08069FBC; animation unk_6b + animationState.
--   * sub_08069D54 (action 2, the walk): not sub_08069F90 and --timer ~= 0: the animation steps, ProcessMovement0,
--     the box clamp (x < unk_6e -> x = unk_6e + 1, COL_WEST_ANY; x > unk_6c -> unk_6c - 1, COL_EAST_ANY; then y with
--     unk_70 / unk_72, COL_NORTH_ANY / COL_SOUTH_ANY: the clamp's flag replaces the tile collisions),
--     sub_0800417E (the bounce), sub_08069F6C; else action 1 (sub_08069F90) or 3, timer (R & $1F) + 30.
--   * sub_08069DF8 (action 3, standing): the animation steps; sub_08069F90 -> action 1; else --timer ~= 0 ->
--     sub_08069D00; else (R & $FF) < $30 -> action 2, else 3; timer (R & $1F) + 30.
--   * sub_08069E44 (action 4): ExecuteScriptAndHandleAnimation(NULL).  sub_08069E50 (action 5, Stockwell's dog
--     waiting for the food): animationState = GetAnimationState, unk_6b 8, sub_0806A028, the animation steps, the
--     $1F rule, sub_08069FBC, animation unk_6b + state; ITEM_QST_DOGFOOD = 2 -> action 7, animation $29,
--     RemoveInteractableObject, SFX_VO_DOG, SFX_TASK_COMPLETE.  sub_08069ECC (action 6): UpdateFuseInteraction
--     ends -> action 1 (USA).  sub_08069EE0 (action 7): the animation steps.
--   * sub_08069F6C: animationState = GetAnimationStateForDirection4(direction), animation state + 4.
--   * sub_08069F90: type 2 with MACHI_02_DOG clear -> TRUE (always "near" Link); else EntityInRectRadius(dog, Link,
--     $14, $14).  sub_08069FBC: animationState 1 / 3 -> unk_6b = Minish ? $24 : $20.
--   * sub_08069FE8: Minish changed -> AddInteractableWhenBigObject / AddInteractableAsMinishFuser(unk_74).
--   * sub_0806A028: an interaction -> Minish: INTERACTION_FUSE -> action 6 (InitializeNPCFusion), else
--     sub_0806A080; full size: sub_08069FBC, sub_0806A080, SFX_VO_DOG, ResetPlayerAnimationAndAction; interactType 0.
--   * sub_0806A080: ShowNPCDialogue(gUnk_08111E34[type2][global_progress]).
--   * sub_0806A0A4 (type2 2's DIALOG_CALL_FUNC): Minish: 4, or MACHI_02_DOG clear -> 3, SetLocalFlag(MACHI_02_DOG),
--     RestorePrevTileEntity(TILE(x, y - 8)); full size: 2, or MACHI_02_DOG clear -> 1, or MACHI_DOG_C clear -> 0
--     and SetLocalFlag(MACHI_DOG_C); MessageNoOverlap(gUnk_08111F74[global_progress][dialog]).
--   * sub_0806A144 (type2 3's): 4; Minish -> 3, or no Flippers and MIZUKAKI_START -> local $85 clear ? 1 : 2;
--     MessageNoOverlap(gUnk_08111FD8[dialog]).
-- The flag numbers come from the code (sub_0806A0A4's immediates: MACHI_02_DOG $CF, MACHI_DOG_C $DB).
-- The tables (gUnk_08111DA8, gUnk_08111DB0, gUnk_08111E34, gUnk_08111F74, gUnk_08111FD8) are read from the
-- player's ROM (RomTablesCat "Dog58.*").
-- SIMPLIFIED: SetEntityPriority is not modelled; a scripted dog (ENT_SCRIPTED: Stockwell's, its script and
--   sub_08069EE8 in Story27Town) keeps the port's script path; Dog_Fusion (the fusion-cutscene dog) is not used.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}
M.ID = 0x35
M.MACHI_02_DOG, M.MACHI_DOG_C, M.LOCAL_85 = 0xCF, 0xDB, 0x85
M.MIZUKAKI_START = 0x29
M.ITEM_QST_DOGFOOD, M.ITEM_FLIPPERS = 0x36, 0x46
M.SPECIAL_TILE_114 = 0x4072
M.SFX_VO_DOG, M.SFX_TASK_COMPLETE = 0xD1, 0xCD
M.SPEED = 0x100
M.FN_A0A4, M.FN_A144 = 0x0806A0A4, 0x0806A144

local RT = require("src.zelda.tmc.RomTables")
local DIRS = RT.t("Dog58.DIRS")     -- gUnk_08111DA8 (u8[8])
local ANIM = RT.t("Dog58.ANIM")     -- gUnk_08111DB0 (u8[4 * $20])
local DIALOG = RT.t("Dog58.DIALOG") -- gUnk_08111E34[4][10] (Dialog)
local MSG = RT.t("Dog58.MSG")       -- gUnk_08111F74[10][5] (u16)
local MSG2 = RT.t("Dog58.MSG2")     -- gUnk_08111FD8[5] (u16)
M.tables = { DIRS = DIRS, ANIM = ANIM, DIALOG = DIALOG, MSG = MSG, MSG2 = MSG2 }

local function S27() return require("src.zelda.tmc.Story27Town") end
local function rand(f)
  if M.random then return M.random(f) end -- tests
  return S27().rand(f)
end
local function ix(e) return math.floor(e.x) end
local function iy(e) return math.floor(e.y) end
local function minish(f) return f.player and f.player.minish and true or false end
local function progress(f) return math.max(0, math.min(9, f.save and f.save.progress or 1)) end
local function inv(f, item) return f.inventory and f:inventory(item) or 0 end
local function sound(f, n) if f.sound then f:sound(n) end end
local function typ(e) return e.form or 0 end
local function type2(e) return band(e.param or 0, 0xFF) end

-- InitAnimationForceUpdate(e, i) on the dog (its own animation, stepped here)
local function anim(f, e, i)
  e.objAnim, e.animIndex = i, i
  if e.anim and e.sprite and f.assets and f.assets.sprite then e.anim:set(f.assets:sprite(e.sprite), i, true) end
end
M.anim = anim
-- UpdateAnimationSingleFrame
local function step(e) if e.anim then e.anim:update(1) end end
local function done(e) return e.anim and band(e.anim.flags or 0, 0x80) ~= 0 end

-- GetFacingDirection(dog, Link) (CalculateDirectionTo, 0 .. 31) and GetAnimationState (its 4-way state)
function M.facing(f, e) return S27().dir32(ix(e), iy(e), ix(f.player), iy(f.player)) end
local function animState(f, e) return S27().state4(M.facing(f, e)) end

-- the tile under the type-2 dog: SetTile / RestorePrevTileEntity
local function tileOf(e) return rshift(ix(e), 4), rshift(iy(e) - 8, 4), (e.layer == 2) and 2 or 1 end
function M.block(f, e)
  local r = f.room
  if not r or not r.setTile then return end
  local tx, ty, l = tileOf(e)
  local name = l == 2 and "top" or "bottom"
  local old = r.maps and r.maps[name] and r.maps[name][ty * r.tw + tx]
  e.dog.prevTile = { tx, ty, l, old }
  r:setTile(l, tx, ty, M.SPECIAL_TILE_114)
end
function M.unblock(f, e)
  local p = e.dog and e.dog.prevTile
  if not p then return end
  e.dog.prevTile = nil
  if p[4] and f.room and f.room.setTile then f.room:setTile(p[3], p[1], p[2], p[4]) end
end

-- sub_08069F90
function M.near(f, e)
  if typ(e) == 2 and not f:flag("local", M.MACHI_02_DOG) then return true end
  local p = f.player
  if not p then return false end
  local dx, dy = ix(e) - ix(p), iy(e) - iy(p) -- EntityInRectRadius($14, $14)
  return dx >= -0x14 and dx <= 0x14 and dy >= -0x14 and dy <= 0x14
end
-- sub_08069FBC
local function sniff(f, e)
  local t = minish(f) and 0x24 or 0x20
  if e.animationState == 1 or e.animationState == 3 then e.dog.unk6b = t end
end
-- sub_08069F6C
local function walkAnim(f, e)
  e.animationState = S27().state4(e.direction)
  if e.animationState + 4 ~= e.animIndex then anim(f, e, e.animationState + 4) end
end
M.walkAnim = walkAnim

-- sub_0806A0A4 (type2 2) / sub_0806A144 (type2 3)
function M.talkA0A4(f, e)
  local dialog
  if minish(f) then
    dialog = 4
    if not f:flag("local", M.MACHI_02_DOG) then
      dialog = 3
      f:setFlag("local", M.MACHI_02_DOG, true)
      if e.dog then M.unblock(f, e) end
    end
  else
    dialog = 2
    if not f:flag("local", M.MACHI_02_DOG) then
      dialog = 1
      if not f:flag("local", M.MACHI_DOG_C) then dialog = 0; f:setFlag("local", M.MACHI_DOG_C, true) end
    end
  end
  local t = MSG[progress(f) * 5 + dialog]
  f:message(t, e)
  return t
end
function M.talkA144(f, e)
  local dialog = 4
  if minish(f) then
    dialog = 3
    if inv(f, M.ITEM_FLIPPERS) == 0 and f:flag("global", M.MIZUKAKI_START) then
      dialog = f:flag("local", M.LOCAL_85) and 2 or 1
    end
  end
  local t = MSG2[dialog]
  f:message(t, e)
  return t
end
-- sub_0806A080: ShowNPCDialogue(gUnk_08111E34[type2][global_progress])
function M.dialogue(f, e)
  local d = DIALOG[band(type2(e), 3) * 10 + progress(f)]
  if not d then return end
  local fn
  if band(rshift(d.w, 16), 0xF) == 5 then -- DIALOG_CALL_FUNC: the function's address (Thumb bit) in a / b
    local addr = band(d.a + d.b * 65536, 0xFFFFFFFE)
    if addr == M.FN_A0A4 then fn = M.talkA0A4 elseif addr == M.FN_A144 then fn = M.talkA144 end
  end
  return S27().dialogue(f, e, d.w, d.a, d.b, fn)
end
-- sub_0806A028
function M.interaction(f, e)
  if (e.interactType or 0) == 0 then return end
  if minish(f) then
    M.dialogue(f, e)
  else
    sniff(f, e)
    M.dialogue(f, e)
    sound(f, M.SFX_VO_DOG)
    local N = require("src.zelda.tmc.Native").N
    if N[0x080791BC] then pcall(N[0x080791BC], f) end -- ResetPlayerAnimationAndAction
  end
  e.interactType = 0
end
-- sub_08069CB8
local function faceMinish(f, e)
  local v = ANIM[M.facing(f, e) + (e.animationState or 0) * 0x20] or 0
  e.animationState = rshift(v, 6)
  e.dog.unk6b = band(v, 0x3F)
  M.interaction(f, e)
  if e.animIndex ~= e.dog.unk6b then anim(f, e, e.dog.unk6b) end
end
-- sub_08069D00
local function idle(f, e)
  e.dog.unk6b = 8
  M.interaction(f, e)
  if (e.animIndex or 0) > 0x1F then
    if not done(e) then return end
    e.dog.unk6b = 8
  end
  if band(rand(f), 0x1FF) < 3 then sniff(f, e) end
  if e.animIndex ~= e.dog.unk6b + e.animationState then anim(f, e, e.dog.unk6b + e.animationState) end
end

-- sub_08069B44 (+ sub_08069EF0)
local function init(f, e)
  local d = e.data or {}
  e.action = 1
  e.dog = { unk68 = 0, unk6a = 0xFF, unk6b = 0 }
  local x0, y0 = d.x or ix(e), d.y or iy(e) -- sub_0805ACC0
  local r = band(d.timer or rshift(e.param or 0, 8), 0xFF) -- the entity data's timer
  if r == 0 then r = 0x20 end
  local g = e.dog
  g.unk6e, g.unk6c, g.unk70, g.unk72 = x0 - r, x0 + r, y0 - 8, y0 + 8
  e.speed = M.SPEED
  e.timer = 30
  e.animationState = 2
  e.literalAnim = true
  e.talkable = true
  anim(f, e, 10)
  if typ(e) == 0 and not minish(f) and inv(f, M.ITEM_QST_DOGFOOD) ~= 2 then e.action = 4 end
  if typ(e) == 2 and not f:flag("local", M.MACHI_02_DOG) then M.block(f, e) end
end
M.init = init

local function newTimer(f) return band(rand(f), 0x1F) + 30 end
local ACTIONS = {}
ACTIONS[1] = function(f, e) -- sub_08069C40
  step(e)
  if M.near(f, e) then
    if minish(f) then faceMinish(f, e)
    else
      e.animationState = animState(f, e)
      idle(f, e)
    end
    e.timer = 30
  else
    e.timer = band(e.timer - 1, 0xFF)
    if e.timer == 0 then
      e.action = 2
      e.timer = newTimer(f)
      e.direction = DIRS[band(rand(f), 7)]
      walkAnim(f, e)
    end
  end
end
-- sub_0800417E: the bounce off what stopped it
local function bounce(e, hx, hy)
  local d = e.direction
  if hx then d = 0x20 - d end
  if hy then d = 0x10 - d end
  e.direction = band(d, 0x1F)
end
M.bounce = bounce
-- ProcessMovement0 (EnemyDeepwood.move0: the per-axis box test) with the dog's NPC hitbox
local function move0(f, e)
  local HB = require("src.zelda.tmc.Hitboxes")
  local box = (HB.npc and f.assets and HB.data and HB.data(f) and HB.npc(f, e)) or { x = 0, y = 0, w = 6, h = 4 }
  local proxy = { x = e.x, y = e.y, hitbox = box, layer = e.layer }
  local hx, hy = require("src.zelda.tmc.EnemyDeepwood").move0({ field = f }, proxy, e.direction, e.speed)
  e.x, e.y = proxy.x, proxy.y
  return hx, hy
end
M.move0 = move0
ACTIONS[2] = function(f, e) -- sub_08069D54
  if not M.near(f, e) then
    e.timer = band(e.timer - 1, 0xFF)
    if e.timer ~= 0 then
      step(e)
      local hx, hy = (M.moveFn or move0)(f, e)
      local g = e.dog
      local fx = e.x - math.floor(e.x)
      local fy = e.y - math.floor(e.y)
      if ix(e) < g.unk6e then e.x = g.unk6e + 1 + fx; hx, hy = true, false
      elseif ix(e) > g.unk6c then e.x = g.unk6c - 1 + fx; hx, hy = true, false end
      if iy(e) < g.unk70 then e.y = g.unk70 + 1 + fy; hx, hy = false, true
      elseif iy(e) > g.unk72 then e.y = g.unk72 - 1 + fy; hx, hy = false, true end
      bounce(e, hx, hy)
      walkAnim(f, e)
      return
    end
  end
  e.action = M.near(f, e) and 1 or 3
  e.timer = newTimer(f)
end
ACTIONS[3] = function(f, e) -- sub_08069DF8
  step(e)
  if M.near(f, e) then e.action = 1
  else
    e.timer = band(e.timer - 1, 0xFF)
    if e.timer ~= 0 then idle(f, e) return end
    e.action = band(rand(f), 0xFF) < 0x30 and 2 or 3
  end
  e.timer = newTimer(f)
end
ACTIONS[4] = function(f, e) step(e) end -- sub_08069E44 (ExecuteScriptAndHandleAnimation, no script)
ACTIONS[5] = function(f, e) -- sub_08069E50
  e.animationState = animState(f, e)
  e.dog.unk6b = 8
  M.interaction(f, e)
  step(e)
  if (e.animIndex or 0) > 0x1F then
    if not done(e) then return end
    e.dog.unk6b = 8
  end
  sniff(f, e)
  if e.animIndex ~= e.dog.unk6b + e.animationState then anim(f, e, e.dog.unk6b + e.animationState) end
  if inv(f, M.ITEM_QST_DOGFOOD) == 2 then
    e.action = 7
    anim(f, e, 0x29)
    e.talkable = false
    sound(f, M.SFX_VO_DOG); sound(f, M.SFX_TASK_COMPLETE)
  end
end
ACTIONS[6] = function(f, e) if not e.fusing then e.action = 1 end end -- sub_08069ECC (Fusers.update runs the fusion)
ACTIONS[7] = function(f, e) step(e) end -- sub_08069EE0
M.ACTIONS = ACTIONS

-- sub_08069FE8
local function interactable(f, e)
  local m = minish(f) and 1 or 0
  if m ~= e.dog.unk6a then e.talkable = true end -- AddInteractableWhenBigObject / AddInteractableAsMinishFuser
  e.dog.unk6a = m
end

-- Dog (main), once per frame from Field's entity loop
function M.update(f, e)
  if e.deleted or e.script then return end
  if not e.dog then
    if not RT.attached() then return end
    init(f, e)
    interactable(f, e)
    return
  end
  if e.fusing and e.action ~= 6 then e.action = 6 end -- INTERACTION_FUSE: InitializeNPCFusion
  local a = ACTIONS[e.action]
  if a then a(f, e) end
  interactable(f, e)
end

return M
