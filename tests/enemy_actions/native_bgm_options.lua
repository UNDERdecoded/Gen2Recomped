-- Engine options and real world actions entered from unchanged public hooks.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local Music = require("src.core.Music")
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local Json = require("src.link.Json")
  local function copy(value)
    return Json.decode(Json.encode(value))
  end
  local rows = {}
  for _, case in ipairs({
    "native-modes",
    "file-modes",
    "file-modes-out",
    "native-missing",
    "file-missing",
    "file-preserve-mode",
    "file-reentrant-native",
    "file-reentrant-shared",
    "file-reentrant-fanfare",
    "native-muted-fanfare",
    "native-registered",
    "file-preserve-game",
    "file-early-options",
  }) do
    if Music.setAudioMode then
      Music.setAudioMode("both")
    end
    local h = dofile(root .. "/tests/native_bgm/streams.lua").install(root, backend, version, f)
    local shared = case:sub(1, 4) == "file"
    if shared or case == "native-registered" then
      h.override("file")
      local songs = native and require("src.core.game3.mod_audio").data.audio.songs or f.data.audio.songs
      songs.MUS_SURF = { file = "owned-option-surf.ogg" }
    end
    local fanfares = case:find("fanfare") and h.fanfares() or nil
    local tick, mix, calls, frames = 0, {}, {}, {}
    local oldMix = love.audio.setMixWithSystem
    love.audio.setMixWithSystem = function(value)
      mix[#mix + 1] = { tick = tick, value = value }
    end
    local mixer = package.loaded["src.audio.AudioMix"]
    if mixer and mixer._resetForTest then
      mixer._resetForTest()
    end
    h.options({ musicVol = 7, audioMode = "both" })
    if case == "file-early-options" then
      h.options({ musicVol = 3, audioMode = "external_only" })
    end
    local entered = false
    local off = f.e.api.hooks:wrap("music.volume", function(next, value, context)
      if tick == 2 and not entered and case:find("reentrant") then
        entered = true
        if case == "file-reentrant-native" then
          h.start({ { "playbgm", h.ids[1], 0 }, { "fadeoutbgm", 4 }, { "end" } })
        elseif case == "file-reentrant-shared" then
          h.start({ { "playbgm", h.ids[3], 0 }, { "end" } })
        else
          h.start({ { "playfanfare", fanfares[1] }, { "end" } })
        end
      end
      local result = next(value, context)
      calls[#calls + 1] = { tick = tick, value = value, result = result, context = copy(context) }
      return result
    end)
    local script = { { "playbgm", h.ids[case == "native-registered" and 1 or 2], 0 } }
    if case == "file-modes-out" then
      script[#script + 1] = { "fadeoutbgm", 4 }
    end
    script[#script + 1] = { "end" }
    local runner = h.start(script)
    for frame = 0, 13 do
      tick = frame
      if case:find("reentrant") then
        if tick == 2 then
          h.options({ musicVol = 3, audioMode = "both" })
        end
      elseif case == "file-early-options" then
        if tick == 5 then
          h.options({ musicVol = 3, audioMode = "both" })
        end
      elseif case:find("missing") then
        if tick == 1 then
          h.options({ musicVol = 3, audioMode = "both" })
        elseif tick == 3 then
          h.options({ audioMode = "both" })
        elseif tick == 4 then
          h.start({ { "playbgm", h.ids[1], 0 }, { "fadeoutbgm", 4 }, { "end" } })
        end
      elseif case == "native-muted-fanfare" then
        if tick == 1 then
          h.options({ musicVol = 3, audioMode = "external_only" })
        elseif tick == 2 then
          h.start({ { "playfanfare", fanfares[1] }, { "end" } })
        end
      else
        if tick == 1 then
          h.options({
            musicVol = 3,
            audioMode = case == "file-preserve-game" and "game_only" or "external_only",
          })
        elseif tick == 3 then
          h.options(
            (case == "file-preserve-mode" or case == "file-preserve-game") and { musicVol = 5 }
              or { musicVol = 5, audioMode = "game_only" }
          )
        elseif tick == 5 or tick == 6 then
          h.options({ musicVol = 3, audioMode = "both" })
        elseif tick == 7 then
          h.options({ musicVol = 0, audioMode = "both" })
        elseif tick == 8 then
          h.options({ musicVol = 7, audioMode = "external_only" })
        elseif tick == 10 then
          h.options({ musicVol = 6, audioMode = "both" })
        end
      end
      if tick == 4 and case == "native-registered" then
        h.start({ { "playbgm", h.ids[2], 0 }, { "end" } })
      end
      local hardware = h.state()
      local active, muted = 0, true
      for _, source in ipairs(hardware.queues) do
        if source.playing then
          active = active + 1
          muted = muted and source.volume == 0
        end
      end
      local state = hardware.native
      state.physicalSong = nil
      frames[#frames + 1] = {
        tick = tick,
        state = state,
        running = runner:isRunning(),
        fanfare = fanfares and h.fanfareState(fanfares) or nil,
        nativeActive = active,
        nativeMuted = muted,
      }
      h.update()
    end
    rows[#rows + 1] = { case = case, calls = calls, frames = frames, mix = mix, entered = entered }
    off()
    love.audio.setMixWithSystem = oldMix
    h.close()
  end
  f.close()
  return rows
end
return M
