-- Round 10: natives the new-game route's scenes call after the castle
-- (Minish Woods / Ezlo, the Minish Village), ported by address.  The scenes
-- themselves run from the cartridge's scripts (Script.lua).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * entity.c DeleteAllEnemies ($0805EBCC): every enemy entity is deleted.
--   * ezlo.c sub_0806D908: face the player (CalculateDirectionTo -> one of
--     8 animation states); sub_0806D944: flipX = (x <= player x);
--     sub_0806D8A0: the MoveTowardsTarget target beside Link;
--     sub_0806D96C: FX_STEAM_EFC ("angry" puff) 24 px above Ezlo, in front.
--   * npc4E.c sub_0806DC7C / sub_0806DCA0: SPECIAL_TILE_114 (solid) on the
--     bottom layer at each tile of gUnk_081141F4 (read from the ROM at
--     import, manifest.r10.fightTiles) and back (the Octorok fight pen).
--   * script.c sub_0807F5B0: gPlayerState.field_0x27[0] = intVariable.
--   * script.c WaitForPlayerNormalOrTalkEzlo ($0807FA40): waits while Link
--     is in one of the busy frame states (item get, falling, swimming...).
local Native = require("src.zelda.tmc.Native")
local N = Native.N
local bit = require("bit")
local band = bit.band

local R = {}

N[0x0805EBCC] = function(f)
  for _, e in ipairs(f.entities) do
    if e.enemy then e.deleted = true end
  end
end

-- CalculateDirectionTo: 0 = up, clockwise, 32 steps
function R.dir32(x0, y0, x1, y1)
  local a = math.atan2(x1 - x0, -(y1 - y0)) -- 0 up, positive clockwise
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end

N[0x0806D908] = function(f, e)
  local d = R.dir32(e.x, e.y, f.player.x, f.player.y)
  e.angle = d * 8 -- the port keeps direction as an angle 0..255 (Script.lua)
  -- gUnk_08114144[d >> 1]: 0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,0
  local i = math.floor(d / 2)
  local st = (i == 15) and 0 or math.floor((i + 1) / 2)
  e.animationState = band(e.animationState or 0, 0x80) + st
end
N[0x0806D944] = function(f, e) e.flipX = e.x <= f.player.x end
-- ezlo.c sub_0806D8A0: MoveTowardsTarget's target = 16 px to Link's side
-- (the side Ezlo faces: -16 when flipX) and 2 below; angle and the 8-way
-- state from gUnk_08114134[direction >> 4]
N[0x0806D8A0] = function(f, e, ctx)
  local S = require("src.zelda.tmc.Script")
  ctx.unk19 = 8
  ctx.postScriptActions = bit.bor(ctx.postScriptActions or 0, 2)
  ctx.condition = 0
  local tx = f.player.x + (e.flipX and -16 or 16)
  local ty = f.player.y + 2
  ctx.tx, ctx.ty = tx, ty
  local a = S.angleTo(tx - e.x, ty - e.y)
  e.angle = a
  local i = bit.rshift(a, 4)
  local st = (i == 15) and 0 or math.floor((i + 1) / 2)
  e.animationState = band(e.animationState or 0, 0x80) + st
