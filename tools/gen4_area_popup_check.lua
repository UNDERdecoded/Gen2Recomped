-- Run:  texlua tools/gen4_area_popup_check.lua <cache dir>
--
-- PLATINUM'S AREA-NAME SIGN (src/world/Gen4AreaPopup.lua), per
-- src/overlay005/map_name_popup.c and FieldMap_ChangeZone.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = (arg and arg[1] or ''):gsub('[/\\]$', '')
local function load(n) local f = loadfile(cacheDir .. '/' .. n .. '.lua') return f and f() end
local rec = load('gen4_area_popup')
check(rec, 'the cache must carry gen4_area_popup (run tools/gen4_area_popup_extract.lua)')
if not rec then print(('%d checks, %d failed'):format(PASS + FAIL, FAIL)) os.exit(1) end

local n = 0
for _, w in pairs(rec.windows) do
  n = n + 1
  check(w.w == 136 and w.h == 40 and #w.idx == 136 * 40, 'sign ' .. w.kind .. ' is 17x5 tiles')
end
check(n == 9, 'nine signs')
check(rec.headers[411].window == 2 and rec.headers[3].window == 1, 'Twinleaf wears the town sign, Jubilife the city one')

local game = { data = { gen4_area_popup = rec, text = load('text') } }
local P = require('src.world.Gen4AreaPopup')

-- triggers
local s = P.onArrive(game, nil, 411)
check(s and s.name == 'Twinleaf Town' and s.window == 1, 'arriving in Twinleaf shows its name on the town sign')
local building
for id, h in pairs(rec.headers) do if h.mapType == 4 and h.window ~= 0 then building = id break end end
check(building == nil or P.onArrive(game, nil, building) == nil, 'a building announces nothing on arrival')
-- two headers of one place share a name: walking between them is silent
local sameA, sameB
for id, h in pairs(rec.headers) do
  for id2, h2 in pairs(rec.headers) do
    if id ~= id2 and h.text == h2.text and h.window ~= 0 then sameA, sameB = id, id2 break end
  end
  if sameA then break end
end
check(sameA and P.onCross(game, nil, sameA, sameB) == nil, 'crossing between headers with one name is silent')
check(P.onCross(game, nil, 411, 342) ~= nil, 'crossing from Twinleaf onto Route 201 announces the route')

-- timing: 10 ticks in, 60 held, 10 out, at 30 Hz
local frames = 0
s = P.onArrive(game, nil, 411)
local inAt
while s do
  s = P.tick(game, s)
  frames = frames + 1
  if s and s.state == 'wait' and not inAt then inAt = frames end
  if frames > 1000 then break end
end
check(inAt == 20, 'in after 10 ticks (20 frames), got ' .. tostring(inAt))
check(frames == 20 + 120 + 20, 'and gone after 80 ticks in all, got ' .. frames)

-- a new name while one is up: the old slides out, the new comes in
s = P.onArrive(game, nil, 411)
for _ = 1, 40 do s = P.tick(game, s) end
s = P.onCross(game, s, 411, 342)
check(s.state == 'out' and s.next, 'a new place sends the old sign out first')
for _ = 1, 30 do s = P.tick(game, s) end
check(s and s.name == 'Route 201' and s.state == 'in', 'then brings the new one in')

-- the centring, worked by hand: width 60 -> 4 + ((8 + 0) * 8 + 8 - 60) / 2
check(P.xOffset(60) == 4 + math.floor((9 * 8 + 8 - 60) / 2), 'MapNamePopUp_DrawWindowFrame centring')

local ow = io.open('src/world/OverworldController.lua'):read('a')
check(ow:find('self:updateMapNameSign(opts, fromHeader)', 1, true), 'setMap hands the sign its trigger')
check(ow:find('require("src.world.Gen4AreaPopup").draw(Game, self.mapNameSign)', 1, true), 'and draws it')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
