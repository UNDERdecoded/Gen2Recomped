-- Round 61: TRAPDOOR $86 (src/object/trapdoor.c) -- Librari's trap door in his book house
-- (TownMinishHoles_LibrariBookHouse $2D:11), the way down to the Flippers' cave.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Trapdoor_Init: collision layer 1, spriteRendering.b3 3, spritePriority.b0 7, subAction 0;
--     ITEM_FLIPPERS owned -> action 4, frameIndex 0; else action 1, animation 0.
--   * Trapdoor_Action1: nothing until the local flag MIZUKAKI_STAIR (Librari's script sets it); then
--     GetNextFrame; a keyframe whose frame flags are exactly 1 (subAction 0) -> frame 0 and
--     sub_08099ECC; the animation done -> action 2, animation 1.
--   * Trapdoor_Action2: the animation runs three times (timer), then action 3, frameIndex 4.
--   * Trapdoor_Action3: Link within EntityInRectRadius(12, 12): subAction 0 -> sub_08099ECC
--     (+ RequestPriorityDuration(30)); with MIZUKAKI_STAIR_WARP_OK -> CreateHoleManager(7).
--   * sub_08099ECC: subAction 1, Link put on the trap door (CopyPosition), PLAYER_FALL with
--     field_0x38 0 and PL_PIT_IS_EXIT: PlayerFallUpdate does not respawn him; once the animation
--     is done he is hidden (spriteSettings.draw 0) and waits in the fall until a HOLE_MANAGER's
--     DoHoleTransition takes him (gHoleTransitions[7], read from the ROM: manifest.r13.holes).
-- SIMPLIFIED: RequestPriorityDuration(30) (it only pauses the room's other entities) is not modelled;
--   the hole manager is Holes.spawn + Holes.exitFor handed to the waiting fall (the port's managers
--   have no per-frame IsPlayerOnHole).
local bit = require("bit")
local band = bit.band

local M = {}
M.TRAPDOOR = 0x86
M.ITEM_FLIPPERS = 0x46
M.MIZUKAKI_STAIR, M.MIZUKAKI_STAIR_WARP_OK = 0x74, 0x75 -- local flags (flags.h, after MIZUKAKI_BOOK_ALLBACK $73)
M.HOLE_TYPE = 7 -- CreateHoleManager(0x7)
M.RADIUS = 12   -- EntityInRectRadius(this, player, 0xc, 0xc)

local function loc(f, n) return f:flag("local", n) end
local function anim(f, e, a)
  e.objAnim, e.animIndex, e.staticFrame = a, a, nil
  if e.anim and e.sprite then e.anim:set(f.assets:sprite(e.sprite), a, true) end
  e.flagKey = nil
end
-- GetNextFrame: the keyframe flags, once per keyframe (0 between)
local function nextFrame(e)
  if not e.anim then return 0 end
  e.anim:update(1)
  if e.flagKey ~= e.anim.key then e.flagKey = e.anim.key return e.anim.flags or 0 end
  return 0
end
local function done(e) return e.anim and (e.anim.done or band(e.anim.flags or 0, 0x80) ~= 0) end

-- EntityInRectRadius: |dx| <= rx and |dy| <= ry (unsigned (d + r) <= 2r)
function M.inRect(e, p, rx, ry)
  local dx = math.floor(p.x) - math.floor(e.x)
  local dy = math.floor(p.y) - math.floor(e.y)
  return dx + rx >= 0 and dx + rx <= 2 * rx and dy + ry >= 0 and dy + ry <= 2 * ry
end

-- sub_08099ECC
function M.drop(d, e)
  local f = d.field
  local p = f.player
  e.subAction = 1
  p.x, p.y = e.x, e.y -- CopyPosition
  p.pitWait61 = true  -- PL_PIT_IS_EXIT
  require("src.zelda.tmc.PlayerFall").start(d, p, nil)
end

function M.init(d, e)
  local f = d.field
  e.layer = 1
  e.oamPrio, e.spritePriority = 3, 7
  e.subAction = 0
  e.timer = 0
  if (f:inventory(M.ITEM_FLIPPERS) or 0) ~= 0 then
    e.action = 4
    e.staticFrame = 0
  else
    e.action = 1
    anim(f, e, 0)
  end
end

function M.update(d, e)
  local f = d.field
  local p = f.player
  if e.action == 1 then
    if loc(f, M.MIZUKAKI_STAIR) then
      local fl = nextFrame(e)
      if fl == 1 and e.subAction == 0 then M.drop(d, e) end
      if done(e) then e.action = 2; anim(f, e, 1) end
    end
  elseif e.action == 2 then
    nextFrame(e)
    if done(e) then
      e.timer = e.timer + 1
      if e.timer == 3 then e.action = 3; e.staticFrame = 4
      else anim(f, e, 1) end
    end
  elseif e.action == 3 then
    if M.inRect(e, p, M.RADIUS, M.RADIUS) then
      if e.subAction == 0 then M.drop(d, e) end
      if loc(f, M.MIZUKAKI_STAIR_WARP_OK) then M.hole(d, p) end
    end
  end
end

-- CreateHoleManager(7): the waiting fall gets the hole's exit
function M.hole(d, p)
  local H = require("src.zelda.tmc.Holes")
  if not d.trapHole61 then d.trapHole61 = H.spawn(d, { type = M.HOLE_TYPE }) end
  if p.falling and p.pitWait61 and not p.fallExit then p.fallExit = H.exitFor(d, p) end
end

function M.spawnObject(d, e)
  if e.id ~= M.TRAPDOOR then return nil end
  local f = d.field
  local def = f:objects():def(M.TRAPDOOR, e.form or 0)
  if def then f:objects():dress(e, def, 0) end
  e.literalAnim = true
  M.init(d, e)
  e.extUpdate = function(dd, me) if not me.deleted then M.update(dd, me) end end
  d:track(e)
  return e
end

-- a new room: the fall's wait is over (Link drawn again)
function M.roomInit(f)
  local p = f.player
  if p and p.hidden61 then p.hidden, p.hidden61 = nil, nil end
  if p then p.pitWait61 = nil end
end

return M
