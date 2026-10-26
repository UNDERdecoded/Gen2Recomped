local M = {}
function M.run(f)
  local T, g, I, e = f.T, f.game, f.Input, f.exports
  local rows = {}
  local function state(label)
    rows[#rows + 1] = {
      label = label,
      up = I:isDown("up"),
      a = I:isDown("a"),
      right = I:isDown("right"),
      zoom = #f.zoom,
      events = #e.events,
    }
  end
  local function last(name, expected)
    local seen = e.events[#e.events]
    T.eq(seen.name, name, "hook name")
    T.eq(seen.game, g, "original Game identity")
    T.same(seen.event, expected, "exact raw payload")
  end
  g:keypressed("up")
  last("input.key", { phase = "pressed", key = "up" })
  T.eq(I:isDown("up"), true, "forwarded keyboard press")
  state("key-down")
  e.capture(true)
  T.eq(g:keyreleased("up"), "captured", "release may be swallowed")
  last("input.key", { phase = "released", key = "up" })
  T.eq(I:isDown("up"), true, "swallowed release does not clear held input")
  state("key-release-captured")
  e.capture(false)
  g:keyreleased("up")
  T.eq(I:isDown("up"), false, "forwarded release clears held input")
  e.capture(true)
  g:keypressed("up")
  T.eq(I:isDown("up"), false, "swallowed press never reaches Input")
  state("key-press-captured")
  e.capture(false)
  g:gamepadpressed(f.pad, "a")
  last("input.gamepad", { phase = "pressed", joystick = f.pad, button = "a" })
  T.eq(e.events[#e.events].event.joystick, f.pad, "opaque joystick identity")
  T.eq(I:isDown("a"), true, "forwarded pad press")
  e.capture(true)
  g:gamepadreleased(f.pad, "a")
  last("input.gamepad", { phase = "released", joystick = f.pad, button = "a" })
  T.eq(I:isDown("a"), true, "swallowed pad release retains held input")
  state("pad-release-captured")
  e.capture(false)
  g:gamepadreleased(f.pad, "a")
  T.eq(I:isDown("a"), false, "forwarded pad release clears held input")
  e.capture(true)
  g:gamepadpressed(f.pad, "a")
  T.eq(I:isDown("a"), false, "swallowed pad press")
  g:gamepadaxis(f.pad, "leftx", 0.875)
  last("input.gamepad", { phase = "axis", joystick = f.pad, axis = "leftx", value = 0.875 })
  T.eq(I:isDown("right"), false, "swallowed axis does not create direction")
  state("axis-captured")
  e.capture(false)
  g:gamepadaxis(f.pad, "leftx", 0.875)
  T.eq(I:isDown("right"), true, "native axis produces direction")
  state("axis-forwarded")
  g:gamepadaxis(f.pad, "leftx", 0)
  last("input.gamepad", { phase = "axis", joystick = f.pad, axis = "leftx", value = 0 })
  T.eq(I:isDown("right"), false, "zero axis releases direction")
  for _, dy in ipairs({ -1, 2.5, 0 }) do
    local n = #f.zoom
    e.capture(true)
    T.eq(g:wheelmoved(99, dy), "captured", "wheel suppression result")
    last("input.wheel", dy)
    T.eq(#f.zoom, n, "captured wheel does not zoom")
    e.capture(false)
    g:wheelmoved(99, dy)
    last("input.wheel", dy)
    T.eq(#f.zoom, n + (dy == 0 and 0 or 1), "native wheel delta")
  end
  state("wheel-forwarded")
  local api = f.public
  if api.supports then
    for _, name in ipairs({ "input.key", "input.gamepad", "input.wheel" }) do
      T.eq(api:supports("hooks", name), true, "public capability " .. name)
    end
    T.eq(api:supports("hooks", "input.not_a_hook"), false, "unknown hook still declines")
  end
  -- Rewriting next's arguments changes downstream observations, not the
  -- original event captured by the native Game body (the Gen1 contract).
  local off = api.hooks:wrap("input.key", function(next, game, ev)
    return next(game, { phase = ev.phase, key = "down" })
  end, 100)
  g:keypressed("up")
  T.eq(e.events[#e.events].event.key, "down", "downstream sees replacement payload")
  T.eq(I:isDown("up"), true, "native callback retains original key")
  T.eq(I:isDown("down"), false, "replacement does not synthesize another key")
  off()
  g:keyreleased("up")
  -- Errors before/after next must not lose or replay a native event.
  for _, after in ipairs({ false, true }) do
    local offError = api.hooks:wrap("input.wheel", function(next)
      if after then
        next()
      end
      error("intentional input contract failure")
    end, 100)
    local n = #f.zoom
    g:wheelmoved(0, 1)
    T.eq(#f.zoom, n + 1, "wrapper error preserves exactly one native call")
    offError()
  end
  local original = g.zoomStep
  local calls = 0
  g.zoomStep = function()
    calls = calls + 1
    error("native zoom failure")
  end
  T.raises(function()
    g:wheelmoved(0, 1)
  end, "native zoom failure", "native failure propagates")
  T.eq(calls, 1, "native failure is never retried")
  g.zoomStep = original
  local n = #e.events
  e.stop()
  g:keypressed("up")
  g:keyreleased("up")
  g:gamepadpressed(f.pad, "a")
  g:gamepadreleased(f.pad, "a")
  g:gamepadaxis(f.pad, "leftx", 0)
  g:wheelmoved(0, 1)
  T.eq(#e.events, n, "unsubscribe removes every fixture callback")
  T.eq(I:isDown("up"), false, "empty chains preserve native release")
  T.eq(I:isDown("a"), false, "empty chains preserve native pad release")
  return rows
end
return M
