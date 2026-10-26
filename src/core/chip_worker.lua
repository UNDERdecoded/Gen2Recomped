-- ChipAudio synthesis worker (love.thread).  Runs the Game Boy audio synth
-- (src/core/ChipSynth.lua) off the main thread so a map/battle song change
-- never stutters the render thread: filling the ~6s playback queue from
-- scratch is ~200ms of Lua synthesis, and this is where it now happens.
--
-- Protocol -- main thread pushes command tables onto the "chipaudio_cmd"
-- channel and drains produced buffers off "chipaudio_out":
--   cmd = "play"  { gen, header, allowLoops, audio,
--                   channelVolumes?, channelPitches? }
--   cmd = "stop"                                       halt production
--   cmd = "channelMix" { volumes, pitches }            per-hw volume/pitch
--   cmd = "invalidate"                                 drop the bank cache
--   cmd = "quit"                                        end the thread
-- out buffers are tagged with the play's `gen` so the main thread can
-- discard anything left over from a superseded song:
--   { gen, sd = SoundData }   one rendered buffer
--   { gen, done = true }      the song ended (non-looping jingle finished)
--   { gen, error = msg }      build/synth failed; main logs and gives up

require("love.thread")
require("love.timer")
require("love.sound")
require("love.data")
require("love.filesystem")
package.preload["src.core.WorkerFs"]=function()
  return assert(love.filesystem.load("src/core/WorkerFs.lua"))()
end
for _, name in ipairs({ "Performance", "AudioPcm" }) do
  local module = name
  package.preload["src.core." .. module] = function()
    return assert(love.filesystem.load("src/core/" .. module .. ".lua"))()
  end
end

for _,path in ipairs({"src.core.FrameProfile","src.core.Logger","src.import.Gen4Sdat",
    "src.audio.NitroSequence","src.audio.NitroTransport","src.audio.NitroAudio","src.audio.NitroWorker"})do
  local name=path
  package.preload[name]=function()
    return assert(love.filesystem.load(name:gsub("%.","/")..".lua"))()
  end
end
local Nitro

-- Load the synth explicitly via love.filesystem (a fresh thread Lua state does
-- not necessarily carry the package searcher that resolves "src.core..."):
local ChipSynth = assert(love.filesystem.load("src/core/ChipSynth.lua"))()

-- ...and the Gen 3 one beside it, loaded only when a song asks for it: a Gen
-- 1/Gen 2 build never touches it, and a dataset with no music image would
-- raise on construction rather than on load.
local SYNTHS = { chip = ChipSynth }
local SYNTH_FILES = { m4a = "src/core/M4ASynth.lua" }

local function synthFor(name)
  local hit = SYNTHS[name or "chip"]
  if hit then return hit end
  local file = SYNTH_FILES[name]
  if not file then return ChipSynth end
  local ok, chunk = pcall(love.filesystem.load, file)
  if not ok or not chunk then return ChipSynth end
  local built, synth = pcall(chunk)
  if not built or type(synth) ~= "table" then return ChipSynth end
  SYNTHS[name] = synth
  return synth
end

local cmdCh = love.thread.getChannel("chipaudio_cmd")
local outCh = love.thread.getChannel("chipaudio_out")

local fxCh = love.thread.getChannel("chipaudio_fx")
local fxJobs, fxGeneration = {}, 1
local function renderFx(job)
  local spec = job.spec
  local perf=require("src.core.Performance")
  local priorOptimization=perf.audioWorkerOptimization
  local volumes, pitches, stereo = ChipSynth.getChannelVolumes(), ChipSynth.getChannelPitches(), ChipSynth.getStereo()
  ChipSynth.setChannelVolumes(spec.volumes)
  ChipSynth.setChannelPitches(spec.pitches)
  ChipSynth.setStereo(spec.stereo)
  require("src.core.Performance").audioWorkerOptimization = job.audioWorkerOptimization ~= false
  local ok, sd = pcall(function()
    local input = { audio = spec.audio }
    if spec.kind == "chip" then
      return ChipSynth.renderEffectData(input, spec.header, spec.options)
    elseif spec.kind == "m4a" then
      return synthFor("m4a").renderEffect(input, spec.header)
    elseif spec.kind == "cry" then
      return synthFor("m4a").renderCry(input, spec.index)
    end
    error("unknown effect job")
  end)
  perf.audioWorkerOptimization=priorOptimization
  ChipSynth.setChannelVolumes(volumes)
  ChipSynth.setChannelPitches(pitches)
  ChipSynth.setStereo(stereo)
  fxCh:push({ generation = job.generation, id = job.id, sd = ok and sd or nil, error = not ok and tostring(sd) or nil })
