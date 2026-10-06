-- tools/gen4_bag_card_check.lua -- Platinum's BAG and TRAINER CARD, the parts
-- that are not pictures, and (given a cache) that the importers' art carries
-- every key the two screens draw and that the trainer case was composed in
-- Platinum's palette rather than Diamond's.
--
--   * the bag's list is the cartridge's ListMenu: an empty header at each
--     end, the cursor starting on row 1, moving freely to row 5 and then
--     scrolling the list under it, no wrap, the far end reachable and the
--     headers never selected; each pocket keeps its own cursor
--   * the pocket strip's arithmetic (CalcPocketSelectorIconsPos) for 8 and 1
--   * a bag opened at one pocket shows exactly that pocket
--   * the TM pocket lists the move's name and the TM's number
--   * the trainer card's face by level / no Pokedex, its live time format
--
--   python tools/run_lua_check.py tools/gen4_bag_card_check.lua [cache dir]

local cacheDir = arg and arg[1]
package.path = "./?.lua;" .. package.path

package.loaded['src.render.Font'] = { width = function(s) return #tostring(s) * 6 end }
package.loaded['src.core.Logger'] = { warn = function() end, info = function() end }
package.loaded['src.core.Strings'] = function(s, ...) if select('#', ...) > 0 then return s:format(...) end return s end
package.loaded['src.render.Assets'] = { image = function() return nil end }
package.loaded['src.ui.Theme'] = { cursor = 0 }
package.loaded['src.render.Gen4Palettes'] = { text = function() return nil end }
package.loaded['src.ui.SecondScreen'] = { mode = function() return "off" end, stowed = function() return true end }

local PASS, FAIL = 0, 0
local function check(cond, what)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print("FAIL: " .. what) end
end

-- --------------------------------------------------------------- the bag --
local Bag = require('src.ui.Gen4BagMenu')
local function bagGame(n, pocket)
  local items, inv, order = {}, {}, {}
  for i = 1, n do
    local key = ("ITEM_%03d"):format(i)
    items[key] = { id = i, name = "Item" .. i, fieldPocket = pocket or 0, description = "d" .. i }
    inv[key] = i
    order[i] = key
  end
  -- one item in MEDICINE, for the per-pocket cursor
  items.ITEM_900 = { id = 900, name = "Potion", fieldPocket = 1 }
  inv.ITEM_900 = 1; order[#order + 1] = "ITEM_900"
  return { data = { items = items, moves = {}, gen4_menus = { bag = { pockets =
             { "ITEMS", "MEDICINE", "POKé BALLS", "TMs & HMs", "BERRIES", "MAIL", "BATTLE ITEMS", "KEY ITEMS" } } } },
           save = { inventory = inv, bagOrder = order, player = {} },
           stack = { pop = function() end, push = function() end } }
end

do
  local s = Bag.new(bagGame(20))
  check(#s.rows == 23 and s.rows[1].header and s.rows[23].header and s.rows[22].close,
        'a pocket of 20: header, 20 items, CLOSE BAG, header (got ' .. #s.rows .. ' rows)')
  check(s.cursorPos == 1 and s.listPos == 0 and s:selected().id == "ITEM_001", 'the cursor starts on row 1, the first item')
  s:moveCursor(false)
  check(s.cursorPos == 1 and s:selected().id == "ITEM_001", 'up from the first item stays (no wrap, the header is not selectable)')
  for _ = 1, 4 do s:moveCursor(true) end
  check(s.cursorPos == 5 and s.listPos == 0, 'four downs reach row 5 without scrolling')
  s:moveCursor(true)
  check(s.cursorPos == 5 and s.listPos == 1 and s:selected().id == "ITEM_006", 'the fifth scrolls the list under the cursor')
  for _ = 1, 40 do s:moveCursor(true) end
  check(s:selected().close and s.listPos == 23 - 9 and s.cursorPos == 7,
        'the end: CLOSE BAG on row 7 with the trailing header below it (pos ' .. s.cursorPos .. ', scroll ' .. s.listPos .. ')')
  local before = s.index
  s:moveCursor(true)
  check(s.index == before, 'down from CLOSE BAG stays (no wrap)')
  for _ = 1, 40 do s:moveCursor(false) end
  check(s.listPos == 0 and s.cursorPos == 1, 'all the way back up: row 1, unscrolled')

  -- each pocket keeps its own cursor
  for _ = 1, 3 do s:moveCursor(true) end
  s:movePocket(1)
  check(s.pocket == 2 and s.cursorPos == 1 and s:selected().id == "ITEM_900", 'MEDICINE opens on its own row 1')
  s:movePocket(-1)
  check(s.pocket == 1 and s.cursorPos == 4, 'back to ITEMS: its cursor is where it was left')

  -- the strip
  local x, pitch = s:iconRow()
  check(x == 7 and pitch == 11, 'eight pockets: icons from x 7, 11 apart (got ' .. x .. ', ' .. pitch .. ')')
end

do
  local s = Bag.new(bagGame(3), { pocket = "ITEMS" })
  local shown = s:shownPockets()
  check(#shown == 1 and shown[1] == 1 and s.pocket == 1, 'opened at ITEMS: ITEMS alone, not BATTLE or KEY ITEMS')
  local x = s:iconRow()
  check(x == 6 + math.floor(80 / 2), 'one pocket: the icon centred in the ninety pixels (x ' .. x .. ')')
  s:movePocket(1)
  check(s.pocket == 1, 'a one-pocket bag does not change pocket')
  local short = Bag.new(bagGame(2))
  check(#short.rows == 5 and short:listRows() == 5, 'a short pocket shows only its own five entries')
  for _ = 1, 9 do short:moveCursor(true) end
  check(short:selected().close and short.listPos == 0, 'a short pocket never scrolls')
end

do
  -- the TM pocket: the move's name, the TM's number
  local g = bagGame(0)
  g.data.items.ITEM_328 = { id = 328, name = "TM01", fieldPocket = 3, machine = { move = 264, kind = "TM" } }
  g.data.items.ITEM_420 = { id = 420, name = "HM01", fieldPocket = 3, machine = { move = 15, kind = "HM" } }
  g.data.moves = { [264] = { name = "Focus Punch" }, [15] = { name = "Cut" } }
  g.save.inventory.ITEM_328 = 2; g.save.inventory.ITEM_420 = 1
  table.insert(g.save.bagOrder, "ITEM_328"); table.insert(g.save.bagOrder, "ITEM_420")
  local s = Bag.new(g)
  s:movePocket(3)
  check(s.rows[2].label == "Focus Punch" and s.rows[2].number == 1 and not s.rows[2].hm,
        'TM01 is listed as Focus Punch, number 1')
  check(s.rows[3].label == "Cut" and s.rows[3].number == 1 and s.rows[3].hm, 'HM01 is listed as Cut, an HM')
end

-- ------------------------------------------------------- the trainer card --
local Card = require('src.ui.Gen4TrainerCard')
package.loaded['src.script.Flags'] = { hasPokedex = function(save) return save.dex == true end }
local function cardGame(save)
  return { data = {}, save = save, stack = { pop = function() end } }
end
do
  local c = Card.new(cardGame({ dex = true, playTime = 3600 * 5 + 60 * 7, player = {} }))
  check(c:faceName() == "normal", 'a new save with the dex: the normal face')
  local c2 = Card.new(cardGame({ dex = true, hallOfFame = { {} }, player = {} }))
  check(c2:faceName() == "cobalt", 'the game completed: one star, cobalt')
  local c3 = Card.new(cardGame({ dex = false, hallOfFame = { {} }, player = {} }))
  check(c3:faceName() == "no_dex", 'no Pokedex: the no-dex face whatever the level')
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if ok and SaveData and SaveData.playSeconds then
    local time
    for _, r in ipairs(c:frontRows()) do if r[1] == "TIME" then time = r[2] end end
    check(time == "  5  07", 'the live time: hours padded to three, two spaces, minutes (got ' .. tostring(time) .. ')')
  end
  c.t = 0
  local shown0 = c:colonShown()
  c.t = 5
  local shown5 = c:colonShown()
  c.t = 20
  check(shown0 and not shown5 and c:colonShown(), 'the colon blinks: hidden the first half of each thirty frames')
end

-- ------------------------------------------------------------ the cache --
if cacheDir then
  local function load(name)
    local f = io.open(cacheDir .. "/" .. name .. ".lua", "rb")
    if not f then return nil end
    local src = f:read("*a"); f:close()
    local fn = loadstring(src)
    return fn and fn()
  end
  local bag = load("gen4_bag_art")
  check(bag ~= nil, 'the cache carries gen4_bag_art (tools/gen4_art_extract bag)')
  if bag then
    local need = { "item_highlight_0", "item_highlight_1", "pocket_highlight_0", "arrow_left", "arrow_right",
                   "item_return", "entry_icons", "special_chars", "sub_borders", "sub_dial", "dial_button_0" }
    for p = 0, 7 do
      need[#need + 1] = "bag_male_" .. p; need[#need + 1] = "bag_female_" .. p
      need[#need + 1] = ("pocket_button_%d_0"):format(p)
    end
    local missing = {}
    for _, k in ipairs(need) do if not bag[k] then missing[#missing + 1] = k end end
    check(#missing == 0, 'gen4_bag_art carries every key the bag draws (missing: ' .. table.concat(missing, ", ") .. ')')
    local h = bag.item_highlight_0
    check(h and h.width == 152 and h.height == 32 and h.originX == -72 and h.originY == -16,
          'the item highlight is the 152x32 cell centred on its anchor')
    check(bag.bag_male_0 and bag.bag_male_0.width == 64 and bag.bag_male_0.originX == -32,
          'the bag is a 64x64 cell centred on (48, 50)')
    check(bag.special_chars and bag.special_chars.width == 184 and bag.entry_icons and bag.entry_icons.width == 64,
          'the special characters (23 tiles) and the 64x16 entry tags')
  end
  local card = load("gen4_trainer_card_art")
  check(card ~= nil, 'the cache carries gen4_trainer_card_art (tools/gen4_art_extract trainer_card)')
  if card then
    local need = { "case_top", "lucas", "dawn", "badge_case", "badge_case_lid" }
    for _, l in ipairs({ "normal", "cobalt", "bronze", "silver", "gold", "black", "no_dex" }) do
      need[#need + 1] = "front_" .. l; need[#need + 1] = "back_" .. l
    end
    for i = 0, 7 do need[#need + 1] = "badge_" .. i end
    local missing = {}
    for _, k in ipairs(need) do if not card[k] then missing[#missing + 1] = k end end
    check(#missing == 0, 'gen4_trainer_card_art carries every key the card draws (missing: ' .. table.concat(missing, ", ") .. ')')
  end
end

-- the palette arithmetic, which needs no cache
do
  local T = require('src.import.Gen4TrainerCardArt')
  local normal, level, case = {}, {}, {}
  for i = 1, 256 do normal[i] = { 1, 1, 1 }; level[i] = { 2, 2, 2 }; case[i] = { 3, 3, 3 } end
  local p = T.subPalette(normal, level, case)
  check(p[1][1] == 3 and p[16][1] == 3 and p[17][1] == 2 and p[64][1] == 2 and p[65][1] == 1
        and p[240][1] == 1 and p[241][1] == 2 and p[256][1] == 2,
        'the sub palette: case over row 0, the level over rows 1-3 and 15, normal elsewhere')
  local m = T.mainPalette(normal, case)
  check(m[16][1] == 3 and m[17][1] == 1, 'the main palette: case over row 0 only')
end

print(("%d checks, %d failed"):format(PASS + FAIL, FAIL))
if FAIL > 0 then error("gen4 bag/card checks failed") end
