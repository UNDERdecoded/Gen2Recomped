package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Game = require("src.core.Game")
local FixedStep = require("src.core.FixedStep")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local noop = function() end
local g = setmetatable({
  bootConfig = noop,
  adoptSave = noop,
  applyOptions = noop,
  updateCameraStick = noop,
}, { __index = Game })
local savedModules, savedUpvalues = {}, {}
local function module(name, value)
  savedModules[name] = { package.loaded[name] }
  package.loaded[name] = value
end
local function upvalue(name, value)
  for i = 1, 100 do
    local key, original = debug.getupvalue(Game.load, i)
    if not key then
      break
    end
    if key == name then
      savedUpvalues[i] = original
      debug.setupvalue(Game.load, i, value)
      return
    end
  end
  error("missing load upvalue: " .. name)
end
-- Stop real Game:load immediately after it installs its real FixedStep
-- callback. Unrelated ROM loading, rendering and save services are isolated.
upvalue("Data", { load = noop, applyMapEditorOverlay = noop,
  publishGen2Palettes = noop, publishGen2MapMetadata = noop,
  publishGen2TilesetNames = noop })
upvalue("ModLoader", {
  new = function()
    return { load = noop, status = noop }
  end,
})
for _, name in ipairs({ "Input", "TouchControls", "Renderer" }) do
  upvalue(name, { init = noop })
end
upvalue("StateStack", { init = noop })
upvalue("SaveData", {
  loadOptions = noop,
  newGame = function()
    return { options = { speed = 4 } }
  end,
})
module("src.render.Pipelines", { install = noop })
module("src.translation.Service", { install = noop })
for _, name in ipairs({ "src.render.Font", "src.ui.Theme", "src.core.Strings" }) do
  module(name, { load = noop })
end
local init = FixedStep.init
local stop = {}
FixedStep.init = function(self, callback)
  init(self, callback)
  error(stop)
end
local ok, err = pcall(Game.load, g)
FixedStep.init = init
for index, value in pairs(savedUpvalues) do
  debug.setupvalue(Game.load, index, value)
end
T.eq(ok, false, "test stops at the intended boot boundary")
T.eq(err, stop, "real Game:load reached FixedStep installation")
T.eq(type(FixedStep.callback), "function", "native step callback captured")

local logic, audio, tilt, pipeline, camera = 0, 0, 0, 0, 0
module("src.pokemon.Gen4PoketchState", { tick = noop })
module("src.core.Music", {
  update = function()
    audio = audio + 1
  end,
})
module("src.render.Tilt", {
  update = function(dt)
    tilt = tilt + dt
  end,
})
package.loaded["src.render.Pipelines"] = {
  update = function(dt)
    pipeline = pipeline + dt
  end,
}
module("src.core.DiscordPresence", { update = noop })
g.updateCameraStick = function(_, dt)
  camera = camera + dt
end
local hooks, savedHooks = Hooks.new(), Runtime.hooks
Runtime.hooks = hooks
local polls, value = 0, 4
local off = hooks:wrap("core.logic_speed", function(next, game)
  T.eq(game, g, "native update passes its Game to speed hook")
  polls = polls + 1
  return value
end)
g.stack = { states = {} }
local lockAt, lockKind
function g:step(dt)
  logic = logic + 1
  T.eq(dt, FixedStep.STEP, "simulation retains fixed delta")
  if logic == lockAt then
    if lockKind == "link" then
      self.linkSession = true
    else
      self.stack.states = { { isMinigame = true }, { isMenu = true } }
    end
  end
end
local function reset()
  logic, audio, tilt, pipeline, camera = 0, 0, 0, 0, 0
  FixedStep.accum, FixedStep.suppressCatchup = 0, false
  g.audioAccum, g.linkSession, g.stack.states = 0, nil, {}
end
for _, speed in ipairs({ 1, 4, 20, 100, 200 }) do
  reset()
  value = speed
  local before = polls
  g:update(FixedStep.STEP)
  -- Floating point subtraction can leave the final step just below STEP.
  T.check(logic >= speed - 1 and logic <= speed, "speed controls native logic budget")
  T.eq(polls, before + 1, "one speed dispatch per Game:update, not per simulation step")
  T.eq(audio, 1, "audio stays at real-time 60Hz")
  T.eq(tilt, FixedStep.STEP, "tilt uses real delta")
  T.eq(pipeline, FixedStep.STEP, "render pipelines use real delta")
  T.eq(camera, FixedStep.STEP, "camera uses real delta")
  T.eq(g._frameSpeed, speed, "native update records frame speed for lock edges")
end
for _, kind in ipairs({ "link", "fixed" }) do
  reset()
  value, lockAt, lockKind = 200, 3, kind
  local before = polls
  g:update(FixedStep.STEP)
  T.eq(logic, 3, kind .. " starts mid-frame and cancels remaining accelerated ticks")
  T.eq(FixedStep.accum, 0, kind .. " drains only the current budget")
  T.eq(FixedStep.suppressCatchup, false, kind .. " does not arm hitch suppression")
  T.eq(audio, 1, kind .. " leaves audio real-time")
  g:update(FixedStep.STEP)
  T.eq(logic, 4, kind .. " next frame runs at literal 1X")
  T.eq(polls, before + 1, kind .. " locked next frame bypasses hook")
  g.linkSession, g.stack.states = nil, {}
  lockAt = nil
  value = 4
  g:update(FixedStep.STEP)
  T.check(logic >= 7 and logic <= 8, kind .. " unlock restores accelerated simulation")
end
reset()
value = 0 / 0
g:update(FixedStep.STEP)
T.eq(logic, 1, "invalid mod speed cannot poison simulation clock")
T.eq(g._frameSpeed, 1, "invalid mod speed normalized before accumulation")
T.eq(audio, 1, "invalid mod speed cannot poison audio clock")
off()
Runtime.hooks = savedHooks
for name, original in pairs(savedModules) do
  package.loaded[name] = original[1]
end
T.finish("core.logic_speed native clocks")
