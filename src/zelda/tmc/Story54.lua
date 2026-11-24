-- Round 54: Lake Hylia after the Fortress of Winds -- the Flippers quest's
-- first step (src/npc/forestMinish.c).
--
-- CARTRIDGE BEHAVIOUR:
--   * sub_08060270 (script_ForestMinish3: the Minish in
--     MinishHouseInteriors_LakeHyliaOcarina, $20:27, FOREST_MINISH type2 $10):
--     no ITEM_FLIPPERS -> index 1, or index 0 and SetGlobalFlag(MIZUKAKI_START
--     $29) the first time; with the Flippers -> index 3, or index 2 and
--     SetLocalFlag($76) the first time; MessageNoOverlap(gUnk_0810A35A[index]).
--   * sub_080601D4 (script_ForestMinish10's talk): LV3_CLEAR clear -> 2,
--     KINSTONE_17 fused -> 1, else 0; MessageNoOverlap(gUnk_0810A354[i]).
--   * sub_0806AFE8 (townMinish.c, script_TownMinish1's talk): by type2 --
--     0 sub_0806B004 (the library bookshelf's yellow Minish: MIZUKAKI_START
--     -> MIZUKAKI_KOBITO, later the 50 rupees), 1 sub_0806B064, 7 / 8
--     sub_0806B098 (MIZUKAKI_HARIFALL), 9 sub_0806B0E0 (the dust tiles),
--     10 sub_0806B134 (POWERGLOVE_HINT), else sub_0806AFBC
--     (ShowNPCDialogue(dialogs[type2][max(progress - 2, 0)])).
--   * Room code (roomInit.c sub_unk3 / sub_StateChange) of the Flippers
--     quest: Library2F / Library1F ($21:02 / $21:03), MinishRafters_DrLeft
--     ($2E:02), TownMinishHoles MayorsHouse / LibraryBookshelf /
--     LibrariBookHouse ($2D:00 / $10 / $11), HouseInteriors2 DrLeft / Romio /
--     Julietta ($22:04 / $06 / $07), HouseInteriors4 MayorLakeCabin ($28:05).
--   * BOOK $8C (src/object/book.c): the three library books (type =
--     ITEM_QST_BOOK1 + n, type2 0 on a shelf / 1 falling in / 2 on the floor
--     / 3 back in the library, flag = paramC high).
-- SIMPLIFIED: sub_08058324 (the rafters' BG) and sub_0801AFE4 (Minish-hole
--   collision) are left to the modules that draw those rooms; PL_SPAWN_MINISH
--   is read as "Link arrived Minish"; Book type2 3 is not carried by
--   Sturgeon (sub_0809B6B0); PLAYER_PUSH while a book slides is not played.
-- The message tables are read from the player's ROM (the npcData range).
local bit = require("bit")
local band = bit.band

local M = {}

local N = require("src.zelda.tmc.Native").N
local function reg(addr, fn) if not N[addr] then N[addr] = fn end end
local function npcT(f) return require("src.zelda.tmc.Ppu").table({ A = f.assets }, "npcData") end

M.ITEM_FLIPPERS, M.MIZUKAKI_START, M.LV3_CLEAR, M.KINSTONE_17 = 0x46, 0x29, 0x04, 0x17
M.A_MSG_3 = 0x0810A35A -- gUnk_0810A35A
M.A_MSG_10 = 0x0810A354 -- gUnk_0810A354

function M.forestMinish3Index(f)
  if (f:inventory(M.ITEM_FLIPPERS) or 0) == 0 then
    if not f:flag("global", M.MIZUKAKI_START) then
      f:setFlag("global", M.MIZUKAKI_START, true)
      return 0
    end
    return 1
  end
  if not f:flag("local", 0x76) then
    f:setFlag("local", 0x76, true)
    return 2
  end
  return 3
end

function M.forestMinish10Index(f)
  if not f:flag("global", M.LV3_CLEAR) then return 2 end
  if f:kinstoneFused(M.KINSTONE_17) then return 1 end
  return 0
end

local function say(f, e, base, i)
  local t = npcT(f)
  if not t then return end
  f:message(t.u16(base + i * 2), e)
end

reg(0x08060270, function(f, e) say(f, e, M.A_MSG_3, M.forestMinish3Index(f)) end)
reg(0x080601D4, function(f, e) say(f, e, M.A_MSG_10, M.forestMinish10Index(f)) end)


-- ------------------------------------------------------------ townMinish.c
M.A_TOWN_DIALOGS = 0x081126F0 -- sub_0806AFBC's dialogs[type2][8] (Dialog: 8 bytes)
M.A_MSG_B004, M.A_MSG_B064, M.A_MSG_B098 = 0x08112C40, 0x08112C4A, 0x08112C50
M.A_MSG_B0E0, M.A_MSG_B134 = 0x08112C5C, 0x08112C60
M.KOBITO, M.HINT3_MAYOR, M.BOOK_ALLBACK, M.KHOUSE51_00, M.KHOUSE42_00 = 0x6A, 0x71, 0x73, 0x78, 0x7B
M.MIZUKAKI_HARIFALL, M.POWERGLOVE_HINT, M.ITEM_POWER_BRACELETS = 0x2A, 0x4A, 0x45
M.ITEM_BOOK1 = 0x39

function M.b004(f, ctx)
  local idx = 0
  if f:flag("global", M.MIZUKAKI_START) then
    if f:flag("local", M.BOOK_ALLBACK) then
      if (f:inventory(M.ITEM_FLIPPERS) or 0) == 0 then
        idx = 3
        if not f:flag("local", M.KHOUSE51_00) then
          idx = 2
          if ctx then ctx.condition = 1 end
          f:setFlag("local", M.KHOUSE51_00, true)
        end
      else idx = 4 end
    else
      idx = 1
      f:setFlag("local", M.KOBITO, true)
    end
  end
  return idx
end
function M.b064(f)
  if not f:flag("global", M.MIZUKAKI_START) then return 0 end
  return f:flag("local", M.BOOK_ALLBACK) and 2 or 1
end
function M.b098(f)
  if (f:inventory(M.ITEM_FLIPPERS) or 0) ~= 0 then return 2 end
  if f:flag("global", M.MIZUKAKI_START) and not f:flag("global", M.MIZUKAKI_HARIFALL) then return 0 end
  return 1
end
function M.b134(f)
  local idx
  if (f:inventory(M.ITEM_POWER_BRACELETS) or 0) ~= 0 then
    idx = 2
    if not f:flag("local", M.KHOUSE42_00) then idx = 1; f:setFlag("local", M.KHOUSE42_00, true) end
  else
    idx = 0
    f:setFlag("global", M.POWERGLOVE_HINT, true)
  end
  if (f.save.progress or 0) > 5 then idx = 3 end
  return idx
end

reg(0x0806AFE8, function(f, e, ctx)
  if ctx then ctx.condition = 0 end
  local t = npcT(f)
  if not t then return end
  local type2 = e.type2 or band(e.param or 0, 0xFF)
  if type2 == 0 then return say(f, e, M.A_MSG_B004, M.b004(f, ctx))
  elseif type2 == 1 then return say(f, e, M.A_MSG_B064, M.b064(f))
  elseif type2 == 7 or type2 == 8 then return say(f, e, M.A_MSG_B098 + (type2 - 7) * 6, M.b098(f))
  elseif type2 == 9 then
    local d = f:dungeon()
    local idx = 1
    for _, c in ipairs({ { 56, 184 }, { 72, 184 }, { 56, 200 }, { 72, 200 } }) do
      if d:actAt(c[1], c[2], 1) ~= 0x57 then idx = 0 end -- ACT_TILE_87
    end
    return say(f, e, M.A_MSG_B0E0, idx)
  elseif type2 == 10 then return say(f, e, M.A_MSG_B134, M.b134(f)) end
  local col = math.max((f.save.progress or 0) - 2, 0)
  require("src.zelda.tmc.CrenelPath").showDialogue(f, e, t, M.A_TOWN_DIALOGS + type2 * 64 + col * 8)
end)

-- -------------------------------------------------------------- room code
local function inv(f, i) return f:inventory(i) or 0 end
local function glob(f, i) return f:flag("global", i) end
local function loc(f, i) return f:flag("local", i) end
local function prop(f, i)
  local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
  return props and props[i]
end
local function list(f, addr) if addr then f:loadEntityList(addr) end end
local function dropList(f, l)
  local ok, D = pcall(require, "src.zelda.tmc.DHCObjects")
  if ok and D.dropList then D.dropList(f, l) end
end

M.ROOMS = {}
local R = M.ROOMS
R[0x2102] = function(f) -- sub_StateChange_HouseInteriors1_Library2F
  if inv(f, M.ITEM_FLIPPERS) == 0 then
    list(f, 0x080D6578)
    if not loc(f, M.BOOK_ALLBACK) then list(f, 0x080D6638) return end
  else
    list(f, 0x080D6558)
  end
  list(f, 0x080D6618)
end
R[0x2103] = function(f) -- sub_StateChange_HouseInteriors1_Library1F
  if (f.save.progress or 0) > 4 then list(f, 0x080D6714) end
  if inv(f, M.ITEM_FLIPPERS) == 0 and glob(f, M.MIZUKAKI_START) and loc(f, M.KOBITO) then list(f, prop(f, 9))
  else list(f, prop(f, 8)) end
end
R[0x2E02] = function(f) -- sub_StateChange_MinishRafters_DrLeft
  if glob(f, M.MIZUKAKI_START) and not glob(f, M.MIZUKAKI_HARIFALL) then list(f, 0x080D9800) end
end
R[0x2D00] = function(f) -- sub_StateChange_TownMinishHoles_MayorsHouse
  if inv(f, M.ITEM_FLIPPERS) == 0 and inv(f, M.ITEM_BOOK1 + 2) == 0 and loc(f, M.HINT3_MAYOR) then list(f, 0x080DB4D0)
  else list(f, 0x080DB4A0) end
end
R[0x2D10] = function(f) -- sub_unk3 + sub_StateChange_TownMinishHoles_LibraryBookshelf
  if glob(f, M.MIZUKAKI_START) and not loc(f, M.BOOK_ALLBACK) then
    -- sub_unk3: gRoomVars.properties[1] = gUnk_080DB910 (in place of the room's list 1)
    dropList(f, f.room.entities and f.room.entities[1])
    list(f, 0x080DB910)
  end
  list(f, 0x080DB8F0)
  if inv(f, M.ITEM_FLIPPERS) == 0 and glob(f, M.MIZUKAKI_START) then list(f, prop(f, 10)) end
end
R[0x2D11] = function(f) -- sub_StateChange_TownMinishHoles_LibrariBookHouse
  if inv(f, M.ITEM_FLIPPERS) ~= 0 or not loc(f, M.BOOK_ALLBACK) then list(f, 0x080DBA08) end
end
R[0x2204] = function(f) -- sub_StateChange_HouseInteriors2_DrLeft
  list(f, 0x080F2174)
  if inv(f, M.ITEM_BOOK1 + 1) == 0 and glob(f, M.MIZUKAKI_HARIFALL) then list(f, 0x080F2194) end
  if f.player and f.player.minish then list(f, 0x080F21B4) end -- PL_SPAWN_MINISH
end
R[0x2206] = function(f) -- sub_StateChange_HouseInteriors2_Romio
  if (f.save.progress or 0) > 7 then list(f, 0x080F23BC) end
  if inv(f, M.ITEM_FLIPPERS) == 0 and glob(f, M.MIZUKAKI_START) then list(f, 0x080F238C)
  else list(f, prop(f, 12)) end
end
R[0x2207] = function(f) -- sub_StateChange_HouseInteriors2_Julietta
  local g = f.save.progress or 0
  if g == 0 or g == 2 or g == 4 then list(f, 0x080F2570)
  elseif g == 5 then
    if inv(f, M.ITEM_FLIPPERS) == 0 then
      if not glob(f, M.MIZUKAKI_START) then list(f, 0x080F2570)
      elseif inv(f, M.ITEM_BOOK1) == 0 then list(f, 0x080F25C0) end
    else list(f, 0x080F2590) end
  elseif g == 8 or g == 9 then list(f, 0x080F2600); list(f, 0x080F2590)
  elseif g == 6 or g == 7 then list(f, 0x080F2590) end
end
R[0x2805] = function(f) -- sub_StateChange_HouseInteriors4_MayorLakeCabin
  if inv(f, M.ITEM_FLIPPERS) == 0 and glob(f, M.MIZUKAKI_START) and inv(f, M.ITEM_BOOK1 + 2) == 0 then list(f, 0x080F3A48) end
end

function M.roomInit(f)
  local r = f.room
  if not r then return end
  local fn = R[(r.area or 0) * 256 + (r.room or 0)]
  if fn then fn(f) end
end

-- ------------------------------------------------------------------ book.c
M.BOOK = 0x8C
M.SFX_10F = 0x10F
local function bookHit(f, e) return require("src.zelda.tmc.Hitboxes").object(f, e) or { x = 0, y = 0, w = 6, h = 6 } end
local function minishSolid(f, e) -- sub_0800445C (Minish Link only)
  if not f.player.minish then return end
  require("src.zelda.tmc.Hitboxes").pushOut(f, e, bookHit(f, e))
end
-- sub_0809B688: EntityInRectRadius(this, Link, 6, 12) and gPlayerState.direction south
-- (here: Link walking / pushing with the south facing)
function M.pushedSouth(e, p)
  return math.abs(p.x - e.x) <= 6 and math.abs(p.y - e.y) <= 12 and p.moving == true and p.animationState == 4
end
local function bookUpdate(d, e)
  local f = d.field
  local p = f.player
  local a = e.action
  if a == 1 then -- Book_Action1
    minishSolid(f, e)
    if (e.unk80 or 0) > 0 then e.unk80 = e.unk80 - 1 return end
    if M.pushedSouth(e, p) then
      e.timer = e.timer - 1
      if e.timer > 0 then return end
      e.action, e.timer, e.speed = 2, 30, 0x40 / 256
      f:sound(M.SFX_10F)
    else
      e.timer = 22
    end
  elseif a == 2 then -- Book_Action2
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then
        e.action = 3
        e.y = e.y + 0x20
        e.z = (e.z or 0) + 0x20
        e.zv = 0
      else
        e.action, e.timer, e.unk80 = 1, 22, 0x18
      end
    end
    e.y = e.y + (e.speed or 0) -- LinearMoveUpdate, direction south
  elseif a == 3 then -- Book_Action3: BounceUpdate(Q_8_8(40)) until the first bounce (BOUNCE_INIT_NEXT)
    local nz = (e.z or 0) + (e.zv or 0)
    if nz > 0 then e.z, e.zv = nz, (e.zv or 0) - 40 / 256 return end
    e.z, e.zv = 0, 0
    e.action = 4
    if (e.flag or 0) ~= 0 then d:set(e.flag, true) end
    if f.addFx then f:addFx(e.x, e.y, 0x0F, 2) end -- FX_DEATH
  elseif a == 4 then -- Book_Action4
    if p.minish then minishSolid(f, e)
    elseif math.abs(p.x - e.x) <= 8 and math.abs(p.y - e.y) <= 8 and p.state ~= "dead" then
      f:giveItem((e.form or 0) + M.ITEM_BOOK1, 0, 0)
      e.deleted = true
    end
  elseif a == 5 then -- Book_Action5 (the Sturgeon carry is not modelled)
    if e.hidden then
      if e.subAction == 0 then
        if inv(f, (e.form or 0) + M.ITEM_BOOK1) == 2 then e.subAction = 1 end
      elseif not f.textbox then
        e.hidden, e.subAction = false, 0
      end
    end
  end
end
M.bookUpdate = bookUpdate

function M.bookInit(d, e)
  local f = d.field
  local item = (e.form or 0) + M.ITEM_BOOK1
  local got = inv(f, item)
  if e.type2 ~= 3 then
    if got ~= 0 then e.deleted = true return false end
  else
    if loc(f, M.BOOK_ALLBACK) then e.deleted = true return false end
    if got ~= 2 then e.hidden = true end
  end
  if (e.flag or 0) ~= 0 and d:check(e.flag) then
    if e.type2 == 0 then e.y = e.y + 48 end
    e.type2 = 2
  end
  if e.type2 == 0 then e.action, e.timer, e.subtimer, e.unk80 = 1, 22, 2, 0
  elseif e.type2 == 1 then
    e.action = 3
    e.z = e.y - ((f.camY or 0) - 0x10) -- InitAnimation: falls in from above the screen
    e.zv = 0
  elseif e.type2 == 2 then e.action = 4
  else e.action, e.subAction = 5, 0 end
  return true
end

function M.spawnObject(d, e)
  if e.id ~= M.BOOK then return nil end
  local f = d.field
  if not M.bookInit(d, e) then return false end
  local item = (e.form or 0) + M.ITEM_BOOK1
  local def = f:objects():def(M.BOOK, e.form)
  if def then f:objects():dress(e, def, item) end
  e.objAnim = item
  e.spriteOffsetY = 3
  e.extUpdate = bookUpdate
  d:track(e)
  return e
end

return M
