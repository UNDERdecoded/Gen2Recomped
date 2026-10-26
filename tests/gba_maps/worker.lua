local root, fixture, observations, version, backend = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4]), assert(arg[5])
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
local T = require('tests.modkit')
local V = require('src.core.GameVersion')
if backend == 'gen1' then assert(V.set(version) == version)
elseif V.VERSIONS[version] then V.set(version) end
-- Extra version arguments select metadata in this fork. They do not register
-- a playable cartridge or fake a GameVersion that the native engine lacks.
local Json = require('src.link.Json')
local f = assert(io.open(observations, 'rb')); local rows = assert(Json.decode(f:read('*a')))[version]; f:close()
local result = assert(loadfile(fixture))()(T, require('src.import.gba.map_catalog'), rows, version)
print('GBA_MAP_CONTRACT ' .. Json.encode(result))
T.finish('public native GBA map identity ' .. version)
