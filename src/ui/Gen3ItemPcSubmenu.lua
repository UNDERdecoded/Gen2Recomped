-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FireRed item_pc.c's per-item submenu: WITHDRAW / GIVE / CANCEL.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3ItemPcSubmenu = {}
Gen3ItemPcSubmenu.__index = Gen3ItemPcSubmenu
Gen3ItemPcSubmenu.isOpaque = false

function Gen3ItemPcSubmenu:uiSize() return 240, 160 end
function Gen3ItemPcSubmenu:wantsFillScale() return true end
function Gen3ItemPcSubmenu:wantsEdgeBleed() return false end

local ENTRIES = {
  { label = "WITHDRAW", kind = "withdraw" },
  { label = "GIVE", kind = "give" },
  { label = "CANCEL", kind = "cancel" },
}
local SELECTED = { x = 48, y = 120, width = 112, height = 32 }

function Gen3ItemPcSubmenu.new(game, itemPc, itemName, onPick)
  local self = setmetatable({
    game = game, itemPc = itemPc, itemName = itemName or "",
    onPick = onPick, index = 1,
  }, Gen3ItemPcSubmenu)
  if itemPc and itemPc.setTransientWindow then itemPc:setTransientWindow("submenu") end
  return self
end

function Gen3ItemPcSubmenu:entries()
  local out, prose = {}, require("src.ui.GbaProse")
  for i, entry in ipairs(ENTRIES) do
    out[i] = { label = prose.itemPc(self.game, entry.kind, Strings(entry.label)), kind = entry.kind }
  end
  return out
end

function Gen3ItemPcSubmenu:move(delta)
  self.index = math.max(1, math.min(#ENTRIES, self.index + delta))
  Sound.play(self.game.data, "Press_AB")
end

function Gen3ItemPcSubmenu:close(kind)
  if self.itemPc and self.itemPc.setTransientWindow then
    self.itemPc:setTransientWindow(nil)
  end
  self.game.stack:pop()
  if kind and kind ~= "cancel" and self.onPick then self.onPick(kind) end
end

function Gen3ItemPcSubmenu:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("up") then return self:move(-1) end
  if input:wasPressed("down") then return self:move(1) end
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    return self:close("cancel")
  end
  if input:wasPressed("a") then
    Sound.play(self.game.data, "Press_AB")
    return self:close(ENTRIES[self.index].kind)
  end
end

function Gen3ItemPcSubmenu:keypressed(key)
  if key == "up" then return self:move(-1) end
  if key == "down" then return self:move(1) end
  if key == "b" then return self:close("cancel") end
  if key == "a" then return self:close(ENTRIES[self.index].kind) end
end

function Gen3ItemPcSubmenu:draw()
  local b = self.itemPc and self.itemPc:box("submenu")
            or { x = 176, y = 104, width = 56, height = 48 }
  if self.itemPc and self.itemPc.drawContentFrame then
    self.itemPc:drawContentFrame(b)
  else
    Font.drawBox(math.floor(b.x / 8) - 1, math.floor(b.y / 8) - 1,
                 math.floor(b.width / 8) + 2, math.floor(b.height / 8) + 2, 1)
  end
  love.graphics.setColor(0, 0, 0, 1)
  local styles = self.game.data.font and self.game.data.font.uiTextStyles or {}
  if styles.dark then Font.pushStyle(styles.dark) end
  for i, entry in ipairs(self:entries()) do
    local y = b.y + 2 + (i - 1) * 16
    Font.draw(entry.label, b.x + 8, y)
    if i == self.index then Font.drawCode(Theme.cursor, b.x, y) end
  end

  local selected = self.itemPc and self.itemPc:subBox("selected") or SELECTED
  if self.itemPc and self.itemPc.drawContentFrame then
    self.itemPc:drawContentFrame(selected, "standard")
  else
    Font.drawBox(selected.x / 8 - 1, selected.y / 8 - 1,
                 selected.width / 8 + 2, selected.height / 8 + 2, 1)
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.itemName .. Strings(" is"), selected.x, selected.y + 2)
  Font.draw(Strings("selected."), selected.x, selected.y + 16)
  if styles.dark then Font.popStyle() end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3ItemPcSubmenu
