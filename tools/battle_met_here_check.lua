-- Run:  python tools/run_lua_check.py tools/battle_met_here_check.lua
--
-- BattleState.metHere names the map the player is ON (game.overworld.map),
-- not save.player.map, which only a save writes (captureSave).
package.path = './?.lua;' .. package.path
love = love or { math = { random = math.random }, filesystem = {}, graphics = {} }
local ok, BattleState = pcall(require, 'src.battle.BattleState')
if not ok then print('SKIP: BattleState needs LOVE (' .. tostring(BattleState):sub(1, 80) .. ')'); return end
local fails = 0
local function check(c, l) if not c then fails = fails + 1; print('FAIL: ' .. l) end end
local data = { maps = { A = { regionMapSection = 'SEC_A' }, B = { regionMapSection = 'SEC_B' } } }
local game = { data = data, save = { player = { map = 'A' } } }
check(BattleState.metHere(game) == 'SEC_A', 'no overworld: falls back to the saved map')
game.overworld = { map = { id = 'B' } }
check(BattleState.metHere(game) == 'SEC_B', 'a live overworld wins over the saved map')
if fails > 0 then os.exit(1) end
print('battle_met_here_check: ok')
