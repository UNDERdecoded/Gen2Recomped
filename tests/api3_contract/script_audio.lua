-- Real loaders/adapters; an explicit source/clock seam avoids audio-device timing.
local M = {}
function M.fixture(root, backend, version, modId, base)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_audio%.lua$")
  local f = base
    or dofile(codeRoot .. "/script_flags.lua").fixture(root, backend, version, modId or "script_audio")
  f.game.data.audio = {
    songs = { TUNE = { file = "tune.wav" }, JINGLE = { file = "jingle.wav" } },
    sfx = { CHIME = { file = "chime.wav" } },
    mapSongs = { [f.home] = "TUNE" },
  }
  f.audioTrace = {}
  f.source = { playing = false }
  function f.source:isPlaying()
    return self.playing
  end
  local Sound, Music = require("src.core.Sound"), require("src.core.Music")
  local restored = {}
  local function patch(module, key, fn)
    local old = module[key]
    restored[#restored + 1] = function()
      module[key] = old
    end
    module[key] = fn
  end
  local function sound(_, key)
    f.audioTrace[#f.audioTrace + 1] = { kind = "sound", id = key }
    f.source.playing = true
    return f.source
  end
  local function music(_, key, _, opts)
    f.audioTrace[#f.audioTrace + 1] = { kind = "music", id = key, keep = opts and opts.keep or false }
    f.current = key
  end
  local function stop()
    f.audioTrace[#f.audioTrace + 1] = { kind = "stop" }
    f.current = nil
    f.musicBusy = false
  end
  local function once(_, key)
    f.audioTrace[#f.audioTrace + 1] = { kind = "once", id = key }
    f.current = key
    f.musicBusy = true
    return true
  end
  local function fade(control)
    f.audioTrace[#f.audioTrace + 1] = { kind = "fade", control = control }
  end
  local function default(_, map)
    f.audioTrace[#f.audioTrace + 1] = { kind = "default", map = map }
  end
  patch(Sound, "play", sound)
  patch(Sound, "playNamedEffect", sound)
  patch(Sound, "sfxBusy", function()
    return f.otherBusy == true
  end)
  patch(Sound, "anyPlaying", function()
    return f.otherBusy == true
  end)
  patch(Music, "play", music)
  patch(Music, "stop", stop)
  patch(Music, "playOnce", once)
  patch(Music, "oneShotPlaying", function()
    return f.musicBusy
  end)
  patch(Music, "current", function()
    return f.current
  end)
  patch(Music, "fadeOut", fade)
  patch(Music, "playMap", default)
  function f.ow:playMapMusic()
    default(f.game.data, self.map.id)
  end
  if backend == "gen1" and f.gen == 3 then
    local Audio = require("src.core.game3.audio")
    patch(Audio, "songInfo", function(key)
      return f.game.data.audio.songs[key] or f.game.data.audio.sfx[key]
    end)
    patch(Audio, "resolveSong", function(key)
      return key
    end)
    patch(Audio, "playSe", function(key)
      return sound(f.game.data, key)
    end)
    patch(Audio, "isSePlaying", function()
      return f.source.playing or f.otherBusy == true
    end)
    patch(Audio, "playSong", function(key, opts)
      if key == 0 then
        return stop()
      end
      return music(f.game.data, key, nil, opts)
    end)
    patch(Audio, "playFanfare", function(key)
      return once(f.game.data, key)
    end)
    patch(Audio, "isFanfareFinished", function()
      return not f.musicBusy
    end)
    patch(Audio, "fadeOutBgm", fade)
    patch(Audio, "restoreMapSong", function()
      return default(f.game.data, f.ow.map.id)
    end)
  end
  f.restore = function()
    for i = #restored, 1, -1 do
      restored[i]()
    end
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  assert(f.exports.queue({
    { "play_sound", "CHIME" },
    { "wait_sound" },
    { "play_music", "TUNE", { keep = true } },
    { "fade_music", 2 },
    { "stop_music" },
    { "play_once", "JINGLE" },
    { "play_default_music" },
    { "set_flag", "mod:after" },
  }))
  for _ = 1, 3 do
    f:tick()
  end
  assert(f.exports.result().done == 0 and #f.audioTrace == 1)
  f.source.playing = false
  f.otherBusy = true
  for _ = 1, 3 do
    f:tick()
  end
  assert(#f.audioTrace == 1 and f.exports.result().done == 0)
  f.otherBusy = false
  for _ = 1, 20 do
    f:tick()
    if f.musicBusy then
      break
    end
  end
  assert(f.musicBusy and f.exports.result().done == 0)
  f.musicBusy = false
  f:drain()
  assert(f.exports.result().success and f.exports.get("mod:after"))
  local report = { trace = f.audioTrace, complete = true }
  f.restore()
  f = M.fixture(root, backend, version)
  local value, why = f.exports.queue({ { "play_sound", "CHIME" }, { "play_music", "" } })
  assert(value == nil and type(why) == "string" and #f.audioTrace == 0)
  report.preflight = true
  f.restore()
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
