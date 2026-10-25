-- CPU-only targeted import into an explicit QA directory; normal caches stay untouched.
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")
local manifestPath, romPath, destination = assert(arg[1]), assert(arg[2]), assert(arg[3])
local function read(path)
  local file = assert(io.open(path, "rb"))
  local value = file:read("*a")
  file:close()
  return value
end
local Json = require("src.link.Json")
local manifest = assert(Json.decode(read(manifestPath)))
local bytes = read(romPath)
assert(bytes:sub(0xAD, 0xB0) == manifest.romHeader.gameCode, "wrong cartridge header")
love.image = { newImageData = dofile("tests/substitute_art/fixture.lua").image }
local extractor = require("src.import.RomExtractorGen3").new(bytes, manifest.version, manifest)
local images, written = {}, {}
extractor.saveImage = function(_, image, path)
  images[path] = image
end
extractor.write = function(_, name, value)
  written[name] = value
end
extractor:extractSubstituteArt()
local record =
  assert(written.constants and written.constants.gen3SubstituteArt, "native stage must import art")
local paths = {}
for _, side in ipairs({ "front", "back" }) do
  local image = assert(images["battle/substitute_" .. side .. ".png"])
  assert(image:getWidth() == 64 and image:getHeight() == 64)
  local target = destination .. "/" .. manifest.version .. "-" .. side .. ".rgba"
  local file = assert(io.open(target, "wb"))
  file:write(image:rgba8())
  file:close()
  paths[side] = target
end
print("SUBSTITUTE_ART " .. Json.encode({ version = manifest.version, art = record, raw = paths }))
