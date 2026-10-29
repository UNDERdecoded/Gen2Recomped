-- Actual native dialogue UI, with an explicit fake audio-device clock.
local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_dialogue_audio%.lua$")
  local base =
    dofile(codeRoot .. "/script_gifts.lua").fixture(root, backend, version, "script_dialogue_audio")
  local f = dofile(codeRoot .. "/script_audio.lua").fixture(root, backend, version, nil, base)
  f.game.data.audio.cries = { MEW = { file = "mew.wav" }, [151] = { file = "mew.wav" } }
  f.game.data.text.WELCOME = "WELCOME"
  f.game.data.text_pointers = {}
  f.ow.map.def.label = "DIALOGUE_HOME"
  f.ow.game, f.ow.text = f.game, f.game.data.text
  local Sound = require("src.core.Sound")
  local oldCry, restore = Sound.playCry, f.restore
  local function cry(_, key)
    f.audioTrace[#f.audioTrace + 1] = { kind = "cry", id = "MEW" }
    f.source.playing = true
    return f.source
  end
  Sound.playCry = cry
  if backend == "gen1" and f.gen == 2 then
    local World = require("src.world.gen2.World")
    f.ow.showText, f.ow.askYesNo = World.showText, World.askYesNo
  end
  local sourceRestore = function() end
  if backend == "gen1" and f.gen == 3 then
    local A = require("src.core.game3.audio")
    local oldPlay, oldBusy = A.playCry, A.isCryFinished
    A.playCry = function(key)
      return cry(f.game.data, key)
    end
    A.isCryFinished = function()
      return not f.source.playing
    end
    sourceRestore = function()
      A.playCry, A.isCryFinished = oldPlay, oldBusy
    end
  end
  f.restore = function()
    Sound.playCry = oldCry
    sourceRestore()
    restore()
  end
  function f:tick(key)
    self.game.input.wasPressed = function(_, button)
      return button == key
    end
    self.loader.hooks:call(backend == "gen1" and "core.update" or "input.step", function()
      if backend == "gen2" then
        self.ow.runner:update()
      end
    end, self.game, 1 / 60)
    if backend == "gen1" and self.gen == 3 then
      local Message = require("src.ui.game3.message")
      Message.tick()
      if key then
        if Message.isWaiting() then
          Message.advance()
        else
          Message.pressAB()
        end
      end
    else
      self.game.stack:update(1 / 60)
    end
    self.game.input.wasPressed = function()
      return false
    end
  end
  return f
end
function M.run(root, backend, version)
  local report = {}
  for _, verb in ipairs({ "play_cry", "text_sound", "engage_music" }) do
    local f = M.fixture(root, backend, version)
    local cue = verb == "play_cry" and "MEW" or verb == "text_sound" and "CHIME" or "TUNE"
    assert(f.exports.queue({ { verb, cue }, { "show_text", "WELCOME" }, { "set_flag", "mod:after" } }))
    assert(#f.audioTrace == 0, "cue must be deferred")
    for _ = 1, 300 do
      f:tick()
      if #f.audioTrace > 0 then
        break
      end
    end
    assert(#f.audioTrace == 1, "dialogue must start cue")
    if verb ~= "engage_music" then
      for _ = 1, 3 do
        f:tick("a")
      end
      assert(f.exports.result().done == 0, "sounding cue blocks completion")
    end
    f.source.playing, f.musicBusy = false, false
    for _ = 1, 30 do
      f:tick()
    end
    if verb == "play_cry" then
      assert(f.exports.result().success == true, "ordinary cry auto closes")
    else
      assert(f.exports.result().done == 0, "text cue keeps button wait")
      for _ = 1, 30 do
        f:tick("a")
      end
    end
    assert(f.exports.result().success == true and f.exports.get("mod:after"))
    report[verb] = { deferred = true, complete = true }
    f.restore()
  end
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
