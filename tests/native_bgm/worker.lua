local M = {}
-- Execute the actual worker body with owned PCM and controlled channels.
-- No worker handler or synthesis method is replaced.
function M.actual(data, header, T)
  local commands, output, packets, sleeps = {}, {}, {}, 0
  local cmd = {
    pop = function()
      return table.remove(commands, 1)
    end,
  }
  local out = {
    clear = function()
      output = {}
    end,
    getCount = function()
      return #output
    end,
    push = function(_, value)
      output[#output + 1] = value
      if value.sd then
        packets[#packets + 1] = value
        commands[#commands + 1] = #packets == 1 and { cmd = "nativePause", gen = 41, nativeEpoch = 1 }
          or { cmd = "quit" }
      end
    end,
  }
  commands[1] =
    { cmd = "play", gen = 41, header = header, synth = "m4a", allowLoops = true, audio = data.audio }
  local workerLove = {
    thread = {
      getChannel = function(name)
        return name == "chipaudio_cmd" and cmd or out
      end,
    },
    sound = love.sound,
    filesystem = {
      load = function(path)
        local name = path:gsub("%.lua$", ""):gsub("/", ".")
        return function()
          return require(name)
        end
      end,
    },
    timer = {
      sleep = function()
        sleeps = sleeps + 1
        assert(sleeps <= 2, "native worker failed to resume")
        T.eq(#packets, 1, "paused real worker produces no PCM, including after a stale resume")
        commands[#commands + 1] = { cmd = "nativeResume", gen = 41, nativeEpoch = sleeps == 1 and 0 or 1 }
      end,
    },
  }
  local environment = setmetatable({ love = workerLove, package = { preload = {} } }, { __index = _G })
  environment.require = function(name)
    local component = name:match("^love%.(.+)$")
    if component then
      return workerLove[component]
    end
    return require(name)
  end
  local chunk = assert(loadfile("src/core/chip_worker.lua"))
  setfenv(chunk, environment)
  chunk()
  T.eq(sleeps, 2, "real worker ignores the stale pause epoch")
  T.eq(#packets, 2, "real worker emits only pre-pause and resumed PCM")
  T.eq(packets[1].nativeEpoch, 0, "initial real worker PCM retains its native epoch")
  T.eq(packets[2].nativeEpoch, 1, "resumed real worker PCM has the new native epoch")
  T.eq(packets[2].sd:getSampleCount(), 8192, "resumed worker uses the actual M4A renderer")
end

function M.transport(h, f, ff, T)
  local Music = require("src.core.Music")
  Music.stop()
  local savedChip, oldThread = package.loaded["src.core.ChipAudio"], love.thread
  local channels, gen = {}, nil
  local function channel(name)
    if not channels[name] then
      channels[name] = {
        values = {},
        push = function(self, value)
          if type(value) == "table" and value.cmd == "play" then
            gen = value.gen
          end
          self.values[#self.values + 1] = value
        end,
        pop = function(self)
          return table.remove(self.values, 1)
        end,
        clear = function(self)
          self.values = {}
        end,
      }
    end
    return channels[name]
  end
  love.thread = {
    getChannel = channel,
    newThread = function()
      return { start = function() end, getError = function() end, wait = function() end }
    end,
  }
  package.loaded["src.core.ChipAudio"] = nil
  local chip = require("src.core.ChipAudio")
  Music.playMap(f.data, "OWNED_NATIVE_BGM_MAP", false, false)
  local count = #h.state().queues
  local def = f.data.audio.songs[("SONG_%03X"):format(h.ids[1])]
  local synth = require("src.core.M4ASynth")
  local sd = synth.soundData(synth.newEngine(f.data, def), 8192, 2)
  channel("chipaudio_out"):push({ gen = gen, nativeEpoch = 0, sd = sd })
  h.update()
  T.eq(h.state().queues[count].queued, 1, "owned worker stream is sounding before the fanfare")
  h.start({ { "playfanfare", ff[1] }, { "end" } })
  T.eq(chip.nativeBgmState().paused, true, "native fanfare pauses the actual worker stream")
  T.eq(h.state().queues[count].queued, 0, "native pause clears already queued PCM")
  channel("chipaudio_out"):push({ gen = gen, nativeEpoch = 0, sd = sd })
  for _ = 1, 4 do
    h.update()
  end
  T.eq(chip.nativeBgmState().paused, false, "native timer releases its worker stream")
  T.eq(h.state().queues[count].queued, 0, "packet from before the pause cannot re-enter the resumed source")
  channel("chipaudio_out"):push({ gen = gen, nativeEpoch = 0, sd = sd })
  channel("chipaudio_out"):push({ gen = gen, nativeEpoch = 1, sd = sd })
  h.update()
  T.eq(h.state().queues[count].queued, 1, "resumed source accepts only its current pause epoch")
  T.eq(h.state().queues[count].produced, 2, "fanfare pause consumes no extra worker PCM")
  chip.shutdown()
  package.loaded["src.core.ChipAudio"] = savedChip
  love.thread = oldThread
end
return M
