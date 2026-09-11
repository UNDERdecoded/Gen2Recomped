-- The cursor/border/geometry constants every menu used to redeclare
-- locally, centralized so field.theme can restyle all of them at once.
-- Defaults are the current literals; the merge never runs without a mod,
-- so a vanilla boot draws byte-identically.

local Font = require("src.render.Font")
local Merge = require("src.mods.Merge")
local Renderer = require("src.render.Renderer")

local Theme = {
  cursor = 0xED,        -- the filled arrow (charmap.asm $ED)
  cursorHollow = 0xEC,  -- the unfilled arrow left on chosen rows
  moreArrow = 0xEE,     -- more-below marker (charmap.asm $EE)
  tile = 8,
  cols = Renderer.WIDTH / 8,
  rows = Renderer.HEIGHT / 8,
  textBox = { tx = 0, ty = 12, tw = 20, th = 6, maxCols = 18 },
  -- InitYesNoTextBoxParameters / AskName: hlcoord 14, 7 (YES_NO_MENU 4x3)
  choiceBox = { tx = 14, ty = 7, tw = 6, th = 5 },
}

-- THE SURFACE THIS DATASET'S SCREEN FURNITURE NEEDS.
--
-- Every layout in the port is written in Game Boy coordinates and the UI
-- canvas is 160x144 to match.  Emerald's dialogue box is twenty-eight tiles
-- wide -- 224 pixels -- and simply does not fit on that canvas: it was drawn
-- off the right-hand edge and blitted at the canvas's own scale rather than
-- the world's, so it came out both larger than the map behind it and cut off.
--
-- The answer lives here rather than in the box, because more than one state
-- has to give the SAME answer.  The fit scale is derived from the surface, so
-- if the box asks for 240x160 and the field does not, the whole screen steps
-- down a scale the moment anybody speaks and back up when they stop.
--
-- A theme whose box fits the classic screen gets the classic screen, so Gen 1
-- and Gen 2 are byte-identical.
function Theme.uiSize()
  local Renderer = require("src.render.Renderer")
  local box = Theme.textBox or {}
  local needW = ((box.tx or 0) + (box.tw or 20)) * 8
  local needH = ((box.ty or 12) + (box.th or 6)) * 8
  if needW <= Renderer.WIDTH and needH <= Renderer.HEIGHT then
    return Renderer.WIDTH, Renderer.HEIGHT
  end
  -- a surface is a whole screen, not a bounding box
  return 240, 160
end

function Theme.load(data)
  -- Font.load rebuilds its border table, so pick it up here rather than at
  -- require time
  Theme.border = Font.BORDER
  -- ...and the cursor, which is NOT the same code in every generation.  $ED
  -- is the filled arrow in Gen 1's charmap and a lower-case 'y' in Gen 3's,
  -- so a font that knows where its own arrows are says so and this takes
  -- them; one that does not keeps the Gen 1 codes exactly as before.
  local symbols = data and data.font and data.font.symbols
  if type(symbols) == "table" then
    for _, key in ipairs({ "cursor", "cursorHollow", "moreArrow" }) do
      if type(symbols[key]) == "number" then Theme[key] = symbols[key] end
    end
  end
  local t = data and data.field and data.field.theme
  if t then
    Merge.deepMerge(Theme, t)
    Font.BORDER = Theme.border
  end
end

return Theme
