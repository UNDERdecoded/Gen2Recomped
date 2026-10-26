-- Independent pixel oracle from pinned Gen1's actual GBA compositor.
package.path = "./?.lua;./?/init.lua;" .. package.path
local root, version = assert(arg[1]), assert(arg[2])
require("src.core.GameVersion").set(version)
local fixture = dofile(root .. "/tests/render_contract/fixture.lua").new("gen1", version, root)
local Atlas = dofile(root .. "/examples/portable_oasc_world/Atlas.lua")
local Tileset = require("src.import.gba.tileset")
local Metatile = require("src.import.gba.metatile")
local f = require("src.import.gba.family").active()
local function bytes(s)
  local out = {}
  for i = 1, #s do
    out[i] = s:byte(i)
  end
  return out
end
local b = fixture.bank
local attrs = { count = 3, data = bytes(b.attributes) }
local pals = {}
for p = 0, 15 do
  pals[p] = {}
  for c = 0, 15 do
    local at = p * 32 + c * 2 + 1
    pals[p][c] = b.palettes:byte(at) + b.palettes:byte(at + 1) * 256
  end
end
local bundle = {
  primaryTiles = { count = 2, raw = bytes(b.tiles) },
  secondaryTiles = { count = 2, raw = bytes(b.tiles) },
  primaryMt = { count = 3, data = bytes(b.metatiles) },
  secondaryMt = { count = 3, data = bytes(b.metatiles) },
  primaryAttr = attrs,
  secondaryAttr = attrs,
  mapPals = Tileset.mergeMapPalettes(pals, pals),
}
local graphics = assert(fixture.handle:tileset(1, fixture.mapId))
local functions = {
  under = Metatile.compositeIndexedUnder,
  over = Metatile.compositeIndexedOver,
  middle = Metatile.compositeIndexedMiddle,
}
local checks = 0
for _, mid in ipairs({ 0, 1, 2, f.numPrimaryMetatiles, f.numPrimaryMetatiles + 1, f.numPrimaryMetatiles + 2 }) do
  local decoded = assert(Atlas.decode(graphics, mid))
  for name, fn in pairs(functions) do
    local indexed = fn(bundle, mid)
    local out = {}
    for i = 1, 256 do
      local n = indexed[i]
      local c = n % 16
      local color = bundle.mapPals[math.floor(n / 16)][c]
      out[i] = c == 0 and string.char(0, 0, 0, 0)
        or string.char(
          math.floor(color % 32 * 255 / 31),
          math.floor(math.floor(color / 32) % 32 * 255 / 31),
          math.floor(math.floor(color / 1024) % 32 * 255 / 31),
          255
        )
    end
    assert(
      decoded[name] == table.concat(out),
      version .. "/" .. mid .. "/" .. name .. " differs from native compositor"
    )
    checks = checks + 1
  end
end
print("NATIVE_PIXELS " .. checks)
