-- tools/gen4_pc_mart_menu_check.lua
--
-- The cartridge's numbers behind the PC storage screen, the main menu and the
-- Poke Mart counter, checked without drawing:
--
--   python tools/run_lua_check.py tools/gen4_pc_mart_menu_check.lua
--
-- (The pictures are tools/gen4_pc_mart_harness's job.)
package.path = './?.lua;' .. package.path
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
package.loaded['src.render.Assets'] = { image = function() return nil end, register = function() end }
package.loaded['src.render.Font'] = { draw = function() end, width = function(s) return #tostring(s) * 6 end,
  fit = function(s) return s end, drawBox = function() end, drawCode = function() end,
  pushStyle = function() end, popStyle = function() end, drawDialogueBox = function() end,
  glyphHeight = function() return 16 end }
package.loaded['src.core.Logger'] = { warn = function() end, info = function() end, error = function() end }
package.loaded['src.core.Strings'] = function(s) return s end
package.loaded['src.core.Sound'] = { play = function() end }
package.loaded['src.core.GameVersion'] = { isGen4 = function() return true end, isGen3 = function() return false end,
  isGen2 = function() return false end, get = function() return 'platinum' end }

local pressed = {}
local input = { wasPressed = function(_, k) return pressed[k] end, isDown = function() return false end }
local function press(screen, key) pressed = { [key] = true }; screen:update(1 / 60); pressed = {} end

-- ------------------------------------------------------------------ the PC
require('src.pokemon.Boxes').load({})
local PC = require('src.ui.Gen4BoxMenu')
local game = { data = { pokemon = { [387] = { name = 'TURTWIG' } }, items = {}, constants = {} },
  save = { party = { { species = 387, hp = 10 }, { species = 387, hp = 10 } } }, input = input,
  stack = { pop = function() end, push = function() end } }
local pc = PC.new(game, { mode = 'move' })
pc.row, pc.col = 1, 1
local x, y, where = pc:handPoint()
check(x == 112 and y == 24 and where == 'box', 'ov19_021D9D48: the hand sits 16 above slot (112, 40)')
pc.row, pc.col = 5, 6
x, y = pc:handPoint()
check(x == 232 and y == 120, 'the last slot is (232, 136) less 16')
pc.row = 0
x, y, where = pc:handPoint()
check(x == 168 and y == 8 and where == 'header', 'the box header point')
press(pc, 'up')
check(pc.row == PC.BUTTON_ROW, 'up from the header lands on the buttons')
pc.col = 1
x, y = pc:handPoint()
check(x == 159 and y == 160, 'PARTY PKMN point')
press(pc, 'right')
x, y = pc:handPoint()
check(x == 235 and y == 160, 'CLOSE BOX point')
press(pc, 'down')
check(pc.row == 0, 'down from the buttons wraps to the header')
pc.row, pc.col = PC.BUTTON_ROW, 1
pc:choose()
check(pc.partyOpen and pc.partyIndex == 1, 'PARTY PKMN opens the party panel')
x, y = pc:handPoint()
check(x == 144 and y == 12, 'the first party slot (144, 28) less 16')
press(pc, 'right')
check(pc.partyIndex == 2, 'left/right crosses the party columns')
pc.partyOpen = nil
pc.row = 0; pc:choose()
check(pc.menu and #pc.menu == 4 and pc.menu[1].key == 'JUMP' and pc.menu[4].key == 'HEADER CANCEL',
  'the header menu is JUMP / WALLPAPER / NAME / CANCEL')
pc:runAction('WALLPAPER'); pc:pickMenuRow(2); pc:pickMenuRow(3)
check(pc:box().wallpaper == 6, 'SCENERY 2, third wallpaper is wallpaper 6 (SNOW)')
game.save.currentBox = 3; pc:box().wallpaper = nil
check(pc:wallpaperId() == 2, 'box 3 starts on wallpaper 2 (PCBoxes_InitInternal)')
game.save.currentBox = 1
game.save.boxes[1][1] = { species = 387, hp = 10, markings = 1 }
pc.row, pc.col = 1, 1; pc:choose(); pc:runAction('MARK')
check(#pc.menu == 8 and pc.menu[1].mark == 0 and pc.menu[7].key == 'CONFIRM MARK', 'the MARK menu: six symbols, CONFIRM, CANCEL')
pc:pickMenuRow(1); pc:pickMenuRow(6)
check(game.save.boxes[1][1].markings == 1, 'a symbol toggles only the draft')
pc:pickMenuRow(7)
check(game.save.boxes[1][1].markings == 32, 'CONFIRM writes the draft back')

-- ------------------------------------------------------------ the main menu
package.loaded['src.core.SaveData'] = { saveFilename = function() return 'x.sav' end,
  load = function() return { player = { name = 'A' }, pokedex = {} } end, playSeconds = function() return 0 end }
love = { filesystem = { getInfo = function() return { type = 'file' } end } }
package.loaded['src.mods.Runtime'] = { call = function(_, _, _, items) return items end }
local Main = require('src.ui.Gen4MainMenu')
local menu = Main.new({ data = {}, input = input, stack = { pop = function() end } }, {})
check(menu.items[1].key == 'continue', 'CONTINUE first with a save')
press(menu, 'up')
check(menu.index == 1, 'FocusNextOption stops at the top')
for _ = 1, 10 do press(menu, 'down') end
check(menu.index == #menu.items, '...and at the bottom')
for i = 1, 5 do menu.items[#menu.items + 1] = { key = 'x' .. i, label = 'X', lines = 1 } end
menu.index = #menu.items; menu:targetScroll()
local tops = menu:tops()
check(menu.scrollTarget == (tops[#tops] - 1) * 8 + 32 - 192,
  'TargetFocusedOptionForScroll: the last window\'s frame ends on the bottom edge')
menu.index = 1; menu:targetScroll()
check(menu.scrollTarget == 0, '...and back to the top')

-- ---------------------------------------------------------------- the mart
local Shop = require('src.ui.Gen4ShopMenu')
local sgame = { data = { items = { [4] = { name = 'Poke Ball', price = 200 }, [17] = { name = 'Potion', price = 300 },
  [428] = { name = 'Kit', price = 0, fieldPocket = 7 } }, constants = { bagSize = 20 } },
  save = { inventory = { [17] = 3 }, money = 1000 }, input = input, stack = { pop = function() end } }
local shop = Shop.new(sgame, { 4, 17 })
shop:choose()
check(shop.mode == 'buy' and shop:cameraTarget() == 10, 'BUY slides the camera to the counter')
shop:choose()
check(shop.mode == 'quantity' and shop.max == 5 and shop.message, 'quantity: the clerk asks, the max is what money buys')
shop:step(1); shop:step(1)
check(shop.qty == 3, 'up adds one')
shop:choose()
check(shop.mode == 'confirm' and shop.yesNo == 1, 'confirm opens on YES')
shop:step(1); shop:choose()
check(shop.mode == 'buy' and sgame.save.money == 1000, 'NO goes back to the list without buying')
shop:choose(); shop:choose(); shop:choose()
check(sgame.save.money == 800 and sgame.save.inventory[4] == 1, 'YES buys')
shop:back()
check(shop.mode == 'menu', 'leaving the list returns to BUY / SELL')
shop:sellItem(17)
check(shop.mode == 'quantity' and shop.transaction == 'sell' and shop.unit == 150 and shop.max == 3
  and shop:cameraTarget() == 0 and not shop:counterUp(), 'selling: half price, the bag\'s count, no counter')
shop.qty = 2; shop:choose(); shop:choose()
check(sgame.save.money == 1100 and sgame.save.inventory[17] == 1, 'sold two')
shop:sellItem(428)
check(shop.mode == 'sell' and shop.message, 'a key item is refused')

-- ------------------------------------------------------- the storage menu
local Storage = require('src.ui.Gen4StorageMenu')
check(Storage.ROWS[1][3] == 'deposit' and Storage.ROWS[#Storage.ROWS][3] == false,
  'CommonScript_InitStorageSystemMenu: DEPOSIT first, SEE YA! last')
local st = Storage.new({ data = {}, input = input, stack = { pop = function() end } }, {})
local tx, ty = st:rect()
check(tx == 1 and ty == 1, 'the list menu sits at tile (1, 1)')

print(checks .. ' PC, main menu and mart checks passed')
