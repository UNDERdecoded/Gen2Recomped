-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- THE UNDERGROUND'S POCKETS: the TRAPS / SPHERES / GOODS / TREASURES lists of
-- the Underground menu (pokeplatinum src/underground/menus.c), and the same
-- lists in a vendor's "pay with a sphere" and "give" modes (vendors.c).
--
-- READ FROM CODE (menus.c):
--   * rows: a trap's name is bank 630 entry = trap id; a sphere row is common
--     128 "{name} {size}" (items 628 entry = sphere type, the size two digits,
--     zero padded); a treasure's name is items entry = treasure id; a good's
--     is goods 626 entry = good id; then a close row (traps 34, items 60,
--     goods 0). The description of the row under the cursor: traps 35 + id - 1,
--     items 62 + id, goods 139 + id - 1.
--   * choosing a row: common 129 "What would you like to do with this ...?"
--     and BURY 134 / TRASH 132 / CANCEL 133 for traps and spheres, TRASH /
--     CANCEL for goods, PUT IN BAG 135 / TRASH / CANCEL for treasures
--     (699-714);
--   * TRASH removes the row: 130 "Threw away the ..." (958-961, 1134-1138);
--   * PUT IN BAG: Underground_ConvertTreasureToBagItem and Bag_TryAddItem;
--     81 for Revive / Max Revive, 79 otherwise, 80 when the Bag is full
--     (1295-1313);
--   * BURY puts a trap (traps.c 1187-1221, 131 / 55 / 73 / 60 / 59) or a
--     sphere (spheres.c 329-390, 58 / 55 / 84 / 60 / 59) on the tile in front
--     and closes the menu; the Digger Drill makes a secret base (not built
--     here: refused with 55).
-- INFERRED: the layout -- a list window on the right with the description
-- box at the bottom -- is drawn with the port's own boxes.

local Font = require("src.render.Font")
local T = require("src.import.Gen4Text")

local P = {}
P.__index = P
P.isOpaque = false
function P:uiSize() return 256, 192 end

local function W() return require("src.world.Gen4UgWorld") end
local function UG() return require("src.world.Gen4Underground") end

function P.text(game, bank, idx, slots)
  local values = {}
  for i = 0, 6 do values[i + 1] = slots and slots[i] or "" end
  T.buffer(game, (table.unpack or unpack)(values))
  local s = T.resolve(game.data, bank, idx, game)
  return (s or ""):gsub("[\v\f]", "\n"):gsub("\r", "\n")
end

function P.itemName(game, id) return P.text(game, W().BANK.items, id) end
function P.trapName(game, id) return P.text(game, W().BANK.traps, id) end
function P.goodName(game, id) return P.text(game, W().BANK.goods, id) end
function P.sphereRow(game, sphereType, size)
  return P.text(game, W().BANK.common, 128, { [2] = P.itemName(game, sphereType), [6] = ("%02d"):format(size or 0) })
end

-- a vendor's "{sphere} {size}" (npcs 25, the size padded with a space)
function P.vendorSphere(game, sphereType, size)
  return P.text(game, W().BANK.npcs, 25, { [2] = P.itemName(game, sphereType), [6] = ("%2d"):format(size or 0) })
end

-- opts: { kind = "traps"|"spheres"|"goods"|"treasures", mode = "menu"|"pay"|"sell",
--         onPick = function(slot) (pay / sell), onClose = function(), ow = overworld,
--         offer = function(id) -> type, size (sell) }
function P.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, opts = opts, kind = opts.kind or "traps", mode = opts.mode or "menu",
    index = 1, top = 1, msg = nil, sub = nil, subIndex = 1 }, P)
  return self
end

function P:entries()
  local save = self.game.save
  if self.kind == "traps" then return UG().traps(save)
  elseif self.kind == "spheres" then return UG().spheres(save)
  elseif self.kind == "goods" then return W().goodsBag(save)
  else return W().treasures(save) end
end

function P:rowLabel(e)
  if self.kind == "traps" then return P.trapName(self.game, e)
  elseif self.kind == "spheres" then return P.sphereRow(self.game, e.type, e.size)
  elseif self.kind == "goods" then return P.goodName(self.game, e)
  else return P.itemName(self.game, e) end
end

function P:closeLabel()
  local B = W().BANK
  if self.kind == "traps" then return P.text(self.game, B.traps, 34) end
  if self.kind == "goods" then return P.text(self.game, B.goods, 0) end
  return P.text(self.game, B.items, 60)
