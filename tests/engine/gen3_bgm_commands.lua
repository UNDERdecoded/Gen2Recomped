package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Music, V = require("src.core.Music"), require("src.core.GameVersion")
local before, oldAudio = V.get(), love.audio
local Source = {}
Source.__index = Source
function Source:play()
  self.playing = true
end
function Source:stop()
  self.playing = false
end
function Source:isPlaying()
  return self.playing or false
end
function Source:setVolume(value)
  self.volume = value
end
function Source:setLooping() end
local sources = {}
love.audio = {
  newSource = function(input)
    local source = setmetatable({ input = input }, Source)
    sources[#sources + 1] = source
    return source
  end,
}
for _, version in ipairs({ "firered", "emerald" }) do
  V.set(version)
  Music.reload()
  Music.applyOptions({ musicVol = 7 })
  local Ids = require("src.core.Gen3SongIds")
  local a, b, c = Ids.resolve("MUS_TITLE"), Ids.resolve("MUS_CYCLING"), Ids.resolve("MUS_SURF")
  local names = Ids.names()
  names.MUS_TITLE = -1
  T.eq(Ids.resolve("MUS_TITLE"), a, "caller mutation cannot alter the native identifier catalogue")
  T.eq(Ids.resolve("  mus_title  "), a, "native symbol fallback retains case and whitespace resolution")
  T.eq(Ids.resolve(" MOD_SONG "), " MOD_SONG ", "unregistered mod labels retain their exact spelling")
  local data = T.fixtures.fresh()
  data.maps = { OWNED_MUSIC_MAP = { music = a } }
  data.audio = {
    songs = {
      MUS_TITLE = { file = "owned-title.ogg" },
      MUS_CYCLING = { file = "owned-cycle.ogg" },
      MUS_SURF = { file = "owned-surf.ogg" },
    },
    mapSongs = { OWNED_MUSIC_MAP = "MUS_TITLE" },
  }
  local game = { data = data, save = { options = {}, flags = {}, player = {} } }
  local world = { map = { id = "OWNED_MUSIC_MAP" }, player = {} }
  Music.playMap(data, world.map.id, false, false)
  local function run(rows)
    local code = assert(require("src.script.Gen3ScriptVM").compile(
      { map_scripts = {
        source = "RomExtractorGen3",
        scripts = { OWNED_BGM = rows },
      } },
      "OWNED_BGM"
    ))
    local runner = require("src.script.ScriptRunner").new(game, world)
    runner:run(code, { source = { modId = "owned_music_contract", strict = true } })
    T.eq(runner:isRunning(), false, "BGM opcodes never turn a fade into a blocking script wait")
    return Music.nativeSnapshot()
  end
  local state = run({ { "playbgm", b, 1 }, { "end" } })
  T.eq(Music.current(), "MUS_CYCLING", "numeric scripts use unchanged named mod music definitions")
  T.eq(state.song, b, "native command tracks the numeric song independently of the file label")
  T.eq(state.mapSong, a, "script cues preserve the map header's default music")
  T.eq(state.savedSong, b, "playbgm keep flag saves the native override")
  state = run({ { "savebgm", c }, { "fadenewbgm", a }, { "end" } })
  T.eq(state.savedSong, c, "savebgm records its own persistent override")
  T.eq(state.song, a, "fadenewbgm follows actual native immediate play dispatch")
  T.eq(Music.current(), "MUS_TITLE", "the native target resolves to its mod file")
  local first = sources[#sources]
  run({ { "playbgm", a, 2 }, { "end" } })
  T.eq(sources[#sources], first, "same native song dedupes without an outgoing fade")
  T.eq(Music.nativeSnapshot().savedSong, c, "only flag one or true changes saved music")
  state = run({ { "fadeoutbgm", 8 }, { "end" } })
  T.eq(state.currentMapMusic, 0, "plain outgoing fade reports native silence as its destination")
  T.eq(state.fadeOut.dur, 64 / 60, "actual production world adapter uses its fixed native fade speed")
  Music.update(data)
  T.check(first:isPlaying(), "outgoing fade retains the running source")
  T.check(math.abs(first.volume - 0.7 * (1 - 1 / 64)) < 1e-12, "native envelope reaches the actual source")
  for _ = 2, 64 do
    Music.update(data)
  end
  T.eq(first:isPlaying(), false, "native audio tick64 stops the faded source")
  T.eq(first.volume, 0, "stopping the source preserves the completed fade's zero gain")
  T.eq(Music.nativeSnapshot().song, nil, "completed native fade clears the logical song")
  T.eq(Music.nativeSnapshot().savedSong, c, "fade completion preserves the saved override")
  state = run({ { "fadeinbgm", 1 }, { "end" } })
  local incoming = sources[#sources]
  T.eq(state.song, a, "fadeinbgm prefers the map song over the saved override")
  T.eq(incoming.volume, 0, "incoming native music begins at zero gain")
  for _ = 1, 64 do
    Music.update(data)
  end
  T.eq(Music.nativeSnapshot().fadeIn, nil, "incoming envelope completes on the native audio clock")
  T.check(math.abs(incoming.volume - 0.7) < 1e-12, "incoming native fade restores the original user gain")
  run({ { "fadeoutbgm", 4 }, { "end" } })
  Music.update(data)
  run({ { "playbgm", a, 0 }, { "end" } })
  T.neq(sources[#sources], incoming, "same-ID playback replaces an outgoing fade with a new owned source")
  T.eq(incoming:isPlaying(), false, "replaced faded sources cannot continue behind the new cue")
  T.eq(Music.nativeSnapshot().fadeOut, nil, "explicit play cancels the previous owner's outgoing fade")
  state = run({ { "playbgm", b, 0 }, { "fadedefaultbgm" }, { "end" } })
  T.eq(state.song, a, "file-only native overrides restore default without inventing a native stream")
  run({ { "savebgm", 0xFFFF }, { "playbgm", 0 }, { "end" } })
  T.eq(Music.current(), nil, "native song zero stops music")
  T.eq(Music.nativeSnapshot().savedSong, nil, "native saved-song sentinel clears the override")
  T.eq(Music.nativeSnapshot().song, nil, "native silence retains no logical playback")
end
Music.reload()
love.audio = oldAudio
V.set(before)
T.finish("native BGM symbols, world commands, owned sources and file envelopes")
