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
local Assets = require('src.render.Assets')
local Font = require('src.render.Font')
local Bag = require('src.inventory.Bag')
local T = require('src.import.Gen4Text')
local Shop = {}
Shop.TEXT = 543
Shop.CAMERA_STEP = 8          -- map pixels per frame (8 * FX32_ONE, a half tile)
Shop.CAMERA_HZ = 30           -- the field task's frame rate
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

function Shop.new(game, stock, onQuit, goods)
  local self = setmetatable({ game = game, stock = stock or {}, onQuit = onQuit, goods = goods,
    mode = 'menu', cursor = 1, scroll = 0, camStep = 0, camAcc = 0 }, Shop)
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

function Shop:cameraTarget()
  if self.mode == 'menu' or self.mode == 'exit' then return 0 end
  return self.camDest
end

-- the counter art is up only once the camera has arrived
function Shop:counterUp()
  return self.mode ~= 'menu' and self.mode ~= 'exit' and self.camStep == self.camDest
end

function Shop:rows()
  if self.mode == 'menu' then
    local buy, sell, bye = self:line(15, 'BUY'), self:line(16, 'SELL'), self:line(17, 'SEE YA!')
    if self.goods then return { buy, bye } end
    return { buy, sell, bye }
  end
  if self.mode == 'sell' then return Bag.order(self.game.save) end
  return self.stock
end

function Shop:back()
  if self.mode == 'menu' then return self:close() end
  if self.mode == 'quantity' or self.mode == 'confirm' then self.mode = self.transaction
  else
    self.mode, self.cursor, self.scroll = 'menu', 1, 0
    self.message = self:line(2, 'Is there anything else I may do\nfor you?')
  end
end

