-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
return function(root)
  local Audio = require("src.audio.NitroAudio")
  local Sdat = require("src.import.Gen4Sdat")
  local P = require("src.core.Performance")
  local Fixture = assert(loadfile(root .. "/tools/audio-profile-check/NitroFixture.lua"))()
  local Sequence = require("src.audio.NitroSequence")
  local checks = 0
  local function check(ok, message)
    assert(ok, message)
    checks = checks + 1
  end
  -- Direct engine comparison covers all samples and exact event/phase state.
  for _, format in ipairs({ 0, 1, 2 }) do
    for _, looping in ipairs({ false, true }) do
      local arc = assert(Sdat.open(Fixture(format, looping)))
      local before
      local after = Audio._workerNew(arc, { nds = 0 })
      -- The baseline renderer retains ordinary arrays; do not compact its samples.
      -- Use a separately constructed public legacy instance through its native
      -- archive seam, keeping the SDAT decoder and sequencer unmodified.
      local oldArchive = Audio.archive
      Audio.archive = function()
        return arc
      end
      P.audioWorkerOptimization = false
      before = Audio.new({ audio = {} }, { nds = 0 })
      Audio.archive = oldArchive
      before.tickPhase = 1
      before.variables = {}
      before.looping = looping
      after.looping = looping
      local sent = {}
      for _ = 1, 8 do
        local sd, state, _, done = Audio._workerRender(after, 8192, sent)
        local bytes = {}
        for _ = 1, sd:getSampleCount() / 512 do
          bytes[#bytes + 1] = before:render():getString()
        end
        check(table.concat(bytes) == sd:getString(), "DS PCM differs, format " .. format)
        check(before.tickPhase == state.tickPhase and before.tempo == state.tempo, "DS tick phase differs")
        check(before:variable(0) == after:variable(0), "DS local variable differs")
        check(#before.voices == #state.voices, "DS voice count differs")
        for n, v in ipairs(before.voices) do
          for key, value in pairs(v) do
            if key ~= "sample" then
              check(value == state.voices[n][key], "DS voice field differs: " .. key)
            end
          end
        end
        if done then
          check(before.ended and #before.voices == 0, "DS tail padding changed")
          break
        end
      end
    end
  end
  check(not Sequence.workerSafe(string.char(160, 128, 0, 0, 1, 0), 0), "random prefix admitted")
  check(not Sequence.workerSafe(string.char(176, 16, 0, 0, 255), 0), "shared variable admitted")
  check(Sequence.workerSafe(string.char(176, 0, 160, 0, 255), 0), "argument mistaken for random opcode")
  P.audioWorkerOptimization = true
  local arc = assert(Sdat.open(Fixture(0, true)))
  local oldArchive = Audio.archive
  Audio.archive = function()
    return arc
  end
  local p = Audio.new({ audio = {} }, { nds = 0 })
  local q = Audio.new({ audio = {} }, { nds = 0 })
  Audio.archive = oldArchive
  p:play()
  q:play()
  local deadline = love.timer.getTime() + 10
  repeat
    Audio.update()
    love.timer.sleep(0.001)
  until #p.queue.buffers > 0 and #q.queue.buffers > 0 or love.timer.getTime() > deadline
  check(#p.queue.buffers > 0 and #q.queue.buffers > 0, "DS worker did not feed independent players")
  check(p.queue.capacity == 16 and p.queue.buffers[1]:getSampleCount() == 8192, "DS queue/block size changed")
  check(rawget(p, "voices") == nil, "worker state was not kept private")
  p:setVariable(0, 42)
  check(p:variable(0) == 42, "DS setter did not update immediate query")
  local voices = p.voices
  check(type(voices) == "table" and rawget(p, "voices") == voices, "direct state read did not restore legacy fields")
  check(type(p.samples) == "table", "legacy sample cache not restored")
  for _, sample in pairs(p.samples) do
    check(type(sample.pcm) == "table", "private PCM leaked through a state read")
  end
  p:stop()
  q:stop()
  check(not p:isPlaying() and not q:isPlaying(), "DS stopped player remained active")
  Audio.archive = function()
    return arc
  end
  local custom = Audio.new({ audio = {} }, { nds = 0 })
  local written = Audio.new({ audio = {} }, { nds = 0 })
  Audio.archive = oldArchive
  custom.render = function()
    return "owned custom renderer"
  end
  check(
    type(rawget(custom, "tracks")) == "table" and custom:render() == "owned custom renderer",
    "custom render did not select legacy transport"
  )
  written.tempo = 73
  check(
    rawget(written, "tempo") == 73 and type(written.tracks) == "table",
    "direct state write did not select legacy transport"
  )

  Audio.archive=function()return arc end
  local rolled=Audio.new({audio={}},{nds=0})
  Audio.archive=oldArchive
  rolled:play();P.audioWorkerOptimization=false;rolled:update()
  check(type(rawget(rolled,'voices'))=='table','P6 disable did not restore legacy state')
  rolled:stop();P.audioWorkerOptimization=true
  P.audioWorkerOptimization = false
  Audio.archive = function()
    return arc
  end
  local legacy = Audio.new({ audio = {} }, { nds = 0 })
  P.audioWorkerOptimization = true
  local threaded = Audio.new({ audio = {} }, { nds = 0 })
  Audio.archive = oldArchive
  legacy:play()
  threaded:play()
  local deadline2 = love.timer.getTime() + 10
  repeat
    threaded:update()
    love.timer.sleep(0.001)
  until #threaded.queue.buffers == 16 or love.timer.getTime() > deadline2
  check(#threaded.queue.buffers == 16, "DS queue did not reach its bounded depth")
  local offsets = { [legacy] = 0, [threaded] = 0 }
  local function step(player)
    offsets[player] = offsets[player] + 512
    local first = player.queue.buffers[1]
    while first and offsets[player] >= first:getSampleCount() do
      offsets[player] = offsets[player] - first:getSampleCount()
      table.remove(player.queue.buffers, 1)
      first = player.queue.buffers[1]
    end
    player:update()
  end
  return checks,
    {
      keepAlive = function()
        threaded:update()
      end,
      legacy = function()
        step(legacy)
      end,
      threaded = function()
        assert(rawget(threaded, "voices") == nil, "DS benchmark left the worker")
        step(threaded)
      end,
      close = function()
        legacy:stop()
        threaded:stop()
      end,
    }
end
