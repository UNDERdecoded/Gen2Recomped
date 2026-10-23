-- API availability is observable through the real loader, before Game/world
-- construction. No imported content, graphics, or network is required.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.harness')
local GameVersion = require('src.core.GameVersion')
local Loader = require('src.mods.Loader')
local Runtime = require('src.mods.Runtime')
local WorldAPI = require('src.world.WorldAPI')
local Schemas = require('src.mods.Schemas')
local Catalog = require('tests.modkit.catalog')
local originalEvents, originalHooks, originalErrors = Runtime.events, Runtime.hooks, Runtime.errors
local originalVersion = GameVersion.get()
local savedLove = love
love = nil

local files = {
  ['mods/probe/manifest.json'] = [[{"id":"probe","name":"Probe","version":"1.0.0","api":2,"entry":"main.lua"}]],
  ['mods/probe/main.lua'] = [[
return function(mod)
  -- Runs inside the entry window, not after the loader has finished.
  mod.exports.early = mod:supports('world', 'warpTo')
  mod.exports.api = mod
end
]],
}
local fs = {
  read = function(path) return files[path] end,
  getDirectoryItems = function(path)
    if path == 'mods' then return { 'probe' } end
    return {}
  end,
  getInfo = function(path)
    if path == 'mods' or path == 'mods/probe' then return { type = 'directory' } end
    if files[path] then return { type = 'file' } end
  end,
  load = function(path) return loadstring(files[path], path) end,
}
local function probe(version)
  GameVersion.set(version)
  local data = { pokemon = {} }
  local loader = Loader.new({ fs = fs, dev = false })
  loader._game = function() error('supports must not construct Game') end
  assert(loader:load(data))
  assert(loader.apis.probe, tostring(loader.errors.probe))
  return loader.apis.probe, loader, data
end
local function yes(api, surface, name)
  local ok, reason = api:supports(surface, name)
  return ok == true and reason == nil
end
local function no(api, surface, name)
  local ok, reason = api:supports(surface, name)
  return ok == false and type(reason) == 'string' and #reason > 0
end

-- Builtin registrants can allocate fresh closures on each load. Compare
-- record structure and values while treating function identity as opaque,
-- as the registry parity gate does.
local function record(value)
  if type(value) == 'function' then return '<function>' end
  if type(value) ~= 'table' then return value end
  local out = {}; for k, v in pairs(value) do out[k] = record(v) end; return out
end

local allHooks, allEvents = {}, {}
for _, version in ipairs(GameVersion.ORDER) do
  local api, loader, data = probe(version)
  T.check(api.exports.early, version .. ': query succeeds inside entry chunk')
  T.check(yes(api, 'hooks', 'battle.damage') and yes(api, 'events', 'world.stepped'),
    version .. ': shared simulation/world call sites available')
  local registries = true
  for name in pairs(Schemas.REGISTRIES) do
    registries = registries and yes(api, 'content', name)
  end
  T.check(registries, version .. ': all API-2 registration surfaces available')
  T.eq(yes(api, 'world', 'flyTo'), type(WorldAPI.flyTo) == 'function',
    version .. ': additive native flight interface is reported when installed')
  T.check(yes(api, 'hooks', 'core.logic_speed'),
    version .. ': native speed hook is advertised')
  T.check(GameVersion.generation(version) == 1 and yes(api, 'hooks', 'item.use')
      or GameVersion.generation(version) ~= 1 and no(api, 'hooks', 'item.use'),
    version .. ': item-use producer is advertised only for its native GB contract')
  T.check(no(api, 'events', 'egg.hatched'),
    version .. ': absent Gen1Recomp API-3 events are not advertised')
  T.check(yes(api, 'events', 'mod.probe.ready') and yes(api, 'events', 'mod.other.ready'),
    version .. ': namespaced user events do not need a producer installed')
  for _, name in ipairs(Catalog.hooks()) do
    if yes(api, 'hooks', name) then allHooks[name] = true end
  end
  for _, name in ipairs(Catalog.events()) do
    if yes(api, 'events', name) then allEvents[name] = true end
  end
  -- Mutation of the handed-out metadata cannot change a capability answer.
  local statusHud = api:supports('hooks', 'battle.status_hud_visible')
  api.gameVersion, api.generation, api.host.version = 'red', 1, 'red'
  GameVersion.set('red')
  T.eq(api:supports('hooks', 'battle.status_hud_visible'), statusHud,
    version .. ': query retains captured host even after metadata/global changes')
  T.check(next(loader.events.listeners) == nil and next(loader.hooks.chains) == nil,
    version .. ': probing installs no listeners or wrappers')
  local pristine = { pokemon = {} }
  GameVersion.set(version)
  local vanilla = Loader.new({ fs = fs, noMods = true, dev = false })
  assert(vanilla:load(pristine))
  T.same(record(data), record(pristine), version .. ': querying mod leaves merged data equal to no-mod boot')
