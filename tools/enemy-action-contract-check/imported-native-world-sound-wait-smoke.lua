package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local root, cache = assert(arg[1]), assert(arg[2])
local Sound, Synth = require("src.core.Sound"), require("src.core.M4ASynth")
local oldAudio = love.audio
local results = {}
for _, version in ipairs({ "firered", "emerald" }) do
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, "gen2", version)
  Sound.invalidate()
  Synth.invalidate()
  local audio = assert(dofile(cache .. "/" .. version .. "/data/generated/audio.lua"))
  assert(audio.sfx.SONG_08D.m4a == 141, "actual imported native sound label")
  local file = assert(io.open(cache .. "/" .. version .. "/" .. audio.gen3.file, "rb"))
  local bytes = file:read("*a")
  file:close()
  assert(#bytes == audio.gen3.size)
  local mount = "owned-real-field-audio-" .. version .. ".bin"
  love.filesystem.write(mount, bytes)
  audio.gen3.file, audio.programPrefix = mount, nil
  f.data.audio = audio
  local sources = {}
  local Source = {}
  Source.__index = Source
  function Source:play()
    self.playing, self.elapsed = true, 0
  end
  function Source:stop()
    self.playing = false
  end
  function Source:isPlaying()
    return self.playing or false
  end
  function Source:setVolume(v)
    self.volume = v
  end
  function Source:setLooping() end
  function Source:advance(dt)
    if self.playing then
      self.elapsed = self.elapsed + dt
      if self.elapsed >= self.duration then
        self.playing = false
      end
    end
  end
  love.audio = {
    newSource = function(input)
      assert(type(input) == "table" and input.getSampleCount, "actual native PCM reaches the speaker")
      local source = setmetatable({
        duration = input:getSampleCount() / input:getSampleRate(),
        samples = input:getSampleCount(),
        rate = input:getSampleRate(),
        channels = input:getChannelCount(),
      }, Source)
      assert(source.samples >= 64 and source.rate == 44100)
      sources[#sources + 1] = source
      return source
    end,
  }
  local Game, Fixed = require("src.core.Game"), require("src.core.FixedStep")
  local stack = require("src.core.StateStack")
  stack:init()
  local game = setmetatable(
    { data = f.data, save = f.game.save, stack = stack, input = require("src.core.Input"), speedOverride = 1 },
    { __index = Game }
  )
  game.input:init()
  local ow = setmetatable(
    { npcs = { {}, {} }, player = { facing = "up" } },
    { __index = require("src.world.OverworldController") }
  )
  local runner = require("src.script.ScriptRunner").new(game, ow)
  local commands = assert(require("src.script.Gen3ScriptVM").compile({
    map_scripts = {
      source = "RomExtractorGen3",
      scripts = {
        OWNED_IMPORTED_SOUND = {
          { "lockall" },
          { "playse", 141 },
          { "waitse" },
          { "setvar", 0x4001, 1 },
          { "releaseall" },
          { "end" },
        },
      },
    },
  }, "OWNED_IMPORTED_SOUND"))
  local steps, firstDone, frames, sounds = 0, nil, {}, {}
  f.e.api.events:on("sound.played", function(event)
    sounds[#sounds + 1] = event
  end)
  stack:push({
    update = function()
      if steps == 0 then
        runner:run(
          commands,
          { source = { modId = "portable_held_item", mapId = "OWNED_IMPORTED_MAP", strict = true } }
        )
      else
        runner:update()
      end
      local advanced = require("src.script.Gen3Commands").getVar(game.save, 0x4001) == 1
      firstDone = advanced and (firstDone or steps) or firstDone
      frames[#frames + 1] = {
        tick = steps,
        advanced = advanced,
        running = runner:isRunning(),
        fieldLocked = ow.gen3Locked or false,
        npcFrozen = ow.npcs[1].gen3ScriptFrozen or false,
        sourcePlaying = sources[1] and sources[1]:isPlaying() or false,
      }
      steps = steps + 1
    end,
  })
  Fixed:init(function(dt)
    game:step(dt)
  end)
  for _ = 1, 100 do
    for _, source in ipairs(sources) do
      source:advance(1 / 60)
    end
    game:update(1 / 60)
  end
  assert(#sources == 1 and #sounds == 1, "the actual imported script sound plays exactly once")
  local expected = math.ceil(sources[1].duration * 60)
  assert(
    firstDone == expected,
    "actual native wait must end with decoded PCM: got " .. tostring(firstDone) .. ", want " .. expected
  )
  for _, frame in ipairs(frames) do
    if frame.tick < expected then
      assert(frame.running and frame.fieldLocked and frame.npcFrozen and not frame.advanced)
    else
      assert(not frame.running and not frame.fieldLocked and not frame.npcFrozen and frame.advanced)
    end
  end
  assert(runner.ctx.g3Locked == nil and not Sound.isSePlaying(f.data))
  results[#results + 1] = {
    version = version,
    completed = firstDone,
    samples = sources[1].samples,
    rate = sources[1].rate,
    channels = sources[1].channels,
    frames = frames,
    sounds = sounds,
  }
  Sound.invalidate()
  Synth.invalidate()
  love.filesystem.remove(mount)
  f.close()
end
love.audio = oldAudio
print("IMPORTED_NATIVE_WORLD_WAIT_SMOKE " .. require("src.link.Json").encode(results))
