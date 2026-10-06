-- Platinum counter: cartridge shop background, with transactions kept on the
-- DS surface so quantity and confirmation never open a Game Boy menu.
--
-- THE FLOW IS overlay007's (src/overlay007/shop_menu.c):
--   * BUY / SELL / SEE YA! is a framed window at tile (1, 1), 13 x 6, over
--     the FIELD -- the counter art is not up yet -- with the clerk's line
--     ("Welcome! How may I serve you?") in the message box.
--   * Choosing BUY slides the field camera right, 8 units a frame for 10
--     frames (8 when the player faces west; Shop_GetCameraPosDest /
--     Shop_MoveCamera), and only then puts up shop_gra's counter. That slide
--     is what puts the player and the clerk in the art's transparent window
--     at the top left; without it the window showed whatever lay up and left
--     of the player -- in a small mart, the black outside the room.
--   * Leaving the list slides it back (Shop_MoveCameraBack), "Is there
--     anything else I may do for you?", and SEE YA! ends on "Please come
--     again!".
-- Every line is bank 543's (TEXT_BANK_UNK_0543).
--
-- THE COUNTER, window by window (sShop_DefaultWindowTemplates), all over
-- Gen4ShopArt's pictures (`gen4_shop_art`):
--   * the list at tile (12, 2), 19 x 14: seven 16-pixel rows, the price
--     right-aligned on 19 * 8, ink (1, 2) on the plate; the highlight sprite at
--     (172, 24 + 16 * row) in sprites.NCLR row 0, row 1 once an item is chosen
--     (Shop_SetCursorSpritePalette); the scroll arrows at (177, 8) / (177, 132)
--   * the description at (5, 18) in (15, 14) -- white on the green band -- and
--     the item's icon centred on (22, 172)
--   * Money at (1, 1) 9 x 4, the amount right-aligned one row down
--   * choosing an item does NOT replace the list.  The description goes, the
--     clerk asks in the message box at (2, 19), and two framed windows come up
--     beside the list: "In Bag:" at (1, 15) 14 x 2 and the quantity at
--     (19, 13) 12 x 4 -- "x01" at its left, the total right-aligned -- with the
--     scroll arrows moved to (162, 108) / (162, 132) as its up/down marks
--     (Shop_SetScrollSpritesPositionXY).  A puts the quantity windows away and
--     asks "... That will be $N. OK?" with a YES / NO window at (23, 13) 7 x 4.
--
-- SELL IS THE BAG.  Platinum's SELL leaves the counter for the Bag
-- application in BAG_MODE_SELL_ITEMS, which asks "How many would you like to
-- sell?", "I can pay $N. Would that be OK?" and "Turned over the ... and
-- received $N." (bank 7, 74..77).  This port opens its own Bag in pick mode
-- and asks those three questions back here, over the field, in the same
-- windows the purchase uses.
local Assets = require('src.render.Assets')
local Font = require('src.render.Font')
local Bag = require('src.inventory.Bag')
local T = require('src.import.Gen4Text')
local Shop = {}
Shop.TEXT = 543
Shop.BAG_TEXT = 7             -- TEXT_BANK_BAG: the selling lines
Shop.CAMERA_STEP = 8          -- map pixels per frame (8 * FX32_ONE, a half tile)
Shop.CAMERA_HZ = 30           -- the field task's frame rate
Shop.TM01, Shop.HM01 = 328, 420
local LIST_X,LIST_Y,ROW_HEIGHT,VISIBLE_ROWS=96,16,16,7
Shop.layout={iconX=22,iconY=172,listX=LIST_X,listY=LIST_Y,rowHeight=ROW_HEIGHT,visibleRows=VISIBLE_ROWS,descriptionX=40,descriptionY=144}
Shop.__index = Shop
Shop.isOpaque = false
function Shop:uiSize() return 256, 192 end
function Shop:wantsFillScale() return true end
function Shop:sgbPalettes() return {require('src.render.PaletteFX').trueColorZone(0,0,31,23)} end

