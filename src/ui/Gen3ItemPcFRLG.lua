-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FIRERED'S ITEM PC (item_pc.c).
--
-- WITHDRAW uses this screen instead of borrowing the bag.  The cartridge
-- background already contains the panel furniture; the BG0 windows define
-- where the label, list and description text land over it.  The item icon is
-- the same 24x24 icon sprite the bag uses, but ItemPc fixes its centre at
-- (24,140).

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3ItemPcFRLG = {}
Gen3ItemPcFRLG.__index = Gen3ItemPcFRLG
Gen3ItemPcFRLG.isOpaque = true

local GBA_W, GBA_H = 240, 160
local FALLBACK = {
  windows = {
    list = { x = 56, y = 8, width = 152, height = 96 },
    description = { x = 40, y = 112, width = 200, height = 48 },
    label = { x = 8, y = 8, width = 40, height = 32 },
    quantity = { x = 192, y = 120, width = 40, height = 32 },
    submenu = { x = 176, y = 104, width = 56, height = 48 },
    message = { x = 16, y = 120, width = 208, height = 32 },
  },
  subwindows = {
    selected = { x = 48, y = 120, width = 112, height = 32 },
    quantityPrompt = { x = 48, y = 120, width = 128, height = 32 },
    result = { x = 48, y = 120, width = 184, height = 32 },
  },
  list = {
    itemX = 9, cursorX = 1, upTextY = 2, rowHeight = 16,
    rows = 6, quantityX = 110,
  },
  description = { x = 0, y = 3, lineHeight = 14 },
  itemIcon = { x = 8, y = 124, size = 24 },
}

function Gen3ItemPcFRLG.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3ItemPcFRLG)
  self.game = game
  self.rows = opts.rows or {}
  self.nativeProse = opts.nativeProse == true or opts.title == nil
  self.title = opts.title or Strings("WITHDRAW ITEM")
  self.onPick = opts.onPick
  self.onCancel = opts.onCancel
  self.onReorder = opts.onReorder
  self.index, self.top = 1, 1
  self.transientWindow = nil
  return self
end

function Gen3ItemPcFRLG:titleText()
  if self.nativeProse then
    return require("src.ui.GbaProse").itemPc(self.game, "title", self.title)
  end
  return self.title
end

-- item_pc.c keeps the base screen alive while it places transient BG0 windows
-- over the lower description area.  In the port those transient windows are
-- separate transparent stack states, so the base screen is redrawn first on
-- every frame.  Marking the active transient lets the base omit its description
-- text while a submenu / quantity prompt / result owns that same rectangle;
-- otherwise the old description remains visible around the smaller overlay and
-- looks like two windows were composited together.
function Gen3ItemPcFRLG:setTransientWindow(kind)
  self.transientWindow = kind
end

function Gen3ItemPcFRLG:uiSize() return GBA_W, GBA_H end
function Gen3ItemPcFRLG:wantsFillScale() return true end
function Gen3ItemPcFRLG:wantsEdgeBleed() return false end

function Gen3ItemPcFRLG:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

function Gen3ItemPcFRLG:screen()
  local r = (self.game.data.constants or {}).gen3FRLGItemPc
  if type(r) ~= "table" or type(r.windows) ~= "table" then return FALLBACK end
  return r
end

function Gen3ItemPcFRLG:box(key)
  local r = self:screen()
  return (r.windows and r.windows[key]) or FALLBACK.windows[key]
end

function Gen3ItemPcFRLG:subBox(key)
  local r = self:screen()
  return (r.subwindows and r.subwindows[key]) or FALLBACK.subwindows[key]
end

