-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE HIDDEN CHESTS (round 70). A room whose header tag (either slot) is
-- 0x27, 0x3C, 0x3E or 0x29..0x32 keeps its chests hidden until the tag
-- reveals them. Traced on the GBA (zelda3 names):
--
--   Dungeon_LoadAttribute, chest part (0x08082500..0x08082548): the tags at
--     +0x9E6 / +0x9E7 are compared with 0x27, 0x3C, 0x3E and (tag - 0x29) <= 9;
--     any of them skips the whole chest loop -- no 0x58 + n attributes.
--     The pre-rendered room maps hold no chest picture there either.
--   0x0807D3E4 (at load): a hidden tag whose room flag bit (+0xAA8 & the
--     slot's bit) is already set is cleared, so a revealed room stays open.
--   RoomTag_OperateChestReveal (0x0807A478): for each chest location
--     (+0xC52, & 0x7FFF) the closed chest's four map words (the chest tile
--     table, Extract's items.chestClosed) go into the map and the chest
--     attribute pair (+0x978, 0x5858, + 0x101 per chest) into the attribute
--     table.
--   Tag 0x27 (0x0807B71C): Link not blinking and a switch pressed -> the
--     reveal (Palace.roomTags already calls inside:revealChests() for it;
--     the method was missing). Tags 0x29..0x2E (0x0807B851.. = tags 1..6's
--     quadrant tests) -> RoomTag_QuadrantTrigger (0x0807B43C): tag > 0x28
--     and the screen clear (0x080CAEC0) -> the reveal instead of the doors.
--     0x2F..0x31 are tags 7..9's tests, 0x32 tag 0x0A's (the whole room).
--
-- Before this round the port marked every chest at load, so a hidden chest
-- could be opened or hooked before it was there (the Ice Palace's 0x7E
-- Freezor chest across the pit, 0xAE / 0x5F / 0x3F's switch chests).
-- No ROM reads here: the chest words are Extract's (data.t.items).

local bit = require("bit")
local band = bit.band

local M = {}

function M.extract(rom, R, check) return {} end

function M.hiddenTag(t)
  t = t or 0
  return t == 0x27 or t == 0x3C or t == 0x3E or (t >= 0x29 and t <= 0x32)
end

-- the room's tags that hide its chests (slot -> tag)
function M.hidingTags(inside)
  local hdr = inside.hdr or {}
  local out = {}
  for slot, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
    if M.hiddenTag(tag) then out[slot] = tag end
  end
  return out
end

-- after markChests: hide the chests again unless the room was revealed
function M.hide(inside, before)
  if not next(M.hidingTags(inside)) then return 0 end
  local mem = inside.mem or {}
  if mem.chestShown then require("src.zelda.alttp.Chest74").redraw(inside) return 0 end   -- r74
  for n in pairs(mem.chests or {}) do if mem.chests[n] then return 0 end end
  local n = 0
  for _, c in ipairs(inside.chests or {}) do
    if not c.lock and not c.opened then
      local A, Gd = inside.attrs, inside.grid
      if c.lower then A, Gd = inside.attrsLo, inside.gridLo end
      for _, cell in ipairs(c.cells) do
        local b = before[cell]
        A[cell] = b and b[1] or 0
        Gd[cell] = b and b[2] or false
      end
      c.hidden = true
      n = n + 1
    end
  end
  inside.chestsHidden70 = n
  return n
end

-- RoomTag_OperateChestReveal
function M.reveal(inside)
  local it = inside.data and inside.data.t and inside.data.t.items
  local n = 0
  for _, c in ipairs(inside.chests or {}) do
    if c.hidden then
      c.hidden = nil
      local A, Gd = inside.attrs, inside.grid
      if c.lower then A, Gd = inside.attrsLo, inside.gridLo end
      for _, cell in ipairs(c.cells) do A[cell] = c.attr; Gd[cell] = true end
      local patch = (c.lower and inside.patch1) or inside.patch
      if it and it.chestClosed and patch and c.w ~= 4 then
        local o = it.chestClosed
        patch[c.y * 64 + c.x] = o[1]
        patch[(c.y + 1) * 64 + c.x] = o[2]
        patch[c.y * 64 + c.x + 1] = o[3]
        patch[(c.y + 1) * 64 + c.x + 1] = o[4]
      end
      n = n + 1
    end
  end
  if inside.mem then inside.mem.chestShown = true end
  inside.chestsHidden70 = 0
  return n
end

-- tags 0x29..0x32: tags 1..10's kill rule, the chests instead of the doors
local HERE = function(q, lk)
  local rx, ry = lk.x >= 256, lk.y >= 256
  return ({ [1] = not rx and not ry, [2] = rx and not ry, [3] = not rx and ry, [4] = rx and ry,
            [5] = not rx, [6] = rx, [7] = not ry, [8] = ry, [9] = true, [10] = true })[q]
end
function M.killTags(actors, lk)
  local game, inside = actors.game, actors.inside
  if not inside or not inside.mem or inside.mem.chestShown then return false end
  if (inside.chestsHidden70 or 0) == 0 then return false end
  local Ac = require("src.zelda.alttp.Actors")
  for _, tag in pairs(M.hidingTags(inside)) do
    if tag >= 0x29 and tag <= 0x32 then
      local q = tag - 0x28
      if HERE(q, lk) then
        local qx, qy = math.floor((lk.x + 8) / 256), math.floor((lk.y + 12) / 256)
        local clear = true
        for _, a in ipairs(actors.list or {}) do
          if not a.dead and Ac.fights(a.type) and (q == 10 or (math.floor((a.x + 8) / 256) == qx
             and math.floor((a.y + 8) / 256) == qy)) then clear = false break end
        end
        if clear and require("src.zelda.alttp.Effects").dying(game) then clear = false end
        if clear then
          M.reveal(inside)
          game.roomImages = nil
          game.chestReveals70 = (game.chestReveals70 or 0) + 1
          return true
        end
      end
    end
  end
  return false
end

function M.install(G)
  local I = require("src.zelda.alttp.Interior")
  if not I.chest70 then
    I.chest70 = true
    local mark0 = I.markChests
    function I:markChests()
      -- the cells' attributes before the chests are marked
      local before = {}
      local idx = self.data.roomIdx
      local list = idx.specials and idx.specials[self.room + 1]
      for _, o in ipairs(list or {}) do
        if o.s == 3 and (o.id == 0x19 or o.id == 0x31) then
          local w = (o.id == 0x31) and 4 or 2
          local A, Gd = self.attrs, self.grid
          if o.layer == 2 then A, Gd = self.attrsLo, self.gridLo end
          for dy = 0, 2 do for dx = 0, w - 1 do
            local cell = (o.y + dy) * 64 + o.x + dx
            if A and before[cell] == nil then before[cell] = { A[cell], Gd and Gd[cell] } end
          end end
        end
      end
      local r = mark0(self)
      self.chestsHidden70 = 0
      M.hide(self, before)
      return r
    end
    function I:revealChests() return M.reveal(self) end
  end
  local Pm = require("src.zelda.alttp.Palace")
  if not Pm.chest70 then
    Pm.chest70 = true
    local rt0 = Pm.roomTags
    function Pm.roomTags(self, lk)
      local r = rt0(self, lk)
      M.killTags(self, lk)
      return r
    end
  end
end

return M
