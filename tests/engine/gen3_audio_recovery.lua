package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Music, V = require("src.core.Music"), require("src.core.GameVersion")
local before = V.get()
for _, version in ipairs({ "firered", "emerald" }) do
  local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
  for _, mode in ipairs({ "missing", "nil", "error" }) do
    local h = dofile("tests/native_bgm/streams.lua").install(".", "gen2", version, f, { queueFailure = mode })
    T.eq(Music.nativeSnapshot().song, h.ids[1], "missing hardware preserves the initial native song identity")
    T.eq(#h.state().queues, 0, "missing hardware cannot invent a live native source")
    h.queueDevice(nil)
    h.start({ { "playbgm", h.ids[2], 0 }, { "end" } })
    h.update()
    T.eq(#h.state().queues, 1, "a new native cue recovers when the device becomes available")
    h.start({ { "playbgm", h.ids[1], 0 }, { "end" } })
    h.update()
    T.eq(
      Music.current(),
      ("SONG_%03X"):format(h.ids[1]),
      "transient failure cannot poison a later native replay"
    )
    T.eq(
      h.state().queues[#h.state().queues].playing,
      true,
      "recovered native replay reaches an actual source"
    )
    h.close()
  end
  for _, mode in ipairs({ "missing", "nil", "error" }) do
    local h = dofile("tests/native_bgm/streams.lua").install(
      ".",
      "gen2",
      version,
      f,
      { initialShared = true, queueFailure = mode }
    )
    T.eq(Music.current(), "MUS_TITLE", "the incoming failure scenario starts with actual shared file music")
    f.data.audio.songs.OWNED_BROKEN_SHARED = {}
    Music.play(f.data, "OWNED_BROKEN_SHARED")
    T.eq(Music.current(), "MUS_TITLE", "a bad shared mod definition retains its existing playing song")
    h.start({ { "playbgm", h.ids[2], 0 }, { "end" } })
    T.eq(Music.nativeSnapshot().song, h.ids[2], "a failed native replacement retains its new logical song")
    T.eq(Music.current(), nil, "a native replacement releases the previous shared physical label")
    for _ = 1, 4 do
      h.update()
    end
    for _, source in ipairs(h.state().native.voices) do
      T.eq(source.playing, false, "failed incoming native output cannot leave shared file audio sounding")
    end
    T.eq(#h.state().queues, 0, "failed incoming output never invents a native queue")
    h.queueDevice(nil)
    h.start({ { "playbgm", h.ids[3], 0 }, { "end" } })
    h.update()
    T.eq(
      Music.current(),
      ("SONG_%03X"):format(h.ids[3]),
      "a later native cue recovers after shared replacement failed"
    )
    h.close()
  end
  local h = dofile("tests/native_bgm/streams.lua").install(".", "gen2", version, f)
  local ff = h.fanfares()
  h.start({ { "playfanfare", ff[1] }, { "end" } })
  local wait = assert(Music.nativeWaitFanfare())
  Music.suspend()
  Music.resume(f.data)
  T.eq(wait(), true, "a suspended native fanfare cannot re-block its old wait after resume")
  h.start({ { "playfanfare", ff[1] }, { "end" } })
  Music.stop()
  T.eq(Music.nativeFanfareFinished(), true, "external music stop cancels native fanfare ownership")
  T.eq(
    require("src.core.Sound").isSePlaying(f.data, ff[1]),
    false,
    "external stop cannot leave the native fanfare sounding"
  )
  h.close()
  for _, mode in ipairs({ "nil", "error" }) do
    h = dofile("tests/native_bgm/streams.lua").install(".", "gen2", version, f)
    ff = h.fanfares()
    local builder, sources, unavailable = love.audio.newSource, {}, true
    love.audio.newSource = function(...)
      if unavailable then
        if mode == "error" then
          error("owned static audio device unavailable")
        end
        return nil
      end
      local source = builder(...)
      sources[#sources + 1] = source
      return source
    end
    h.start({ { "playfanfare", ff[1] }, { "end" } })
    T.eq(Music.nativeFanfareFinished(), false, "a missing static source retains the native fanfare clock")
    T.eq(
      require("src.core.Sound").isSePlaying(f.data, ff[1]),
      false,
      "a failed static source never owns an SE player"
    )
    unavailable = false
    h.start({ { "playfanfare", ff[1] }, { "end" } })
    T.eq(#sources, 1, "a failed cold fanfare can build its source on a later cue")
    T.eq(
      require("src.core.Sound").isSePlaying(f.data, ff[1]),
      true,
      "the recovered cold fanfare owns its SE player"
    )
    local stoppedWait = assert(Music.nativeWaitFanfare())
    Music.stop()
    h.start({ { "playfanfare", ff[1] }, { "end" } })
    T.eq(stoppedWait(), true, "an externally cancelled wait stays complete during a later fanfare")
    T.eq(#sources, 2, "external stop discards sources owned by the ended session")
    Music.reload()
    T.eq(sources[#sources]:isPlaying(), false, "reload stops the previous session's fanfare source")
    h.start({ { "playfanfare", ff[1] }, { "end" } })
    T.eq(#sources, 3, "reload cannot reuse a stale native fanfare source")
    love.audio.newSource = builder
    h.close()
  end
  h = dofile("tests/native_bgm/streams.lua").install(".", "gen2", version, f)
  ff = h.fanfares()
  local Game, platform = require("src.core.Game"), require("src.core.Platform").detect()
  local oldMobile = platform.mobile
  platform.mobile = true
  local game = setmetatable({ data = f.data }, { __index = Game })
  h.start({ { "playfanfare", ff[1] }, { "end" } })
  local suspendedWait = assert(Music.nativeWaitFanfare())
  game:audioSession(false, "owned test interruption")
  h.queueDevice("nil")
  game:audioSession(true, "owned test interruption")
  T.eq(Music.nativeFanfareFinished(), true, "a failed foreground re-cue cannot revive the old fanfare clock")
  T.eq(suspendedWait(), true, "a failed foreground re-cue releases the old native wait")
  h.queueDevice(nil)
  for _ = 1, 60 do
    h.update()
  end
  T.eq(
    Music.current(),
    ("SONG_%03X"):format(h.ids[1]),
    "actual Game foreground retry uses its own imported dataset"
  )
  T.eq(h.state().queues[#h.state().queues].playing, true, "the foreground retry reaches a live native source")
  platform.mobile = oldMobile
  h.close()
  f.close()
end
V.set(before)
T.finish("native audio missing-device recovery, replay and session ownership")
