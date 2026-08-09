-- Regression: the `music.volume` mod hook must not crash on Music's private
-- `state`.  applyVolume (src/core/Music.lua) builds its hook context from
-- state.current/mapSong/onBike/... but was defined above the `local state`
-- table, so those reads bound to the nil global `state` instead -- a mod that
-- registered music.volume hit "attempt to index a nil value (global 'state')"
-- the first time any volume was applied.  This drives a file-backed song
-- through Music with the hook installed and asserts the context resolves.
-- ROM-free: a fake audio source, no data/generated/.
--   luajit tests/engine/music_volume_hook_state.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = require("tests.love_stub")

-- minimal audio source: only the methods Music calls on a file song
local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:pause() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:setLooping(v) self.looping = v end
function Source:setVolume(v) self.volume = v end
function Source:setFilter() end
love.audio = {
  newSource = function(file) return setmetatable({ file = file }, Source) end,
}

local Runtime = require("src.mods.Runtime")
local Music = require("src.core.Music")

local events = require("src.mods.Events").new()
local hooks = require("src.mods.Hooks").new()
Runtime.install(events, hooks)

-- one file-backed song is enough; the chip path would pull in `bit`
local data = { audio = { songs = { TEST = { file = "test.ogg" } } } }

-- record every context the hook is handed, and scale the volume so the
-- return value is exercised too
local calls = {}
hooks:wrap("music.volume", function(_next, vol, ctx)
  calls[#calls + 1] = ctx
  return vol * 0.5
end, nil, "voltest")

T.check(Runtime.wantsHook("music.volume"), "the music.volume hook is registered")

-- Before the fix this call raised inside applyVolume; reaching the next line
-- at all is the core of the regression.
Music.play(data, "TEST")
T.check(#calls >= 1, "applyVolume ran the hook during play without crashing")

-- A second application, now that the song is current: state must resolve to
-- the real playback table, so the context carries the live song + scale.
local before = #calls
Music.setVolumeLevel(5)
T.check(#calls > before, "setVolumeLevel re-applies volume through the hook")
local ctx = calls[#calls]
T.check(type(ctx) == "table", "the hook receives a context table")
T.eq(ctx.song, "TEST", "ctx.song is the live song (state resolved, not nil)")
T.eq(ctx.optionScale, 5 / 7, "ctx.optionScale reflects the 0-7 volume level")

T.finish("music_volume_hook_state")
