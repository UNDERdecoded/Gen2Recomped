-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- AN UNDERGROUND VENDOR'S SHOP (pokeplatinum src/underground/vendors.c,
-- UndergroundVendors_ShopMenuTask 625-933), single player.
--
-- READ FROM CODE (messages are bank 636, TEXT_BANK_UNDERGROUND_NPCS):
--   * intro 0 (27 for a treasure vendor), then the options: traps GET TRAP 13
--     / GIVE TRAP 14 / EXIT 15, goods 16 / 17 / 18, treasures GIVE TREASURES
--     28 / CANCEL 22; B or EXIT -> 9 and the shop closes;
--   * GET: the five rows of Gen4UgWorld.stock + a close row, the required
--     sphere beside them (23, then 25 "{sphere} {size}"); a row -> 1 "Which
--     Sphere will you trade me for my ...?" -> the sphere pocket (19);
--     TryBuyItem (218-246): the wrong type 4, too small 5, no room 3, else the
--     whole sphere goes -- no change -- 2, then 6 "... was obtained!"; every
--     outcome then 8 "Do you need anything else?" and the options again;
--   * GIVE: the traps / goods bag / treasures, each row's offer beside it
--     (24, 25 or 26 NOT FOR SALE: A does nothing); A -> 10 "You'll trade your
--     ... for my ...?" YES/NO; YES -> a full sphere pocket 3, else the item
--     goes, 11, 7 "You obtained a ..., size ..."; NO -> 9 and the shop closes.
-- INFERRED: the layout (the port's boxes); sounds by their SDAT names.

local Font = require("src.render.Font")
local Pockets = require("src.ui.Gen4UgPockets")

local S = {}
S.__index = S
S.isOpaque = false
function S:uiSize() return 256, 192 end

local function W() return require("src.world.Gen4UgWorld") end
local function UG() return require("src.world.Gen4Underground") end
local function npcs(game, idx, slots) return Pockets.text(game, W().BANK.npcs, idx, slots) end

S.OPTIONS = {
  traps = { { "get", 13 }, { "give", 14 }, { "exit", 15 } },
  goods = { { "get", 16 }, { "give", 17 }, { "exit", 18 } },
  treasures = { { "give", 28 }, { "exit", 22 } },
}

function S.new(game, vendorIndex, opts)
  opts = opts or {}
  local v = W().VENDORS[vendorIndex + 1]
  local self = setmetatable({ game = game, vendor = vendorIndex, kind = v and v[1] or "goods", opts = opts,
    state = "message", index = 1, queue = {} }, S)
  self:say(npcs(game, self.kind == "treasures" and 27 or 0), "options")
  return self
end

function S:say(text, after)
  self.msg = text; self.after = after; self.state = "message"
  if after == "confirm" then self.confirmText = text end
end

function S:natDex()
  local s = self.game.save
  local d = s and s.pokedex
  return (d and (d.national or d.nationalDex)) and true or false
end

function S:close()
  if self.closed then return end
  self.closed = true
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.opts.onClose then self.opts.onClose() end
end

local function se(self, name)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, name) end
end

function S:itemName(id)
  if self.kind == "traps" then return Pockets.trapName(self.game, id) end
  if self.kind == "goods" then return Pockets.goodName(self.game, id) end
  return Pockets.itemName(self.game, id)
end

function S:endTransaction() self:say(npcs(self.game, 8), "options") end

-- TryBuyItem with the sphere in pocket slot `slot`
function S:pay(row, slot)
  local save = self.game.save
  local sphere = UG().spheres(save)[slot]
  if not sphere then return self:endTransaction() end
  if sphere.type ~= row.type then return self:say(npcs(self.game, 4), "end") end
  if sphere.size < row.size then return self:say(npcs(self.game, 5), "end") end
  local ok
  if self.kind == "traps" then ok = UG().addTrap(save, row.id) else ok = W().addGoodBag(save, row.id) end
  if not ok then return self:say(npcs(self.game, 3), "end") end
  table.remove(UG().spheres(save), slot)
  self.bought = row
  return self:say(npcs(self.game, 2), "obtained")
end

function S:openPay(row)
  local game = self.game
  game.stack:push(Pockets.new(game, { kind = "spheres", mode = "pay",
    onPick = function(slot)
      local top = game.stack:top()
      if top and top.close then top:close() end
      self:pay(row, slot)
    end,
    onClose = function() if self.state == "paying" then self.state = "buy" end end }))
  self.state = "paying"
end

function S:openSell()
  local game = self.game
  local kind = self.kind
  local pocket
  pocket = Pockets.new(game, { kind = kind, mode = "sell",
    offer = function(id) return W().offer(game.save, game.data, self.vendor, kind, id) end,
    onPick = function(slot, e)
      local id = (kind == "spheres") and e.type or e
      local t, size = W().offer(game.save, game.data, self.vendor, kind, id)
      if not t or t == 0 then return end
      pocket:close()
      self.selling = { slot = slot, id = id, type = t, size = size }
      self.yes = 1
      self:say(npcs(game, 10, { [2] = self:itemName(id), [4] = Pockets.itemName(game, t) }), "confirm")
    end,
    onClose = function() if self.state == "selling" then self:endTransaction() end end })
  game.stack:push(pocket)
  self.state = "selling"
