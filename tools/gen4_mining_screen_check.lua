-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that where you tap is the cell the cartridge would have dug,
-- for every pixel of the bottom screen; that the dirt quads, the button rects and
-- the crack meter are the cartridge's numbers; and that the treasure-to-bag-item
-- join resolves for all forty-nine.
--
-- THE TRAP THIS FILE EXISTS TO PIN DOWN: a screen is the one thing here that
-- cannot be play-tested from a terminal, so the temptation is to check the
-- constants and call it done. Constants were exactly what pass 134's first check
-- asserted while the shipped function did something else. So section 2 sweeps
-- ALL 49,152 pixels of the 256x192 screen through `Gen4MiningScreen.cellAt` --
-- the function `touchpressed` actually calls -- and compares each answer against
-- the cartridge's own arithmetic computed independently.
--
-- Usage: texlua tools/gen4_mining_screen_check.lua [<dataset dir>]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local dir = (arg[1] or "G:/Gen2Recomped/platinum/data/generated"):gsub("[/\\]*$", "") .. "/"
local Mining = require("src.import.Gen4Mining")
local Screen = require("src.ui.Gen4MiningScreen")

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local L = Screen.LAYOUT
local W, H = 256, 192

-- ---------------------------------------------------------------------------
section("1. the layout, against the cartridge's own numbers")
-- ---------------------------------------------------------------------------
-- TILE_WIDTH_PIXELS * 2 is a mining cell; the grid starts at 2 cells down
-- because Mining_RemoveDirt subtracts 2 after dividing.
ok(L.CELL == 16, "a mining cell is 16px, layout says %d", L.CELL)
ok(L.GRID_Y == 32, "the grid starts 32px down, layout says %d", L.GRID_Y)
ok(L.GRID_X == 0, "the grid starts at x 0, layout says %d", L.GRID_X)
-- `touchX >= MINING_GAME_WIDTH * 2 * TILE_WIDTH_PIXELS` is the sidebar test, and
-- it has to be the grid's right edge or a column of cells is unreachable.
ok(L.SIDEBAR_X == Mining.GRID_WIDTH * 2 * 8,
   "the sidebar starts at %d but the grid's right edge is %d",
   L.SIDEBAR_X, Mining.GRID_WIDTH * 2 * 8)
ok(L.GRID_Y + Mining.GRID_HEIGHT * L.CELL == H,
   "the grid ends at %d, not at the screen's %d",
   L.GRID_Y + Mining.GRID_HEIGHT * L.CELL, H)
-- sHammerButtonRectangle { 26, 6, 32, 14 }, sPickaxeButtonRectangle { 26, 15, 32, 23 }
ok(L.HAMMER.x == 26 * 8 and L.HAMMER.y == 6 * 8
   and L.HAMMER.w == 6 * 8 and L.HAMMER.h == 8 * 8,
   "the hammer button is %d,%d %dx%d; tiles 26,6..32,14 give 208,48 48x64",
   L.HAMMER.x, L.HAMMER.y, L.HAMMER.w, L.HAMMER.h)
ok(L.PICKAXE.x == 26 * 8 and L.PICKAXE.y == 15 * 8
   and L.PICKAXE.w == 6 * 8 and L.PICKAXE.h == 8 * 8,
   "the pickaxe button is %d,%d %dx%d; tiles 26,15..32,23 give 208,120 48x64",
   L.PICKAXE.x, L.PICKAXE.y, L.PICKAXE.w, L.PICKAXE.h)
-- the two must not overlap, or one tool can never be chosen
ok(L.HAMMER.y + L.HAMMER.h <= L.PICKAXE.y,
   "the hammer and pickaxe buttons overlap")

section("2. every pixel of the screen lands where the cartridge would put it")
-- Mining_RemoveDirt: x = touchX / 16, y = touchY / 16 - 2, then a bounds test.
-- Its caller gates on touchX < 208 and touchY >= 32 first.
local swept, disagreed, firstBad = 0, 0, nil
local inGrid, inSidebar, inCrack = 0, 0, 0
for py = 0, H - 1 do
  for px = 0, W - 1 do
    swept = swept + 1
    local gotX, why = Screen.cellAt(px, py)
    local gotY = select(2, Screen.cellAt(px, py))
    local wantX, wantY
    if px < Mining.GRID_WIDTH * 2 * 8 and py >= 4 * 8 then
      local cx = math.floor(px / 16)
      local cy = math.floor(py / 16) - 2
      if cx >= 0 and cx < Mining.GRID_WIDTH and cy >= 0 and cy < Mining.GRID_HEIGHT then
        wantX, wantY = cx, cy
      end
    end
    if wantX then inGrid = inGrid + 1 elseif px >= L.SIDEBAR_X then inSidebar = inSidebar + 1
    else inCrack = inCrack + 1 end
    if gotX ~= wantX or (wantX and gotY ~= wantY) then
      disagreed = disagreed + 1
      firstBad = firstBad or ("%d,%d: screen says %s,%s (%s), the cartridge says %s,%s")
        :format(px, py, tostring(gotX), tostring(gotY), tostring(why),
                tostring(wantX), tostring(wantY))
    end
  end
