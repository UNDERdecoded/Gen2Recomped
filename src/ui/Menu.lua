-- Generic bordered list menu with the blinking ▶ cursor.
-- items: { { label=..., onSelect=function }, ... }
-- Pops itself on B (unless cancelable=false); also on START only when
-- opts.startCloses is set -- pokered's wMenuWatchedKeys mask varies per
-- menu and only the start menu's adds PAD_START.

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local Menu = {}
Menu.__index = Menu

function Menu.new(game, items, opts)
  local self = setmetatable({}, Menu)
  opts = opts or {}
  self.game = game
  self.items = items
  self.index = 1
  self.tx = opts.tx or 10
  self.ty = opts.ty or 0
  self.tw = opts.tw or 10
  -- Gen 3 WindowTemplate coordinates describe the CONTENT rectangle.  Its
  -- standard frame is drawn one tile outside on every side.  Most of this
  -- engine's menus use the older convention where tx/ty/tw/th already name
  -- the OUTER framed rectangle, so keep that as the default and opt the few
  -- cartridge-window callers into the GBA convention explicitly.
  self.gbaWindow = opts.gbaWindow or false
  self.frameIndex = opts.frameIndex
  -- grow the box to the widest label so longer (e.g. localized) labels don't
  -- overflow the frame; nudge tx left to keep the box on-screen (20 tiles).
  do
    local widest = 0
    for _, it in ipairs(items) do
      if it.label then
        local n = #Font.split(it.label)
        if n > widest then widest = n end
      end
    end
    local needed = widest + 3
    if not self.gbaWindow and needed > self.tw then self.tw = needed end
    -- ...ON THE SCREEN THAT IS ACTUALLY THERE.  Twenty tiles is the Game Boy's
    -- width and was written in here as a constant; Hoenn's screen is thirty,
    -- so a box the cartridge places near the right-hand side was shoved left
    -- by ten tiles.  Theme.uiSize is the same answer every Gen 3 screen asks
    -- for, and it returns the Game Boy's own 160 for Gen 1 and Gen 2, so
    -- nothing there moves.
    local cols = math.floor(select(1, Theme.uiSize()) / 8)
    if not self.gbaWindow and self.tx + self.tw > cols then
      self.tx = math.max(0, cols - self.tw)
    end
  end
  self.rowStep = opts.rowStep or 2
  -- maxVisible: cap the box to this many rows and scroll the rest instead
  -- of growing past it (e.g. the start menu, whose row count varies with
  -- save state and mod hooks); nil/unset keeps every caller's old
  -- behavior of sizing the box to fit all items.
  self.maxVisible = opts.maxVisible
  self.scroll = 0
  local visible = (self.maxVisible and math.min(self.maxVisible, #items))
    or #items
  self.th = opts.th or (visible * self.rowStep + 2)
  self.cancelable = opts.cancelable ~= false
  -- Whether START closes the menu.  In pokered a menu responds only to the
  -- keys in its wMenuWatchedKeys mask; the common PAD_A | PAD_B (and the
  -- list menu's PAD_A | PAD_B | PAD_SELECT) masks leave START unwatched, so
  -- only menus whose real mask includes PAD_START -- the start menu
  -- (engine/menus/draw_start_menu.asm) -- opt in here.
  self.startCloses = opts.startCloses or false
  -- screen-edge anchor for this menu (see Menu:draw); nil keeps it in the
  -- classic centred letterbox
  self.anchor = opts.anchor
  self.onCancel = opts.onCancel
  -- BIT_NO_MENU_BUTTON_SOUND (wMiscFlags): the PC session runs its
  -- menus silent (home/window.asm HandleMenuInput_)
  self.noSound = opts.noSound or false
  -- opts.onHighlight(index, item): fired once on open and again every time
  -- the cursor lands on a different row.  Crystal's boy/girl question uses
  -- it to swap the pic above the box to whichever character is under the
  -- cursor; menus that do not pass it behave exactly as before.
  self.onHighlight = opts.onHighlight
  -- opts.index: open with the cursor on this row (1-based) rather than the
  -- first -- FireRed's elevator opens on the floor you are standing on
  if tonumber(opts.index) then
    self.index = math.max(1, math.min(#items, math.floor(tonumber(opts.index))))
  end
  -- A LINE UNDER THE MENU SAYING WHAT THE ROW DOES.
  --
  -- Emerald's PC menus are two windows, not one: the list, and a message
  -- window under it carrying the highlighted row's own description --
  -- "Take out items from the PC.", "Store POKeMON in your party in BOXES."
  -- Both description arrays have been read out of the cartridge since the
  -- menus went in (gen3PCMenu.describe and .storage.describe) and neither
  -- was ever drawn, because this widget had nowhere to put them: a row's
  -- `describe` was set by two callers and silently ignored.
  --
  -- The box is the screen's own bottom strip, which is where the cartridge
  -- puts it, and it only appears for a menu that has descriptions at all --
  -- so every Game Boy menu in this engine is untouched.
  self.describeBox = opts.describeBox
  for _, it in ipairs(items) do
    if it.describe then self.describes = true break end
  end
  self:clampScroll()
  if self.onHighlight then self.onHighlight(self.index, self.items[self.index]) end
  return self
end

-- keeps self.index inside the visible [scroll+1, scroll+maxVisible] window;
-- callers that move self.index directly (e.g. restoring a saved cursor
-- position) should call this afterwards to scroll it into view
function Menu:clampScroll()
  if not (self.maxVisible and #self.items > self.maxVisible) then
    self.scroll = 0
    return
  end
  if self.index - self.scroll > self.maxVisible then
    self.scroll = self.index - self.maxVisible
  elseif self.index - self.scroll < 1 then
    self.scroll = self.index - 1
  end
end

function Menu:update(dt)
  local input = self.game.input
  local wasIndex = self.index
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.items
  elseif input:wasPressed("down") then
    self.index = self.index < #self.items and self.index + 1 or 1
  elseif input:wasPressed("a") then
    -- HandleMenuInput_ (home/window.asm): SFX_PRESS_AB on every A press
    if not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    local item = self.items[self.index]
    -- keepOpen entries run without closing the menu (e.g. the
    -- Pokédex CRY option keeps the side menu up)
    if not item.keepOpen then self.game.stack:pop() end
    if item.onSelect then item.onSelect() end
  elseif self.cancelable and (input:wasPressed("b")
      or (self.startCloses and input:wasPressed("start"))) then
    -- HandleMenuInput_ returns for any watched key, but only replays
    -- SFX_PRESS_AB for the PAD_A | PAD_B branch -- so B beeps and START
    -- (when watched, e.g. the start menu) closes silently.
    if input:wasPressed("b") and not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  end
  self:clampScroll()
  if self.onHighlight and self.index ~= wasIndex then
    self.onHighlight(self.index, self.items[self.index])
  end
end

function Menu:draw()
  -- A MENU THAT IS STILL ON THE STACK BUT NOT ON SCREEN.  A state above it
  -- may be an OVERLAY rather than a screen -- Hoenn's counter is one -- and
  -- then whatever is left underneath shows through it.  `hidden` keeps the
  -- state (so closing what is above lands back on it) and stops the drawing.
  if self.hidden then return end
  -- opts.anchor opts a menu out of the centred letterbox and onto a screen
  -- edge (the START menu asks for "topright").  Only menus that ask for it
  -- move; every other menu is placed exactly as before.
  local r = self.anchor and self.game and self.game.renderer
  local frameTx, frameTy, frameTw, frameTh = self.tx, self.ty, self.tw, self.th
  if self.gbaWindow then
    frameTx, frameTy = self.tx - 1, self.ty - 1
    frameTw, frameTh = self.tw + 2, self.th + 2
  end
  if r and r.setUIAnchor then
    r:setUIAnchor(frameTx * 8, frameTy * 8,
                  frameTw * 8, frameTh * 8, self.anchor)
  end
  Font.drawBox(frameTx, frameTy, frameTw, frameTh, self.frameIndex)
  love.graphics.setColor(0, 0, 0, 1)
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
    or #self.items
  -- Row Y: pokered's boxed menus anchor the choices to the BOTTOM interior
  -- row and let any slack fall as a blank row under the top edge --
  -- draw_start_menu.asm (TextBoxBorder 10,0, then hlcoord 12,2 /
  -- wTopMenuItemY 2), players_pc.asm and bills_pc.asm all do the same.  The
  -- bottom border is ty + th - 1, so the last choice sits on ty + th - 2 and
  -- row r counts back up from there.  Anchoring from the top instead only
  -- agrees when th is exactly visible * rowStep + 2, which is Menu.new's
  -- default but NOT what a caller sizing its own box passes: BagMenu's
  -- USE/TOSS is th = 5 for two choices (#284, matching text_boxes.asm's
  -- USE_TOSS_MENU_TEMPLATE rows 10..14), and a top anchor pushed TOSS onto
  -- the bottom border (#564, #572).
  -- ...AND LIFTED BY WHATEVER IT OVERHANGS.
  --
  -- The anchor above is right for a Game Boy character, which is one tile.
  -- Emerald's dialogue face is FIFTEEN pixels tall, so the bottom-anchored
  -- last row runs seven pixels into the border it is anchored against -- and
  -- with the slack still falling under the top edge, the whole list reads as
  -- if it started halfway down the box.  The block rises by exactly its
  -- overhang, which is nothing at all for an 8-pixel font: every Game Boy
  -- menu in this engine draws where it always did, and a taller face lands
  -- with its last descender flush on the inner edge.
  if self.gbaWindow then
    -- FireRed Menu_InitCursor + AddTextPrinterParameterized3: the selector is
    -- at x=0 in the window, labels at x=8, both start one pixel down, and rows
    -- are sixteen pixels apart in the Oak intro menus.
    for row = 1, visible do
      local item = self.items[self.scroll + row]
      if not item then break end
      local y = self.ty * 8 + 1 + (row - 1) * self.rowStep * 8
      Font.draw(item.label, self.tx * 8 + 8, y)
    end
    local cursorRow = self.index - self.scroll
    Font.drawCode(Theme.cursor, self.tx * 8,
      self.ty * 8 + 1 + (cursorRow - 1) * self.rowStep * 8)
    self:drawDescription()
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local lastY = (self.ty + self.th - 2) * 8
  local lift = math.max(0, (lastY + Font.glyphHeight())
                           - (self.ty + self.th - 1) * 8)
  for row = 1, visible do
    local item = self.items[self.scroll + row]
    if not item then break end
    Font.draw(item.label, (self.tx + 2) * 8,
      (self.ty + self.th - 2 - (visible - row) * self.rowStep) * 8 - lift)
  end
  local cursorRow = self.index - self.scroll
  Font.drawCode(Theme.cursor, (self.tx + 1) * 8,
    (self.ty + self.th - 2 - (visible - cursorRow) * self.rowStep) * 8 - lift)
  -- moreArrow ($EE): the same "more below" glyph OptionRows/ManagerState
  -- use, sat on the bottom border like TextBox's page-advance cursor.  It
  -- has to be the border row, not ty + th - 2: that is the last interior
  -- row, which the last choice now occupies, and Menu.new widens the box to
  -- widest + 3 so tx + tw - 2 is exactly that label's final glyph (#564).
  if self.maxVisible and self.scroll + self.maxVisible < #self.items then
    Font.drawCode(Theme.moreArrow, (self.tx + self.tw - 2) * 8,
      (self.ty + self.th - 1) * 8)
  end
  self:drawDescription()
  love.graphics.setColor(1, 1, 1, 1)
end

-- The highlighted row's description, in a box along the bottom of the screen.
-- Sized to the screen Theme reports, so the Game Boy's 160x144 and Hoenn's
-- 240x160 each get a full-width strip without this widget knowing which it
-- is drawing on.
function Menu:drawDescription()
  if not self.describes then return end
  local item = self.items[self.index]
  local text = item and item.describe
  if type(text) ~= "string" or text == "" then return end
  local w, h = Theme.uiSize()
  local cols, rowsTall = math.floor(w / 8), math.floor(h / 8)
  local lines = 0
  for _ in (text .. "\n"):gmatch("[^\n]*\n") do lines = lines + 1 end
  local box = self.describeBox or {}
  local bh = box.th or (lines * 2 + 2)
  local bw = box.tw or cols
  local bx = box.tx or 0
  local by = box.ty or (rowsTall - bh)
  Font.drawBox(bx, by, bw, bh)
  love.graphics.setColor(0, 0, 0, 1)
  local y = (by + 1) * 8
  for line in text:gmatch("[^\n]+") do
    Font.draw(line, (bx + 1) * 8, y)
    y = y + 16
  end
end

return Menu