end

-- The union covers every existing native callback; stale catalog entries
-- also fail. This gate reads source rather than a second hand-kept name list.
T.same(allHooks, (function()
  local out = {}; for _, name in ipairs(Catalog.hooks()) do out[name] = true end; return out
end)(), 'all native hook names have a queryable implementation')
T.same(allEvents, (function()
  local out = {}; for _, name in ipairs(Catalog.events()) do out[name] = true end; return out
end)(), 'all native event names have a queryable implementation')

-- Also reject advertised names whose native call site was removed. Read
-- the simple declaration lists without exporting mutable production state.
local h = assert(io.open('src/mods/Capabilities.lua', 'r'))
local body = h:read('*a'); h:close()
local declared = { hooks = {}, events = {} }
for surface, list in body:gmatch('add%("(%w+)", "%d+", ([^%)]+)%)') do
  local names = list:match('^%[%[(.-)%]%]$') or list:match('^"(.-)"$')
  assert(names, 'unrecognized capability declaration')
  for name in names:gmatch('%S+') do declared[surface][name] = true end
end
T.same(declared.hooks, allHooks, 'advertised hook catalog has no stale call sites')
T.same(declared.events, allEvents, 'advertised event catalog has no stale call sites')

local api, loader = probe('crystal')
local noWorldBefore = package.loaded['src.world.WorldAPI']
T.check(yes(api, 'world', 'warpTo') and yes(api, 'world', 'heightAt'),
  'world methods available independently of save/map state')
T.eq(package.loaded['src.world.WorldAPI'], noWorldBefore, 'queries never require WorldAPI')
for _, surface in ipairs({ 'content', 'world', 'hooks', 'events' }) do
  for _, invalid in ipairs({ '', 1, false, {}, function() end }) do
    T.check(no(api, surface, invalid), surface .. ': malformed name declines with reason')
  end
  T.check(no(api, surface, nil), surface .. ': missing name declines with reason')
  T.check(no(api, surface, 'does.not.exist'), surface .. ': unknown name declines with reason')
end
for _, surface in ipairs({ '', 'event', 'hook', 'storage', 1, false, {} }) do
  T.check(no(api, surface, 'anything'), 'unknown/malformed surface declines with reason')
end
T.check(no(api, nil, 'anything'), 'missing surface declines with reason')
T.check(no(api, 'events', 'mod.probe.') and no(api, 'events', 'mod..ready'),
  'empty user-event namespace/name is unavailable')
T.check(no(api, 'world', 'new') and no(api, 'world', '_mapNamed')
    and no(api, 'world', 'face') and no(api, 'world', '__index'),
  'constructors, internals and NPC-handle methods are not world capabilities')
T.check(no(api, 'content', 'Pokemon') and no(api, 'hooks', 'BATTLE.DAMAGE'),
  'names are case-sensitive')

-- Verify world catalog against the real public method table, not just names
-- duplicated in a test. A supported method may still decline without a map.
love = savedLove or require('tests.love_stub')
local WorldAPI = require('src.world.WorldAPI')
for name, method in pairs(WorldAPI) do
  if type(method) == 'function' and name ~= 'new' and name:sub(1, 1) ~= '_' then
    T.check(yes(api, 'world', name), 'public WorldAPI method query: ' .. name)
  end
end
local worldNames = assert(body:match('for name in %(%[%[(.-)%]%]%):gmatch'))
for name in worldNames:gmatch('%S+') do
  T.eq(type(WorldAPI[name]), 'function', 'advertised world method exists: ' .. name)
end
local world = WorldAPI.new({}, 'probe')
local result, reason = world:warpTo('missing', 0, 0)
T.check(result == nil and reason == 'no overworld' and yes(api, 'world', 'warpTo'),
  'availability is distinct from current-state eligibility')

