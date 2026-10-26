-- Real imported music, native world scripts and renderers; no game/device starts.
-- Arguments: host checkout, backend, version, existing cache root, owned ROM.
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")
local root, backend, version, cacheRoot, romPath = unpack(arg)
local native = backend == "gen1"
local function read(path)
  local file = assert(io.open(path, "rb"))
  local bytes = file:read("*a")
  file:close()
  return bytes
end
local rom = read(romPath)
local imported = assert(dofile(cacheRoot .. "/" .. version .. "/data/generated/audio.lua"))
local image = read(cacheRoot .. "/" .. version .. "/" .. imported.gen3.file)
assert(image == rom:sub(imported.gen3.base + 1, imported.gen3.base + #image))
local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
local Audio = native and require("src.core.game3.audio")
local Player = native and require("src.core.game3.m4a_player")
local pack, cache, constants
if native then
  require("src.import.gba.versions").select(version)
  local files = {}
  cache = {
    write = function(_, path, bytes)
      files[path] = bytes
      return true
    end,
    read = function(_, path)
      return files[path]
    end,
  }
  assert(require("src.import.gba.extract_audio").run(rom, cache, { root = "owned-native-import/audio" }))
  pack = assert(Player.loadPack(cache, "owned-native-import/audio"))
else
  local Json = require("src.link.Json")
  local extractor = require("src.import.RomExtractorGen3").new(
    rom,
    { id = version },
    Json.decode(read(root .. "/tools/rom_manifest_" .. version .. ".json"))
  )
  local audio = dofile(cacheRoot .. "/" .. version .. "/data/generated/audio.lua")
  audio.gen3.file, audio.programPrefix = "owned-imported-native-bgm.bin", nil
  love.filesystem.write(audio.gen3.file, image)
  extractor._songs, extractor._audio, extractor._constants = audio.songs, audio, {}
  extractor:extractFanfares()
  constants = assert(extractor._constants.gen3Fanfares)
end
local rows = {}
for _, case in ipairs({ "native-fade", "native-wait", "deferred-default", "stop-bgm" }) do
  local h = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, f)
  h.start({ { "playbgm", 0, 0 }, { "end" } })
  local resolve = native and Audio.resolveSong or require("src.core.Gen3SongIds").resolve
  local ids = { resolve("MUS_LEVEL_UP"), resolve("MUS_OBTAIN_ITEM") }
  if native then
    Audio._pack, Audio._cache, Audio._ready = pack, cache, true
    Audio._fanfareSd, Audio._fanfareSrc = {}, {}
  else
    local audio = dofile(cacheRoot .. "/" .. version .. "/data/generated/audio.lua")
    audio.gen3.file, audio.programPrefix = "owned-imported-native-bgm.bin", nil
    love.filesystem.write(audio.gen3.file, image)
    f.data.audio, f.data.constants.gen3Fanfares = audio, constants
    require("src.core.M4ASynth").invalidate()
  end
  h.clear()
  h.start({ { "playbgm", h.ids[case == "deferred-default" and 2 or 1], 0 }, { "end" } })
  h.update()
  local script
  if case == "native-fade" then
    script = { { "fadeoutbgm", 4 }, { "setvar", 0x4001, 1 }, { "end" } }
  else
    script = { { "playfanfare", ids[1] } }
    if case == "deferred-default" then
      script[#script + 1] = { "fadedefaultbgm" }
    end
    if case == "stop-bgm" then
      script[#script + 1] = { "playbgm", 0, 0 }
    end
    script[#script + 1] = { "waitfanfare" }
    script[#script + 1] = { "setvar", 0x4001, 1 }
    script[#script + 1] = { "end" }
  end
  local runner = h.start(script)
  if case ~= "native-fade" then
    assert(h.soundData.staticInputs > 0, "actual-import cold fanfare must admit userdata PCM")
  end
  local frames, completed = {}, nil
  for tick = 0, 85 do
    h.tick(tick)
    if tick > 0 then
      if native then
        runner:tick()
      else
        runner:update()
      end
    end
    local state = h.state()
    state.fanfare = h.fanfareState(ids)
    state.tick, state.running, state.value = tick, runner:isRunning(), h.value(runner)
    if state.value == 1 then
      completed = completed or tick
    end
    frames[#frames + 1] = state
    h.update()
  end
  assert(completed ~= nil and not runner:isRunning(), "imported native script must complete")
  rows[#rows + 1] = {
    case = case,
    completed = completed,
    frames = frames,
    trace = h.trace(),
    coldFanfareSource = case ~= "native-fade",
  }
  h.close()
end
f.close()
love.filesystem.remove("owned-imported-native-bgm.bin")
print("IMPORTED_NATIVE_BGM_STREAMS " .. require("src.link.Json").encode(rows))