end

function P:description(e)
  local B = W().BANK
  if e == nil then
    if self.kind == "traps" then return P.text(self.game, B.traps, 68) end
    if self.kind == "goods" then return P.text(self.game, B.goods, 139 + 139 - 1) end
    return P.text(self.game, B.items, 62)
  end
  if self.kind == "traps" then return P.text(self.game, B.traps, 35 + e - 1) end
  if self.kind == "spheres" then return P.text(self.game, B.items, 62 + e.type) end
  if self.kind == "goods" then return P.text(self.game, B.goods, 139 + e - 1) end
  return P.text(self.game, B.items, 62 + e)
end

function P:idOf(e)
  if self.kind == "spheres" then return e.type end
  return e
end

function P:close()
  if self.closed then return end
  self.closed = true
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.opts.onClose then self.opts.onClose() end
end

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, name) end
end

function P:say(text, after)
  self.msg = { text = text, after = after }
end

function P:subOptions()
  if self.kind == "traps" or self.kind == "spheres" then return { "bury", "trash", "cancel" } end
  if self.kind == "goods" then return { "trash", "cancel" } end
  return { "bag", "trash", "cancel" }
end
local SUB_ENTRY = { bury = 134, trash = 132, cancel = 133, bag = 135 }

function P:front()
  local ow = self.opts.ow or self.game.overworld
  local p = ow and ow.player
  if not (p and p.facingCell) then return nil end
  local fx, fy = p:facingCell()
  return ow, fx, fy
end

-- the chosen sub-option on row `slot`
function P:doOption(opt, slot)
  local save = self.game.save
  local B = W().BANK
  local e = self:entries()[slot]
  if not e then return end
  if opt == "cancel" then self.sub = nil return end
  self.sub = nil
  if opt == "trash" then
    local name = (self.kind == "spheres") and P.itemName(self.game, e.type) or self:rowLabel(e)
    table.remove(self:entries(), slot)
    se(self, "SEQ_SE_CONFIRM")
    return self:say(P.text(self.game, B.common, 130, { [2] = name }))
  end
  if opt == "bag" then
    local itemConst = require("src.import.Gen4Mining").TREASURE_ITEMS and require("src.import.Gen4Mining").TREASURE_ITEMS[e - 11]
    local id = itemConst and self:bagItemId(itemConst)
    local Bag = require("src.inventory.Bag")
    local ok = id and Bag.add(save, id, 1, self.game.data)
    local name = P.itemName(self.game, e)
    if ok then
      table.remove(self:entries(), slot)
      return self:say(P.text(self.game, B.common, (e == 29 or e == 30) and 81 or 79, { [0] = name, [1] = name, [2] = name }))
    end
    return self:say(P.text(self.game, B.common, 80, { [0] = name, [1] = name, [2] = name }))
  end
  if opt == "bury" then
    local ow, fx, fy = self:front()
    if not ow then return end
    if self.kind == "traps" then
      if e == 33 then return self:say(P.text(self.game, B.common, 55)) end
      local refusal, id = W().placeTrap(self.game, ow, slot, fx, fy)
      if refusal then return self:say(P.text(self.game, B.common, refusal)) end
      se(self, "SEQ_SE_DP_UG_008")
      return self:say(P.text(self.game, B.common, 131, { [3] = P.trapName(self.game, id) }), "exit")
    else
      local refusal, s = W().burySphere(self.game, ow, slot, fx, fy)
      if refusal then return self:say(P.text(self.game, B.common, refusal)) end
      return self:say(P.text(self.game, B.common, 58, { [0] = P.itemName(self.game, s.type), [1] = tostring(s.size) }), "exit")
    end
  end
end

function P:bagItemId(constant)
  local want = (constant:gsub("^ITEM_", ""):gsub("_", " ")):upper()
  for id, def in pairs(self.game.data.items or {}) do
    if type(def) == "table" and ((def.translationSourceName or def.name) or ""):upper() == want then
      local inv = self.game.save.inventory or {}
      if type(id) == "number" and inv[("ITEM_%03d"):format(id)] ~= nil then return ("ITEM_%03d"):format(id) end
      return id
    end
  end
  return nil
end

