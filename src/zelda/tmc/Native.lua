-- Native functions the cartridge's scripts call (Script `Call` /
-- `CallWithArg`), ported by address.
--
-- HOW THE ADDRESSES WERE FOUND: the decomp's script sources
-- (data/scripts/**/*.inc) name the function of every Call; assembling the
-- same scripts puts its address in the ROM.  A scratch tool matched each
-- source script to its bytes in the ROM by the full opcode sequence and
-- read the name -> address pairs (148 unambiguous ones); functions named
-- sub_XXXXXXXX carry their address in the name; a few neighbours in
-- src/script.c were placed by the thumb function starts between known
-- ones (CreatePlayerQuestionMark $0807F40C, SetPriorityPlayerEvent
-- $0807F354, WaitForPlayerMacro $0807F2A8, the collision-layer setters,
-- GetRandomInt $0807F0EC).  Addresses below are the function's, without
-- the thumb bit.
--
-- Each port is fn(field, entity, ctx, active) where `active` is the
-- interpreter's gActiveScriptInfo (flags bit 0 = keep going this frame,
-- commandSize 0 = run this command again next frame).

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local Native = {}
local N = {}
Native.table = N

local function keepGoing(a) a.flags = bor(a.flags, 1) end
local function stay(a) a.commandSize = 0 end
local function face(e, tx, ty)
  local dx, dy = tx - e.x, ty - e.y
  if math.abs(dx) > math.abs(dy) then e.animationState = dx > 0 and 2 or 6
  else e.animationState = dy > 0 and 4 or 0 end
end

-- ---------------------------------------------------------- src/script.c
N[0x0807F0EC] = function(f, e, ctx) -- GetRandomInt
  local n = ctx.intVariable
  ctx.intVariable = n > 0 and math.random(0, n - 1) or 0
end
local SVAL = { 0xA, 0x14, 0x1E, 0x12, 0x1C, 0x26, 0xC, 0x18 }
N[0x0807F100] = function(f, e, ctx) -- random facing (even states), random idle time
  e.animationState = band(math.random(0, 7), 6)
  ctx.unk1A = SVAL[math.random(1, 8)]
end
local SSTATE = { 6, 2, 6, 2, 4, 6, 4, 2 }
N[0x0807F128] = function(f, e, ctx)
  e.animationState = SSTATE[math.random(1, 8)]
  ctx.unk1A = SVAL[math.random(1, 8)]
end
N[0x0807F158] = function(f, e) e.layer = 1 end          -- SetCollisionLayer1
N[0x0807F168] = function(f) f.player.layer = 1 end       -- SetPlayerCollisionLayer1
N[0x0807F180] = function(f, e) e.layer = 2 end          -- SetCollisionLayer2
N[0x0807F190] = function(f) f:fade("in", false, 256) end -- SetFade(FADE_INSTANT, 256)
N[0x0807F1A0] = function(f, e, ctx, a)                   -- look at the player
  face(e, f.player.x, f.player.y)
  keepGoing(a)
end
N[0x0807F1C4] = function(f) f.player.scriptAnim = f.player.hasCap and 0x1BC or 0x459 end -- ANIM_DIE1(_NOCAP)
N[0x0807F1E8] = function(f) f.player.scriptAnim = f.player.hasCap and 0x2BD or 0x45A end -- ANIM_DIE2(_NOCAP)
N[0x0807F210] = function(f) f.player.scriptAnim = f.player.hasCap and 0x80C or 0x41C end -- ANIM_HOP(_NOCAP)
N[0x0807F244] = function(f, e, ctx)                      -- EquipItem: item | slot << 16
  local item, slot = band(ctx.intVariable, 0xFFFF), rshift(ctx.intVariable, 16)
  if item >= 1 and item <= 6 then
    for _, s in ipairs({ 6, 4, 3, 2, 1 }) do if f:inventory(s) ~= 0 then item = s break end end
  end
  f:equip(slot == 0 and "a" or "b", item)
end
N[0x0807F29C] = function() end                            -- SetPlayerMacro (input recordings: not ported)
-- SetPlayerMacro / WaitForPlayerMacro (round 5: PlayerMacro.lua)
N[0x0807F29C] = function(f, e, ctx) require("src.zelda.tmc.PlayerMacro").init(f, ctx.intVariable) end
N[0x0807F2A8] = function(f, e, ctx, a) if f.playerMacro then stay(a) else keepGoing(a) end end
N[0x0807F2D4] = function(f, e, ctx, a)                   -- WaitForAnimDone
  if e.anim and e.anim.done then keepGoing(a) else stay(a) end
