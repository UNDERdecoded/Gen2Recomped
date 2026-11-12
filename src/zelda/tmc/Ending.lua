-- Round 28: the ending after Vaati's last fight (data/scripts/cutscene/outro/
-- *.inc run from the ROM by Script.lua) -- the C side of those scripts, the
-- outro rooms' entity lists and the Npc4E transitions; the credits roll is
-- Staffroll.lua (started by sub_0807FB94).  R27B.lua dispatches here.
--
-- Rooms (src/roomInit.c, global ENDING $51): sub_unk3_HyruleCastle_0 / _1,
--   sub_unk3_MinishWoods_Main, sub_unk3_SanctuaryEntrance_Main,
--   sub_unk3_MtCrenel_MountainTop put the ending's list in place of the
--   room's list 0 and drop list 2 (gRoomVars.properties[0] / [2]):
--   $80:00 gUnk_080D7348, $80:01 gUnk_080D7410, $00:00 gUnk_080F4EB0,
--   $81:00 gUnk_080F5348 (+ sub_0804ED18: the BGM carries on), $06:00
--   gUnk_080FAD48.  ($80:02, $88:00, $88:1F and the garden $89:01 are done
--   by RoomCode / DHCObjects / BossVaati3.)
-- NPC4E_DoScreenTransition (npc4E.c gNpc4ETransitions / gNpc4ETransitionTypes,
--   src/data/screenTransitions.c): indices 7-15, the outro's chain garden ->
--   DHC throne -> castle throne -> DHC entrance -> castle entrance -> castle
--   hall (the staff unfrozen) -> Minish Woods -> Mt Crenel -> garden ->
--   Sanctuary entrance; TRANSITION_FADE_WHITE_SLOW ones fade to white.
-- Natives:
--   sub_080960C4 (cutsceneMiscObject.c): CUTSCENE_MISC_OBJECT $23 / $24
--     (type2 $49 / $4A) on the caller, both running intVariable's script, $24
--     on layer 2 sorted above; Type35: InitializeAnimation(type2), the
--     script, its position copied from the parent each frame.
--   sub_08094B0C / sub_08094B3C: the cap's height up to -32 by 1, down to
--     -13 by 0.5 (the command repeats until there).
--   sub_080961B0: eight $25 sparkles, direction 32 * i, speed (Random() &
--     $1F0) + gUnk_08122B1E[i]; Type37: animation 75, LinearMoveAngle, gone
--     off screen.
--   sub_08066E68 (zelda.c): animation $54.
--   sub_0807FADC (script.c) -> sub_0808C650 (bossDoor.c): a
--     WHITE_TRIANGLE_EFFECT (whiteTriangleEffect.c) on the caller; the
--     command waits until it is gone.  Type 0: gUnk_081215E8[type2] -- the
--     window triangle (sub_0801E49C: corners at angle -$40, +$68, -$E8,
--     radius r) grows by its speed, turns by its spin, gone past radius 500
--     (or below 0) with layerFXControl 0; type 1 (made by type 0): the
--     brightness $100 down by unk_6a a frame, white for type2 & 2.
--   sub_08094B94: CUTSCENE_MISC_OBJECT $22 at Link, z -48, running
--     script_CutsceneMiscObjectTheLittleHat ($0800AEDC, the script after
--     script_ZeldaGoodbye in data/scripts.s, matched to its ROM bytes), Ezlo's
--     animation type2 (the C's trailing ExecuteScriptForEntity / GetNextFrame
--     of the caller is the caller's own update, not repeated here).  sub_08094BE0: that hat at Link, z -12, y + 1,
--     layer 2, animation 1.  Type1 ($22): layer 2, animation 0, the script.
--   sub_0806305C (minishEzlo.c): priority 0, animation $10, SFX_PLY_SHRINKING.
--   sub_0808D2CC (minishVillageObject.c): MINISH_VILLAGE_OBJECT type 1 ->
--     type 9 (SanctuaryScripts runs type 9), priority 2.
--   sub_0808D280: that type 9 fades out (action 2), SFX_EVAPORATE.
--   CreateDeathFx ($080A29BC, objectUtils.c): FX_DEATH on the caller.
--   sub_0807F844 (wrapped): the camera target, then sub_080809D4's snap.
--   sub_0807FB94: SetTask(TASK_STAFFROLL) -> Staffroll.lua.
--   CUTSCENE_MISC_OBJECT type 5 type2 2 (the DHC rubble of the outro
--     lists): animation 0 / 2 by its timer (paramB's high byte), timers 2
--     and 3 mirrored.
--
-- SIMPLIFIED: the triangle window is drawn as a filled white (or black)
--   triangle at the brightness's alpha, over the HUD; sub_080630A4's affine
--   shrink of Ezlo (SetAffineInfo) is not drawn (the engine has no affine
--   NPC sprites) -- only its position steps are kept; the spriteRendering.b3
--   layer maps (gUnk_08114F30 / F34) are not modelled.
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = {}

M.ROM_RANGES = {
  outroSparks = { 0x08122B1E, 0x08122B2E }, -- gUnk_08122B1E (u16[8]): sub_080961B0's sparkle speeds
  staffEN = { 0x08127644, 0x08127998 },     -- gUnk_08127644 (StaffrollEntry[71], 12 bytes): the English credits
  staffGfx = { 0x08127CEC, 0x08127D00 },    -- gUnk_08127CEC (StaffrollGfxEntry[10]): palette / gfx group per picture
}

local V = require("src.zelda.tmc.VaatiScripts")
local S = require("src.zelda.tmc.SanctuaryScripts")
local N = require("src.zelda.tmc.Native").N
local anim = V.anim

local ENDING, GAMECLEAR = 0x51, 0x55
local SFX = { EVAPORATE = 0xF6, APPARATE = 0xF7, PLY_SHRINKING = 0x16F }
M.SFX = SFX
M.GAMECLEAR = GAMECLEAR

local function stay(a) if a then a.commandSize = 0 end end
local function sound(f, s) if f.sound then f:sound(s) end end

-- gSineTable (256 steps a turn, $100 = 1)
local SIN = {}
for i = 0, 255 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
M.SIN = SIN
local function sin(a) return SIN[band(a, 0xFF)] end
local function cos(a) return SIN[band(a + 0x40, 0xFF)] end

-- ---------------------------------------------------------------- rooms
-- sub_unk3_*: the ending's list replaces the room's list 0; list 2 dropped
M.ROOM_LISTS = {
  [0x8000] = 0x080D7348, -- HyruleCastle_0: script_Npc4EHyruleCastleEntrance
  [0x8001] = 0x080D7410, -- HyruleCastle_1: script_Npc4EUnfreezeCastleStaff, the guards / maids in stone
  [0x0000] = 0x080F4EB0, -- MinishWoods_Main: script_Npc4EMinishWoods, four Octoroks
  [0x8100] = 0x080F5348, -- SanctuaryEntrance_Main: script_Npc4EFixedEverything, Ezlo, Zelda
  [0x0600] = 0x080FAD48, -- MtCrenel_MountainTop: script_Npc4EMtCrenel, four Tektites
}
local function dropList(f, list)
  local ok, D = pcall(require, "src.zelda.tmc.DHCObjects")
  if ok and D.dropList then return D.dropList(f, list) end
  if not list then return end
  for _, dat in ipairs(list) do
    for _, e in ipairs(f.entities) do if e.data == dat then e.deleted = true end end
  end
end
function M.roomInit(f)
  local r = f.room
  if not r or not f:flag("global", ENDING) then return end
  local key = (r.area or 0) * 256 + (r.room or 0)
  local list = M.ROOM_LISTS[key]
  if not list then return end
  local lists = r.entities or {}
  dropList(f, lists[0]); dropList(f, lists[2])
  f:loadEntityList(list)
  if key == 0x8100 then f.queuedBgm = nil end -- sub_0804ED18: gArea.queued_bgm = gArea.bgm
end

-- ---------------------------------------------------------------- transitions
-- gNpc4ETransitions[7..15] (endX / endY 0 = the room's origin, as the ROM has)
local WHITE, BLACK = "white", "black"
M.TRANSITIONS = {
  [7] = { warpType = 1, area = 0x88, room = 0x1F, endX = 0, endY = 0, facing = 4, kind = 0, layer = 1, fade = WHITE },   -- gUnk_0813AC70
  [8] = { warpType = 1, area = 0x80, room = 0x02, endX = 0, endY = 0, facing = 4, kind = 0, layer = 1, fade = WHITE },   -- gUnk_0813AC84
  [9] = { warpType = 1, area = 0x88, room = 0x00, endX = 0, endY = 0, facing = 4, kind = 0, layer = 1, fade = BLACK },   -- gUnk_0813AC98
  [10] = { warpType = 1, area = 0x80, room = 0x00, endX = 0, endY = 0, facing = 4, kind = 0, layer = 1, fade = WHITE },  -- gUnk_0813ACAC
  [11] = { warpType = 1, area = 0x80, room = 0x01, endX = 0, endY = 0, facing = 4, kind = 0, layer = 1, fade = BLACK },  -- gUnk_0813ACC0
  [12] = { warpType = 1, area = 0x00, room = 0x00, endX = 0, endY = 0, facing = 4, kind = 0, layer = 1, fade = BLACK },  -- gUnk_0813ACD4
  [13] = { warpType = 1, area = 0x06, room = 0x00, endX = 0, endY = 0, facing = 4, kind = 0, layer = 1, fade = BLACK },  -- gUnk_0813ACE8
  [14] = { warpType = 1, area = 0x89, room = 0x01, endX = 0xA8, endY = 0x88, facing = 6, kind = 0, layer = 1, fade = BLACK }, -- gUnk_0813AC5C
  [15] = { warpType = 1, area = 0x81, room = 0x00, endX = 0xA8, endY = 0x88, facing = 6, kind = 0, layer = 1, fade = WHITE }, -- gUnk_0813ACFC
}
do
  local ok, V3 = pcall(require, "src.zelda.tmc.BossVaati3")
  if ok and type(V3) == "table" and V3.NPC4E_TRANSITIONS then
    for i, t in pairs(M.TRANSITIONS) do V3.NPC4E_TRANSITIONS[i] = V3.NPC4E_TRANSITIONS[i] or t end
  end
  -- the white fade of TRANSITION_FADE_WHITE_SLOW: set before the transition starts
  local prev = N[0x0806DA1C]
  N[0x0806DA1C] = function(f, e, ctx, a)
    local t = M.TRANSITIONS[ctx.intVariable or -1]
    if t then f.fadeWhite = (t.fade == WHITE); f.r28white = true end
    if prev then return prev(f, e, ctx, a) end
    if t then f:startTransition(t) end
  end
end

-- sub_0807F844 (script.c): camera_target = the entity, then sub_080809D4
-- (scroll.c) puts the scroll on it at once (clamped to the room); Native.lua
-- only sets the target, so the camera crawled to an Npc4E 0x378 px away
do
  local prev = N[0x0807F844]
  if prev and not M._camWrapped then
    M._camWrapped = true
    N[0x0807F844] = function(f, e, ctx, a)
      prev(f, e, ctx, a)
      M.snapCamera(f, e)
    end
  end
end
function M.snapCamera(f, t)
  local r = f.room
  if not (r and t and r.width and r.height) then return end
  local W, H = 240, 160
  local cx = math.max(0, math.min(t.x - W / 2, r.width - W))
  local cy = math.max(0, math.min(t.y - H / 2, r.height - H))
  if r.width < W then cx = (r.width - W) / 2 end
  if r.height < H then cy = (r.height - H) / 2 end
  f.camX, f.camY, f.scrolling = math.floor(cx), math.floor(cy), false
end

-- ---------------------------------------------------------------- misc objects
local function newMisc(f, typ, type2, x, y, script)
  return S.miscObject(f, typ, type2, x, y, script)
end
M.newMisc = newMisc

-- Type35 ($23 / $24): InitializeAnimation(type2), the parent's position
local type35 = {
  init = function(f, e) anim(f, e, e.type2 or e.param or 0) end,
  tick = function(f, e)
    local p = e.parent
    if p and not p.deleted then e.x, e.y, e.z = p.x, p.y, p.z end
  end,
}
V.MISC[0x23] = V.MISC[0x23] or type35
V.MISC[0x24] = V.MISC[0x24] or type35
-- Type37 ($25): drawn, animation 75, LinearMoveAngle, gone off screen
V.MISC[0x25] = V.MISC[0x25] or {
  init = function(f, e) e.hidden = false; anim(f, e, 75) end,
  tick = function(f, e)
    local s, d = e.speed or 0, e.direction or 0
    e.x = e.x + s * sin(d) / 65536
    e.y = e.y - s * cos(d) / 65536
    local x, y = math.floor(e.x) - (f.camX or 0) + 0x3F, math.floor(e.y) - math.floor(e.z or 0) - (f.camY or 0) + 0x3F
    if not (x >= 0 and x < 0x16E and y >= 0 and y < 0x11E) then e.deleted = true end
  end,
}
-- Type1 ($22, the little hat): layer 2, animation 0, the script
V.MISC[0x22] = V.MISC[0x22] or {
  init = function(f, e) e.layer = 2; if not e.r28anim then anim(f, e, 0) end end,
}
-- Type5 type2 2: the rubble of the outro lists (timer = paramB >> 8)
do
  local base = V.MISC[5]
  if base and not base.r28 then
    local tick = base.tick
    V.MISC[5] = { r28 = true, init = base.init, tick = function(f, e)
      local t2 = band(e.param or e.type2 or 0, 0xFF)
      if e.type2 == nil and e.param then e.type2 = t2 end
      if t2 == 2 then
        if not e.r28act then
          e.r28act = true
          local timer = band(rshift(e.param or 0, 8), 0xFF)
          if timer == 1 then anim(f, e, 2)
          elseif timer == 2 then e.flipX = true; anim(f, e, 0)
          elseif timer == 0 then anim(f, e, 0)
          elseif timer == 3 then e.flipX = true; anim(f, e, 2) end
        end
        return
      end
      if tick then return tick(f, e) end
    end }
  end
end

N[0x080960C4] = N[0x080960C4] or function(f, e, ctx) -- sub_080960C4
  local a = newMisc(f, 0x23, 0x49, e.x, e.y, ctx.intVariable)
  if a then a.parent, a.type2, a.z = e, 0x49, e.z; a.underOf = e end
  local b = newMisc(f, 0x24, 0x4A, e.x, e.y, ctx.intVariable)
  if b then b.parent, b.type2, b.z, b.layer = e, 0x4A, e.z, 2; b.overLink = true end
end
N[0x08094B0C] = N[0x08094B0C] or function(f, e, ctx, a) -- z up to -32
  local cz = math.floor(-(e.z or 0)) - 1
  if cz <= -32 then cz = -32 else stay(a) end
  e.z = -cz
end
N[0x08094B3C] = N[0x08094B3C] or function(f, e, ctx, a) -- z down to -13
  local cz = -(e.z or 0) + 0.5
  if math.floor(cz) >= -13 then cz = -13 else stay(a) end
  e.z = -cz
end
N[0x080961B0] = N[0x080961B0] or function(f, e) -- eight sparkles
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "outroSparks")
  for i = 0, 7 do
    local o = newMisc(f, 0x25, 0, e.x, e.y)
    if o then
      o.direction = 32 * i
      o.speed = band(math.random(0, 0xFFFF), 0x1F0) + (T and T.u16(0x08122B1E + 2 * i) or 0)
      o.z = e.z
    end
  end
end
N[0x08066E68] = N[0x08066E68] or function(f, e) e.field80 = 0x54; e.animIndex = nil end -- Zelda: animation $54
N[0x080A29BC] = N[0x080A29BC] or function(f, e) -- CreateDeathFx (objectUtils.c): CreateFx(parent, FX_DEATH, 0)
  if f.addFx then f:addFx(e.x, e.y, 0x0F, 0x02) end
end
N[0x0806305C] = N[0x0806305C] or function(f, e) -- MinishEzlo: priority 0, animation $10
  e.prioB1 = 0
  e.field80 = 0x10; e.animIndex = nil
  sound(f, SFX.PLY_SHRINKING)
end
N[0x080630A4] = N[0x080630A4] or function() end -- SIMPLIFIED: the affine shrink is not drawn
N[0x0808D2CC] = N[0x0808D2CC] or function(f) -- MINISH_VILLAGE_OBJECT type 1 -> 9
  for _, o in ipairs(f.entities) do
    if not o.deleted and o.kind == 6 and o.id == 0x3E and o.form == 1 then
      o.form = 9; o.prio = 2; o.r27vBody = nil; o.r27sBody = nil
      return
    end
  end
end
N[0x0808D280] = N[0x0808D280] or function(f) -- the portal (type 9) fades out (SanctuaryScripts.mvoUpdate action 2)
  for _, o in ipairs(f.entities) do
    if not o.deleted and o.kind == 6 and o.id == 0x3E and o.form == 9 then
      o.action, o.sa = 2, 0
      sound(f, SFX.EVAPORATE)
      return
    end
  end
end
-- the hat (CUTSCENE_MISC_OBJECT $22): script_CutsceneMiscObjectTheLittleHat
M.HAT_SCRIPT = 0x0800AEDC
function M.findHat(f)
  for _, o in ipairs(f.entities) do
    if not o.deleted and o.kind == 6 and o.id == 0x6A and o.form == 0x22 then return o end
  end
end
N[0x08094B94] = N[0x08094B94] or function(f, e)
  local p = f.player
  local o = newMisc(f, 0x22, 0, p.x, p.y, M.HAT_SCRIPT)
  if o then o.z = 48 end
  if e.type2 then e.field80 = e.type2; e.animIndex = nil end
end
N[0x08094BE0] = N[0x08094BE0] or function(f) -- the hat on Link
  local o = M.findHat(f)
  if o then
    local p = f.player
    o.x, o.y, o.z, o.layer = p.x, p.y + 1, 12, 2
    o.r28anim = true
    anim(f, o, 1)
  end
end

-- ---------------------------------------------------------------- white triangle
-- gUnk_081215E8 (whiteTriangleEffect.c): {brightness type2, its step, radius,
-- radius speed, radius accel, angle, spin, spin accel, win in, win out}
M.TRIANGLE = {
  [0] = { 5, 4, 280, -6, 0, 0, -8, 0, 31, 63 },
  [1] = { 6, 2, 0, 4, 0, 0, 8, 0, 63, 31 },
  [2] = { 7, 4, 0, 4, 0, 0, -6, 0, 63, 31 },
  [3] = { 6, 2, 0, 16, 0, 0, 16, 0, 63, 31 },
}
local function s8(v) v = band(v, 0xFF) return v >= 0x80 and v - 0x100 or v end
function M.startTriangle(f, parent, type2)
  local c = M.TRIANGLE[type2 or 0] or M.TRIANGLE[0]
  local t = { parent = parent, r = c[3], rv = c[4], ra = c[5], ang = c[6], av = c[7], aa = c[8],
              bright = { v = 0x100, step = c[2], white = band(c[1], 2) ~= 0, up = band(c[1], 1) ~= 0 } }
  f.r28tri = t
  f.r28triDone = false
  M.stepTriangle(f) -- sub_0808C6D4 runs sub_0808C74C at once
  return t
end
-- sub_0808C74C (+ the brightness object's sub_0808C8B8)
function M.stepTriangle(f)
  local t = f.r28tri
  if not t then return end
  local p = t.parent
  if p and not p.deleted then t.x, t.y = math.floor(p.x) - (f.camX or 0), math.floor(p.y) - (f.camY or 0)
  else t.x, t.y = 0x78, 0x50 end
  local b = t.bright
  if b and not b.started then b.started = true
  elseif b then
    b.v = b.v - b.step
    if b.v < 0 then b.v = 0 end
  end
  if t.r < 0 or t.r > 500 then
    t.r = t.r < 0 and 0 or 500
    f.r28tri = nil -- sub_0808C840: layerFXControl 0, the window off
    f.r28triDone = true
    return
  end
  t.r = t.r + t.rv
  t.rv = t.rv + t.ra
  if t.rv > 0x10 then t.rv = 0x10 end
  if t.rv < -0x10 then t.rv = s8(0xF0) end
  t.ang = band(t.ang + t.av, 0xFF)
  t.av = t.av + t.aa
  if t.av > 0x10 then t.av = 0x10 end
  if t.av < -0x10 then t.av = -0x10 end
end
function M.triangleCorners(t)
  local out = {}
  for _, d in ipairs({ -0x40, 0x68, -0xE8 }) do
    local a = band(t.ang + d, 0xFF)
    out[#out + 1] = t.x + math.floor(cos(a) * t.r / 256)
    out[#out + 1] = t.y + math.floor(sin(a) * t.r / 256)
  end
  return out
end
N[0x0807FADC] = N[0x0807FADC] or function(f, e, ctx, a) -- sub_0807FADC
  local s = ctx.unk18 or 0
  if s == 0 then
    ctx.unk18 = 1
    M.startTriangle(f, e, ctx.intVariable or 0)
  elseif s == 1 then
    if f.r28triDone then ctx.unk18 = 2 end
  else
    f.r28triDone = true -- sub_0808C688
    ctx.unk18 = nil
    return
  end
  stay(a)
end

-- ---------------------------------------------------------------- credits
N[0x0807FB94] = N[0x0807FB94] or function(f) M.startStaffroll(f) end -- SetTask(TASK_STAFFROLL)
function M.startStaffroll(f)
  f.r28staff = require("src.zelda.tmc.Staffroll").new(f)
  -- the task owns the screen: the field's own fade / iris / triangle stop
  f.fadeLevel, f.fadeTarget, f.iris, f.r28tri = 0, 0, nil, nil
end

-- ---------------------------------------------------------------- hooks
function M.frame(f, input)
  if f.r28staff then
    local r = f.r28staff:update(input)
    if r == "title" then
      f.r28staff = nil
      if f.game and f.game.toTitle then f.game:toTitle() end
    end
    return true
  end
  if f.r28white and not f.transition and (f.fadeLevel or 0) == 0 then f.fadeWhite = false; f.r28white = nil end
  if f.r28tri and not (f.menu and f.menu.open) then M.stepTriangle(f) end
  return false
end

function M.draw(f, font)
  if f.r28staff then return f.r28staff:draw() end
  local t = f.r28tri
  if t and t.bright and love and love.graphics then
    local lv = rshift(t.bright.v, 4)
    if t.bright.up then lv = 16 - lv end
    if lv > 0 then
      local c = t.bright.white and 1 or 0
      love.graphics.setColor(c, c, c, math.min(1, lv / 16))
      love.graphics.polygon("fill", M.triangleCorners(t))
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

return M
