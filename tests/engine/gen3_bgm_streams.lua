package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Music = require("src.core.GameVersion"), require("src.core.Music")
local versionBefore = V.get()
for _, version in ipairs({ "firered", "emerald" }) do
  local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
  local function install(options)
    return dofile("tests/native_bgm/streams.lua").install(".", "gen2", version, f, options)
  end
  local h = install()
  local state = h.state()
  T.eq(state.queues[1].playing, false, "native cue waits for its audio service")
  T.eq(state.queues[1].queued, 0, "native cue construction synthesizes no lookahead")
  T.eq(require("src.core.ChipAudio").awaitingFirstBuffer(), true, "native startup is pending until serviced")
  h.update()
  T.eq(h.state().queues[1].queued, 1, "native service produces one buffer")
  T.eq(h.state().queues[1].playing, true, "first native buffer starts playback")
  T.eq(
    require("src.core.ChipAudio").awaitingFirstBuffer(),
    false,
    "serviced startup releases the pending state"
  )
  h.start({ { "fadeoutbgm", 4 }, { "end" } })
  for _ = 1, 63 do
    h.update()
  end
  local producedBeforeStop = h.state().queues[1].produced
  h.drain()
  h.update()
  state = h.state()
  T.eq(state.queues[1].playing, false, "completed outgoing fade stops the actual queue")
  T.eq(state.queues[1].queued, 0, "stopping clears pending native PCM")
  T.eq(state.queues[1].produced, producedBeforeStop, "final fade tick produces no buffer after its stop")
  T.eq(state.queues[1].plays, 1, "native fade never spuriously restarts its source")
  h.close()

  h = install({ finite = true })
  for _ = 1, 3 do
    h.update()
  end
  T.eq(h.state().queues[1].produced, 3, "finite native sequences retain their silent carrier until stopped")
  h.close()

  h = install()
  Music.reload()
  local a, b = h.ids[1], h.ids[2]
  f.data.audio.songs.MUS_TITLE = f.data.audio.songs[("SONG_%03X"):format(a)]
  f.data.audio.songs.MUS_CYCLING = f.data.audio.songs[("SONG_%03X"):format(b)]
  f.data.audio.mapSongs.OWNED_NATIVE_BGM_MAP = "MUS_TITLE"
  Music.playMap(f.data, "OWNED_NATIVE_BGM_MAP", false, false)
  state = h.state()
  T.eq(state.queues[#state.queues].playing, true, "named mod M4A extension retains shared immediate playback")
  T.eq(state.queues[#state.queues].queued, 4, "named mod M4A extension keeps its shared preroll")
  T.eq(state.queues[#state.queues].plays, 1, "Music never starts a chip source a second time")
  h.start({ { "playbgm", b, 0 }, { "fadedefaultbgm" }, { "end" } })
  T.eq(h.state().native.song, a, "named M4A mods do not allocate a native background carrier")
  T.eq(h.state().native.fadeOut, nil, "shared-only default restoration stays immediate")
  h.close()

  for _, failAfterBuffer in ipairs({ false, true }) do
    h = install()
    Music.stop()
    local originalChip = package.loaded["src.core.ChipAudio"]
    local oldThread = love.thread
    local channels, lastGen, workerError = {}, nil, nil
    local function channel(name)
      if not channels[name] then
        channels[name] = {
          values = {},
          push = function(self, value)
            if type(value) == "table" and value.cmd == "play" then
              lastGen = value.gen
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
      newThread = function()
        return {
          start = function() end,
          getError = function()
            return workerError
          end,
          wait = function() end,
        }
      end,
      getChannel = channel,
    }
    package.loaded["src.core.ChipAudio"] = nil
    local chip = require("src.core.ChipAudio")
    Music.playMap(f.data, "OWNED_NATIVE_BGM_MAP", false, false)
    local count = #h.state().queues
    T.eq(h.state().queues[count].playing, false, "native worker startup does not play an empty source")
    if failAfterBuffer then
      local def = f.data.audio.songs[("SONG_%03X"):format(a)]
      local engine = require("src.core.M4ASynth").newEngine(f.data, def)
      local sd = require("src.core.M4ASynth").soundData(engine, 8192, 2)
      channel("chipaudio_out"):push({ gen = lastGen + 1, sd = sd })
      h.update()
      T.eq(h.state().queues[count].queued, 0, "stale worker generations cannot enter the live native queue")
      h.start({ { "fadeoutbgm", 4 }, { "end" } })
      channel("chipaudio_out"):push({ gen = lastGen, sd = sd })
      h.update()
      local played = h.trace().queues[count].plays
      T.eq(#played, 1, "first matching native worker buffer starts exactly once")
      T.check(
        math.abs(played[1].volume - 0.7 * (1 - 1 / 64)) < 1e-12,
        "worker playback starts after this audio tick's fade gain"
      )
      h.drain()
    end
    workerError = "owned worker failure"
    h.update()
    h.update()
    state = h.state()
    T.eq(#state.queues, count, "worker fallback retains the native source owned by Music")
    T.eq(state.queues[count].playing, true, "worker fallback recovers the actual source")
    local expectedGain = 0.7 * (failAfterBuffer and (1 - 3 / 64) or 1)
    T.check(
      type(state.queues[count].volume) == "number"
        and math.abs(state.queues[count].volume - expectedGain) < 1e-12,
      "recovered source keeps the native gain and fade owner"
    )
    h.start({ { "playbgm", 0, 0 }, { "end" } })
    for _, voice in ipairs(h.state().queues) do
      T.eq(voice.playing, false, "native stop releases every worker/fallback source")
    end
    chip.shutdown()
    package.loaded["src.core.ChipAudio"] = originalChip
    love.thread = oldThread
    h.close()
  end
  f.close()
end
V.set(versionBefore)
T.finish("native BGM stream clocks, mod ownership and worker recovery")
