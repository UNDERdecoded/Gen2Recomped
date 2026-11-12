-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DIALOGUE (round 4b): the cartridge's own messages, font and window
-- (RomMap.text). Pure logic: parse a message into tokens and run a message
-- box the way the SNES renderer the GBA kept does it (zelda3
-- RenderText_Draw_MessageCharacters): letters at the current speed, line
-- commands, scroll, wait, wait-for-key, end. The renderer draws `box.glyphs`.
--
-- Not ported: the item chooser (Item draws its text but picks nothing),
-- the scroll animation (lines move up at once), sound effects, the
-- cartridge's name entry (the name is the save's).
-- Round 22: the choice cursors (RenderText_Draw_Choose2LowOr3 / Choose2HiOr3
-- / Choose3 / Choose1Or2, commands 0x68 / 0x6F / 0x71 / 0x72): the box waits
-- on the command; up / down load the cursor message (1-2 / 11-12 / 6-8 /
-- 9-10: the arrow and blanks on the option lines, ending on the same
-- command) over the text; a confirm closes the box with `box.choice`
-- (choice_in_multiselect_box, 0 = the first option).

local bit = require("bit")
local band = bit.band

local T = {}

-- r22: the choice commands -> { first cursor message, options, wraps }
local CHOOSE = { [0x68] = { 1, 2 }, [0x6F] = { 11, 2 }, [0x71] = { 6, 3, true }, [0x72] = { 9, 2 } }
T.CHOOSE = CHOOSE
local CMD = { name = 0x6A, window = 0x6B, number = 0x6C, position = 0x6D,
              scroll = 0x73, line1 = 0x74, line2 = 0x75, line3 = 0x76,
              color = 0x77, wait = 0x78, sound = 0x79, speed = 0x7A,
              clear = 0x7D, waitkey = 0x7E, finish = 0x7F }
T.CMD = CMD

-- message index as the cartridge stores it (0x0812740C: SNES index > 15 is
-- stored 3 lower)
function T.bmgIndex(snesIndex)
  if snesIndex > 15 then return snesIndex - 3 end
  return snesIndex
end

-- the symbol glyphs the {kind 1} command names: the GBA font's button row
-- (round 18, read from the font: tile 0x0B R, 0x0C B, 0x0D L, 0x0E A; 0x0F
-- is blank) for the message codes 0x5B (R: lift / open / talk / dash), 0x5C
-- (B: the sword), 0x5D (L: the map), 0x5E (A: the item); SELECT + L + R
-- leaves sleep mode (message 394)
-- r22: 0x44 is the choice cursor, the font's right-pointing triangle (tile
-- 0x00, by its shape; it drew as "D" from the font's first half before)
local BUTTON = { [0x5B] = 0x0B, [0x5C] = 0x0C, [0x5D] = 0x0D, [0x5E] = 0x0E, [0x44] = 0x00 }

