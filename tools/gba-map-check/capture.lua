-- Observe public slot/name results in the real separate Gen1 checkout.
local root = assert(arg[1])
package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path
require('tests.modkit')
local Version = require('src.core.GameVersion')
local Catalog = require('src.import.gba.map_catalog')
local Family = require('src.import.gba.family')
local out = {}
for _, version in ipairs { 'firered', 'leafgreen', 'emerald', 'ruby', 'sapphire' } do
  assert(Version.set(version) == version)
  local entries = {}
  for group, info in pairs(Family.active():groups().groups) do
    for i, pret in ipairs(info.maps) do
      local number = i - 1
      local id = assert(Catalog.mapIdFor(group, number))
      local g, n = Catalog.groupNumFor(id)
      assert(g == group and n == number, 'nonunique canonical slot identity')
      entries[#entries + 1] = { group = group, number = number, pret = pret,
        canonical = id, constant = Family.active():mapConstAt(group, number) }
    end
  end
  table.sort(entries, function(a, b)
    return a.group < b.group or a.group == b.group and a.number < b.number
  end)
  out[version] = entries
end
print(require('src.link.Json').encode(out))