-- Version-specific routing is deliberately different from Gen1Recomp.
for _, version in ipairs(GameVersion.ORDER) do
  local mod = probe(version)
  local gen = GameVersion.generation(version)
  T.eq(mod:supports('hooks', 'trainer.before_battle'), true, version .. ': native trainer preparation seam')
  T.eq(mod:supports('hooks', 'world.talk'), true, version .. ': native NPC talk seam')
  T.eq(mod:supports('hooks', 'battle.status_hud_visible'), true,
    version .. ': native GB/GBA/DS HUD seam')
  T.eq(mod:supports('hooks', 'battle.overlay'), gen <= 3,
    version .. ': GB/GBA-only overlay seam')
  T.eq(mod:supports('hooks', 'ui.party.submenu'), gen <= 3,
    version .. ': native party-menu seam')
  T.eq(mod:supports('hooks', 'ui.pc.items'), gen <= 2,
    version .. ': native PC seam')
  T.eq(mod:supports('events', 'intro.birch_speech.started'), version == 'emerald',
    version .. ': Emerald-only Birch intro')
  T.eq(mod:supports('hooks', 'intro.oak_speech.build'), gen <= 2 and version ~= 'prism',
    version .. ': Oak route excludes Prism and newer intros')
end

-- A content query gates an actual registration through the entry API.
local entry = files['mods/probe/main.lua']
files['mods/probe/main.lua'] = [[
return function(mod)
  if mod:supports('content', 'strings') then
    mod.content.strings:register('QUERY_TEXT', 'Query succeeded')
  end
  if mod:supports('content', 'not_a_registry') then
    error('unavailable registration must be skipped')
  end
end
]]
local _, contentLoader, contentData = probe('crystal')
T.eq(contentData.strings.QUERY_TEXT, 'Query succeeded', 'supported registry accepts real registration')
T.eq(#contentLoader.errors, 0, 'unavailable content fallback loads without errors')
files['mods/probe/main.lua'] = entry

-- A generation-specific query gates the real DS HUD call site. Returning
-- false avoids drawing and lets this run without a graphics context.
local Gen4Battle = require('src.battle.Gen4Battle')
for _, version in ipairs({ 'platinum', 'black' }) do
  local mod = probe(version)
  local calls = 0
  if mod:supports('hooks', 'battle.status_hud_visible') then
    mod.hooks:wrap('battle.status_hud_visible', function()
      calls = calls + 1
      return false
    end)
  end
  T.eq(Gen4Battle.drawHealthboxes({}), true, version .. ': supported HUD hook suppresses native boxes')
  T.eq(calls, 1, version .. ': native HUD call reaches mod once')
end

-- A successful probe gates an actual native call: world.timeOfDay dispatches
-- the hook and resulting event. Queries themselves have no bus side effects.
api, loader = probe('crystal')
local calls, changes = 0, 0
if api:supports('hooks', 'world.tod') then
  api.hooks:wrap('world.tod', function(next, tod, ctx)
    calls = calls + 1
    return 'TEST_NIGHT'
  end)
end
if api:supports('events', 'world.tod_changed') then
  api.events:on('world.tod_changed', function(payload)
    changes = changes + 1
    T.eq(payload.tod, 'TEST_NIGHT', 'native event carries hook result')
  end)
end
local Overworld = require('src.world.OverworldController')
local ow = setmetatable({ tod = 'DAY', map = { id = 'PROBE' }, player = {} }, { __index = Overworld })
ow.syncGen2Tod = function() end
T.eq(ow:timeOfDay(), 'TEST_NIGHT', 'queried native hook executes through actual world method')
T.check(calls == 1 and changes == 1, 'native hook/event each dispatched once')
-- Unsubscribe and use the same native path: original time-of-day behavior.
loader.events:removeOwner('probe')
loader.hooks:removeOwner('probe')
GameVersion.set('red')
ow.tod = 'DAY'
T.eq(ow:timeOfDay(), 'DAY', 'unmodified native path retains vanilla result')
T.check(calls == 1 and changes == 1, 'no-mod path invokes no mod callbacks')

GameVersion.set(originalVersion)
love = savedLove
Runtime.install(originalEvents, originalHooks, originalErrors)
T.finish('mod supports')
