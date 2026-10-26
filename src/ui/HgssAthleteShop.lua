-- src/ui/HgssAthleteShop.lua -- HEARTGOLD / SOULSILVER'S POKeATHLON DOME
-- COUNTERS on the shop screen (src/ui/Gen4ShopMenu.lua, `install`): the
-- Athlete Shop's daily prizes (MART_TYPE_POKEATHLON_DAILY) and the Data Card
-- counter (MART_TYPE_DATA_CARDS), both paid in Athlete Points. Opened by
-- src/script/HgssPokeathlonShops.lua with opts.athlon = { kind, prices }.
--
-- READ FROM CODE (pokeheartgold src/overlay_03/shop_menu.c, asm/overlay_31.s):
--   * the list IS the price table (ov03_02256BEC / ov03_02256C84): the item
--     ids and the prices out of the MartItem rows, nothing from item data
--     (ShopMenu_GetItemPrice -> GetOverriddenPriceByItemID)
--   * the purse is the Athlete Points (MartData_BuyMenu_GetPlayerBalance),
--     shown as bank 435 #33 "Athlete Pts." and #32 "{n}P" (ov31_0225DE70),
--     a price as #19 "{n}P"
--   * choosing (ov03_02257874 -> MartData_BuyMenu_CheckCanPurchaseItem):
--     a daily prize whose LIST POSITION was taken today -> #25 "You can't
--     buy any more today!"; a Data Card already received -> #26 "You already
--     have this!"; too few points -> #48 "You don't have enough points!"
--     (ov31_0225E95C); no count dial: ONE, then the room check
--     (ov03_02257CA0: an Apricorn needs its box below 99, anything else room
--     in the Bag -- a Data Card too) and #46 "Would you like X?" with YES / NO
--   * YES (MartData_PerformTransaction): a prize goes in the Bag or, for an
--     Apricorn, the Apricorn Box, and its list position is marked for today;
--     a Data Card is NOT an item -- only its received bit (item - 505) is set;
--     the points are taken and GAME_STAT_CURRENCY_SPENT counts them; the line
--     is #49 "All right, here you go..." for a Data Card or an Apricorn, the
--     ordinary #15 "Here you are! ... Pocket." otherwise (ov31's martType
--     switch)
--   * "In Bag" for an Apricorn is the box's count (ov03_02257978)
-- STAND-INS, said so: the room-full line (#16) is the ordinary shop's
-- (overlay 31's line for that case was not traced); a taken prize is drawn
-- like any other (whether overlay 31 dims it was not read).

local T = require("src.import.Gen4Text")
local Strings = require("src.core.Strings")

local M = {}

M.BANK = 435
M.DATA_CARD_01 = 505
M.APRICORN_FIRST, M.APRICORN_LAST = 485, 491
M.FAILED_DAILY, M.FAILED_CARD, M.FAILED_POOR = 2, 3, 1

local function se(self, name)
  pcall(function() require("src.core.Sound").playSe(self.game.data, name) end)
end

-- a bank 435 line, its slots from `...` (slot 0 first)
local function bank(self, n, fallback, ...)
  T.buffer(self.game, ...)
  local text = T.resolve(self.game.data, M.BANK, n, self.game)
  if text then text = text:gsub("[\v\f]+", "\n"):gsub("\n+$", "") end
  return (text and text ~= "") and text or fallback
end
M.bank = bank

local function isApricorn(id)
  id = tonumber(id) or 0
  return id >= M.APRICORN_FIRST and id <= M.APRICORN_LAST
end
M.isApricorn = isApricorn

local function Shops() return require("src.script.HgssPokeathlonShops") end
local function points(self) return tonumber(self.game.save.hgssAthletePoints) or 0 end

-- MartData_BuyMenu_CheckCanPurchaseItem: 0 can, 1 poor, 2 taken today, 3 had
function M.check(self, id, slot)
  local S = Shops()
  if self.athlon.kind == "daily" then
    if S.dailyTaken(self.game.save, slot) then return M.FAILED_DAILY end
  elseif self.athlon.kind == "cards" then
    if S.hasCard(self.game.save, (tonumber(id) or 0) - M.DATA_CARD_01) then return M.FAILED_CARD end
  end
  return points(self) < (self.unit or 0) and M.FAILED_POOR or 0
end

-- ov03_02257CA0's room check, without keeping anything
local function room(self, id)
  local save = self.game.save
  if isApricorn(id) then
    return require("src.world.HgssApricorns").count(save, id - M.APRICORN_FIRST) < 99
  end
  local Bag = require("src.inventory.Bag")
  if not Bag.add(save, id, 1, self.game.data) then return false end
  Bag.remove(save, id, 1)
  return true
end

local function choose(self)
  local id = self.stock[self.cursor]
  local def = self:def(id)
  if not def then return self:back() end
  self.item, self.unit, self.qty, self.transaction = id, tonumber(def.price) or 0, 1, "buy"
  local why = M.check(self, id, self.cursor - 1)
  if why == M.FAILED_DAILY then self.message = bank(self, 25, Strings("You can't buy any more today!"))
  elseif why == M.FAILED_CARD then self.message = bank(self, 26, Strings("You already have this!"))
  elseif why == M.FAILED_POOR then self.message = bank(self, 48, Strings("You don't have enough points!")) end
  if why ~= 0 then self.item = nil; return end
  se(self, "SEQ_SE_DP_SELECT")
  if not room(self, id) then
    self.item = nil
    self.message = bank(self, 16, Strings("You don't have enough room."))
    return
  end
  self.mode, self.yesNo = "confirm", 1
  self.message = bank(self, 46, Strings("Would you like\n%s?", def.name or ""), def.name or "")
end

local function transact(self)
  local save, id, cost = self.game.save, self.item, self.unit or 0
  local S = Shops()
  local def = self:def(id) or {}
  if points(self) < cost then
    self.message, self.mode, self.item = bank(self, 48, Strings("You don't have enough points!")), "buy", nil
    return
  end
  if self.athlon.kind == "daily" then
    if isApricorn(id) then
      require("src.world.HgssApricorns").give(save, id - M.APRICORN_FIRST, 1)
      self.message = bank(self, 49, Strings("All right, here you go.\nCome back anytime!"))
    else
      require("src.inventory.Bag").add(save, id, 1, self.game.data)
      self.message = self:line(6, Strings("Here you are!\nThank you!"), def.name or "", self:pocketName(def))
    end
    S.takeDaily(save, self.cursor - 1)
  else
    S.giveCard(save, (tonumber(id) or 0) - M.DATA_CARD_01)
    self.message = bank(self, 49, Strings("All right, here you go.\nCome back anytime!"))
  end
  -- MartData_SubCurrency (PokeathlonSave_SubAthletePoints: not below 0) and
  -- GAME_STAT_CURRENCY_SPENT
  save.hgssAthletePoints = math.max(0, points(self) - cost)
  pcall(function() require("src.pokemon.Gen4GameRecords").add(save, 35, cost) end)
  se(self, "SEQ_SE_DP_REGI")
  self.mode, self.item = "buy", nil
end

function M.install(Shop)
  local new, def, funds, pay, poorLine, owned, line, chooseFn =
    Shop.new, Shop.def, Shop.funds, Shop.pay, Shop.poorLine, Shop.owned, Shop.line, Shop.choose

  Shop.new = function(game, stock, onQuit, goods, opts)
    local self = new(game, stock, onQuit, goods, opts)
    self.athlon = opts and opts.athlon or nil
    return self
  end

  -- the item at its MartItem price
  Shop.def = function(self, id)
    local d = def(self, id)
    if d and self.athlon then
      local price = self.athlon.prices[tonumber(id) or id] or 0
      return setmetatable({ price = price }, { __index = d })
    end
    return d
  end

  Shop.funds = function(self)
    if self.athlon then return points(self) end
    return funds(self)
  end
  Shop.pay = function(self, n)
    if self.athlon then self.game.save.hgssAthletePoints = math.max(0, points(self) - n); return end
    return pay(self, n)
  end
  Shop.poorLine = function(self)
    if self.athlon then return bank(self, 48, Strings("You don't have enough points!")) end
    return poorLine(self)
  end
  Shop.owned = function(self, id)
    if self.athlon and isApricorn(id) then
      return require("src.world.HgssApricorns").count(self.game.save, id - M.APRICORN_FIRST)
    end
    return owned(self, id)
  end

  -- the purse and the price in points (#33 / #32 / #19)
  Shop.line = function(self, n, fallback, ...)
    if self.athlon then
      if n == 18 then return bank(self, 33, Strings("Athlete Pts.")) end
      if n == 19 then local p = tostring(points(self)); return bank(self, 32, Strings("%sP", p), p) end
      if n == 9 then local p = tostring((...) or ""):gsub("^%s+", ""); return bank(self, 19, Strings("%sP", p), p) end
    end
    return line(self, n, fallback, ...)
  end

  -- the Bag pocket's name, as the ordinary purchase line wants it
  Shop.pocketName = Shop.pocketName or function(self, d)
    local pockets = ((self.game.data.gen4_menus or {}).bag or {}).pockets or {}
    local pocket = pockets[(tonumber(d.fieldPocket) or 0) + 1] or ""
    if pocket == "" then
      local l = T.resolve(self.game.data, 10, 120 + (tonumber(d.fieldPocket) or 0), self.game)
      pocket = l and l:match("^(.-) Pocket") or ""
    end
    return pocket
  end

  Shop.choose = function(self)
    if not self.athlon then return chooseFn(self) end
    if self.mode == "buy" then return choose(self) end
    if self.mode == "confirm" then
      if self.yesNo == 2 then return self:back() end
      se(self, "SEQ_SE_DP_SELECT")
      return transact(self)
    end
    return chooseFn(self)
  end
end

return M
