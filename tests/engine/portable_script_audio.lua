package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_audio")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(v)
  return Contract.fixture("tests/api3_contract", "gen2", v or "red")
end
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " shared audio contract: " .. tostring(why))
end
for _, rows in ipairs({
  { { "set_flag", "mod:prefix" }, { "play_sound", "UNKNOWN" } },
  { { "play_music", "UNKNOWN" } },
  { { "play_once", "UNKNOWN" } },
  { { "play_sound", "" } },
  { { "play_music", "TUNE", { keep = "yes" } } },
  { { "play_music", "TUNE", { volume = 1 } } },
  { { "fade_music", -1 } },
  { { "fade_music", 256 } },
  { { "wait_sound", 1 } },
  { { "stop_music", false } },
}) do
  local f = fixture()
  T.eq(f.exports.queue(rows), nil, "invalid audio preflight")
  T.eq(f.exports.get("mod:prefix"), false, "invalid audio suffix prevents prefix")
  T.eq(#f.audioTrace, 0, "preflight plays no cue")
  f.restore()
end
for _, phase in ipairs({ "sound", "once" }) do
  for _, change in ipairs({ "rollback", "save", "data", "map" }) do
    local f = fixture()
    local original = f.ow.runner
    local first = phase == "sound" and { "play_sound", "CHIME" } or { "play_once", "JINGLE" }
    local rows = phase == "sound" and { first, { "wait_sound" }, { "set_flag", "mod:after" } }
      or { first, { "set_flag", "mod:after" } }
    T.check(f.exports.queue(rows), "audio admitted before context change")
    if change == "rollback" then
      f.loader:_rollback("script_audio")
    elseif change == "map" then
      f.ow.map = { id = f.home }
    else
      f.game[change] = {}
    end
    f:tick()
    f.source.playing = false
    f.musicBusy = false
    f:tick()
    T.eq(f.exports.result().success, false, "retired audio wait fails script")
    T.eq(f.exports.result().done, 1, "retired audio finishes once")
    T.eq(f.ow.runner, original, "retired audio restores idle runner")
    T.eq(#f.audioTrace, 1, "retirement adds no audio or later effects")
    f.restore()
  end
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "play_sound", "CHIME" }, { "wait_sound" }, { "set_flag", "mod:after" } }),
    "sound timeout admitted"
  )
  for _ = 1, 600 do
    f:tick()
  end
  T.eq(f.exports.result().success, true, "600-frame sound ceiling releases native wait")
  T.eq(f.exports.get("mod:after"), true, "sound timeout keeps native continuation behavior")
  f.restore()
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "play_once", "JINGLE" }, { "set_flag", "mod:after" } }),
    "stalled fanfare admitted"
  )
  for _ = 1, 3600 do
    f:tick()
  end
  T.eq(f.exports.result().success, false, "stalled one-shot fails at bounded deadline")
  T.eq(f.exports.get("mod:after"), false, "stalled one-shot cannot burn later flag")
  f.restore()
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "play_once", "JINGLE" }, { "set_flag", "mod:after" } }),
    "one-shot before foreign music"
  )
  f.current = "FOREIGN"
  f:drain()
  T.eq(f.exports.result().success, true, "one-shot does not wait on a replacement song")
  T.eq(f.current, "FOREIGN", "replacement song retained")
  f.restore()
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "play_sound", "CHIME" }, { "wait_sound" }, { "set_flag", "mod:after" } }),
    "sound before overlay"
  )
  f.source.playing = false
  f.game.stack.states[2] = {}
  for _ = 1, 5 do
    f:tick()
  end
  T.eq(f.exports.get("mod:after"), false, "audio continuation pauses beneath overlay")
  f.game.stack.states[2] = nil
  f:drain()
  T.eq(f.exports.get("mod:after"), true, "audio resumes in foreground")
  f.restore()
end
for _, v in ipairs({ "firered", "emerald" }) do
  local f = fixture(v)
  f.game.data.audio.songs.SONG_007 = { index = 7, musName = "MUS_TEST", sfxName = "SE_TEST", tracks = {} }
  f.game.data.audio.sfx.Get_Item1 = { m4a = 7, song = "SONG_007" }
  T.check(
    f.exports.queue({
      { "play_sound", "SE_TEST" },
      { "wait_sound" },
      { "play_music", 7 },
      {
        "play_once",
        "Get_Item1",
      },
    }),
    "native Gen3 names/number/fanfare role admitted"
  )
  T.eq(f.audioTrace[1].id, "SONG_007", "native sequence resolved for effect")
  f.source.playing = false
  for _ = 1, 5 do
    f:tick()
  end
  T.eq(f.audioTrace[2].id, "SONG_007", "numeric music id resolved")
  T.eq(f.audioTrace[3].id, "SONG_007", "native obtain-item fanfare role resolved")
  f.musicBusy = false
  f:drain()
  T.eq(f.exports.result().success, true, "native Gen3 resolved sequence completes")
  f.restore()
  f = fixture(v)
  f.game.data.audio.songs.A = { index = 7, musName = "MUS_DUP" }
  f.game.data.audio.songs.B = { index = 8, musName = "MUS_DUP" }
  T.eq(
    f.exports.queue({ { "set_flag", "mod:prefix" }, { "play_music", "MUS_DUP" } }),
    nil,
    "ambiguous sequence name preflight"
  )
  T.eq(f.exports.get("mod:prefix"), false, "ambiguous cue prevents prefix")
  T.check(f.exports.queue({ { "play_music", 0 } }), "Gen3 native zero music id admitted")
  T.eq(f.audioTrace[1].kind, "stop", "Gen3 native zero means stop")
  f.restore()
