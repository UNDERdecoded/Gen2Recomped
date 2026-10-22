package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_dialogue_audio")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(v)
  return Contract.fixture("tests/api3_contract", "gen2", v or "red")
end
local function sounding(f)
  for _ = 1, 300 do
    f:tick()
    if #f.audioTrace > 0 then
      return f.game.stack:top()
    end
  end
  error("no deferred cue")
end
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " native dialogue audio contract: " .. tostring(why))
end
for _, row in ipairs({
  { "play_cry", "UNKNOWN" },
  { "play_cry", 151 },
  { "play_cry", "MEW", 1 },
  { "play_cry", "MEW", true, 1 },
  { "text_sound", "UNKNOWN" },
  { "engage_music", "UNKNOWN" },
  { "text_sound", "CHIME", false },
  { "engage_music", false },
}) do
  local f = fixture()
  T.eq(f.exports.queue({ { "set_flag", "mod:prefix" }, row }), nil, "bad deferred cue refused")
  T.eq(f.exports.get("mod:prefix"), false, "whole script preflight")
  T.eq(#f.audioTrace, 0, "preflight is silent")
  f.restore()
end
for _, change in ipairs({ "rollback", "save", "data", "map" }) do
  for _, phase in ipairs({ "typing", "sounding", "button" }) do
    local f = fixture()
    T.check(
      f.exports.queue({
        { "play_cry", "MEW", true },
        { "engage_music", "TUNE" },
        { "show_text", "WELCOME" },
        { "set_flag", "mod:after" },
      }),
      "retirement fixture queued"
    )
    local box = f.game.stack:top()
    local auto = box.auto
    if phase ~= "typing" then
      sounding(f)
    end
    if phase == "button" then
      f.source.playing = false
      f:tick()
    end
    if change == "rollback" then
      f.loader:_rollback("script_dialogue_audio")
    elseif change == "map" then
      f.ow.map = { id = f.home }
    else
      f.game[change] = {}
    end
    local foreign = { update = function() end }
    f.game.stack:push(foreign)
    -- Retained callbacks after retirement cannot replay cues or remove UI.
    auto.sound()
    auto.tick()
    f:tick()
    T.eq(f.exports.get("mod:after"), false, "retired cue has no continuation")
    T.eq(f.game.stack:top(), foreign, "foreign overlay retained")
    T.eq(f.exports.result().done, 1, "retired cue completes once")
    f.restore()
  end
end
for _, callback in ipairs({ "sound", "poll", "engage" }) do
  local f = fixture()
  local Sound, Music = require("src.core.Sound"), require("src.core.Music")
  local foreign = { update = function() end }
  local function retire()
    f.loader:_rollback("script_dialogue_audio")
    f.game.stack:push(foreign)
  end
  local oldSound, oldMusic = Sound.playCry, Music.play
  if callback == "sound" then
    Sound.playCry = function(...)
      local src = oldSound(...)
      retire()
      return src
    end
  elseif callback == "poll" then
    f.source.isPlaying = function()
      retire()
      return false
    end
  else
    Music.play = function(...)
      oldMusic(...)
      retire()
    end
  end
  T.check(
    f.exports.queue({
      { "play_cry", "MEW" },
      { "engage_music", "TUNE" },
      { "show_text", "WELCOME" },
      { "set_flag", "mod:after" },
    }),
    "reentrant cue admitted"
  )
  for _ = 1, 300 do
    f:tick()
    if callback == "engage" then
      f.source.playing = false
    end
    if f.exports.result().done > 0 then
      break
    end
  end
  T.eq(f.game.stack:top(), foreign, "reentrant callback cannot pop foreign state")
  T.eq(f.exports.result().done, 1, "reentrant completion once")
  T.eq(f.exports.get("mod:after"), false, "reentrant continuation suppressed")
  Sound.playCry, Music.play = oldSound, oldMusic
  f.restore()
end
do
  local f = fixture()
  T.check(
    f.exports.queue({
      { "play_cry", "MEW" },
      { "text_sound", "CHIME" },
      { "engage_music", "TUNE" },
      { "ask", "WELCOME" },
      { "set_flag", "mod:after" },
    }),
    "combined cues with question"
  )
  local box = sounding(f)
  T.eq(#f.audioTrace, 2, "both cry and text effect play")
  for _ = 1, 3 do
    f:tick("a")
  end
  T.eq(f.game.stack:top(), box, "question waits for sound before choice")
  local retained = box.auto
  retained.sound()
  T.eq(#f.audioTrace, 2, "sound callback is once only")
  f.source.playing = false
  for _ = 1, 3 do
    f:tick()
  end
  T.check(f.game.stack:top() ~= box, "native choice after audio gate")
  T.eq(f.audioTrace[3].kind, "music", "engage follows completed cue")
  retained.tick()
  retained.sound()
  T.eq(#f.audioTrace, 3, "underlay callbacks add no playback")
  for _ = 1, 30 do
    f:tick("a")
  end
  T.eq(f.exports.result().success, true, "choice continues script once")
  T.eq(f.exports.result().done, 1, "choice single completion")
  f.restore()
end
do
  local f = fixture()
  T.check(
    f.exports.queue({
      { "play_cry", "MEW" },
      { "engage_music", "TUNE" },
      { "show_text", "WELCOME" },
      { "set_flag", "mod:after" },
    }),
    "bounded cry fixture"
  )
  sounding(f)
  for _ = 1, 600 do
    f:tick()
  end
  T.eq(f.exports.result().success, true, "600-frame native audio ceiling releases dialogue")
  T.eq(#f.audioTrace, 2, "music starts once at sound ceiling")
  f.restore()
end
for _, stage in ipairs({ "dispatch", "typed" }) do
  local f = fixture()
  T.check(
    f.exports.queue({ { "wait", 2 }, { "play_cry", "MEW" }, { "show_text", "WELCOME" }, {
      "set_flag",
      "mod:after",
    } }),
    "asset-change fixture"
  )
  if stage == "typed" then
    for _ = 1, 4 do
      f:tick()
    end
  end
  f.game.data.audio.cries.MEW = nil
  for _ = 1, 300 do
    f:tick()
  end
  T.eq(f.exports.result().success, false, "missing cry revalidated at " .. stage)
  T.eq(f.exports.get("mod:after"), false, "changed asset prevents continuation")
  T.eq(#f.audioTrace, 0, "missing asset never played")
  f.restore()
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod = saved[2], saved[3], saved[4], saved[5]
love = saved[6]
T.finish()
