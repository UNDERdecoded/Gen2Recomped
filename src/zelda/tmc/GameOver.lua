-- The game-over task (src/gameOverTask.c, subtaskAuxCutscene.c
-- sub_08052010, gameUtils.c SetPopupState) through Ppu.lua.
--
-- Setup: DispReset (BG0 + OBJ, controls $1F0C / $1C01 / $1D02 / $1E03),
-- the pause backdrop setup (sub_080A4D34), palette group $A, colour 0
-- black, gfx group 4 (the popup frame into BG2's buffer and tiles, the
-- GAME OVER letters at OBJ tile $200), BG1 $1C01 and BG2 $1D05.
--
-- The eight letters are sprite $1FD frames 0-7 at x 48, 68, 88, 108, 137,
-- 156, 174, 192, palette 8, priority 2.  They wait 60 frames at y 80,
-- rise one pixel a frame to y 37, wait 60 more; then BG1 / BG2 come on with
-- the popup: message $10 (Save / Don't Save), then $11 (Continue / Quit),
-- drawn by ShowTextBox into BG1 (fill 6, colour 4, tiles at $06006000,
-- palette $D) at row 8, column 11, the choice marker being variable 1 or 2
-- ($0F $00 / $0F $01: bank 3 glyph 0 or 1).

local Ppu = require("src.zelda.tmc.Ppu")

local GameOver = {}
GameOver.__index = GameOver

local X = { 48, 68, 88, 108, 137, 156, 174, 192 }
local POPUP = { [0] = { col = 11, row = 8, text = 0x10 }, [1] = { col = 11, row = 8, text = 0x11 } }

function GameOver.new(field)
  local self = setmetatable({ field = field, state = "init", y = 80, wait = 60, timer = 60, choice = 0, fadeIn = 0 }, GameOver)
  local p = Ppu.new(field.assets)
  self.ppu = p
  p.dispcnt = 0x1140
  p.bg[0].control, p.bg[1].control, p.bg[2].control, p.bg[3].control = 0x1F0C, 0x1C01, 0x1D02, 0x1E03
  -- sub_080A4D34
  for _, g in ipairs({ 16, 23, 25, 27 }) do p:loadGfxGroup(g) end
  p:loadPaletteGroup(11); p:loadPaletteGroup(12); p:setColor(0, 0)
  p:loadPaletteGroup(0xB5)
  p:loadGfxGroup(0x58)
  p.bg[3].control = 0x1E0B; p.bg[3].updated = true
  p:loadPaletteGroup(0x0A)
  p:setColor(0, 0)
  p:loadGfxGroup(4)
  p:fill(0x06000000, 0x20, 0)
  p.bg[1].control = 0x1C01
  p.bg[2].control = 0x1D05
  p.bg[1].updated, p.bg[2].updated = true, true
  return self
end

-- SetPopupState(type, choice)
function GameOver:popup(kind, choice)
  local p = self.ppu
  p:fill(0x02021F30, 0x800, 0)
  local vars = { [1] = "\15\0", [2] = "\15\0", [3] = "\15\0", [4] = "\15\0" }
  vars[choice + 1] = "\15\1"
  local o = POPUP[kind]
  local font = { dest = 0x02021F30 + 2 * (o.col + o.row * 32), gfx_dest = 0x06006000, gfx_src = 0xD300,
                 width = 0xE0, centre = false, sm_border = false, draw_border = false, border_type = 0,
                 fill = 6, charColor = 4, spacing = 1, stylized = 0 }
  p:showTextBox(o.text, font, vars)
  p.bg[1].updated = true
  self.kind = kind
end

-- returns "continue", "quit" or nil
function GameOver:update(input)
  local f = self.field
  if self.fadeIn < 16 then self.fadeIn = self.fadeIn + 0.25 end
  if self.state == "init" then
    if self.wait > 0 then self.wait = self.wait - 1
    elseif self.y >= 38 then self.y = self.y - 1
    else
      self.timer = self.timer - 1
      if self.timer <= 0 then
        self.state = "popup"
        self.ppu.dispcnt = self.ppu.dispcnt + 0x600
        self.timer = 30
        self:popup(0, 0)
      end
    end
    return nil
  end
  if self.timer > 0 then self.timer = self.timer - 1 return nil end
  local c = self.choice
  if input.pressed("up") then c = 0 elseif input.pressed("down") then c = 1 end
  if input.pressed("a") then
    f:sound(0x6A) -- SFX_TEXTBOX_SELECT
    if self.kind == 0 then
      if c == 0 and f.game.opts.host and f.game.opts.host.requestSave then f.game.opts.host:requestSave() end
      self.choice = 0
      self.timer = 30
      self:popup(1, 0)
      return nil
    end
    return c == 0 and "continue" or "quit"
  end
  if c ~= self.choice then
    self.choice = c
    self:popup(self.kind, c)
    f:sound(0x69) -- SFX_TEXTBOX_CHOICE
  end
  return nil
end

function GameOver:draw()
  local p = self.ppu
  p:flush()
  for i = 0, 7 do
    p:drawDirect(0x1FD, i, { x = X[i + 1], y = self.y, _4 = 0, _6 = 0, _8 = 0x8600 })
  end
  -- the field has already faded to black; the letters fade in over it
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, Ppu.W, Ppu.H)
  love.graphics.setColor(1, 1, 1, math.min(1, self.fadeIn / 16))
  love.graphics.draw(p:render(), 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
end

return GameOver
