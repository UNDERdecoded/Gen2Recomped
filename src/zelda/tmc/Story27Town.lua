-- Round 27 (team A, group T1): the script natives of the Hyrule Town / castle
-- / field NPCs, ported by address from the decomp (src/npc/*.c,
-- src/object/*.c), plus the per-NPC code they need (the kid who follows Link,
-- the scripted house doors, the phonograph's song picker, the key the crow
-- drops in the graveyard).  The scripts themselves run from the ROM
-- (Script.lua); everything registers into Native.N without overwriting.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * npcUtils.c ShowNPCDialogue (M.dialogue): the Dialog word = flag (12
--     bits), flag type (4: room / local / global / kinstone / inventory),
--     dialog type (4: none, normal = b, set flag, toggle flag, check flag,
--     call func, minish), then the two text ids a / b; set / toggle / check
--     show a when the flag was set, else b.  DIALOG_CALL_FUNC calls the
--     function (townsperson.c sub_0806200C is the only one in these tables).
--   * townsperson.c: sub_08061FD8 animation = state >> 1; sub_08062048 the
--     line by story (gUnk_0810B7C0[type * 8 + max(progress - 2, 0)], TPWNSPERSON
--     only, else MessageNoOverlap(0)); sub_08061F94 FX_BIG_EXPLOSION;
--     sub_08061FB8 SetInteractableObjectCollision(1, gUnk_0810B748[i],
--     gUnk_0810B740[i]); sub_08061FF4 gUnk_0810B790[type]; sub_08061E90 the
--     wander (random direction, never straight back, speed gUnk_0810B74A[type],
--     32..95 frames, clamped 16 px around home); sub_08061FB0 hitbox off.
--   * guardWithSpear.c: sub_08064428 dialog (gUnk_0810CF4C[type2] or
--     gUnk_0810D0A4[(type2 & $7F) * 8 + progress - 2]); sub_08064198 /
--     sub_080642B8 follow Link along y / x (2 px a frame at most, FX_DASH
--     when Link dashes or lands); the sword-move checks; sub_080643D8.
--   * pina.c, carpenter.c, sturgeon.c, sittingPerson.c, librarians.c,
--     zelda.c (not the outro's sub_08066E68), nayru.c, farore.c,
--     hurdyGurdyMan.c, emma.c (DoExitTransition to the inn rooms), mama.c,
--     drLeft.c, beedle.c, teachers.c, kid.c, pita.c, marcy.c,
--     tingleSiblings.c, ministerPotho.c, kingDaltus.c, dog.c, phonograph.c
--     (USA), mayorHagen.c, brocco.c, stamp.c, houseDoorExterior.c,
--     keyStealingTakkuri.c: each function as in the decomp (see the ports).
--   * kid.c sub_08062500: the kid follows Link.  KID_HEAP (20 records of
--     Link's x, y, z, framestate, facing, layer) is filled by sub_0806252C on
--     the line from Link to the kid; each frame sub_080622F4 pushes a new
--     record when Link changed (or the last one is in the air / more than
--     24 px from Link) and puts the kid on the last one; the kid stops
--     following when Link comes out of a hole more than 120 x 80 px away.
--     While following, the kid's script does not run (Kid action 1).
--   * houseDoorExterior.c: a door record with a script (DrLeftDoor,
--     FirstHouseDoor, LonLonRanchDoor) is ENT_SCRIPTED: action 2 (no auto
--     open), its script runs, post-script actions $80 / $100 set frame 0 /
--     1 (closed doors are solid); sub_080869A4 is the push test (8 frames
--     of UP against it), sub_0808692C makes it a plain type-2 door.
--     A closed scripted door keeps Link out by its hitbox (gUnk_081206AC,
--     Hitboxes.pushOut) and Field:doorExit skips its doorway (the hooks:
--     HouseDoor.door -> M.scriptedDoor, Field:doorExit -> M.closedDoorAhead,
--     Hitboxes.interactHit -> M.interactHit for the custom interact boxes).
--   * phonograph.c (USA) sub_0806E964: UP / DOWN wrap 1..$1C ($34 after
--     GAMECLEAR), held keys step and clamp; A plays song gUnk_081145E4[n]
--     (again = SONG_STOP_ALL while it lasts), B ends it; the number shows in
--     text $3302.
--
-- SOUNDS: SFX_TASK_COMPLETE ($CD, librarians), SFX_PLY_JUMP ($7C, Zelda),
-- SFX_123 / SFX_102 (crow), SFX_RUPEE_BOUNCE ($6E, the key),
-- the phonograph's songs (BGM ids -> f:bgm) and SONG_STOP_ALL (f:bgm(nil)).
--
-- SIMPLIFIED:
--   * the home spot of the wanderers (sub_0805ACC0: a DELAYED_ENTITY_LOAD
--     property) is the spawn position.
--   * ProcessMovement0: the NPC's point against the room's solid tiles.
--   * sub_08095BE0 (the book the librarian holds up, CUTSCENE_MISC_OBJECT
--     type $18) is not drawn; the animation $C and the sound are.
--   * the phonograph's number window uses the message window (text $3302).
--   * gPlayerEntity.speed > $140 (dash puffs by the spear guards) = Link
--     dashing with the Pegasus Boots (p.dash).
--   * the crow's key (KEY_STEALING_TAKKURI type 5) bounces and lands; its
--     sprite is the object definition's animation $3C.
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local Native = require("src.zelda.tmc.Native")
local N = Native.N
local function reg(addr, fn) if not N[addr] then N[addr] = fn end end

local M = {}

-- ROM tables (USA addresses, hi exclusive), read through ExtractR27A.tables
M.ROM_RANGES = {
  tp_box = { 0x0810B740, 0x0810B748 },    -- townsperson gUnk_0810B740 (custom interact boxes)
  tp_dirs = { 0x0810B748, 0x0810B74A },   -- townsperson gUnk_0810B748 (interact directions)
  tp_speed = { 0x0810B74A, 0x0810B774 },  -- townsperson gUnk_0810B74A (speed by type)
  tp_msg = { 0x0810B790, 0x0810B7BA },    -- townsperson gUnk_0810B790 (text by type)
  tp_msg2 = { 0x0810B7BA, 0x0810B7C0 },   -- townsperson gUnk_0810B7BA (sub_0806200C)
  tp_dialog = { 0x0810B7C0, 0x0810BD00 }, -- townsperson gUnk_0810B7C0 (Dialog[21][8])
  sit_dialog = { 0x0810CC08, 0x0810CD88 },-- sittingPerson.c gUnk_0810CC08 (Dialog[6][8])
  guard_dialog = { 0x0810CF4C, 0x0810D0A4 }, -- guard.c gUnk_0810CF4C (Dialog[43])
  guard_dialog2 = { 0x0810D0A4, 0x0810D524 }, -- guard.c gUnk_0810D0A4 (Dialog[18][8])
  sturgeon_msg = { 0x0810FA54, 0x0810FA5A }, -- sturgeon gUnk_0810FA54 (3 texts)
  phono_songs = { 0x081145E4, 0x081146B8 },  -- phonograph.c gUnk_081145E4 (s16 song, length)
}

local function tables(f, name)
  local X = require("src.zelda.tmc.ExtractR27A")
  local ok, t = pcall(X.tables, f, name)
  if ok then return t end
  return nil
end
M.tables = tables

-- ------------------------------------------------------------ constants
local TEXT = function(cat, n) return cat * 256 + n end
local T_TOWN, T_TOWN2, T_TOWN3, T_TOWN4, T_TOWN5, T_TOWN6 = 0x34, 0x35, 0x36, 0x37, 0x38, 0x39
local T_PROLOGUE, T_VAATI, T_CARPENTERS, T_LIBRARY, T_CAFE = 0x10, 0x13, 0x1B, 0x49, 0x4F
local T_DR_LEFT, T_SCHOOL, T_BAKERY, T_POST, T_TINGLE, T_HAGEN, T_FESTIVAL = 0x4D, 0x3E, 0x3C, 0x40, 0x3F, 0x4C, 0x25

local ITEM = {
  GREEN_SWORD = 0x02, RED_SWORD = 0x03, MAGIC_BOOMERANG = 0x0C, GUST_JAR = 0x11,
  BOOK1 = 0x39, BOOK2 = 0x3A, BOOK3 = 0x3B, FLIPPERS = 0x46, KINSTONE = 0x5C,
  BRIOCHE = 0x68, CROISSANT = 0x69, PIE = 0x6A, CAKE = 0x6B,
  ROLL = 0x49, DASH = 0x4A, ROCK = 0x4B, BEAM = 0x4C, GREAT = 0x4D, DOWN = 0x4E, PERIL = 0x4F,
}
local FLAG = { LV1_CLEAR = 0x02, TABIDACHI = 0x15, MIZUKAKI_START = 0x29, KAKERA_COMPLETE = 0x3A,
               GAMECLEAR = 0x55, LEFT_TALK = 0xAF, SHOP03_PAN_1ST = 0x5B, MIZUKAKI_HINT3_MAYOR = 0x71,
               MAYOR_2_TALK1ST = 0x89 }
local SFX = { TASK_COMPLETE = 0xCD, PLY_JUMP = 0x7C, S123 = 0x123, S102 = 0x102, RUPEE_BOUNCE = 0x6E, DOOR = 0x111 }
M.SFX = SFX
local SPECIAL_FX, FX_BIG_EXPLOSION, FX_DASH = 0x0F, 0x35, 0x11
local NPC = { TOWNSPERSON = 0x06, KID = 0x07, PINA = 0x14, SITTING_PERSON = 0x13 }

-- ------------------------------------------------------------ helpers
local function keepGoing(a) if a then a.flags = bor(a.flags, 1) end end
local function stay(a) if a then a.commandSize = 0 end end
local function progress(f) return f.save.progress or 1 end
local function type2(e) return e.type2 or band(e.param or 0, 0xFF) end
local function timer0(e) return band(rshift(e.param or 0, 8), 0xFF) end
local function inv(f, item) return f:inventory(item) or 0 end
local function rand(f)
  local D = require("src.zelda.tmc.Drops")
  return D.random(D.rngOf(f))
end
M.rand = rand

-- InitializeAnimation / InitAnimationForceUpdate on an NPC (its field80)
local function anim(e, idx)
  e.field80 = idx
  e.forceAnim = idx
  e.lookFrame = nil
end
M.anim = anim

-- GetFacingDirection: 0..31, 0 north, clockwise
local function dir32(x0, y0, x1, y1)
  local a = math.atan2(x1 - x0, -(y1 - y0))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
M.dir32 = dir32
local function state8(d) return band(rshift(d + 2, 2), 7) end -- GetAnimationStateForDirection8
local function state4(d) return band(rshift(d + 4, 3), 3) end -- GetAnimationStateForDirection4
M.state8, M.state4 = state8, state4

-- ProcessMovement0 (SIMPLIFIED: the entity's point against solid tiles)
local SIN = {}
for i = 0, 255 + 64 do SIN[i] = math.floor(math.sin((i % 256) * math.pi / 128) * 256 + 0.5) end
local function move(f, e, dir, speed)
  local m = band(dir, 0x1F) * 8
  local nx = e.x + SIN[m] * speed / 65536
  local ny = e.y - SIN[m + 64] * speed / 65536
  local r = f.room
  if r and r.isSolid and r:isSolid(nx, ny, e.layer or 1) then return false end
  e.x, e.y = nx, ny
  return true
end
M.move = move
-- LinearMoveAngle(e, speed, angle 0..255)
local function moveAngle(e, speed, angle)
  local m = band(angle, 0xFF)
  e.x = e.x + SIN[m] * speed / 65536
  e.y = e.y - SIN[m + 64] * speed / 65536
end

local function findNpc(f, id)
  for _, o in ipairs(f.entities or {}) do
    if o.kind == 7 and o.id == id and not o.deleted then return o end
  end
  return nil
end

local function message(f, text, e) f:message(text, e) end -- MessageNoOverlap / MessageFromTarget

-- ShowNPCDialogue(ent, dialog): w = the Dialog word, a / b the texts;
-- `fn` = the DIALOG_CALL_FUNC function
function M.dialogue(f, e, w, a, b, fn)
  local flag, ftype, dtype = band(w, 0xFFF), band(rshift(w, 12), 0xF), band(rshift(w, 16), 0xF)
  local function check()
    if ftype == 0 then return f:flag("room", flag)
    elseif ftype == 1 then return f:flag("local", flag)
    elseif ftype == 2 then return f:flag("global", flag)
    elseif ftype == 3 then return f:kinstoneFused(flag) and true or false
    elseif ftype == 4 then return inv(f, flag) ~= 0 end
    return false
  end
  local kind = ({ [0] = "room", "local", "global" })[ftype]
  local text = 0
  if dtype == 2 then -- DIALOG_SET_FLAG
    local was = kind and check() or false
    if kind then f:setFlag(kind, flag, true) end
    text = was and a or b
  elseif dtype == 3 then -- DIALOG_TOGGLE_FLAG
    local was = kind and check() or false
    if kind then f:setFlag(kind, flag, not was) end
    text = was and a or b
  elseif dtype == 4 then text = check() and a or b -- DIALOG_CHECK_FLAG
  elseif dtype == 5 then
    if fn then fn(f, e) return end
    text = 0
  elseif dtype == 1 then text = b
  elseif dtype == 6 then text = f.player.minish and b or a
  end
  message(f, text, e)
  return text
end
-- a Dialog read from a ROM table
local CALL_FUNCS = {}
function M.dialogueAt(f, e, t, addr)
  if not t then message(f, 0, e) return end
  local w, a, b = t.u32(addr), t.u16(addr + 4), t.u16(addr + 6)
  local fn
  if band(rshift(w, 16), 0xF) == 5 then fn = CALL_FUNCS[band(t.u32(addr + 4), 0xFFFFFFFE)] end
  return M.dialogue(f, e, w, a, b, fn)
end
-- a Dialog written in the .c file: { flag, flagType, type, fromSelf, a, b }
local function D(flag, ftype, dtype, self, a, b)
  return { w = flag + lshift(ftype, 12) + lshift(dtype, 16) + lshift(self, 20), a = a, b = b }
end
local function show(f, e, d) return M.dialogue(f, e, d.w, d.a, d.b) end
local ROOM, LOCAL = 0, 1
local NONE_, NORMAL, SET, TOGGLE, CHECK = 0, 1, 2, 3, 4
local KINSTONE = 3

-- AddInteractableWhenBigFuser(e, offer)
local function bigFuser(e, offer)
  e.talkable = true
  if offer ~= nil then e.fuser = offer end
end
local function fuserProgress(f, e)
  local ks = f.save.kinstones
  local p = ks and ks.fuserProgress
  return (p and e.fuserId and p[e.fuserId]) or 0
end

-- SetInteractableObjectCollision(e, ignoreLayer, directions, box)
local function interactBox(e, dirs, x, y, w, h)
  e.interactBox = { x = x, y = y, w = w, h = h, dirs = dirs }
end
-- Hitboxes.interactHit hook: the custom box test of sub_080784E4
function M.interactHit(e, ix, iy, player)
  local b = e.interactBox
  if band(rshift(b.dirs or 0, rshift(player.animationState or 4, 1)), 1) ~= 0 then return false end
  local dx = ix - (math.floor(e.x) + b.x)
  local dy = iy - (math.floor(e.y) + b.y)
  return dx >= -b.w and dx < b.w and dy >= -b.h and dy < b.h
end

-- the remembered input (M.frame) for natives that read the pad
local NO_INPUT = { pressed = function() return false end, down = function() return false end }
local function input(f) return f.r27aInput or NO_INPUT end

-- ======================================================== townsperson.c
local A_TP_DIALOG = 0x0810B7C0
reg(0x08061FD8, function(f, e) anim(e, rshift(e.animationState or 4, 1)) end)
-- sub_0806200C (the DIALOG_CALL_FUNC of gUnk_0810B7C0)
local function tpBook(f, e)
  local index = 0
  if f:flag("global", FLAG.MIZUKAKI_START) and f:flag("local", 0x6B) then
    index = inv(f, ITEM.BOOK1) == 2 and 2 or 1
  end
  local t = tables(f, "tp_msg2")
  message(f, t and t.u16(0x0810B7BA + 2 * index) or 0, e)
end
CALL_FUNCS[0x0806200C] = tpBook
M.tpBook = tpBook
reg(0x08062048, function(f, e)
  if e.id == NPC.TOWNSPERSON then
    local i = math.max(progress(f) - 2, 0)
    M.dialogueAt(f, e, tables(f, "tp_dialog"), A_TP_DIALOG + ((e.form or 0) * 8 + i) * 8)
  else
    message(f, 0, e)
  end
end)
reg(0x08061F94, function(f, e) f:addFx(e.x, e.y, SPECIAL_FX, FX_BIG_EXPLOSION) end)
reg(0x08061FB8, function(f, e, ctx)
  local i = ctx.intVariable or 0
  local td, tb = tables(f, "tp_dirs"), tables(f, "tp_box")
  if not (td and tb) then return end
  local a = 0x0810B740 + 4 * i
  interactBox(e, td.u8(0x0810B748 + i), tb.s8(a), tb.s8(a + 1), tb.u8(a + 2), tb.u8(a + 3))
end)
reg(0x08061FF4, function(f, e)
  local t = tables(f, "tp_msg")
  message(f, t and t.u16(0x0810B790 + 2 * (e.form or 0)) or 0, e)
end)
local function home(e)
  if not e.r27home then
    local d = e.data or {}
    e.r27home = { x = d.x or e.x, y = d.y or e.y }
  end
  return e.r27home
end
-- the clamp of the wanderers: 16 px around home ends the walk
local function clampHome(e, ctx, hx, hy)
  local dx = math.floor(e.x) - hx
  if dx > 0x10 then e.x = hx + 0x10; ctx.unk12 = 1 end
  if dx < -0x10 then e.x = hx - 0x10; ctx.unk12 = 1 end
  local dy = math.floor(e.y) - hy
  if dy > 0x10 then e.y = hy + 0x10; ctx.unk12 = 1 end
  if dy < -0x10 then e.y = hy - 0x10; ctx.unk12 = 1 end
end
-- never straight back (the switch of sub_08061E90 / sub_08062948)
local NOT_BACK = { [0] = { 0x10, 0x08 }, [0x08] = { 0x18, 0x10 }, [0x10] = { 0x00, 0x18 }, [0x18] = { 0x08, 0x00 } }
local function turn(cur, d)
  local nb = NOT_BACK[cur or -1]
  if nb and d == nb[1] then return nb[2] end
  return d
end
M.turn = turn
reg(0x08061E90, function(f, e, ctx, a)
  local h = home(e)
  if ctx.unk18 == 0 then
    ctx.unk18 = ctx.unk18 + 1
    ctx.unk12 = band(rand(f), 0x3F) + 0x20
    local d = band(rand(f), 0x18) -- DirectionRound(Random())
    d = turn(e.direction, d)
    e.direction = d
    e.animationState = state8(d)
    local t = tables(f, "tp_speed")
    e.speed = t and t.u16(0x0810B74A + 2 * (e.form or 0)) or 0x80
  end
  local idx = rshift(e.animationState or 4, 1) + 4
  if idx ~= e.field80 then anim(e, idx) end
  move(f, e, e.direction or 0, e.speed or 0x80)
  clampHome(e, ctx, h.x, h.y)
  ctx.unk12 = ctx.unk12 - 1
  if ctx.unk12 ~= 0 then stay(a) end
end)
reg(0x08061FB0, function(f, e) e.noHitbox = true; e.solid = false end)

-- ======================================================== guardWithSpear.c
local A_GUARD1, A_GUARD2 = 0x0810CF4C, 0x0810D0A4
reg(0x08064428, function(f, e)
  local i = math.max(progress(f) - 2, 0)
  local t2 = type2(e)
  if band(t2, 0x80) == 0 then
    M.dialogueAt(f, e, tables(f, "guard_dialog"), A_GUARD1 + t2 * 8)
  else
    M.dialogueAt(f, e, tables(f, "guard_dialog2"), A_GUARD2 + (band(t2, 0x7F) * 8 + i) * 8)
  end
end)
-- sub_08064198 (axis "y") / sub_080642B8 (axis "x"): keep level with Link
local function guardFollow(f, e, axis)
  local p = f.player
  e.unk71 = e.unk71 or 0
  if e.unk71 > 0 then e.unk71 = e.unk71 - 1 end
  local unk70 = 0
  local diff = (axis == "y") and (math.floor(p.y) - math.floor(e.y)) or (math.floor(p.x) - math.floor(e.x))
  diff = math.max(-2, math.min(2, diff))
  if diff ~= 0 then
    if axis == "y" then e.direction = diff >= 1 and 16 or 0 else e.direction = diff >= 1 and 8 or 24 end
    e.speed = math.abs(diff) * 256
    local before = math.floor(axis == "y" and e.y or e.x)
    move(f, e, e.direction, e.speed)
    if before ~= math.floor(axis == "y" and e.y or e.x) then
      if p.dash and (f.frame or 0) % 6 == 0 then f:addFx(e.x, e.y, SPECIAL_FX, FX_DASH) end
      e.unk71 = 10
      e.animationState = state8(e.direction)
      local idx = rshift(e.animationState, 1) + 4 + unk70
      if idx ~= e.field80 then anim(e, idx) end
    end
  end
  if e.unk71 == 0 then
    e.animationState = state8(dir32(e.x, e.y, p.x, p.y))
    local idx = rshift(e.animationState, 1) + unk70
    if idx ~= e.field80 then anim(e, idx) end
  end
  local oldZ = e.z or 0
  e.z = p.z or 0
  if oldZ > 0 and (p.z or 0) == 0 then f:addFx(e.x, e.y, SPECIAL_FX, FX_DASH) end
end
M.guardFollow = guardFollow
reg(0x08064198, function(f, e) guardFollow(f, e, "y") end)
reg(0x080642B8, function(f, e) guardFollow(f, e, "x") end)
reg(0x080644A4, function(f) f.player.lastSwordMove = 0 end) -- GuardWithSpear_ResetLastSwordMove
reg(0x08064488, function(f)                                -- ...IfNotInSwordState
  local p = f.player
  if not (p.state == "sword" or p.ss) then p.lastSwordMove = 0 end
end)
reg(0x08064470, function(f, e, ctx)                        -- GuardWithSpear_CheckSwordMoveSpin
  ctx.condition = (f.player.lastSwordMove == 1) and 1 or 0 -- SWORD_MOVE_SPIN
end)
reg(0x080644B4, function(f, e, ctx)                        -- CheckLastSwordMove
  ctx.condition = (e.animationState == ctx.intVariable) and 1 or 0
end)
local GUARD_MSG = {
  [0] = { TEXT(T_PROLOGUE, 0x62), TEXT(T_VAATI, 0x28), TEXT(T_VAATI, 0x2B), TEXT(T_VAATI, 0x2B) },
  [1] = { TEXT(T_PROLOGUE, 0x62), TEXT(T_VAATI, 0x28), TEXT(T_VAATI, 0x2C), TEXT(T_VAATI, 0x2C) },
}
local function swordStage(f)
  if not f:flag("global", FLAG.LV1_CLEAR) then return 0 end
  if inv(f, ITEM.GREEN_SWORD) == 0 then return 1 end
  if inv(f, ITEM.RED_SWORD) == 0 then return 2 end
  return 3
end
reg(0x080643D8, function(f, e)
  message(f, GUARD_MSG[type2(e) ~= 0 and 1 or 0][swordStage(f) + 1], e)
end)

-- ======================================================== pina.c
local function pinaAnim(n) return function(f) local p = findNpc(f, NPC.PINA) if p then anim(p, n) end end end
reg(0x08063C14, pinaAnim(8))
reg(0x08063C5C, pinaAnim(9))
reg(0x08063C2C, pinaAnim(4))
reg(0x08063C44, pinaAnim(0))
reg(0x08063C74, function(f) local p = findNpc(f, NPC.PINA) if p then f:bubble(p, 0, 8, -0x18) end end)
reg(0x08063CAC, function(f, e) bigFuser(e) end)            -- Pina_MakeInteractable
local PINA_D = {}
for i = 0, 3 do PINA_D[i] = D(6, ROOM, TOGGLE, 1, TEXT(T_TOWN, 0x22), TEXT(T_TOWN, 0x21)) end
PINA_D[4] = D(6, ROOM, TOGGLE, 1, TEXT(T_TOWN2, 0x1D), TEXT(T_TOWN2, 0x1C))
PINA_D[5] = D(6, ROOM, TOGGLE, 1, TEXT(T_TOWN3, 0x1C), TEXT(T_TOWN3, 0x1B))
PINA_D[6] = D(6, ROOM, TOGGLE, 1, TEXT(T_TOWN4, 0x1D), TEXT(T_TOWN4, 0x1C))
PINA_D[7] = D(6, ROOM, TOGGLE, 1, TEXT(T_TOWN5, 0x1D), TEXT(T_TOWN5, 0x1C))
PINA_D[8] = D(6, ROOM, TOGGLE, 1, TEXT(T_TOWN6, 0x17), TEXT(T_TOWN6, 0x16))
PINA_D[9] = PINA_D[8]
reg(0x08063C90, function(f, e) show(f, e, PINA_D[math.min(progress(f), 9)]) end)

-- ======================================================== carpenter.c
reg(0x080672B0, function(f, e, ctx)
  anim(e, (ctx.intVariable or 0) + rshift(e.animationState or 4, 1) + (e.form or 0) * 8)
end)
local CARP_MSG = { [0] = TEXT(T_CARPENTERS, 0xD), TEXT(T_CARPENTERS, 0xE), 0, TEXT(T_CARPENTERS, 0x18),
                   TEXT(T_CARPENTERS, 0x19), 0, TEXT(T_CARPENTERS, 0x23), TEXT(T_CARPENTERS, 0x23), 0,
                   TEXT(T_CARPENTERS, 0x26), TEXT(T_CARPENTERS, 0x26), 0 }
reg(0x080672C8, function(f, e)
  local dialog = 0
  if inv(f, ITEM.GUST_JAR) == 0 and f:flag("global", FLAG.TABIDACHI) then dialog = 1 end
  message(f, CARP_MSG[math.floor((dialog * 2 + (e.form or 0) * 6) / 2)] or 0, e)
end)
local CARP_D = D(0xB, KINSTONE, CHECK, 1, TEXT(T_TOWN3, 0x42), TEXT(T_TOWN3, 0x41))
reg(0x08067304, function(f, e) show(f, e, CARP_D) end)

-- ======================================================== sturgeon.c
reg(0x08064D08, function(f, e) e.timer = 1 end)
reg(0x08064D10, function(f, e) e.timer = 0 end)
reg(0x08064CC0, function(f, e) bigFuser(e) end)            -- Sturgeon_MakeInteractable
reg(0x08064CD8, function(f, e)
  local tmp = 2
  if inv(f, ITEM.FLIPPERS) == 0 then tmp = f:flag("local", 0x73) and 1 or 0 end
  local t = tables(f, "sturgeon_msg")
  message(f, t and t.u16(0x0810FA54 + 2 * tmp) or 0, e)
end)

-- ======================================================== houseDoorExterior.c
local function HD() return require("src.zelda.tmc.HouseDoor") end
-- sub_08086954: Link pushing up against the closed door; the timer left
local function doorPush(f, e)
  local p = f.player
  local i = input(f)
  local touching = math.abs(p.x - e.x) < 10 + 6 and p.y >= e.y - 5 and p.y <= e.y + 12 -- sub_0800445C
  if touching then
    local near = math.abs(p.x - e.x) <= 6 and math.abs(p.y - e.y) <= 20
    local upOnly = i.down("up") and not (i.down("left") or i.down("right") or i.down("down"))
    if near and p.animationState == 0 and upOnly and not p.jumping and (p.z or 0) == 0 then
      e.timer = (e.timer or 8) - 1
    end
  else
    e.timer = 8
  end
  return e.timer
end
M.doorPush = doorPush
local function doorSolid(f, e)
  local want = (e.staticFrame or 0) == 0
  if (e.blocking or false) ~= want then HD().setSolid(f:dungeon(), e, want) end
end
-- sub_080868EC: the door's post-script actions ($80 closed, $100 open)
local function doorPost(self, e)
  local pa = self.postScriptActions or 0
  self.postScriptActions = 0
  if band(pa, 0x80) ~= 0 then e.staticFrame = 0 end
  if band(pa, 0x100) ~= 0 then e.staticFrame = 1 end
end
local DOOR_BOX = { x = 0, y = -5, w = 10, h = 4 } -- gUnk_081206AC
local function doorScriptUpdate(dg, e)
  local f = dg.field
  -- HouseDoorExterior_Type1: off screen (CheckRegionOnScreen 32x32) -> deleted
  if e.type2 == 1 and e.mgr and e.rec then
    local x, y = f.camX - e.rec.x + 240, f.camY - e.rec.y + 160
    if not (x >= 0 and x < 32 + 240 and y >= 0 and y < 32 + 160) then
      if e.blocking then HD().setSolid(dg, e, false) end
      e.deleted = true
      e.mgr.spawned[e.index] = nil
      return
    end
  end
  -- a scripted door is solid by its hitbox (sub_0800445C: Link pushed out of
  -- gUnk_081206AC), not by a solid tile: a solid door tile would be taken
  -- as a doorway by Field:doorExit and let Link in
  if e.blocking then HD().setSolid(dg, e, false) end
  if (e.staticFrame or 0) == 0 then
    local HB = require("src.zelda.tmc.Hitboxes")
    HB.pushOut(f, e, DOOR_BOX)
  end
end
-- HouseDoor.door hook: a door record with a script (ENT_SCRIPTED: action 2)
function M.scriptedDoor(dg, e, rec)
  local f = dg.field
  if not (rec and rec.script and rec.script ~= 0 and f.mem and f.mem:valid(rec.script)) then return end
  local Script = require("src.zelda.tmc.Script")
  e.script = Script.new(f.mem, rec.script)
  e.script.postActions = doorPost
  e.scriptedDoor = true
  e.extUpdate = doorScriptUpdate
end
-- Field:doorExit hook: a closed scripted door in front of Link (its hitbox,
-- gUnk_081206AC, keeps him off the doorway; the script decides)
function M.closedDoorAhead(f, p)
  for _, e in ipairs(f.entities or {}) do
    if e.scriptedDoor and not e.deleted and (e.staticFrame or 0) == 0
       and math.abs(p.x - e.x) < 16 and p.y >= e.y - 8 and p.y <= e.y + 24 then return true end
  end
  return false
end
-- an entity-data door with a script (graveyard, type2 3)
local function adoptDoor(f, e)
  if e.houseDoor or not e.script then return end
  local O = f:objects()
  local def = O and O:def(0x19, e.form)
  if def and not e.sprite then O:dress(e, def, 0) end
  e.houseDoor, e.scriptedDoor = true, true
  e.literalAnim = nil
  e.staticFrame = 0
  e.timer = 8
  e.type2 = type2(e)
  e.layer = e.layer or 1
  e.script.postActions = doorPost
  e.extUpdate = doorScriptUpdate
  f:dungeon():track(e)
  doorSolid(f, e)
end
reg(0x0808692C, function(f, e)
  if not e.houseDoor then adoptDoor(f, e) end
  e.scriptedDoor = nil
  e.type2 = 2
  e.action = (e.staticFrame or 0) == 0 and 1 or 2
  e.subAction = 0
  e.timer = 8
  e.extUpdate = HD().update
  doorSolid(f, e)
end)
reg(0x080869A4, function(f, e, ctx)
  ctx.condition = 0
  if doorPush(f, e) <= 0 then
    e.timer = 8
    ctx.condition = 1
  end
end)

-- ======================================================== sittingPerson.c
-- SittingPersion_Init: flipX = timer, facing 6 / 2, timer = that facing
local function sitInit(e)
  if e.r27sit then return end
  e.r27sit = true
  e.flipX = timer0(e) ~= 0
  e.animationState = e.flipX and 2 or 6
  e.sitTimer = e.animationState
end
reg(0x08063850, function(f, e, ctx)
  sitInit(e)
  anim(e, (ctx.intVariable or 0) + (e.flipX and 4 or 0) + rshift(e.animationState or 4, 1))
end)
reg(0x08063944, function(f, e, ctx)                       -- SittingPersion_ShowDialogue
  sitInit(e)
  ctx.condition = 0
  local i = math.max(progress(f) - 2, 0)
  M.dialogueAt(f, e, tables(f, "sit_dialog"), 0x0810CC08 + (type2(e) * 8 + i) * 8)
end)
reg(0x08063874, function(f, e) sitInit(e); e.animationState = e.sitTimer end)

-- ======================================================== librarians.c
reg(0x0806BB1C, function(f, e, ctx)
  local item = -1
  if inv(f, ITEM.BOOK1) == 1 then item = ITEM.BOOK1
  elseif inv(f, ITEM.BOOK2) == 1 then item = ITEM.BOOK2
  else
    if inv(f, ITEM.BOOK3) == 1 then item = ITEM.BOOK3 end
    if item < 1 then return end
  end
  if (ctx.intVariable or 0) == 0 then
    e.heldBook = item -- sub_08095BE0 (SIMPLIFIED: not drawn)
    anim(e, 0xC)
    f:sound(SFX.TASK_COMPLETE)
  else
    f:setInventory(item, 2)
  end
end)
local LIB_MSG = { [0] = TEXT(T_LIBRARY, 0xF), TEXT(T_LIBRARY, 0x10), TEXT(T_LIBRARY, 0x12) }
reg(0x0806BBB0, function(f, e)
  local tmp
  if inv(f, ITEM.FLIPPERS) == 0 then tmp = f:flag("global", FLAG.MIZUKAKI_START) and 1 or 0 else tmp = 2 end
  message(f, LIB_MSG[tmp], e)
end)
reg(0x0806BA34, function(f, e, ctx)
  local msg = TEXT(T_LIBRARY, 0x12)
  ctx.condition = 0
  if f:flag("local", 0x73) then
    msg = TEXT(T_LIBRARY, 0x13)
  else
    local b1, b2, b3 = inv(f, ITEM.BOOK1), inv(f, ITEM.BOOK2), inv(f, ITEM.BOOK3)
    local function got(m)
      msg = m
      ctx.condition = 1
      f:setFlag("local", 0x6B, true)
      f:setFlag("local", 0x6A, true)
    end
    if b1 == 1 then got(TEXT(T_LIBRARY, 0x6))
    elseif b2 == 1 then got(TEXT(T_LIBRARY, 0x7))
    elseif b3 == 1 then got(TEXT(T_LIBRARY, 0x8))
    elseif f:flag("local", 0x6A) then
      if not f:flag("local", 0x6B) then
        msg = TEXT(T_LIBRARY, 0x1); f:setFlag("local", 0x6B, true)
      elseif b1 == 0 then msg = TEXT(T_LIBRARY, 0x2); f:setFlag("local", 0x6B, true)
      elseif b2 == 0 then msg = TEXT(T_LIBRARY, 0x3); f:setFlag("local", 0x6D, true)
      elseif b3 == 0 then msg = TEXT(T_LIBRARY, 0x4); f:setFlag("local", 0x70, true)
      end
    end
  end
  message(f, msg, e)
end)
reg(0x0806BB7C, function(f, e, ctx)
  ctx.condition = 0
  if inv(f, ITEM.BOOK1) == 2 and inv(f, ITEM.BOOK2) == 2 and inv(f, ITEM.BOOK3) == 2 then
    f:setFlag("local", 0x73, true)
    ctx.condition = 1
  end
end)

-- ======================================================== zelda.c
reg(0x08066E50, function(f, e) anim(e, 0x4C) end)
-- sub_08066E80: the hop down (anim $16, jump on its frame flag, $1E on landing)
reg(0x08066E80, function(f, e, ctx, a)
  local st = ctx.unk18
  local fl = band(e.anim and e.anim.flags or 0, e.r27key == (e.anim and e.anim.key) and 0xFE or 0xFF)
  if st == 0 then
    ctx.unk18 = 1
    anim(e, 0x16)
  elseif st == 1 then
    if band(fl, 1) ~= 0 then
      ctx.unk18 = 2
      e.czv = 2 -- Q_16_16(2.0)
      e.r27key = e.anim and e.anim.key -- frame &= $FE
      f:sound(SFX.PLY_JUMP)
    end
  elseif st == 2 or st == 3 then
    moveAngle(e, 0x100, 0x80)
    local nz = (e.cz or 0) - (e.czv or 0)
    local air = nz < 0
    if air then e.cz, e.czv = nz, (e.czv or 0) - 0.125 else e.cz, e.czv = 0, 0 end -- GravityUpdate($2000)
    e.z = -(e.cz or 0)
    if st == 2 and (e.czv or 0) < 0 then ctx.unk18 = 3 end
    if st == 3 and not air then ctx.unk18 = 4; anim(e, 0x1E) end
  elseif st == 4 then
    if e.anim and e.anim.done and e.field80 == 0x1E and not e.forceAnim then keepGoing(a) return end
  end
  stay(a)
end)
local ZELDA_TILES = { 0x81C, 0x85C, 0x89C, 0x8DC, 0x91C, 0x95C, 0x99C, 0x9DC, 0x9DD, 0x9DE, 0x9DF, 0x9E0, 0x9E1, 0x9E2 } -- gUnk_08110BE0
M.ZELDA_TILES = ZELDA_TILES
reg(0x08066F94, function(f)
  for _, pos in ipairs(ZELDA_TILES) do f:dungeon():block(pos % 64, math.floor(pos / 64), 1, true) end
end)
reg(0x08066FB8, function(f)
  for _, pos in ipairs(ZELDA_TILES) do f:dungeon():block(pos % 64, math.floor(pos / 64), 1, false) end
end)

-- ======================================================== nayru.c / farore.c
local function oracleInteract(f, e)
  local offer = e.fuser
  if fuserProgress(f, e) ~= 0 and progress(f) < 7 then offer = 0 end
  bigFuser(e, offer)
end
reg(0x08064928, oracleInteract)                            -- Nayru_MakeInteractable
reg(0x08064A28, oracleInteract)                            -- Farore_MakeInteractable

-- ======================================================== hurdyGurdyMan.c
reg(0x0806E440, function(f, e) bigFuser(e) end)            -- HurdyGurdyMan_MakeInteractable
local HG_D = {}
local HG_T = { { 0x52, 0x51 }, { 0x52, 0x51 }, { 0x54, 0x53 }, { 0x56, 0x55 }, { 0x58, 0x57 }, { 0x5A, 0x59 },
               { 0x5C, 0x5B }, { 0x5E, 0x5D } }
for i, t in ipairs(HG_T) do HG_D[i - 1] = D(0x59, LOCAL, TOGGLE, 1, TEXT(T_CAFE, t[1]), TEXT(T_CAFE, t[2])) end
reg(0x0806E418, function(f, e) show(f, e, HG_D[math.min(math.max(progress(f) - 2, 0), 7)]) end)

-- ======================================================== emma.c
local function innRoom(room, x)
  return function(f)
    f:startTransition({ warpType = 1, area = 0x21, room = room, endX = x, endY = 0x38, layer = 1,
                        kind = 0, facing = 4 })
  end
end
reg(0x0806C578, innRoom(0x05, 0x50))                       -- gUnk_0813AD10: the west room
reg(0x0806C588, innRoom(0x06, 0x50))                       -- gUnk_0813AD24: the middle room
reg(0x0806C598, innRoom(0x07, 0x60))                       -- gUnk_0813AD38: the east room

-- ======================================================== mama.c
reg(0x0806C4F8, function(f, e) bigFuser(e) end)            -- Mama_MakeInteractable
reg(0x0806C4A8, function(f, e, ctx)
  if e.anim and e.anim.done and not e.forceAnim then
    local p = f.player
    local tmp = state4(dir32(e.x, e.y, p.x, p.y))
    e.animationState = tmp * 2
    anim(e, tmp)
    ctx.condition = 1
  else
    ctx.condition = 0
  end
end)
local MAMA_D = {}
local MAMA_T = { { 3, 2 }, { 3, 2 }, { 3, 2 }, { 3, 2 }, { 0xD, 0xC }, { 0x1B, 0x1A }, { 0x27, 0x26 }, { 0x33, 0x32 },
                 { 0x3F, 0x3E }, { 0x49, 0x48 } }
for i, t in ipairs(MAMA_T) do MAMA_D[i - 1] = D(1, ROOM, TOGGLE, 1, TEXT(T_CAFE, t[1]), TEXT(T_CAFE, t[2])) end
reg(0x0806C4DC, function(f, e) show(f, e, MAMA_D[math.min(progress(f), 9)]) end)

-- ======================================================== drLeft.c
reg(0x0806C09C, function(f, e) interactBox(e, 0, 0, 6, 8, 12) end) -- gUnk_081133B4
reg(0x0806C00C, function(f, e, ctx) ctx.condition = (e.anim and e.anim.done and not e.forceAnim) and 1 or 0 end)
local LEFT_MSG = { [0] = TEXT(T_DR_LEFT, 0x7), TEXT(T_DR_LEFT, 0x8), TEXT(T_DR_LEFT, 0x9), TEXT(T_DR_LEFT, 0xA),
                   TEXT(T_DR_LEFT, 0xA), TEXT(T_DR_LEFT, 0x5), TEXT(T_DR_LEFT, 0x6), TEXT(T_DR_LEFT, 0xF) }
reg(0x0806C038, function(f, e)
  local index = progress(f) - 5
  if index ~= 0 then index = 0 end
  if inv(f, ITEM.FLIPPERS) == 0 then
    if inv(f, ITEM.BOOK2) == 0 then
      index = 6
      if not f:flag("local", FLAG.LEFT_TALK) then index = 5; f:setFlag("local", FLAG.LEFT_TALK, true) end
    else
      index = 7
      if inv(f, ITEM.BOOK2) > 1 then index = 0 end
    end
  end
  message(f, LEFT_MSG[index], e)
end)

-- ======================================================== beedle.c
local BEEDLE_ITEMS = { [0] = 0x00, 0x2D, 0x2C, 0x29, 0x2A, 0x2B, 0x2E, 0x00 } -- gBeedleItems
reg(0x080634E4, function(f, e, ctx) ctx.intVariable = type2(e) end) -- Beedle_GetObjectType
reg(0x080634EC, function(f, e) f.shopItem = BEEDLE_ITEMS[type2(e)] or 0 end) -- gRoomVars.shopItemType
-- GetBottleContaining: the bottle's number (1..4), 0 when none
function M.bottleContaining(f, item)
  local b = f.save.bottles or {}
  for i = 1, 4 do if b[i] == item then return i end end
  return 0
end
reg(0x08063504, function(f, e, ctx)                        -- Beedle_IsBottleInInventory
  ctx.condition = M.bottleContaining(f, BEEDLE_ITEMS[type2(e)] or 0) ~= 0 and 1 or 0
end)

-- ======================================================== keyStealingTakkuri.c
-- the key (type 5): Type5_Init / Action1 / Type1_Action1
local function keyUpdate(dg, k)
  local f = dg.field
  local par = k.parent
  if not par or par.deleted then k.deleted = true return end
  if k.action == 1 then
    moveAngle(k, k.speed, band(k.direction, 0x1F) * 8) -- LinearMoveUpdate
    -- BounceUpdate(Q_8_8(32))
    local nz = (k.cz or 0) - (k.czv or 0)
    local st
    if nz < 0 then k.cz, k.czv = nz, (k.czv or 0) - 0.125; st = 2
    else
      k.cz = 0
      local v = -((k.czv or 0) - 0.125)
      v = v / 2 + v / 8
      if v >= 0.75 then k.czv = v; st = 1 else k.czv = 0; st = 0 end
    end
    if st < 2 then
      if k.timer ~= 0 then k.timer = k.timer - 1; k.czv = 1 -- Q_16_16(1.0)
      else k.action = 2; k.layer = f.player.layer or 1 end
      f:sound(SFX.RUPEE_BOUNCE)
    end
    k.z = -(k.cz or 0)
  end
  if (par.subtimer or 0) ~= 0 then k.x, k.y, k.z = par.x, par.y, (par.z or 0) + 8 end -- PositionRelative(0, $80000)
  k.hidden = par.hidden
end
M.keyUpdate = keyUpdate
reg(0x0809E0A0, function(f, e)
  local O = f:objects()
  local p = f.player
  local k = { kind = 6, id = 0x97, form = 5, x = p.x, y = p.y, z = 8, cz = -8, czv = 2, animationState = 0,
              field80 = 0, field82 = 0, interactType = 0, action = 1, direction = 0x18, speed = 0x100,
              timer = 1, layer = 2, parent = e, extUpdate = keyUpdate, anim = require("src.zelda.tmc.Anim").new() }
  local def = O and O:def(0x97, 5)
  if def then O:dress(k, def, 0x3C); k.objAnim = 0x3C end
  f:sound(SFX.RUPEE_BOUNCE)
  e.child = k
  e.subtimer = 0
  f:dungeon():track(k)
  f.entities[#f.entities + 1] = k
end)
reg(0x0809E0D4, function(f, e, ctx, a)
  if ctx.unk18 == 0 then
    local t = e.child
    if t and not t.deleted then
      if (t.action or 0) < 2 then stay(a) return end
    else t = f.player end
    ctx.unk18 = 1
    -- LookAt
    ctx.unk19 = 8
    ctx.tx, ctx.ty = t.x, t.y
    e.direction = dir32(e.x, e.y, t.x, t.y)
    f:sound(SFX.S123)
    stay(a)
    return
  end
  local t = e.child
  local tx, ty
  if t and not t.deleted then tx, ty = math.floor(t.x), math.floor(t.y) else tx, ty = math.floor(ctx.tx), math.floor(ctx.ty) end
  ctx.unk19 = ctx.unk19 - 1
  if ctx.unk19 == 0 then
    ctx.unk19 = 8
    e.direction = dir32(e.x, e.y, tx, ty)
  end
  local bx, by = math.floor(e.x) - tx, math.floor(e.y) - ty
  moveAngle(e, e.speed or 0x100, band(e.direction or 0, 0x1F) * 8)
  if (math.floor(e.x) - tx) * bx < 1 and (math.floor(e.y) - ty) * by < 1 then
    e.x, e.y = tx, ty
    e.subtimer = 1
    f:sound(SFX.S102)
  else
    stay(a)
  end
end)

-- ======================================================== teachers.c
reg(0x0806C674, function(f, e) bigFuser(e) end)            -- Teachers_MakeInteractable
local TEACH = {
  [0] = { [0] = D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 1)), D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 1)),
          D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 1)), D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 1)),
          D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 1)), D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 1)),
          D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 9)), D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 9)) },
  [1] = { [0] = D(0xA, ROOM, TOGGLE, 1, TEXT(T_TOWN, 0x35), TEXT(T_TOWN, 0x34)),
          D(0xA, ROOM, TOGGLE, 1, TEXT(T_TOWN, 0x35), TEXT(T_TOWN, 0x34)),
          D(0xA, ROOM, TOGGLE, 1, TEXT(T_TOWN2, 0x28), TEXT(T_TOWN2, 0x27)),
          D(0xA, ROOM, TOGGLE, 1, TEXT(T_TOWN3, 0x25), TEXT(T_TOWN3, 0x24)),
          D(0, ROOM, TOGGLE, 1, TEXT(T_SCHOOL, 3), TEXT(T_SCHOOL, 2)),
          D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 6)), D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 0xA)),
          D(0, 0, NORMAL, 1, 0, TEXT(T_SCHOOL, 0xA)) },
}
reg(0x0806C70C, function(f, e)
  local row = TEACH[e.form or 0] or TEACH[0]
  show(f, e, row[math.min(math.max(progress(f) - 2, 0), 7)])
end)

-- ======================================================== kid.c
local KID_HEAP_COUNT = 0x14
local function framestate(p)
  if p.state == "hole" then return 0x16 end -- PL_STATE_HOLE
  if p.state == "sword" or p.ss then return 2 end
  return 0
end
local function playerRec(f)
  local p = f.player
  return { x = math.floor(p.x), y = math.floor(p.y), z = math.floor(p.z or 0), fs = framestate(p),
           st = p.animationState or 4, layer = p.layer or 1 }
end
local function same(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z and a.fs == b.fs and a.st == b.st and a.layer == b.layer
end
-- sub_0806252C: the records on the line from Link to the kid
function M.kidFill(f, e)
  local it = playerRec(f)
  local function fixedDiv(n, d) local q = n * 256 / d return q >= 0 and math.floor(q) or -math.floor(-q) end
  local dx = fixedDiv(it.x - math.floor(e.x), KID_HEAP_COUNT)
  local dy = fixedDiv(it.y - math.floor(e.y), KID_HEAP_COUNT)
  local heap = {}
  for i = 0, KID_HEAP_COUNT - 1 do
    heap[i] = { x = it.x - math.floor(i * dx / 256), y = it.y - math.floor(i * dy / 256), z = it.z, fs = it.fs,
                st = e.animationState or 4, layer = e.layer or 1 } -- (i * dx) >> 8, arithmetic
  end
  e.kidHeap = heap
end
local function shiftRight(heap)
  for i = KID_HEAP_COUNT - 1, 1, -1 do heap[i] = heap[i - 1] end
end
-- sub_080622F4: one frame of following
function M.kidFollow(f, e)
  local heap = e.kidHeap
  local p = f.player
  local it = playerRec(f)
  if heap[0].fs == 0x16 and it.fs ~= 0x16 then
    if math.abs(math.floor(e.x) - math.floor(p.x)) > 120 or math.abs(math.floor(e.y) - math.floor(p.y)) > 80 then
      e.kidFollowing = false
      return
    end
    M.kidFill(f, e)
    heap = e.kidHeap
  end
  local moving = 0
  e.unk69 = e.unk69 or 0
  if not same(it, heap[0]) then
    shiftRight(heap)
    heap[0] = it
    moving = 4
    if e.unk69 > 0 then e.unk69 = e.unk69 - 1 end
  else
    local last = heap[KID_HEAP_COUNT - 1]
    if last.z > 0 then -- (z < 0 on the cartridge: in the air)
      shiftRight(heap); moving = 4
    else
      local dx, dy = math.floor(p.x) - last.x, math.floor(p.y) - last.y
      if math.floor(math.sqrt(dx * dx + dy * dy)) > 0x18 then shiftRight(heap); moving = 4 end
    end
  end
  local last = heap[KID_HEAP_COUNT - 1]
  e.x, e.y, e.z = last.x, last.y, last.z
  e.animationState, e.layer = last.st, last.layer
  if e.unk69 > 0 then e.unk69 = e.unk69 - 1 end
  local idx = moving + rshift(e.animationState, 1)
  if (e.form or 0) == 6 then idx = idx + 0x10 end
  if not (idx == e.field80 or (moving == 0 and e.unk69 > 0)) then
    anim(e, idx)
    e.unk69 = 0x1E
  end
end
-- while following, the kid's script does not run (Kid action 1)
local KidRun = {}
KidRun.__index = KidRun
function KidRun:run(e, f)
  if not e.kidFollowing then e.script = self.inner; return true end
  if e.kidTalk then
    if f:messageActive() then return true end
    e.kidTalk = nil
  end
  if (e.interactType or 0) ~= 0 then
    e.interactType = 0
    e.kidTalk = true
    local talk = N[0x0806265C]
    if talk then talk(f, e, self.inner) end
    return true
  end
  M.kidFollow(f, e)
  if not e.kidFollowing then e.script = self.inner end
  return true
end
function KidRun:postActions() end
reg(0x08062500, function(f, e, ctx)
  e.kidFollowing = true
  e.talkable = false -- RemoveInteractableObject
  e.noHitbox, e.solid = true, false
  M.kidFill(f, e)
  if e.script and getmetatable(e.script) ~= KidRun then
    e.script = setmetatable({ inner = e.script, stopped = false }, KidRun)
  end
end)
reg(0x08062948, function(f, e, ctx, a)
  local h = home(e)
  if ctx.unk18 == 0 then
    ctx.unk18 = ctx.unk18 + 1
    ctx.unk12 = band(rand(f), 0x3F) + 0x20
    local d = band(rand(f), 0x18)
    d = turn(e.direction, d)
    e.direction = d
    e.animationState = state8(d)
    e.speed = 0x80
  end
  local idx = rshift(e.animationState or 4, 1) + 4
  if idx ~= e.field80 then anim(e, idx) end
  move(f, e, e.direction or 0, e.speed or 0x80)
  clampHome(e, ctx, h.x, h.y)
  ctx.unk12 = ctx.unk12 - 1
  if ctx.unk12 ~= 0 then stay(a) end
end)

-- ======================================================== pita.c
reg(0x08062EB8, function(f)                                -- RemoveAllBakedGoods
  for _, i in ipairs({ ITEM.BRIOCHE, ITEM.CROISSANT, ITEM.PIE, ITEM.CAKE }) do f:setInventory(i, 0) end
end)
local PRIZE = { [0] = 0x20, 0x40, 0x60, 0x80, 0xFF }
local PRIZE_W = { 0x10, 0x10, 0x10, 0x20, 0x20, 0x30, 0x30, 0x30 }
local PRIZE_K = { [0] = 0x6E, 0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75 }
-- GetRandomByWeight
function M.byWeight(w, r)
  r = band(r, 0xFF)
  local i = 0
  repeat i = i + 1; r = r - (w[i] or 0) until r < 0 or i > #w
  return i - 1
end
reg(0x08062EDC, function(f, e, ctx)
  local tmp = 0 -- (uninitialised on the cartridge; Link always holds one here)
  if inv(f, ITEM.BRIOCHE) ~= 0 then tmp = 0 end
  if inv(f, ITEM.CROISSANT) ~= 0 then tmp = 1 end
  if inv(f, ITEM.PIE) ~= 0 then tmp = 2 end
  if inv(f, ITEM.CAKE) ~= 0 then tmp = 3 end
  if not f:flag("local", FLAG.SHOP03_PAN_1ST) then f:setFlag("local", FLAG.SHOP03_PAN_1ST, true); tmp = 4 end
  if band(rand(f), 0xFF) > PRIZE[tmp] then ctx.condition = 0 return end
  local k = PRIZE_K[M.byWeight(PRIZE_W, rand(f))]
  f:giveItem(ITEM.KINSTONE, k, 1) -- InitItemGetSequence(ITEM_KINSTONE, k, 1)
  message(f, TEXT(T_BAKERY, 0x5), e)
  ctx.condition = 1
end)

-- ======================================================== marcy.c
local MARCY_MSG = { [0] = TEXT(T_POST, 0x4), TEXT(T_POST, 0xB), TEXT(T_POST, 0x9), TEXT(T_POST, 0xA) }
reg(0x08062D18, function(f, e, ctx)
  local tmp = 0
  local order = { { ITEM.PERIL, 0x26, 7 }, { ITEM.DOWN, 0x25, 6 }, { ITEM.GREAT, 0x24, 5 }, { ITEM.BEAM, 0x23, 4 },
                  { ITEM.ROCK, 0x22, 3 }, { ITEM.DASH, 0x21, 2 }, { ITEM.ROLL, 0x20, 1 } }
  for _, o in ipairs(order) do
    if inv(f, o[1]) ~= 0 and not f:flag("local", o[2]) then tmp = o[3] end
  end
  e.type2 = tmp
  tmp = 0
  -- CheckFlags($1C1F): local flags $1F..$3A all set
  local all = true
  for i = 0x1F, 0x1F + 0x1C - 1 do if not f:flag("local", i) then all = false break end end
  if all then tmp = 1
  elseif f:flag("local", 0x8C) then tmp = 2; f:setFlag("local", 0x8C, false)
  elseif f:flag("local", 0x8B) then tmp = 3 end
  message(f, MARCY_MSG[tmp], e)
  ctx.condition = tmp == 0 and 1 or 0
end)
reg(0x08062E14, function(f) f:setFlag("local", 0x8B, true) end)

-- ======================================================== tingleSiblings.c
reg(0x08064EA4, function(f, e)                             -- TingleSiblings_MakeInteractable
  local offer = e.fuser
  local t = e.form or 0
  if t == 0 and f:kinstoneFused(0x59) and inv(f, ITEM.MAGIC_BOOMERANG) == 0 then offer = 0 end
  if t == 3 and f:kinstoneFused(0x5A) and inv(f, ITEM.MAGIC_BOOMERANG) == 0 then offer = 0 end
  bigFuser(e, offer)
end)
local TINGLE_MSG = {
  [0] = { 0x1, 0x2, 0x3, 0x4, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F },
  [1] = { 0x5, 0x6, 0x7, 0x7, 0x20, 0x21, 0x22, 0x23, 0x24 },
  [2] = { 0x8, 0x9, 0x9, 0x9, 0x25, 0x26, 0x27, 0x28, 0x29 },
  [3] = { 0xA, 0xB, 0xC, 0xD, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E },
}
local TINGLE_ROOMFLAG = { [0] = 0, 0, 0, 0 } -- gUnk_0810FC50
local function fusedCount(f)
  local n = 0
  local fz = f.save.kinstones and f.save.kinstones.fused or {}
  for id, v in pairs(fz) do if v and type(id) == "number" and id >= 1 and id <= 100 then n = n + 1 end end
  return n
end
M.fusedCount = fusedCount
reg(0x08064F28, function(f, e, ctx)
  ctx.condition = 0
  local t = math.min(e.form or 0, 3)
  local rf = TINGLE_ROOMFLAG[t]
  local u, remaining
  if not f:flag("room", rf) then
    local b = fuserProgress(f, e)
    if b >= 2 then u = 3
    else
      u = 2
      if inv(f, ITEM.MAGIC_BOOMERANG) == 0 then u = (b ~= 0) and 1 or 0 end
    end
    remaining = -1
  elseif not f:flag("global", FLAG.KAKERA_COMPLETE) then
    remaining = 100 - fusedCount(f)
    if remaining < 1 then
      u, remaining = 8, 0
      f:setFlag("global", FLAG.KAKERA_COMPLETE, true)
      ctx.condition = 1
    else
      u = 7
      if remaining > 9 then u = 6 end
      if remaining > 0x27 then u = 5 end
      if remaining > 0x45 then u = 4 end
    end
  else
    u, remaining = 8, 0
  end
  if remaining > 0 then f.messageRupees = remaining end -- gMessage.rupees
  message(f, TEXT(T_TINGLE, TINGLE_MSG[t][u + 1]), e)
  f:setFlag("room", rf, not f:flag("room", rf))
end)

-- ======================================================== ministerPotho.c / kingDaltus.c
local POTHO_MSG = { TEXT(T_PROLOGUE, 0x5A), TEXT(T_VAATI, 0x27), TEXT(T_VAATI, 0x2A), TEXT(T_VAATI, 0x2F) }
reg(0x08066904, function(f, e) message(f, POTHO_MSG[swordStage(f) + 1], e) end)
reg(0x0806672C, function(f, e) bigFuser(e) end)            -- KingDaltus_MakeInteractable

-- ======================================================== dog.c
reg(0x08069EE8, function(f, e) e.action = 5 end)

-- ======================================================== phonograph.c (USA)
local PHONO = { delay = 20, rate = 4 } -- SIMPLIFIED: gInput.menuScrollKeys' repeat
local function phonoShow(f, e, n)
  local bytes = f.assets and f.assets.message and f.assets:message(0x3302)
  if not bytes then f.r27phono = nil return end
  local TB = require("src.zelda.tmc.TextBox")
  local tb = TB.new(bytes, { number = ("%3d"):format(n), assets = f.assets, playerName = f.save.name })
  tb.scale = 8
  f.r27phono = { box = tb }
end
local function phonoSong(f, n)
  local t = tables(f, "phono_songs")
  if not t then return 0, -1 end
  return t.s16(0x081145E4 + 4 * n), t.s16(0x081145E4 + 4 * n + 2)
end
M.phonoSong = phonoSong
-- SoundReq on a song id: songs below the SFX range play as music
local function soundReq(f, id)
  if id < 0x64 then if id > 0 then f:bgm(id) end else f:sound(id) end
end
local function phonograph(f, e, ctx, a)
  local i = input(f)
  e.phonoSel = e.phonoSel or 1      -- Phonograph action 0: unk_68 = 1
  e.phonoPlaying = e.phonoPlaying or -1 -- unk_6a = -1
  if i.pressed("b") then f.r27phono = nil return end -- sub_08050384
  if ctx.unk18 == 0 then
    ctx.unk18 = 1
    e.phonoT = 0
    phonoShow(f, e, e.phonoSel)
  end
  local val2 = f:flag("global", FLAG.GAMECLEAR) and 0x34 or 0x1C
  local val = e.phonoSel
  local up, down = i.down("up"), i.down("down")
  if i.pressed("up") or i.pressed("down") then
    val = val + (i.pressed("up") and 1 or -1)
    if val <= 0 then val = val2 end
    if val > val2 then val = 1 end
    e.phonoHold = 0
  elseif up or down then
    e.phonoHold = (e.phonoHold or 0) + 1
    if e.phonoHold >= PHONO.delay and (e.phonoHold - PHONO.delay) % PHONO.rate == 0 then
      val = val + (up and 1 or -1)
      if val <= 0 then val = 1 end
      if val > val2 then val = val2 end
    end
  else
    e.phonoHold = 0
  end
  if val ~= e.phonoSel then
    phonoShow(f, e, val)
    if e.phonoT > 0 then e.phonoT = e.phonoT - 1 end
  end
  e.phonoSel = val
  if i.pressed("a") then
    if e.phonoSel ~= e.phonoPlaying or e.phonoT == 0 then
      local song, len = phonoSong(f, e.phonoSel)
      soundReq(f, song)
      e.phonoPlaying = e.phonoSel
      e.phonoT = len
    else
      f:bgm(nil) -- SoundReq(SONG_STOP_ALL)
      e.phonoPlaying = 0
    end
  end
  if e.phonoT > 0 then
    e.phonoT = e.phonoT - 1
    if e.phonoT <= 0 then e.phonoPlaying, e.phonoT = 0, 0 end
  end
  stay(a)
end
M.phonograph = phonograph
reg(0x0806E964, function(f, e, ctx, a)
  phonograph(f, e, ctx, a)
  if f.r27phono then f.r27phonoAlive = true end -- the window stays while the native runs
end)

-- ======================================================== mayorHagen.c
local HAGEN = {}
for i = 0, 3 do HAGEN[i] = D(0x89, LOCAL, SET, 1, TEXT(T_HAGEN, 0xD), TEXT(T_HAGEN, 0x1)) end
for i, n in ipairs({ 0xE, 0xE, 0xF, 0x10, 0x11, 0x12, 0x14, 0x2, 0xC, 0x3, 0x4 }) do HAGEN[3 + i] = D(0, 0, NORMAL, 1, 0, TEXT(T_HAGEN, n)) end
reg(0x0806CE80, function(f, e)
  local v = progress(f)
  if v == 5 then
    if inv(f, ITEM.FLIPPERS) == 0 then
      if f:flag("local", 0x70) then
        if not f:flag("local", FLAG.MIZUKAKI_HINT3_MAYOR) then v = 0xB; f:setFlag("local", FLAG.MIZUKAKI_HINT3_MAYOR, true)
        else v = 0xC end
      else
        v = 0xA
      end
    else
      if not f:flag("local", FLAG.MAYOR_2_TALK1ST) then v = 0xD; f:setFlag("local", FLAG.MAYOR_2_TALK1ST, true)
      else v = 0xE end
    end
  end
  show(f, e, HAGEN[math.min(v, 0xE)])
end)

-- ======================================================== brocco.c / stamp.c
local BROCCO = { [0] = D(0, 0, NORMAL, 1, 0, TEXT(T_FESTIVAL, 0x10)), D(0, 0, NORMAL, 1, 0, TEXT(T_FESTIVAL, 0x10)),
                 D(5, ROOM, TOGGLE, 1, TEXT(T_TOWN, 0x24), TEXT(T_TOWN, 0x23)),
                 D(5, ROOM, TOGGLE, 1, TEXT(T_TOWN, 0x24), TEXT(T_TOWN, 0x23)),
                 D(5, ROOM, TOGGLE, 1, TEXT(T_TOWN2, 0x1F), TEXT(T_TOWN2, 0x1E)),
                 D(5, ROOM, TOGGLE, 1, TEXT(T_TOWN3, 0x1E), TEXT(T_TOWN3, 0x1D)),
                 D(5, ROOM, TOGGLE, 1, TEXT(T_TOWN4, 0x1F), TEXT(T_TOWN4, 0x1E)),
                 D(5, ROOM, TOGGLE, 1, TEXT(T_TOWN5, 0x1F), TEXT(T_TOWN5, 0x1E)),
                 D(5, ROOM, TOGGLE, 1, TEXT(T_TOWN6, 0x19), TEXT(T_TOWN6, 0x18)),
                 D(5, ROOM, TOGGLE, 1, TEXT(T_TOWN6, 0x19), TEXT(T_TOWN6, 0x18)) }
reg(0x080636D8, function(f, e) show(f, e, BROCCO[math.min(progress(f), 9)]) end)
local STAMP = { [0] = D(0, ROOM, TOGGLE, 1, TEXT(T_POST, 0x1), TEXT(T_POST, 0x0)),
                D(0, ROOM, TOGGLE, 1, TEXT(T_POST, 0x3), TEXT(T_POST, 0x2)) }
reg(0x08062CBC, function(f, e) show(f, e, STAMP[f:kinstoneFused(0x2C) and 1 or 0]) end)

-- ======================================================== module hooks
-- the pad of this frame, for the natives that read gInput (phonograph,
-- the door push test); never owns the frame
function M.frame(f, inp)
  f.r27aInput = inp
  if f.r27phono and not f.r27phonoAlive then f.r27phono = nil end
  f.r27phonoAlive = nil
  return false
end
function M.draw(f, font)
  local ph = f.r27phono
  if ph and ph.box and ph.box.draw then
    ph.box:update({})
    pcall(ph.box.draw, ph.box, font, 240, 160)
  end
end
-- entity-data scripted doors (houseDoorExterior type2 3)
function M.roomInit(f)
  for _, e in ipairs(f.entities or {}) do
    if e.kind == 6 and e.id == 0x19 and e.script and not e.houseDoor then adoptDoor(f, e) end
  end
end

M.D, M.show = D, show
return M