-- Every rectangle item_pc.c stores in a WindowTemplate is the CONTENT area.
-- DrawStdFrameWithCustomTileAndPalette adds one 8px tile around it.  The old
-- overlays treated those content dimensions as the complete frame, shrinking
-- every transient window and pushing the right-hand submenu partly off-screen.
function Gen3ItemPcFRLG:drawContentFrame(b, frameIndex)
  if not b then return end
  local tx, ty = math.floor(b.x / 8) - 1, math.floor(b.y / 8) - 1
  local tw, th = math.floor(b.width / 8) + 2, math.floor(b.height / 8) + 2
  if frameIndex == "standard" and Font.drawStandardBox then
    Font.drawStandardBox(tx, ty, tw, th)
  else
    -- ItemPc_SetBorderStyleOnWindow uses the player's current user frame for
    -- submenu / quantity windows. Only callers that explicitly request the
    -- fixed standard frame should override it.
    Font.drawBox(tx, ty, tw, th, tonumber(frameIndex))
  end
end

function Gen3ItemPcFRLG:listRows()
  local r = self:screen()
  return math.max(1, math.floor(tonumber(r.list and r.list.rows)
                               or FALLBACK.list.rows))
end

function Gen3ItemPcFRLG:selected()
  return self.rows[self.index]
end

