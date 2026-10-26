-- One unchanged public API-3 mod registration observes real music services.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local rows = {}
  for _, case in ipairs({
    "native",
    "native-select",
    "native-volume",
    "native-map",
    "file",
    "file-select",
    "file-silence",
    "file-volume",
    "file-options",
    "file-options-out",
    "file-map",
    "file-map-fanfare",
    "file-out",
    "file-in",
    "file-repeat",
    "file-replace",
    "file-to-native",
    "file-fanfare",
    "file-failure",
    "file-location",
    "file-intro",
    "file-cry",
    "file-cry-stop",
  }) do
    local crying = case == "file-cry" or case == "file-cry-stop"
    local h, cryHardware
    if crying then
      -- Keep the owned cry image/pack intact. Only shared file transport is
      -- needed here; native carrier scenarios use the sequencer fixture.
      local base = dofile(root .. "/tests/native_bgm/fixture.lua").install(root, backend, version, f)
      cryHardware = base.hardware
      h = {
        ids = base.ids,
        start = base.start,
        update = base.update,
        close = base.close,
        options = base.options,
        endFiles = base.hardware.endSources,
        state = function()
          return { native = base.state() }
        end,
        override = function()
          local songs = native and require("src.core.game3.mod_audio").data.audio.songs or f.data.audio.songs
          songs.MUS_CYCLING = { file = "owned-bgm-stream-override.ogg" }
        end,
      }
    else
      h = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, f)
    end
    local shared = case:sub(1, 4) == "file"
    local fanfares = (case == "file-fanfare" or case == "file-map-fanfare") and h.fanfares() or nil
    local builder = love.audio.newSource
    if shared then
      h.override("file")
      local songs = native and require("src.core.game3.mod_audio").data.audio.songs or f.data.audio.songs
      songs.MUS_SURF = { file = "owned-hook-surf.ogg" }
      if case == "file-failure" then
        love.audio.newSource = function(input, ...)
          if input == "owned-bgm-stream-override.ogg" then
            error("owned file unavailable")
          end
          return builder(input, ...)
        end
      elseif case == "file-intro" then
        songs.MUS_CYCLING.loopFile = "owned-hook-loop.ogg"
      end
    end
    local Game, savedWorld, savedGame
    if case == "file-location" then
      -- Load the real engine object, rather than the read-only Game facade
      -- that a generation-3 mod's lazy require is allowed to receive.
      savedGame = package.loaded["src.core.Game"]
      Game = dofile("src/core/Game.lua")
      package.loaded["src.core.Game"] = Game
      savedWorld, Game.overworld =
        Game.overworld, {
          player = { cellX = 5, cellY = 6 },
          map = { id = "OWNED_HOOK_MAP" },
          tod = "night",
        }
    end
    local calls, frames, tick = {}, {}, 0
    local Json = require("src.link.Json")
    local function copy(value)
      return Json.decode(Json.encode(value))
    end
    local handles = {}
    handles[#handles + 1] = f.e.api.hooks:wrap("music.select", function(next, value, context)
      local selected = value
      if case == "file-silence" then
        selected = nil
      elseif case == "file-select" then
        selected = "MUS_SURF"
      elseif case == "native-select" then
        selected = "OWNED_MUST_NOT_SELECT_NATIVE"
      end
      local result = next(selected, context)
      calls[#calls + 1] =
        { name = "music.select", tick = tick, value = value, context = copy(context), result = result }
      return result
    end)
    handles[#handles + 1] = f.e.api.hooks:wrap("music.volume", function(next, value, context)
      local result =
        next((case == "file-volume" or case == "native-volume") and value * 0.5 or value, context)
      calls[#calls + 1] =
        { name = "music.volume", tick = tick, value = value, context = copy(context), result = result }
      return result
    end)
    for _, name in ipairs({ "music.started", "music.stopped" }) do
      handles[#handles + 1] = f.e.api.events:on(name, function(event)
        calls[#calls + 1] = { name = name, tick = tick, event = copy(event) }
      end)
    end
    local function mapCue()
      if native then
        require("src.core.game3.audio").playMapSong(h.ids[2], { mapSong = h.ids[2], exact = true })
      else
        f.data.audio.mapSongs.OWNED_HOOK_MAP = shared and "MUS_CYCLING" or ("SONG_%03X"):format(h.ids[2])
        require("src.core.Music").playMap(f.data, "OWNED_HOOK_MAP", true, true)
      end
    end
    local script = { { "playbgm", h.ids[case == "file-map-fanfare" and 1 or 2], 0 } }
    if case == "file-out" or case == "file-options-out" then
      script[#script + 1] = { "fadeoutbgm", 4 }
    elseif case == "file-in" then
      script[#script + 1] = { "fadeinbgm", 4 }
    end
    script[#script + 1] = { "end" }
    if case == "native-map" or case == "file-map" then
      mapCue()
    end
    local runner = h.start(script)
    local ticks = (case == "file-out" or case == "file-options-out") and 70 or crying and 17 or 9
    for frame = 0, ticks do
      tick = frame
      if tick == 2 then
        if case == "file-options" or case == "file-options-out" then
          h.options(3)
        elseif case == "file-repeat" then
          h.start({ { "playbgm", h.ids[2], 0 }, { "end" } })
        elseif case == "file-replace" then
          h.start({ { "playbgm", h.ids[3], 0 }, { "end" } })
        elseif case == "file-to-native" then
          h.start({ { "playbgm", h.ids[1], 0 }, { "end" } })
        elseif case == "file-fanfare" or case == "file-map-fanfare" then
          h.start({ { "playfanfare", fanfares[1] }, { "end" } })
          if case == "file-map-fanfare" then
            mapCue()
          end
        elseif crying then
          h.start({ { "playmoncry", 4, 0 }, { "end" } })
        end
      end
      if tick == 4 and case == "file-cry-stop" then
        cryHardware.stop()
      end
      if tick == 3 and case == "file-intro" then
        h.endFiles()
      end
      local state = h.state().native
      -- Physical native labels are internal to the engines. Compare the
      -- actual native producer identity and every public music callback.
      state.physicalSong = nil
      local producer
      if native then
        local slot = require("src.core.game3.audio")._bgmLocal
        producer = slot and slot.songId
      elseif require("src.core.ChipAudio").nativeBgmState() then
        local label = require("src.core.Music").current()
        producer = type(label) == "string" and tonumber(label:match("^SONG_(%x+)$") or "", 16) or nil
      end
      frames[#frames + 1] = { tick = tick, state = state, producer = producer, running = runner:isRunning() }
      h.update()
    end
    local samples
    if crying then
      for _, play in ipairs(cryHardware.trace()) do
        if play.samples then
          samples = #play.samples
        end
      end
      assert(samples and samples > 1000, "the world command must render an actual owned cry")
    end
    rows[#rows + 1] = { case = case, calls = calls, frames = frames, crySamples = samples }
    for _, unsubscribe in ipairs(handles) do
      unsubscribe()
    end
    if Game then
      Game.overworld = savedWorld
      package.loaded["src.core.Game"] = savedGame
    end
    love.audio.newSource = builder
    h.close()
  end
  f.close()
  return rows
end
return M
