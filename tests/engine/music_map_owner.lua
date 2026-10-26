-- The same native owner scenario runs on clean Gen1Recomp and this fork.
-- File-backed fake Sources replace only the audio device, not Music or hooks.
package.path = './?.lua;./?/init.lua;' .. package.path
local assertions, sources = 0, {}
local function eq(got, expected, label)
  assertions = assertions + 1
  assert(got == expected, label .. ': ' .. tostring(got) .. ' ~= ' .. tostring(expected))
end
local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:pause() self.playing = false end
function Source:isPlaying() return self.playing == true end
function Source:setLooping(value) self.looping = value end
function Source:setVolume(value) self.volume = value end
function Source:getVolume() return self.volume or 0 end
function Source:setFilter() end
function Source:setPitch() end
love = { audio = { newSource = function(file)
  local source = setmetatable({ file = file }, Source)
  sources[#sources + 1] = source
  return source
end } }
local Runtime = require('src.mods.Runtime')
local Music = require('src.core.Music')
local GameVersion = require('src.core.GameVersion')
local results = {}
for _, version in ipairs({ 'red', 'blue', 'yellow', 'gold', 'silver', 'crystal', 'firered', 'emerald' }) do
  GameVersion.set(version)
  Music.reload()
  local hooks, events = require('src.mods.Hooks').new(), require('src.mods.Events').new()
  Runtime.install(events, hooks)
  local wet, calls = false, 0
  hooks:wrap('music.select', function(nextSong, song, ctx)
    calls = calls + 1
    local selected = nextSong(song, ctx)
    if wet and ctx.reason == 'map' then return 'WET' end
    return selected
  end, nil, 'map-owner-test')
  local songs = {}
  for _, id in ipairs({ 'MAP_A', 'MAP_B', 'RADIO', 'BATTLE', 'WET', 'DIRECT' }) do
    songs[id] = { file = id .. '.ogg' }
  end
  local data = { audio = { songs = songs, mapSongs = { A = 'MAP_A', B = 'MAP_B' }, battle = { wild = 'BATTLE' } } }
  Music.playMap(data, 'A', false, false)
  eq(Music.current(), 'MAP_A', version .. ' starts native map music')
  eq(Music.mapSong(), 'MAP_A', version .. ' remembers its unmodified cue')
  local before, previous, selected = #sources, Music.current(), calls
  eq(Music.mapSong(), 'MAP_A', version .. ' repeated read is observational')
  Music.setMapSong('RADIO')
  eq(Music.mapSong(), 'RADIO', version .. ' explicit radio override is remembered')
  eq(Music.current(), previous, version .. ' storing does not change current playback')
  eq(#sources, before, version .. ' storing and reading create no Sources')
  eq(calls, selected, version .. ' storing and reading invoke no selector')
  Music.playBattle(data, 'wild')
  eq(Music.current(), 'BATTLE', version .. ' battle owns playback')
  eq(Music.mapSong(), 'RADIO', version .. ' battle preserves the remembered cue')
  wet = true
  selected = calls
  Music.restoreMap(data)
  eq(Music.current(), 'WET', version .. ' map restoration uses the weather selector')
  eq(calls, selected + 1, version .. ' one selector invocation per restore')
  eq(Music.mapSong(), 'RADIO', version .. ' selected weather never overwrites the native cue')
  wet = false
  Music.restoreMap(data)
  eq(Music.current(), 'RADIO', version .. ' removing weather restores the remembered override')
  Music.playMap(data, 'B', false, false)
  eq(Music.mapSong(), 'MAP_B', version .. ' a real map change replaces the override')
  Music.play(data, 'DIRECT')
  eq(Music.mapSong(), 'MAP_B', version .. ' direct playback preserves map ownership')
  Music.stop()
  eq(Music.current(), nil, version .. ' explicit stop silences the current cue')
  eq(Music.mapSong(), 'MAP_B', version .. ' explicit stop preserves the restorable cue')
  Music.restoreMap(data)
  eq(Music.current(), 'MAP_B', version .. ' ordinary restore still uses its own Source')
  before, previous = #sources, Music.current()
  Music.setMapSong(nil)
  eq(Music.mapSong(), nil, version .. ' nil clears only the remembered cue')
  eq(Music.current(), previous, version .. ' clearing does not stop audio')
  eq(#sources, before, version .. ' clearing creates no Sources')
  results[#results + 1] = { version = version, current = Music.current(), rememberedCleared = Music.mapSong() == nil }
end
print('MUSIC_MAP_OWNER ' .. require('src.link.Json').encode({ assertions = assertions, versions = results }))
print(assertions .. '/' .. assertions .. ' checks passed (native map music ownership)')