function P:choose(slot)
  local entries = self:entries()
  if slot > #entries then se(self, "SEQ_SE_CONFIRM") return self:close() end
  se(self, "SEQ_SE_CONFIRM")
  if self.mode == "pay" or self.mode == "sell" then
    if self.opts.onPick then return self.opts.onPick(slot, entries[slot]) end
    return
  end
  local e = entries[slot]
  -- the Digger Drill is used as it is chosen (menus.c 907: SecretBases_UseDiggerDrill)
  if self.kind == "traps" and e == 33 then
    local game = self.game
    local ow = self.opts.ow or game.overworld
    self:close()
    local top = game.stack:top()
    if top and top.isUndergroundMenu then top:close() end
    return require("src.ui.Gen4UgBaseUI").drill(game, ow, slot)
  end
  local name = (self.kind == "spheres") and P.itemName(self.game, e.type) or self:rowLabel(e)
  self.ask = P.text(self.game, W().BANK.common, 129, { [2] = name })
  self.sub = { slot = slot }
  self.subIndex = 1
end

function P:update()
  local input = self.game.input
  if self.msg then
    if input:wasPressed("a") or input:wasPressed("b") then
      local after = self.msg.after
      self.msg = nil
      if after == "exit" then
        -- the whole Underground menu goes after a bury (the field resumes)
        self:close()
        local top = self.game.stack:top()
        if top and top.isUndergroundMenu then top:close() end
      end
    end
    return
  end
  if self.sub then
    local opts = self:subOptions()
    if input:wasPressed("up") then self.subIndex = (self.subIndex - 2) % #opts + 1 end
    if input:wasPressed("down") then self.subIndex = self.subIndex % #opts + 1 end
    if input:wasPressed("a") then return self:doOption(opts[self.subIndex], self.sub.slot) end
    if input:wasPressed("b") then self.sub = nil end
    return
  end
  local n = #self:entries() + 1
  if input:wasPressed("up") then self.index = (self.index - 2) % n + 1; se(self, "SEQ_SE_CONFIRM") end
  if input:wasPressed("down") then self.index = self.index % n + 1; se(self, "SEQ_SE_CONFIRM") end
  if self.index > n then self.index = n end
  if input:wasPressed("a") then return self:choose(self.index) end
  if input:wasPressed("b") then return self:close() end
end

P.VISIBLE = 7

function P:draw()
  local g = love.graphics
  local entries = self:entries()
  local n = #entries + 1
  if self.index < self.top then self.top = self.index end
  if self.index >= self.top + P.VISIBLE then self.top = self.index - P.VISIBLE + 1 end
  Font.drawBox(15, 1, 16, P.VISIBLE * 2 + 2)
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
  for row = 0, P.VISIBLE - 1 do
    local i = self.top + row
    if i > n then break end
    local label = (i <= #entries) and self:rowLabel(entries[i]) or self:closeLabel()
    local y = 16 + row * 16
    Font.draw(label, 136, y)
    if i == self.index then Font.drawCode(require("src.ui.Theme").cursor, 126, y) end
  end
  Font.popStyle()
  if self.mode == "sell" and self.opts.offer and entries[self.index] then
    local t, size = self.opts.offer(self:idOf(entries[self.index]))
    Font.drawBox(0, 1, 14, 6)
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
    Font.draw(P.text(self.game, W().BANK.npcs, 24), 12, 14)
    if t and t ~= 0 then Font.draw(P.vendorSphere(self.game, t, size), 12, 30)
    else Font.draw(P.text(self.game, W().BANK.npcs, 26), 12, 30) end
    Font.popStyle()
  end
  local text
  if self.msg then text = self.msg.text
  elseif self.sub then text = self.ask
  else text = self:description(entries[self.index]) end
  if text and text ~= "" then
    Font.drawDialogueBox(1, 18, 29, 6)
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
    local y = 152
    for l in (text .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
    Font.popStyle()
  end
  if self.sub then
    local opts = self:subOptions()
    Font.drawBox(22, 9, 9, #opts * 2 + 2)
    Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
    for k, o in ipairs(opts) do
      local y = 80 + (k - 1) * 16
      Font.draw(P.text(self.game, W().BANK.common, SUB_ENTRY[o]), 196, y)
      if k == self.subIndex then Font.drawCode(require("src.ui.Theme").cursor, 186, y) end
    end
    Font.popStyle()
  end
  g.setColor(1, 1, 1, 1)
end

return P