end
io.write(("  swept %d pixels: %d diggable, %d sidebar, %d crack strip\n")
         :format(swept, inGrid, inSidebar, inCrack))
ok(disagreed == 0, "%d pixels disagree -- %s", disagreed, tostring(firstBad))
-- the sweep has to reach all three regions, or it is not testing the split
ok(inGrid == Mining.GRID_WIDTH * Mining.GRID_HEIGHT * L.CELL * L.CELL,
   "the diggable area is %d pixels; 13x10 cells of 16x16 is %d",
   inGrid, Mining.GRID_WIDTH * Mining.GRID_HEIGHT * L.CELL * L.CELL)
ok(inSidebar > 0 and inCrack > 0, "the sweep never reached the sidebar or the crack strip")
-- every cell must be reachable, and by exactly 256 pixels
local per = {}
for py = 0, H - 1 do
  for px = 0, W - 1 do
    local cx, cy = Screen.cellAt(px, py)
    if cx then per[cy * 100 + cx] = (per[cy * 100 + cx] or 0) + 1 end
  end
end
local cells, wrong = 0, 0
for y = 0, Mining.GRID_HEIGHT - 1 do
  for x = 0, Mining.GRID_WIDTH - 1 do
    local n = per[y * 100 + x]
    if n then cells = cells + 1 end
    if n ~= L.CELL * L.CELL then wrong = wrong + 1 end
  end
end
ok(cells == Mining.GRID_WIDTH * Mining.GRID_HEIGHT,
   "only %d of %d cells can be tapped at all", cells, Mining.GRID_WIDTH * Mining.GRID_HEIGHT)
ok(wrong == 0, "%d cells are not exactly %d pixels", wrong, L.CELL * L.CELL)

section("3. the sidebar picks a tool")
-- Mining_ButtonTouchCheck's own comparisons, computed here independently and
-- swept over every pixel of the sidebar: 26*8+6 < x < 31*8+4, hammer
-- 5*8+3 < y < 13*8+6, pickaxe 14*8+2 < y < 21*8+6 -- all strict. (This section
-- used to assert the DRAWN rectangles, which is not what the cartridge tests.)
local function cartridgeTool(x, y)
  if not (26 * 8 + 6 < x and x < 31 * 8 + 4) then return nil end
  if 5 * 8 + 3 < y and y < 13 * 8 + 6 then return "hammer" end
  if 14 * 8 + 2 < y and y < 21 * 8 + 6 then return "pickaxe" end
  return nil
end
local hammer, pickaxe, neither, wrongTool = 0, 0, 0, 0
for y = 0, H - 1 do
  for x = L.SIDEBAR_X, W - 1 do
    local tool = Screen.toolAt(y, x)
    if tool ~= cartridgeTool(x, y) then wrongTool = wrongTool + 1 end
    if tool == "hammer" then hammer = hammer + 1
    elseif tool == "pickaxe" then pickaxe = pickaxe + 1
    else neither = neither + 1 end
  end
end
io.write(("  hammer %d px, pickaxe %d px, neither %d\n"):format(hammer, pickaxe, neither))
ok(wrongTool == 0, "%d sidebar pixels pick a different tool than the cartridge's test", wrongTool)
ok(hammer == 37 * 66, "the hammer covers %d pixels, not 37 x 66", hammer)
ok(pickaxe == 37 * 59, "the pickaxe covers %d pixels, not 37 x 59", pickaxe)
ok(neither > 0, "every pixel of the sidebar picks a tool; the gap between the two "
   .. "buttons and the margins have gone")
ok(Screen.toolAt(43, 230) == nil and Screen.toolAt(44, 230) == "hammer",
   "the hammer's test is 43 < y, strict")
ok(Screen.toolAt(110, 230) == nil, "the hammer's test is y < 110, strict")
ok(Screen.toolAt(80, 214) == nil and Screen.toolAt(80, 252) == nil,
   "the x test is 214 < x < 252, strict at both ends")

