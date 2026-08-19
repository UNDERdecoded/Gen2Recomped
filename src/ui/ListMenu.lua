-- Generic full-screen scrollable list: items are { label=..., right=...,
-- value=... }; onChoose(item) / onCancel().  Used by the bag, shops, the
-- box and the Pokédex.

local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")

local ListMenu = {}
ListMenu.__index = ListMenu
ListMenu.isOpaque = true

-- SGB: generic whole-screen palette (SET_PAL_GENERIC)
function ListMenu:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

local ROWS = 7
-- frames to wait before key-repeat kicks in, then between repeats
local REPEAT_DELAY = 16
local REPEAT_RATE = 4

-- ui.list_menu identity: unhooked opts pass through unchanged
local function sameOpts(opts) return opts end

-- Gen2's bag screen shows the pack itself down the left column
-- (engine/items/pack.asm DrawPackGFX), one image per pocket: the pack is
-- drawn open at the page you are on.
local packImages = {}
-- the shade the remap shader turns into palette color 2
local GEN2_SHADE2 = 0.33
local function gen2Pack(pocket)
  pocket = pocket or 0
  if packImages[pocket] ~= nil then return packImages[pocket] or nil end
  local Assets = require("src.render.Assets")
  local path = ("assets/generated/ui/pack_%d.png"):format(pocket)
  if not Assets.exists(path) then
    packImages[pocket] = false
    return nil
  end
  local ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
  packImages[pocket] = ok and img or false
  return packImages[pocket] or nil
end

