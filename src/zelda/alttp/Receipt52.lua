-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 52: the receipts that count (rupees, bombs, arrows). A chest with
-- 50 rupees gave nothing in the port: G:getItem only knew the positive
-- kValueToGiveItemTo writes (Gear.lua), and wrote receipt 0x43 / 0x44's
-- value into the menu byte 0x56 instead of the arrow filler.
--
-- Traced on the GBA:
--   * AncillaAdd_ItemReceipt 0x080AC8AC (item = +0x175D): a positive
--     kValueToGiveItemTo (0x16E4A4) is stored at kMemoryLocationToGiveItemTo
--     (0x16E344) -- receipts 0x43 / 0x44 store 1 / 10 at 0x02002356, the
--     arrow filler. 0x24 (key) and the bombs (0x080ACB94..0x080ACBCE): 0x27
--     +1, 0x28 +3, 0x31 +10 to their location, 0x02002355 (the bomb filler),
--     at most 0x63.
--   * The rupees 0x080AD05C (item = +0xE29 + k, switch on item - 0x34, jump
--     table 0x080AD08C): 0x34..0x36 -> 0x16E525[item - 0x34], 0x40 / 0x41
--     -> 0x16E525[(item + 0xC3) & 0xFF], 0x47 -> 0x16E525[2], 0x46 ->
--     0x12C (movs 0x2C at 0x080AD0F4, high byte 1 at 0x080AD0FC); then
--     AddRupees 0x080AA83C -> the rupee goal 0x02002340 (the real count;
--     the HUD's number 0x02002342 follows it one a frame, at most 999,
--     0x080A7284..0x080A72D6).
--   * Hud_RefillLogic (0x080A72F4 / 0x080A7316): while the bomb / arrow
--     filler is not 0 it counts down by one a frame and the bombs
--     (0x02002323) / arrows (0x02002357) go up by one, stopping at
--     kMaxBombs / kMaxArrows[upgrade] (0x16B588 / 0x16B598).
--
-- From the ROM at import: the rupee amounts, the 300 immediates, the bomb
-- immediates (the arrow values are Gear.lua's kValueToGiveItemTo).
-- OURS: the HUD shows the rupee count at once (the port has no rupee goal).

local bit = require("bit")
local band = bit.band

local M = {}

M.OFF = { rupees = 0x16E525 }
M.SITES = { r300lo = 0x080AD0F4, r300hi = 0x080AD0FC, bomb1 = 0x080ACB94, bomb3 = 0x080ACBAA, bomb10 = 0x080ACBB4 }
M.RUPEE_IDX = { [0x34] = 0, [0x35] = 1, [0x36] = 2, [0x40] = 3, [0x41] = 4, [0x47] = 2 }
M.BOMB_ID = { [0x27] = "bomb1", [0x28] = "bomb3", [0x31] = "bomb10" }
M.ARROW_ID = { [0x43] = true, [0x44] = true }

local function imm8(rom, at)
  local op = rom:u16(at - 0x08000000)
  if band(op, 0xF800) ~= 0x2000 then return nil end   -- movs rN, #imm8
  return band(op, 0xFF)
end

function M.extract(rom, R, check)
  local S = M.SITES
  local t = { rupees = rom:bytesU8(M.OFF.rupees, 5), bombs = {} }
  local lo, hi = imm8(rom, S.r300lo), imm8(rom, S.r300hi)
  local ok = lo ~= nil and hi ~= nil
  if ok then t.r300 = hi * 256 + lo end
  for k, at in pairs({ bomb1 = S.bomb1, bomb3 = S.bomb3, bomb10 = S.bomb10 }) do
    t.bombs[k] = imm8(rom, at)
    ok = ok and t.bombs[k] ~= nil
  end
  check(ok and t.rupees[1] < t.rupees[2] and t.rupees[2] < t.rupees[3] and t.rupees[4] > t.rupees[5]
        and t.r300 > t.rupees[4] and t.bombs.bomb1 < t.bombs.bomb3 and t.bombs.bomb3 < t.bombs.bomb10,
        "receipt rupee amounts and bomb counts")
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.rcpt52 end
M.tabs = T

-- the amount a receipt adds to the rupees (nil: not a rupee receipt)
function M.rupeesOf(tb, id)
  if id == 0x46 then return tb.r300 end
  local i = M.RUPEE_IDX[id]
  return i and tb.rupees[i + 1] or nil
end

local function maxOf(game, kind)
  local ui = game.data and game.data.ui or {}
  local st = game.stats
  if kind == "bombs" then return (ui.maxBombs and ui.maxBombs[(st.bombLevel or 0) + 1]) or 10 end
  return (ui.maxArrows and ui.maxArrows[(st.arrowLevel or 0) + 1]) or 30
end

-- Hud_RefillLogic: one bomb / arrow a frame from the fillers
function M.refill(game)
  local st = game.stats
  if not st then return end
  if (game.bombFill or 0) > 0 then
    game.bombFill = game.bombFill - 1
    if (st.bombs or 0) ~= maxOf(game, "bombs") then st.bombs = (st.bombs or 0) + 1 end
  end
  if (game.arrowFill or 0) > 0 then
    game.arrowFill = game.arrowFill - 1
    if (st.arrows or 0) ~= maxOf(game, "arrows") then st.arrows = (st.arrows or 0) + 1 end
  end
end

function M.install(G)
  local get0 = G.getItem
  function G:getItem(id)
    local tb = T(self)
    if not tb then return get0(self, id) end
    local p = self.progress
    local inv56 = p.inv and p.inv[0x56]
    local r = get0(self, id)
    local st = self.stats
    local n = M.rupeesOf(tb, id)
    if n then
      st.rupees = math.min(999, (st.rupees or 0) + n)
      self.rupeeReceipts = (self.rupeeReceipts or 0) + 1
    elseif M.BOMB_ID[id] then
      self.bombFill = math.min(0x63, (self.bombFill or 0) + tb.bombs[M.BOMB_ID[id]])
    elseif M.ARROW_ID[id] then
      -- a positive kValueToGiveItemTo is stored (not added) at the filler
      local gear = self.data.t and self.data.t.gear
      local v = gear and gear.value and gear.value[id + 1]
      if v and v > 0 then self.arrowFill = v end
      if p.inv then p.inv[0x56] = inv56 end   -- (not a menu byte in the port)
    end
    return r
  end
  local up0 = G.update
  function G:update(dt)
    local r = up0(self, dt)
    if T(self) and (self.state == "play" or self.state == "room") and not self.menu then M.refill(self) end
    return r
  end
end

return M
