-- src/script/Gen5MartCommands.lua -- BLACK / WHITE'S POKE MART COUNTER.
--
-- Every Center's clerk runs shared script 871 (Black /a/0/5/7): its own
-- BUY / SELL / SEE YA menu (bank 424), then
--
--   0x149 <var shop, var result>   BUY: the counter's list. The clerk's
--        script sets 0x8000 = 255 for the regular counter (stock by badges)
--        or the second clerk's specialty id; 871 copies it to 0x8021.
--   0x14E <u16, var, var>          SELL: the Bag in sell mode, bracketed by
--        0x14B / 0x14A and the 0x1AE / 0x1B1 / 0x1AD fades
--
-- Both used to lower to nothing ("bw_149" unimplemented, 0x14E unaliased),
-- so BUY and SELL fell straight back to the menu. The stock is read out of
-- overlay 21 at import (src/import/Gen5Marts.lua, constants.gen5Marts).
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, v) return tonumber(G4().valueOf(ctx, v)) or 0 end

local function badges(save)
  local n = 0
  local held = save and (save.badges or (save.player and save.player.badges))
  if type(held) == "table" then for _, has in pairs(held) do if has then n = n + 1 end end
  elseif tonumber(held) then n = tonumber(held) end
  return n
end

-- the counter's stock for a 0x149 shop value: a list of item ids the cache has
function M.stock(game, shop)
  local data = game and game.data
  local marts = data and data.constants and data.constants.gen5Marts
  local list = require("src.import.Gen5Marts").stock(marts, shop, badges(game and game.save))
  local out = {}
  for _, id in ipairs(list or {}) do
    if data.items and data.items[id] then out[#out + 1] = id end
  end
  return out
end

local function setResult(ctx, dest, value)
  if dest and ctx.save then G4().setVar(ctx.save, dest, value) end
end

function Commands.g4_bw_mart(ctx, shopVar, dest, sell)
  local game = ctx.game
  if not game then return end
  local runner = ctx.runner
  local Screens = require("src.ui.Screens")
  local stock = {}
  -- the Battle Subway's Exchange Service Corner (shop 0xFE / 0xFD): items
  -- for BP, src/import/Gen5Marts.lua's bpStock (ov21 0x021B39C4)
  local shop = valueOf(ctx, shopVar)
  if not sell and (shop == 0xFE or shop == 0xFD) then
    local marts = game.data and game.data.constants and game.data.constants.gen5Marts
    local price = {}
    for _, row in ipairs(require("src.import.Gen5Marts").bpStock(marts, shop) or {}) do
      if game.data.items and game.data.items[row.item] then
        stock[#stock + 1] = row.item
        price[row.item] = row.price
      end
    end
    Screens.push(game, "ShopMenu", stock, function()
      setResult(ctx, dest, 0)
      if runner then runner:resume() end
    end, nil, { direct = true, frontier = { price = function(id) return price[id] or 0 end } })
    if runner then runner:yield() end
    return
  end
  if not sell then
    stock = M.stock(game, shop)
    if not stock[1] then
      require("src.core.Logger").warn("bw shop: no stock for shop %s -- re-import the ROM",
        tostring(valueOf(ctx, shopVar)))
      setResult(ctx, dest, 0)
      return
    end
  end
  Screens.push(game, "ShopMenu", stock, function()
    setResult(ctx, dest, 0)
    if runner then runner:resume() end
  end, nil, { direct = true, sell = sell or nil })
  if sell then
    local top = game.stack and game.stack:top()
    if top and top.openBag and top.mode == "sell" then top:openBag() end
  end
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_bw_mart = { foreground = true, blocking = true }

-- THE SPECIAL BUYERS (constants.gen5Marts.buyers, src/import/Gen5Marts.lua):
--   0x14E <1, kindVar, resultVar>  the Bag in sell mode, but only the
--        buyer's list at the buyer's price; result 1 when something was sold
--   0x20E <kind, dest>             1 when the Bag holds anything on the list
--        (ov21 0x021B716C: the member's items, each checked in the Bag)
function M.buyList(game, kind)
  local marts = game and game.data and game.data.constants and game.data.constants.gen5Marts
  local rows = marts and marts.buyers and marts.buyers[kind]
  if not rows then return nil end
  -- the Bag keys items "ITEM_%03d" (Gen4Commands itemKey); the scripts pass
  -- numbers -- the list answers to both
  local out = {}
  for _, r in ipairs(rows) do out[r.item] = r.price; out[("ITEM_%03d"):format(r.item)] = r.price end
  return out
end
function Commands.g4_bw_buyer_has_items(ctx, kind, destVar)
  local list = M.buyList(ctx.game, valueOf(ctx, kind)) or {}
  local inv = (ctx.save and ctx.save.inventory) or {}
  local has = 0
  for id in pairs(list) do
    if (tonumber(inv[id]) or 0) > 0 then has = 1 break end
  end
  setResult(ctx, destVar, has)
end
function Commands.g4_bw_buyer_sell(ctx, kindVar, resultVar)
  local game = ctx.game
  if not game then return end
  local runner = ctx.runner
  local list = M.buyList(game, valueOf(ctx, kindVar))
  if not list then
    require("src.core.Logger").warn("bw buyer: no list for kind %s -- re-import the ROM", tostring(valueOf(ctx, kindVar)))
    setResult(ctx, resultVar, 0)
    return
  end
  local before = tonumber(game.save and game.save.money) or 0
  require("src.ui.Screens").push(game, "ShopMenu", {}, function()
    setResult(ctx, resultVar, ((tonumber(game.save and game.save.money) or 0) > before) and 1 or 0)
    if runner then runner:resume() end
  end, nil, { direct = true, sell = true, buyList = list })
  local top = game.stack and game.stack:top()
  if top and top.openBag and top.mode == "sell" then top:openBag() end
  if runner then runner:yield() end
end
Commands.meta.g4_bw_buyer_sell = { foreground = true, blocking = true }

-- ONE ITEM TO A SPECIAL BUYER, the gourmet's maid's way (M0894): she asks
-- for a single item, says the price and pays it. Each reads the same
-- /a/2/0/8 member as 0x20E (`kind` through the byte table to the member):
--   0x20F <item, kind, dest>         the price, 0 when unlisted (ov21
--        0x021B70D8; a u16 store)
--   0x249 <item, kind, slot, digits> that price into a number buffer
--        (0x021B721C)
--   0x24A <item, kind>               that price added to the money
--        (0x021B72CC); the script removes the item itself
local function buyerPrice(ctx, item, kind)
  local list = M.buyList(ctx.game, valueOf(ctx, kind)) or {}
  return tonumber(list[valueOf(ctx, item)]) or 0
end
function Commands.g4_bw_buyer_price(ctx, item, kind, destVar)
  setResult(ctx, destVar, buyerPrice(ctx, item, kind) % 65536)
end
function Commands.g4_bw_buyer_price_buffer(ctx, item, kind, slot)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[valueOf(ctx, slot) + 1] = tostring(buyerPrice(ctx, item, kind))
end
function Commands.g4_bw_buyer_pay(ctx, item, kind)
  local price = buyerPrice(ctx, item, kind)
  if price > 0 and Commands.g4_add_money then Commands.g4_add_money(ctx, price) end
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwpokemart = function(ins, s) emit(s, { "g4_bw_mart", ins.args[1], ins.args[2] }) end
  L.bwmartsell = function(ins, s)
    if tonumber(ins.args[1]) == 1 then return emit(s, { "g4_bw_buyer_sell", ins.args[2], ins.args[3] }) end
    emit(s, { "g4_bw_mart", nil, ins.args[2], true })
  end
  L.bwbuyerhasitems = function(ins, s) emit(s, { "g4_bw_buyer_has_items", ins.args[1], ins.args[2] }) end
  L.bwbuyerprice = function(ins, s) emit(s, { "g4_bw_buyer_price", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwbuyerpricebuffer = function(ins, s) emit(s, { "g4_bw_buyer_price_buffer", ins.args[1], ins.args[2], ins.args[3] }) end
  L.bwbuyerpay = function(ins, s) emit(s, { "g4_bw_buyer_pay", ins.args[1], ins.args[2] }) end
  -- the Center's PC, 0x14F <var, mode>: Platinum's box modes 0..3 are the
  -- same; Black / White's 4 is the Battle Box, which this port opens as MOVE
  -- (Platinum's 4 is COMPARE)
  L.bwopenstorage = function(ins, s)
    local mode = tonumber(ins.args[2])
    if mode == 4 then mode = 2 end
    emit(s, { "g4_storage", mode or ins.args[2] })
  end
  -- the Xtransceiver's story calls (0x155)
  require("src.script.Gen5XtransceiverCommands").install(L)
  -- a question's YES / NO beside the question (0x34 then 0x47)
  require("src.script.Gen5MessageCommands").install(L)
end

return M