function ListMenu.new(game, title, items, opts)
  opts = opts or {}
  -- bag / shop / dex / generic: mods may enable wrap, pageJump, keyRepeat
  if Runtime.wantsHook("ui.list_menu") then
    local hooked = Runtime.call("ui.list_menu", sameOpts, {
      wrap = opts.wrap,
      pageJump = opts.pageJump,
      keyRepeat = opts.keyRepeat,
      repeatDelay = opts.repeatDelay,
      repeatRate = opts.repeatRate,
    }, {
      game = game,
      title = title,
      kind = opts.kind or title,
      itemCount = items and #items or 0,
    })
    if type(hooked) == "table" then
      if hooked.wrap ~= nil then opts.wrap = hooked.wrap end
      if hooked.pageJump ~= nil then opts.pageJump = hooked.pageJump end
      if hooked.keyRepeat ~= nil then opts.keyRepeat = hooked.keyRepeat end
      if hooked.repeatDelay ~= nil then opts.repeatDelay = hooked.repeatDelay end
      if hooked.repeatRate ~= nil then opts.repeatRate = hooked.repeatRate end
    end
  end
  local self = setmetatable({}, ListMenu)
  self.game = game
  self.title = title
  self.kind = opts.kind or title
  self.items = items
  self.index = 1
  self.scroll = 0
  self.onChoose = opts.onChoose
  self.onCancel = opts.onCancel
  self.footer = opts.footer
  self.pageJump = opts.pageJump    -- Left/Right move a page at a time
  self.wrap = opts.wrap            -- Up on first / Down on last wraps
  self.keyRepeat = opts.keyRepeat  -- hold Up/Down (and pageJump L/R) to scroll
  self.repeatDelay = opts.repeatDelay or REPEAT_DELAY
  self.repeatRate = opts.repeatRate or REPEAT_RATE
  self.holdDir = nil
  self.holdFrames = 0
  self.onSelectKey = opts.onSelectKey -- SELECT pressed on an item
  -- Gen2 pack pockets: LEFT/RIGHT turn the page (engine/items/pack.asm
  -- Pack_JumpToPocket).  Takes priority over pageJump, which the bag
  -- does not use.
  self.onPocketSwitch = opts.onPocketSwitch
  self.pocketIndex = opts.pocketIndex or 0
  -- scripted mode (the old man tutorial): update() runs the script
  -- every frame INSTEAD of reading input -- DisplayListMenuID's old-man
  -- branch (home/list_menu.asm:65-80) never calls HandleMenuInput
  self.script = opts.script
  -- shop mode: the footer becomes the clerk's line in a framed bottom
  -- text box, a money box sits top-right, and the list shortens to
  -- clear them (DisplayPokemartDialogue_'s screen)
  self.dialogue = opts.dialogue
  -- PC item lists (players_pc.asm): PrintListMenuEntries shows 4 names
  -- and PrintText footers ("How many?", stored/withdrew) use the standard
  -- bottom text box -- same row budget as the mart, without the money box.
  self.messageBox = opts.messageBox
  self.money = opts.money          -- () -> current money for the box
  -- BIT_NO_MENU_BUTTON_SOUND (wMiscFlags): both PC sessions hold the flag
  -- for their whole run (engine/menus/pc.asm, engine/menus/players_pc.asm),
  -- so their lists opt out of the A/B beep the same way Menu's noSound does
  self.noSound = opts.noSound or false
  self.rows = opts.rows or ((opts.dialogue or opts.messageBox) and 4 or ROWS)
  -- Gen2's pack screen puts the bag art and the pocket name above a framed
  -- item window instead of Gen1's bare white list, so it fits fewer rows.
  self.gen2Bag = self.kind == "bag"
    and require("src.core.GameVersion").isGen2() or false
  if self.gen2Bag then self.rows = 5 end -- ItemsPocketMenuHeader.MenuData
  -- Gen2's Pokedex is a two-panel screen rather than Gen1's bare list:
  -- Pokedex_DrawMainScreenBG borders one box at (0,0) and another at (0,9),
  -- both nine columns wide, and runs a vertical rule down column 8 -- so the
  -- selected mon's picture and the SEEN/OWN counters live on the left and
  -- the listing gets columns 9-19.  Pokedex_PrintListing steps two rows per
  -- entry from row 2, which is seven of them.
  self.gen2Dex = opts.gen2Dex or nil
  if self.gen2Dex then self.rows = 7 end
  return self
end

local function moveIndex(self, delta)
  local n = #self.items
  if n == 0 then return end
  local next = self.index + delta
  if self.wrap then
    next = ((next - 1) % n) + 1
  else
    next = math.max(1, math.min(n, next))
  end
  self.index = next
end

local function syncScroll(self)
  if self.index - self.scroll > self.rows then
    self.scroll = self.index - self.rows
  end
  if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
end

-- HandleMenuInput_ (home/window.asm) replays SFX_PRESS_AB for any watched
-- A or B press; DisplayListMenuID's mask is PAD_A | PAD_B | PAD_SELECT
-- (home/list_menu.asm), so the SELECT swap key stays silent (#570)
local function beep(self)
  -- game.data is nil under the UI harnesses that drive a list with a stub
  -- game (tests/engine/rebind_capture_bug510.lua), where there is no audio
  -- cache to play out of
  if self.noSound or not (self.game and self.game.data) then return end
  require("src.core.Sound").play(self.game.data, "Press_AB")
end

-- edge press or key-repeat tick for a held direction
local function navPressed(self, dir)
  if dir == "up" then
    moveIndex(self, -1)
  elseif dir == "down" then
    moveIndex(self, 1)
  elseif dir == "left" and self.pageJump then
    moveIndex(self, -self.rows)
  elseif dir == "right" and self.pageJump then
    moveIndex(self, self.rows)
  else
    return false
  end
  syncScroll(self)
  return true
end

function ListMenu:update(dt)
  if self.script then
    self.script(self)
    return
  end
  local input = self.game.input
  -- an empty pocket still turns the page
  if self.onPocketSwitch and input:wasPressed("left") then
    self.onPocketSwitch(self, -1)
    return
  elseif self.onPocketSwitch and input:wasPressed("right") then
    self.onPocketSwitch(self, 1)
    return
  end
  if #self.items == 0 then
    if input:wasPressed("a") or input:wasPressed("b") then
      beep(self)
      self.game.stack:pop()
      if self.onCancel then self.onCancel() end
    end
    return
  end

  local moved = false
  if input:wasPressed("up") then
    moved = navPressed(self, "up")
    self.holdDir, self.holdFrames = "up", 0
  elseif input:wasPressed("down") then
    moved = navPressed(self, "down")
    self.holdDir, self.holdFrames = "down", 0
  elseif self.pageJump and input:wasPressed("left") then
    moved = navPressed(self, "left")
    self.holdDir, self.holdFrames = "left", 0
  elseif self.pageJump and input:wasPressed("right") then
    moved = navPressed(self, "right")
    self.holdDir, self.holdFrames = "right", 0
  elseif self.onSelectKey and input:wasPressed("select") then
    self.onSelectKey(self.items[self.index], self)
  elseif input:wasPressed("b") then
    beep(self)
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
    return
  elseif input:wasPressed("a") then
    beep(self)
    local item = self.items[self.index]
    if self.onChoose then
      self.onChoose(item, self)
    end
    return
  end

  -- hold-to-scroll (opt-in via ui.list_menu keyRepeat)
  if self.keyRepeat then
    local dir = self.holdDir
    if dir and input:isDown(dir) then
      self.holdFrames = self.holdFrames + 1
      local afterDelay = self.holdFrames - self.repeatDelay
      if afterDelay >= 0 and afterDelay % self.repeatRate == 0 then
        navPressed(self, dir)
      end
    else
      self.holdDir, self.holdFrames = nil, 0
    end
  end

  if not moved then syncScroll(self) end
end

-- remove current item (e.g. consumed); keeps cursor valid
function ListMenu:removeCurrent()
  table.remove(self.items, self.index)
  self.index = math.max(1, math.min(self.index, #self.items))
end

function ListMenu:close()
  local top = self.game.stack:top()
  if top == self then self.game.stack:pop() end
end

-- Pokedex_DrawMainScreenBG plus the window trick that puts the listing on the
-- right: the tilemap is snapshotted to the window map after Pokedex_
-- PrintListing (listing at columns 0-10, so screen columns 8-18) and to the
-- BG map after the sidebar is drawn over columns 0-8.  Pokedex_LoadGFX
-- inverts the $60-$7f block, so every cleared cell (tile $7f) is palette
-- colour 3 and the glyphs on it read white; the untouched field stays on the
-- colour-2 tile $32.  Pokedex_PrintNumberIfOldMode returns straight back out
-- in the Johto mode a new game starts in, which is why these rows carry a
-- caught ball and a name but no dex number.
function ListMenu:drawGen2Dex()
  local Sprites = require("src.pokemon.Sprites")
  local P = require("src.render.PaletteFX")
  local shade2 = 0.33
  love.graphics.setColor(shade2, shade2, shade2, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 6, 6, 58, 60)    -- box at (0,0), 7x7
  love.graphics.rectangle("fill", 6, 78, 58, 52)   -- box at (0,9), 6x7
  love.graphics.rectangle("fill", 64, 8, 88, 120)  -- the cleared listing box
  love.graphics.setColor(1, 1, 1, 1)
  for _, r in ipairs({ { 5, 5, 60, 1 }, { 5, 66, 60, 1 }, { 5, 5, 1, 62 },
                       { 5, 77, 60, 1 }, { 5, 130, 60, 1 }, { 5, 77, 1, 54 } }) do
    love.graphics.rectangle("fill", r[1], r[2], r[3], r[4])
  end

  local item = self.items[self.index]
  local id = item and item.value
  if id then
    self.dexPics = self.dexPics or {}
    if self.dexPics[id] == nil then
      local path = Sprites.path(self.game.data, id, "front", { kind = "dex" })
      local ok, img = false, nil
      if path then ok, img = pcall(love.graphics.newImage, path) end
      self.dexPics[id] = ok and img or false
    end
    local pic = self.dexPics[id]
    if pic then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(pic, 8, 8)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  local counts = self.gen2Dex
  Font.beginTint()
  Font.draw(Strings("SEEN"), 8, 88)
  Font.draw(("%3d"):format(counts.seen or 0), 40, 96)
  Font.draw(Strings("OWN"), 8, 112)
  Font.draw(("%3d"):format(counts.owned or 0), 40, 120)
  Font.draw(Strings("SEL"), 0, 136)
  Font.drawCode(0xED, 24, 136)
  Font.draw(Strings("OPTION"), 32, 136)
  Font.draw(Strings("ST"), 88, 136)
  Font.drawCode(0xED, 104, 136)
  Font.draw(Strings("SEARCH"), 112, 136)

  for row = 1, self.rows do
    local i = self.scroll + row
    local entry = self.items[i]
    if not entry then break end
    local y = row * 16
    love.graphics.setColor(1, 1, 1, 1)
    if entry.ball then
      local bx, by = 68, y + 4
      love.graphics.setColor(shade2, shade2, shade2, 1)
      love.graphics.circle("fill", bx, by, 3.5)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", bx - 3.5, by - 0.5, 7, 1)
      love.graphics.circle("fill", bx, by, 1.2)
    end
    Font.draw(entry.label, 72, y)
    if i == self.index then
      -- the cursor is OAM under gfx/pokedex/cursor.pal, so it keeps its green
      -- through the shade remap
      love.graphics.setColor(90 / 255, 189 / 255, 0, 1)
      for _, r in ipairs({ { 64, y - 3, 88, 1 }, { 64, y + 10, 88, 1 },
                           { 64, y - 3, 1, 14 }, { 151, y - 3, 1, 14 } }) do
        love.graphics.rectangle("fill", r[1], r[2], r[3], r[4])
        P.markTrueColor(r[1], r[2], r[3], r[4])
      end
    end
  end
  Font.endTint()
  love.graphics.setColor(1, 1, 1, 1)
end

function ListMenu:draw()
  if self.gen2Dex then return self:drawGen2Dex() end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  local listTop, listX, cursorX = 8, 16, 8
  if self.gen2Bag then
    -- pack.asm: DrawPackGFX at (0,3), DrawPocketName at (0,7),
    -- ClearPocketList at (5,2) 15x10 and the list at menu_coords 7,1.
    -- Everything the tilemap does not blank sits on shade 2, which is
    -- _CGB_PackPals' blue -- or its red inside the pocket-name box.
    listTop, listX, cursorX = 0, 64, 56
    love.graphics.setColor(GEN2_SHADE2, GEN2_SHADE2, GEN2_SHADE2, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 40, 16, 120, 80)
    local pack = gen2Pack(self.pocketIndex)
    -- the pack is plain 2bpp art in GSC: it takes its box's palette
    -- rather than opting out of the shade remap
    if pack then love.graphics.draw(pack, 0, 24) end
    love.graphics.rectangle("fill", 0, 56, 40, 24)
    love.graphics.setColor(GEN2_SHADE2, GEN2_SHADE2, GEN2_SHADE2, 1)
    love.graphics.rectangle("line", 0.5, 56.5, 39, 23)
    love.graphics.setColor(0, 0, 0, 1)
    -- DrawPocketName blits a 5x3 tile block out of gfx/pack/pack_menu.tilemap,
    -- so a two-word pocket ('KEY ITEMS') is stacked, not run on one line --
    -- drawn flat it spilled past the 40px box and into the item list.
    local lines = {}
    for word in Strings(self.title):gmatch("%S+") do lines[#lines + 1] = word end
    local nameTop = 56 + (24 - #lines * 8) / 2
    for i, line in ipairs(lines) do
      Font.draw(line, math.max(0, (40 - Font.width(line)) / 2),
                nameTop + (i - 1) * 8)
    end
    -- header row: the GB font has no side arrows, so the LEFT/RIGHT pocket
    -- markers (Pack_InterpretJoypad.d_left/.d_right) are drawn as triangles
    love.graphics.setColor(1, 1, 1, 1)
    if self.onPocketSwitch then
      love.graphics.polygon("fill", 0, 4, 6, 0, 6, 8)
      love.graphics.polygon("fill", 14, 4, 8, 0, 8, 8)
    end
    Font.draw(Strings("POCKET"), 16, 0)
    local right = Strings("ITEMS")
    local rx = 160 - Font.width(right)
    Font.draw(right, rx, 0)
    love.graphics.polygon("fill", rx - 16, 0, rx - 10, 0, rx - 13, 6)
    love.graphics.polygon("fill", rx - 8, 6, rx - 2, 6, rx - 5, 0)
    love.graphics.setColor(0, 0, 0, 1)
  else
    Font.draw(Strings(self.title), 8, 4)
  end
  if #self.items == 0 then
    Font.draw(Strings("Nothing here."), listX, 64)
  end
  for row = 1, self.rows do
    local i = self.scroll + row
    local item = self.items[i]
    if not item then break end
    local y = listTop + row * 16
    Font.draw(item.label, listX, y)
    if item.ball then -- the Pokédex owned-ball marker tile
      -- one blank glyph after the name, measured in glyph advances rather
      -- than bytes: NIDORAN♂/♀ carry a multi-byte charmap entry, so
      -- `#item.label` overcounted by 2 and pushed their ball 16px right (#285)
      local bx = listX + Font.width(item.label) + 8 + 3
      local by = y + 3
      love.graphics.circle("fill", bx, by, 3.5)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", bx - 3.5, by - 0.5, 7, 1)
      love.graphics.circle("fill", bx, by, 1.2)
      love.graphics.setColor(0, 0, 0, 1)
    end
    if item.right then
      -- PlaceMenuItemQuantity (engine/menus/menu_2.asm) steps the name
      -- pointer by SCREEN_WIDTH + 1 before printing, so GSC hangs the count
      -- on the row BELOW the name at the right edge.  Sharing the name's row
      -- is what let a 12-letter item run into it.
      if self.gen2Bag then
        Font.draw(item.right, 160 - Font.width(item.right), y + 8)
      else
        Font.draw(item.right, 160 - 8 - Font.width(item.right), y)
      end
    end
    if i == self.index then
      -- hollowIndex: a chosen row keeps the hollow '▷' left behind by
      -- pokered's PlaceUnfilledArrowMenuCursor (the old man demo's
      -- auto A-press, home/list_menu.asm:89-91)
      Font.drawCode((self.swapIndex == i or self.hollowIndex == i)
                    and Theme.cursorHollow or Theme.cursor, cursorX, y)
    end
    if self.swapIndex == i and i ~= self.index then
      Font.drawCode(Theme.cursorHollow, cursorX, y) -- ▷ marks the item being moved
    end
  end
  if self.dialogue then
    -- money box (DisplayTextBoxID MONEY_BOX, hlcoord 11,0): the amount
    -- right-aligned on its middle row
    Font.drawBox(11, 0, 9, 3)
    love.graphics.setColor(0, 0, 0, 1)
    local money = ("¥%d"):format(self.money and self.money() or 0)
    Font.draw(money, 152 - Font.width(money), 8)
  end
  -- The footer may be a FUNCTION of the highlighted row, not just a string.
  -- Gen 2's pack prints the item's own description here and repaints it on
  -- every cursor move (UpdateItemDescription), so the content depends on the
  -- SELECTION rather than on the screen -- and a value captured once at
  -- construction can only ever be the row the list opened on.
  local footer = self.footer
  if type(footer) == "function" then
    local okFooter, text = pcall(footer, self, self.items and self.items[self.index])
    footer = okFooter and text or nil
  end
  -- the pack's description box (UpdateItemDescription) is always up
  if self.dialogue or self.gen2Bag or (self.messageBox and footer) then
    -- standard bottom text box (PrintText); long prompts wrap and keep
    -- their last two lines, like the GB's scrolled box (#115/#174)
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    if footer then
      local flat = {}
      for _, page in ipairs(require("src.render.TextBox").paginate(footer)) do
        for _, line in ipairs(page) do flat[#flat + 1] = line end
      end
      local y = 112
      for i = math.max(1, #flat - 1), #flat do
        Font.draw(flat[i], 8, y)
        y = y + 16
      end
    end
  elseif footer then
    -- bare footer (bag money line, etc.)
    local flat = {}
    for _, page in ipairs(require("src.render.TextBox").paginate(footer)) do
      for _, line in ipairs(page) do flat[#flat + 1] = line end
    end
    local y = (#flat >= 2) and 120 or 136
    for i = math.max(1, #flat - 1), #flat do
      Font.draw(flat[i], 8, y)
      y = y + 16
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return ListMenu
