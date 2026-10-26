package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Version = require('src.core.GameVersion')
local Names = require('src.core.Gen3MapNames')
local Catalog = require('src.import.gba.map_catalog')
local Loader = require('src.world.MapLoader')
local Copy = require('src.mods.Merge').deepCopy
local Registry = require('src.mods.Registry')
local Schema = require('src.mods.Schemas').REGISTRIES.maps
local Identity = require('src.core.MapIdentity')
local before = Version.get()

local function fixture(group, number)
  local data = T.fixtures.fresh()
  local id = string.format('MAP_G%02d_N%02d', group, number)
  local def = Copy(data.maps.FIX_TOWN)
  def.id, def.group, def.number, def.layoutId = id, group, number, 1
  def.width, def.height, def.blocks = 2, 1, { 0, 0 }
  def.collisionCells, def.elevationCells = { 0, 1 }, { 3, 4 }
  def.warps, def.objects, def.connections = {}, {}, {}
  data.maps = { [id] = def }
  local ts = data.tilesets[def.tileset]
  ts.blockCells, ts.blockTiles = 1, 2
  return data, def, id, Catalog.mapIdFor(group, number)
end

for _, game in ipairs { 'firered', 'emerald' } do
  Version.set(game); Loader.invalidateAll()
  local group, number = game == 'firered' and 4 or 25, game == 'firered' and 1 or 40
  local data, def, source, name = fixture(group, number)
  local untouched = Copy(def)
  T.check(type(name) == 'string', 'fixture uses observed native catalogue slot')
  T.eq(Names.publish(data), true, 'native map names published')
  T.eq(data.maps[name], def, 'public name is actual native definition identity')
  T.eq(data.maps[source], def, 'native storage address preserved')
  T.same(def, untouched, 'publishing cannot rewrite native header or grid')
  T.eq(Names.sourceId(data, name), source, 'public name resolves native storage key')
  T.eq(Names.canonicalId(data, source), name, 'native key resolves observed public name')
  T.eq(Names.registryId(data.maps, name), source, 'registry aliases fold to native address')
  T.eq(Names.registryId(data.maps, source), source, 'native registry key is stable')
  T.eq(Identity.runtimeId(data, name), source, 'native runtime identity resolves public names')
  T.eq(Identity.sourceId(data, name), source, 'native save/storage identity remains unchanged')
  T.eq(Identity.same(data, source, name), true, 'shared native identity agrees across both names')
  T.same(Identity.aliases(data, source), { source, name }, 'save lookup enumerates only proven physical names')
  local records = { [source] = { [3] = 'NATIVE' }, [name] = { [7] = false } }
  T.eq(Identity.savedValue(data, records, source, 3), 'NATIVE', 'native per-map save leaf retains priority')
  T.eq(Identity.savedValue(data, records, source, 7), false, 'public per-map save leaf retains explicit false')
  local map = Loader.load(data, source)
  T.eq(map.id, source, 'actual runtime and scripts retain native map id')
  T.eq(map.def, def, 'actual map owner retains native definition')
  T.eq(Loader.cached(name), map, 'native-first load binds public cache lookup')
  T.eq(Loader.load(data, name), map, 'public and native load share actual Map')
  T.eq(Loader.load(data, name).renderer, map.renderer, 'public and native load share actual renderer')
  map:setBlock(0, 0, 1, true)
  T.eq(Loader.load(data, name):blockAt(0, 0), 1, 'both aliases observe actual script artwork')
  T.eq(Loader.load(data, name):cellCollision(0, 0), 1, 'both aliases observe actual script permission')
  T.eq(def.blocks[1], 0, 'runtime edits do not rewrite native shared source')
  local otherNumber = number + 1
  local otherId = string.format('MAP_G%02d_N%02d', group, otherNumber)
  local otherName = assert(Catalog.mapIdFor(group, otherNumber))
  local other = Copy(def); other.id, other.number, other.blocks = otherId, otherNumber, def.blocks
  data.maps[otherId] = other; Names.publish(data)
  T.eq(data.maps[otherName], other, 'later native content registration receives its own observed name')
  T.eq(other.layoutId, def.layoutId, 'two distinct physical maps may share one layout id')
  T.neq(Loader.load(data, otherName), map, 'a shared layout cannot collapse distinct map owners')
  T.eq(Names.sourceId(data, otherName), otherId, 'shared-layout neighbor retains actual header address')
  map:clearBlockPatches()
  data.map_scripts = { source = 'RomExtractorGen3', scripts = {
    EDIT = { { 'setmetatile', 0, 0, 1, 1 }, { 'end' } },
  } }
  local gameState = { data = data, save = { flags = {}, party = {} } }
  local runner = require('src.script.ScriptRunner').new(gameState, { map = Loader.load(data, name) })
  runner:run(require('src.script.Gen3ScriptVM').compile(data, 'EDIT'))
  T.eq(runner:isRunning(), false, 'actual native VM completes after public-address load')
  T.eq(map:blockAt(0, 0), 1, 'actual native VM writes the same existing Map')
  T.eq(map:isWalkableCell(0, 0), false, 'actual native movement sees VM blocking')
  T.eq(Loader.evict(name), true, 'public cache eviction addresses native resource')
  T.eq(Loader.cached(source), nil, 'public eviction removes native cache entry')
  local reloaded = Loader.load(data, name)
  T.neq(reloaded, map, 're-entry has a newly built actual native owner')
  T.eq(reloaded.id, source, 'public-address re-entry retains native runtime id')
  T.eq(reloaded:blockAt(0, 0), 0, 're-entry restores source without earlier script patch')
  local registry = Registry.new('maps', Schema)
  registry.base = function() return data.maps end
  registry:patch(name, { label = 'PUBLIC_EDIT' }, 'public_mod')
  registry:patch(source, { music = 77 }, 'native_mod')
  T.eq(#registry.ops[source], 2, 'actual registry folds public/native mod writes in order')
  T.eq(registry.ops[name], nil, 'no independent alias operation log')
  T.eq(registry:get(name), registry:get(source), 'registry reads return same merged value')
  Schema.write(data.maps, registry)
  T.eq(data.maps[source], data.maps[name], 'actual schema merge preserves one native definition')
  T.eq(data.maps[name].id, source, 'mod merge retains native script/storage identity')
  T.eq(data.maps[name].label, 'PUBLIC_EDIT', 'public patch applied')
  T.eq(data.maps[name].music, 77, 'native patch composes with public patch')
  Names.publish(data)
  registry = Registry.new('maps', Schema); registry.base = function() return data.maps end
  local payload = Copy(data.maps[name]); payload.id, payload.group, payload.number = name, 99, 99
  registry:override(name, payload, 'replacement_mod'); Schema.write(data.maps, registry); Names.publish(data)
  T.eq(data.maps[source].id, source, 'public-address override retains native runtime id')
  T.eq(data.maps[source].group, group, 'public-address override cannot move the physical group')
  T.eq(data.maps[source].number, number, 'public-address override cannot move the physical number')
  T.eq(data.maps[source], data.maps[name], 'public-address override remains one physical map')
  local shared = data.maps[source]
  local replacement = Copy(shared); replacement.label = 'NATIVE_REPLACEMENT'
  data.maps[source] = replacement; Names.publish(data)
  T.eq(data.maps[name], replacement, 'native direct replacement updates unchanged physical alias')
  replacement = Copy(replacement); replacement.label = 'PUBLIC_REPLACEMENT'
  data.maps[name] = replacement; Names.publish(data)
  T.eq(data.maps[source], replacement, 'public direct replacement updates unchanged native address')
  local both = Copy(replacement)
  data.maps[source], data.maps[name] = both, both; Names.publish(data)
  replacement = Copy(both); data.maps[source] = replacement; Names.publish(data)
  T.eq(data.maps[name], replacement, 'already-shared replacement becomes next publication baseline')
  data.maps[name] = nil; Names.publish(data)
  T.eq(data.maps[name], nil, 'publication cannot resurrect an explicit deletion')
  T.eq(Names.sourceId(data, name), name, 'deleted alias cannot address an old native map')
  T.eq(Names.canonicalId(data, source), source, 'deleted public name is not advertised')
  -- A new registry starts from an actually published family for tombstones.
  local removed, _, raw, public = fixture(group, number); Names.publish(removed)
  registry = Registry.new('maps', Schema); registry.base = function() return removed.maps end
  registry:remove(public, 'remove_mod'); Schema.write(removed.maps, registry); Names.publish(removed)
  T.eq(removed.maps[raw], nil, 'public registry tombstone removes actual native definition')
  T.eq(removed.maps[public], nil, 'public registry tombstone removes its physical alias')
  -- Sharing a layout, provenance string, or slot-looking spelling is not
  -- enough to collapse an authored independent definition.
  local conflict, native, rawId, publicId = fixture(group, number)
  local authored = Copy(native); authored.id = publicId; authored.sourceId = rawId
  conflict.maps[publicId] = authored; Names.publish(conflict)
  T.eq(conflict.maps[rawId], native, 'independent native definition stays intact')
  T.eq(conflict.maps[publicId], authored, 'independent authored variant stays intact')
  T.eq(Names.sourceId(conflict, publicId), publicId, 'claimed provenance is not physical identity')
  T.eq(Identity.same(conflict, rawId, publicId), false, 'independent authored variants are distinct native identities')
  conflict.maps[publicId] = nil; Names.publish(conflict)
  T.eq(conflict.maps[publicId], nil, 'publication cannot recreate a deleted conflicting authored map')
  local invalid, wrong, rawId2, publicId2 = fixture(group, number)
  wrong.number = number + 1; Names.publish(invalid)
  T.eq(invalid.maps[publicId2], nil, 'header/slot disagreement cannot publish a public name')
  T.eq(invalid.maps[rawId2], wrong, 'refused metadata does not rewrite authored source')
  local unknown = { maps = { MAP_G99_N99 = { id = 'MAP_G99_N99', group = 99, number = 99, layoutId = 1 } } }
  Names.publish(unknown)
  T.eq(next(unknown._gen3MapNames.bySource), nil, 'unknown slots are not inferred from a shared layout')
  local switched, original, originalId, originalName = fixture(group, number); Names.publish(switched)
  Version.set(game == 'firered' and 'emerald' or 'firered')
  T.eq(Names.publish(switched), false, 'same map table cannot be relabelled for another edition')
  T.eq(Names.canonicalId(switched, originalId), originalId, 'stale edition cannot advertise canonical names')
  T.eq(switched.maps[originalName], original, 'profile refusal does not modify previous data')
  Version.set(game)
  Loader.invalidateAll()
end
Version.set('red')
local classic = { maps = { MAP_G04_N01 = { id = 'MAP_G04_N01', group = 4, number = 1 } } }
T.eq(Names.publish(classic), false, 'Gen1 cannot acquire GBA aliases')
T.eq(classic.maps.FR_PLAYERS_HOUSE_2F, nil, 'Gen1 registry is unchanged')
Version.set(before)
T.finish('native GBA map name identity and lifecycle')