end

local BUF = ChipSynth.MUSIC_BUFFER_SAMPLES
-- how many finished buffers may sit in the hand-off channel before the worker
-- pauses.  The deep (~6s) playback depth lives in the main-thread Source; this
-- only bounds the worker's look-ahead (and its memory) between drains.
local LOOKAHEAD = 8

local gen = nil        -- active song generation, or nil when stopped
local engine = nil     -- the engine producing the current song
local synth = ChipSynth -- ...and which module built it
local finished = false -- the current song ran out (non-looping)
local data = nil       -- { audio = <slim audio tables> } for ROM bank/wave reads

local function handle(cmd)
  if cmd.cmd == "performance" then
    require("src.core.Performance").audioWorkerOptimization=cmd.enabled
  elseif cmd.cmd == "nitro" then
    if not Nitro then Nitro=require("src.audio.NitroWorker") end
    local ok,why=pcall(Nitro.command,cmd)
    if not ok and cmd.id then
      love.thread.getChannel("chipaudio_nds_"..cmd.id):push({gen=cmd.gen,error=tostring(why)})
    end
  elseif cmd.cmd == "fx" then
    if cmd.generation == fxGeneration and #fxJobs < 2 then
      fxJobs[#fxJobs + 1] = cmd
    end
  elseif cmd.cmd == "fxCancel" then
    fxGeneration = cmd.generation
    fxJobs = {}
    fxCh:clear()
  elseif cmd.cmd == "play" then
    require("src.core.Performance").audioWorkerOptimization = cmd.audioWorkerOptimization ~= false
    ChipSynth.setStereo(cmd.stereo)
    gen = cmd.gen
    finished = false
    engine = nil
    outCh:clear() -- drop any buffers left from the previous song
    data = { audio = cmd.audio }
    if cmd.channelVolumes ~= nil then
      ChipSynth.setChannelVolumes(cmd.channelVolumes)
    end
    if cmd.channelPitches ~= nil then
      ChipSynth.setChannelPitches(cmd.channelPitches)
    end
    synth = synthFor(cmd.synth)
    local ok, eng = pcall(synth.newEngine, data, cmd.header,
                          { allowLoops = cmd.allowLoops })
    if ok then
      engine = eng
    else
      outCh:push({ gen = gen, error = tostring(eng) })
      finished = true
    end
  elseif cmd.cmd == "stop" then
    gen = nil
    engine = nil
    finished = false
    outCh:clear()
  elseif cmd.cmd == "channelMix" then
    ChipSynth.setStereo(cmd.stereo)
    if cmd.volumes ~= nil then ChipSynth.setChannelVolumes(cmd.volumes) end
    if cmd.pitches ~= nil then ChipSynth.setChannelPitches(cmd.pitches) end
  elseif cmd.cmd == "invalidate" then
    ChipSynth.invalidateBanks()
    for _, s in pairs(SYNTHS) do
      if s.invalidate then pcall(s.invalidate) end
    end
  elseif cmd.cmd == "quit" then
    return true
  end
  return false
end

while true do
  -- drain every pending command first, so a stop/new-play is seen promptly
  local quit = false
  local cmd = cmdCh:pop()
  while cmd do
    if handle(cmd) then quit = true end
    cmd = cmdCh:pop()
  end
  if quit then break end

  if engine and not finished and gen and outCh:getCount() < LOOKAHEAD then
    local activeGen = gen
    local ok, sd = pcall((synth or ChipSynth).soundData, engine, BUF, 2)
    if not ok then
      outCh:push({ gen = activeGen, error = tostring(sd) })
      finished = true
    else
      outCh:push({ gen = activeGen, sd = sd })
      if engine:finished() then
        outCh:push({ gen = activeGen, done = true })
        finished = true
      end
    end
  elseif #fxJobs == 0 then
    -- nothing to do (idle, or the look-ahead is full): yield the core
    love.timer.sleep(0.001)
  end
  -- At most one effect between music buffers, so prewarming cannot monopolize
  -- the worker while a streaming source needs its next buffer.
  if #fxJobs > 0 and fxCh:getCount() < 2 then
    renderFx(table.remove(fxJobs, 1))
  end
  if Nitro then Nitro.step() end
end
