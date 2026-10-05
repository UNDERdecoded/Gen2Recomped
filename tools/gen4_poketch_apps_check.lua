-- Run:  texlua tools/gen4_poketch_apps_check.lua
--
-- THE POKETCH'S TRAINER COUNTER AND COLOR CHANGER (src/ui/Gen4Poketch.lua),
-- per applications/poketch/trainer_counter and color_changer.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
package.loaded['src.render.SecondScreen'] = { toLocal = function(_, x, y) return x, y end, mode = function() return 'off' end }
package.loaded['src.render.Assets'] = { image = function() return nil end, register = function() end }
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1 print('FAIL: ' .. l) end end
local P = require('src.ui.Gen4Poketch')
local function same(a, b) for i = 1, 3 do if a[i] ~= b[i] then return false end end return true end
check(same(P.counterDigits(5), { false, false, 5 }), '5 shows one digit')
check(same(P.counterDigits(41), { false, 4, 1 }), '41 shows two')
check(same(P.counterDigits(0), { false, false, 0 }), '0 still shows its last digit')
check(same(P.counterDigits(1200), { 9, 9, 9 }), 'and the count stops at 999')
check(P.COUNTER_ICONS[1][1] == 96 and P.COUNTER_DIGITS[4][2] == 168, 'the cartridge\'s positions')
local store = {}
local fake = setmetatable({ store = function() return store end }, { __index = P })
P.colorTouch(fake, 48, 140); check(store.color == 0, 'x 48 is colour 0')
P.colorTouch(fake, 111, 140); check(store.color == 3, 'x 111 is colour 3 (16 pixels a notch)')
P.colorTouch(fake, 183, 140); check(store.color == 7, 'x 183 is colour 7')
P.colorTouch(fake, 100, 120); check(store.color == 7, 'a touch off the slider changes nothing')
local src = io.open('src/ui/Gen4Poketch.lua'):read('a')
check(src:find('["Trainer Counter"] = Gen4Poketch.drawTrainerCounter', 1, true)
      and src:find('["Color Changer"] = Gen4Poketch.drawColorChanger', 1, true), 'both apps are drawn')
print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
