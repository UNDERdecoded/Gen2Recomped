package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/input_hooks/fixture.lua")
local Touch = require("src.core.TouchControls")
local Version = require("src.core.GameVersion")
local oldVersion = Version.get()
for _, version in ipairs(Version.ORDER) do
  local f = Fixture.new(".", "gen2", version, 2, "native")
  local g, I, api, e = f.game, f.Input, f.public, f.exports
  local calls, top = {}, {}
  g.stack.top = function()
    return top
  end
  top.onKeyPressed = function(_, key)
    calls[#calls + 1] = "key:" .. key
  end
  top.onKeyReleased = function(_, key)
    T.eq(I:isDown("up"), false, "release reaches Input before capture observer: " .. version)
    calls[#calls + 1] = "release:" .. key
  end
  local noted, note = 0, Touch.noteGamepad
  Touch.noteGamepad = function()
    noted = noted + 1
  end
  top.onGamepadPressed = function(_, button)
    calls[#calls + 1] = "pad:" .. button
  end
  top.onGamepadReleased = function(_, button)
    if button == "a" then
      T.eq(I:isDown("a"), false, "pad release before observer")
    end
    calls[#calls + 1] = "pad-release:" .. button
  end
  local unstick = 0
  g.unstick = function()
    unstick = unstick + 1
    return "unstuck"
  end
  local held = {}
  for key, value in pairs(I.axisHeld or {}) do
    held[key] = value
  end
  e.capture(true)
  g:keypressed("f9")
  g:keypressed("up")
  g:keyreleased("up")
  g:gamepadpressed(f.pad, "a")
  g:gamepadreleased(f.pad, "a")
  g:gamepadaxis(f.pad, "triggerleft", 1)
  T.eq(unstick, 0, "hook precedes engine emergency hotkey: " .. version)
  T.eq(#calls, 0, "hook precedes every capture callback")
  T.eq(noted, 0, "suppression precedes touch overlay bookkeeping")
  T.same(I.axisHeld or {}, held, "suppression does not create pseudo-button state")
  T.eq(#I.pressQueue, 0, "suppressed input creates no queued press")
  e.capture(false)
  T.eq(g:keypressed("f9"), "unstuck", "native hotkey result survives hooks")
  T.eq(unstick, 1, "hotkey runs exactly once")
  T.eq(#calls, 0, "native hotkey retains priority over top capture")
  g:keypressed("up")
  T.eq(I:isDown("up"), false, "top key capture keeps native priority over Input")
  T.same(calls, { "key:up" }, "exactly one captured key")
  I:keypressed("up")
  g:keyreleased("up")
  g:gamepadpressed(f.pad, "a")
  T.eq(I:isDown("a"), false, "top pad capture does not fall through")
  I:gamepadpressed(f.pad, "a")
  g:gamepadreleased(f.pad, "a")
  g:gamepadaxis(f.pad, "triggerleft", 1)
  T.eq(calls[#calls], "pad:triggerleft", "swallowed axis did not consume later capture edge")
  g:gamepadaxis(f.pad, "triggerleft", 0)
  T.eq(calls[#calls], "pad-release:triggerleft", "axis release still reaches capture observer")
  Touch.noteGamepad = note
  -- Standard hook ordering, next() argument forwarding, and return values.
  local order = {}
  local a = api.hooks:wrap("input.wheel", function(next, game, dy)
    order[#order + 1] = "outer"
    T.eq(game, g, "original Game in outer wrapper")
    T.eq(dy, 2.5, "fractional raw wheel delta")
    next(game, -100)
    order[#order + 1] = "after"
    return false
  end, 30)
  local b = api.hooks:wrap("input.wheel", function(next, game, dy)
    order[#order + 1] = "inner"
    T.eq(dy, -100, "rewritten delta visible downstream")
    return next()
  end, 20)
  local n = #f.zoom
  T.eq(g:wheelmoved(777, 2.5), false, "outer hook return value preserved")
  T.same(order, { "outer", "inner", "after" }, "descending priority and continuation")
  T.eq(f.zoom[n + 1], 1, "native wheel still uses original positive delta")
  a()
  b()
  -- Free-camera behavior (including its existing zero-delta step) is native.
  local free = {}
  g.zoomView = function()
    return {
      zoomBy = function(_, delta)
        free[#free + 1] = delta
      end,
    }
  end
  for _, dy in ipairs({ 2.5, -1, 0 }) do
    e.capture(true)
    g:wheelmoved(0, dy)
    e.capture(false)
    g:wheelmoved(0, dy)
  end
  T.same(free, { -1, 1, 1 }, "free camera preserves native sign and zero behavior")
  -- Nil and false are ordinary wrapper results; only omitting next suppresses.
  local off = api.hooks:wrap("input.key", function()
    return nil
  end, 100)
  n = #calls
  T.eq(g:keypressed("up"), nil, "nil-result suppression")
  T.eq(#calls, n, "nil-result wrapper prevents native callback")
  off()
  f.result.loader.hooks:removeOwner("portable_input")
  n = #e.events
  g:keypressed("up")
  T.eq(#e.events, n, "owner cleanup removes public registrations")
  f.close()
end
Version.set(oldVersion)
T.finish("portable input routing")