end
N[0x0807F304] = function(f, e, ctx, a)                   -- WaitForPlayerAnim
  if f.player.anim.done then keepGoing(a) else stay(a) end
end
N[0x0807F348] = function() end                            -- SetPriorityMessage
N[0x0807F354] = function() end                            -- SetPriorityPlayerEvent
N[0x0807F360] = function() end                            -- SetPriorityHighest
N[0x0807F36C] = function() end                            -- FX_REFLECT4 sparkle
N[0x0807F3C8] = function(f) f:sound(0x10C) end            -- the sparkle + SFX_BUTTON_DEPRESS
N[0x0807F3D8] = function(f, e, ctx)                      -- animation intVariable + facing
  e.field80 = ctx.intVariable + rshift(e.animationState or 4, 1)
end
N[0x0807F3F8] = function(f) f:bubble(f.player, 0) end     -- CreatePlayerExclamationMark
N[0x0807F40C] = function(f) f:bubble(f.player, 1) end     -- CreatePlayerQuestionMark
N[0x0807F420] = function() end                            -- LoadMenu
N[0x0807F434] = function(f, e, ctx, a)                   -- CheckInteractType
  local t = e.interactType or 0
  ctx.intVariable = (t == 1 or t == 2) and t or 0
  if t ~= 0 then e.interactType = 0 end
  keepGoing(a)
end
N[0x0807F464] = function(f, e, ctx, a)                   -- walk to x = intVariable
  if ctx.unk18 == 0 then
    ctx.unk18 = 1
    ctx.postScriptActions = bor(ctx.postScriptActions, 2)
    ctx.tx = ctx.intVariable
    e.animationState = (ctx.tx > e.x) and 2 or 6
  end
  local d = ctx.tx - e.x
  local s = (e.speed or 0x100) / 256
  if math.abs(d) <= s then e.x = ctx.tx else e.x = e.x + (d > 0 and s or -s) stay(a) end
end
N[0x0807F4F8] = function(f, e, ctx, a)                   -- walk to y = intVariable
  if ctx.unk18 == 0 then
    ctx.unk18 = 1
    ctx.postScriptActions = bor(ctx.postScriptActions, 2)
    ctx.ty = ctx.intVariable
    e.animationState = (ctx.ty > e.y) and 4 or 0
  end
  local d = ctx.ty - e.y
  local s = (e.speed or 0x100) / 256
  if math.abs(d) <= s then e.y = ctx.ty else e.y = e.y + (d > 0 and s or -s) stay(a) end
end
N[0x0807F5C0] = function(f, e, ctx, a)                   -- WaitForCameraTouchRoomBorder
  if f.scrolling then stay(a) else keepGoing(a) end
end
N[0x0807F680] = function(f, e, ctx, a)                   -- player x > intVariable
  ctx.condition = f.player.x > band(ctx.intVariable, 0xFFFF) and 1 or 0
  keepGoing(a)
end
N[0x0807F6B4] = function(f, e, ctx, a)                   -- player y > intVariable
  ctx.condition = f.player.y > band(ctx.intVariable, 0xFFFF) and 1 or 0
  keepGoing(a)
end
N[0x0807F6E8] = function(f, e, ctx) f.player.flags = bor(f.player.flags or 0, ctx.intVariable) end -- SetPlayerFlag
N[0x0807F75C] = function(f, e, ctx)                      -- SetPlayerPos (x << 16 | y)
  f.player.x, f.player.y = rshift(ctx.intVariable, 16), band(ctx.intVariable, 0xFFFF)
end
N[0x0807F844] = function(f, e) f.cameraTarget = e end     -- camera on this entity
N[0x0807F92C] = function(f, e) e.talkable = true end      -- MakePedestalInteractable
N[0x0807F9A4] = function(f, e, ctx, a)                   -- WaitForPlayerNormal
  if f.player.state == "normal" and not f:messageActive() then keepGoing(a) else stay(a) end
end
N[0x0807DF28] = function(f) f.menuDisabled = true end     -- DisablePauseMenuAndPutAwayItems
N[0x0807DF50] = function(f)                              -- EnablePauseMenu (+ ResetPlayerAnimationAndAction)
  f.menuDisabled = nil
  f.player.scriptAnim = nil
