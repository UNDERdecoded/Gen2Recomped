package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local hostRoot, backend, version, cache, romPath = unpack(arg)
local native = backend == "gen1"
local function read(path)
  local f = assert(io.open(path, "rb"))
  local bytes = f:read("*a")
  f:close()
  return bytes
end
local rom = read(romPath)
local function uint(at, size)
  local n = 0
  for i = 0, size - 1 do
    n = n + assert(rom:byte(at + i + 1)) * 256 ^ i
  end
  return n
end
local original = assert(dofile(cache .. "/" .. version .. "/data/generated/audio.lua"))
local constants = assert(dofile(cache .. "/" .. version .. "/data/generated/constants.lua"))
local image = read(cache .. "/" .. version .. "/" .. original.gen3.file)
assert(
  image == rom:sub(original.gen3.base + 1, original.gen3.base + #image),
  "imported M4A image equals owned ROM slice"
)
local map = version == "firered" and 0x2539D4 or 0x31F61C
local cryIds, decoded, metadata, sampleMeta = {}, {}, {}, {}
for n, species in ipairs({ 4, 277, 411 }) do
  local index = species <= 251 and species - 1 or uint(map + (species - 277) * 2, 2)
  local wave = uint(original.gen3Cries.table + index * 12 + 4, 4) - 0x08000000
  local kind, count, freq = uint(wave, 2), uint(wave + 12, 4), uint(wave + 4, 4)
  assert(kind == 0 or kind == 1)
  local size = kind == 1 and math.ceil(count / 64) * 33 or count
  local encoded = rom:sub(wave + 17, wave + 16 + size)
  if native then
    decoded[n] = kind == 1 and require("src.core.game3.m4a_sample").decodeGfdpcm(encoded, count) or encoded
    assert(#decoded[n] == count)
  end
  cryIds[species], sampleMeta[index] = index, { sampleId = n }
  metadata[n] = { offset = native and #(table.concat(decoded)) - #decoded[n] or 0, size = count, freq = freq }
end
local f = dofile(hostRoot .. "/tests/enemy_actions/assist.lua").fixture(hostRoot, backend, version)
local runtime, oldSession
if native then
  runtime = require("src.core.game3.runtime")
  oldSession, runtime.session = runtime.session, { version = version }
end
local rows = {}
for _, species in ipairs({ 4, 277, 411 }) do
  for _, mode in ipairs({ 0, 6, 9 }) do
    local hardware = dofile(hostRoot .. "/tests/native_cry/fixture.lua").install(native, f)
    if native then
      require("src.core.game3.audio")._pack = {
        index = { cries = sampleMeta, cryIds = cryIds },
        samplesBin = table.concat(decoded),
        samples = metadata,
      }
    else
      local audio = assert(dofile(cache .. "/" .. version .. "/data/generated/audio.lua"))
      local mounted = "owned-imported-cry-image.bin"
      love.filesystem.write(mounted, image)
      audio.gen3.file, audio.programPrefix = mounted, nil
      f.data.audio, f.data.constants = audio, constants
      require("src.core.M4ASynth").invalidate()
    end
    local commands = {}
    local function add(name, a, b)
      commands[#commands + 1] = native and { op = name, a, b } or { name, a, b }
    end
    add("setvar", 0x8004, species)
    add("setvar", 0x8005, mode)
    add("playmoncry", 0x8004, 0x8005)
    add("waitmoncry")
    add("setvar", 0x4001, 1)
    add("end")
    hardware.tick(0)
    local runner, value
    if native then
      runner = require("src.core.game3.scripting.vm").new({ scripts = { OWNED_IMPORTED_CRY = commands } })
      assert(runner:start("OWNED_IMPORTED_CRY"))
      value = function()
        return require("src.core.game3.scripting.flags").getVar(runner.store, runner.ctx, 0x4001)
      end
    else
      local Cmd = require("src.script.Gen3Commands")
      Cmd.setVar(f.game.save, 0x4001, 0)
      local lowered = assert(require("src.script.Gen3ScriptVM").compile({
        map_scripts = {
          source = "RomExtractorGen3",
          scripts = { OWNED_IMPORTED_CRY = commands },
        },
      }, "OWNED_IMPORTED_CRY"))
      runner = require("src.script.ScriptRunner").new(f.game, {})
      runner:run(lowered, { source = { modId = "portable_held_item", strict = true } })
      value = function()
        return Cmd.getVar(f.game.save, 0x4001)
      end
    end
    local frames, completed = {}, nil
    for tick = 0, 220 do
      hardware.tick(tick)
      if tick > 0 then
        if native then
          runner:tick()
        else
          runner:update()
        end
      end
      local state = hardware.snapshot()
      state.tick, state.running, state.value, state.sources =
        tick, runner:isRunning(), value(), hardware.active()
      frames[#frames + 1] = state
      if value() == 1 then
        completed = completed or tick
      end
      hardware.update()
    end
    assert(
      completed and completed > 0 and not runner:isRunning(),
      "actual imported cry finishes before script return"
    )
    local plays = hardware.trace()
    assert(
      #plays == 1 and plays[1].samples and #plays[1].samples > 64,
      "actual imported cry renders audible PCM"
    )
    rows[#rows + 1] = {
      version = version,
      species = species,
      mode = mode,
      index = cryIds[species],
      completed = completed,
      frames = frames,
      plays = plays,
    }
    hardware.close()
    love.filesystem.remove("owned-imported-cry-image.bin")
  end
end
if native then
  runtime.session = oldSession
end
f.close()
print("IMPORTED_NATIVE_CRY_COMMANDS " .. require("src.link.Json").encode(rows))