-- `goods` turns this into a non-item counter (MART_TYPE_SEAL): BUY / SEE YA!
-- only, the names and prices out of the adapter, the count beside the price
-- from the destination inventory and the fit test its own:
--   goods = { def(id) -> {name, price, description}, owned(id),
--             canAdd(id, qty), add(id, qty), fullMessage, ownedLabel }
-- a bank 543 line, its {STRVAR_1 kind slot pad} slots filled by slot
function Shop:line(n, fallback, ...)
  T.buffer(self.game, ...)
  local text = T.resolve(self.game.data, Shop.TEXT, n, self.game)
  -- a mid-line scroll (\v) or clear (\f) becomes a line break in this box
  if text then text = text:gsub("[\v\f]+", "\n") end
  return text or fallback
end
-- a bank 7 (bag) line, the same way
function Shop:bagLine(n, fallback, ...)
  T.buffer(self.game, ...)
  local text = T.resolve(self.game.data, Shop.BAG_TEXT, n, self.game)
  if text then text = text:gsub("[\v\f]+", "\n") end
  return text or fallback
end

function Shop.new(game, stock, onQuit, goods)
  local self = setmetatable({ game = game, stock = stock or {}, onQuit = onQuit, goods = goods,
    mode = 'menu', cursor = 1, scroll = 0, camStep = 0, camAcc = 0, yesNo = 1 }, Shop)
  self.message = self:line(0, 'Welcome!\nHow may I serve you?')
  -- Shop_GetCameraPosDest: ten steps, eight when the player faces west
  local ow = game.overworld
  local facing = ow and ow.player and ow.player.facing
  self.camDest = (facing == 'left' or facing == 'west') and 8 or 10
  return self
end

function Shop:def(id)
  if self.goods then return id and self.goods.def(id) end
  return id and self.game.data.items[id]
end

function Shop:owned(id)
  if self.goods then return self.goods.owned(id) end
  return self.game.save.inventory[id] or 0
end

-- SEE YA!: "Please come again!", then the counter is gone
function Shop:close()
  self.mode, self.cursor = 'exit', 1
  self.message = self:line(1, 'Please come again!')
end

function Shop:finish()
  self.camStep = 0
  self:applyCamera()
  self.game.stack:pop()
  if self.onQuit then self.onQuit() end
end

-- the field camera, slid while the counter is up (Shop_MoveCamera)
function Shop:applyCamera()
  local ow = self.game.overworld
  if not (ow and ow.followCamera and ow.camera) then return end
  ow:followCamera()
  ow.camera.x = ow.camera.x + self.camStep * Shop.CAMERA_STEP
end

-- selling never slides the camera: it is the Bag's screen, not the counter's
function Shop:selling() return self.mode == 'sell' or self.transaction == 'sell' and (self.mode == 'quantity' or self.mode == 'confirm') end

function Shop:cameraTarget()
  if self.mode == 'menu' or self.mode == 'exit' or self:selling() then return 0 end
  return self.camDest
end

-- the counter art is up only once the camera has arrived
function Shop:counterUp()
  return self.mode ~= 'menu' and self.mode ~= 'exit' and not self:selling() and self.camStep == self.camDest
end

function Shop:rows()
  if self.mode == 'menu' then
    local buy, sell, bye = self:line(15, 'BUY'), self:line(16, 'SELL'), self:line(17, 'SEE YA!')
    if self.goods then return { buy, bye } end
    return { buy, sell, bye }
  end
  if self.mode == 'sell' then return {} end
  return self.stock
end

function Shop:back()
  if self.mode == 'menu' then return self:close() end
  if self.mode == 'quantity' or self.mode == 'confirm' then
    self.mode = self.transaction
    self.message = nil
    if self.transaction == 'sell' then return self:openBag() end
  else
    self.mode, self.cursor, self.scroll, self.transaction = 'menu', 1, 0, nil
    self.message = self:line(2, 'Is there anything else I may do\nfor you?')
  end