-- tokens of message n (BMG index)
function T.parse(data, n)
  local ui = data.ui
  local off = ui.textOffsets[n + 1]
  assert(off, "no message " .. tostring(n))
  local s = data.text
  local p = off + 1
  local out = {}
  for _ = 1, 4000 do
    local c = s:byte(p)
    if not c or c == 0 then break end
    if c == 0x1A then
      local len = s:byte(p + 1)
      local kind, code = s:byte(p + 2), s:byte(p + 4)
      local args = {}
      for k = p + 5, p + len - 1 do args[#args + 1] = s:byte(k) end
      if kind == 1 then
        out[#out + 1] = { k = "ch", c = BUTTON[code] or code }
      else
        out[#out + 1] = { k = "cmd", code = code, arg = args[1] or 0 }
      end
      p = p + math.max(len, 2)
    elseif c == 0x0A then
      out[#out + 1] = { k = "nl" }
      p = p + 1
    else
      -- English: codes <= 0x7F are drawn from the font's second half
      out[#out + 1] = { k = "ch", c = (c <= 0x7F) and (c + 0x100) or c }
      p = p + 1
    end
  end
  return out
end

-- plain text of a message (tests, logs)
function T.plain(data, n, name)
  local t = {}
  for _, tok in ipairs(T.parse(data, n)) do
    if tok.k == "ch" then
      t[#t + 1] = tok.c >= 0x100 and string.char(tok.c - 0x100) or "?"
    elseif tok.k == "nl" then t[#t + 1] = "\n"
    elseif tok.code == CMD.name then t[#t + 1] = name or "Link"
    end
  end
  return table.concat(t)
end

local Box = {}
Box.__index = Box
T.Box = Box

-- opts: name (player name), linkScreenY (picks the window as 0x08129C58)
function T.open(data, n, opts)
  opts = opts or {}
  local self = setmetatable({ data = data, n = n, toks = T.parse(data, n), i = 1,
                              glyphs = {}, line = 0, x = 0, pendingNl = false,
                              speed = 0, delay = 0, wait = 0, waitKey = false,
                              done = false, closing = false, border = true,
                              version = 0 }, Box)
  self.pos = ((opts.linkScreenY or 0) > 0x5B) and 0 or 1
  self.name = opts.name or "Link"
  return self
end

local function glyphWidth(data, c)
  return data.ui.textWidths[c + 1] or 6
end

function Box:put(c)
  if self.pendingNl then
    self.pendingNl = false
    self.line = math.min(self.line + 1, 2)
    self.x = 0
  end
  -- r22: a glyph overwrites the columns it covers (the VWF renderer
  -- masks them; the cursor messages blank the old arrow with spaces)
  local w = glyphWidth(self.data, c)
  local n = #self.glyphs
  if n > 0 then
    local keep, cut = {}, false
    for _, g in ipairs(self.glyphs) do
      if g.line == self.line and g.x >= self.x and g.x < self.x + w then cut = true else keep[#keep + 1] = g end
    end
    if cut then self.glyphs = keep end
  end
  self.glyphs[#self.glyphs + 1] = { line = self.line, x = self.x, c = c }
  self.x = self.x + w
  self.version = self.version + 1
end

function Box:scroll()
  local keep = {}
  for _, g in ipairs(self.glyphs) do
    if g.line > 0 then g.line = g.line - 1; keep[#keep + 1] = g end
  end
  self.glyphs = keep
  self.line, self.x = 2, 0
  self.version = self.version + 1
end

-- one frame. confirm = A or B pressed this frame; up / down (r22) move a
-- choice cursor
function Box:update(confirm, up, down)
  if self.done then return end
  if self.waitKey then
    if confirm then
      self.waitKey = false
      self.cd2 = 28   -- text_wait_countdown2 (RenderText_Draw_PauseForInput)
      if self.closing then self.done = true end
    end
    return
  end
  -- r22: waiting on a choice command
  local ch = self.choosing
  if ch then
    if (self.cd2 or 0) > 0 then self.cd2 = self.cd2 - 1 return end
    if confirm then
      self.choosing, self.done = nil, true
      return
    end
    if up or down then
      local c = self.choice or 0
      if ch[3] then
        if up then c = (c == 0) and ch[2] - 1 or c - 1 else c = (c == ch[2] - 1) and 0 or c + 1 end
      else
        c = up and 0 or 1
      end
      if c == (self.choice or 0) and not ch[3] then return end
      self.choice = c
      self.choiceMoves = (self.choiceMoves or 0) + 1
      -- Text_LoadCharacterBuffer + Text_InitVwfState: the cursor message
      self.choosing = nil
      self.toks, self.i = T.parse(self.data, T.bmgIndex(ch[1] + c)), 1
      self.pendingNl = false
    else
      return
    end
  end
  if self.wait > 0 then
    self.wait = self.wait - 1
    if confirm then self.wait = 0 end
    return
  end
  local letters = 0
  while not self.done do
    local tok = self.toks[self.i]
    if not tok then
      self.closing, self.waitKey = true, true
      return
    end
    if tok.k == "ch" then
      if self.speed >= 2 and self.delay > 0 then
        self.delay = self.delay - 1
        return
      end
      self:put(tok.c)
      self.i = self.i + 1
      self.delay = math.max(0, self.speed - 1)
      letters = letters + 1
      if self.speed ~= 0 then return end
    elseif tok.k == "nl" then
      self.pendingNl = true
      self.i = self.i + 1
    else
      local c, a = tok.code, tok.arg
      self.i = self.i + 1
      if c == CMD.line1 or c == CMD.line2 or c == CMD.line3 then
        self.line, self.x, self.pendingNl = c - CMD.line1, 0, false
      elseif c == CMD.scroll then
        self.pendingNl = false
        self:scroll()
      elseif c == CMD.name then
        for k = 1, #self.name do self:put(self.name:byte(k) + 0x100) end
      elseif c == CMD.window then
        self.border = (a ~= 2)
      elseif c == CMD.position then
        self.pos = (a == 0) and 0 or 1
      elseif c == CMD.speed then
        self.speed = a
      elseif c == CMD.wait then
        local w = self.data.ui.textWaits[band(a, 15) + 1] or 31
        self.wait = w - 1
        return
      elseif c == CMD.waitkey then
        self.waitKey = true
        return
      elseif c == CMD.finish then
        self.closing, self.waitKey = true, true
        return
      elseif CHOOSE[c] then
        -- r22: stay on the command (the read position does not move)
        self.i = self.i - 1
        self.choosing = CHOOSE[c]
        self.choice = self.choice or 0
        return
      elseif c == CMD.clear then
        self.glyphs, self.line, self.x = {}, 0, 0
        self.version = self.version + 1
      end
    end
  end
end

-- the window: { x, y } on screen, 24 x 8 tiles, as 0x081290B4 places it
-- (map byte offset -> row/column; the HUD layer scrolls 8 px left)
function Box:window()
  local off = self.data.ui.textWindowPos[self.pos + 1]
  local w = band(off, 0x7FF) / 2
  local col, row = w % 32, math.floor(w / 32)
  return col * 8 - 8, row * 8
end

-- the 24 x 8 border words (RenderText_DrawBorderRow: top, 6 middle, bottom)
function Box:borderWords()
  local b = self.data.ui.textBorder
  local words = {}
  for row = 0, 7 do
    local k = (row == 0) and 0 or ((row == 7) and 6 or 3)
    for col = 0, 23 do
      local i = (col == 0) and 1 or ((col == 23) and 3 or 2)
      words[row * 24 + col + 1] = b[k + i]
    end
  end
  return words
end

-- 168 x 48 colour indices (0 = clear, else 16 + pixel: palette 1) of the text
function T.pixels(data, glyphs)
  local font = data.font
  local W, H = 168, 48
  local out = {}
  for _, g in ipairs(glyphs) do
    local c = g.c
    local tile = math.floor(c / 16) * 32 + (c % 16)
    for half = 0, 1 do
      local o = (tile + half * 16) * 32
      for y = 0, 7 do
        local py = g.line * 16 + half * 8 + y
        for xb = 0, 3 do
          local b = font:byte(o + y * 4 + xb + 1) or 0
          for nib = 0, 1 do
            local v = (nib == 0) and band(b, 15) or bit.rshift(b, 4)
            local px = g.x + xb * 2 + nib
            if v ~= 0 and px < W and py < H then out[py * W + px] = 16 + v end
          end
        end
      end
    end
  end
  return out, W, H
end

return T
