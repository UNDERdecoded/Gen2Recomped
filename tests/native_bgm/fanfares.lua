local M = {}
function M.install(root, backend, version, f, options)
  options = options or {}
  local native = backend == "gen1"
  local h = dofile(root .. "/tests/native_bgm/fixture.lua").install(root, backend, version, f)
  local Audio = native and require("src.core.game3.audio")
  local function resolve(name)
    return native and Audio.resolveSong(name) or require("src.core.Gen3SongIds").resolve(name, version)
  end
  local ids = { resolve("MUS_LEVEL_UP"), resolve("MUS_OBTAIN_ITEM") }
  local rows = {
    LEVEL_UP = { index = ids[1], frames = options.frames or 4 },
    ITEM = { index = ids[2], frames = 6 },
  }
  if options.emptyTable then
    rows = {}
  end
  if native then
    Audio._ready = false
    Audio._fanfareFrames, Audio._fanfareRestore, Audio._bgmPaused = 0, nil, false
    Audio._waitFanfareCb = nil
    Audio._pack.index.fanfares = nil
    Audio._pack.index.songs = {}
    if not options.noTable then
      Audio._pack.index.fanfares = {}
      for _, row in pairs(rows) do
        Audio._pack.index.fanfares[row.index] = row
      end
    end
    if options.songFrames then
      Audio._pack.index.songs[ids[1]] = { fanfareFrames = options.songFrames }
    end
  else
    f.data.audio.gen3 = nil
    f.data.constants.gen3Fanfares = nil
    if not options.noTable then
      f.data.constants.gen3Fanfares = { fanfares = rows }
    end
    if options.songFrames then
      f.data.audio.songs[("SONG_%03X"):format(ids[1])] = { fanfareFrames = options.songFrames }
    end
  end
  local Music = require("src.core.Music")
  return {
    ids = ids,
    bgmIds = h.ids,
    start = h.start,
    tick = h.tick,
    update = h.update,
    trace = h.trace,
    state = function()
      local state = h.state()
      if native then
        state.fanfare = {
          active = Audio._fanfareActive,
          frames = Audio._fanfareFrames,
          restore = Audio._fanfareRestore,
          paused = Audio._bgmPaused,
        }
        state.finished = Audio.isFanfareFinished()
        state.clock = Audio._cryClock
      else
        state.fanfare = Music.nativeFanfareSnapshot and Music.nativeFanfareSnapshot() or nil
        if Music.nativeFanfareFinished then
          state.finished = Music.nativeFanfareFinished()
        else
          state.finished = not Music.oneShotPlaying()
        end
        state.clock = require("src.core.NativeCryPlayer").snapshot().clock
      end
      return state
    end,
    value = function(runner, id)
      if native then
        return require("src.core.game3.scripting.flags").getVar(runner.store, runner.ctx, id or 0x4001)
      end
      return require("src.script.Gen3Commands").getVar(f.game.save, id or 0x4001)
    end,
    clear = function()
      if not native then
        require("src.script.Gen3Commands").setVar(f.game.save, 0x4001, 0)
      end
    end,
    close = h.close,
  }
end
return M
