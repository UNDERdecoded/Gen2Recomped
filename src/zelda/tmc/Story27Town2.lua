-- Round 27 (team A, group T2): the script natives of the Blade Brothers'
-- dojos, Stockwell's shop, Simon's simulation, Burlov / Carlov's chest game,
-- Dampe, Gorman, the farmers, the ghost brothers, Percy and Librari, ported by
-- address from the decomp (src/npc/*.c), plus the per-NPC code they need.
-- The Great Fairy (src/object/greatFairy.c) is in Town2Fairy.lua.  The scripts
-- run from the ROM (Script.lua); ports register into Native.N without
-- overwriting an existing one.
--
-- CARTRIDGE BEHAVIOUR (ported, src/npc/*.c):
--   * bladeBrothers.c: sub_08068C28 timer = gUnk_08111623[type] (type 1 steps
--     through spin -> rock breaker -> dash -> down thrust by the scrolls owned);
--     sub_08068CA0 "already taught", sub_08068CFC "may learn" (green sword,
--     boots, cape, DOUKUTU_05_EVENT, 10 hearts, the six skills, the great
--     spin), sub_08068C8C (*(u32*)(gUnk_0811162B + $D + timer * 4): only the
--     $80 techniques skip the lesson), the nine message tables (MessageNoOverlap),
--     BladeBrothers_LearnSkill (gPlayerState.skills |= 1 << (gUnk_08111740[t]
--     - 1): Link may use the move until the next room, SwordSkills.skill reads
--     it through M.learned), _ResetLastSwordMove, _CheckLastSwordMove (move ==
--     gUnk_08111740[t] -> wait gUnk_0811172A[t], condition 1), _GetScroll
--     (InitItemGetSequence(item & $7F)), _StartPlayerDemonstration
--     (ForceEquipItem(BladeBrothers_EquippedItem[t], A) + the player macro
--     gPlayerMacroBladeBrothers0..7 -- written out in data_080046A4.c),
--     sub_08068BB4 / sub_08068BD0 keep / restore the A and B items,
--     sub_08068F00 (timer 1: LoadRoomEntityList(gUnk_080F3494), the pots),
--     sub_08068F14 / sub_08068F3C (ModHealth for Scarblade / Splitblade);
--     sub_08068BEC: a frame flagged 1 -> FX_WHITE_SPLASH 16 px up + SFX_FA.
--   * pot.c Pot_Action1: a pot whose tile the rock-breaker sword hit
--     (SPECIAL_TILE_5) breaks and sets lastSwordMove = SWORD_MOVE_BREAK_POT.
--   * farmers.c: init (flipX = timer, animationState 6 / 2, kept in timer),
--     sub_0806BC94 InitializeAnimation(intVariable + (flipX ? 8 : 0) + state/2),
--     sub_0806BCB8, Farmers_MarkEenieFuserDoner (type 0), sub_0806BCE8
--     (ShowNPCDialogue gUnk_08113158[type]).
--   * gorman.c: sub_08069888 (the line by the house flags, scripted Gorman
--     answers it on any interaction), sub_0806991C / sub_080699AC (walk target
--     from gUnk_08111C5C / gUnk_08111C84, direction -> state), sub_08069A3C /
--     A60 / A84 / AA8 (the next spot from the tables by Random() & 1),
--     sub_08069ACC (--unk_68 as s8 < 1).
--   * stockwell.c: the NPC itself (action 0: script_Stockwell, anim 4;
--     action 1: talk -> TEXT_STOCKWELL 1 or the sale confirm + script_StockwellBuy,
--     the idle animations gUnk_0810FDB8 on frame flag $40, roomVars.animFlags
--     & 1 -> script_StockwellDogFood; action 2 waits for the message; action 4
--     just animates), sub_08065370 (buy: full quiver / bombs, owned shield,
--     999 shells; price, InitItemGetSequence(item, type2, 2), SHOP00 flags,
--     items_bought; the thank-you by count and price), sub_080654DC /
--     sub_080654EC the ? / ! bubbles, sub_080654FC (wait for frame flag $20
--     off), sub_08065528 (roomVars.animFlags = intVariable).
--   * simon.c: sub_0806C224 / sub_0806C280 DoExitTransition(gUnk_0813AD60 /
--     gUnk_0813AD74, written out in data/screenTransitions.c), MAROYA_WAKEUP;
--     Simon_CreateChest (FX_BIG_EXPLOSION2, TILE_TYPE_115 under him,
--     SFX_SECRET_BIG); sub_0806C2A0 mosaic fades (as plain fades, speed 4).
--   * picolyteBottle.c: the chest game's controller (type 0: three chests,
--     two when local flag $93 is clear, the prize layout from gUnk_081142CC /
--     gUnk_081142DC by (Random() & $70) >> 4) and its chests (type 1:
--     AddInteractableChest, TILE_TYPE_115 / 116 on the top layer, opened ->
--     the parent's timer / type2, CARLOV_OBJECT(2, prize) shows what it was);
--     sub_0806E140 (double / triple the stake, 999 cap), sub_0806E1E0,
--     sub_0806E1FC (DoExitTransition gUnk_0813AD4C), sub_0806E20C / E23C (the
--     prize in gRoomTransition.field_0x6), sub_0806E250 (KINSTONE_31 fused).
--   * dampe.c: sub_0806BE84 / sub_0806BEC8 (the key lines), sub_0806BEFC (the
--     graveyard gate tiles 382-385 at (14..15, 22..23)), sub_0806BF44 (on
--     screen: x - scroll_x + 16 < $110 and y - scroll_y + 24 < $D0).
--   * ghostBrothers.c: GhostBrothers_MakeInteractable, sub_08065F64 (dialogs
--     [type][max(progress - 2, 0)]), sub_08065CCC (action 3: the alpha steps of
--     gUnk_0811022E, then not drawn; the script does not run meanwhile).
--   * percy.c sub_0806B4F0 (gUnk_08112E2C[type2], incl. sub_0806B504 and
--     sub_0806B540 -- the 100 shells / 100 rupees reward state machine).
--   * librari.c sub_0806B260, sub_0806B2B4 (the line rotation by room flags).
--
-- SFX (SoundReq): SFX_FA ($FA, the blade brothers' splash), SFX_SECRET_BIG
--   ($73, Simon's chest); Town2Fairy.lua lists the Great Fairy's.
--
-- SIMPLIFIED:
--   * the temporary skill of LearnSkill is read by SwordSkills.skill (and the
--     boots' dash) only; it is cleared on the next room (UpdatePlayerSkills
--     runs in PlayerInit).
--   * the rock-breaker pot break is checked against SwordSkills' hitbox of the
--     frame (f.swordBoxNow) in the rooms with a blade brother, not through the
--     pot's tile.
--   * Stockwell's action 3 (a dog-food dialogue no script reaches) is not
--     ported; the shop's carried items (gRoomVars.shopItemType) are read from
--     f.shopItem / f.shopItem2 (Script.lua's CheckShopItem), which nothing sets
--     yet.
--   * the chest game's chests draw as their tiles (no NPC sprite);
--     gPlayerState.mobility |= $80 in the game room is not modelled.
--   * mosaic fades are plain fades.
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local Native = require("src.zelda.tmc.Native")
local N = Native.N

local M = {}
M.P = {} -- name -> port (tests)

local function reg(addr, name, fn)
  M.P[name] = fn
  if not N[addr] then N[addr] = fn end
end
local function keepGoing(a) if a then a.flags = bor(a.flags or 0, 1) end end
local function stay(a) if a then a.commandSize = 0 end end
local function T(cat, i) return cat * 256 + i end
local function msg(f, id, e) if id and id ~= 0 then f:message(id, e) end end
local function inv(f, item) return f:inventory(item) or 0 end
local function typeOf(e) return e.form or 0 end
local function type2Of(e) return e.type2 or band(e.param or 0, 0xFF) end
local function timer0(e) return band(rshift(e.param or 0, 8), 0xFF) end
local function rnd(f)
  local D = require("src.zelda.tmc.Drops")
  if D.random and D.rngOf then return D.random(D.rngOf(f)) end
  return math.random(0, 0x7FFFFFFF)
end
M.rnd = rnd

-- InitializeAnimation(e, n): a literal animation (field80 >= 8 or forced)
local function setAnim(e, n)
  e.forceAnim, e.field80 = n, n
  if e.literalAnim then e.objAnim = n; e.animIndex = nil end
end

-- ShowNPCDialogue (npcUtils.c) on a Dialog written out as {flag, flagType,
-- dialogType, a, b[, fn]}
function M.dialogue(f, e, d)
  local flag, ftype, dtype, ia, ib = d[1], d[2], d[3], d[4], d[5]
  local function check()
    if ftype == 0 then return f:flag("room", flag)
    elseif ftype == 1 then return f:flag("local", flag)
    elseif ftype == 2 then return f:flag("global", flag)
    elseif ftype == 3 then return f:kinstoneFused(flag)
    elseif ftype == 4 then return inv(f, flag) ~= 0 end
    return false
  end
  local function set(v)
    local kind = ftype == 0 and "room" or ftype == 1 and "local" or "global"
    f:setFlag(kind, flag, v)
  end
  local text = 0
  if dtype == 1 then text = ib
  elseif dtype == 2 then local was = check(); set(true); text = was and ia or ib
  elseif dtype == 3 then local was = check(); set(not was); text = was and ia or ib
  elseif dtype == 4 then text = check() and ia or ib
  elseif dtype == 5 then if d[6] then d[6](f, e) end return
  elseif dtype == 6 then text = f.player.minish and ib or ia end
  msg(f, text, e)
end
local DIALOG = { ROOM = 0, LOCAL = 1, GLOBAL = 2, KINSTONE = 3, INVENTORY = 4,
                 NONE = 0, NORMAL = 1, SET = 2, TOGGLE = 3, CHECK = 4, CALL = 5, MINISH = 6 }

-- the facing direction 0..31 (CalculateDirectionFromOffsets) and
-- GetAnimationStateForDirection-style tables
local function dir32(dx, dy)
  if dx == 0 and dy == 0 then return 0 end
  local a = math.atan2(dx, -dy)
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
M.dir32 = dir32

-- ===========================================================================
-- bladeBrothers.c
-- ===========================================================================
local ITEM = { GREEN_SWORD = 0x02, ROCS_CAPE = 0x14, PEGASUS_BOOTS = 0x15, SPIN = 0x48, ROLL = 0x49, DASH = 0x4A,
               ROCK = 0x4B, BEAM = 0x4C, GREAT = 0x4D, DOWN = 0x4E, PERIL = 0x4F, FAST_SPIN = 0x73,
               FAST_SPLIT = 0x74, LONG_SPIN = 0x75, SHIELD = 0x0D, MIRROR_SHIELD = 0x0E, QST_DOGFOOD = 0x36,
               QST_GRAVEYARD_KEY = 0x3C, SHELLS = 0x3F, FLIPPERS = 0x46, RUPEE100 = 0x58, SHELLS30 = 0x61,
               WALLET = 0x64, BOMBBAG = 0x65, LARGE_QUIVER = 0x66, BOMBS10 = 0x6C, BOMBS30 = 0x6D,
               ARROWS10 = 0x6E, ARROWS30 = 0x6F }
M.ITEM = ITEM
local TEXT_BLADE = 0x46
local SFX_FA, FX_WHITE_SPLASH, OBJ_SPECIAL_FX = 0xFA, 0x44, 0x0F

M.BB_TIMER = { [0] = 7, 0, 4, 6, 5, 8, 9, 10 }                         -- gUnk_08111623
-- gUnk_0811162B (57 bytes as written in bladeBrothers.c)
local BB_ITEMS = { [0] = ITEM.SPIN, ITEM.ROCK, ITEM.DASH, ITEM.DOWN, ITEM.ROLL, ITEM.BEAM, ITEM.PERIL, ITEM.GREAT,
                   bor(ITEM.FAST_SPIN, 0x80), bor(ITEM.FAST_SPLIT, 0x80), bor(ITEM.LONG_SPIN, 0x80) }
for i = 11, 56 do BB_ITEMS[i] = 0 end
BB_ITEMS[45], BB_ITEMS[49], BB_ITEMS[53] = 1, 1, 1
M.BB_ITEMS = BB_ITEMS
M.BB_EQUIPPED = { [0] = 0, 0, ITEM.PEGASUS_BOOTS, ITEM.ROCS_CAPE, 0, 0, 0, 0, 0, 0, 0 } -- BladeBrothers_EquippedItem
M.BB_MOVE = { [0] = 1, 4, 3, 7, 2, 5, 8, 6, 10, 11, 12 }                             -- gUnk_08111740
M.BB_WAIT = { [0] = 0, 0, 30, 0, 0, 0, 0, 30, 0, 0, 0 }                              -- gUnk_0811172A
local function bbTexts(list) local t = {} for i, v in ipairs(list) do t[i - 1] = v ~= 0 and T(TEXT_BLADE, v) or 0 end return t end
M.BB_TEXT = {
  intro = bbTexts({ 0x01, 0x09, 0x11, 0x19, 0x22, 0x2b, 0x34, 0x3d, 0x46, 0x50, 0x5a }),    -- gUnk_08111664
  ask = bbTexts({ 0x02, 0x0a, 0x12, 0x1a, 0x23, 0x2c, 0x35, 0x3e, 0x47, 0x51, 0x5b }),      -- gUnk_0811167A
  technique = bbTexts({ 0x03, 0x0b, 0x13, 0x1b, 0x24, 0x2d, 0x36, 0x3f, 0, 0, 0 }),        -- gUnk_08111690
  possession = bbTexts({ 0x04, 0x0c, 0x14, 0x1c, 0x25, 0x2e, 0x37, 0x40, 0x48, 0x52, 0x5c }), -- gUnk_081116A6
  e18 = bbTexts({ 0x05, 0x0d, 0x15, 0x1d, 0x26, 0x2f, 0x38, 0x41, 0, 0, 0 }),              -- gUnk_081116BC
  e30 = bbTexts({ 0x06, 0x0e, 0x16, 0x1e, 0x27, 0x30, 0x39, 0x42, 0x49, 0x53, 0x5d }),     -- gUnk_081116D2
  e48 = bbTexts({ 0, 0, 0, 0x1f, 0x28, 0x31, 0x3a, 0x43, 0x1f, 0x1f, 0x1f }),              -- gUnk_081116E8
  e60 = bbTexts({ 0, 0x07, 0x0f, 0x17, 0, 0x32, 0x3b, 0x44, 0, 0, 0x5e }),                 -- gUnk_081116FE
  e78 = bbTexts({ 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0, 0, 0 }),              -- gUnk_08111714
}
-- gPlayerMacroBladeBrothers0..7 (src/data/data_080046A4.c): {frames, keys}
-- pairs, PLAYER_MACRO_END ($C000) after; GBA keys A 1, B 2, right $10,
-- left $20, down $80, R $100
local A_, B_, RIGHT, LEFT, DOWN, R_ = 0x1, 0x2, 0x10, 0x20, 0x80, 0x100
M.BB_MACROS = {
  [0] = { 120, B_, 60, 0 },
  { 60, RIGHT, 4, B_, 60, 0 },
  { 4, LEFT, 120, A_, 60, 0 },
  { 1, DOWN, 4, A_, 10, 0, 10, B_, 60, 0 },
  { 4, RIGHT, 8, R_ + RIGHT, 30, 0, 1, LEFT, 30, 0, 4, LEFT, 4, R_ + LEFT, 20, 0, 6, B_, 60, 0 },
  { 1, LEFT, 30, 0, 4, B_, 60, 0, 4, B_, 60, 0 },
  { 1, LEFT, 30, 0, 4, B_, 60, 0, 4, B_, 60, 0 },
  { 1, LEFT, 120, B_, 10, 0, 4, B_, 4, 0, 4, B_, 4, 0, 4, B_, 4, 0, 4, B_, 4, 0, 4, B_, 4, 0, 4, B_, 4, 0, 4, B_, 30, 0 },
}
local PLAYER_MACRO_END = 0xC000
local DOUKUTU_05_EVENT = 0x03
local BB_LIST_POTS = 0x080F3494 -- gUnk_080F3494 (data/map/entity_headers.s)

local SKILL_BIT = { [ITEM.SPIN] = 0x1, [ITEM.ROLL] = 0x2, [ITEM.DASH] = 0x4, [ITEM.ROCK] = 0x8, [ITEM.BEAM] = 0x10,
                    [ITEM.GREAT] = 0x20, [ITEM.DOWN] = 0x40, [ITEM.PERIL] = 0x80, [ITEM.FAST_SPIN] = 0x200,
                    [ITEM.FAST_SPLIT] = 0x400, [ITEM.LONG_SPIN] = 0x800 }
M.SKILL_BIT = SKILL_BIT
-- gPlayerState.skills set by BladeBrothers_LearnSkill (this room only)
function M.learned(f, item)
  local p = f and f.player
  local b = SKILL_BIT[item]
  return (p and b and p.r27skills and band(p.r27skills, b) ~= 0) and true or false
end

local function bbTimer(e) return e.r27timer or 0 end
local function u32le(t, i) return t[i] + t[i + 1] * 0x100 + t[i + 2] * 0x10000 + t[i + 3] * 0x1000000 end

reg(0x08068C28, "sub_08068C28", function(f, e)
  local t = M.BB_TIMER[typeOf(e)] or 0
  if typeOf(e) == 1 and inv(f, ITEM.SPIN) ~= 0 then
    if inv(f, ITEM.ROCK) == 0 then t = 1
    elseif inv(f, ITEM.DASH) == 0 then t = 2
    else t = 3 end
  end
  e.r27timer = t
end)
reg(0x08068C6C, "BladeBrothers_GetScroll", function(f, e)
  f:giveItem(band(BB_ITEMS[bbTimer(e)] or 0, 0x7F), 0, 0)
end)
reg(0x08068C8C, "sub_08068C8C", function(f, e, ctx)
  ctx.condition = u32le(BB_ITEMS, 0xD + bbTimer(e) * 4)
end)
reg(0x08068CA0, "sub_08068CA0", function(f, e, ctx)
  if typeOf(e) == 1 then
    ctx.condition = 1
    if inv(f, ITEM.SPIN) == 0 then ctx.condition = 0 end
    if inv(f, ITEM.ROCK) == 0 then ctx.condition = 0 end
    if inv(f, ITEM.DASH) == 0 then ctx.condition = 0 end
    if inv(f, ITEM.DOWN) ~= 0 then return end
    ctx.condition = 0
  else
    ctx.condition = inv(f, band(BB_ITEMS[bbTimer(e)] or 0, 0x7F)) ~= 0 and 1 or 0
  end
end)
reg(0x08068CFC, "sub_08068CFC", function(f, e, ctx)
  ctx.condition = 0
  local t = bbTimer(e)
  if t > 10 then return end
  local item
  if t == 1 then item = ITEM.GREEN_SWORD
  elseif t == 2 then item = ITEM.PEGASUS_BOOTS
  elseif t == 3 then item = ITEM.ROCS_CAPE
  elseif t == 5 then if f:flag("local", DOUKUTU_05_EVENT) then ctx.condition = 1 end return
  elseif t == 6 then if (f.save.stats.maxHealth or 0) >= 10 * 8 then ctx.condition = 1 end return
  elseif t == 7 then
    for _, s in ipairs({ ITEM.SPIN, ITEM.ROLL, ITEM.DASH, ITEM.ROCK, ITEM.BEAM, ITEM.DOWN }) do
      if inv(f, s) == 0 then return end
    end
    item = ITEM.PERIL
  elseif t == 10 then item = ITEM.GREAT
  else ctx.condition = 1 return end -- 0, 4, 8, 9 (and default)
  if inv(f, item) ~= 0 then ctx.condition = 1 end
end)
for _, m in ipairs({ { 0x08068DB8, "sub_08068DB8", "intro" }, { 0x08068DD0, "sub_08068DD0", "ask" },
                     { 0x08068DE8, "sub_08068DE8", "technique" }, { 0x08068E00, "sub_08068E00", "possession" },
                     { 0x08068E18, "sub_08068E18", "e18" }, { 0x08068E30, "sub_08068E30", "e30" },
                     { 0x08068E48, "sub_08068E48", "e48" }, { 0x08068E60, "sub_08068E60", "e60" },
                     { 0x08068E78, "sub_08068E78", "e78" } }) do
  local tab = M.BB_TEXT[m[3]]
  reg(m[1], m[2], function(f, e) msg(f, tab[bbTimer(e)] or 0, e) end)
end
reg(0x08068E90, "BladeBrothers_LearnSkill", function(f, e)
  local p = f.player
  p.r27skills = band(bor(p.r27skills or 0, lshift(1, (M.BB_MOVE[bbTimer(e)] or 1) - 1)), 0xFFFF)
end)
reg(0x08068EB4, "BladeBrothers_ResetLastSwordMove", function(f) f.player.lastSwordMove = 0 end)
reg(0x08068EC4, "BladeBrothers_CheckLastSwordMove", function(f, e, ctx)
  if M.BB_MOVE[bbTimer(e)] == (f.player.lastSwordMove or 0) then
    ctx.wait = M.BB_WAIT[bbTimer(e)] or 0
    ctx.condition = 1
  else
    ctx.condition = 0
  end
end)
reg(0x08068F00, "sub_08068F00", function(f, e)
  if bbTimer(e) == 1 then f:loadEntityList(BB_LIST_POTS) end
end)
reg(0x08068F14, "sub_08068F14", function(f, e)
  if bbTimer(e) == 5 then f:modStat("health", 160) end
  if bbTimer(e) == 6 then f:modStat("health", -160); f:modStat("health", 2) end
end)
reg(0x08068F3C, "sub_08068F3C", function(f, e)
  if bbTimer(e) == 6 then f:modStat("health", 160) end
end)
reg(0x08068BB4, "sub_08068BB4", function(f, e)
  e.r27slotA, e.r27slotB = f:equipped("a") or 0, f:equipped("b") or 0
end)
reg(0x08068BD0, "sub_08068BD0", function(f, e)
  f:equip("a", e.r27slotA or 0)
  f:equip("b", e.r27slotB or 0)
end)
-- InitPlayerMacro on a macro written out here (PlayerMacro.lua's runtime)
function M.startMacro(f, list)
  if not list then f.playerMacro = nil return end
  local l = {}
  for i = 1, #list do l[i] = list[i] end
  l[#l + 1] = PLAYER_MACRO_END
  l[#l + 1] = 0
  f.playerMacro = { list = l, i = 0, waiting = 0, held = 0, prev = 0, base = 0 }
end
reg(0x08068B84, "BladeBrothers_StartPlayerDemonstration", function(f, e)
  local t = bbTimer(e)
  local item = M.BB_EQUIPPED[t] or 0
  if item ~= 0 then f:equip("a", item) end
  M.startMacro(f, M.BB_MACROS[t])
end)

-- sub_08068BEC: FX_WHITE_SPLASH 16 px above, SFX_FA
local function bbSplash(f, e)
  f:addFx(e.x, e.y - 16, OBJ_SPECIAL_FX, FX_WHITE_SPLASH)
  local fx = f.entities[#f.entities]
  if fx and fx.fx then fx.spritePriority = 1 end
  f:sound(SFX_FA)
end
M.bbSplash = bbSplash

-- pot.c: a pot under the rock-breaker blade breaks (SWORD_MOVE_BREAK_POT)
local function potBreak(f)
  local box = f.swordBoxNow
  if not box or (box.t or -1) < (f.frame or 0) - 1 then return end
  if box.r27seen == box.t then return end
  box.r27seen = box.t
  local S = require("src.zelda.tmc.SwordSkills")
  if not S.skill(f, ITEM.ROCK) then return end
  for _, o in ipairs(f.entities) do
    if o.kind == 6 and o.id == 0x05 and o.liftable and not o.deleted and not o.thrown
       and math.abs(o.x - box.x) < 6 + box.w and math.abs((o.y - 3) - box.y) < 6 + box.h then
      require("src.zelda.tmc.PotGust").breakPot(f, o)
      f.player.lastSwordMove = 4 -- SWORD_MOVE_BREAK_POT
    end
  end
end
M.potBreak = potBreak

-- ===========================================================================
-- farmers.c
-- ===========================================================================
local TEXT_FARMERS = 0x1A
local function farmerInit(f, e)
  if e.r27init then return end
  e.r27init = true
  e.flipX = timer0(e) ~= 0
  e.animationState = e.flipX and 2 or 6
  e.r27timer = e.animationState
end
reg(0x0806BC94, "sub_0806BC94", function(f, e, ctx)
  farmerInit(f, e)
  setAnim(e, (ctx.intVariable or 0) + (e.flipX and 8 or 0) + rshift(e.animationState or 0, 1))
end)
reg(0x0806BCB8, "sub_0806BCB8", function(f, e) farmerInit(f, e); e.animationState = e.r27timer end)
reg(0x0806BCC0, "Farmers_MarkEenieFuserDoner", function(f, e)
  if typeOf(e) == 0 then require("src.zelda.tmc.Fusers").markDone(f, e) end
end)
M.FARMER_DIALOG = { -- gUnk_08113158
  [0] = { 0x29, DIALOG.KINSTONE, DIALOG.CHECK, T(TEXT_FARMERS, 0x7), T(TEXT_FARMERS, 0x2) },
  { 0x29, DIALOG.KINSTONE, DIALOG.CHECK, T(TEXT_FARMERS, 0x11), T(TEXT_FARMERS, 0xd) },
}
reg(0x0806BCE8, "sub_0806BCE8", function(f, e)
  local d = M.FARMER_DIALOG[typeOf(e)]
  if d then M.dialogue(f, e, d) end
end)

-- ===========================================================================
-- gorman.c
-- ===========================================================================
local TEXT_GORMAN = 0x31
M.GORMAN_TEXT = { [0] = T(TEXT_GORMAN, 0x1), T(TEXT_GORMAN, 0x2), T(TEXT_GORMAN, 0xc), T(TEXT_GORMAN, 0xd),
                  T(TEXT_GORMAN, 0xe), T(TEXT_GORMAN, 0x15) }                                   -- gUnk_08111C50
M.GORMAN_SPOTS1 = { [0] = { 0x68, 0x1c8 }, { 0x28, 0x1c8 }, { 0x68, 0x188 }, { 0x68, 0x1c8 }, { 0x28, 0x188 }, { 0x68, 0x188 } } -- gUnk_08111C5C
M.GORMAN_SPOTS2 = { [0] = { 0x178, 0x108 }, { 0x138, 0x108 } }                                -- gUnk_08111C84
local GORMAN_STATE = { [0] = 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 0 }                   -- gUnk_08111C74 / C8C
M.GORMAN_NEXT = { A3C = { [0] = 0, 1, 0, 1, 2, 3, 2, 3, 4, 5, 4, 5 },                          -- gUnk_08111C9C
                  A60 = { [0] = 1, 2, 0, 0, 3, 4, 1, 2, 5, 5, 3, 4 },                          -- gUnk_08111CA8
                  A84 = { [0] = 0, 1, 0, 1 },                                                  -- gUnk_08111CB4
                  AA8 = { [0] = 1, 1, 0, 0 } }                                                 -- gUnk_08111CB8
local G = { GOMAN_RENTED_HOUSE = 0x47, RENTED_HOUSE_DIN = 0x2b, RENTED_HOUSE_NAYRU = 0x2c, RENTED_HOUSE_FARORE = 0x2d,
            TATEKAKE_HOUSE = 0x18, GOMAN_NEW_HOUSE = 0x48, NEW_HOUSE_DIN = 0x2e, NEW_HOUSE_NAYRU = 0x2f,
            NEW_HOUSE_FARORE = 0x30, MAROYA_WAKEUP = 0x50, MIZUKAKI_START = 0x29 }
local function gormanTalk(f, e)
  local gf = function(id) return f:flag("global", id) end
  local index
  if not gf(G.GOMAN_RENTED_HOUSE) then
    index = 0
    f:setFlag("global", G.GOMAN_RENTED_HOUSE, true)
  elseif not gf(G.RENTED_HOUSE_DIN) and not gf(G.RENTED_HOUSE_NAYRU) and not gf(G.RENTED_HOUSE_FARORE) then
    index = 1
  elseif not gf(G.TATEKAKE_HOUSE) then
    index = 2
  elseif not gf(G.GOMAN_NEW_HOUSE) then
    index = 3
    f:setFlag("global", G.GOMAN_NEW_HOUSE, true)
  elseif not gf(G.NEW_HOUSE_DIN) and not gf(G.NEW_HOUSE_NAYRU) then
    index = gf(G.NEW_HOUSE_FARORE) and 5 or 4
  else
    index = 5
  end
  msg(f, M.GORMAN_TEXT[index], e)
end
reg(0x08069888, "sub_08069888", function(f, e) gormanTalk(f, e) end)
local function gormanTarget(f, e, ctx, a, spots)
  e.r27g68 = band(rnd(f), 0x1F) + 0x3C
  local s = spots[e.r27g69 or 0] or spots[0]
  ctx.tx, ctx.ty = s[1], s[2]
  ctx.unk19 = 8
  ctx.postScriptActions = bor(ctx.postScriptActions or 0, 2)
  ctx.condition = 0
  local d = dir32(ctx.tx - e.x, ctx.ty - e.y)
  e.direction = d
  e.angle = d * 8
  e.animationState = bor(band(e.animationState or 0, 0x80), GORMAN_STATE[rshift(band(d * 8, 0xFF), 4)])
  keepGoing(a)
end
reg(0x0806991C, "sub_0806991C", function(f, e, ctx, a) gormanTarget(f, e, ctx, a, M.GORMAN_SPOTS1) end)
reg(0x080699AC, "sub_080699AC", function(f, e, ctx, a) gormanTarget(f, e, ctx, a, M.GORMAN_SPOTS2) end)
for _, k in ipairs({ { 0x08069A3C, "A3C" }, { 0x08069A60, "A60" }, { 0x08069A84, "A84" }, { 0x08069AA8, "AA8" } }) do
  local tab = M.GORMAN_NEXT[k[2]]
  reg(k[1], "sub_08069" .. k[2], function(f, e)
    e.r27g69 = tab[band(rnd(f), 1) + (e.r27g69 or 0) * 2] or 0
  end)
end
reg(0x08069ACC, "sub_08069ACC", function(f, e, ctx)
  e.r27g68 = band((e.r27g68 or 0) - 1, 0xFF)
  local s = e.r27g68 >= 0x80 and e.r27g68 - 0x100 or e.r27g68
  ctx.condition = s < 1 and 1 or 0
end)

-- ===========================================================================
-- stockwell.c
-- ===========================================================================
local TEXT_STOCKWELL = 0x2C
M.SCRIPT_STOCKWELL, M.SCRIPT_STOCKWELL_BUY, M.SCRIPT_STOCKWELL_DOGFOOD = 0x080142B0, 0x08014384, 0x080143C0
M.STOCKWELL_IDLE = { [0] = 4, 6, 6, 5, 6, 6, 6, 5, 6, 6, 6, 5, 6, 6, 6, 5 } -- gUnk_0810FDB8
M.QUIVER_SIZES = { [0] = 30, 50, 70, 99 }                                    -- gQuiverSizes
M.BOMBBAG_SIZES = { [0] = 10, 30, 50, 99 }                                   -- gBombBagSizes
local SHOP00_SAIFU, SHOP00_YAZUTSU, SHOP00_BOMBBAG = 0x55, 0x56, 0xCD
-- gUnk_080FD964 (src/itemMetaData.c, 8 bytes an item: price, unused,
-- saleItemConfirmMessageId, gotItemMessageId)
M.ROM_RANGES = { shopItemData = { 0x080FD964, 0x080FD964 + 0x80 * 8 } }
local function shopEntry(f, item)
  local t = require("src.zelda.tmc.ExtractR27A").tables(f, "shopItemData")
  if not t then return nil end
  local a = 0x080FD964 + item * 8
  return { price = t.u16(a) or 0, confirm = t.u16(a + 4) or 0, got = t.u16(a + 6) or 0 }
end
M.shopEntry = shopEntry
local function roomVars(f)
  f.r27rv = f.r27rv or { animFlags = 0 }
  return f.r27rv
end
M.roomVars = roomVars
local function newScript(f, e, addr)
  if not (f.mem and f.mem:valid(addr)) then return end
  e.script = require("src.zelda.tmc.Script").new(f.mem, addr)
end
local function animFlags(e) return e.anim and e.anim.flags or 0 end

local function stockwellUpdate(f, e)
  local act = e.action or 0
  if act == 0 then
    e.action = 1
    e.literalAnim = true
    setAnim(e, 4)
    e.talkable = true -- AddInteractableWhenBigObject
    -- SetInteractableObjectCollision(super, 0, 0, &gUnk_0810FDA0 {0, 8, 10, 16})
    -- (the box Hitboxes.interactHit tests: e.interactBox, Story27Town.lua)
    e.interactBox = { x = 0, y = 8, w = 10, h = 16, dirs = 0 }
    newScript(f, e, M.SCRIPT_STOCKWELL)
  elseif act == 1 then
    if band(roomVars(f).animFlags, 1) ~= 0 then
      e.action, e.subAction = 4, 0
      newScript(f, e, M.SCRIPT_STOCKWELL_DOGFOOD)
    elseif band(animFlags(e), 0x20) == 0 and (e.interactType or 0) ~= 0 then
      e.interactType = 0
      e.action = 2
      setAnim(e, 7)
      local item = f.shopItem or 0
      local id
      if item == 0 then
        id = T(TEXT_STOCKWELL, 0x1)
      else
        local s = shopEntry(f, item)
        id = s and s.confirm or 0
        f.messageRupees = s and s.price or 0
        e.action, e.subAction = 4, 0
        newScript(f, e, M.SCRIPT_STOCKWELL_BUY)
      end
      msg(f, id, e)
    elseif band(animFlags(e), 0x40) ~= 0 then
      setAnim(e, M.STOCKWELL_IDLE[band(rnd(f), 0xF)])
      if e.anim then e.anim.flags = band(e.anim.flags or 0, bit.bnot(0x40)) end
    else
      if e.anim then e.anim:update(1) end
    end
  elseif act == 2 then
    if e.anim then e.anim:update(1) end
    if not f:messageActive() then
      e.interactType = 0
      e.action = 1
      setAnim(e, 4)
    end
  else -- 3 (not ported, see SIMPLIFIED) / 4
    if e.anim then e.anim:update(1) end
  end
end
M.stockwellUpdate = stockwellUpdate

reg(0x08065370, "sub_08065370", function(f, e, ctx)
  local ok = true
  local item = f.shopItem or 0
  local st = f.save.stats
  local flag = 0
  local function show(id) msg(f, id, e) ctx.condition = 0 end
  if item == ITEM.ARROWS10 or item == ITEM.ARROWS30 then
    if (M.QUIVER_SIZES[st.quiverType or 0] or 30) <= (st.arrowCount or 0) then return show(T(TEXT_STOCKWELL, 0xe)) end
  elseif item == ITEM.SHIELD then
    if inv(f, ITEM.SHIELD) ~= 0 or inv(f, ITEM.MIRROR_SHIELD) ~= 0 then return show(T(TEXT_STOCKWELL, 0xb)) end
  elseif item == ITEM.BOMBS10 or item == ITEM.BOMBS30 then
    if (M.BOMBBAG_SIZES[st.bombBagType or 0] or 10) <= (st.bombCount or 0) then return show(T(TEXT_STOCKWELL, 0xe)) end
  elseif item == ITEM.WALLET then flag = SHOP00_SAIFU
  elseif item == ITEM.LARGE_QUIVER then flag = SHOP00_YAZUTSU
  elseif item == ITEM.BOMBBAG then flag = SHOP00_BOMBBAG
  elseif item == ITEM.SHELLS30 then
    if 999 <= (st.shells or 0) then msg(f, T(TEXT_STOCKWELL, 0xe), e); ok = false end
  end
  if ok then
    local s = shopEntry(f, item)
    local price = s and s.price
    if price and price <= (st.rupees or 0) then
      f:modStat("rupees", -price)
      f:giveItem(item, f.shopItem2 or 0, 2)
      f.shopItem, f.shopItem2 = 0, 0
      ctx.condition = 1
      if flag ~= 0 then f:setFlag("local", flag, true) end
      if (f.save.itemsBought or 0) <= 0xFFFFFFFE then f.save.itemsBought = (f.save.itemsBought or 0) + 1 end
      if f.save.itemsBought >= 10 then ctx.intVariable = T(TEXT_STOCKWELL, 0x11)
      elseif price >= 100 then ctx.intVariable = T(TEXT_STOCKWELL, 0x10)
      else ctx.intVariable = T(TEXT_STOCKWELL, 0xf) end
      return
    end
    if price then msg(f, T(TEXT_STOCKWELL, 0xd), e) end
  end
  ctx.condition = 0
end)
reg(0x080654DC, "sub_080654DC", function(f, e) f:bubble(e, 1, 8, -24) end)
reg(0x080654EC, "sub_080654EC", function(f, e) f:bubble(e, 0, 8, -24) end)
reg(0x080654FC, "sub_080654FC", function(f, e, ctx, a)
  if band(animFlags(e), 0x20) ~= 0 then stay(a) else keepGoing(a) end
end)
reg(0x08065528, "sub_08065528", function(f, e, ctx) roomVars(f).animFlags = ctx.intVariable or 0 end)

-- ===========================================================================
-- simon.c
-- ===========================================================================
local function exitTo(f, t) f:startTransition(t) end
-- gUnk_0813AD60 / gUnk_0813AD74 / gUnk_0813AD4C (data/screenTransitions.c)
M.TR_SIMULATION = { warpType = 1, area = 0x44, room = 0x00, endX = 0x98, endY = 0x88, layer = 1, kind = 2, facing = 4 }
M.TR_SIMON = { warpType = 1, area = 0x23, room = 0x04, endX = 0x50, endY = 0x48, layer = 1, kind = 0, facing = 4 }
M.TR_BORLOV = { warpType = 1, area = 0x23, room = 0x06, endX = 0x78, endY = 0x68, layer = 1, kind = 0, facing = 0 }
local SFX_SECRET_BIG, FX_BIG_EXPLOSION2, TILE_TYPE_115 = 0x73, 0x43, 115
reg(0x0806C224, "sub_0806C224", function(f) exitTo(f, M.TR_SIMULATION) end)
reg(0x0806C23C, "Simon_CreateChest", function(f, e)
  f:addFx(e.x, e.y, OBJ_SPECIAL_FX, FX_BIG_EXPLOSION2)
  f:objects():setTileType(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16), TILE_TYPE_115)
  f:sound(SFX_SECRET_BIG)
end)
reg(0x0806C280, "sub_0806C280", function(f)
  f:setFlag("global", G.MAROYA_WAKEUP, true)
  exitTo(f, M.TR_SIMON)
end)
reg(0x0806C2A0, "sub_0806C2A0", function(f, e, ctx)
  local v = ctx.intVariable or 0
  if v == 0 then f:fade("out", false, 4) -- FADE_IN_OUT | FADE_INSTANT | FADE_MOSAIC
  elseif v == 1 then f:fade("in", false, 4) end
end)

-- ===========================================================================
-- picolyteBottle.c (Burlov's chest game) -- Carlov's room scripts
-- ===========================================================================
local TEXT_BURLOV = 0x42
local NPC_PICOLYTE, OBJ_CARLOV = 0x51, 0x35
M.CHEST2 = { [0] = 1, 0, 0, 1, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0 }            -- gUnk_081142CC
M.CHEST3 = { [0] = 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0, 0,            -- gUnk_081142DC
             1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0 }
local TILE_CHEST, TILE_CHEST_OPEN = 0x73, 0x74

local function pbChestSetup(f, c) -- sub_0806E0DC
  c.timer = 0
  if (c.subtimer or 0xFF) ~= 0xFF then
    c.action = 2
    c.r27tile = { math.floor(c.x / 16), math.floor(c.y / 16) }
    if c.child then c.child.deleted = true; c.child = nil end
    c.talkable = true -- AddInteractableChest
    f:objects():setTileType(2, c.r27tile[1], c.r27tile[2], TILE_CHEST)
  else
    c.action = 3
    c.talkable = false
  end
end
local function pbLayout(f, e) -- sub_0806E014
  local k = rshift(band(rnd(f), 0x70), 4)
  e.type2, e.timer = 0xFF, 0xFF
  local c1, c2, c3 = e.r27ent[1], e.r27ent[2], e.r27ent[3]
  if not f:flag("local", 0x93) then
    e.r27damage = 0
    c1.subtimer, c2.subtimer = M.CHEST2[k * 2], M.CHEST2[k * 2 + 1]
    c1.x, c1.y = e.x + 0x48, e.y + 0x48
    c2.x, c2.y = e.x + 0x68, e.y + 0x48
    c3.subtimer = 0xFF
    c3.x, c3.y = e.x, e.y
  else
    e.r27damage = 1
    c1.subtimer, c2.subtimer, c3.subtimer = M.CHEST3[k * 4], M.CHEST3[k * 4 + 1], M.CHEST3[k * 4 + 2]
    c1.x, c1.y = e.x + 0x38, e.y + 0x48
    c2.x, c2.y = e.x + 0x58, e.y + 0x48
    c3.x, c3.y = e.x + 0x78, e.y + 0x48
  end
end
M.pbLayout = pbLayout
local function pbInit(f, e)
  if typeOf(e) == 0 then
    e.action = 1
    e.sprite = nil -- never drawn (PicolyteBottle_Init sets no spriteSettings.draw)
    e.r27ent = {}
    for i = 0, 2 do
      local c = f:spawn({ kind = 7, id = NPC_PICOLYTE, paramA = 1, paramB = i, x = e.x, y = e.y, pool = 0, paramC = 0 })
      if c then
        c.parent = e
        c.type2 = i
        c.sprite, c.solid, c.talkable = nil, false, false -- drawn as the chest tile
        c.r27pb = true
        c.action = 0
      end
      e.r27ent[i + 1] = c or { x = e.x, y = e.y }
    end
    e.r27u74, e.r27u76 = 0, 10
    f.r27prize = 10 -- gRoomTransition.field_0x6
    pbLayout(f, e)
    -- the chests' own init (type 1, PicolyteBottle_Init's else branch)
    for i = 1, 3 do local c = e.r27ent[i]; if c.r27pb then c.layer = 1; pbChestSetup(f, c) end end
  end
end
local function pbUpdate(f, e)
  if typeOf(e) == 0 then
    if (e.action or 0) == 0 then pbInit(f, e) return end
    if e.timer ~= 0xFF then
      if (e.r27damage or 0) ~= 0 then e.r27ent[3].timer = (e.r27ent[3].timer or 0) + 1 end
      e.r27ent[1].timer = (e.r27ent[1].timer or 0) + 1
      e.r27ent[2].timer = (e.r27ent[2].timer or 0) + 1
      e.timer = 0xFF
      f:setFlag("room", 0, true)
    end
  elseif e.action == 2 then
    if (e.interactType or 0) ~= 0 then
      e.interactType = 0
      e.parent.timer = e.type2
      e.parent.type2 = e.subtimer
    elseif (e.timer or 0) ~= 0 then
      e.timer = 0
      local o = f:spawn({ kind = 6, id = OBJ_CARLOV, paramA = 2, paramB = e.subtimer or 0, x = e.x, y = e.y, pool = 0, paramC = 0 })
      if o then o.parent = e; e.child = o; o.x, o.y = e.x, e.y end
      e.talkable = false -- RemoveInteractableObject
      f:objects():setTileType(2, e.r27tile[1], e.r27tile[2], TILE_CHEST_OPEN)
    end
  end
end
M.pbUpdate = pbUpdate

reg(0x0806E140, "sub_0806E140", function(f, e, ctx, a)
  if (e.type2 or 0) ~= 0 and e.type2 ~= nil then
    ctx.condition = 1
    e.r27u74 = (e.r27u74 or 0) + 1
    local v = e.r27u76 or 0
    v = (e.r27damage or 0) == 0 and v * 2 or v * 3
    e.r27u76 = band(v, 0xFFFF)
    if e.r27u76 >= 1000 then
      e.r27u76 = 999
      ctx.condition = 0
      f:message(T(TEXT_BURLOV, 0x1b), e)
    else
      f.messageRupees = e.r27u76
      f:message(T(TEXT_BURLOV, 0x18), e)
    end
  else
    ctx.condition = 0
    e.r27u74, e.r27u76 = 0, 0
    f:message(T(TEXT_BURLOV, 0x1c), e)
  end
  f.r27prize = e.r27u76
  keepGoing(a)
end)
reg(0x0806E1E0, "sub_0806E1E0", function(f, e)
  if not e.r27ent then return end
  pbLayout(f, e)
  for i = 1, 3 do local c = e.r27ent[i]; if c.r27pb then pbChestSetup(f, c) end end
end)
reg(0x0806E1FC, "sub_0806E1FC", function(f) exitTo(f, M.TR_BORLOV) end)
reg(0x0806E20C, "sub_0806E20C", function(f, e)
  if (f.r27prize or 0) ~= 0 then
    f.messageRupees = f.r27prize
    f:message(T(TEXT_BURLOV, 0x1f), e)
  else
    f:message(T(TEXT_BURLOV, 0x20), e)
  end
end)
reg(0x0806E23C, "sub_0806E23C", function(f)
  if (f.r27prize or 0) ~= 0 then f:modStat("rupees", f.r27prize) end
end)
reg(0x0806E250, "sub_0806E250", function(f, e, ctx, a)
  ctx.condition = f:kinstoneFused(0x31) and 1 or 0 -- KINSTONE_31
  keepGoing(a)
end)

-- ===========================================================================
-- dampe.c
-- ===========================================================================
local TEXT_DAMPE = 0x28
local DANPEI_TALK1ST = 0x69
reg(0x0806BE84, "sub_0806BE84", function(f, e, ctx)
  local texts = { [0] = T(TEXT_DAMPE, 0x1), T(TEXT_DAMPE, 0x8), T(TEXT_DAMPE, 0x4) }
  ctx.condition = 0
  local i = 1
  if not f:flag("local", DANPEI_TALK1ST) then
    i = 0
    f:setFlag("local", DANPEI_TALK1ST, true)
    ctx.condition = 1
  end
  if inv(f, ITEM.QST_GRAVEYARD_KEY) >= 2 then i = 2 end
  msg(f, texts[i], e)
end)
reg(0x0806BEC8, "sub_0806BEC8", function(f, e, ctx)
  local texts = { [0] = T(TEXT_DAMPE, 0x2), T(TEXT_DAMPE, 0x3), T(TEXT_DAMPE, 0x4) }
  local i = 0
  ctx.condition = 0
  local k = inv(f, ITEM.QST_GRAVEYARD_KEY)
  if k == 1 then i = 1; ctx.condition = 1
  elseif k >= 2 then i = 2 end
  msg(f, texts[i], e)
end)
reg(0x0806BEFC, "sub_0806BEFC", function(f)
  local O = f:objects()
  O:setTileType(1, 14, 22, 382)
  O:setTileType(1, 15, 22, 383)
  O:setTileType(1, 14, 23, 384)
  O:setTileType(1, 15, 23, 385)
end)
reg(0x0806BF44, "sub_0806BF44", function(f, e, ctx)
  local sx = math.floor(e.x) - math.floor(f.camX or 0) + 0x10
  local sy = math.floor(e.y) - math.floor(f.camY or 0) + 0x18
  ctx.condition = (sx >= 0 and sx < 0x110 and sy >= 0 and sy < 0xD0) and 1 or 0
end)

-- ===========================================================================
-- ghostBrothers.c
-- ===========================================================================
local GHOST_FADE = { 0x10, 0x2, 0x10f, 0x2, 0x20e, 0x2, 0x30d, 0x2, 0x40c, 0x2, 0x50b, 0x2, 0x60a, 0x2, 0x709, 0x2,
                     0x808, 0x2, 0x907, 0x2, 0xa06, 0x2, 0xb05, 0x2, 0xc04, 0x2, 0xd03, 0x2, 0xe02, 0x2, 0xf01, 0x2,
                     0x1000, 0x2, 0xffff } -- gUnk_0811022E
M.GHOST_FADE = GHOST_FADE
reg(0x08065D00, "GhostBrothers_MakeInteractable", function(f, e) e.talkable = true end)
local function ghostDraw(me, field, camX, camY)
  local a = me.r27alpha or 1
  if a <= 0 or me.r27undrawn then return end
  if not (love and love.graphics and field.drawSpriteList) then return end
  local g = me.drawGhost
  me.drawGhost = nil
  local r, gg, b, aa = love.graphics.getColor()
  love.graphics.setColor(r, gg, b, (aa or 1) * a)
  field:drawSpriteList({ me })
  love.graphics.setColor(r, gg, b, aa)
  me.drawGhost = g
end
M.ghostDraw = ghostDraw
-- gScreen.controls.alphaBlend: EVA (low 5 bits) of 16 is the sprite's share
local function bldAlpha(v) return math.min(band(v, 0x1F), 16) / 16 end
reg(0x08065CCC, "sub_08065CCC", function(f, e)
  e.action = 3
  e.timer = 30
  e.r27fade = 1
  e.r27alpha = bldAlpha(0x10)
  e.drawGhost = ghostDraw
end)
local function ghostUpdate(f, e)
  if e.action ~= 3 then return end
  if e.script then e.script.wait = (e.script.wait or 0) + 1 end -- case 3 does not run the script
  e.timer = (e.timer or 1) - 1
  if e.timer ~= 0 then return end
  local i = e.r27fade or 1
  if GHOST_FADE[i] ~= 0xFFFF then
    e.r27alpha = bldAlpha(GHOST_FADE[i])
    e.timer = band(GHOST_FADE[i + 1], 0xFF)
    e.r27fade = i + 2
    return
  end
  e.r27undrawn = true -- spriteSettings.draw = 0
  e.action = 1
end
M.ghostUpdate = ghostUpdate
local function townDialog(cat, a, b) return { 4, DIALOG.ROOM, DIALOG.TOGGLE, T(cat, a), T(cat, b) } end
local NORMAL_TINGLE = { 0, 0, DIALOG.NORMAL, 0, T(0x3F, 0x31) }
M.GHOST_DIALOGS = { -- dialogs[type][progress]
  [0] = { [0] = NORMAL_TINGLE, NORMAL_TINGLE, NORMAL_TINGLE, NORMAL_TINGLE, NORMAL_TINGLE, NORMAL_TINGLE, NORMAL_TINGLE, NORMAL_TINGLE },
  { [0] = townDialog(0x34, 0x17, 0x16), townDialog(0x34, 0x17, 0x16), townDialog(0x35, 0x13, 0x12),
    townDialog(0x36, 0x13, 0x12), townDialog(0x37, 0x13, 0x12), townDialog(0x38, 0x13, 0x12),
    townDialog(0x39, 0x12, 0x11), { 0, 0, DIALOG.NORMAL, 0, T(0x3A, 0x3) } },
}
reg(0x08065F64, "sub_08065F64", function(f, e)
  local t = math.max((f.save.progress or 0) - 2, 0)
  local row = M.GHOST_DIALOGS[typeOf(e)]
  local d = row and row[t]
  if d then M.dialogue(f, e, d) end
end)

-- ===========================================================================
-- percy.c
-- ===========================================================================
local TEXT_PERCY, TEXT_FESTIVAL = 0x23, 0x25
local URO_POEMN_TALK = 0x86
local function percyTalk(f, e) -- sub_0806B504
  local texts = { [0] = T(TEXT_PERCY, 0x0c), T(TEXT_PERCY, 0x0d), T(TEXT_PERCY, 0x0e), T(TEXT_PERCY, 0x10) }
  local i = 1
  if f:kinstoneFused(0x21) then i = 3 -- KINSTONE_21
  elseif not f:flag("local", URO_POEMN_TALK) then
    i = 0
    f:setFlag("local", URO_POEMN_TALK, true)
  end
  msg(f, texts[i], e)
end
local function percyReward(f, e) -- sub_0806B540 (runs as the script's command)
  local ctx, a = e.script, require("src.zelda.tmc.Script").active
  if not ctx then return end
  local s = ctx.unk18 or 0
  if s == 0 then
    msg(f, T(TEXT_PERCY, 0x12), e)
    if f:flag("local", 0x3f) then return end
    ctx.unk18 = 1
    f:setFlag("local", 0x3f, true)
  elseif s == 1 then
    if not f:messageActive() then
      ctx.unk18 = 2
      msg(f, T(TEXT_PERCY, 0x15), e)
    end
  elseif s == 2 then
    if not f:messageActive() then
      ctx.unk18 = 3
      if f.save.hasAllFigurines then f:giveItem(ITEM.RUPEE100, 0, 0)
      else f:giveItem(ITEM.SHELLS, 100, 0) end
      f:setFlag("room", 0xf, true)
    end
  elseif s == 3 then
    if f.player.state ~= "itemget" then
      ctx.wait = 0x2d
      return
    end
  end
  stay(a)
end
M.PERCY_DIALOGS = { -- gUnk_08112E2C
  [0] = { 0, 0, DIALOG.CALL, 0, 0, percyTalk },
  { 0, 0, DIALOG.NORMAL, 0, T(TEXT_PERCY, 0x12) },
  { 0, 0, DIALOG.NORMAL, 0, T(TEXT_PERCY, 0x11) },
  { 0, 0, DIALOG.NORMAL, 0, T(TEXT_FESTIVAL, 0x19) },
  { 0, 0, DIALOG.CALL, 0, 0, percyReward },
}
reg(0x0806B4F0, "sub_0806B4F0", function(f, e)
  local d = M.PERCY_DIALOGS[type2Of(e)]
  if d then M.dialogue(f, e, d) end
end)

-- ===========================================================================
-- librari.c
-- ===========================================================================
local TEXT_TOWN_MINISH1, TEXT_MINISH = 0x4A, 0x0D
reg(0x0806B260, "sub_0806B260", function(f, e, ctx)
  local texts = { [0] = T(TEXT_TOWN_MINISH1, 0x19), T(TEXT_TOWN_MINISH1, 0x1a), T(TEXT_TOWN_MINISH1, 0x22),
                  T(TEXT_TOWN_MINISH1, 0x27) }
  ctx.condition = 0
  local i
  if inv(f, ITEM.FLIPPERS) == 0 then
    if f:flag("global", G.MIZUKAKI_START) then
      i = 2
      ctx.condition = 1
    elseif not f:flag("local", 0x7a) then
      i = 0
      f:setFlag("local", 0x7a, true)
    else
      i = 1
    end
  else
    i = 3
  end
  msg(f, texts[i], e)
end)
reg(0x0806B2B4, "sub_0806B2B4", function(f, e)
  local texts = { [0] = T(TEXT_MINISH, 0xad), T(TEXT_MINISH, 0xae), T(TEXT_MINISH, 0xaf), T(TEXT_MINISH, 0xb0),
                  T(TEXT_MINISH, 0xb1) }
  local i
  if f:flag("local", 0xb3) then
    if not f:flag("room", 0) then i = 1; f:setFlag("room", 0, true)
    elseif not f:flag("room", 1) then i = 2; f:setFlag("room", 1, true)
    elseif not f:flag("room", 2) then i = 3; f:setFlag("room", 2, true)
    else
      i = 4
      f:setFlag("room", 0, false); f:setFlag("room", 1, false); f:setFlag("room", 2, false)
    end
  else
    i = 0
  end
  msg(f, texts[i], e)
end)

-- ===========================================================================
-- per-NPC code (R27A hooks)
-- ===========================================================================
local NPC = { STOCKWELL = 0x1C, GHOST_BROTHERS = 0x21, BLADE_BROTHERS = 0x30, GORMAN = 0x34, LIBRARI = 0x39,
              FARMERS = 0x3E, PICOLYTE_BOTTLE = 0x51 }
M.NPC = NPC

function M.roomInit(f)
  roomVars(f).animFlags = 0 -- gRoomVars is cleared on a room change
  f.r27rv.shopItemType = 0
  if f.player then f.player.r27skills = nil end -- UpdatePlayerSkills (PlayerInit)
  for _, e in ipairs(f.entities or {}) do
    if e.kind == 7 then
      if e.id == NPC.FARMERS then farmerInit(f, e)
      elseif e.id == NPC.LIBRARI and not e.r27init then e.r27init = true; e.animationState = timer0(e) end
    end
  end
  local F = require("src.zelda.tmc.Town2Fairy")
  if F.roomInit then F.roomInit(f) end
end

local function busy(f)
  return f.transition or (f.menu and f.menu.open) or f.gameOver
end

function M.frame(f, input)
  if busy(f) then return nil end
  local hasBlade = false
  local list = f.entities or {}
  for i = 1, #list do
    local e = list[i]
    if e and e.kind == 7 and not e.deleted then
      local id = e.id
      if id == NPC.BLADE_BROTHERS then
        hasBlade = true
        if e.anim and band(e.anim.flags or 0, 1) ~= 0 then
          e.anim.flags = band(e.anim.flags, 0xFE)
          bbSplash(f, e)
        end
      elseif id == NPC.STOCKWELL then
        stockwellUpdate(f, e)
      elseif id == NPC.GHOST_BROTHERS then
        ghostUpdate(f, e)
      elseif id == NPC.GORMAN then
        -- sub_08069838 / sub_080697EC: after the script ran (last frame),
        -- an interaction it did not take is answered by sub_08069888
        -- (script_GormanFirstHouse takes its own with CheckEntityInteractType)
        if (e.interactType or 0) ~= 0 and not f:messageActive() then
          e.interactType = 0
          gormanTalk(f, e)
        end
      elseif id == NPC.PICOLYTE_BOTTLE then
        pbUpdate(f, e)
      elseif id == NPC.FARMERS then
        farmerInit(f, e)
      end
    end
  end
  if hasBlade then potBreak(f) end
  local F = require("src.zelda.tmc.Town2Fairy")
  F.frame(f, input)
  return nil
end

-- the Great Fairy object and its natives
local Fairy = require("src.zelda.tmc.Town2Fairy")
M.spawnObject = Fairy.spawnObject

return M