end

-- SELL: the Bag, in pick mode; what it hands back is sold here
function Shop:openBag()
  self.mode, self.transaction = 'sell', 'sell'
  local ok = pcall(require('src.ui.Screens').push, self.game, 'BagMenu', {
    pick = true,
    onPick = function(id) self:sellItem(id) end,
    onCancel = function() self.transaction = nil; self.mode = 'sell'; self:back() end,
  })
  return ok
end

-- the Bag chose `id`: "Oh, no. I can't buy that." or the quantity
function Shop:sellItem(id)
  local def = self:def(id)
  local price = def and tonumber(def.price) or 0
  self.mode, self.transaction = 'sell', 'sell'
  if not def or def.keyItem or def.fieldPocket == 7 or price <= 0
      or (tonumber(id) and tonumber(id) >= 420 and tonumber(id) <= 427) then
    self.message = self:bagLine(74, "I can't buy that.", def and def.name or '')
    return
  end
  self.item, self.qty, self.mode, self.yesNo = id, 1, 'quantity', 1
  self.unit = math.floor(price / 2)
  self.max = math.max(1, self.game.save.inventory[id] or 0)
  self.message = self:bagLine(75, (def.name or '') .. '?\nHow many would you like to sell?', def.name or '')
end

function Shop:choose()
  if self.mode == 'menu' then
    if self.cursor == #self:rows() then return self:close() end
    if self.cursor == 1 then
      self.mode = 'buy'
      self.cursor, self.scroll, self.message = 1, 0, nil
      return
    end
    self.cursor, self.scroll, self.message = 1, 0, nil
    return self:openBag()
  end
  if self.mode == 'sell' then return self:openBag() end
  if self.mode == 'confirm' then
    if self.yesNo == 2 then return self:back() end
    return self:transact()
  end
  if self.mode == 'quantity' then
    self.mode, self.yesNo = 'confirm', 1
    local def = self:def(self.item)
    if self.transaction == 'buy' then
      local name = def and def.name or ''
      self.message = self:line(5, ('%s, and you want %d.\nThat will be $%d. OK?'):format(name, self.qty, self.qty * self.unit),
        name, tostring(self.qty), tostring(self.qty * self.unit))
    else
      self.message = self:bagLine(76, 'I can pay $' .. (self.qty * self.unit) .. '.\nWould that be OK?', tostring(self.qty * self.unit))
    end
    return
  end
  local id = self:rows()[self.cursor]
  local def = self:def(id)
  if not def then return self:back() end
  local price = tonumber(def.price) or 0
  self.unit = price
  self.max = math.min(99, price > 0 and math.floor((self.game.save.money or 0) / price) or 99)
  if self.max < 1 then self.message = self:line(3, "You don't have enough money."); return end
  self.item, self.transaction, self.qty, self.mode = id, 'buy', 1, 'quantity'
  self.message = self:line(4, (def.name or '') .. '? Certainly.\nHow many would you like?', def.name)
end

