-- Boxed-menu row geometry (#564 start menu, #572 the PC and Pokédex windows).
-- pokered's menu boxes hug their choices: the last one lands on the bottom
-- interior row, so a double-spaced menu whose box is n*2+2 tall starts at
-- ty+2 -- draw_start_menu.asm (TextBoxBorder at 10,0 b=$0e, then hlcoord
-- 12,2 with wTopMenuItemY 2), players_pc.asm (0,0 b=8 c=14, hlcoord 2,2).
-- The port drew every row one tile high, which parked the text against the
-- top border and left the bottom interior row blank.
-- ROM-free: builds the real screens over tests/fixture_data.
--   luajit tests/engine/menu_row_offset_bug564.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq, same = T.check, T.eq, T.same
local Data = T.fixtures.load()

local Font = require("src.render.Font")
local SaveData = require("src.core.SaveData")
local Screens = require("src.ui.Screens")
local StateStack = require("src.core.StateStack")
local Theme = require("src.ui.Theme")

local function newGame()
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local save = SaveData.newGame()
  save.flags = save.flags or {}
  save.flags.EVENT_GOT_POKEDEX = true
  save.pokedex = { seen = { FIXMON_A = true }, owned = { FIXMON_A = true } }
  save.inventory = { FIX_POTION = 3 }
  return {
    data = Data, save = save, stack = stack,
    input = {
      queue = {},
      wasPressed = function(self, btn) return self.queue[btn] or false end,
      isDown = function() return false end,
    },
  }
end

-- Draw the menu with the font stubbed out and report, in tile rows, where
-- the labels, the ▶ cursor and the "more below" arrow actually landed.
local function layout(menu)
  local realDraw, realCode = Font.draw, Font.drawCode
  local out = { rows = {}, cols = {} }
  Font.draw = function(_, x, y)
    out.rows[#out.rows + 1] = y / 8
    out.cols[#out.cols + 1] = x / 8
    return 8
  end
  Font.drawCode = function(code, x, y)
    if code == Theme.cursor then
      out.cursor, out.cursorCol = y / 8, x / 8
    elseif code == Theme.moreArrow then
      out.arrow = y / 8
    end
  end
  local ok, err = pcall(menu.draw, menu)
  Font.draw, Font.drawCode = realDraw, realCode
  if not ok then error(err, 0) end
  return out
end

-- Every boxed menu owes the same two things to its border, and the second
-- is the one #564/#572 were about: a menu that starts at ty+1 leaves the
-- bottom interior row empty and the text crowded under the top edge.
local function boxRules(menu, label)
  local at = layout(menu)
  local first, last = at.rows[1], at.rows[#at.rows]
  check(first and first >= menu.ty + 1 and last <= menu.ty + menu.th - 2,
        label .. ": every choice sits inside the border (rows "
        .. tostring(first) .. ".." .. tostring(last) .. ", interior "
        .. (menu.ty + 1) .. ".." .. (menu.ty + menu.th - 2) .. ")")
  eq(last, menu.ty + menu.th - 2,
     label .. ": the last choice lands on the bottom interior row")
  eq(at.cursor, at.rows[menu.index - menu.scroll],
     label .. ": the cursor shares its row with the highlighted choice")
  eq(at.cursorCol, menu.tx + 1, label .. ": the cursor sits one tile in")
  return at
end

-- ---------------------------------------------------------------- #564
-- draw_start_menu.asm: box at (10,0) 14 rows tall, first choice at row 2,
-- seven double-spaced choices, so the last is on row 14 and the blank row
-- is the one under the top border.
local game = newGame()
local start = Screens.push(game, "StartMenu")
eq(#start.items, 7, "vanilla start menu has seven rows with the dex")
local at = boxRules(start, "start menu")
same(at.rows, { 2, 4, 6, 8, 10, 12, 14 }, "start menu rows match hlcoord 12,2")
eq(at.cols[1], start.tx + 2, "start menu labels sit two tiles in")

start.index = 3
eq(layout(start).cursor, 6, "cursor follows the third row down to row 6")

-- The "more below" glyph rides the bottom border, because the bottom
-- interior row now belongs to a choice (#564).
local Menu = require("src.ui.Menu")
local many = {}
for i = 1, 10 do many[i] = { label = "ROW" .. i } end
local scrolled = Menu.new(game, many,
  { tx = 9, ty = 0, tw = 11, maxVisible = 8 }) -- StartMenu's own opts
local sat = layout(scrolled)
eq(sat.arrow, scrolled.ty + scrolled.th - 1,
   "the more-below arrow is on the border row")
check(sat.arrow > sat.rows[#sat.rows],
      "the arrow is clear of the last visible choice")

-- ---------------------------------------------------------------- #572
-- players_pc.asm: TextBoxBorder (0,0) b=8 c=14 -> a 16x10 box whose four
-- choices start at hlcoord 2,2.
local pc = Screens.push(newGame(), "PlayerPC")
eq(pc.th, 10, "player's PC box is 10 tiles tall")
same(boxRules(pc, "player's PC").rows, { 2, 4, 6, 8 },
     "player's PC rows match hlcoord 2,2")

-- The Pokédex side menu (pokedex.asm PokedexMenuItemsText): DATA / CRY /
-- AREA / QUIT, opened by choosing a seen species off the dex list.
local dexGame = newGame()
local dexList = Screens.push(dexGame, "PokedexMenu", {})
local entry = dexList.items[1]
eq(entry.value, "FIXMON_A", "the fixture dex list opens on a seen species")
dexList.onChoose(entry, dexList)
local side = dexGame.stack:top()
check(side ~= dexList, "choosing an entry pushes the side menu")
same(boxRules(side, "Pokédex side menu").rows, { 10, 12, 14, 16 },
     "side menu rows fill its box")

-- The bag's USE / TOSS box is the one menu pokered draws without a blank
-- leading row: USE_TOSS_MENU_TEMPLATE (data/text_boxes.asm) is (13,10) to
-- (19,14) with the text at 15,11, so two double-spaced choices exactly
-- fill rows 11 and 13.  #284 sized the port's box to that, which is why
-- the shared "first choice at ty+2" rule pushes TOSS onto the border here.
local bagGame = newGame()
local bag = Screens.push(bagGame, "BagMenu")
bag.onChoose(bag.items[1], bag)
local useToss = bagGame.stack:top()
eq(#useToss.items, 2, "the bag submenu is USE / TOSS")
boxRules(useToss, "bag USE/TOSS")

T.finish("menu_row_offset_bug564")
