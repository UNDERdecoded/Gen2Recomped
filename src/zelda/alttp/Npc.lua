-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PEOPLE (round 16): the townsfolk of Kakariko and the way to Sahasrahla.
--
-- Overworld sprites per area and story phase: the GBA's 0x080CB140 picks
-- one of three u32 tables by sram_progress_indicator (RAM byte; 2 ->
-- 0x227E70, 3 -> 0x2280B0, else 0x227D70, the first one only for the 64
-- Light World areas) and walks the area's list of { y, x, type } (16 px
-- units from the area's corner; type 0xFA is a counter marker, SNES 0xF4)
-- until 0xFF -- SNES Overworld_LoadSprites / kOverworldSprites.
--
-- The people here (SNES zelda3 names; the draw tables are the GBA's copies
-- of the SNES DrawMultipleData, 8 bytes an entry, found by their x / y /
-- size and the SNES -> GBA OBJ char mapping, r16/py/dmdsearch.py):
--
--   0x16 Sahasrahla (Sprite_16_Elder: Sasha_Idle, Elder_Draw)   message 0x32,
--        then 0x33 (marks the map: savegame_map_icons_indicator = 3)
--   0x78 his wife (Sprite_78_MrsSahasrahla, ElderWife_Draw)    0x2B, the
--        legend 0x2C, then 0x2D (after the choice "yes")
--   0x2A the sweeping lady (Sprite_SweepingLady)                0xA5
--   0x3C the boy at the trough (Sprite_TroughBoy, faces Link)   0x147 / 0x148
--   0x34 / 0x3D the snitch ladies (Sprite_OldSnitchLady): indoors 0xAD;
--        OURS: outdoors they stand (their run to the guards is not ported)
--
-- They stand where the cartridge puts them, turn and animate as their
-- routines do, block Link (Sprite_BehaveAsBarrier) and talk when Link faces
-- them and presses A (Sprite_ShowSolicitedMessage). Round 22: message
-- 0x2C's choice cursor is the cartridge's (Text.lua); "Not at all" repeats it.

local bit = require("bit")
local band, bxor = bit.band, bit.bxor

local N = {}