end
do
  local f = fixture()
  local opts = { keep = true, reason = "script" }
  T.check(
    f.exports.queue({ { "wait", 1 }, { "play_music", "TUNE", opts } }),
    "music options snapshot admitted"
  )
  opts.keep = false
  f:drain()
  T.eq(f.ow.keepMusicOnce, true, "caller cannot mutate queued music options")
  f.restore()
end
do
  local f = fixture()
  T.check(f.exports.queue({ { "wait", 1 }, { "play_music", "TUNE" } }), "deferred cue admitted")
  f.game.data.audio.songs.TUNE = nil
  f:drain()
  T.eq(f.exports.result().success, false, "live missing cue fails dispatch")
  T.eq(#f.audioTrace, 0, "missing live cue does not play")
  f.restore()
end
do
  local f = fixture()
  local Music = require("src.core.Music")
  local native = Music.play
  Music.play = function(...)
    native(...)
    f.loader:_rollback("script_audio")
  end
  T.check(
    f.exports.queue({ { "play_music", "TUNE", { keep = true } }, { "set_flag", "mod:after" } }),
    "retirement during native music admitted"
  )
  T.eq(f.exports.result().success, false, "music callback retirement cancels script")
  T.eq(f.ow.keepMusicOnce, nil, "retired cue cannot arm a later warp's music flag")
  T.eq(#f.audioTrace, 1, "already committed native cue is retained")
  f.restore()
end
for _, v in ipairs({ "firered", "emerald" }) do
  local f = fixture(v)
  T.eq(
    f.exports.queue({ { "set_flag", "mod:prefix" }, { "play_music", "MUS_UNKNOWN" } }),
    nil,
    "unknown Gen3 cue refused before prefix"
  )
  T.eq(f.exports.get("mod:prefix"), false, "Gen3 cue refusal has no prefix")
  f.game.data.audio.songs.TUNE = false
  T.eq(f.exports.queue({ { "play_music", "TUNE" } }), nil, "disabled cue not accepted as a definition")
  f.restore()
end
-- Native Sound file/effect dispatch, with only the actual device replaced.
do
  love = require("tests.love_stub")
  local Sound = require("src.core.Sound")
  local previousAudio = love.audio
  local calls = 0
  local src = {
    playing = false,
    setVolume = function() end,
    stop = function(self)
      self.playing = false
    end,
    play = function(self)
      self.playing = true
    end,
    isPlaying = function(self)
      return self.playing
    end,
  }
  love.audio = {
    newSource = function(file, kind)
      T.eq(file, "native-cue.wav", "native file cue passed to device")
      calls = calls + 1
      return src
    end,
  }
  local data = { audio = { songs = { PORTABLE_NATIVE_FILE = { file = "native-cue.wav" } } } }
  T.eq(Sound.playNamedEffect(data, "PORTABLE_NATIVE_FILE"), src, "native helper returns started source")
  T.eq(calls, 1, "native helper builds source once")
  T.eq(Sound.playNamedEffect(data, "PORTABLE_NATIVE_FILE"), src, "native helper reuses native cache")
  T.eq(calls, 1, "native helper preserves cache")
  Sound.invalidate("PORTABLE_NATIVE_FILE")
  love.audio = previousAudio
end
-- Actual native music one-shot and restore state; only the device is a seam.
do
  local f = fixture()
  f.restore()
  love = require("tests.love_stub")
  local previousAudio = love.audio
  local src = {
    playing = false,
    setVolume = function() end,
    setLooping = function() end,
    setPitch = function() end,
    stop = function(self)
      self.playing = false
    end,
    play = function(self)
      self.playing = true
    end,
    isPlaying = function(self)
      return self.playing
    end,
  }
  love.audio = {
    newSource = function(file)
      T.eq(file, "native-jingle.wav", "native music resolves file definition")
      return src
    end,
  }
  local Music = require("src.core.Music")
  Music.stop()
  f.game.data.audio.songs.JINGLE = { file = "native-jingle.wav" }
  T.check(
    f.exports.queue({ { "play_once", "JINGLE" }, { "set_flag", "mod:after" } }),
    "native music one-shot admitted"
  )
  T.eq(Music.current(), "JINGLE", "native music controller owns current jingle")
  T.eq(Music.oneShotPlaying(), true, "native music pending restore retained")
  for _ = 1, 3 do
    f:tick()
  end
  T.eq(f.exports.get("mod:after"), false, "script waits on actual native restore state")
  src.playing = false
  Music.update(f.game.data)
  f:drain()
  T.eq(Music.oneShotPlaying(), false, "actual native controller drains restore")
  T.eq(f.exports.get("mod:after"), true, "actual native restore resumes script")
  Music.stop()
  love.audio = previousAudio
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script audio")
