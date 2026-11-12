-- Pause screens 8-11 (src/menu/pauseMenu.c), drawn through Menu.lua's Ppu:
--
--  8  SWORD TECHNIQUES (PauseMenu_Screen_8): eight scrolls; left / right
--     move the cursor (sprite $1FC frames 8 / 9, x = $1A + $1B * n); a
--     learnt scroll shows its icon (frame 10), the big scroll (its own
--     frame, palette unk1) and the description gUnk_08128D70[n].textIndex
--     with the font gUnk_08129004 into BG1 (sub_080A7040).
--  9  SLEEP (PauseMenu_Screen_9): popup type 2 (Yes / No, left / right);
--     yes fades to white over $20 and back (the cartridge's sleep mode).
-- 10  SAVE from QUEST STATUS, 11 SAVE from ITEMS (PauseMenu_Screen_10):
--     popup type 0 (up / down); yes shows dialog 8 ("Saving...") while
--     HandleSave runs -- here the runtime's save -- then back to screen 2
--     (from 10) or 1 (from 11).
-- Popups are SetPopupState (gameUtils.c) into BG1, dialogs CreateDialogBox
-- (fileselect.c) into BG0.

local bit = require("bit")
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local SaveMenu = {}

local SPRITE = 0x1FC                    -- DRAW_DIRECT_SPRITE_INDEX + 1
local SCROLLS = 0x08128D70              -- gUnk_08128D70 {item, pal, frame, _, _, _, text}
local KEYS8, LAYOUT8 = 0x08128DB8, 0x08128DBC
local FONT8 = 0x08129004
local SFX_CHOICE, SFX_SELECT, SFX_CANCEL = 0x69, 0x6A, 0x6C

local function readLayout(t, a)
  local l = {}
  for i = 1, 9 do l[i] = t.u8(a + i - 1) end
  l.elements = {}
  local p = a + 9
  while t.u8(p) ~= 0xFF and #l.elements < 8 do
    l.elements[#l.elements + 1] = { t.u8(p), t.u8(p + 1) }
    p = p + 2
  end
  return l
end

-- SetPopupState(type, choice) -- sPopupOptions: {dest_off[language], _8,
-- right_align, text}; USA language 1
local POPUP = { [0] = { off = 11, row = 8, text = 16 }, [1] = { off = 11, row = 8, text = 17 },
                [2] = { off = 15, row = 5, text = 13 } }
function SaveMenu.popup(m, kind, choice)
  local p = m.ppu
  p:fill(0x02021F30, 0x800, 0)
  local vars = { [1] = "\15\0", [2] = "\15\0", [3] = "\15\0", [4] = "\15\0" }
  vars[choice + 1] = "\15\1"
  local o = POPUP[kind]
  local font = { dest = 0x02021F30 + 2 * (o.off + o.row * 32), gfx_dest = 0x06006000, gfx_src = 0xD300,
                 width = 0xE0, centre = kind == 2, sm_border = false, draw_border = false, border_type = 0,
                 fill = 6, charColor = 4, spacing = 1, stylized = 0 }
  p:showTextBox(o.text, font, vars)
  p.bg[1].updated = true
end

-- CreateDialogBox(n) (fileselect.c)
function SaveMenu.dialog(m, n)
  local p = m.ppu
  p:fill(0x02034CB0, 0x800, 0)
  local t = p:table("dialogBox")
  if t then
    local e = 0x080FC85C + 6 * n
    local font = p:font("dialogBox", 0x080FC844)
    if font then
      font.gfx_src = bor(font.gfx_src, lshift(t.u16(e), 12))
      p:showTextBox(t.u16(e + 2), font)
    end
    local sfx = t.u16(e + 4)
    if sfx ~= 0 then m.field:sound(sfx) end
  end
  p.bg[0].updated = true
end

local function back(m, to)
  m.field:sound(SFX_CANCEL)
  m.nextScreen, m.state = to, 3
end

function SaveMenu.init(m, n)
  local p, t = m.ppu, m.data
  m.sv = { choice = 0, menuType = 1 }
  m.keys = nil
  if n == 8 then
    -- sub_080A6108
    m.keys = { t.u8(KEYS8), t.u8(KEYS8 + 1), t.u8(KEYS8 + 2), t.u8(KEYS8 + 3) }
    m.ui:layout(readLayout(t, LAYOUT8))
    m.sv.scroll = m.cursors[8] or 0
    m.sv.shownText = nil
  elseif n == 9 then
    m.ui:layout({ 0xFF, 0xD8, 0, 0xFF, 0xD8, 0, 0xFF, 0xD8, 0, elements = {} })
    SaveMenu.popup(m, 2, 0)
    p.bg[1].y = 0
  else
    m.ui:layout({ 0xFF, 0xD8, 0, 0xFF, 0xD8, 0, 0xFF, 0xD8, 0, elements = {} })
    SaveMenu.popup(m, 0, 0)
  end
end

local function scrollEntry(m, i)
  local t = m.data
  local a = SCROLLS + 8 * i
  return { item = t.u8(a), pal = t.u8(a + 1), frame = t.u8(a + 2), text = t.u16(a + 6) }
end

-- sub_080A7040: the scroll's description into BG1
local function describe(m, i)
  local sv, p = m.sv, m.ppu
  if sv.shownText == i then return end
  sv.shownText = i
  p:fill(0x02021F30 + 0x200, 0x600, 0)
  local e = scrollEntry(m, i)
  if m.field:inventory(e.item) ~= 0 then
    local font = p:font("pauseData2", FONT8)
    if font then p:showTextBox(e.text, font) end
  end
  p.bg[1].y = 3
  p.bg[1].updated = true
end

-- returns true when it handled the frame
function SaveMenu.update(m, input)
  local n, sv, f = m.screen, m.sv, m.field
  if not sv then return false end
  if n == 8 then
    local c = sv.scroll
    if input.pressed("left") then c = c - 1 elseif input.pressed("right") then c = c + 1 end
    c = (c + 8) % 8
    if c ~= sv.scroll then sv.scroll = c; m.cursors[8] = c; f:sound(SFX_CHOICE) end
    return true
  end
  if sv.menuType == 2 then
    if n == 9 then
      -- sub_080A5BB8: the white fade, then back
      sv.timer = sv.timer - 1
      if sv.timer <= 0 then sv.white = nil; m.state, m.nextScreen = 3, 2 end
      return true
    end
    -- sub_080A5A54: HandleSave (the runtime's save), then menu type 3
    sv.timer = sv.timer - 1
    if sv.timer == 20 then
      local host = f.game.opts and f.game.opts.host
      if host and host.requestSave then pcall(host.requestSave, host) end
      sv.saved = true
    end
    if sv.timer <= 0 then sv.menuType = 3; sv.timer = 0 end
    return true
  elseif sv.menuType == 3 then
    -- sub_080A5A90: back to the page it came from
    return back(m, n == 10 and 2 or 1) or true
  end
  local c, pick = sv.choice, false
  if n == 9 then
    if input.pressed("left") then c = 0 elseif input.pressed("right") then c = 1
    elseif input.pressed("b") then if sv.choice ~= 0 then pick = true else c = 1 end
    elseif input.pressed("a") then pick = true end
    if c ~= sv.choice then sv.choice = c; SaveMenu.popup(m, 2, c); f:sound(SFX_CHOICE) end
    if pick then
      if c == 0 then
        sv.menuType, sv.timer, sv.white = 2, 60, 0
      else
        back(m, 2)
      end
    end
    return true
  end
  -- screens 10 / 11 (sub_080A59C8)
  if input.pressed("up") then c = 0 elseif input.pressed("down") then c = 1
  elseif input.pressed("b") then if sv.choice == 0 then c = 1 else pick = true end
  elseif input.pressed("a") then pick = true end
  if pick then
    if c == 0 then
      SaveMenu.dialog(m, 8)
      f:sound(SFX_SELECT)
      sv.menuType, sv.timer = 2, 40
    else
      sv.menuType = 3
      f:sound(SFX_CANCEL)
    end
  elseif c ~= sv.choice then
    sv.choice = c
    SaveMenu.popup(m, 0, c)
    f:sound(SFX_CHOICE)
  end
  return true
end

function SaveMenu.draw(m)
  local n, p, sv = m.screen, m.ppu, m.sv
  if not sv then return end
  if n == 8 then
    -- sub_080A617C
    local c = sv.scroll
    local tick = band(m.ticks or 0, 0x20) ~= 0
    p:drawDirect(SPRITE, tick and 8 or 9, { x = c * 0x1B + 0x1A, y = 0x2F, _4 = 0, _6 = 0, _8 = 0xC00 })
    local e = scrollEntry(m, c)
    if m.field:inventory(e.item) ~= 0 then
      p:drawDirect(SPRITE, 0xB, { x = 0xCC, y = 0x88, _4 = 0, _6 = 0, _8 = 0xC00 })
      p:drawDirect(SPRITE, e.frame, { x = 0x30, y = 0x6C, _4 = 0, _6 = 0, _8 = bor(lshift(e.pal, 12), 0xD80) })
      p:drawDirect(SPRITE, 0xC, { x = 0x78, y = 0x68, _4 = 0, _6 = 0, _8 = bor(lshift(e.pal, 12), 0xC00) })
    end
    for i = 0, 7 do
      local s = scrollEntry(m, i)
      if m.field:inventory(s.item) ~= 0 then
        p:drawDirect(SPRITE, 10, { x = 0x18 + 0x1B * i, y = 0x2F, _4 = 0, _6 = 0, _8 = bor(lshift(s.pal, 12), 0xC00) })
      end
    end
    describe(m, c)
  elseif n == 9 and sv.white then
    sv.white = math.min(16, sv.white + 1)
  end
end

-- the white sleep fade over the picture (SetFade(FADE_IN_OUT |
-- FADE_BLACK_WHITE | FADE_INSTANT, $20))
function SaveMenu.overlay(m)
  local sv = m.sv
  if m.screen == 9 and sv and sv.white then
    local a = sv.timer > 30 and (60 - sv.timer) / 30 or sv.timer / 30
    love.graphics.setColor(1, 1, 1, math.max(0, math.min(1, a)))
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return SaveMenu