end
N[0x0806D96C] = function(f, e)
  f:addFx(e.x, e.y - 24, 0x0F, 0x42) -- SPECIAL_FX, FX_STEAM_EFC ($42)
  local fx = f.entities[#f.entities]
  if fx and fx.fx then fx.spritePriority = 1 end
end

local function fightTiles(f)
  local r10 = f.assets.manifest.r10
  return r10 and r10.fightTiles or {}
end
N[0x0806DC7C] = function(f)
  for _, pos in ipairs(fightTiles(f)) do f:dungeon():block(pos % 64, math.floor(pos / 64), 1, true) end
end
N[0x0806DCA0] = function(f)
  for _, pos in ipairs(fightTiles(f)) do f:dungeon():block(pos % 64, math.floor(pos / 64), 1, false) end
end

N[0x0807F5B0] = function(f, e, ctx) f.player.field27 = ctx.intVariable end
-- ezlo.c sub_0806D9A4: Link faces Ezlo, animation state 4
N[0x0806D9A4] = function(f, e)
  f.player.entFlip = not (e.x <= f.player.x)
  f.player.animationState = 4
end
-- script.c ResetPlayerFlag ($0807F6F8): flags &= ~intVariable; PL_NO_CAP ($8)
-- cleared = Link wears Ezlo from now on
N[0x0807F6F8] = function(f, e, ctx)
  local v = ctx.intVariable or 0
  f.player.flags = band(f.player.flags or 0, bit.bnot(v))
  if band(v, 0x8) ~= 0 then f.player.hasCap = true end
end

local BUSY = { itemget = true, dead = true, fall = true, swim = true, jump = true, portal = true,
               climb = true, stairs = true, drown = true, hole = true, thrown = true }
N[0x0807FA40] = function(f, e, ctx, a)
  if BUSY[f.player.state or "normal"] then a.commandSize = 0 else a.flags = bit.bor(a.flags, 1) end
end

-- forestMinish.c sub_08060158 / sub_0806014C: every 3rd frame the Minish
-- looks toward Link when he is within 32x32 (GetFacingDirectionInRectRadius),
-- else back to its own facing (its animIndex, index = state * 4).
-- Round 11: the head / body frame comes from gUnk_08109C98 (read from the
-- ROM, manifest.r11.minishLook): entry [(animationState / 2) * 16 +
-- (index >> 1)] = {frame, frameIndex}; frameIndex bit 7 turns the body
-- (animationState = GetAnimationStateForDirection8(index)). The entity's
-- frame bytes are set directly (frameSpriteSettings 1, frameDuration $F0),
-- so its animation stands still until a script sets one again.
local function minishLook(f, e)
  if (e.r10lookT or 0) > 0 then e.r10lookT = e.r10lookT - 1 return end
  e.r10lookT = 2
  e.r10ownState = e.r10ownState or e.animationState or 4
  local p = f.player
  local index
  if math.abs(p.x - e.x) <= 0x20 and math.abs(p.y - e.y) <= 0x20 then
    index = R.dir32(e.x, e.y, p.x, p.y)
  else
    e.animationState = e.r10ownState
    index = e.r10ownState * 4
  end
  local r11 = f.assets.manifest.r11
  local tab = r11 and r11.minishLook
  local ent = tab and tab[math.floor((e.animationState or 4) / 2) * 16 + bit.rshift(index, 1)]
  if not ent then
    e.animationState = band(math.floor((index + 2) / 4), 7)
    return
  end
  local fr, fi = ent[1], ent[2]
  if band(fi, 0x80) ~= 0 then e.animationState = band(math.floor((index + 2) / 4), 7) end
  e.lookFrame = { frame = fr, frameIndex = band(fi, 0x7F) }
end
N[0x08060158] = minishLook
N[0x0806014C] = function(f, e) e.r10lookT = 0; minishLook(f, e) end

-- NPCs with no script in their EntityData whose init starts one from a
-- table by type2 (forestMinish.c ForestMinish action 0: animationState =
-- timer << 1, StartCutscene(gUnk_08109D18[type2])); called from Field:spawn
function R.npcSpawn(f, e, d)
  if e.script or d.kind ~= 7 then return end
  local r10 = f.assets.manifest.r10
  local tab = r10 and r10.npcScriptTables and r10.npcScriptTables[d.id]
  if not tab then return end
  local type2 = band(d.paramB or 0, 0xFF)
  local addr = tab[type2]
  if not addr or addr == 0 or not (f.mem and f.mem:valid(addr)) then return end
  e.script = require("src.zelda.tmc.Script").new(f.mem, addr)
  e.animationState = band(bit.rshift(d.paramB or 0, 8), 0xFF) * 2
end

return R
