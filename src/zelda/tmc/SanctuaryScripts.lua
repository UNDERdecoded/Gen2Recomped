-- Round 27 (team B): the Sanctuary ($78 Hall / Main / StainedGlass) -- the C
-- side of its cartridge scripts (data/scripts/sanctuary/*.inc): the sword
-- charging at the pedestal, the text board, the stained-glass light objects
-- and the Ezlo hint manager.  The scripts run from the ROM (Script.lua); the
-- entity bodies use VaatiScripts' body table (VaatiScripts.MISC for
-- CUTSCENE_MISC_OBJECT types).  R27B.lua dispatches here.
--
-- CUTSCENE_MISC_OBJECT $6A (src/object/cutsceneMiscObject.c):
--   type $16 (Type22: the sword in the pedestal, sub_08095A1C: room origin +
--     (232, 312), z -4, layer 2, StartCutscene(intVariable)), types $1C /
--     $1D (Type28: sub_08095D54 the floating element at Link, layer 2;
--     sub_08095D8C the sword-charge sparks at the caller): not drawn until
--     the script shows them, PRIO_PLAYER_EVENT, the script, the animation,
--     and a keyframe's frame byte (& ~$80) != 0 -> ChangeObjPalette(
--     gUnk_08122B00[byte] & ~$80) (sub_08095D30).
--   type $17 (Type23, the text board): frameIndex 0, the script; action 2 ->
--     120 frames blinking then drawn, action 4 -> 120 blinking then hidden.
--   type $1E (Type30, sub_08095E7C with a script / sub_08095EAC sparkles):
--     sync flag $10 deletes it; type2 != 0: animation 75, GravityUpdate with
--     its speed, gone off screen; sync $20000 -> zVelocity 4.0, speed 192.
--   type $1F (Type31, sub_08096028: the new sword's glow while Link holds it
--     up): type2 3 / 4 / 6 by local flags $7A / $7B of bank 3 (palette 0 /
--     1 / 4); Link's animation $8BF (frame bit 0 clear) or $8E3; its frame =
--     Link's frameIndex - 52 - 75 (or - 85 - 42); Link's frame bit $10 ->
--     SFX $1D4; gone when Link's animation changes.
-- NPC4E_ChangeInteractableHitbox ($0806DA04, npc4E.c): the interact box
--   gNpc4ECollisionData[intVariable] (x, y, w, h, the blocked-facing mask).
-- sub_080962F8: SetInteractableObjectCollision from gUnk_08122B3C[n].
-- SetSpriteOffset ($0807F994): spriteOffsetX / Y = intVariable >> 16 / & $FFFF.
-- MINISH_VILLAGE_OBJECT $3E (src/object/minishVillageObject.c), in the
--   Sanctuary / DHC areas (VaatiScripts.AREAS) only, types 1 / 2 /
--   9 (frame 0, priority 7, SPECIAL_TILE_105 on the tile above, the palette
--   cycle gUnk_08121704 every 8 frames, type 9 every 2), 6 (priority 7, the
--   palette cycle gUnk_08121720 every 2 frames), 7 (frameIndex type2, BG
--   priority 3, priority 7, alpha), 8 (frameIndex type2, priority 7; type2 0
--   before local $7C: the alpha fade-in (SFX_179) then SPECIAL_TILE_105, else
--   SPECIAL_TILE_105 at once (type2 != 0: the tile above); the palette cycle
--   gUnk_08121738 every 8 frames).
-- MISC_MANAGER $0F type $E (miscManager.c MiscManager_TypeE): with the Four
--   Sword and LV6SOTO_01_CAP_0 (bank 10 $85) clear, SetNextAreaHint(TEXT_EZLO
--   $0F); gone once the flag is set.
--
-- SIMPLIFIED: the BG blends (layerFXControl / alphaBlend) of the stained-glass
--   objects are an alpha on the sprite; type 7's affine scale is not drawn;
--   Type31's sub_080042D0 draws the frame of its own sprite (no OAM sub-entry
--   offsets); CreateRepeatedSoundManager is Ceremony.lua's no-op.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = {}

M.ROM_RANGES = {
  miscPalettes = { 0x08122B00, 0x08122B0E }, -- gUnk_08122B00 (cutsceneMiscObject.c extern u16[]): palettes by frame byte
  miscInteract = { 0x08122B3C, 0x08122B49 }, -- gUnk_08122B3C[0] (HitboxCfg: Hitbox, u8[4], u8 dirs)
  sparkSpeeds = { 0x08122B0E, 0x08122B1E },  -- gUnk_08122B0E (s16[8]): sub_08095EAC's sparkle speeds
}

local V = require("src.zelda.tmc.VaatiScripts")
local N = require("src.zelda.tmc.Native").N
local anim, step, newKey = V.anim, V.step, V.newKey

local SPECIAL_TILE_105 = 0x4069
local SFX_179, SFX_1D4 = 0x179, 0x1D4

-- constants written out in the decomp's .c
M.NPC4E_COLLISION = { -- npc4E.c gNpc4ECollisionData {x, y, w, h, blocked facings}
  [0] = { 0, 0, 8, 8, 0x0E }, { 0, 0, 26, 8, 0x0E }, { 0, 0, 16, 4, 0x0E }, { 0, 0, 10, 10, 0 }, { 0, 0, 10, 10, 0 },
  { 0, 0, 6, 4, 0x0E }, { 0, 8, 16, 4, 0x0E }, { 0, -8, 24, 8, 0x0E }, { 0, 0, 88, 8, 0x0E },
}
M.PAL_TYPE1 = { 0x12d, 0x12e, 0x12f, 0x130, 0x131, 0x132, 0x133, 0x132, 0x131, 0x130, 0x12f, 0x12e, 0x12d } -- gUnk_08121704
M.PAL_TYPE6 = { 0x149, 0x14a, 0x14b, 0x14a }                                                             -- gUnk_08121720
M.PAL_TYPE8 = { 0x14c, 0x14d, 0x14e, 0x14f, 0x150, 0x151, 0x150, 0x14f, 0x14e, 0x14d, 0x14c }           -- gUnk_08121738

local function sound(f, s) if f.sound then f:sound(s) end end
local function pal(f, e, p) e.palette = f.assets:objPalette(p) end

-- ---------------------------------------------------------------- natives
local function startScript(f, e, addr)
  if f.mem and f.mem:valid(addr) then e.script = require("src.zelda.tmc.Script").new(f.mem, addr) end
end
-- CreateObject(CUTSCENE_MISC_OBJECT, type, type2) + StartCutscene
function M.miscObject(f, typ, type2, x, y, script)
  local e = f:spawn({ kind = 6, id = 0x6A, paramA = typ, paramB = type2 or 0, x = math.floor(x), y = math.floor(y),
                      pool = script and 0x4F or 0x0F, paramC = script or 0 })
  if not e then return nil end
  if script and not e.script then startScript(f, e, script) end
  if not e.anim then e.anim = require("src.zelda.tmc.Anim").new() end
  if e.sprite == nil then V.dressMisc(f, e, typ) end
  -- Field lists an object only when it has a sprite or a script
  local listed = false
  for i = #f.entities, math.max(1, #f.entities - 2), -1 do if f.entities[i] == e then listed = true break end end
  if not listed then f.entities[#f.entities + 1] = e end
  return e
end
N[0x08095A1C] = N[0x08095A1C] or function(f, e, ctx) -- the sword in the pedestal
  local o = M.miscObject(f, 0x16, 0, 232, 312, ctx.intVariable)
  if o then o.z = 4; o.layer = 2 end
end
N[0x08095D54] = N[0x08095D54] or function(f, e, ctx) -- an element floating up from Link
  local p = f.player
  local o = M.miscObject(f, 0x1C, 0, p.x, p.y, ctx.intVariable)
  if o then o.layer = 2 end
end
N[0x08095D8C] = N[0x08095D8C] or function(f, e, ctx) -- a sword-charge part at the caller
  M.miscObject(f, 0x1D, 0, e.x, e.y, ctx.intVariable)
end
N[0x08095E7C] = N[0x08095E7C] or function(f, e, ctx)
  M.miscObject(f, 0x1E, 0, e.x, e.y, ctx.intVariable)
end
N[0x08095EAC] = N[0x08095EAC] or function(f, e, ctx)
  local a, b, vel, speed
  if (ctx.intVariable or 0) == 0 then a, b, vel, speed = 0x10, 0x1F, 0.25, 0
  else
    local T = require("src.zelda.tmc.ExtractR26").tables(f, "sparkSpeeds")
    a, b, vel, speed = 8, 0xF, 4, T and T.s16(0x08122B0E + 2 * math.random(0, 7)) or 0
  end
  local x, y = a - band(math.random(0, 0xFFFF), b), a - band(math.random(0, 0xFFFF), b)
  local o = M.miscObject(f, 0x1E, 1, e.x + x, e.y + y)
  if o then
    o.czv, o.speed = vel, speed
    if (ctx.intVariable or 0) ~= 0 then o.type2 = 0xFF end
  end
end
N[0x08096028] = N[0x08096028] or function(f) -- the new sword's glow
  local t2 = 6
  if not f:flag("bank", 123, 0x300) then t2 = 4 end
  if not f:flag("bank", 122, 0x300) then t2 = 3 end
  M.miscObject(f, 0x1F, t2, f.player.x, f.player.y)
end
N[0x080962F8] = N[0x080962F8] or function(f, e, ctx)
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "miscInteract")
  local n = ctx.intVariable or 0
  if T and n == 0 then
    local a = 0x08122B3C
    e.interactBox = { x = T.s8(a + 8), y = T.s8(a + 9), w = T.u8(a + 10), h = T.u8(a + 11), dirs = T.u8(a + 12) }
  end
  e.talkable = true
end
N[0x0806DA04] = N[0x0806DA04] or function(f, e, ctx) -- NPC4E_ChangeInteractableHitbox
  local c = M.NPC4E_COLLISION[ctx.intVariable or 0]
  if c then e.interactBox = { x = c[1], y = c[2], w = c[3], h = c[4], dirs = c[5] } end
end
-- UpdatePlayerSkills (playerUtils.c): gPlayerState.skills from the
-- inventory; here every skill test reads the inventory itself (SwordSkills)
N[0x0807AEE4] = N[0x0807AEE4] or function() end
N[0x0807F994] = N[0x0807F994] or function(f, e, ctx) -- SetSpriteOffset
  local v = ctx.intVariable or 0
  local sx, sy = band(rshift(v, 16), 0xFF), band(v, 0xFF)
  e.spriteOX = sx >= 0x80 and sx - 0x100 or sx
  e.spriteOY = sy >= 0x80 and sy - 0x100 or sy
end

-- ---------------------------------------------------------------- $6A bodies
local function miscPalette(f, e)
  if not newKey(e) then return end
  local b = band(e.anim.flags or 0, 0x7F)
  if b == 0 then return end
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "miscPalettes")
  if T and b < 7 then pal(f, e, band(T.u16(0x08122B00 + 2 * b), bit.bnot(0x80))) end
end
local hiddenScripted = {
  init = function(f, e) e.hidden = true; e.prioB1 = 3 end,
  tick = function(f, e) miscPalette(f, e); V.e82(f, e) end,
}
V.MISC[0x16] = hiddenScripted
V.MISC[0x1C] = hiddenScripted
V.MISC[0x1D] = hiddenScripted
V.MISC[0x17] = { -- Type23, the text board
  init = function(f, e) e.action = 1; e.staticFrame = 0 end,
  tick = function(f, e)
    local a = e.action or 1
    if a == 2 then e.action, e.timer = 3, 120 end
    if a == 4 then e.action, e.timer = 5, 120 end
    a = e.action
    if a == 3 or a == 5 then
      e.hidden = not e.hidden
      e.timer = e.timer - 1
      if e.timer == 0 then e.action, e.hidden = 1, (a == 5) end
    end
    V.e82(f, e)
  end,
}
V.MISC[0x1E] = { -- Type30
  init = function(f, e)
    if (e.type2 or 0) ~= 0 then
      e.hidden = false
      anim(f, e, 75)
      e.cz, e.czv = e.cz or 0, e.czv or 0
      e.overLink = true
    end
  end,
  tick = function(f, e)
    local S = require("src.zelda.tmc.Script")
    if band(S.active.syncFlags, 0x10) ~= 0 then e.deleted = true return end
    if (e.type2 or 0) == 0 then return end
    if band(e.type2, 0x80) == 0 and band(S.active.syncFlags, 0x20000) ~= 0 then
      e.type2, e.czv, e.speed = 0xFF, 4, 192
    end
    -- GravityUpdate(speed): z up by zVelocity, gravity speed / 256 (Q8.8 of Q16.16)
    e.cz = (e.cz or 0) + (e.czv or 0)
    e.czv = (e.czv or 0) - (e.speed or 0) / 256
    if e.cz < 0 then e.cz = 0 end
    e.z = e.cz
    step(e)
    local sy = e.y - (f.camY or 0) - e.z
    if sy < -16 or sy > 176 then e.deleted = true end
  end,
}
V.MISC[0x1F] = { -- Type31, the glow on the new sword
  init = function(f, e)
    local p = f.player
    local pl = ({ [3] = 0, [4] = 1, [6] = 4 })[e.type2 or 3] or 0
    pal(f, e, pl)
    if band(p.anim and p.anim.flags or 0, 1) == 0 then e.want, e.timer, e.subtimer = 0x8BF, 52, -75
    else e.want, e.timer, e.subtimer = 0x8E3, 85, -42 end
    e.x, e.y = p.x, p.y
    e.spritePriority = 3
    e.frameNo = nil
    e.drawGhost = V.drawStatic
  end,
  tick = function(f, e)
    local p = f.player
    if p.anim and band(p.anim.flags or 0, 0x10) ~= 0 and e._pk ~= p.anim.key then e._pk = p.anim.key; sound(f, SFX_1D4) end
    if p.animId ~= e.want then e.deleted = true return end
    e.frameNo = band((p.anim.frame or 0) - e.timer + e.subtimer, 0xFF)
    e.x, e.y = p.x, p.y
  end,
}

-- ---------------------------------------------------------------- $3E objects
local function setTile105(f, e, pos)
  local tl = require("src.zelda.tmc.DHCObjects")._tile
  tl.set(f, e.layer or 1, pos, SPECIAL_TILE_105)
end
local function cycle(f, e, list, every)
  e.timer = (e.timer or every) - 1
  if e.timer <= 0 then
    e.timer = every
    e.sub = (e.sub or 0) % #list + 1
    pal(f, e, list[e.sub])
  end
end
local function drawAlpha(e, f, camX, camY)
  if not (love and love.graphics) then return end
  local g = love.graphics
  local a = e.alpha or 1
  if a <= 0 then return end
  g.setColor(1, 1, 1, a)
  e.frameNo = e.staticFrame or 0
  V.drawStatic(e, f, camX, camY)
  g.setColor(1, 1, 1, 1)
end
M.MVO = 0x3E
function M.spawnObject(d, e)
  if e.id ~= M.MVO then return nil end
  local t = e.form or 0
  if not (t == 1 or t == 2 or t == 6 or t == 7 or t == 8 or t == 9) then return nil end
  local f = d.field
  if not (f.room and V.AREAS[f.room.area]) then return nil end -- the Sanctuary / DHC ones (Minish Village's stay ObjStatic's)
  local O = f:objects()
  local def = O:def(M.MVO, t)
  if def then O:dress(e, def, 0) end
  e.spritePriority = 7
  local pos = math.floor(e.x / 16) + math.floor(e.y / 16) * 64
  if t == 1 or t == 2 or t == 9 then
    e.staticFrame = 0
    e.action = 1
    setTile105(f, e, pos - 0x40)
    e.timer = 8
  elseif t == 6 then
    e.staticFrame = e.staticFrame or 0
    e.timer = 8
  elseif t == 7 then
    e.oamPrio = 3
    e.staticFrame = e.type2 or 0
    e.alpha = 0.5
    e.drawGhost = drawAlpha
  elseif t == 8 then
    e.staticFrame = e.type2 or 0
    e.action = 2
    if (e.type2 or 0) == 0 and not f:flag("local", 0x7C) then
      e.action, e.timer = 1, 0
      e.alpha = 0
      e.drawGhost = drawAlpha
      sound(f, SFX_179)
    else
      e.timer = 8
      setTile105(f, e, (e.type2 or 0) ~= 0 and pos - 0x40 or pos)
    end
  end
  e.extUpdate = function(dd, me) M.mvoUpdate(dd.field, me) end
  d:track(e)
  return e
end
function M.mvoUpdate(f, e)
  local t = e.form
  if t == 1 or t == 2 or t == 9 then
    if e.action == 2 and (f.frame or 0) % 4 == 0 then -- sub_0808D280's fade
      e.sa = (e.sa or 0) + 1
      e.alpha = math.max(0, 1 - e.sa / 16)
      e.drawGhost = drawAlpha
      if e.sa >= 16 then e.deleted = true return end
    end
    cycle(f, e, M.PAL_TYPE1, t == 9 and 2 or 8)
  elseif t == 6 then
    cycle(f, e, M.PAL_TYPE6, 2)
  elseif t == 8 then
    if e.action == 1 then
      if (f.frame or 0) % 4 == 0 then
        e.timer = e.timer + 1
        e.alpha = math.min(1, e.timer / 16)
        if e.timer >= 16 then
          e.action, e.timer, e.alpha, e.drawGhost = 2, 8, nil, nil
          setTile105(f, e, math.floor(e.x / 16) + math.floor(e.y / 16) * 64)
        end
      end
    else
      cycle(f, e, M.PAL_TYPE8, 8)
    end
  end
end

-- ---------------------------------------------------------------- MISC_MANAGER type $E
function M.spawnManager(d, m)
  if m.id ~= 0x0F or m.type ~= 0x0E then return nil end
  require("src.zelda.tmc.R26").ticker(d, function(dd, t)
    local f = dd.field
    if t.done then return end
    local fs = f:inventory(6)
    local has = fs == true or (type(fs) == "number" and fs >= 1)
    local cap = f:flag("bank", 0x85, 0x8C0) -- LV6SOTO_01_CAP_0
    if t.action == 0 then t.action = 1 end
    if t.action == 1 then
      if not has or cap then return end
      t.action = 2
      f.areaHint = 0x0B0F -- SetNextAreaHint(TEXT_INDEX(TEXT_EZLO, $0F))
    elseif cap then
      f.areaHint = nil -- sub_0801855C
      t.done = true
    end
  end, { action = 0 })
  return true
end

return M
