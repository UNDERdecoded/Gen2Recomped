package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local oldAudio, oldSound = love.audio, love.sound.newSoundData
love.audio = {
  newSource = function(input)
    return { input = input }
  end,
}
local hardware = dofile("tests/native_bgm/sounddata.lua").install()
local sd = love.sound.newSoundData(2, 22050, 16, 2)
T.eq(type(sd), "userdata", "hardware shape reaches the production native userdata admission")
sd:setSample(0, 1, -0.5)
sd:setSample(0, 2, 0.75)
T.eq(sd:getSample(0, 1), -0.5, "userdata keeps the rendered left sample")
T.eq(sd:getSample(0, 2), 0.75, "userdata keeps the rendered right sample")
T.eq(sd:getSampleCount(), 2, "userdata preserves frame count")
T.eq(sd:getSampleRate(), 22050, "userdata preserves sample rate")
T.eq(sd:getBitDepth(), 16, "userdata preserves bit depth")
T.eq(sd:getChannelCount(), 2, "userdata preserves channel count")
local src = love.audio.newSource(sd, "static")
T.eq(src.input:getSample(0, 2), 0.75, "CPU Source traces the actual backing samples")
T.eq(hardware.created, 1, "construction is counted without creating a real audio device")
T.eq(hardware.staticInputs, 1, "static sources receive userdata before tracing")
hardware.close()
T.eq(love.sound.newSoundData, oldSound, "hardware fixture restores the SoundData constructor")
love.audio = oldAudio
local V, Music = require("src.core.GameVersion"), require("src.core.Music")
local versionBefore = V.get()
for _, version in ipairs({ "firered", "emerald" }) do
  local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
  local h = dofile("tests/native_bgm/streams.lua").install(".", "gen2", version, f)
  local ids = h.fanfares()
  T.eq(h.soundData.staticInputs, 0, "cold definitions do not render or create static Sources")
  local function start()
    return h.start({ { "playfanfare", ids[1] }, { "waitfanfare" }, { "end" } })
  end
  local runner = start()
  T.eq(h.soundData.staticInputs, 1, "first public cue renders cold userdata PCM")
  T.eq(runner:isRunning(), true, "public native wait blocks on the real fanfare clock")
  local samples, audible = 0, false
  for _, source in ipairs(h.trace().files) do
    for _, frame in ipairs(source.samples or {}) do
      samples = samples + #frame
      for _, value in ipairs(frame) do
        audible = audible or value ~= 0
      end
    end
  end
  T.check(samples > 0 and audible, "cold renderer emits real audible PCM in the full trace")
  for _ = 1, 4 do
    h.update()
    runner:update()
  end
  T.eq(runner:isRunning(), false, "cold public wait finishes after four audio ticks")
  start()
  T.eq(h.soundData.staticInputs, 1, "same-session replay uses the native static source cache")
  Music.reload()
  runner = start()
  T.eq(h.soundData.staticInputs, 2, "reload constructs a new cold Source instead of reusing the old session")
  T.eq(h.fanfareState(ids).se.first, true, "fresh cold replay owns the real native SE player")
  local static = h.soundData.sources[#h.soundData.sources]
  local play, playing = static.play, static.isPlaying
  static.play, static.isPlaying =
    function()
      error("owned invalid static source")
    end, function()
      error("owned invalid static source")
    end
  T.eq(pcall(start), true, "an invalid cached static source cannot crash a native script")
  T.eq(h.fanfareState(ids).se.first, false, "a refusing static source cannot report audible SE activity")
  static.play, static.isPlaying = play, playing
  start()
  T.eq(h.soundData.staticInputs, 2, "a transient static failure does not poison its same-session cache")
  T.eq(h.fanfareState(ids).se.first, true, "the cached static source can recover on the next real cue")
  Music.stop()
  h.start({ { "playbgm", h.ids[1], 0 }, { "end" } })
  h.update()
  local restored = h.invalidateQueues()
  T.eq(pcall(h.update), true, "a live source becoming invalid cannot crash the next audio update")
  T.eq(
    pcall(h.start, { { "fadeoutbgm", 4 }, { "end" } }),
    true,
    "world commands remain callable while the output handle refuses every audio method"
  )
  local platform = require("src.core.Platform").detect()
  local mobile = platform.mobile
  platform.mobile = true
  local game = setmetatable({ data = f.data }, { __index = require("src.core.Game") })
  T.eq(
    pcall(game.audioSession, game, false, "owned invalid device"),
    true,
    "actual Game can suspend invalid handles"
  )
  h.queueDevice("nil")
  T.eq(
    pcall(game.audioSession, game, true, "owned invalid device"),
    true,
    "foreground handles an unavailable replacement device"
  )
  restored()
  h.queueDevice(nil)
  for _ = 1, 60 do
    h.update()
  end
  T.eq(Music.current(), ("SONG_%03X"):format(h.ids[1]), "foreground retry uses the current Game dataset")
  local queues = h.state().queues
  T.eq(queues[#queues].playing, true, "foreground retry creates a healthy native stream")
  for index = 1, #queues - 1 do
    T.eq(queues[index].playing, false, "old-session native handles cannot resume behind the replacement")
  end
  platform.mobile = mobile
  local ending = h.start({
    { "playbgm", h.ids[2], 1 },
    { "savebgm", h.ids[3] },
    { "playfanfare", ids[1] },
    { "waitfanfare" },
    { "end" },
  })
  local endedWait = assert(Music.nativeWaitFanfare())
  T.eq(Music.nativeSnapshot().savedSong, h.ids[3], "ending session owns a saved native song")
  T.eq(ending:isRunning(), true, "ending session has a live native audio wait")
  -- The actual launcher boot and mod reload use this bus; do not call
  -- Music.reload ourselves and hide a missing production registration.
  require("src.render.Assets").invalidate()
  T.eq(Music.nativeSnapshot().song, nil, "asset-entry invalidation retires the native song")
  T.eq(Music.nativeSnapshot().mapSong, nil, "asset-entry invalidation retires native map ownership")
  T.eq(Music.nativeSnapshot().savedSong, nil, "asset-entry invalidation retires the old saved song")
  T.eq(endedWait(), true, "asset-entry invalidation releases the previous session's native wait")
  ending:update()
  T.eq(ending:isRunning(), false, "the previous session's actual VM finishes before fresh entry")
  local retired = h.state()
  local sourcesStopped, queuesStopped = true, true
  for _, voice in ipairs(retired.native.voices) do
    sourcesStopped = sourcesStopped and not voice.playing
  end
  for _, queue in ipairs(retired.queues) do
    queuesStopped = queuesStopped and not queue.playing
  end
  T.eq(sourcesStopped, true, "asset-entry invalidation stops every old static source")
  T.eq(queuesStopped, true, "asset-entry invalidation stops every old streaming source")
  h.close()
  f.close()
end
V.set(versionBefore)
T.finish("native cold userdata PCM, cache admission and session reload")