section("4. the dirt quads")
-- Mining_DrawDirt names four tile indices per layer; the sheet is 16 tiles wide
-- (its NCGR says 16x2), so index n is at column n % 16, row floor(n / 16).
local TILES = {
  [0] = { 14, 15, 30, 31 }, [1] = { 10, 11, 26, 27 }, [2] = { 8, 9, 24, 25 },
  [3] = { 6, 7, 22, 23 },   [4] = { 4, 5, 20, 21 },   [5] = { 2, 3, 18, 19 },
  [6] = { 0, 1, 16, 17 },
}
for level = 0, 6 do
  local t = TILES[level]
  local column = t[1] % 16
  ok(L.DIRT_COLUMN[level] == column,
     "layer %d draws from column %d; tile %d is column %d",
     level, L.DIRT_COLUMN[level], t[1], column)
  -- the quad has to be a 2x2 block: second tile one to the right, third and
  -- fourth directly below
  ok(t[2] == t[1] + 1 and t[3] == t[1] + 16 and t[4] == t[1] + 17,
     "layer %d's four tiles are not a 2x2 block at stride 16", level)
end
-- column 12 is skipped, which is why the column cannot be derived as 14 - 2*level
local used = {}
for level = 0, 6 do used[L.DIRT_COLUMN[level]] = true end
ok(not used[12], "column 12 is in use; the cartridge's seven quads skip it")
ok(L.DIRT_COLUMN[1] ~= 12,
   "layer 1 draws from column 12, which is the 14 - 2 * level formula rather "
   .. "than the cartridge's table")

section("5. the crack meter")
local full = Screen.crackLengthFor(196)
local empty = Screen.crackLengthFor(0)
io.write(("  crack length: %d tiles at full integrity, %d at zero\n"):format(full, empty))
ok(full == 0, "a full wall shows %d crack tiles, expected 0", full)
ok(empty == 25, "a broken wall shows %d crack tiles, expected 25", empty)
-- monotone, and never off the strip it is drawn in
local prev = -1
for integrity = 0, 196 do
  local n = Screen.crackLengthFor(integrity)
  ok(n >= 0 and n <= L.CRACK_END_TILE,
     "integrity %d gives %d crack tiles; the strip ends at tile %d",
     integrity, n, L.CRACK_END_TILE)
  if prev >= 0 then
    ok(n <= prev, "the crack got shorter as the wall weakened (%d -> %d)", prev, n)
  end
  prev = n
end
-- the crack art lives in the interface sheet, whose NCGR declares 54 tiles wide
ok(L.CRACK_SHEET_WIDTH == 54,
   "the interface sheet is 54 tiles wide; the crack base tiles 11, 65, 119 and "
   .. "173 are column 11 of rows 0..3 only at that stride")
for row = 0, 3 do
  local base = ({ 11, 65, 119, 173 })[row + 1]
  ok(base % 54 == L.CRACK_SHEET_COLUMN and math.floor(base / 54) == row,
     "crack base tile %d is column %d row %d at stride 54, expected column %d row %d",
     base, base % 54, math.floor(base / 54), L.CRACK_SHEET_COLUMN, row)
end

section("6. every treasure can reach the bag")
local chunk = loadfile(dir .. "items.lua")
if not chunk then
  io.stderr:write("could not load " .. dir .. "items.lua\n")
  os.exit(2)
end
local items = chunk()
local byName = {}
for id, def in pairs(items) do
  if type(def) == "table" and type(def.name) == "string" then byName[def.name:upper()] = id end
end
local resolved, unresolved = 0, {}
for key = 0, 48 do
  local constant = Mining.TREASURE_ITEMS[key]
  if constant then
    local id = byName[(constant:gsub("^ITEM_", ""):gsub("_", " "))]
    if id then resolved = resolved + 1 else unresolved[#unresolved + 1] = constant end
  end
end
io.write(("  %d of 49 treasure constants resolve to an item id\n"):format(resolved))
ok(resolved == 49, "%d treasure constants do not resolve: %s",
   #unresolved, table.concat(unresolved, ", "))
-- The join is on the DISPLAY NAME because a Gen 4 item record carries no symbol,
-- so a rename in the text bank breaks it. The control: a name that should not
-- resolve must not, or the lookup is matching anything.
ok(byName["NOT AN ITEM AT ALL"] == nil,
   "the item lookup resolves a name that does not exist, so section 6 proves nothing")

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)