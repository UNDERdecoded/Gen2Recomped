package.path = "./?.lua;./?/init.lua;" .. package.path
local Identity = require("src.compat.gen1.MapIdentity")
local maps = assert(loadfile(arg[2]))()
local binding = Identity.bind(maps, arg[1])
local matched, unknown = 0, 0
for key, def in pairs(maps) do
  if type(def) == "table" and type(def.group) == "number" and type(def.number) == "number" then
    local name = Identity.lookup(arg[1], def.group, def.number)
    if name then
      local nativeId, actual = binding:nativeId(name)
      assert(actual == def and maps[nativeId] == def, "wrong native map record")
      assert(binding:legacyId(key) == name, "native identity did not round trip")
      assert(def.id == key, "imported definition was renamed")
      matched = matched + 1
    else unknown = unknown + 1 end
  end
end
assert(matched > 300, "native cache coverage missing")
print(arg[1], matched, unknown)