end
N[0x080791BC] = function(f)                              -- SetPlayerActionNormal
  f.player.state = "normal"
  f.player.scriptAnim = nil
  -- round 10: the player script only runs in PLAYER_SLEEP (StartPlayerScript
  -- queues it); action PLAYER_NORMAL ends it (the Minish Woods look-around
  -- loop, script_PlayerAtFirstLookAtEzlo, is ended this way)
  if f.playerScript then f.playerScript.stopped = true end
end
N[0x080791D0] = N[0x080791BC]                             -- ResetPlayerAnimationAndAction
N[0x080787B4] = function(f, e) e.talkable = true end      -- AddInteractableCheckableObject

-- ---------------------------------------------------------- elsewhere
N[0x0807529C] = function(f) f:bubble(f.player, 1, 8, -32) end -- player "?" (src/player.c)
N[0x08053250] = function(f)                              -- the respawn point = here (gameUtils.c)
  local p = f.player
  f.entry = { area = f.room.area, room = f.room.room, x = p.x, y = p.y, facing = p.animationState }
end
N[0x080536A8] = function(f) f:fade("in", false, 16) end    -- cutscene.c: sub_080A71C4(5, 5, FADE_INSTANT, 16)
N[0x080536B8] = function(f) f:fade("out", false, 256) end  -- ...and SetFade(FADE_IN_OUT | FADE_INSTANT, 256)
N[0x08061FE4] = function(f, e)                           -- townsperson: walking animation
  e.forceAnim = rshift(e.animationState or 4, 1) + 4
  e.field80 = 4
end
N[0x08066E08] = function(f, e) e.field80 = 0x50 end       -- Zelda animations (zelda.c)
N[0x08066E20] = function(f, e) e.field80 = 0x44 end
N[0x08066E38] = function(f, e) e.field80 = 0x48 end
N[0x08066D04] = function() end                            -- find the Zelda follower (not ported)
N[0x08066D14] = function(f, e, ctx) ctx.condition = 0 end -- ...so she is not there to hide behind
for _, a in ipairs({ 0x08060090, 0x08061E70, 0x08062A48, 0x080636F4, 0x080639D0, 0x08064828, 0x08066288,
                     0x080668F0, 0x08067314, 0x08068884, 0x080694B0, 0x0806B60C, 0x0806BCD4, 0x0806BE3C,
                     0x0806C870, 0x0806CD58, 0x0806CE5C, 0x0807F92C }) do
  N[a] = function(f, e) e.talkable = true end              -- <Npc>_MakeInteractable
end
N[0x0807F934] = function(f, e) e.talkable = true end      -- MakeCheckableObjectInteractable
-- kid.c sub_08062788 / sub_080627E8: SPECIAL_TILE_114 (solid) across
-- tiles (11..13, 24..25) and back
N[0x08062788] = function(f)
  for ty = 24, 25 do for tx = 11, 13 do f:dungeon():block(tx, ty, 1, true) end end
end
N[0x080627E8] = function(f)
  for ty = 24, 25 do for tx = 11, 13 do f:dungeon():block(tx, ty, 1, false) end end
end
N[0x08066274] = function() end                            -- Smith_ChangeInteractableHitbox
N[0x080A2124] = function() end                            -- Windcrest_ChangeInteractableHitbox

-- the Field's host entry point
local extLoaded = false
function Native.call(field, fn, e, ctx, active)
  if not extLoaded then -- round 6: modules that register ports
    extLoaded = true
    require("src.zelda.tmc.Crenel")
    require("src.zelda.tmc.ZeldaFollower")
    require("src.zelda.tmc.Drops")    -- round 9: Disable/EnableRandomDrops
    require("src.zelda.tmc.Ceremony") -- round 9: the castle scenes' helpers
    require("src.zelda.tmc.RouteNatives") -- round 10: Minish Woods / Village scenes
    require("src.zelda.tmc.R27A").natives() -- round 27A: overworld story natives (R27A.lua)
    require("src.zelda.tmc.R26").mods() -- round 27b: the dungeon modules register their natives (R27B.lua)
  end
  local port = N[band(fn, 0xFFFFFFFE)]
  if not port then return false end
  port(field, e, ctx, active)
  return true
end

Native.N = N -- round 5: modules register their ports (Crenel.lua)
return Native
