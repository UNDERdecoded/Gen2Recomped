local M = {}
function M.run(f)
  local T, stack, e, api = f.T, f.stack, f.exports, f.public
  local base, menu, overlay = f.base, f.menu, f.overlay
  local rows = {}
  local function draw(label, states, expected, palette)
    local trace, zones = f.frame(states)
    T.same(trace, expected, label .. " native draw order")
    if f.palettePath then
      T.eq(zones, palette, label .. " visible palette owner")
    end
    T.same(stack.states, states, label .. " rendering does not rewrite stack")
    rows[#rows + 1] = { label = label, drawn = trace, base = stack:visibleBase() }
  end
  if api.supports then
    T.eq(api:supports("hooks", "screen.render_visible"), true, "native capability")
  end
  T.eq(stack:renderVisible(nil), false, "nil is not a renderable state")
  draw("native opaque menu", { base, menu }, { "BagMenu" }, "BagMenu zones")
  T.eq(e.seen.extra, 0, "opaque state signature has no invented args")
  T.eq(e.seen.state.screenId, menu.screenId, "native screen identifier reaches public hook")
  T.eq(e.seen.state == menu, f.stateIdentity, "host-native state identity semantics")
  e.hide("BagMenu", true)
  draw("mirrored menu", { base, menu }, { "Base" }, "Base zones")
  T.same(f.stackFrame({ base, menu }), { "Base" }, "native StateStack:draw hides mirrored menu")
  T.eq(stack:top(), menu, "hidden menu remains the native top")
  local before, baseUpdates, presses = e.seen.calls, base.updates, menu.presses
  f.input:keypressed("z")
  f.input:step()
  stack:update(1 / 60)
  T.eq(menu.updates, 1, "hidden menu keeps update ownership")
  T.eq(base.updates, baseUpdates, "world below does not steal update ownership")
  T.eq(menu.presses, presses + 1, "hidden menu receives native Input press")
  T.eq(e.seen.calls, before, "simulation never queries the render predicate")
  f.input:keyreleased("z")
  f.input:step()
  draw("overlay above mirrored menu", { base, menu, overlay }, { "Base", "TextBox" }, "TextBox zones")
  local hiddenChild = f.state("BagMenu", true)
  draw("multiple mirrored menus", { base, menu, hiddenChild }, { "Base" }, "Base zones")
  local replacement = {}
  for key, value in pairs(base) do
    replacement[key] = value
  end
  replacement.contractMarker = "replacement"

  local off = api.hooks:wrap("screen.render_visible", function(next, state)
    T.eq(state.screenId, base.screenId, "outer predicate sees actual state fields")
    return next(replacement)
  end, 100)
  T.eq(stack:renderVisible(base), true, "next(replacement) reaches downstream predicate")
  T.eq(e.seen.state.contractMarker, "replacement", "explicit next forwards replacement fields")
  off()
  base.contractMarker = nil
  -- Only literal false hides. No boolean coercion or special consume value.
  for _, case in ipairs({
    { name = "nil" },
    { name = "true", value = true },
    { name = "zero", value = 0 },
    { name = "empty string", value = "" },
    { name = "table", value = {} },
  }) do
    off = api.hooks:wrap("screen.render_visible", function()
      return case.value
    end, 100)
    T.eq(stack:renderVisible(menu), true, case.name .. " remains visible")
    off()
  end
  off = api.hooks:wrap("screen.render_visible", function()
    return false, true
  end, 100)
  T.eq(stack:renderVisible(base), false, "only first result controls visibility")
  off()
  local order = {}
  local outer = api.hooks:wrap("screen.render_visible", function(next)
    order[#order + 1] = "outer"
    local value = next()
    order[#order + 1] = "after"
    return value
  end, 20)
  local inner = api.hooks:wrap("screen.render_visible", function(next, state)
    order[#order + 1] = "inner"
    T.eq(state.screenId, base.screenId, "next() keeps current state fields")
    return next()
  end, 10)
  T.eq(stack:renderVisible(base), true, "default true passes through public wrappers")
  T.same(order, { "outer", "inner", "after" }, "priority and next ordering")
  outer()
  inner()
  for _, after in ipairs({ false, true }) do
    off = api.hooks:wrap("screen.render_visible", function(next)
      if after then
        next()
      end
      error("intentional screen predicate failure")
    end, 100)
    T.eq(stack:renderVisible(menu), false, "wrapper failure preserves downstream false")
    off()
  end
  if f.api >= 3 then
    off = api.hooks:wrap("screen.render_visible", function(next)
      next()
      return next()
    end, 100)
    before = e.seen.calls
    T.eq(stack:renderVisible(base), true, "API-3 repeated next result")
    T.eq(e.seen.calls, before + 1, "API-3 next caches downstream predicate")
    off()
  end
  draw("hidden sole menu", { menu }, {}, nil)
  draw("empty stack", {}, {}, nil)
  local nativeDraw, attempts = menu.draw, 0
  menu.draw = function()
    attempts = attempts + 1
    error("native screen draw failure")
  end
  f.frame({ base, menu })
  T.eq(attempts, 0, "hidden native drawer is never invoked")
  e.hide("BagMenu", false)
  T.raises(function()
    f.frame({ base, menu })
  end, "native screen draw failure", "native draw errors escape")
  T.eq(attempts, 1, "native draw failure is not retried")
  menu.draw = nativeDraw
  e.hide("BagMenu", true)

  e.hide("Base", true)
  e.hide("TextBox", true)
  draw("all hidden", { base, menu, overlay }, {}, nil)
  e.hide("Base", false)
  e.hide("TextBox", false)
  e.stop()
  e.stop()
  before = e.seen.calls
  draw("unsubscribed", { base, menu }, { "BagMenu" }, "BagMenu zones")
  T.eq(e.seen.calls, before, "unsubscribe is idempotent")
  api.hooks:wrap("screen.render_visible", function()
    return false
  end, 100)
  local peers = 0
  local peer = f.result.loader.hooks:wrap("screen.render_visible", function(next, ...)
    peers = peers + 1
    return next(...)
  end, 10, "other_screen_owner")
  f.result.loader.hooks:removeOwner("portable_screen_visibility")
  T.eq(stack:renderVisible(menu), true, "owner removal restores default")
  T.eq(peers, 1, "owner removal preserves another mod")
  peer()
  return rows
end
return M