function Shop:choose()
  if self.mode == 'menu' then
    if self.cursor == #self:rows() then return self:close() end
    self.mode = self.cursor == 1 and 'buy' or 'sell'
    self.cursor, self.scroll, self.message = 1, 0, nil
    return
  end
  if self.mode == 'confirm' then return self:transact() end
  if self.mode == 'quantity' then
    self.mode = 'confirm'
    if self.transaction == 'buy' then
      local def = self:def(self.item)
      self.message = self:line(5, nil, def and def.name or '', tostring(self.qty), tostring(self.qty * self.unit))
    end
    return
  end
  local id = self:rows()[self.cursor]
  local def = self:def(id)
  if not def then return self:back() end
  local price = tonumber(def.price) or 0
  if self.mode == 'sell' and (def.keyItem or def.fieldPocket == 7
      or tonumber(id) and tonumber(id) >= 420 and tonumber(id) <= 427
      or price <= 0) then
    self.message = "I can't buy that item."; return
  end
  self.unit = self.mode == 'sell' and math.floor(price / 2) or price
  self.max = self.mode == 'sell' and (self.game.save.inventory[id] or 0)
    or math.min(99, price > 0 and math.floor((self.game.save.money or 0) / price) or 99)
  if self.max < 1 then self.message = self:line(3, "You don't have enough money."); return end
  self.item, self.transaction, self.qty, self.mode = id, self.mode, 1, 'quantity'
  if self.transaction == 'buy' then self.message = self:line(4, nil, def.name) end
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
      self.message = 'Thank you!'
    end
  end
  self.mode = self.transaction
  self.cursor = math.max(1, math.min(self.cursor, #self:rows() + 1))
end

function Shop:step(delta)
  if self.mode == 'quantity' then self.qty = (self.qty - 1 + delta) % self.max + 1; return end
  if self.mode == 'confirm' then return end
  local count = #self:rows() + (self.mode == 'menu' and 0 or 1)
  self.cursor = (self.cursor - 1 + delta) % math.max(1, count) + 1
  self.message = nil
  self.scroll = math.max(0, math.min(self.scroll, self.cursor - 1))
  if self.cursor > self.scroll + VISIBLE_ROWS then self.scroll = self.cursor - VISIBLE_ROWS end
end

function Shop:selectedItem()
  local id = (self.mode == 'quantity' or self.mode == 'confirm') and self.item
    or self.mode ~= 'menu' and self:rows()[self.cursor]
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
  if y>=168 then self:back(); return true end
  if self.mode=='quantity' then
    if y>=72 and y<96 then self:step(x<176 and -1 or 1)
    elseif y>=96 and y<128 then self:choose() end
  elseif self.mode=='confirm' then
    if y>=96 and y<128 then if x<176 then self:choose() else self:back() end end
  elseif self.mode~='menu' and x>=160 and x<192 and (y<16 or y>=128 and y<144) then
    self:step(y<16 and -1 or 1)
  elseif x>=LIST_X and y>=LIST_Y and y<LIST_Y+VISIBLE_ROWS*ROW_HEIGHT then
    local row=self.scroll+math.floor((y-LIST_Y)/ROW_HEIGHT)+1
    local count=#self:rows()+(self.mode=='menu' and 0 or 1)
    if row<=count then self.cursor=row; self.message=nil; self:choose() end
  elseif x<104 and y>=96 and y<128 and self.mode~='menu' then
    local count=#self:rows()+1
    self.scroll=math.max(0,math.min(math.max(0,count-VISIBLE_ROWS),self.scroll+(x<52 and -VISIBLE_ROWS or VISIBLE_ROWS)))
  end
  return true
end

function Shop:drawSprite(key,x,y)
  local rec=((self.game.data.gen4_graphics or {}).screens or {})[key]
  if not rec then return false end
  local path=type(rec)=='table' and rec.path or rec
  self.icons=self.icons or {}
  if self.icons[path]==nil then local ok,img=pcall(Assets.image,path);self.icons[path]=ok and img or false end
  local image=self.icons[path]
  if not image then return false end
  local ox,oy=0,0
  if type(rec)=='table' then ox,oy=rec.originX or 0,rec.originY or 0 end
  love.graphics.draw(image,x+ox,y+oy);return true
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
  if input:wasPressed('b') then self:back()
  elseif input:wasPressed('up') then self:step(self.mode == 'quantity' and 1 or -1)
  elseif input:wasPressed('down') then self:step(self.mode == 'quantity' and -1 or 1)
  elseif input:wasPressed('right') and self.mode == 'quantity' then self:step(10)
  elseif input:wasPressed('left') and self.mode == 'quantity' then self:step(-10)
  elseif input:wasPressed('a') then self:choose() end
end

-- the clerk's line in the field message box (bank 543 over the field)
function Shop:drawFieldMessage()
  if not self.message then return end
  Font.drawDialogueBox(1, 18, 30, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local y = 152
  for line in (tostring(self.message) .. '\n'):gmatch('([^\n\v\f]*)[\n\v\f]') do
    if y > 176 then break end
    Font.draw(line, 16, y); y = y + 16
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

function Shop:draw()
  local g = love.graphics
  if not self:counterUp() then
    g.setColor(1, 1, 1, 1)
    if self.mode == 'menu' then self:drawContextMenu() end
    if self.mode == 'menu' or self.mode == 'exit' then self:drawFieldMessage() end
    return
  end
  local art = ((self.game.data.gen4_graphics or {}).screens or {})['shop/tilemap']
  local path = type(art) == 'table' and art.path or art
  if path and self.image == nil then
    local ok, img = pcall(Assets.image, path); self.image = ok and img or false
  end
  g.setColor(1, 1, 1, 1)
  if self.image then g.draw(self.image, 0, 0) end
  -- Keep the ROM's list and description panels visible. Game Boy windows
  -- previously covered almost every pixel of the imported shop artwork.
  -- Shop_PrintCurrentMoney: "Money" over the amount, right-aligned, in the
  -- standard window at tile (1, 1), 9 x 4
  require('src.ui.Gen4MoneyWindow').draw({ left = 1, top = 1, tilesW = 9, tilesH = 4,
    label = self:line(18, 'Money'), amount = self:line(19, '$' .. tostring(self.game.save.money or 0),
      tostring(self.game.save.money or 0)) })
  if self.mode == 'quantity' or self.mode == 'confirm' then
    local def = self:def(self.item)
    Font.draw(def.name, 112, 16)
    Font.draw('x' .. self.qty .. '   $' .. self.qty * self.unit, 112, 48)
    Font.draw((self.goods and self.goods.ownedLabel or 'In Bag: ')..tostring(self:owned(self.item)),8,120)
    if self.mode=='quantity' then Font.draw('-                 +',112,80) end
    Font.draw(self.mode == 'confirm' and 'A: YES   B: NO' or 'A: OK   B: CANCEL', 104, 96)
  else
    local rows = self:rows()
    for i = 1, VISIBLE_ROWS do
      local index, y = self.scroll + i, LIST_Y + (i - 1) * ROW_HEIGHT
      local id = rows[index]
      if id or self.mode ~= 'menu' and index == #rows + 1 then
        local def = self.mode ~= 'menu' and self:def(id)
        local label = self.mode == 'menu' and id or def and def.name or 'CANCEL'
        if index == self.cursor then
          if not self:drawSprite('shop/cursor_00',172,y+8) then
            g.setColor(0.55,0.75,0.85,1);g.rectangle('fill',96,y-2,152,16)
          end
          g.setColor(1,1,1,1)
        end
        local right = def and (self.mode == 'sell' and ('x' .. self:owned(id)) or ('$' .. (def.price or 0)))
        Font.draw(Font.fit(label, right and 144 - Font.width(right) or 152), LIST_X, y)
        if def then
          Font.draw(right, 248 - Font.width(right), y)
        end
      end
    end
  end
  if self.mode=='buy' or self.mode=='sell' then
    if self.scroll>0 then self:drawSprite('shop/scroll_00',177,8) end
    if self.scroll+VISIBLE_ROWS<#self:rows()+1 then self:drawSprite('shop/scroll_01',177,132) end
  end
  local def, id = self:selectedItem()
  local rec = def and not self.goods and ((self.game.data.gen4_graphics or {}).screens or {})[('items/icon_%03d'):format(tonumber(def.id) or tonumber(id) or 0)]
  if rec then
    local path = type(rec) == 'table' and rec.path or rec
    self.icons = self.icons or {}
    if self.icons[path] == nil then local ok, icon = pcall(Assets.image,path); self.icons[path] = ok and icon or false end
    local icon = self.icons[path]
    if icon then g.draw(icon,Shop.layout.iconX-icon:getWidth()/2,Shop.layout.iconY-icon:getHeight()/2) end
  end
  local y = Shop.layout.descriptionY
  Font.pushStyle({text={1,1,1},shadow={0,0,0}})
  for line in (tostring(self:description()) .. '\n'):gmatch('([^\n]*)\n') do
    if y > 184 then break end
    Font.draw(Font.fit(line, 212), 40, y); y = y + 14
  end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

return Shop
