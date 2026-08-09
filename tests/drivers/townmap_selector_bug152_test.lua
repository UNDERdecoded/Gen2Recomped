-- Driver: regression coverage for #152 "'Selector' on the world map is off and
-- character location is not shown".
--
-- pret/pokered engine/menus/town_map.asm DisplayTownMap draws the Kanto map
-- with a blinking box cursor CENTERED on the currently selected location plus a
-- separate blinking "you are here" marker at the player's current map location.
-- Two independent defects lived in src/ui/TownMap.lua's grid+background path
-- (the primary path when the extracted Kanto art is present):
--
--   DEFECT A (selector off): the 16x16 hollow cursor frame was drawn with its
--   top-left AT the 8x8 cell's top-left (markerXY), so the frame's center
--   landed +4,+4 off the cell -- the town square sat in the frame's top-left
--   quadrant instead of being enclosed.  Fix centers the frame (-4,-4).
--
--   DEFECT B (character location not shown): the player marker was painted with
--   setColor(0.75,0.1,0.1) red.  The TOWN MAP composites through the SGB
--   shade-remap shader (PaletteFX.shader), which keys ONLY on the red channel;
--   red 0.75 falls in the c1 bucket = TOWNMAP {165,214,255}, the exact
--   light-blue used for water and the town-square fill, so the marker was
--   painted but recolored invisible.  Fix paints it red=0 -> c3 (dark dot).
--
-- This driver opens the grid TOWN MAP outdoors at PALLET TOWN, moves the cursor
-- off the player's town to VIRIDIAN CITY (so the you-are-here marker and the
-- selection cursor must BOTH be visible), and asserts -- at native resolution,
-- after replicating the Renderer's TOWNMAP shade-remap pass -- that the player
-- marker is a visible dark dot (DEFECT B) and the cursor frame is centered on
-- the selected cell (DEFECT A).  Fails on the current build, passes once fixed.
--
-- Run:
--   SHOT_DIR=/tmp/bug152 POKEPORT_IDENTITY=bug152 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/townmap_selector_bug152_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local PaletteFX = require("src.render.PaletteFX")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- The defect lives in the SGB ('gbc') mode shade-remap; pin it deterministic.
  game.save.options = game.save.options or {}
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")

  game.save.player = game.save.player or {}
  game.save.player.name = "bryan"

  -- Outdoor map so the player's map resolves to a town-map location (byMap).
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(5)

  Screens.push(game, "TownMap")
  U.wait(6)
  local top = game.stack:top()

  -- Functional preconditions: the grid path with extracted art, and the
  -- character's location known (playerLoc non-nil) -- otherwise the two draw
  -- defects would not even be on the code path we mean to test.
  assert(top and top.mode == "grid",
    "town map must be in grid mode (extracted art), got " .. tostring(top and top.mode))
  assert(top.bg ~= nil and top.bg.cursor ~= nil,
    "extracted Kanto background + cursor asset must be present for this test")
  assert(top.playerLoc ~= nil and top.playerLoc.name == "PALLET TOWN",
    "character location must resolve to PALLET TOWN, got "
    .. tostring(top.playerLoc and top.playerLoc.name))

  -- Human-viewable before/after frame: cursor still on the player's own town.
  top.blink = 0
  U.shot(game, DIR .. "/townmap_bug152_pallet.png")
  U.wait(4)

  -- Move the cursor OFF the player's town up to VIRIDIAN CITY, so the
  -- you-are-here marker (PALLET) and the selection cursor (VIRIDIAN) occupy
  -- different cells and BOTH must render (matches the reporter's should2).
  local guard = 0
  while top.locs[top.sel].name ~= "VIRIDIAN CITY" and guard < 8 do
    U.tap(game, "up"); U.wait(3); guard = guard + 1
  end
  assert(top.locs[top.sel].name == "VIRIDIAN CITY",
    "up must snap the cursor to VIRIDIAN CITY, landed on "
    .. tostring(top.locs[top.sel].name))
  assert(top.locs[top.sel] ~= top.playerLoc,
    "cursor must be on a DIFFERENT cell than the you-are-here marker")

  top.blink = 0
  U.shot(game, DIR .. "/townmap_bug152_viridian.png")
  U.wait(4)

  -- ---- deterministic native-resolution pixel gate ----
  -- TownMap:draw() emits raw DMG shades; the Renderer composites the whole
  -- screen through PaletteFX.shader() with the TOWNMAP SGB palette (keyed on
  -- the RED channel only).  Replicate that here at native 160x144 so the pixel
  -- checks are scale-independent -- the same offscreen-colorize technique as
  -- battle_hpbar_gbc_bug229_test.lua.
  if not (love and love.graphics and love.graphics.newCanvas and PaletteFX.shader()) then
    error("#152 driver: no shader/canvas support available to verify colorized output")
  end

  top.blink = 0 -- marker shows while blink<20, cursor while blink%16<10
  local raw = love.graphics.newCanvas(160, 144)
  love.graphics.setCanvas(raw)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  top:draw()
  love.graphics.setCanvas()

  local shader = PaletteFX.shader()
  local colors = PaletteFX.pal(game.data, "TOWNMAP")
  assert(colors, "TOWNMAP palette must resolve")
  local shaded = love.graphics.newCanvas(160, 144)
  love.graphics.setCanvas(shaded)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setShader(shader)
  PaletteFX.sendColors(shader, colors)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(raw)
  love.graphics.setShader()
  love.graphics.setCanvas()

  local id = shaded:newImageData()
  do -- save the colorized native frame for human viewing
    local d = id:encode("png")
    local f = io.open(DIR .. "/townmap_bug152_viridian_native.png", "wb")
    if f then f:write(d:getString()); f:close() end
  end

  local function sumAt(x, y)
    local r, g, b = id:getPixel(x, y)
    return r + g + b, r, g, b
  end

  -- markerXY(loc) = (loc.x*8+16, loc.y*8+8) = the 8x8 cell top-left.
  -- PALLET (x2,y11) -> (32,96); the you-are-here dot fills +2,+2 4x4, center ~ (35,99).
  local ms, mr, mg, mb = sumAt(35, 99)
  -- VIRIDIAN (x2,y8) -> (32,72).  Post-fix the centered 16x16 frame's top border
  -- sits ~4px ABOVE the cell top (row ~68) and its left border ~4px LEFT (col ~28).
  local ts = select(1, sumAt(32, 68))
  local ls = select(1, sumAt(28, 78))
  U.log(string.format("marker(35,99) rgb=%.2f/%.2f/%.2f sum=%.2f", mr, mg, mb, ms))
  U.log(string.format("cursor top(32,68) sum=%.2f  left(28,78) sum=%.2f", ts, ls))

  -- DEFECT B: the "you are here" marker must be a VISIBLE dark dot, not the
  -- map-fill light-blue (sum 2.49) the red-channel shade-remap folded it into.
  assert(ms < 0.6, string.format(
    "#152 DEFECT B: player-location marker invisible -- PALLET cell reads sum=%.2f "
    .. "(map-fill blue); expected a dark you-are-here dot (sum<0.6)", ms))
  -- DEFECT A: the 16x16 cursor frame must be CENTERED on the selected cell, so a
  -- dark border pixel exists ~4px above and ~4px left of the VIRIDIAN cell top-left.
  assert(ts < 0.6, string.format(
    "#152 DEFECT A: cursor frame not centered -- no dark top border above VIRIDIAN "
    .. "cell (sum=%.2f, expected <0.6)", ts))
  assert(ls < 0.6, string.format(
    "#152 DEFECT A: cursor frame not centered -- no dark left border of VIRIDIAN "
    .. "cell (sum=%.2f, expected <0.6)", ls))

  U.log("RESULT bug152 PASS")
  U.wait(2)
end
