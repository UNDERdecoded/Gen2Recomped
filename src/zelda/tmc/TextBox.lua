-- Message windows for The Minish Cap.
--
-- Messages are the cartridge's own bytes (text.lua from the import).  The
-- control codes are the ones tools/src/tmc_strings documents:
--   $0A newline              $02 c  colour (0 white 1 red 2 green 3 blue 4 yellow)
--   $03 a b sound            $04 a [b]  window settings ($04 $10 x)
--   $05 c [a]  choice        $06 n  variable (0 = the player's name,
--                                   1..n = a choice cursor slot)
--   $07 a b, $08 $FF, $09 a  timing    $0C k  a button glyph   $0F s  a symbol
-- Two lines show at a time (an empty line starts a new page), typed out a
-- character per frame; A or B finishes the page, then turns it.

local bit = require("bit")
local band = bit.band

local TextBox = {}
TextBox.__index = TextBox

local COLORS = {
  [0] = { 1, 1, 1 }, { 0.97, 0.35, 0.3 }, { 0.4, 0.95, 0.45 }, { 0.45, 0.65, 1 }, { 1, 0.9, 0.35 },
}
local KEYS = { [0] = "A", "B", "L", "R", "+", "+", "+", "+", "+", "SELECT", "START" }

-- bytes -> lines of runs {text, color}; choice slots recorded
function TextBox.parse(bytes, playerName, opts)
  local lines, line, color = {}, {}, 0
  local choices = {}
  local slots05 = {} -- round 8: $05 choice markers (used when no $06 slot is)
  opts = opts or {}
  local i, n = 1, #bytes
  local function put(s)
    local last = line[#line]
    if last and last.color == color and not last.slot then last.text = last.text .. s
    else line[#line + 1] = { text = s, color = color } end
  end
  local function newline()
    lines[#lines + 1] = line
    line = {}
  end
  while i <= n do
    local c = bytes:byte(i)
    i = i + 1
    if c == 0x0A then newline()
    elseif c == 0x0D then -- carriage return: ignored
    elseif c == 0x02 then color = bytes:byte(i) or 0; i = i + 1
    elseif c == 0x01 or c == 0x09 or c == 0x0F then
      if c == 0x0F then put("*") end
      i = i + 1
    elseif c == 0x07 and opts.continue then
      -- round 8: $07 hi lo goes on with message (hi << 8 | lo) in a new window
      local nb = opts.continue((bytes:byte(i) or 0) * 256 + (bytes:byte(i + 1) or 0))
      i = i + 2
      if nb then
        newline(); newline()
        bytes, i, n = nb, 1, #nb
      end
    elseif c == 0x03 or c == 0x07 then i = i + 2
    elseif c == 0x04 then
      local a = bytes:byte(i) or 0
      i = i + (a == 0x10 and 2 or 1)
    elseif c == 0x05 then
      local a = bytes:byte(i) or 0
      i = i + (a == 0xFF and 1 or 2)
      choices.present = true
      local run = { text = "  ", color = color, slot = #slots05 + 1 }
      line[#line + 1] = run
      slots05[#slots05 + 1] = run
    elseif c == 0x06 then
      local v = bytes:byte(i) or 0
      i = i + 1
      if v == 0 then put(playerName or "Link")
      elseif opts.numbers and opts.numbers[v] then put(tostring(opts.numbers[v])) -- round 27A: gMessage.rupees / field_0x14 by the code's number (SideQuests27.messageNumbers)
      elseif opts.number then put(tostring(opts.number)) -- round 8: gMessage.rupees
      else
        local run = { text = "  ", color = color, slot = v }
        line[#line + 1] = run
        choices[#choices + 1] = run
      end
    elseif c == 0x08 then i = i + 1
    elseif c == 0x0C then
      put("[" .. (KEYS[bytes:byte(i) or 0] or "?") .. "]")
      i = i + 1
    elseif c >= 0x20 and c < 0x7F then put(string.char(c))
    elseif c == 0x85 then put("...")
    elseif c == 0xA3 then put("~")
    elseif c >= 0x80 then put("?")
    end
  end
  newline()
  if #choices == 0 and #slots05 >= 2 then
    for k, r in ipairs(slots05) do choices[k] = r end
    choices.present = true
  else
    for _, r in ipairs(slots05) do r.text = ""; r.slot = nil end
  end
  return lines, choices
end

-- break the lines into pages of two; a blank line forces a page turn
local function paginate(lines)
  local pages, page = {}, {}
  for _, l in ipairs(lines) do
    local blank = #l == 0
    if blank then
      if #page > 0 then pages[#pages + 1] = page; page = {} end
    else
      page[#page + 1] = l
      if #page == 2 then pages[#pages + 1] = page; page = {} end
    end
  end
  if #page > 0 then pages[#pages + 1] = page end
  if #pages == 0 then pages[1] = {} end
  return pages
end

function TextBox.new(bytes, opts)
  opts = opts or {}
  local lines, choices = TextBox.parse(bytes or "", opts.playerName, opts)
  local self = setmetatable({
    pages = paginate(lines), page = 1, shown = 0, done = false,
    choices = choices, cursor = 1, result = 0,
    top = opts.top, speed = opts.speed or 1,
    assets = opts.assets, scale = opts.assets and 0 or 8,
  }, TextBox)
  self.pageChars = self:countChars()
  return self
end

function TextBox:countChars()
  local n = 0
  for _, l in ipairs(self.pages[self.page] or {}) do
    for _, r in ipairs(l) do n = n + #r.text end
  end
  return n
end

function TextBox:hasChoice()
  return #self.choices >= 2 and self.page == #self.pages
end

-- input: table of wasPressed flags {a, b, left, right, up, down}
function TextBox:update(press)
  self.ticks = (self.ticks or 0) + 1
  -- MsgOpen: the window grows one step a frame before the text starts
  if (self.scale or 8) < 8 then self.scale = self.scale + 1 return end
  if self.done then return end
  if self.shown < self.pageChars then
    self.shown = self.shown + self.speed
    if press.a or press.b then self.shown = self.pageChars end
    return
  end
  if self:hasChoice() then
    if press.left or press.up then self.cursor = math.max(1, self.cursor - 1) end
    if press.right or press.down then self.cursor = math.min(#self.choices, self.cursor + 1) end
    if press.a then
      self.result = self.cursor - 1
      self.done = true
    elseif press.b then
      self.result = #self.choices - 1
      self.done = true
    end
    return
  end
  if press.a or press.b then
    if self.page < #self.pages then
      self.page = self.page + 1
      self.shown = 0
      self.pageChars = self:countChars()
    else
      self.done = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- The cartridge's message window (message.c), drawn into BG0 through
-- Ppu.lua: border tiles from sub_08056F88(0, 0) at tile $7B ($0600CF60),
-- DispMessageFrame with palette $F, the two text lines as 8x16 cells in
-- the canvas at tile $82 / $B6 ($0600D040, 26 cells a line), the window
-- growing and shrinking by sizeScale 0..8 (ChangeWindowSize: width 26,
-- height 4, x 1, y 12 -- or y 1 when the speaker is low on screen), and
-- the page cursor (tile $80) in the last cell.
-- ---------------------------------------------------------------------------
local MSG_BEGIN = { 0xF082, 0xF083, 0xF0B6, 0xF0B7 }
local BG0 = 0x02034CB0

function TextBox:cartDraw(assets)
  local Ppu = require("src.zelda.tmc.Ppu")
  local p = self.ppu
  if not p then
    p = Ppu.new(assets)
    p.transparent = true
    p.dispcnt = 0x0140
    p.bg[0].control = 0x1F0C
    p:loadPaletteGroup(12)
    p:borderTiles(0, 0, 0x0600CF60)
    self.ppu = p
  end
  local scale = math.max(1, math.min(8, self.scale or 8))
  local posY = self.top and 1 or 12
  local w = math.floor(scale * 52 / 16); if w % 2 == 1 then w = w + 1 end
  local h = math.floor(scale * 8 / 16); if h % 2 == 1 then h = h + 1 end
  local x0 = 13 + 1 - math.floor(w / 2)
  local y0 = 2 + posY - math.floor(h / 2)
  local waiting = self.shown >= self.pageChars and not self:hasChoice()
  local blink = waiting and math.floor((self.ticks or 0) / 16) % 2 == 0
  local key = table.concat({ scale, self.page, math.floor(self.shown), self.cursor, tostring(blink) }, ",")
  if key ~= self.lastKey then
    self.lastKey = key
    p:fill(BG0, 0x800, 0)
    local start = BG0 + 2 * (y0 * 32 + x0)
    p:messageFrame(start, w, h, 0xF07B)
    if w > 0 and h > 0 then
      local i = math.floor((4 - h) / 2)
      local buf = start + 2
      for _ = 1, h do
        buf = buf + 0x40
        local attr = MSG_BEGIN[i + 1]
        for k = 0, w - 1 do p:set16(buf + 2 * k, attr + 2 * k) end
        i = i + 1
      end
    end
    -- the canvas: two lines, 0xFF-filled, glyphs typed out to `shown`
    local ffi = require("ffi")
    local len = 2 * 26 * 64
    local canvas = ffi.new("uint8_t[?]", len)
    ffi.fill(canvas, len, 0xFF)
    local left = math.floor(self.shown)
    for li, line in ipairs(self.pages[self.page] or {}) do
      local chars = {}
      for _, run in ipairs(line) do
        local colour = run.color % 8
        if run.slot then
          -- a choice slot is variable n: $0F $00 / $0F $01 -- the bank-3
          -- marker glyph, glyph 1 on the chosen one (gUnk_020227E8)
          local on = self:hasChoice() and run == self.choices[self.cursor]
          if left > 0 then chars[#chars + 1] = { on and 0x301 or 0x300, colour } end
          left = left - #run.text
        else
          for k = 1, #run.text do
            if left <= 0 then break end
            chars[#chars + 1] = { run.text:byte(k), colour }
            left = left - 1
          end
        end
      end
      p:drawGlyphs(canvas, len, chars, (li - 1) * 0xD0, li * 0xD0, 0, 0, 0)
    end
    p:write(0x0600D040, ffi.string(canvas, len))
    if blink then
      p:set16(start + 2 * ((h + 1) * 32 - 2 + w), 0xF080)
    end
    p.bg[0].updated = true
  end
  return p:render()
end

function TextBox:draw(font, W, H)
  local g = love.graphics
  if self.assets and self.assets.manifest.gfxGroups then
    g.setColor(1, 1, 1, 1)
    g.draw(self:cartDraw(self.assets), 0, 0)
    return
  end
  local bh = 40
  local y0 = self.top and 6 or (H - bh - 6)
  g.setColor(0.06, 0.08, 0.2, 0.92)
  g.rectangle("fill", 8, y0, W - 16, bh, 4, 4)
  g.setColor(0.9, 0.85, 0.6, 1)
  g.setLineWidth(1)
  g.rectangle("line", 8.5, y0 + 0.5, W - 17, bh - 1, 4, 4)
  g.setFont(font)
  local left = self.shown
  local lh = 15
  for li, line in ipairs(self.pages[self.page] or {}) do
    local x = 15
    for _, run in ipairs(line) do
      local text = run.text
      if left < #text then text = text:sub(1, math.max(0, math.floor(left))) end
      left = left - #run.text
      local c = COLORS[run.color] or COLORS[0]
      g.setColor(c[1], c[2], c[3], 1)
      g.print(text, x, y0 + 5 + (li - 1) * lh)
      -- choice cursor
      if self:hasChoice() and self.shown >= self.pageChars and run == self.choices[self.cursor] then
        g.setColor(1, 0.9, 0.3, 1)
        g.print(">", x, y0 + 5 + (li - 1) * lh)
      end
      x = x + font:getWidth(run.text)
      if left <= 0 and self.shown < self.pageChars then break end
    end
  end
  if self.shown >= self.pageChars and not self:hasChoice() then
    if math.floor(love.timer and love.timer.getTime() * 3 or 0) % 2 == 0 then
      g.setColor(1, 1, 1, 1)
      g.polygon("fill", W - 20, y0 + bh - 9, W - 14, y0 + bh - 9, W - 17, y0 + bh - 5)
    end
  end
  g.setColor(1, 1, 1, 1)
end

local _ = band
return TextBox
