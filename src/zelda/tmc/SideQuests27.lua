-- Round 27 (team A, group SQ): side quests.  An R27A module (R27A.lua).
--
-- PORTED (ROM parity, from the decomp; whole functions, SoundReq -> f:sound):
-- src/npc/rem.c (REM $37, Rem's Shoe Shop, area $23 room 2; the Wake-Up
--   Mushroom / Pegasus Boots quest):
--   * Rem type 0 (sub_0806a370): action 0 sub_0806A3D8 (action 1, timer 180,
--     sub_0806A8C8 makes type 2 (unless SHOP02_KUTSU_00) and type 3 (2 px
--     lower), StartCutscene(script_Rem $08012F0C)); action 1 sub_0806A410
--     (180 frames, animation 8, at its end sub_0806A9B0 = asleep); action 2
--     sub_0806A458 (dozing: animation 9 for gUnk_081122A0[Random & 7] frames,
--     then 10, clear NPC37_REM_SLEEP, back to 2); action 3 sub_0806A4CC
--     (woken by a talk: 10 then facing Link, unk_6a = was asleep); action 4
--     sub_0806A550 (animation $C; its frame flag 1: InitScreenShake(8, 2),
--     sync flag $100, SFX_CHEST_OPEN; at its end action 5, animation $D and
--     sub_0806A914 = a type 1); action 6 sub_0806A5C0; animation $F's frame
--     flags 1 / 2: SFX_218 / SFX_219.
--   * type 1 sub_0806A5E8 (asleep at the bench: animation $10, SFX_REM_SLEEP
--     every (Random & $3F) + 120 frames), type 2 sub_0806A630 (animation $12,
--     runs while sync flag $100; its frame flag 1: SFX_SECRET), type 3
--     sub_0806A674 (animation $13: the jiggle by its parent's animation 9,
--     still once sync $100), type 4 sub_0806A830 (animation $14, its frame
--     flag 1 makes a type 5 on top; gone with sync $200), type 5 sub_0806A890
--     (animation $15 once).
--   * natives: Rem_MakeInteractable, sub_0806A958, sub_0806A96C,
--     sub_0806A9B0, sub_0806A9E8, sub_0806AA10, sub_0806AA18, sub_0806AA50
--     (the three Town Minish under the shop: the next line of the three
--     gUnk_081122A8 / B0 / B8 rows by local flag $8F and the boots, each
--     Minish hops (zVelocity 1.5), $1E sets flag $8F and condition 1),
--     sub_0806AB74 (the orchestrator's y kept >= origin + $A8), DeleteNpcRem
--     (the type 1 and the thought bubble).
-- src/npc/postman.c (POSTMAN $04, Hyrule Town): sub_08060528 (scripted:
--   a talk -> sub_080606D8 = gUnk_0810AA30[global_progress - 2], he waits
--   while the box is open; the jump over a Link standing in the way
--   (unk_6a > $12B: zVelocity 2.0, not talkable, SFX_PLY_JUMP), GravityUpdate
--   24.0, the dust FX_DASH on his frame flag 1); natives
--   Postman_MakeInteractable, sub_0806075C, sub_08060700 (LookAt the next
--   point of his route gUnk_0810A918 / gUnk_0810A66C), sub_0806076C (the
--   route's control bytes: -1 wait-to-jump, -2/-3 layer 1/2, -4 hide 30
--   frames, -5 pick a route that starts off screen, 0 pick the next route),
--   sub_080608E4 (Link inside gUnk_0810AA70[intVariable][facing]: condition
--   1, unk_6a += 2).
-- src/npc/mutoh.c: Mutoh_MakeInteractable, sub_080670B4 (TEXT_CARPENTERS 2,
--   3 when no Gust Jar and TABIDACHI), sub_080670E4 (its Dialog table by
--   global_progress).
-- src/npc/smith.c: sub_0806622C (Dialog by global_progress - 2),
--   sub_08066258 (SFX_HAMMER4/5/6 by Random & 7).
-- src/npc/talon.c: sub_08065780 (a random facing (Random & 6), context wait
--   gUnk_0810FED8[(Random >> 8) & 7]); the scripted action 2 sub_080656D4
--   (a talk with the Lon Lon key starts script_TalonGotKey $0800B41C, else
--   the script's intVariable message and action 3 sub_080656A4 until it
--   closes).
-- src/npc/malon.c: sub_08065914 (EPONA at +24, -1, MILK_CART at +40).
-- src/npc/anju.c: Anju_MakeInteractable.  The cucco game: SQ27Cucco.lua.
-- src/manager/hyruleTownBellManager.c (manager $33, Hyrule Town; the Roc's
--   Cape heart piece): Link in the 32 x 32 box at origin + ($1F8, $140) with
--   z < -$18 while jumping with the cape: SFX_10A, 90 frames later a
--   GRAVEYARD_KEY type 1 at z -24 (graveyardKey.c gUnk_08123FB0[1]: the heart
--   piece falls (BounceUpdate $1800, SFX_RUPEE_BOUNCE), on the ground
--   sub_0809D91C (FX_DASH, SFX_SECRET) and Link takes it (SetFlag($D0)).
-- Bottles (what CrenelPath.lua left out): script command $1F
--   CheckBottleContaining (GetBottleContaining); itemJarEmpty.c /
--   playerItemBottle.c for milk, half milk, potions, butter, picolytes
--   (ANIM_BOTTLE_DRINK, Link faces down; on his frame flag 1
--   PlayerItemBottle_UsePotionOrPicolyte: health 40 (milk -> half milk), 80,
--   160, picolyte type + 900 frames + SFX_PICOLYTE) and the charms
--   (ANIM_BOTTLE_POUR, frame 1: charm, 3600 frames, SFX_ELEMENT_CHARGE);
--   interrupts.c: the charm / picolyte timers (SFX_ICE_BLOCK_MELT / SFX_140
--   when they run out).
-- Also: sub_0807F93C (CreateSpeechBubbleSleep), ScriptCommand_SetMessageValue
--   is left to its group; TextBox gets gMessage.field_0x14 via
--   M.messageNumbers (one anchored line in TextBox.lua).
-- SIMPLIFIED: the picolyte sparkles and the charms' / picolytes' effects in
--   battle and drops are not ported; the bottle sprite in Link's hand is not
--   drawn; the Postman's sub_0806ED78 (NPC push) is the generic one.
local bit = require("bit")
local band, bor, bnot, rshift = bit.band, bit.bor, bit.bnot, bit.rshift
local Native = require("src.zelda.tmc.Native")
local N = Native.N
local function reg(addr, fn) if not N[addr] then N[addr] = fn end end

local M = {}
local Cucco = require("src.zelda.tmc.SQ27Cucco")
M.Cucco = Cucco

local REM, POSTMAN, TALON, MALON, EPONA, MILK_CART = 0x37, 0x04, 0x1D, 0x1E, 0x1F, 0x20
local SCRIPT_REM, SCRIPT_TALON_GOT_KEY = 0x08012F0C, 0x0800B41C
local SFX_218, SFX_219, SFX_CHEST_OPEN, SFX_REM_SLEEP, SFX_SECRET = 0x218, 0x219, 0x11B, 0xCC, 0x72
local SFX_PLY_JUMP, SFX_10A, SFX_RUPEE_BOUNCE = 0x7C, 0x10A, 0x6E
local SFX_PICOLYTE, SFX_ELEMENT_CHARGE, SFX_ICE_BLOCK_MELT, SFX_140 = 0x220, 0x1CF, 0x1B3, 0x140
local TEXT_REM, TEXT_POST, TEXT_MUTOH, TEXT_CARPENTERS, TEXT_SMITH, TEXT_PROLOGUE =
  0x4400, 0x4000, 0x4100, 0x1B00, 0x3200, 0x1000
local SHOP02_KUTSU_00, NPC37_REM_SLEEP = 0x60, 0x62
local ITEM_PEGASUS_BOOTS, ITEM_GUST_JAR, ITEM_QST_LONLON_KEY = 0x15, 0x11, 0x37
local TABIDACHI = 0x15
local FX_DASH = 0x11

local function D() return require("src.zelda.tmc.Drops") end
local function rnd(f) return D().random(D().rngOf(f)) end
local function s8(v) v = band(v, 0xFF) return v >= 128 and v - 256 or v end

-- GetFacingDirection (0..31) and GetAnimationStateForDirection4
local function dir32(x0, y0, x1, y1)
  local a = math.atan2(x1 - x0, -(y1 - y0))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
local function dir4(d) return band(math.floor((d + 4) / 8), 3) end
M.dir32, M.dir4 = dir32, dir4

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
-- a message with gMessage.rupees / field_0x14 ... (the $06 01 / 02 codes)
function M.messageNumbers(f, index, e, nums)
  f.messageRupees = nums[1]
  f:message(index, e)
  local tb = f.textbox
  if tb and nums[2] and f.assets and f.assets.message then
    -- rebuild with every number (TextBox.lua opts.numbers)
    local TextBox = require("src.zelda.tmc.TextBox")
    local bytes = f.assets:message(index)
    if bytes then
      local top = f.player and (f.player.y - (f.camY or 0)) > 100
      f.textbox = TextBox.new(bytes, { playerName = f.save.name, top = top, assets = f.assets, number = nums[1],
        numbers = nums, continue = function(id) return f.assets:message(id) end })
    end
  end
end

-- ShowNPCDialogue (npcUtils.c) for a Dialog written out from a .c table:
-- { flag, flagType, type, fromSelf, a, b }
local DIALOG_ROOM, DIALOG_LOCAL, DIALOG_GLOBAL, DIALOG_KINSTONE, DIALOG_INVENTORY = 0, 1, 2, 3, 4
local DIALOG_NONE, DIALOG_NORMAL, DIALOG_SET, DIALOG_TOGGLE, DIALOG_CHECK, DIALOG_CALL, DIALOG_MINISH = 0, 1, 2, 3, 4, 5, 6
M.DIALOG = { ROOM = 0, LOCAL = 1, GLOBAL = 2, KINSTONE = 3, INVENTORY = 4, NONE = 0, NORMAL = 1, SET = 2, TOGGLE = 3, CHECK = 4, MINISH = 6 }
local KIND = { [0] = "room", "local", "global" }
function M.dialogText(f, d)
  local flag, ft, dt, a, b = d[1], d[2], d[3], d[5], d[6]
  local function check()
    if ft <= 2 then return f:flag(KIND[ft], flag) end
    if ft == DIALOG_KINSTONE then return f.kinstoneFused and f:kinstoneFused(flag) or false end
    if ft == DIALOG_INVENTORY then return (f:inventory(flag) or 0) ~= 0 end
    return false
  end
  if dt == DIALOG_SET then
    local was = check()
    if ft <= 2 then f:setFlag(KIND[ft], flag, true) end
    return was and a or b
  elseif dt == DIALOG_TOGGLE then
    local was = check()
    if ft <= 2 then f:setFlag(KIND[ft], flag, not was) end
    return was and a or b
  elseif dt == DIALOG_CHECK then
    return check() and a or b
  elseif dt == DIALOG_NORMAL then
    return b
  elseif dt == DIALOG_MINISH then
    return f.player.minish and b or a
  end
  return 0
end
function M.showDialogue(f, e, d)
  local t = M.dialogText(f, d)
  f:message(t, e)
  return t
end
local function progress(f) return f.save.progress or 0 end

-- LookAt (script.c) as Script.lua's lookAt
local DIR_TABLE = { [0] = 0, 0, 2, 2, 2, 2, 4, 4, 4, 4, 6, 6, 6, 6, 0, 0 }
local function lookAt(e, ctx, x, y)
  local S = require("src.zelda.tmc.Script")
  ctx.unk19 = 8
  ctx.postScriptActions = bor(ctx.postScriptActions or 0, 2)
  ctx.condition = 0
  ctx.tx, ctx.ty = x, y
  local d = S.angleTo(x - e.x, y - e.y)
  e.angle = d
  e.animationState = bor(band(e.animationState or 0, 0x80), DIR_TABLE[rshift(d, 4)])
end

-- an NPC animation set by the C code (InitializeAnimation): kept literal
-- until a script's SetAnimation changes field80 (see M.frame)
local function setAnim(e, idx)
  e.r27anim, e.field80, e.r27f80 = idx, idx, idx
  e.animIndex = nil
end
local function animDone(e) return e.anim and band(e.anim.flags or 0, 0x80) ~= 0 end
local function frameByte(e) return e.anim and e.anim.flags or 0 end
local function clearFrame(e) if e.anim then e.anim.flags = 0 end end

-- CreateNPC(id, type, 0) at x, y
local function createNPC(f, id, form, x, y)
  local e = f:spawn({ kind = 7, id = id, paramA = form, paramB = 0, paramC = 0, x = x, y = y, pool = 0 })
  if e then e.talkable, e.solid, e.r27sq = false, false, true end
  return e
end
M.createNPC = createNPC

-- the script pause while an NPC's C action owns it (ExecuteScript not called)
local function pause(e, on)
  if not e.script then return end
  if on then
    if not e.r27paused and not e.script.stopped then e.r27paused = true; e.script.stopped = true end
  elseif e.r27paused then
    e.r27paused = nil; e.script.stopped = false
  end
end

-- ---------------------------------------------------------------------------
-- Rem (rem.c)
-- ---------------------------------------------------------------------------
local SLEEP_T = { 60, 100, 200, 60, 100, 200, 80, 80 } -- gUnk_081122A0
local JIGGLE = { [0] = 0, -1, 0, 1, 0, -1, 0, 1 }       -- gUnk_08112294

local function remSleep(f, e) -- sub_0806A9B0
  e.action, e.subAction = 2, 0
  e.timer = SLEEP_T[band(rnd(f), 7) + 1]
  e.unk80 = 9
  setAnim(e, 9)
  f:setFlag("local", NPC37_REM_SLEEP, true)
end
M.remSleep = remSleep

local function remSpawn1(f, e) -- sub_0806A914
  local n = createNPC(f, REM, 1, e.x, e.y)
  if n then n.spritePriority = (e.spritePriority or 4) end
  return n
end

local function sync() return require("src.zelda.tmc.Script").active end

local function remType0(f, e)
  local a = e.action or 0
  if a == 0 then -- sub_0806A3D8
    e.action, e.subAction = 1, 0
    e.timer = 180
    if not f:flag("local", SHOP02_KUTSU_00) then
      local t2 = createNPC(f, REM, 2, e.x, e.y)
      if t2 then t2.parent = e end
    end
    local t3 = createNPC(f, REM, 3, e.x, e.y + 2)
    if t3 then t3.parent = e end
    if not e.script and f.mem and f.mem:valid(SCRIPT_REM) then
      e.script = require("src.zelda.tmc.Script").new(f.mem, SCRIPT_REM)
    end
  elseif a == 1 then -- sub_0806A410
    local s = e.subAction or 0
    if s == 0 then
      e.timer = (e.timer or 1) - 1
      if e.timer <= 0 then e.subAction = 1; setAnim(e, 8) end
    elseif s == 1 then
      if animDone(e) then remSleep(f, e) end
    end
  elseif a == 2 then -- sub_0806A458
    local s = e.subAction or 0
    if s == 0 then
      e.timer = (e.timer or 1) - 1
      if e.timer <= 0 then e.subAction = 1 end
    elseif s == 1 then
      if animDone(e) then e.subAction = 2; setAnim(e, 10); f:setFlag("local", NPC37_REM_SLEEP, false) end
    elseif s == 2 then
      if animDone(e) then e.action, e.subAction, e.timer = 1, 0, 60; setAnim(e, 2) end
    end
  elseif a == 3 then -- sub_0806A4CC
    local s = e.subAction or 0
    if s == 0 then
      if animDone(e) then
        local ai = e.r27anim or e.field80 or 0
        if ai - 8 >= 0 and ai - 8 < 2 then
          e.subAction, e.unk6a = 1, 1
          setAnim(e, 10)
        else
          e.subAction, e.unk6a = 2, 0
          setAnim(e, dir4(dir32(e.x, e.y, f.player.x, f.player.y)))
        end
      end
    elseif s == 1 then
      if animDone(e) then e.subAction = 2; setAnim(e, dir4(dir32(e.x, e.y, f.player.x, f.player.y))) end
    else
      e.timer = 180
    end
  elseif a == 4 then -- sub_0806A550
    if (e.subAction or 0) == 0 then
      e.subAction = 1
      setAnim(e, 0xC)
    else
      if frameByte(e) == 1 then
        clearFrame(e)
        if f.shake then f:shake(8, 2) end
        local A = sync()
        A.syncFlags = bor(A.syncFlags, 0x100)
        f:sound(SFX_CHEST_OPEN)
      end
      if animDone(e) then
        e.action, e.subAction = 5, 0
        setAnim(e, 0xD)
        remSpawn1(f, e)
      end
    end
  elseif a == 6 then -- sub_0806A5C0
    if animDone(e) then setAnim(e, band(rnd(f), 3) + 4) end
  end
  if (e.r27anim or e.field80) == 0xF then
    local fb = frameByte(e)
    if fb == 1 then clearFrame(e); f:sound(SFX_218) end
    if fb == 2 then clearFrame(e); f:sound(SFX_219) end
  end
end

local function remHelper(f, e)
  local t = e.form or 0
  local A = sync()
  if t == 1 then -- sub_0806A5E8
    if (e.action or 0) == 0 then
      e.action = 1
      setAnim(e, 0x10)
      e.timer = band(rnd(f), 0x3F) + 60
    end
    e.timer = (e.timer or 1) - 1
    if e.timer <= 0 then
      e.timer = band(rnd(f), 0x3F) + 120
      f:sound(SFX_REM_SLEEP)
    end
  elseif t == 2 then -- sub_0806A630
    if (e.action or 0) == 0 then e.action = 1; setAnim(e, 0x12) end
    e.r27freeze = band(A.syncFlags, 0x100) == 0 -- GetNextFrame only while sync $100
    if frameByte(e) == 1 then clearFrame(e); f:sound(SFX_SECRET) end
  elseif t == 3 then -- sub_0806A674
    local a = e.action or 0
    if a == 0 then
      e.action = 1
      e.spritePriority = 6
      setAnim(e, 0x13)
      e.r27freeze = true
    elseif a == 1 then
      e.r27freeze = true
      e.spriteOX, e.spriteOY = e.spriteOX or 0, e.spriteOY or 0
      if band(A.syncFlags, 0x100) ~= 0 then
        e.action = 2
        e.spriteOX, e.spriteOY = 0, 0
      elseif e.parent and (e.parent.r27anim == 9) then
        e.spritePriority = 3
        local fc = f.frame or 0
        if (e.timer or 0) == 0 then
          local r = rnd(f)
          e.timer = band(r, 7)
          e.u68 = JIGGLE[band(rshift(r, 8), 7)]
        elseif band(fc, 3) == 0 then
          e.timer = e.timer - 1
          if e.spriteOX < 1 then e.u68 = 1 end
          if e.spriteOX > 0xF then e.u68 = -1 end
          e.spriteOX = e.spriteOX + (e.u68 or 0)
        end
        if (e.subtimer or 0) == 0 then
          local r = rnd(f)
          e.subtimer = band(r, 7)
          e.u69 = JIGGLE[band(rshift(r, 8), 7)]
        elseif band(rshift(fc, 4), 3) == 0 then
          e.subtimer = e.subtimer - 1
          if e.spriteOY > -1 then e.u69 = -1 end
          if e.spriteOY <= -8 then e.u69 = 1 end
          e.spriteOY = e.spriteOY + (e.u69 or 0)
        end
      else
        e.spritePriority = 6
        if e.spriteOX > 0 then e.spriteOX = e.spriteOX - 1 elseif e.spriteOX < 0 then e.spriteOX = e.spriteOX + 1 end
        if e.spriteOY > 0 then e.spriteOY = e.spriteOY - 1 elseif e.spriteOY < 0 then e.spriteOY = e.spriteOY + 1 end
      end
    else
      e.r27freeze = false
    end
  elseif t == 4 then -- sub_0806A830
    if (e.action or 0) == 0 then e.action = 1; setAnim(e, 0x14) end
    if band(A.syncFlags, 0x200) ~= 0 then e.deleted = true return end
    if frameByte(e) == 1 then
      clearFrame(e)
      local n = createNPC(f, REM, 5, e.x, e.y)
      if n then n.spritePriority = (e.spritePriority or 4) - 1 end
    end
  elseif t == 5 then -- sub_0806A890
    if (e.action or 0) == 0 then e.action = 1; setAnim(e, 0x15) end
    if animDone(e) then e.deleted = true end
  end
end

-- Rem_MakeInteractable: AddInteractableWhenBigObject + SetInteractableObjectCollision(e, 0, 0,
-- gUnk_0811229C {0, 6, 10, 16}) (the box Hitboxes.interactHit tests: e.interactBox)
reg(0x0806A93C, function(f, e) e.talkable = true; e.interactBox = { x = 0, y = 6, w = 10, h = 16, dirs = 0 } end)
reg(0x0806A958, function(f, e, ctx, a) if e.action ~= 5 then a.commandSize = 0 end end)
reg(0x0806A96C, function(f, e, ctx, a)
  ctx.condition = 0
  if (e.interactType or 0) ~= 0 then
    if e.action ~= 3 then
      e.action, e.subAction = 3, 0
    elseif (e.subAction or 0) > 1 then
      e.interactType = 0
      ctx.condition = 1
      a.flags = bor(a.flags, 1)
    end
  end
end)
reg(0x0806A9B0, function(f, e) remSleep(f, e) end)
reg(0x0806A9E8, function(f, e) -- sub_0806A9E8
  local n = createNPC(f, REM, 4, e.x, e.y)
  if n then n.spritePriority = (e.spritePriority or 4) + 1 end
end)
reg(0x0806AA10, function(f, e) remSpawn1(f, e) end)
reg(0x0806AA18, function(f, e)
  local idx
  if (e.unk6a or 0) ~= 0 then idx = TEXT_REM + 0x08
  elseif band(f.frame or 0, 1) == 0 then idx = TEXT_REM + 0x07
  else idx = TEXT_REM + 0x0D end
  f:message(idx, e)
end)
reg(0x0806AB74, function(f, e) -- sub_0806AB74
  f.r27remFlagUnused = true
  if e.y < 0xA8 then e.y = 0xA8 end
end)
reg(0x0806AB9C, function(f, e) -- DeleteNpcRem + DeleteThoughtBubble
  for _, o in ipairs(f.entities) do
    if o.kind == 7 and o.id == REM and o.form == 1 and not o.deleted then o.deleted = true break end
  end
  for _, o in ipairs(f.entities) do if o.bubbleKind ~= nil then o.bubbleT = 0; o.bubbleKind = nil break end end
end)
reg(0x0807F93C, function(f, e, ctx) -- script.c sub_0807F93C: CreateSpeechBubbleSleep
  local v = ctx.intVariable or 0
  f:bubble(e, 2, s8(rshift(v, 8)), s8(v))
end)

-- sub_0806AA50: the Town Minish under Rem's shop
local LINES = {
  { TEXT_REM + 0x1C, TEXT_REM + 0x1D, TEXT_REM + 0x1E }, -- gUnk_081122A8
  { TEXT_REM + 0x1F, TEXT_REM + 0x20, TEXT_REM + 0x21 }, -- gUnk_081122B0
  { TEXT_REM + 0x10, TEXT_REM + 0x11, TEXT_REM + 0x12 }, -- gUnk_081122B8
}
local function hop(e) e.r27hop = true; e.cz = e.cz or 0; e.czv = 0x18000 end
reg(0x0806AA50, function(f, e, ctx, a)
  local u = ctx.r27u18 or 0
  if u == 0 then
    ctx.condition = 0
    local row
    if not f:flag("local", 0x8F) then row = LINES[1]
    elseif (f:inventory(ITEM_PEGASUS_BOOTS) or 0) == 0 then row = LINES[2]
    else row = LINES[3] end
    local k = f.r27animFlags or 0
    local idx = row[k + 1]
    k = k + 1
    if k > 2 then k = 0 end
    f.r27animFlags = k
    f:message(idx, e)
    local iv = ctx.intVariable or 0
    f.r27puzzle = f.r27puzzle or {}
    if iv == 0 then
      f.r27puzzle[0] = e
      hop(e)
    else
      local prev = f.r27puzzle[iv - 1]
      local found, nxt = prev == nil, nil
      for _, o in ipairs(f.entities) do
        if found and o ~= f.r27puzzle[0] and o.kind == e.kind and o.id == e.id and not o.deleted then nxt = o break end
        if o == prev then found = true end
      end
      if not nxt then -- PrependEntityToList put the first one at the head
        for _, o in ipairs(f.entities) do
          if o.kind == e.kind and o.id == e.id and not o.deleted and o ~= f.r27puzzle[0] and o ~= f.r27puzzle[1] then nxt = o break end
        end
      end
      f.r27puzzle[iv] = nxt
      if nxt then hop(nxt) end
    end
    if idx == TEXT_REM + 0x1E then
      f:setFlag("local", 0x8F, true)
      ctx.condition = 1
    end
    ctx.r27u18 = 1
  elseif u == 1 then
    local p = f.r27puzzle and f.r27puzzle[ctx.intVariable or 0]
    if p and (p.cz or 0) < 0 then a.commandSize = 0 return end
    if p then hop(p) end
    ctx.r27u18 = 2
  else
    if (e.cz or 0) >= 0 then ctx.r27u18 = 0 return end
  end
  a.commandSize = 0
end)

-- ---------------------------------------------------------------------------
-- Postman (postman.c)
-- ---------------------------------------------------------------------------
local PC = { [0] = { 0x0, 0x0 }, { 0x48, 0xa8 }, { 0x0, 0xf0 }, { 0x1f8, 0x0 }, { 0x3f8, 0xf0 }, { 0x1f8, 0x3c8 },
  { 0x48, 0xf0 }, { 0x60, 0xf0 }, { 0x60, 0x188 }, { 0x78, 0x188 }, { 0x78, 0x270 }, { 0x38, 0x270 },
  { 0x38, 0x328 }, { 0x98, 0x328 }, { 0xd8, 0x328 }, { 0x108, 0x328 }, { 0x188, 0x328 }, { 0x188, 0x368 },
  { 0x108, 0x278 }, { 0x128, 0x278 }, { 0x128, 0x1d0 }, { 0x1a8, 0x1d0 }, { 0x1f8, 0x1d0 }, { 0x1a8, 0x288 },
  { 0x1f8, 0x288 }, { 0x1f8, 0x328 }, { 0x268, 0x328 }, { 0x268, 0x368 }, { 0x268, 0x390 }, { 0x1f8, 0xf0 },
  { 0x248, 0x1d0 }, { 0x248, 0x1c0 }, { 0x248, 0x288 }, { 0x298, 0x288 }, { 0x298, 0x328 }, { 0x328, 0x328 },
  { 0x328, 0x390 }, { 0x368, 0x328 }, { 0x368, 0x318 }, { 0x3a0, 0x318 }, { 0x3a0, 0x290 }, { 0x370, 0x290 },
  { 0x370, 0x280 }, { 0x360, 0x280 }, { 0x360, 0x270 }, { 0x340, 0x270 }, { 0x340, 0x248 }, { 0x320, 0x248 },
  { 0x2e0, 0x248 }, { 0x2e0, 0x1d0 }, { 0x2d0, 0x1d0 }, { 0x2d0, 0x1c0 }, { 0x320, 0x168 }, { 0x378, 0x168 },
  { 0x378, 0xf0 }, { 0x2b0, 0x288 }, { 0x2b0, 0x280 }, { 0x2c0, 0x280 }, { 0x2c0, 0x270 }, { 0x2d0, 0x270 },
  { 0x2d0, 0x248 }, { 0x78, 0x1f0 }, { 0x78, 0x230 } } -- gUnk_0810A66C
local R768 = { 1, -4, 0, 1, 2 }
M.POST_ROUTES = { [0] = R768, R768, -- gUnk_0810A918 -> gUnk_0810A768 ...
  { 6, 0, 2, 4, 21 }, { 6, 0, 2, 1, 21 }, { 2, -5, 3, 5, 7, 9 }, { 29, 0, 3, 20, 17, 16 }, { 3, -5, 3, 3, 7, 9 },
  { 54, 0, 2, 18, 62 }, { 4, -5, 3, 3, 5, 9 }, { 25, 0, 3, 46, 30, 31 }, { 5, -5, 3, 3, 5, 7 },
  { 24, 0, 3, 45, 47, 14 }, { 22, 0, 3, 15, 66, 63 }, { 23, 24, 0, 3, 12, 47, 45 }, { 23, 21, 0, 2, 65, 26 },
  { 29, 0, 3, 6, 20, 17 }, { 22, 0, 3, 66, 11, 63 }, { 54, 0, 2, 8, 62 }, { 29, 0, 3, 6, 20, 16 },
  { 29, 0, 3, 6, 17, 16 }, { 7, 0, 2, 22, 23 }, { 7, 0, 2, 23, 19 }, { 6, 0, 2, 1, 4 },
  { 8, 9, 61, -1, 62, 10, 11, 12, 13, -1, 14, 15, 0, 2, 27, 25 },
  { 14, -1, 13, 12, 11, 10, 62, -1, 61, 9, 8, 7, 0, 2, 22, 19 },
  { 18, 19, 20, 21, 0, 2, 65, 13 }, { 20, 19, 18, 15, 0, 2, 24, 27 }, { 16, 0, 2, 29, 33 }, { 15, 0, 2, 24, 25 },
  { 25, 0, 3, 46, 31, 10 }, { 16, 0, 2, 28, 33 }, { 26, 0, 2, 41, 43 }, { 25, 0, 3, 10, 46, 30 },
  { 17, 27, 0, 2, 42, 35 }, { 17, 16, 0, 2, 28, 29 }, { 28, 36, 35, 0, 2, 40, 37 }, { 36, 28, 27, 0, 2, 34, 42 },
  { 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 0, 2, 57, 61 }, { 46, 45, 44, 43, 42, 41, 40, 39, 38, 37, 35, 0, 2, 36, 40 },
  { 35, 0, 2, 36, 37 }, { 34, 0, 2, 44, 52 }, { 27, 0, 2, 34, 35 }, { 26, 0, 2, 32, 43 }, { 34, 0, 2, 52, 39 },
  { 26, 0, 2, 32, 41 }, { 25, 0, 3, 10, 30, 31 }, { 24, 0, 3, 14, 12, 47 }, { 32, 0, 2, 54, 49 },
  { 24, 0, 3, 14, 12, 45 }, { 33, 0, 2, 51, 55 }, { 32, 0, 2, 48, 54 }, { 34, 0, 2, 44, 39 }, { 33, 0, 2, 50, 55 },
  { 32, 0, 2, 48, 49 }, { 30, 0, 2, 64, 59 }, { 55, 56, 57, 58, 59, 60, 48, 0, 2, 60, 58 },
  { 60, 59, 58, 57, 56, 55, 33, 0, 2, 50, 51 }, { 48, 0, 2, 60, 56 }, { 47, 0, 2, 38, 61 },
  { 31, 51, 50, 49, 48, 0, 2, 56, 58 }, { 49, 50, 51, 31, 30, 0, 2, 64, 53 }, { 52, 53, 54, 0, 2, 8, 18 },
  { 53, 52, 47, 0, 2, 38, 57 }, { 30, 0, 2, 53, 59 }, { 22, 0, 3, 66, 11, 15 }, { 22, 0, 3, 11, 15, 63 },
  { 21, 0, 2, 26, 13, 0, 0 } }
M.POST_COORDS = PC
local POST_TEXT = { 0xC, 0xC, 0xD, 0xE, 0xF, 0x10, 0x11, 0x12 } -- gUnk_0810AA30 (DIALOG_NORMAL)
local POST_RECT = { [0] = { { 0, -16, 16, 16 }, { 16, 0, 16, 16 }, { 0, 16, 16, 16 }, { -16, 0, 16, 16 } },
                    { { 0, -16, 32, 32 }, { 16, 0, 32, 32 }, { 0, 16, 32, 32 }, { -16, 0, 32, 32 } } } -- gUnk_0810AA70

local function onScreen(f, e)
  local x, y = e.x - (f.camX or 0), e.y - (f.camY or 0)
  return x > -16 and x < 256 and y > -16 and y < 176
end
local function route(e) return M.POST_ROUTES[e.pm68 or 0] or R768 end
local function rv(t, i) local v = t[i + 1] return v or 0 end

reg(0x080606C0, function(f, e) e.talkable = true end) -- Postman_MakeInteractable
reg(0x0806075C, function(f, e) e.pm68, e.pm69 = 0xB, -1 end)
reg(0x08060700, function(f, e, ctx, a) -- sub_08060700
  local c = PC[rv(route(e), e.pm69 or 0)] or PC[0]
  lookAt(e, ctx, c[1], c[2])
  a.flags = bor(a.flags, 1)
end)
reg(0x0806076C, function(f, e, ctx, a) -- sub_0806076C
  if (e.cz or 0) < 0 then a.commandSize = 0 return end
  e.pm69 = (e.pm69 or 0) + 1
  e.layer = 1
  e.talkable = true
  local t = route(e)
  local i = e.pm69
  while true do
    local v = rv(t, i)
    local k = v + 5
    if k == 5 then
      local n = rv(t, i + 1)
      local pick = n > 0 and (rnd(f) % n) or 0
      e.pm68 = rv(t, i + 2 + pick)
      e.pm69 = 0
      return
    elseif k == 4 then e.pm6a = 300
    elseif k == 3 then e.layer = 1
    elseif k == 2 then e.layer = 2
    elseif k == 1 then ctx.wait = 0x1E; e.hidden = true
    elseif k == 0 then
      local n = rv(t, i + 1)
      local at = n > 0 and (rnd(f) % n) or 0
      for _ = 1, n do
        e.pm68 = rv(t, i + 2 + at)
        local c = PC[rv(M.POST_ROUTES[e.pm68] or R768, 0)] or PC[0]
        e.x, e.y = c[1], c[2]
        if not onScreen(f, e) then break end
        at = (at + 1) % n
      end
      e.pm69 = 0
      return
    else
      return
    end
    e.pm69 = e.pm69 + 1
    i = i + 1
  end
end)
reg(0x080608E4, function(f, e, ctx) -- sub_080608E4
  ctx.condition = 0
  if (e.cz or 0) >= 0 then
    local p = f.player
    local pl = p.layer or 1
    if not ((e.layer == 1 and pl == 2) or (e.layer == 2 and pl == 1)) then
      local r = POST_RECT[ctx.intVariable == 1 and 1 or 0][rshift(e.animationState or 4, 1) % 4 + 1]
      local x = math.floor(p.x) - (math.floor(e.x) + r[1]) + r[3]
      local y = math.floor(p.y) - (math.floor(e.y) + r[2]) + r[4]
      if x >= 0 and y >= 0 and r[3] * 2 > x and r[4] * 2 > y then
        ctx.condition = 1
        e.pm6a = (e.pm6a or 0) + 2
      end
    end
  end
end)

local function postman(f, e)
  if e.pmAct == nil then e.pmAct = 1; e.pm6a, e.pm6d = e.pm6a or 0, 0; e.cz, e.czv = e.cz or 0, e.czv or 0 end
  if e.pmAct == 1 then
    if e.interactType == 1 then
      e.pmAct, e.interactType = 2, 0
      local i = math.max(progress(f) - 2, 0)
      f:message(TEXT_POST + (POST_TEXT[i + 1] or 0x12), e) -- sub_080606D8 (DIALOG_NORMAL)
      e.pmState = e.animationState
      e.animationState = dir4(dir32(e.x, e.y, f.player.x, f.player.y)) * 2
      pause(e, true)
    end
  elseif e.pmAct == 2 then
    if not f:messageActive() then e.pmAct = 1; e.animationState = e.pmState or e.animationState; pause(e, false) end
  end
  -- sub_080604DC: the dust
  if not e.hidden and onScreen(f, e) and band(frameByte(e), 1) ~= 0 then
    e.anim.flags = band(e.anim.flags, 0xFE)
    if f.addFx then f:addFx(e.x, e.y + 1, 0x0F, FX_DASH) end
  end
  if (e.pm6a or 0) > 0 then
    if e.pm6a > 0x12B then
      e.pm6a = 0
      e.czv = 0x20000
      e.pm6d = 1
      e.talkable = false
      f:sound(SFX_PLY_JUMP)
    else
      e.pm6a = e.pm6a - 1
    end
  end
  -- GravityUpdate(24.0)
  if e.cz < 0 or e.czv > 0 then
    local nz = e.cz - e.czv
    if nz < 0 then e.cz, e.czv = nz, e.czv - 0x1800 else e.cz, e.czv = 0, 0 end
  end
  e.z = -e.cz / 65536
  if e.pm6d ~= 0 and e.czv == 0 and e.cz == 0 then e.pm6d = 0; e.talkable = true end
end
M.postman = postman

-- ---------------------------------------------------------------------------
-- Mutoh, Smith, Talon, Malon, Anju
-- ---------------------------------------------------------------------------
reg(0x08067100, function(f, e) e.talkable = true end) -- Mutoh_MakeInteractable
reg(0x080670B4, function(f, e) -- sub_080670B4
  local i = 0
  if (f:inventory(ITEM_GUST_JAR) or 0) == 0 and f:flag("global", TABIDACHI) then i = 1 end
  f:message(TEXT_CARPENTERS + (i == 0 and 2 or 3), e)
end)
local MUTOH = {}
for i = 0, 4 do MUTOH[i] = { 0, DIALOG_ROOM, DIALOG_TOGGLE, 1, TEXT_MUTOH + 1, TEXT_MUTOH + 0 } end
MUTOH[5] = { 0xB, DIALOG_KINSTONE, DIALOG_CHECK, 1, TEXT_MUTOH + 4, TEXT_MUTOH + 2 }
MUTOH[6] = { 0xB, DIALOG_KINSTONE, DIALOG_CHECK, 1, TEXT_MUTOH + 4, TEXT_MUTOH + 3 }
MUTOH[7] = MUTOH[6]
MUTOH[8] = { 0xB, DIALOG_KINSTONE, DIALOG_CHECK, 1, TEXT_MUTOH + 4, TEXT_MUTOH + 5 }
MUTOH[9] = MUTOH[8]
M.MUTOH = MUTOH
reg(0x080670E4, function(f, e) M.showDialogue(f, e, MUTOH[math.min(progress(f), 9)]) end)
local SMITH = {}
for i, t in ipairs({ 1, 1, 2, 3, 4, 5, 6, 6 }) do
  SMITH[i - 1] = { TABIDACHI, DIALOG_GLOBAL, DIALOG_CHECK, 1, TEXT_SMITH + t, TEXT_PROLOGUE + 0x0E }
end
M.SMITH = SMITH
reg(0x0806622C, function(f, e) M.showDialogue(f, e, SMITH[math.min(math.max(progress(f) - 2, 0), 7)]) end)
local HAMMER = { 0xDF, 0xE0, 0xE1, 0xDF, 0xE0, 0xE1, 0xDF, 0xE0 } -- SFX_HAMMER4/5/6
reg(0x08066258, function(f) f:sound(HAMMER[band(rnd(f), 7) + 1]) end)
local TALON_WAIT = { 10, 20, 30, 18, 28, 38, 12, 24 } -- gUnk_0810FED8
reg(0x08065780, function(f, e, ctx) -- sub_08065780
  local r = rnd(f)
  e.animationState = band(r, 6)
  ctx.wait = TALON_WAIT[band(rshift(r, 8), 7) + 1]
end)
reg(0x08065914, function(f, e) -- sub_08065914
  for _, o in ipairs(f.entities) do
    if o.kind == 7 and not o.deleted then
      if o.id == EPONA then o.x, o.y, o.parent = e.x + 24, e.y - 1, e
      elseif o.id == MILK_CART then o.x, o.y, o.parent = e.x + 40, e.y, e end
    end
  end
end)
reg(0x0806C354, function(f, e) e.talkable = true end) -- Anju_MakeInteractable

-- talon.c scripted actions 2 / 3
local function talon(f, e)
  if e.action == 2 then
    local it = e.interactType or 0
    if it == 1 then
      if (f:inventory(ITEM_QST_LONLON_KEY) or 0) ~= 0 then
        if f.mem and f.mem:valid(SCRIPT_TALON_GOT_KEY) then
          pause(e, false)
          e.script = require("src.zelda.tmc.Script").new(f.mem, SCRIPT_TALON_GOT_KEY)
        end
      else
        e.u69, e.action, e.interactType = e.action, 3, 0
        e.u6aState = e.animationState
        f:message(e.script and e.script.intVariable or 0, e)
        e.animationState = dir4(dir32(e.x, e.y, f.player.x, f.player.y)) * 2 -- sub_0806574C
        pause(e, true)
      end
    end
  elseif e.action == 3 then
    if not f:messageActive() then
      e.action = e.u69 or 2
      if e.u6aState then e.animationState = e.u6aState end
      pause(e, false)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Hyrule Town bell (hyruleTownBellManager.c) and its heart piece
-- ---------------------------------------------------------------------------
local function fallingHeart(f, d)
  local O = f:objects()
  local g = O:groundItem(0x63, 0, 0x1F8, 0x140, {})
  if not g then return end
  g.act, g.cz, g.czv, g.flagSpec = 9, -24 * 65536, 0, 0xD0 -- gUnk_08123FB0[1]: flag $D0
  local t = { kind = 9, id = -1, hidden = true, ticker = true }
  t.extUpdate = function(dd, me)
    if g.deleted then me.deleted = true return end
    local r = require("src.zelda.tmc.EnemyCrenel").bounce(g, 0x1800)
    g.z = -(g.cz or 0) / 65536
    if r < 2 then
      f:sound(SFX_RUPEE_BOUNCE)
      g.act, g.cz, g.czv, g.z = 2, 0, 0, 0
      if f.addFx then f:addFx(g.x, g.y, 0x0F, FX_DASH) end -- sub_0809D91C
      f:sound(SFX_SECRET)
      me.deleted = true
    end
  end
  d:track(t)
end
M.fallingHeart = fallingHeart

local function bellTick(d, m)
  local f = d.field
  local p = f.player
  if m.action == 0 then
    local x = 0x1F8 - math.floor(p.x) + 0x10
    local y = 0x140 - math.floor(p.y) + 0x10
    if x >= 0 and x < 0x20 and y >= 0 and y < 0x20 and (p.z or 0) > 0x18 and p.jump then
      m.action, m.timer = 1, 90
      f:sound(SFX_10A)
    end
  else
    m.timer = m.timer - 1
    if m.timer == 0 then
      fallingHeart(f, d)
      m.deleted = true
    end
  end
end
M.bellTick = bellTick

function M.spawnManager(d, m)
  if m.id == 0x33 then -- HYRULE_TOWN_BELL_MANAGER
    local t = { kind = 9, id = 0x33, hidden = true, ticker = true, action = 0, timer = 0 }
    t.extUpdate = function(dd, me) bellTick(dd, me) end
    d:track(t)
    return true
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- bottles
-- ---------------------------------------------------------------------------
local ITEM_BOTTLE1, B_EMPTY, B_MILK, B_HALF = 0x1C, 0x20, 0x22, 0x23
local DRINK = { [0x21] = 160, [0x22] = 40, [0x23] = 40, [0x24] = 160, [0x25] = 80 }
local function isDrink(c) return DRINK[c] ~= nil or (c >= 0x29 and c <= 0x2E) end
local function isCharm(c) return c >= 0x2F and c <= 0x31 end
M.isDrink, M.isCharm = isDrink, isCharm

function M.getBottleContaining(f, item)
  local b = f.save.bottles or {}
  for i = 1, 4 do
    if (f.save.items[ITEM_BOTTLE1 + i - 1] or 0) ~= 0 and b[i] == item then return i end
  end
  return 0
end

-- PlayerItemBottle_UsePotionOrPicolyte
function M.drink(f, i, c)
  local b = f.save.bottles
  local new, health = B_EMPTY, 0
  if c == B_MILK then new = B_HALF; health = 40
  elseif DRINK[c] then health = DRINK[c]
  else
    f.save.stats.picolyteType = c
    f.save.stats.picolyteTimer = 900
    f:sound(SFX_PICOLYTE)
  end
  f:modStat("health", health)
  b[i] = new
end
-- PlayerItemBottle_UseOther for a charm
function M.charm(f, i, c)
  f.save.bottles[i] = B_EMPTY
  f.save.stats.charm = c
  f.save.stats.charmTimer = 3600
  f:sound(SFX_ELEMENT_CHARGE)
end

function M.useBottle(p, item)
  if item < ITEM_BOTTLE1 or item > ITEM_BOTTLE1 + 3 or p.state ~= "normal" then return nil end
  local f = p.field
  local b = f.save.bottles or {}
  local i = item - ITEM_BOTTLE1 + 1
  local c = b[i] or B_EMPTY
  if not isDrink(c) and not isCharm(c) then return nil end
  p.state = "ext"
  p.moving = false
  if isDrink(c) then
    p.animationState = 4
    p.entFlip = false
    p:setAnim(0x2DF, true) -- ANIM_BOTTLE_DRINK
  else
    p:setAnim(0x610, true) -- ANIM_BOTTLE_POUR
  end
  local used = false
  p.extUpdate = function(pl)
    pl.anim:update(1)
    local fl = pl.anim.flags or 0
    if not used and fl == 1 then
      used = true
      pl.anim.flags = 0
      if isDrink(c) then M.drink(f, i, c) else M.charm(f, i, c) end
    end
    if band(fl, 0x80) ~= 0 or pl.anim.done then
      if not used then used = true; if isDrink(c) then M.drink(f, i, c) else M.charm(f, i, c) end end
      pl.state = "normal"
      pl.extUpdate = nil
      pl.animId = -1
    end
  end
  return true
end

-- interrupts.c: the charm and picolyte timers
function M.statTimers(f)
  local s = f.save.stats
  if (s.charm or 0) == 0 then s.charmTimer = 0
  elseif (s.charmTimer or 0) == 0 then s.charm = 0; f:sound(SFX_ICE_BLOCK_MELT)
  else
    s.charmTimer = s.charmTimer - 1
    if s.charmTimer == 0 then s.charm = 0; f:sound(SFX_ICE_BLOCK_MELT) end
  end
  if (s.picolyteType or 0) == 0 then s.picolyteTimer = 0
  elseif (s.picolyteTimer or 0) == 0 then s.picolyteType = 0; f:sound(SFX_140)
  else
    s.picolyteTimer = s.picolyteTimer - 1
    if s.picolyteTimer == 0 then s.picolyteType = 0; f:sound(SFX_140) end
  end
end

local function install()
  local Script = require("src.zelda.tmc.Script")
  local C = Script.commands
  if C and not C[0x1F] then
    -- ScriptCommand_CheckBottleContaining
    C[0x1F] = function(e, ctx, host)
      ctx.condition = M.getBottleContaining(host, ctx.mem:u16(ctx.ip + 2))
      Script.active.flags = bor(Script.active.flags, 1)
    end
  end
  local okCP, CP = pcall(require, "src.zelda.tmc.CrenelPath")
  if okCP and CP.useBottle and not CP.r27aBottles then
    CP.r27aBottles = true
    local orig = CP.useBottle
    CP.useBottle = function(p, item, button)
      local r = M.useBottle(p, item)
      if r ~= nil then return r end
      return orig(p, item, button)
    end
  end
  Cucco.install()
end
M.install = install
install()

-- ---------------------------------------------------------------------------
-- R27A hooks
-- ---------------------------------------------------------------------------
function M.roomInit(f)
  install()
  f.r27animFlags, f.r27puzzle, f.r27penSaved = 0, nil, nil
  for _, e in ipairs(f.entities) do
    if e.kind == 7 and e.id == REM and (e.form or 0) == 0 then e.action = e.action or 0; e.r27sq = true end
  end
end

local function npcAnimIndex(e)
  local base = e.field80 or 0
  if base < 8 then return band(base, 0xFC) + rshift(e.animationState or 4, 1) end
  return base
end

function M.frame(f, input)
  if (f.menu and f.menu.open) or f.gameOver or f.transition then return false end
  local list = {}
  for _, e in ipairs(f.entities) do list[#list + 1] = e end
  for _, e in ipairs(list) do
    if e.kind == 7 and not e.deleted then
      if e.id == REM then
        -- a script's SetAnimation since our last InitializeAnimation
        if e.r27f80 ~= nil and e.field80 ~= e.r27f80 then e.r27anim = npcAnimIndex(e); e.r27f80 = e.field80 end
        if (e.form or 0) == 0 then
          if e.action == nil then e.action = 0 end
          remType0(f, e)
        else
          remHelper(f, e)
        end
        if e.r27anim then e.forceAnim = e.r27anim end
        if e.r27freeze and e.anim and e.anim.timer then e.anim.timer = e.anim.timer + 1 end
      elseif e.id == POSTMAN and (e.script or e.pmAct) then
        postman(f, e)
      elseif e.id == TALON and e.script then
        talon(f, e)
      end
      -- the Town Minish hops of sub_0806AA50 (GravityUpdate(64.0))
      if e.r27hop then
        local nz = (e.cz or 0) - (e.czv or 0)
        if nz < 0 then e.cz, e.czv = nz, (e.czv or 0) - 0x4000 else e.cz, e.czv, e.r27hop = 0, 0, nil end
        e.z = -(e.cz or 0) / 65536
      end
    end
  end
  if not f.textbox then M.statTimers(f) end
  return false
end

function M.draw(f, font) Cucco.draw(f, font) end

return M