function Gen3ItemPcFRLG:setRows(rows)
  self.rows = rows or {}
  self.index = math.max(1, math.min(self.index or 1, #self.rows))
  local visible = self:listRows()
  self.top = math.max(1, math.min(self.top or 1,
                  math.max(1, #self.rows - visible + 1)))
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then
    self.top = self.index - visible + 1
  end
end

function Gen3ItemPcFRLG:moveCursor(delta)
  local n = #self.rows
  if n == 0 then return end
  self.index = (self.index - 1 + delta) % n + 1
  local visible = self:listRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then
    self.top = self.index - visible + 1
  end
  Sound.play(self.game.data, "Press_AB")
end

function Gen3ItemPcFRLG:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen3ItemPcFRLG:beginMove()
  local row = self:selected()
  if not row or row.close then return end
  self.moveIndex = self.index
  Sound.play(self.game.data, "Press_AB")
end

function Gen3ItemPcFRLG:finishMove()
  local from = self.moveIndex
  if not from then return end
  local source = self.rows[from]
  local to = self.index
  local target = self.rows[to]
  self.moveIndex = nil
  -- MoveItemSlotInList is an insertion move. Dropping on the source itself or
  -- the row immediately after it cannot change the list.
  if not source or source.close or to == from or to == from + 1 then
    Sound.play(self.game.data, "Press_AB")
    return
  end
  if self.onReorder then
    self.onReorder(source.id, target and not target.close and target.id or nil)
  end
  for i, row in ipairs(self.rows) do
    if row.id == source.id then self.index = i; break end
  end
  local visible = self:listRows()
  if self.index < self.top then self.top = self.index end
  if self.index > self.top + visible - 1 then self.top = self.index - visible + 1 end
  Sound.play(self.game.data, "Press_AB")
end

function Gen3ItemPcFRLG:cancelMove()
  if not self.moveIndex then return false end
  self.moveIndex = nil
  Sound.play(self.game.data, "Press_AB")
  return true
end

function Gen3ItemPcFRLG:choose()
  if self.moveIndex then return self:finishMove() end
  local row = self:selected()
  if not row or row.close then return self:close() end
  -- Task_ItemPcMain opens sItemPcSubmenuOptions first.  WITHDRAW and GIVE then
  -- branch from that answer; CANCEL simply restores this same list.
  self.game.stack:push(require("src.ui.Gen3ItemPcSubmenu").new(
    self.game, self, row.label or row.id, function(kind)
      if self.onPick then self.onPick(row.id, self, kind) end
    end))
end

function Gen3ItemPcFRLG:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("a") then self:choose()
  elseif input:wasPressed("select") then
    if self.moveIndex then self:finishMove() else self:beginMove() end
  elseif input:wasPressed("b") then
    if not self:cancelMove() then self:close() end
  end
end

function Gen3ItemPcFRLG:keypressed(key)
  if key == "down" then return self:moveCursor(1) end
  if key == "up" then return self:moveCursor(-1) end
  if key == "a" then return self:choose() end
  if key == "tab" or key == "select" then
    if self.moveIndex then return self:finishMove() end
    return self:beginMove()
  end
  if key == "b" then
    if not self:cancelMove() then return self:close() end
  end
end

function Gen3ItemPcFRLG:background()
  local path = ((self.game.data.constants or {}).gen3FRLGItemPc or {}).image
  if type(path) ~= "string" then return nil end
  local ok, image = pcall(Assets.image, path)
  return ok and image or nil
end

local function drawLines(text, x, y, pitch)
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    Font.draw(line, x, y)
    y = y + pitch
  end
end

function Gen3ItemPcFRLG:drawRows()
  local r = self:screen()
  local L = r.list or FALLBACK.list
  local win = self:box("list")
  local pitch = math.max(8, math.floor(tonumber(L.rowHeight)
                                      or FALLBACK.list.rowHeight))
  local y0 = win.y + (tonumber(L.upTextY) or FALLBACK.list.upTextY)
  local itemX = win.x + (tonumber(L.itemX) or FALLBACK.list.itemX)
  local cursorX = win.x + (tonumber(L.cursorX) or FALLBACK.list.cursorX)
  local quantityX = win.x + (tonumber(L.quantityX) or FALLBACK.list.quantityX)

  local uiStyles = self.game.data.font and self.game.data.font.uiTextStyles or {}
  if uiStyles.dark then Font.pushStyle(uiStyles.dark) end
  for i = 0, self:listRows() - 1 do
    local row = self.rows[self.top + i]
    if not row then break end
    local y = y0 + i * pitch
    local label = row.label or ""
    if self.nativeProse and row.close then
      label = require("src.ui.GbaProse").itemPc(self.game, "cancel", label)
    end
    Font.draw(label, itemX, y)
    if row.qty and not row.close then
      local faced = Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
      Font.draw(Strings("×%3d", row.qty), quantityX, y)
      if faced then Font.popFace() end
    end
    local n = self.top + i
    if n == self.index then
      Font.drawCode(self.moveIndex == n and Theme.cursorHollow or Theme.cursor,
                    cursorX, y)
    elseif self.moveIndex == n then
      Font.drawCode(Theme.cursorHollow, cursorX, y)
    end
  end
  if uiStyles.dark then Font.popStyle() end
end

function Gen3ItemPcFRLG:draw()
  love.graphics.setColor(1, 1, 1, 1)
  local field = self:background()
  if field then
    love.graphics.draw(field, 0, 0)
  else
    love.graphics.setColor(0.74, 0.78, 0.71, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
    for _, key in ipairs({ "label", "list", "description" }) do
      local b = self:box(key)
      Font.drawBox(math.floor(b.x / 8), math.floor(b.y / 8),
                   math.floor(b.width / 8), math.floor(b.height / 8))
    end
  end

  love.graphics.setColor(0, 0, 0, 1)
  local label = self:box("label")
  local labelText = tostring(self:titleText() or ""):gsub(" ", "\n", 1)
  local faced = Font.hasFace and Font.hasFace("small") and Font.pushFace("small")
  local uiStyles = self.game.data.font and self.game.data.font.uiTextStyles or {}
  if uiStyles.white then Font.pushStyle(uiStyles.white) end
  drawLines(labelText, label.x, label.y + 1, 13)
  if uiStyles.white then Font.popStyle() end
  if faced then Font.popFace() end

  self:drawRows()

  local row = self:selected()
  if not self.transientWindow then
    local desc = self:box("description")
    local D = self:screen().description or FALLBACK.description
    local description = row and (row.close and Strings("Return to the PC.")
                                  or row.description) or ""
    if uiStyles.white then Font.pushStyle(uiStyles.white) end
    drawLines(description, desc.x + (tonumber(D.x) or 0),
              desc.y + (tonumber(D.y) or 3),
              tonumber(D.lineHeight) or FALLBACK.description.lineHeight)
    if uiStyles.white then Font.popStyle() end
  end

  if row and (row.id or row.close) then
    local BagScreen = require("src.ui.Gen3BagMenu")
    local ok, icon, quad, size = pcall(BagScreen.itemIcon,
      { game = self.game }, row.id, row.close and 375 or nil)
    if ok and icon and quad then
      local cell = self:screen().itemIcon or FALLBACK.itemIcon
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(icon, quad, cell.x, cell.y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3ItemPcFRLG
