-- tools/gen4_summary_art_check.lua -- the summary screen's cartridge art.
--
-- Checks that the importer (src/import/Gen4SummaryArt.lua) and the screen
-- (src/ui/Gen4SummaryMenu.lua) agree with pokeplatinum's summary sources on
-- the numbers the art depends on, and -- given a cache -- that every key the
-- screen asks for was extracted.
--
-- Run:  python tools/run_lua_check.py tools/gen4_summary_art_check.lua [<cache dir>]

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local A = require("src.import.Gen4SummaryArt")

local fails, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if cond then io.write("  ok    " .. what .. "\n")
  else fails = fails + 1; io.write("  FAIL  " .. what .. "\n") end
end

-- type_icon.c sMoveTypeIconPaletteIndex / sMoveCategoryIconPaletteIndex
local want = { normal = 0, fighting = 0, flying = 1, poison = 1, ground = 0, rock = 0, bug = 2,
  ghost = 1, steel = 0, mystery = 2, fire = 0, water = 1, grass = 2, electric = 0, psychic = 1,
  ice = 1, dragon = 2, dark = 0, cool = 0, beauty = 1, cute = 1, smart = 2, tough = 0 }
local same = true
for k, v in pairs(want) do if A.TYPE_ROW[k] ~= v then same = false end end
for k in pairs(A.TYPE_ROW) do if want[k] == nil then same = false end end
ok(same, "type icons use type_icon.c's palette rows for all 23 icons")
ok(A.CATEGORY_ROW.physical == 0 and A.CATEGORY_ROW.special == 1 and A.CATEGORY_ROW.status == 0,
   "category icons: physical 0, special 1, status 0")
-- sprites.c templates: tabs 0,1,2,4 in row 1, 3,5,6,7 in row 2
ok(A.TAB_ROW[0] == 1 and A.TAB_ROW[1] == 1 and A.TAB_ROW[2] == 1 and A.TAB_ROW[4] == 1
   and A.TAB_ROW[3] == 2 and A.TAB_ROW[5] == 2 and A.TAB_ROW[6] == 2 and A.TAB_ROW[7] == 2,
   "tab sprites take their template's explicit palette row")
ok(A.HP_TILES.green == 0xC0 and A.HP_TILES.yellow == 0xE0 and A.HP_TILES.red == 0x100 and A.HP_PALETTE == 10,
   "HP bar tiles and palette are main.c's")
ok(A.EXP_TILE == 0xAC and A.HEART_FILLED == 0x12C and A.HEART_EMPTY == 0x12E and A.HEART_ROW == 47,
   "EXP bar and appeal heart tiles are main.c's")
local balls = { 0, 2, 2, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 2, 0 }
local ballsOk = #A.BALL_PALETTE == 16
for i = 1, 16 do if A.BALL_PALETTE[i] ~= balls[i] then ballsOk = false end end
ok(ballsOk, "caught balls use sBallIDToPaletteNum")

-- the screen's numbers, read from its source (it needs love.graphics to load)
local f = io.open((root ~= "" and root .. "../" or "") .. "src/ui/Gen4SummaryMenu.lua", "rb")
local src = f and f:read("*a") or ""
if f then f:close() end
ok(src:find("moves = { 0, 0 }, contestMoves = { 0, 256 }, ribbons = { 256, 56 }", 1, true) ~= nil,
   "the panels are move_info at main.c's BG2 scrolls")
ok(src:find("moveType = { 151, 42 }", 1, true) and src:find("moveCursor = { 194, 48 }", 1, true)
   and src:find("category = { 108, 72 }", 1, true) and src:find("markings = { 48, 150 }", 1, true),
   "sprite positions are sprites.c's")
ok(not src:find("g.rectangle('fill',0,20", 1, true) and not src:find("rectangle('fill',0,144", 1, true),
   "no hand-drawn panel rectangles")

-- the cache, when given
local dir = arg[1]
if dir then
  local okI, index = pcall(dofile, dir .. "/gen4_summary_art.lua")
  ok(okI and type(index) == "table", "the cache carries gen4_summary_art")
  if okI and type(index) == "table" then
    local missing = {}
    local keys = { "a_button", "lv", "exp_bar", "hp_green", "hp_yellow", "hp_red", "heart_filled",
      "heart_empty", "move_cursor_0", "move_cursor_1", "ribbon_cursor", "ribbon_arrow_0",
      "ribbon_arrow_1", "tab_arrow_0", "tab_arrow_1", "shiny", "pokerus_cured", "pokerus_icon",
      "sub_backdrop", "category_physical", "category_special", "category_status" }
    for s = 0, 15 do keys[#keys + 1] = ("tab_%02d"):format(s) end
    for i = 1, 16 do keys[#keys + 1] = ("ball_%02d"):format(i) end
    for s = 1, 6 do keys[#keys + 1] = "status_" .. s end
    for s = 0, 4 do keys[#keys + 1] = "contest_dot_" .. s end
    for p = 0, 7 do keys[#keys + 1] = ("sub_button_%d_0"):format(p) end
    for _, m in ipairs(A.MARKINGS) do keys[#keys + 1] = "marking_" .. m .. "_0"; keys[#keys + 1] = "marking_" .. m .. "_1" end
    for t in pairs(A.TYPE_ROW) do keys[#keys + 1] = "type_" .. t end
    for _, k in ipairs(keys) do if not index[k] then missing[#missing + 1] = k end end
    ok(#missing == 0, "every key the screen draws was extracted" .. (#missing > 0 and (" (missing " .. table.concat(missing, ", ") .. ")") or ""))
    ok(index.tab_00 and index.tab_00.originX == -8 and index.move_cursor_0 and index.move_cursor_0.originX == -64,
       "sprites carry their cell origins")
  end
end

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
