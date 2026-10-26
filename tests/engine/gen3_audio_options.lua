package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Music = require("src.core.GameVersion"), require("src.core.Music")
local before = V.get()
local function fileVolume(frame)
  for _, source in ipairs(frame.state.voices) do
    if source.playing and source.file then
      return source.volume
    end
  end
end
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/native_bgm_options.lua").run(".", "gen2", version)
  T.eq(#rows, 13, "all audio mode, missing-option and reentrant scenarios execute")
  local byName = {}
  for _, row in ipairs(rows) do
    byName[row.case] = row
    for _, event in ipairs(row.mix) do
      T.eq(type(event.value), "boolean", "platform mixing policy remains boolean")
    end
  end
  local modes = byName["file-modes"].frames
  T.eq(fileVolume(modes[2]), 0, "external audio mode mutes the actual shared file")
  T.eq(fileVolume(modes[4]), 0.5, "game-only mode restores the newly requested file level")
  T.eq(fileVolume(modes[11]), 0.6, "both mode restores the current requested file level")
  T.eq(
    fileVolume(byName["file-preserve-mode"].frames[4]),
    0,
    "an omitted generic mode retains the existing shared mute policy"
  )
  local mix = {}
  for _, event in ipairs(byName["file-preserve-game"].mix) do
    mix[#mix + 1] = event.value
  end
  T.same(
    mix,
    { true, false, true, false, true },
    "native and shared mode defaults retain the reference's distinct platform policy calls"
  )
  local missing = byName["file-missing"].frames
  T.eq(fileVolume(missing[4]), 0.3, "an omitted shared level retains its previous trim")
  T.eq(missing[5].state.fadeOut.start, 1, "an omitted native level defaults independently to full volume")
  T.eq(byName["file-reentrant-native"].entered, true, "a real native script is entered from the option hook")
  T.eq(
    byName["file-reentrant-native"].frames[3].state.fadeOut.start,
    3 / 7,
    "a native fade begun inside the old-level callback captures the new native master"
  )
  T.eq(
    fileVolume(byName["file-reentrant-shared"].frames[3]),
    0.3,
    "a shared cue begun inside the hook receives the new bridge level"
  )
  local fanfare = byName["file-reentrant-fanfare"].frames[3].state.voices
  T.eq(fanfare[#fanfare].volume, 3 / 7, "a reentrant native fanfare receives the new native master")
  fanfare = byName["native-muted-fanfare"].frames[3].state.voices
  T.eq(fanfare[#fanfare].volume, 0, "external-only mode also mutes the native fanfare source")
  T.eq(
    fileVolume(byName["file-early-options"].frames[1]),
    0,
    "newly registered mod audio receives options before its first cue"
  )
  T.eq(
    fileVolume(byName["native-registered"].frames[5]),
    0.5,
    "registered shared options remain live while the native carrier owns playback"
  )
  for _, frame in ipairs(byName["native-modes"].frames) do
    if frame.tick == 1 or frame.tick == 8 then
      T.eq(frame.nativeActive, 1, "muting retains an actual native carrier")
      T.eq(frame.nativeMuted, true, "external-only mode writes zero gain to that carrier")
    end
  end
  local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
  local h = dofile("tests/native_bgm/streams.lua").install(".", "gen2", version, f)
  local fresh = {}
  for key, value in pairs(f.data) do
    fresh[key] = value
  end
  fresh.audio = { songs = { MUS_CYCLING = { file = "owned-fresh-options.ogg" } } }
  local savedData = f.game.data
  f.game.data = fresh
  local Game = require("src.core.Game")
  local game = setmetatable({ data = fresh }, { __index = Game })
  game:applyOptions({ musicVol = 3, audioMode = "external_only" })
  h.start({ { "playbgm", h.ids[2], 0 }, { "end" } })
  local voices = h.state().native.voices
  T.eq(voices[#voices].volume, 0, "actual Game options bind its fresh dataset before the next world cue")
  game:applyOptions({ musicVol = 3, audioMode = "game_only" })
  T.eq(voices[#voices].playing, true, "changing options preserves shared source ownership")
  T.eq(h.state().native.voices[#voices].volume, 0.3, "the same Game can restore its current shared source")
  h.close()
  f.game.data = savedData
  f.close()
end
-- Native options do not rewrite the independent generic player's trim when
-- no shared mod audio is installed. This also protects older game profiles.
local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", "firered")
local h = dofile("tests/native_bgm/streams.lua").install(".", "gen2", "firered", f)
Music.setAudioMode("both")
Music.setVolumeLevel(7)
Music.applyOptions({ musicVol = 3, audioMode = "external_only" }, { audio = { songs = {} } })
Music.stop()
V.set("red")
Music.play({ audio = { songs = { OWNED_LEGACY = { file = "owned-legacy-options.ogg" } } } }, "OWNED_LEGACY")
local voices = h.state().native.voices
T.eq(voices[#voices].volume, 0.7, "native-only mute/level options cannot overwrite the generic legacy trim")
V.set("firered")
h.close()
f.close()
local mixer = require("src.audio.AudioMix")
local oldAudio = love.audio
mixer._resetForTest()
love.audio = nil
T.eq(mixer.set(true), false, "a missing platform mixing API is a safe no-op")
T.eq(mixer.current(), nil, "a missing API cannot cache an unapplied policy")
love.audio = {
  setMixWithSystem = function()
    error("owned platform unavailable")
  end,
}
mixer.set(true)
T.eq(mixer.current(), nil, "a throwing platform does not poison a later retry")
local changes = {}
love.audio.setMixWithSystem = function(value)
  changes[#changes + 1] = value
end
T.eq(mixer.set(true), true, "a recovered platform can apply the policy")
T.eq(mixer.set(true), false, "repeated policies do not repeat hardware calls")
T.eq(mixer.set(false), true, "a distinct policy reaches the backend")
T.same(changes, { true, false }, "only successful policy transitions are cached")
love.audio = oldAudio
V.set(before)
T.finish("native audio options, shared trims, reentrant hooks and platform policy")
