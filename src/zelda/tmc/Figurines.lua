-- Round 32: Carlov's figurines (Hyrule Town, HOUSE_INTERIORS_3 room 7):
-- FIGURINE_DEVICE ($22, src/object/figurineDevice.c), the script natives of
-- script_Carlov2, and the figurine menu (src/menu/figurineMenu.c, subtask
-- 7) drawn through Ppu.lua.  An R27A module (R27A.MODULES already names
-- "src.zelda.tmc.Figurines"): frame / draw / natives at load.  The figurine
-- data (gUnk_080FC3E4, gFigurines, their palettes and gfx) comes from the
-- player's ROM at import (ExtractR32.lua, figurines.bin).
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * FIGURINE_DEVICE type 0 (the viewer at the left): SPECIAL_TILE_34 x3;
--     checkable (AddInteractableCheckableObject) once SHOP07_TANA (local
--     $5E, the lever pulled once) is set: room flag 2 + the menu in browse
--     mode (MenuFadeIn(7, $FF)); before that room flag 5 (the cutscene
--     object's "not yet" message).
--   * type 1 (the machine): its child type 3 (the shell counter); room flag
--     0 (PULLABLE_LEVER's flag) -> FigurineDevice_Draw on the child, a type
--     2 capsule at (+8, +7) with subtimer = the figurine, type2 = its
--     colour (gUnk_080FC3E4[n].type), SFX_111; the first time SHOP07_TANA.
--   * type 2 (the capsule): animation 1, then the colour palette
--     ({0, 1, 2, 4}[type2]), animation 2, SFX_110, 40 frames -> room flag
--     2 + the menu showing the figurine; the menu closed -> gone, room flag
--     4 cleared.
--   * type 3: sub_080880D8 counts the figurines available now over four
--     frames (sub_08088160 by the story stage sub_0808804C, a bank flag, a
--     fused Kinstone, or the special cases); new ones since the last visit
--     -> room flag 6; then room flag 1 (Carlov's "yes") shows the counter
--     (sub_080882A8: ShowTextBox(CARLOV $18) with the shells and the
--     chance, sub_0808826C: 100 * missing / available, min 1); Up / Down
--     (R: 10) change the shells (FigurineDevice_ChangeShellAmount), A ->
--     room flag 3 and CARLOV $1A with the shells.
--   * FigurineDevice_Draw: a number 0..99 (Random & $7F until < 100), the
--     shells paid, a figurine 1..128 at random; the chance floored by the
--     count (15 / 12 / 9 / 6); lucky -> the next available one not owned,
--     else the next available one owned (none: a new one after all);
--     count + 1, room flag 7 (8 and SHOP07_COMPLETE when the last).
--   * The menu, after a draw (menu types 0-3): the capsule (OBJECT_A2)
--     falls and opens, the screen brightens (layerBrightness up and down
--     over $80 frames), at $40 the figurine's bit is written (duplicate:
--     SFX_MENU_ERROR, else SFX_ITEM_GET); then its picture, name and
--     description; Left / Right scroll the description, B / START leave
--     (room flag 2 cleared).  Browse: Up / Down one, L / R five, the list
--     of five names (sub_080A4BA0, "?????" text $889 for one not owned),
--     the scroll bar and arrows (sprite $1FC), the number, the description
--     (text $900 + n into BG1, shown in WIN0 y 120..152).
-- Round 33: the menu keeps the field's BG0 control ($1F0C; with 0 the BG0
--   buffer's copy wiped BG2's first 64 tiles: the scattered grey / white
--   blocks), the capsule is OBJECT_A2 (objectA2.c: the fall from z -80 with
--   BounceUpdate(32.0), SFX_186, animations 1 / 2, FX_BIG_EXPLOSION2 and
--   gMenu.field_0x0 on frame byte 9) and gUnk_0812813C (B "Return") is laid
--   out by Ui.lua.
-- SIMPLIFIED: MenuFadeIn is an 8-frame fade; the brightness ramp is a white
--   overlay; the counter box is drawn over the field with the cartridge's
--   Font.
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local M = {}
M.ID = 0x22
M.TANA, M.COMPLETE = 0x5E, 0x5F           -- SHOP07_TANA / SHOP07_COMPLETE (local)
M.FIGURE_ALLCOMP = 0x59                   -- global
M.ITEM_CARLOV_MEDAL = 0x3E
local TEXT_CARLOV = 0x43
local function T(n) return TEXT_CARLOV * 256 + n end
local SFX_110, SFX_111 = 0x110, 0x111
local SFX_TEXTBOX_SELECT, SFX_TEXTBOX_CHOICE, SFX_MENU_ERROR, SFX_MENU_CANCEL, SFX_ITEM_GET = 0x6A, 0x69, 0x6D, 0x6C, 0x109
local CAPSULE_PAL = require("src.zelda.tmc.RomTables").t("Figurines.CAPSULE_PAL")  -- gUnk_08120AA8
local RANGES = require("src.zelda.tmc.RomTables").t("Figurines.RANGES")    -- gUnk_08120AAC

-- ---------------------------------------------------------------------------
-- data (figurines.bin)
-- ---------------------------------------------------------------------------
local function blob(f)
  local A = f.assets
  if A.fig32 == nil then
    local idx = A.manifest and A.manifest.r32 and A.manifest.r32.figurines
    local b = idx and A.store:read("figurines.bin")
    if not (idx and b) and rawget(_G, "R26_DEV_ROM") then -- (dev scenes on an older cache read the ROM, as ExtractR26.tables)
      idx, b = require("src.zelda.tmc.ExtractR32").build(rawget(_G, "R26_DEV_ROM"))
    end
    A.fig32 = (idx and b) and { idx = idx, b = b } or false
  end
  return A.fig32 or nil
end
local function rd(f, name, a, n)
  local d = blob(f)
  if not d then return nil end
  local r = d.idx[name]
  local o = a - r[1]
  if o < 0 or o + n > r[3] then return nil end
  return d.b:sub(r[2] + o + 1, r[2] + o + n)
end
local function u32(s, i) local a, b, c, d = s:byte(i, i + 3) return a + 256 * (b + 256 * (c + 256 * d)) end
local function u16(s, i) local a, b = s:byte(i, i + 1) return a + 256 * b end

-- gUnk_080FC3E4[k]: {bank, flag, unk_6, type}
function M.entry(f, k)
  local s = rd(f, "flags", 0x080FC3E4 + 8 * k, 8)
  if not s then return nil end
  return { bank = u32(s, 1), flag = u16(s, 5), kind = s:byte(7), type = s:byte(8) }
end
-- gFigurines[k]: palette / gfx bytes
function M.art(f, k)
  local s = rd(f, "table", 0x081281A8 + 16 * k, 16)
  if not s then return nil end
  local pal, gfx, size = u32(s, 1), u32(s, 5), u32(s, 9)
  if size >= 0x80000000 then return nil end -- (LZ77: none in the USA ROM)
  return rd(f, "pal", pal, 9 * 32), rd(f, "gfx", gfx, size)
end

-- ---------------------------------------------------------------------------
-- the save
-- ---------------------------------------------------------------------------
function M.save(f)
  local s = f.save
  s.figurines32 = s.figurines32 or { owned = {}, count = 0, available = 0, all = 0 }
  return s.figurines32
end
function M.owned(f, k) return M.save(f).owned[k] == true end
function M.max(f) return f.save.sawStaffroll and 136 or 130 end

-- sub_0808804C: the story stage
function M.stage(f)
  if f.save.sawStaffroll then return 9 end
  if f:flag("global", 6) then return 7 end          -- LV5_CLEAR
  if f:flag("bank", 0x77, 0x800) then return 6 end   -- LV5_31_CAP_0
  if f:flag("bank", 50, 0x300) then return 5 end     -- OUBO_KAKERA
  if f:flag("global", 5) then return 4 end          -- LV4_CLEAR
  if f:flag("global", 4) then return 3 end          -- LV3_CLEAR
  if f:flag("bank", 0x9C, 0x100) then return 2 end   -- SOUGEN_08_TORITSUKI
  if f:flag("global", 3) then return 1 end          -- LV2_CLEAR
  return 0
end

local function fused(f, id)
  local k = f.kinstone
  return k and k.isFused and k:isFused(id) or false
end

-- sub_08088160: figurine k can be drawn now
function M.available(f, k, stage)
  local e = M.entry(f, k)
  if not e then return false end
  stage = stage or M.stage(f)
  if stage >= e.kind then return true end
  local kd = e.kind
  if kd == 0x08 or kd == 0x40 then return f:flag("bank", e.flag, e.bank) end
  if kd == 0x10 then return fused(f, e.flag) end
  if kd == 0x20 then
    local fl = e.flag
    if fl == 0 then return fused(f, 0x20) or fused(f, 0x10) or fused(f, 0x19) end
    if fl == 1 then return stage >= 5 and fused(f, 0x28) end
    if fl == 2 then return fused(f, 0x54) or fused(f, 0x56) or fused(f, 0x3D) end
    if fl == 3 then return fused(f, 0x3B) or fused(f, 0x4A) or fused(f, 0x0D) end
    if fl == 4 then return fused(f, 0x49) or fused(f, 0x55) or fused(f, 0x3C) end
    if fl == 5 then return stage >= 2 and f:flag("global", 0x12) end -- MACHI_MACHIHOKORI
  end
  return false
end

local function rand(f)
  local D = require("src.zelda.tmc.Drops")
  if D.random and D.rngOf then return D.random(D.rngOf(f)) end
  return math.random(0, 0x7FFFFFFF)
end
M._rand = rand

-- ---------------------------------------------------------------------------
-- FigurineDevice_Draw (on the type 3 counter `c`); returns the figurine
-- ---------------------------------------------------------------------------
function M.chanceFloor(count, chance)
  if count < 50 then return math.max(chance, 15)
  elseif count < 80 then return math.max(chance, 12)
  elseif count < 110 then return math.max(chance, 9) end
  return math.max(chance, 6)
end

function M.drawFigurine(f, c, rnd)
  rnd = rnd or function() return rand(f) end
  local S = M.save(f)
  local lucky
  repeat lucky = band(rnd(), 0x7F) until lucky < 100
  f:modStat("shells", -(c.shells or 1))
  local idx = band(rnd(), 0x7F) + 1
  local start = idx
  c.chance = M.chanceFloor(S.count, c.chance or 0)
  local stage = c.stage or M.stage(f)
  local got
  if lucky < c.chance then
    got = false
    repeat
      if idx > 136 then idx = 1 end
      if M.available(f, idx, stage) and not S.owned[idx] then got = true else idx = idx + 1 end
    until got or idx == start
  else
    got = true
    repeat
      if idx > 136 then idx = 1 end
      if M.available(f, idx, stage) and S.owned[idx] then got = false else idx = idx + 1 end
    until (not got) or idx == start
  end
  if got then
    S.count = S.count + 1
    if S.count ~= c.avail then f:setFlag("room", 7, true)
    else f:setFlag("local", M.COMPLETE, true); f:setFlag("room", 8, true) end
  end
  return idx
end

-- FigurineDevice_ChangeShellAmount
function M.changeShells(f, c, d)
  local shells = (f.save.stats and f.save.stats.shells) or 0
  if f:flag("local", M.COMPLETE) then M.errorSound(f, c) return end
  local prevChance = c.chance
  local newChance = prevChance + d
  if d < 0 then
    if newChance < c.prevChance then
      if c.chance ~= c.prevChance then
        c.chance, c.shells = c.prevChance, 1
        f:sound(SFX_TEXTBOX_CHOICE)
      else M.errorSound(f, c) end
    else
      c.chance, c.shells = newChance, c.shells + d
      f:sound(SFX_TEXTBOX_CHOICE)
    end
    return
  end
  local prevShells = c.shells
  local newAmount = prevShells + d
  if newAmount > shells then
    if shells ~= c.shells then
      newAmount = shells
      d = shells - c.shells
      newChance = prevChance + d
    else M.errorSound(f, c) return end
  end
  if newChance > 100 then
    if c.chance == 100 then M.errorSound(f, c) return end
    newChance = 100
    d = newChance - prevChance
    newAmount = prevShells + d
  end
  c.chance, c.shells = newChance, newAmount
  f:sound(SFX_TEXTBOX_CHOICE)
end
function M.errorSound(f, c)
  if (c.timer or 0) == 0 then c.timer = 20; f:sound(SFX_MENU_ERROR) end
end

-- sub_0808826C
function M.setChance(f, c)
  local S = M.save(f)
  local t = c.avail > 0 and math.floor(100 * (c.avail - S.count) / c.avail) or 0
  if t == 0 and not f:flag("local", M.COMPLETE) then t = 1 end
  c.chance, c.prevChance = t, t
end

-- ---------------------------------------------------------------------------
-- the counter box (sub_080882A8): ShowTextBox(CARLOV $18 + type2) with the
-- Font gUnk_08120AB4 (from the .c source) into BG0, the numbers padded to
-- three digits (gUnk_020227E8[0] / [1])
-- ---------------------------------------------------------------------------
local COUNTER_FONT = { dest = 0x02034FCE, gfx_dest = 0x0600D000, buffer = 0x02000D00, gfx_src = 0xF080, width = 0x68,
  centre = false, sm_border = false, draw_border = true, border_type = 8, fill = 2, charColor = 0, spacing = 1, stylized = 0 }
local function pad3(n) return string.format("%3d", n) end

local function counterShow(f, c)
  local Ppu = require("src.zelda.tmc.Ppu")
  local p = Ppu.new(f.assets)
  p.transparent = true
  p.dispcnt = 0x0140
  p.bg[0].control = 0x1F0C
  p:loadPaletteGroup(12)
  local vars = { [1] = pad3(c.shells), [2] = pad3(c.chance) } -- $06 01 / $06 02: gUnk_020227E8[0] / [1]
  M.vars32 = vars
  p:showTextBox(T(0x18 + (c.type2 or 0)), COUNTER_FONT, vars)
  p.bg[0].updated = true
  f.figCounter32 = p
end
M._counterFont = COUNTER_FONT

-- ---------------------------------------------------------------------------
-- the objects
-- ---------------------------------------------------------------------------
local function setPalette(f, e, pal)
  if e.palId == pal then return end
  e.palId = pal
  e.baseDef = e.baseDef or e.def
  e.palette = f.assets:objPalette(pal, f.room.atlas and f.room.atlas.palettes)
end

local function tiles(f, e) -- sub_08087F58
  local r = f.room
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  for dx = -1, 1 do
    if tx + dx >= 0 and tx + dx < r.tw and ty >= 0 and ty < r.th then r:setTile(1, tx + dx, ty, 0x4022) end
  end
end

local function spawnDevice(f, typ, x, y)
  return f:spawn({ kind = 6, id = M.ID, paramA = typ, paramB = 0, pool = 0x0F, x = x, y = y, paramC = 0 })
end

local function init(f, e)
  local t = e.form or 0
  e.fig32 = f.room
  e.u7a = 0
  e.type2 = band(e.param or 0, 0xFF)
  if t == 0 then
    if f:flag("local", M.TANA) then e.u7a = 1; e.talkable = true end
    e.oamPrio, e.spritePriority = 3, 7
    tiles(f, e)
  elseif t == 1 then
    local c = spawnDevice(f, 3, e.x, e.y)
    if c then c.parentDev, e.child = e, c end
    e.oamPrio, e.spritePriority = 3, 7
    tiles(f, e)
  elseif t == 2 then
    e.spritePriority = 7
    e.objAnim = 1
  elseif t == 3 then
    e.timer, e.subtimer, e.shells = 30, 0, 1
    e.u7b, e.avail, e.chance, e.prevChance = 0, 0, 0, 0
    e.stage = M.stage(f)
    e.hidden = true
  end
end

local function capsule(f, e)
  e.anim:update(1)
  if e.u7a == 0 then
    if e.anim.done then
      e.u7a, e.timer = 1, 40
      setPalette(f, e, CAPSULE_PAL[e.type2 or 0] or 0)
      e.objAnim = 2
      f:sound(SFX_110)
    end
  elseif e.u7a == 1 then
    if e.objAnim == 2 and e.animIndex == 2 and e.anim.done then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.u7a = 2
        f:setFlag("room", 2, true)
        M.openMenu(f, e.subtimer)
      end
    end
  else
    if not f:flag("room", 2) then
      e.hidden = true
      f:setFlag("room", 4, false)
      e.deleted = true
    end
  end
end

local function counter(f, e, input)
  if e.u7a == 0 then
    if e.u7b == 4 then
      if not f:flag("room", 1) then return end
      e.u7a, e.shells = 1, 1
      f:setFlag("room", 1, false)
      M.setChance(f, e)
      counterShow(f, e)
    else
      for k = RANGES[e.u7b + 1], RANGES[e.u7b + 2] - 1 do
        if M.available(f, k, e.stage) then e.avail = e.avail + 1 end
      end
      e.u7b = e.u7b + 1
      if e.u7b == 4 then
        local S = M.save(f)
        if S.available ~= e.avail then
          if S.available ~= 0 then f:setFlag("room", 6, true) end
          S.available = e.avail
        end
        if f:flag("local", M.COMPLETE) and e.avail ~= S.count then f:setFlag("local", M.COMPLETE, false) end
      end
    end
  elseif e.u7a == 1 then
    if (e.timer or 0) > 0 then e.timer = e.timer - 1 end
    if input and input.pressed("a") then
      f:sound(SFX_TEXTBOX_SELECT)
      e.u7a, e.timer = 2, 60
      f.figCounter32 = nil
      return
    end
    local old = e.shells
    local step = (input and input.down and input.down("r")) and 10 or 1
    local up, down = M.scroll(e, input, "up"), M.scroll(e, input, "down")
    if up then M.changeShells(f, e, step) elseif down then M.changeShells(f, e, -step) end
    if old ~= e.shells or (up or down) then counterShow(f, e) end
  else
    e.u7a, e.u7b = 0, 4
    f:setFlag("room", 3, true)
    f.messageRupees = e.shells
    f:message(T(0x1A), e)
  end
end

-- gInput.menuScrollKeys: a new press, then every 4 frames after 20 held
function M.scroll(st, input, k)
  if not input then return false end
  st.rep32 = st.rep32 or {}
  if input.pressed and input.pressed(k) then st.rep32[k] = 0 return true end
  if input.down and input.down(k) then
    local n = (st.rep32[k] or 0) + 1
    st.rep32[k] = n
    return n >= 20 and (n - 20) % 4 == 0
  end
  st.rep32[k] = nil
  return false
end

local function update(f, e, input)
  local t = e.form or 0
  if t == 0 then
    if e.u7a == 0 then e.u7a, e.talkable = 1, true
    elseif e.u7a == 1 then
      if (e.interactType or 0) ~= 0 then
        e.interactType = 0
        if f:flag("local", M.TANA) then
          e.u7a = 2
          f:setFlag("room", 2, true)
          M.openMenu(f, 0xFF)
        else
          f:setFlag("room", 5, true)
        end
      end
    elseif not f:flag("room", 2) then
      e.u7a, e.talkable = 1, true
    end
  elseif t == 1 then
    if e.u7a == 0 then
      if f:flag("room", 0) then e.u7a = f:flag("local", M.TANA) and 1 or 2 end
    else
      if e.u7a == 2 then f:setFlag("local", M.TANA, true) end
      e.u7a = 0
      local c = e.child
      local idx = c and M.drawFigurine(f, c) or 1
      f:setFlag("room", 0, false)
      local cap = spawnDevice(f, 2, e.x + 8, e.y + 7)
      if cap then
        cap.subtimer = idx
        local en = M.entry(f, idx)
        cap.type2 = en and en.type or 0
        cap.parentDev = e
      end
      f:sound(SFX_111)
    end
  elseif t == 2 then
    capsule(f, e)
  elseif t == 3 then
    counter(f, e, input)
  end
end

-- ---------------------------------------------------------------------------
-- script natives (script_Carlov2)
-- ---------------------------------------------------------------------------
local N = require("src.zelda.tmc.Native").table
local function inRegion(f, cx, cy, w, h)
  return f.player and f:playerInRegion(cx, cy, w, h)
end
local function msg(f, e, id) f:message(id, e) end

N[0x0808861C] = N[0x0808861C] or function(f, e, ctx, a) -- the player at the lever
  local p = f.player
  ctx.condition = (inRegion(f, 168, 84, 12, 8) and (p.animationState or 4) == 0 and (p.z or 0) == 0) and 1 or 0
  a.flags = bor(a.flags, 1)
end
N[0x08088658] = N[0x08088658] or function(f, e, ctx, a) -- the player at the door
  ctx.condition = (inRegion(f, 120, 120, 16, 8) and (f.player.z or 0) == 0) and 1 or 0
  a.flags = bor(a.flags, 1)
end
N[0x08088478] = N[0x08088478] or function(f, e) -- FigurineDevice_NoFigurinesLeftMessage
  local S = M.save(f)
  local id, unlucky = nil, false
  if not f:flag("room", 8) then
    if not f:flag("room", 7) then id, unlucky = T(34), true else id = T(37) end
  else
    if S.count == 136 then S.all = 0xFF; id = T(41)
    elseif S.count == 130 then id = f.save.sawStaffroll and T(39) or T(40)
    else id = T(39) end
  end
  if unlucky then f.messageRupees = 5 end
  msg(f, e, id)
  f.player.animationState = 6
end
N[0x08088504] = N[0x08088504] or function(f, e) -- FigurineDevice_NothingNewToDrawMessage
  local c = M.save(f).count
  msg(f, e, c == 136 and T(47) or (c == 130 and T(20) or T(17)))
end
N[0x08088544] = N[0x08088544] or function(f, e) -- FigurineDevice_NewFigurinesMessage
  msg(f, e, M.save(f).count ~= 130 and T(14) or T(21))
end
N[0x08088574] = N[0x08088574] or function(f, e) -- FigurineDevice_TryAgainMessage
  local id
  if f:flag("room", 9) then id = f:flag("local", M.COMPLETE) and T(19) or T(12) else id = T(11) end
  msg(f, e, id)
end
N[0x080885B0] = N[0x080885B0] or function(f, e) -- FigurineDevice_LostOrFinishedMessage
  local S = M.save(f)
  if not f:flag("room", 8) then
    if not f:flag("room", 7) then
      f:modStat("rupees", 5)
      msg(f, e, T(38))
    end
  elseif (S.all or 0) ~= 0 then
    f.save.hasAllFigurines = true
    f.save.stats.hasAllFigurines = true
    f:giveItem(M.ITEM_CARLOV_MEDAL, 0, 0)
    f:setFlag("global", M.FIGURE_ALLCOMP, true)
  end
  f:setFlag("room", 8, false)
  f:setFlag("room", 7, false)
end

-- ---------------------------------------------------------------------------
-- the figurine menu (subtask 7)
-- ---------------------------------------------------------------------------
local Menu32 = {}
Menu32.__index = Menu32
-- gUnk_0812816C / gUnk_08128190 (figurineMenu.c, written out in the source)
local NAME_FONT = { dest = 0x02001B40, gfx_dest = 0x0600A000, buffer = 0x02000D00, gfx_src = 0xF100, width = 0x88,
  centre = false, sm_border = false, draw_border = false, border_type = 0, fill = 4, charColor = 0, spacing = 0, stylized = 0 }
local DESC_FONT = { dest = 0x02021F72, gfx_dest = 0x06004000, buffer = 0x02000D00, gfx_src = 0xC200, width = 0xE0,
  centre = false, sm_border = false, draw_border = false, border_type = 0, fill = 5, charColor = 0, spacing = 0, stylized = 0 }
M.NAME_FONT, M.DESC_FONT = NAME_FONT, DESC_FONT
local SPR = 0x1FC -- sub_080A4978_draw_constant (USA)

-- round 33: gUnk_0812813C (KeyButtonLayout, figurineMenu.c): the three
-- buttons' x / y / label bytes, then the {type, type2} element list up to
-- $FF; both read from the ROM (round 36) and joined here at use
local KEY_BYTES = require("src.zelda.tmc.RomTables").t("Figurines.KEY_LAYOUT")
local KEY_ELEMENTS = require("src.zelda.tmc.RomTables").t("Figurines.KEY_ELEMENTS")
local KEY_LAYOUT = setmetatable({}, { __index = function(_, k)
  if k == "elements" then return KEY_ELEMENTS end
  return KEY_BYTES[k]
end })
M.KEY_LAYOUT = KEY_LAYOUT
local OBJECT_A2, SPECIAL_FX, FX_BIG_EXPLOSION2 = 0xA2, 0x0F, 0x43
local SFX_186 = 0x186
local A2_PAL = require("src.zelda.tmc.RomTables").t("Figurines.A2_PAL") -- gUnk_08124704

function M.openMenu(f, which)
  local Ppu = require("src.zelda.tmc.Ppu")
  local m = setmetatable({ field = f, which = which, ticks = 0, fadeIn = 8 }, Menu32)
  m.browse = (which == 0xFF)
  local p = Ppu.new(f.assets)
  m.ppu = p
  -- round 33: gScreen.bg0.control keeps the field's $1F0C (common.c /
  -- ui.c); sub_080A4DB8 only sets bg0.updated.  With control 0 the BG0
  -- buffer's copy landed on screen base 0 = BG2's tiles 0-$3F (the stone
  -- texture's grey / white blocks of the round 32 shots).
  p.bg[0].control = 0x1F0C
  -- sub_080A4D34 (LoadGfxGroups as Menu:openMenu) / sub_080A4DB8(3)
  for _, g in ipairs({ 16, 23 }) do p:loadGfxGroup(g) end
  p:loadGfxGroup(f:inventory(0x08) ~= 0 and 24 or 25)
  p:loadGfxGroup(f:inventory(0x0C) ~= 0 and 28 or 27)
  p:loadPaletteGroup(11); p:loadPaletteGroup(12); p:setColor(0, 0)
  p:loadPaletteGroup(0xB5)
  local s = f.save.stats
  local v = 0
  if s.health <= 8 then v = 2 elseif s.maxHealth - s.health >= 9 then v = 1 end
  p:loadGfxGroup(0x56 + v)
  p:clearBuffers({ [0] = true, true, true })
  p.dispcnt = bor(0x0F00, 0x1940)
  for b = 0, 2 do p.bg[b].x, p.bg[b].y, p.bg[b].updated = 0, 0, true end
  p.bg[1].control, p.bg[2].control, p.bg[3].control = 0x1C02, 0x1D03, 0x1E0B
  p:loadPaletteGroup(206)
  p:loadGfxGroup(89)
  -- FigurineMenu_080A4608
  p:setColor(0, p.pal[251])
  p:setColor(0x15C, p.pal[211])
  p:clearBuffers({ [0] = true, [3] = true })
  p.bg[3].updated = true
  m.names = {}
  local r1 = which
  if M.max(f) < r1 then r1 = 1 end
  m.idx = r1
  m.u1d, m.u1a, m.u1e, m.u1f = -1, -1, 0, 0
  if m.browse then
    m.type, m.column = 1, 0xFF
    m:keyLayout() -- FigurineMenu1_Type0: sub_080A70AC(gUnk_0812813C)
  else
    m.type, m.column, m.u20 = 1, 0, 0
  end
  f.figMenu32 = m
  if f.bgmVolume then f:bgmVolume(0x80) end
  return m
end

-- sub_080A4BA0: one of the five name rows
function Menu32:nameRow(n, slot)
  local f, p = self.field, self.ppu
  local font = {}
  for k, v in pairs(NAME_FONT) do font[k] = v end
  font.gfx_dest = font.gfx_dest + lshift(slot * 3, 9)
  font.gfx_src = font.gfx_src + lshift(slot * 3, 4)
  font.dest = font.dest + lshift(slot, 7)
  if slot == 2 then font.fill = 2 end
  local key = -1
  local vars
  if n > 0 and n <= M.max(f) then
    vars = { [0] = f.save.name or "Link", [1] = string.format("%03d", n) }
    key = M.owned(f, n) and (0x800 + n) or (0x8000 + n)
  end
  if self.names[slot] == key then return end
  self.names[slot] = key
  local base = NAME_FONT.dest + lshift(slot, 7)
  local fillv = slot == 2 and 0xF004 or 0xF00B
  for i = 0, 63 do p:set16(base + 2 * i, fillv) end
  if key > 0 then
    local id = key > 0x7FFF and 0x889 or key
    font.dest = font.dest + 0x16
    p:showTextBox(id, font, vars)
  end
  p.bg[3].updated = true
end

-- sub_080A4CBC: the description into BG1; returns its scroll limit
function Menu32:description(n)
  local f, p = self.field, self.ppu
  if self.u1a ~= n then
    self.u1a = n
    p:fill(Layout().gBG1Buffer, 0x800, 0)
    if M.owned(f, n) then p:showTextBox(0x900 + n, DESC_FONT, { [0] = f.save.name or "Link" }) end
    p.bg[1].updated = true
  end
  local a = DESC_FONT.dest + 0x100
  local rows = 0
  while rows < 0x14 do
    if p:u16(a) == 0 then break end
    a = a + 0x40
    rows = rows + 1
  end
  return rows * 8
end
function Layout() return require("src.zelda.tmc.Layout") end

-- FigurineMenu_080A4978: the OAM
function Menu32:oam()
  local f, p = self.field, self.ppu
  p:flush()
  if self.ui then self.ui:draw() end -- round 33: DrawUIElements (earlier OAM slots: on top)
  Menu32.drawObj(p, self.fx); Menu32.drawObj(p, self.cap) -- round 33: DrawEntities
  local max = M.max(f)
  p:drawDirect(SPR, 0, { x = 0x9C, y = 0x48, _8 = 0x800 })
  if band(self.column, 2) ~= 0 and self.idx <= max then
    local r0 = math.floor(0x5000 / max) * (self.idx - 1)
    r0 = rshift(r0, 8) + 0x20
    p:drawDirect(SPR, 1, { x = 0xE8, y = r0, _8 = 0x800 })
    local r4 = band(self.ticks, 0x10) ~= 0 and 4 or 2
    p:drawDirect(SPR, r4, { x = 0xE8, y = 0x1A, _8 = 0x800 })
    p:drawDirect(SPR, r4 + 1, { x = 0xE8, y = 0x76, _8 = 0x800 })
  end
  if band(self.ticks, 0x10) ~= 0 and band(self.column, 0x10) ~= 0 and self.u1e ~= 0 then
    if self.u1f > 0 then p:drawDirect(SPR, 6, { x = 6, y = 0x9C, _8 = 0x800 }) end
    if self.u1e > self.u1f then p:drawDirect(SPR, 7, { x = 0xEA, y = 0x9C, _8 = 0x800 }) end
  end
  if band(self.column, 4) ~= 0 then
    local r4 = self.idx
    for r6 = 2, 0, -1 do
      p:drawDirect(0, 9, { x = 0x5D + r6 * 7, y = 0x10, _8 = bor(lshift(r4 % 10, 1), 0x9E0) })
      r4 = math.floor(r4 / 10)
    end
  end
  if band(self.column, 1) ~= 0 and M.owned(f, self.idx) then
    p:drawDirect(SPR - 4, self.idx - 1, { x = 0x2C, y = 0x48, _8 = lshift(0xD4, 7) })
    if self.u1d ~= self.idx then
      self.u1d = self.idx
      local pal, gfx = M.art(f, self.idx)
      if pal then
        for i = 0, 9 * 16 - 1 do
          local c = pal:byte(2 * i + 1) + 256 * pal:byte(2 * i + 2)
          p.pal[256 + 0x60 + i] = c
        end
        p.dirty = true
      end
      if gfx then p:write(0x06010000 + 0x4000, gfx, 0, #gfx) end
    end
  end
end

-- sub_080A4B44
function Menu32:texts()
  local n = self.idx
  if band(self.column, 0x10) ~= 0 then self.u1e = self:description(n) end
  if band(self.column, 4) ~= 0 then self:nameRow(n, 2) end
  if band(self.column, 8) ~= 0 then
    self:nameRow(n - 2, 0); self:nameRow(n - 1, 1); self:nameRow(n + 1, 3); self:nameRow(n + 2, 4)
  end
end

function Menu32:exit()
  local f = self.field
  if f.bgmVolume then f:bgmVolume(0x100) end
  f:sound(SFX_MENU_CANCEL)
  f:setFlag("room", 2, false)
  f.figMenu32 = nil
end

function Menu32:scrollInfo(input, y)
  if M.scroll(self, input, "right") then y = y + 8 elseif M.scroll(self, input, "left") then y = y - 8 end
  if y < 0 then y = 0 end
  if self.u1e < y then y = self.u1e end
  self.u1f = y
  self.ppu.bg[1].y = band(y - 112, 0x1FF)
end

-- round 33: sub_080A70AC(gUnk_0812813C) -- the B "back" hint (Ui.lua)
function Menu32:keyLayout()
  local ok, Ui = pcall(require, "src.zelda.tmc.Ui")
  if not ok then return end
  local ok2, ui = pcall(Ui.new, self.ppu)
  if not ok2 or not ui then return end
  ui:layout(KEY_LAYOUT)
  self.ui = ui
end

-- round 33: OBJECT_A2 (src/object/objectA2.c), the capsule in the menu.
-- Init: animation 0, flipX on Random & $10, at (40, 72) z -80, palette
-- gUnk_08124704[type], PRIO_HIGHEST.  Action1: BounceUpdate(32.0) -- z -=
-- zVelocity, zVelocity -= $20 (Q8.8) -- and, USA (language < 2), the first
-- landing ends it: z 0, animation 1, SFX_186.  Action2: animation done ->
-- animation 2.  Action3: frame byte 9 -> FX_BIG_EXPLOSION2 and
-- gMenu.field_0x0 = 1 (the reveal starts); $80 -> deleted.
local function newObj(f, id, form, anim, x, y, z)
  local O = f._objects
  local d = O and O:def(id, form)
  if not d then return nil end
  local e = { kind = 6, id = id, form = form, x = x, y = y, z = z or 0, anim = require("src.zelda.tmc.Anim").new() }
  O:dress(e, d, anim)
  local spr = f.assets:sprite(d.sprite)
  if not (spr and spr.anims and spr.anims[anim]) then anim = 0 end
  e.animIndex = anim
  e.anim:set(spr, anim, true)
  return e
end
function Menu32:capsuleNew(typ)
  local f = self.field
  local e = newObj(f, OBJECT_A2, typ, 0, 40, 72, -80)
  if not e then self.field0 = true return end -- (no definition: straight to the reveal)
  e.zv, e.action = 0, 1
  e.flipX = band(rand(f), 0x10) ~= 0
  e.palBank = A2_PAL[typ] or 0 -- ChangeObjPalette
  self.cap = e
end
function Menu32:capsuleUpdate()
  local e, f = self.cap, self.field
  if not e then return end
  if e.action == 1 then
    local nz = e.z - e.zv
    if nz < 0 then
      e.z, e.zv = nz, e.zv - 0x20 / 256
    else
      e.z, e.zv, e.action = 0, 0, 2
      e.animIndex = 1
      e.anim:set(f.assets:sprite(e.sprite), 1, true)
      f:sound(SFX_186)
    end
  elseif e.action == 2 then
    if e.anim.done then
      e.action = 3
      e.animIndex = 2
      e.anim:set(f.assets:sprite(e.sprite), 2, true)
    end
  else
    if e.anim.flags == 9 then
      e.anim.flags = 0
      self.fx = newObj(f, SPECIAL_FX, FX_BIG_EXPLOSION2, FX_BIG_EXPLOSION2, e.x, e.y, e.z)
      if self.fx then self.fx.palBank = self.fx.def.palette end
      self.field0 = true
    elseif e.anim.flags == 0x80 then
      self.cap = nil
      return
    end
  end
  e.anim:update(1) -- GetNextFrame
end
-- DrawEntities in the menu: gfxType 2 objects use the OBJ tiles already in
-- VRAM (OBJECT_A2 tile $200 = gGfx_89_6 at $06014000, the FX tile 96),
-- palette bank = the object palette (0-5 fixed), OAM priority 0
local function drawObj(p, e)
  if not e then return end
  local frame = e.anim.frame
  if frame == nil or frame == 0xFF then return end
  local flip = e.anim:hflip() ~= (e.flipX or false)
  p:drawDirect(e.sprite, frame, { x = math.floor(e.x), y = math.floor(e.y + (e.z or 0)), _6 = flip and 0x1000 or 0,
                                  _8 = (e.palBank or 0) * 0x1000 + (e.def and e.def.gfx or 0) })
end
Menu32.drawObj = drawObj

function Menu32:update(input)
  local f = self.field
  self.ticks = self.ticks + 1
  -- UpdateEntities / UpdateUIElements (every menu type)
  if self.cap then self:capsuleUpdate() end
  if self.fx then self.fx.anim:update(1); if self.fx.anim.done then self.fx = nil end end
  if self.ui then
    self.ui.hideFlags = 0
    self.ui:update({ equipped = {}, health = 0 })
  end
  if self.fadeIn > 0 then self.fadeIn = self.fadeIn - 1 end
  if self.browse then
    if self.type == 1 then
      if self.fadeIn > 0 then return end
      if input.pressed("b") or input.pressed("start") then self:exit() return end
      local n = self.idx
      if M.scroll(self, input, "l") then n = n - 5 elseif M.scroll(self, input, "r") then n = n + 5
      elseif M.scroll(self, input, "up") then n = n - 1 elseif M.scroll(self, input, "down") then n = n + 1 end
      local max = M.max(f)
      if n <= 0 then n = 1 end
      if n > max then n = max end
      local y = self.u1f
      if n ~= self.idx then
        self.idx = n
        f:sound(SFX_TEXTBOX_CHOICE)
        y = 0
        self.u1f = 0
      end
      self:scrollInfo(input, y)
    end
  else
    if self.type == 1 then
      -- FigurineMenu0_Type1: CreateObject(OBJECT_A2, gUnk_080FC3E4[n].type)
      if self.fadeIn == 0 then
        local en = M.entry(f, self.idx)
        self:capsuleNew(en and en.type or 0)
        self.type = 2
      end
    elseif self.type == 2 then
      if not self.field0 then return end
      self.u20 = self.u20 + 1
      if self.u20 == 0x40 then
        local S = M.save(f)
        self.duplicate = S.owned[self.idx] == true
        S.owned[self.idx] = true
        self.column = 1
      end
      if self.u20 == 0x80 then
        self.bright = 0
        self.type = 3
        self.column = 0x15
        self:keyLayout()
        f:sound(self.duplicate and SFX_MENU_ERROR or SFX_ITEM_GET)
      else
        local b = rshift(self.u20, 2)
        if b > 0x10 then b = 0x20 - b end
        self.bright = b
      end
    else
      if input.pressed("b") or input.pressed("start") then self:exit() return end
      self:scrollInfo(input, self.u1f)
    end
  end
end

function Menu32:render()
  local p = self.ppu
  self:texts()
  self:oam()
  local g = love.graphics
  -- WIN0 (0..240, y $78..$98): BG1 (the description) only inside
  local full = p.dispcnt
  p.dispcnt = band(full, bit.bnot(0x0200))
  g.setColor(1, 1, 1, 1)
  g.draw(p:render("nowin"), 0, 0)
  p.dispcnt = full
  if band(self.column, 0x10) ~= 0 then
    g.setScissor(0, 0x78, 240, 0x20)
    local ok = pcall(function() g.draw(p:render("win"), 0, 0) end)
    g.setScissor()
    if not ok then g.setScissor() end
  end
  if (self.bright or 0) > 0 then
    g.setColor(1, 1, 1, self.bright / 16)
    g.rectangle("fill", 0, 0, 240, 160)
  end
  if self.fadeIn > 0 then
    g.setColor(0, 0, 0, self.fadeIn / 8)
    g.rectangle("fill", 0, 0, 240, 160)
  end
  g.setColor(1, 1, 1, 1)
end
M.Menu32 = Menu32

-- ---------------------------------------------------------------------------
-- the R27A interface
-- ---------------------------------------------------------------------------
function M.frame(f, input)
  local m = f.figMenu32
  if m then
    if not pcall(m.update, m, input) then f.figMenu32 = nil end
    return true
  end
  local r = f.room
  if not r then return false end
  local list = {}
  for _, e in ipairs(f.entities) do if e.kind == 6 and e.id == M.ID and not e.deleted then list[#list + 1] = e end end
  local block = false
  for _, e in ipairs(list) do
    if e.fig32 ~= r then init(f, e) end
    update(f, e, input)
    if (e.form or 0) == 3 and e.u7a == 1 then block = true end
  end
  if f.figCounter32 and not block then f.figCounter32 = nil end
  return block
end

function M.draw(f)
  local m = f.figMenu32
  if m then
    local ok = pcall(m.render, m)
    if not ok then love.graphics.setScissor() end
    return
  end
  local p = f.figCounter32
  if p then
    local img = p:render()
    if img then love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(img, 0, 0) end
  end
end

return M