end

function S:confirmSell(yes)
  local game = self.game
  local sl = self.selling
  self.selling = nil
  if not yes then return self:say(npcs(game, 9), "close") end
  if not W().addSphere(game.save, sl.type, sl.size) then return self:say(npcs(game, 3), "end") end
  local list
  if self.kind == "traps" then list = UG().traps(game.save)
  elseif self.kind == "goods" then list = W().goodsBag(game.save)
  else list = W().treasures(game.save) end
  table.remove(list, sl.slot)
  self.gotSphere = sl
  return self:say(npcs(game, 11), "gotSphere")
end

function S:advance()
  local after = self.after
  self.msg = nil
  if after == "options" then self.state = "options"; self.index = 1
  elseif after == "close" then return self:close()
  elseif after == "end" then return self:endTransaction()
  elseif after == "obtained" then
    se(self, "SEQ_SE_DP_KIRAKIRA")
    return self:say(npcs(self.game, 6, { [2] = self:itemName(self.bought.id) }), "end")
  elseif after == "gotSphere" then
    local s = self.gotSphere
    return self:say(npcs(self.game, 7, { [2] = Pockets.itemName(self.game, s.type), [6] = ("%2d"):format(s.size) }), "end")
  elseif after == "confirm" then self.state = "confirm"
  elseif after == "pick" then self:openPay(self.picked)
  end
end

function S:update()
  local input = self.game.input
  if self.state == "message" then
    if input:wasPressed("a") or input:wasPressed("b") then se(self, "SEQ_SE_CONFIRM"); self:advance() end
    return
  end
  if self.state == "paying" or self.state == "selling" then return end
  if self.state == "confirm" then
    if input:wasPressed("up") or input:wasPressed("down") then self.yes = 3 - self.yes end
    if input:wasPressed("a") then return self:confirmSell(self.yes == 1) end
    if input:wasPressed("b") then return self:confirmSell(false) end
    return
  end
  local rows = self:rows()
  if input:wasPressed("up") then self.index = (self.index - 2) % #rows + 1 end
  if input:wasPressed("down") then self.index = self.index % #rows + 1 end
  if input:wasPressed("b") then
    if self.state == "buy" then self.state = "options"; self.index = 1 return end
    return self:say(npcs(self.game, 9), "close")
  end
  if input:wasPressed("a") then
    se(self, "SEQ_SE_CONFIRM")
    local r = rows[self.index]
    if self.state == "options" then
      if r.id == "exit" then return self:say(npcs(self.game, 9), "close") end
      if r.id == "get" then
        self.stock = W().stock(self.game.save, self.game.data, self.vendor, self:natDex())
        self.state = "buy"; self.index = 1
        return
      end
      return self:openSell()
    end
    if self.state == "buy" then
      if not r.row then self.state = "options"; self.index = 1 return end
      self.picked = r.row
      return self:say(npcs(self.game, 1, { [2] = self:itemName(r.row.id) }), "pick")
    end
  end
end

function S:rows()
  if self.state == "buy" then
    local out = {}
    for _, row in ipairs(self.stock or {}) do out[#out + 1] = { label = self:itemName(row.id), row = row } end
    local close = Pockets.text(self.game, self.kind == "traps" and W().BANK.traps or W().BANK.goods, 0)
    out[#out + 1] = { label = close }
    return out
  end
  local out = {}
  for _, o in ipairs(S.OPTIONS[self.kind] or {}) do out[#out + 1] = { id = o[1], label = npcs(self.game, o[2]) } end
  return out
end

local function ink() Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } }) end

function S:draw()
  if self.state == "options" or self.state == "buy" then
    local rows = self:rows()
    Font.drawBox(15, 1, 16, #rows * 2 + 2)
    ink()
    for i, r in ipairs(rows) do
      local y = 16 + (i - 1) * 16
      Font.draw(r.label, 136, y)
      if i == self.index then Font.drawCode(require("src.ui.Theme").cursor, 126, y) end
    end
    Font.popStyle()
    if self.state == "buy" then
      local r = rows[self.index]
      Font.drawBox(0, 1, 14, 6)
      ink()
      Font.draw(npcs(self.game, 23), 12, 14)
      if r and r.row then Font.draw(Pockets.vendorSphere(self.game, r.row.type, r.row.size), 12, 30) end
      Font.popStyle()
    end
  end
  if self.state == "confirm" then
    Font.drawBox(24, 12, 7, 6)
    ink()
    local Strings = require("src.core.Strings")
    Font.draw(Strings("YES"), 208, 108); Font.draw(Strings("NO"), 208, 124)
    Font.drawCode(require("src.ui.Theme").cursor, 198, self.yes == 1 and 108 or 124)
    Font.popStyle()
  end
  local text = self.msg
  if self.state == "confirm" then text = self.confirmText end
  if text and text ~= "" then
    Font.drawDialogueBox(1, 18, 29, 6)
    ink()
    local y = 152
    for l in (text .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
    Font.popStyle()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return S
