-- Run:  python tools/run_lua_check.py tools/translation/coverage_check.lua <game data root>
--
-- WHAT A TRANSLATION REACHES, per imported game. Each game's cache is
-- collected (Sources.collect, what the worker sends to the translator) and
-- installed (Sources.apply, what the game swaps in at boot) with a marker
-- "translation" -- every string wrapped in «» -- and the screens' sources
-- are checked: names, menus, locations, type names, Pokétch apps, engine
-- labels drawn whole. Also checked: what must NOT change (ids, map names the
-- code looks up, people's names), and that a species-name nickname clears.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}
local PASS, FAIL = 0, 0
local function check(c, l) if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l) end end
local root = (arg and arg[1] or 'G:/Gen2Recomped'):gsub('[/\\]$', '')
local Sources = require('src.translation.Sources')
local Service = require('src.translation.Service')

local function loadMod(dir, name)
  local f = io.open(dir .. name .. '.lua', 'rb'); if not f then return nil end
  local chunk = loadstring(f:read('*a'), name); f:close()
  if not chunk then return nil end
  setfenv(chunk, {})
  local ok, t = pcall(chunk)
  return ok and type(t) == 'table' and t or nil
end
local function marked(s) return type(s) == 'string' and s:sub(1, 2) == '\194\171' end

local games = { 'red/', 'blue/', 'yellow/', 'gold/', 'silver/', 'crystal/', 'prism/', 'polishedcrystal/',
                'firered/', 'emerald/', 'platinum/' }
local seenAny = 0
for _, prefix in ipairs(games) do
  local dir = root .. '/' .. (prefix == 'red/' and '' or prefix) .. 'data/generated/'
  local data = {}
  for _, name in ipairs(Sources.MODULES) do data[name] = loadMod(dir, name) end
  if data.text then
    seenAny = seenAny + 1
    local game = prefix:gsub('/', '')
    local original = { field = data.field, pokemon = data.pokemon }
    local catalog = {}
    for _, s in ipairs(Sources.collect(data)) do catalog[s] = '\194\171' .. s .. '\194\187' end
    Sources.apply(data, catalog)
    Service.catalog = catalog
    -- species, moves, items
    local function anyMarked(t, field)
      local yes, total = 0, 0
      for _, d in pairs(t or {}) do
        if type(d) == 'table' and type(d[field]) == 'string' and d[field] ~= '' then
          total = total + 1; if marked(d[field]) then yes = yes + 1 end
        end
      end
      return yes, total
    end
    for _, m in ipairs({ 'pokemon', 'moves', 'items' }) do
      local y, t = anyMarked(data[m], 'name')
      check(t == 0 or y == t, ('%s: %s names translated %d/%d'):format(game, m, y, t))
    end
    local f, of = data.field or {}, original.field or {}
    -- Gen 1/2 town map, Gen 3 Fly menu
    if f.townMap and f.townMap.landmarks then
      local y, t = 0, 0
      for _, lm in pairs(f.townMap.landmarks) do
        if type(lm) == 'table' and type(lm.name) == 'string' and lm.name:find('%a') then t = t + 1; if marked(lm.name) then y = y + 1 end end
      end
      check(y == t and t > 0, ('%s: town map locations %d/%d'):format(game, y, t))
    end
    if f.flyWarps then
      local y, t = 0, 0
      for _, w in pairs(f.flyWarps) do
        if type(w) == 'table' and type(w.name) == 'string' then t = t + 1; if marked(w.name) then y = y + 1 end end
      end
      check(y == t, ('%s: Fly menu towns %d/%d'):format(game, y, t))
    end
    local bt = f.gen2BattleTower
    if bt and bt.menu then check(marked(bt.menu[1]), game .. ': Battle Tower menu') end
    if bt and bt.trainers then
      local tr = bt.trainers[1]
      check(not (tr and marked(tr.name)), game .. ': Battle Tower trainers keep their names')
    end
    if f.egg and f.egg.name then check(marked(f.egg.name), game .. ': the egg\'s name') end
    if f.boot and f.boot.startMap then check(f.boot.startMap == of.boot.startMap, game .. ': ids under field stay put') end
    if f.presetNames and f.presetNames.player then
      check(not marked(f.presetNames.player[1]), game .. ': preset player names stay names')
    end
    -- type names: data keeps English, the screen shows the translation
    local chart = data.type_chart
    if chart and chart.types then
      local y, t = 0, 0
      for _, rec in pairs(chart.types) do
        if type(rec) == 'table' and type(rec.name) == 'string' and not Sources.isId(rec.name) then
          t = t + 1; if marked(Service.name(rec.name)) and not marked(rec.name) then y = y + 1 end
        end
      end
      check(y == t, ('%s: type names shown translated %d/%d'):format(game, y, t))
    end
    local apps = data.gen4_menus and data.gen4_menus.poketch and data.gen4_menus.poketch.apps
    if apps then
      local app = apps[1] or apps[0]
      check(app and not marked(app.name) and marked(Service.name(app.name)), game .. ': Pokétch app names shown translated')
    end
    -- a species-name nickname clears, a real one stays
    local someKey, someDef
    for k, d in pairs(original.pokemon or {}) do if type(d) == 'table' and type(d.name) == 'string' then someKey, someDef = k, d; break end end
    if someKey then
      local save = { party = { { species = someKey, nickname = someDef.name, moves = {} },
                               { species = someKey, nickname = 'SPARKY', moves = {} } } }
      Service.normalizeNicknames(data, save)
      check(save.party[1].nickname == nil and save.party[2].nickname == 'SPARKY', game .. ': species-name nicknames show translated')
    end
  end
end
check(seenAny > 0, 'no imported game found under ' .. root)

-- engine labels drawn whole
do
  local engine = require('data.localization.engine_sources')
  local keys = {}
  for _, s in ipairs(engine) do keys[s] = true end
  for _, s in ipairs({ 'SAVE', 'CANCEL', 'SLP', 'USE', 'START:QUIT' }) do
    check(keys[s], 'the engine label "' .. s .. '" is collected')
  end
  Service.catalog = { SAVE = 'SAUVER', RED = 'ROUGE' }
  Service.engineKeys = keys
  check(Service.display('SAVE') == 'SAUVER', 'an engine label drawn whole is translated')
  check(Service.display('RED') == 'RED', 'a player called RED stays RED')
  Service.engineKeys = nil
end

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
