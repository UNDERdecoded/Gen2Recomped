-- Actual import stage and native fanfare timers, checked against private ROM inputs.
-- Arguments: existing cache root, owned FireRed ROM path, owned Emerald ROM path.
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")
local V = require("src.core.GameVersion")
local Extractor = require("src.import.RomExtractorGen3")
local Json = require("src.link.Json")
local function read(path)
  local file = assert(io.open(path, "rb"))
  local bytes = file:read("*a")
  file:close()
  return bytes
end
local rows = {}
for _, version in ipairs({ "firered", "emerald" }) do
  V.set(version)
  local rom = read(assert(arg[version == "firered" and 2 or 3]))
  local base = arg[1] .. "/" .. version
  local audio = assert(dofile(base .. "/data/generated/audio.lua"))
  local constants = assert(dofile(base .. "/data/generated/constants.lua"))
  local image = read(base .. "/" .. audio.gen3.file)
  assert(image == rom:sub(audio.gen3.base + 1, audio.gen3.base + #image))
  audio.gen3.file, audio.programPrefix = "owned-imported-bgm-image.bin", nil
  love.filesystem.write(audio.gen3.file, image)
  local manifest = Json.decode(read("tools/rom_manifest_" .. version .. ".json"))
  local extractor = Extractor.new(rom, { id = version }, manifest)
  local present = constants.gen3Fanfares ~= nil
  constants.gen3Fanfares = nil
  extractor._songs, extractor._audio, extractor._constants = audio.songs, audio, constants
  extractor:extractFanfares()
  local metadata = constants.gen3Fanfares
  local row = { version = version, cachedMetadata = present, freshMetadata = metadata ~= nil }
  if metadata then
    row.count, row.table, row.agreed = metadata.count, metadata.table, metadata.agreed
    local expected, checked = {}, {}
    for i = 0, metadata.count - 1 do
      expected[extractor.rom:u16(metadata.table + i * 4)] = extractor.rom:u16(metadata.table + i * 4 + 2)
    end
    local Fanfare = require("src.core.Gen3Fanfare")
    for name, record in pairs(metadata.fanfares) do
      assert(expected[record.index] == record.frames, "fresh metadata differs from the ROM timer table")
      expected[record.index] = nil
      local info = assert(Fanfare.info({ audio = audio, constants = constants }, record.index))
      assert(info.id == record.index and info.frames == record.frames)
      assert(info.player == (tonumber(audio.songs[record.song].player) or 2))
      assert(Fanfare.isSong({ audio = audio, constants = constants }, record.index))
      checked[#checked + 1] = { name = name, id = info.id, frames = info.frames, player = info.player }
    end
    assert(next(expected) == nil and #checked == metadata.count)
    table.sort(checked, function(a, b)
      return a.id < b.id
    end)
    row.checked = checked
  end
  assert(metadata, "current importer did not produce native fanfare metadata")
  rows[#rows + 1] = row
  print("IMPORTED_NATIVE_FANFARE_STAGE " .. Json.encode(row))
  love.filesystem.remove(audio.gen3.file)
  require("src.core.M4ASynth").invalidate()
end
print("IMPORTED_NATIVE_FANFARE_STAGES " .. Json.encode(rows))