function Shop:transact()
  local save, cost = self.game.save, self.qty * self.unit
  if self.transaction == 'buy' then
    if (save.money or 0) < cost then self.message = self:line(3, "You don't have enough money.")
    elseif self.goods and not self.goods.canAdd(self.item, self.qty) then
      self.message = self.goods.fullMessage or 'There is no more room.'
    elseif self.goods then
      self.goods.add(self.item, self.qty)
      save.money = (save.money or 0) - cost; self.message = 'Thank you!'
    elseif not Bag.add(save, self.item, self.qty, self.game.data) then self.message = self:line(7, 'Your Bag is full.')
    else save.money = (save.money or 0) - cost
      local def = self:def(self.item) or {}
      local pockets = ((self.game.data.gen4_menus or {}).bag or {}).pockets or {}
      local pocket = pockets[(tonumber(def.fieldPocket) or 0) + 1] or ''
      self.message = self:line(6, 'Thank you!', def.name or '', pocket)
      -- Platinum awards one Premier Ball per purchase of at least ten Poke Balls.
      if self.item == 4 and self.qty >= 10 and self.game.data.items[12] then
        Bag.add(save, 12, 1, self.game.data)
        self.message = self.message .. '\n' .. self:line(10, '')
      end
    end
  else
    if (save.inventory[self.item] or 0) >= self.qty then
      Bag.remove(save, self.item, self.qty); save.money = math.min(999999, (save.money or 0) + cost)
      local def = self:def(self.item) or {}
      self.message = self:bagLine(77, 'Thank you!', def.name or '', tostring(cost))
    end
  end
  self.mode = self.transaction
  self.cursor = math.max(1, math.min(self.cursor, #self:rows() + 1))
end

function Shop:step(delta)
  if self.mode == 'quantity' then self.qty = (self.qty - 1 + delta) % self.max + 1; return end
  if self.mode == 'confirm' then self.yesNo = (self.yesNo - 1 + (delta > 0 and 1 or -1)) % 2 + 1; return end
  if self.mode == 'sell' then return end
  local count = #self:rows() + (self.mode == 'menu' and 0 or 1)
  self.cursor = (self.cursor - 1 + delta) % math.max(1, count) + 1
  if self.mode ~= 'menu' then self.message = nil end
  self.scroll = math.max(0, math.min(self.scroll, self.cursor - 1))
  if self.cursor > self.scroll + VISIBLE_ROWS then self.scroll = self.cursor - VISIBLE_ROWS end
end

function Shop:selectedItem()
  local id = (self.mode == 'quantity' or self.mode == 'confirm') and self.item
    or (self.mode == 'buy') and self:rows()[self.cursor]
  return self:def(id), id
end

function Shop:description()
  local def = self:selectedItem()
  return self.message or def and def.description or ''
end

function Shop:touchpressed(id,px,py)
  local rect=require('src.render.Renderer').uiPresentation
  if not rect or px<rect.x or py<rect.y or px>=rect.x+rect.w or py>=rect.y+rect.h then return false end
  local x,y=(px-rect.x)/rect.scaleX,(py-rect.y)/rect.scaleY
  if self.mode=='exit' then if self.camStep==0 then self:finish() end; return true end
  if self.camStep~=self:cameraTarget() then return true end
  if self.mode=='menu' then
    -- the context window's rows (tile 1, 1; 16 pixels each)
    local row=math.floor((y-8)/16)+1
    if x<120 and y>=8 and row>=1 and row<=#self:rows() then self.cursor=row; self:choose() end
    return true
  end
  if self.mode=='sell' then if y>=144 then self:choose() end; return true end
  if self.mode=='quantity' then
    -- the quantity window (19, 13) 12 x 4 and its two marks at x 162
    if x>=144 and y>=96 and y<144 then
      if x<176 then self:step(y<120 and 1 or -1) else self:choose() end
    elseif y>=144 then self:back() end
    return true
  elseif self.mode=='confirm' then
    -- YES / NO at (23, 13), a row each
    if x>=176 and y>=96 and y<136 then self.yesNo=y<120 and 1 or 2; self:choose()
    elseif y>=144 then self:back() end
    return true
  end
  if y>=168 then self:back(); return true end
  if x>=160 and x<192 and (y<16 or y>=128 and y<144) then
    self:step(y<16 and -1 or 1)
  elseif x>=LIST_X and y>=LIST_Y and y<LIST_Y+VISIBLE_ROWS*ROW_HEIGHT then
    local row=self.scroll+math.floor((y-LIST_Y)/ROW_HEIGHT)+1
    local count=#self:rows()+1
    if row<=count then self.cursor=row; self.message=nil; self:choose() end
  elseif x<104 and y>=96 and y<128 then
    local count=#self:rows()+1
    self.scroll=math.max(0,math.min(math.max(0,count-VISIBLE_ROWS),self.scroll+(x<52 and -VISIBLE_ROWS or VISIBLE_ROWS)))
  end
  return true
end

local function image(self, path)
  if not path then return nil end
  self.icons = self.icons or {}
  if self.icons[path] == nil then
    local ok, img = pcall(Assets.image, path); self.icons[path] = ok and img or false
    if self.icons[path] then self.icons[path]:setFilter('nearest', 'nearest') end
  end
  return self.icons[path] or nil
end

-- this counter's own art first (gen4_shop_art), an older cache's
-- gen4_graphics.screens picture second
function Shop:drawSprite(key,x,y,fallback)
  local rec=(self.game.data.gen4_shop_art or {})[key]
  if not rec and fallback then rec=((self.game.data.gen4_graphics or {}).screens or {})[fallback] end
  if not rec then return false end
  local img=image(self,type(rec)=='table' and rec.path or rec)
  if not img then return false end
  local ox,oy=-img:getWidth()/2,-img:getHeight()/2
  if type(rec)=='table' then ox,oy=rec.originX or ox,rec.originY or oy end
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(img,math.floor(x+ox),math.floor(y+oy));return true
end

function Shop:update(dt)
  -- the camera, one step per field frame toward where this mode wants it
  local want = self:cameraTarget()
  if self.camStep ~= want then
    self.camAcc = self.camAcc + (dt or 1 / 60) * Shop.CAMERA_HZ
    while self.camAcc >= 1 and self.camStep ~= want do
      self.camAcc = self.camAcc - 1
      self.camStep = self.camStep + (want > self.camStep and 1 or -1)
    end
  else
    self.camAcc = 0
  end
  self:applyCamera()
  local input = self.game.input
  if self.mode == 'exit' then
    if self.camStep == 0 and (input:wasPressed('a') or input:wasPressed('b')) then self:finish() end
    return
  end
  -- input waits for the camera, as the field task does
  if self.camStep ~= want then return end
  if (input:wasPressed('a') or input:wasPressed('b')) and self:turnPage() then return end
  if input:wasPressed('b') then self:back()
  elseif input:wasPressed('up') then self:step(self.mode == 'quantity' and 1 or -1)
  elseif input:wasPressed('down') then self:step(self.mode == 'quantity' and -1 or 1)
  elseif input:wasPressed('right') and self.mode == 'quantity' then self:step(10)
  elseif input:wasPressed('left') and self.mode == 'quantity' then self:step(-10)
  elseif input:wasPressed('a') then
    -- a message over the list is read, then put away, before the list moves
    if (self.mode == 'buy') and self.message then self.message = nil else self:choose() end
  end
end

-- the message's lines, and how many two-line pages they make -- "Here you are!
-- Thank you!" is followed by "You put away the ..." after a scroll ({\r}), so a
-- line longer than the box is read a page at a time
function Shop:messageLines()
  local lines = {}
  for line in (tostring(self.message or '') .. '\n'):gmatch('([^\n\v\f]*)[\n\v\f]') do lines[#lines + 1] = line end
  if self.pagedMessage ~= self.message then self.pagedMessage, self.messagePage = self.message, 0 end
  return lines
end

-- A on a message with another page turns it; true when it did
function Shop:turnPage()
  if not self.message then return false end
  local lines = self:messageLines()
  if ((self.messagePage or 0) + 1) * 2 < #lines then
    self.messagePage = (self.messagePage or 0) + 1
    return true
  end
  return false
end

-- the clerk's line in the field message box (bank 543 over the field)
function Shop:drawFieldMessage()
  if not self.message then return end
  Font.drawDialogueBox(1, 18, 30, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local lines = self:messageLines()
  local first = (self.messagePage or 0) * 2
  for i = 1, 2 do
    local line = lines[first + i]
    if line then Font.draw(line, 16, 152 + (i - 1) * 16) end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Shop_InitContextMenu: tile (1, 1), 13 x 6, the standard window frame
function Shop:drawContextMenu()
  local g = love.graphics
  Font.drawBox(0, 0, 15, 8)
  g.setColor(0, 0, 0, 1)
  for i, label in ipairs(self:rows()) do
    local y = 8 + (i - 1) * 16
    Font.draw(label, 24, y)
    if i == self.cursor then Font.drawCode(require('src.ui.Theme').cursor, 12, y) end
  end
  g.setColor(1, 1, 1, 1)
end

-- the money window (Shop_PrintCurrentMoney): (1, 1) 9 x 4
function Shop:drawMoney()
  require('src.ui.Gen4MoneyWindow').draw({ left = 1, top = 1, tilesW = 9, tilesH = 4,
    label = self:line(18, 'Money'), amount = self:line(19, '$' .. tostring(self.game.save.money or 0),
      tostring(self.game.save.money or 0)) })
end

-- a padded number, the way StringTemplate_SetNumber pads it
local function pad(n, digits, zeros)
  local s = tostring(math.floor(n))
  if #s < digits then s = (zeros and '0' or ' '):rep(digits - #s) .. s end
  return s
end

-- Shop_ShowQtyWithinInventory and Shop_ShowQtyTotalItemPurchase
function Shop:drawQuantity()
  local g = love.graphics
  if self.transaction == 'buy' then
    Font.drawBox(0, 14, 16, 4)
    g.setColor(1, 1, 1, 1)
    local owned = self.goods and self.goods.ownedLabel and (self.goods.ownedLabel .. tostring(self:owned(self.item)))
      or self:line(20, 'In Bag: ' .. tostring(self:owned(self.item)), pad(self:owned(self.item), 3))
    Font.draw(owned, 8, 120)
  end
  Font.drawBox(18, 12, 14, 6)
  g.setColor(1, 1, 1, 1)
  Font.draw(self:line(21, 'x' .. pad(self.qty, 2, true), pad(self.qty, 2, true)), 152, 112)
  local total = self:line(22, '$' .. tostring(self.qty * self.unit), pad(self.qty * self.unit, 6))
  Font.draw(total, 248 - Font.width(total), 112)
  self:drawSprite('scroll_up', 162, 108, 'shop/scroll_00')
  self:drawSprite('scroll_down', 162, 132, 'shop/scroll_01')
end

-- Menu_MakeYesNoChoice over sShop_YesNoChoiceWindowTemplate: (23, 13) 7 x 4
function Shop:drawYesNo()
  Font.drawBox(22, 12, 9, 6)
  love.graphics.setColor(1, 1, 1, 1)
  for i, n in ipairs({ 23, 24 }) do
    local y = 104 + (i - 1) * 16
    Font.draw(self:line(n, i == 1 and 'YES' or 'NO'), 184 + 12, y)
    if i == self.yesNo then Font.drawCode(require('src.ui.Theme').cursor, 184, y) end
  end
end

function Shop:drawList()
  local g = love.graphics
  local rows = self:rows()
  local chosen = self.mode == 'quantity' or self.mode == 'confirm'
  local special = (self.game.data.gen4_shop_art or {}).special
  for i = 1, VISIBLE_ROWS do
    local index, y = self.scroll + i, LIST_Y + (i - 1) * ROW_HEIGHT
    local id = rows[index]
    if id or index == #rows + 1 then
      local def = self:def(id)
      if index == self.cursor then
        if not self:drawSprite(chosen and 'cursor_1' or 'cursor_0', 172, y + 8, 'shop/cursor_00') then
          g.setColor(0.55,0.75,0.85,1);g.rectangle('fill',96,y-2,152,16)
        end
        g.setColor(1,1,1,1)
      end
      local label = def and def.name or self:line(8, 'CANCEL')
      local textX = LIST_X
      -- a TM counter: "No.NN" in font_special_chars, then the move's name at
      -- x 35 (Shop_MenuPrintCallback / Shop_InitItemsList)
      local n = tonumber(id)
      if def and n and n >= Shop.TM01 and n <= Shop.HM01 and not self.goods then
        local machine = def.machine
        local move = machine and self.game.data.moves and self.game.data.moves[machine.move]
        if move and move.name then label = move.name end
        textX = LIST_X + 35
        local img = special and image(self, type(special) == 'table' and special.path or special)
        if img then
          self.specialQuads = self.specialQuads or {}
          local function tile(t, w, x)
            local key = t .. ':' .. w
            if not self.specialQuads[key] then self.specialQuads[key] = g.newQuad(t * 8, 0, w * 8, 8, img:getDimensions()) end
            g.draw(img, self.specialQuads[key], x, y + 4)
          end
          g.setColor(1, 1, 1, 1)
          tile(13, 2, LIST_X)
          local num = pad(n - Shop.TM01 + 1, 2, true)
          for k = 1, #num do tile(tonumber(num:sub(k, k)), 1, LIST_X + 16 + (k - 1) * 8) end
        end
      end
      local right = def and (self:line(9, '$' .. tostring(def.price or 0), pad(tonumber(def.price) or 0, 4)))
      Font.draw(Font.fit(label, right and 152 - (textX - LIST_X) - Font.width(right) or 152), textX, y)
      if right then Font.draw(right, 248 - Font.width(right), y) end
    end
  end
  -- Shop_MenuCursorCallback: up while the list is scrolled, down while more
  -- than seven rows remain below the top one
  if self.mode == 'buy' then
    if self.scroll > 0 then self:drawSprite('scroll_up', 177, 8, 'shop/scroll_00') end
    if #rows + 1 > VISIBLE_ROWS and #rows + 1 > self.scroll + VISIBLE_ROWS then self:drawSprite('scroll_down', 177, 132, 'shop/scroll_01') end
  end
end

function Shop:draw()
  local g = love.graphics
  if not self:counterUp() then
    g.setColor(1, 1, 1, 1)
    if self.mode == 'menu' then self:drawContextMenu() end
    if self:selling() then
      self:drawMoney()
      if self.mode == 'quantity' then self:drawQuantity() end
      if self.mode == 'confirm' then self:drawYesNo() end
    end
    if self.mode == 'menu' or self.mode == 'exit' or self:selling() then self:drawFieldMessage() end
    return
  end
  local art = (self.game.data.gen4_shop_art or {})[self.goods and 'counter_no_item' or 'counter']
    or ((self.game.data.gen4_graphics or {}).screens or {})['shop/tilemap']
  local counter = image(self, type(art) == 'table' and art.path or art)
  g.setColor(1, 1, 1, 1)
  if counter then g.draw(counter, 0, 0) end
  self:drawMoney()
  self:drawList()
  local transaction = self.mode == 'quantity' or self.mode == 'confirm'
  if not transaction and not self.message then
    local def, id = self:selectedItem()
    local rec = def and not self.goods and ((self.game.data.gen4_graphics or {}).screens or {})[('items/icon_%03d'):format(tonumber(def.id) or tonumber(id) or 0)]
    local icon = rec and image(self, type(rec) == 'table' and rec.path or rec)
    if icon then g.setColor(1,1,1,1); g.draw(icon,Shop.layout.iconX-icon:getWidth()/2,Shop.layout.iconY-icon:getHeight()/2) end
    local y = Shop.layout.descriptionY
    Font.pushStyle({text={1,1,1},shadow={0,0,0}})
    for line in (tostring(self:description()) .. '\n'):gmatch('([^\n]*)\n') do
      if y > 184 then break end
      Font.draw(Font.fit(line, 212), self.goods and 8 or 40, y); y = y + 16
    end
    Font.popStyle()
  else
    if self.mode == 'quantity' then self:drawQuantity() end
    if self.mode == 'confirm' then self:drawYesNo() end
    self:drawFieldMessage()
  end
  g.setColor(1, 1, 1, 1)
end

return Shop