-- ---------------------------------------------------------------- import
function N.extract(rom, R, check)
  local M = R.npc
  local out = { ow = {}, dmd = {} }
  for phase, spec in ipairs(M.owSprites) do
    local lists = {}
    for a = 0, spec[2] - 1 do
      local p = rom:ptr(spec[1] + a * 4)
      check(p, "overworld sprite list %d/%02X", phase, a)
      local list = {}
      for k = 0, 63 do
        local y = rom:u8(p + k * 3)
        if y == 0xFF then break end
        local x, t = rom:u8(p + k * 3 + 1), rom:u8(p + k * 3 + 2)
        if t ~= 0xFA then list[#list + 1] = { y, x, t } end
      end
      lists[a + 1] = list
    end
    out.ow[phase] = lists
  end
  for name, spec in pairs(M.dmd) do
    local t = {}
    for i = 0, spec[2] - 1 do
      local p = spec[1] + i * 8
      local x, y = rom:u16(p), rom:u16(p + 2)
      t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                   rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
    end
    out.dmd[name] = t
  end
  -- Kakariko after the escape holds the sweeping lady and the trough boy
  local kak = out.ow[2][0x18 + 1]
  local seen = {}
  for _, e in ipairs(kak) do seen[e[3]] = true end
  check(seen[0x2A] and seen[0x3C], "overworld sprite lists (Kakariko)")
  check(out.dmd.elder[1][5] == 2 and out.dmd.wife[1][5] == 2, "people draw tables")
  return out
end

-- ---------------------------------------------------------------- types
-- SNES OAM direction (sprite_D: 0 right, 1 left, 2 down, 3 up) from the
-- NPC to Link (Sprite_DirectionToFaceLink)
local function faceLink(a, lk)
  local dx, dy = (lk.x) - a.x, (lk.y) - a.y
  if math.abs(dx) >= math.abs(dy) then return dx >= 0 and 0 or 1 end
  return dy >= 0 and 2 or 3
end
N.faceLink = faceLink

N.TYPES = {
  [0x16] = { dmd = "elder", frame = function(a, f) return math.floor(f / 32) % 2 end, shadow = true },
  [0x78] = { dmd = "wife", frame = function(a, f) return math.floor(f / 16) % 2 end, prep = { 8, 8 } },
  [0x2A] = { dmd = "sweep", frame = function(a, f) return math.floor(f / 16) % 2 end, shadow = true },
  [0x3C] = { dmd = "trough", frame = function(a) return a.npcD or 2 end, shadow = true, faces = true },
  [0x34] = { dmd = "snitch", frame = function(a, f) return (a.npcD or 2) * 2 + math.floor(f / 16) % 2 end,
             shadow = true, faces = true },
  [0x3D] = { dmd = "lady", frame = function(a, f) return (a.npcD or 2) * 2 + math.floor(f / 16) % 2 end,
             shadow = true, faces = true },
  -- r22: the shop clerk (Shop.lua; Shopkeeper_Draw: frame_counter >> 4 & 1)
  [0xBB] = { dmd = "shop", frame = function(a, f) return math.floor(f / 16) % 2 end, shadow = true },
}

-- the message an NPC gives now, and what happens after it
function N.talk(game, a)
  local t = a.type
  local p = game.progress
  local msg, after
  -- r19: the boots are GBA inventory byte 0x39 (SNES link_item_boots 0x55;
  -- the GBA's bytes from the gloves on are the SNES's - 0x1C: gloves 0x38,
  -- the menu's ability box 0x39 / 0x38 / 0x3A / 0x3B, sword 0x3D). Round 18
  -- wrote 0x35, which is item slot 22 (the magic cape): a round-18 file with
  -- 0x35 counts as having them (and is moved to 0x39)
  local function hasBoots()
    if p.inv and (p.inv[0x35] or p.inv["53"]) and not (p.inv[0x39] or p.inv["57"]) then
      p.inv[0x35], p.inv["53"], p.inv[0x39] = nil, nil, 1
    end
    return p.inv and (p.inv[0x39] or p.inv["57"]) and true or false
  end
  if t == 0x16 and bit.band(p.pendants or 0, 4) ~= 0 and not hasBoots() then
    -- round 18, Sasha_Idle with the Pendant of Courage and no boots: 0x38
    -- (0x39 when the map was not marked), then Sprite_Sahasrahla state 2
    -- gives the Pegasus Boots (Link_ReceiveItem(0x4B); GBA inventory byte
    -- 0x39 = SNES link_item_boots), then state 3: 0x37 (the ice rod hint)
    msg = ((p.mapIcons or 0) >= 3) and 0x38 or 0x39
    after = function(g)
      g.progress.inv = g.progress.inv or {}
      g.progress.inv[0x39] = 1
      g.progress.mapIcons = 3
      g:getItem(0x4B)
      local rm = g:receiptMessage(0x4B)
      local function hint(g2) g2:showMessage(0x37); g2.onTextDone = function(g3) g3.progress.gotBoots = true end end
      if rm and g:showMessage(rm) then g.onTextDone = hint else hint(g) end
    end
  elseif t == 0x16 and bit.band(p.pendants or 0, 4) ~= 0 then
    msg = 0x37        -- boots already: the ice rod hint (until the ice rod)
  elseif t == 0x16 then
    -- Sasha_Idle: no Pendant of Courage yet -> 0x32, then 0x33 marks the map
    msg = 0x32
    after = function(g)
      g:showMessage(0x33)
      g.onTextDone = function(g2) g2.progress.mapIcons = 3; g2.progress.metSahasrahla = true end
    end
  elseif t == 0x78 then
    -- MrsSahasrahla: 0x2B, the legend 0x2C, 0x2D (r22: Sprite_78's state
    -- 2: "Not at all" (choice 1) tells the legend again, "Yes" goes on)
    if (a.npcState or 0) >= 3 then msg = 0x2D
    else
      msg = 0x2B
      local function legend(g)
        g:showMessage(0x2C)
        g.onTextDone = function(g2)
          if (g2.lastChoice or 0) ~= 0 then return legend(g2) end
          g2:showMessage(0x2D)
          a.npcState = 3
          g2.onTextDone = function(g3) g3.progress.wifeHint = true end
        end
      end
      after = legend
    end
  elseif t == 0x2A then msg = 0xA5
  elseif t == 0xBB then
    -- r22: the clerk's solicited message (Shop.lua); a ware is bought, not talked to
    if a.shopItem or not a.clerk then return false end
    msg = require("src.zelda.alttp.Shop").MSG_HELLO
  elseif t == 0x3C then
    if (p.mapIcons or 0) < 3 then
      msg = 0x147
      after = function(g) g.progress.mapIcons = math.max(g.progress.mapIcons or 0, 2) end
    else msg = 0x148 end
  elseif t == 0x34 or t == 0x3D then
    if game.state == "room" then msg = 0xAD end
  end
  if not msg then return false end
  game:showMessage(msg)
  game.onTextDone = after
  game.npcTalks = (game.npcTalks or 0) + 1
  game.lastNpcMsg = msg
  return true
end

-- per-frame: the ones that face Link (Sprite_DirectionToFaceLink ^ 3 for
-- the trough boy's head and the ladies)
function N.update(game, list)
  for _, a in ipairs(list) do
    local spec = N.TYPES[a.type]
    if spec and spec.faces and not a.dead then a.npcD = bxor(faceLink(a, game.link), 0) end
  end
end

-- draw through Sprites (Sprite_DrawMultiplePlayerDeferred with the type's
-- OAM flags); returns true when drawn
function N.draw(spr, a, x, y, frame)
  local spec = N.TYPES[a.type]
  local t = spr.data.t and spr.data.t.npc
  if not (spec and t) then return false end
  local list = t.dmd[spec.dmd]
  if not list then return false end
  if a.shopItem then return false end   -- r22: a ware (Shop.draw)
  local f = band(spr.info.flags3[a.type + 1] or 0, 0x0F)
  local j = spec.frame(a, frame or 0)
  spr:drawDmd(a, list, j * 2, 2, x, y, f)
  return true
end

-- ---------------------------------------------------------------- game
-- spawn an area's people (the overworld actor list, OwActors.lua)
function N.spawnArea(game, oa)
  local t = game.data.t and game.data.t.npc
  if not t or not game.area then return end
  local parent = game.area.parent
  local prog = game:storyProgress()
  local phase = (prog == 2 and 2) or (prog == 3 and 3) or 1
  local lists = t.ow[phase]
  local list = lists and lists[(phase == 1 and parent or parent) + 1]
  if phase == 1 and parent >= 64 then list = nil end
  if not list then return end
  local bx = (parent % 8) * 512
  local by = math.floor((parent % 64) / 8) * 512
  for _, e in ipairs(list) do
    local spec = N.TYPES[e[3]]
    if spec then
      local a = { type = e[3], x = bx + e[2] * 16 + (spec.prep and spec.prep[1] or 0),
                  y = by + e[1] * 16 + (spec.prep and spec.prep[2] or 0),
                  npc = true, state = "idle", dir = 1, t = 0, hp = 255, lower = false }
      oa.list[#oa.list + 1] = a
    end
  end
  -- r23: the desert's statues and plaque (Desert.lua)
  require("src.zelda.alttp.Desert").spawnArea(game, oa, list, bx, by)
end

-- install into Game: overworld people per area, talking with A
function N.install(G)
  local updOw = G.updateOwActors
  function G:updateOwActors()
    if self.state == "play" and self.area and self.data.t and self.data.t.npc then
      local oa = self.owActors
      if not oa or oa.areaKey ~= self.area.parent or oa.world ~= self.link.world then
        self.owActors = nil
        oa = self:owActorList()
        N.spawnArea(self, oa)
      end
      N.update(self, oa.list)
    end
    return updOw(self)
  end
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if inp.a and self.owActors and not self.textBox then
      local Carry = require("src.zelda.alttp.Carry")
      local q = Carry.QUERY and Carry.QUERY[self.link.facing]
      local lk = self.link
      local px, py = lk.x + (q and q[1] or 8), lk.y + (q and q[2] or 16)
      for _, a in ipairs(self.owActors.list) do
        if a.npc and not a.dead and px >= a.x - 2 and px < a.x + 18 and py >= a.y - 2 and py < a.y + 18 then
          if N.talk(self, a) then return true end
        end
      end
    end
    return owFrame(self, inp)
  end
end

-- overworld: is (x, y) inside a person (they block Link)?
function N.solidAt(oa, x, y)
  if not oa then return false end
  for _, a in ipairs(oa.list) do
    if a.npc and not a.dead and x >= a.x and x < a.x + 16 and y >= a.y and y < a.y + 16 then return true end
    -- r23: a barrier with its own box (the desert statues, Desert.lua)
    local b = a.box
    if b and not a.dead and x >= a.x + b[1] and x < a.x + b[1] + b[3] and y >= a.y + b[2] and y < a.y + b[2] + b[4] then return true end
  end
  return false
end

return N
