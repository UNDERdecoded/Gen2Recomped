local M = {}
function M.run(f)
  local T, b, api, e = f.T, f.battle, f.public, f.exports
  local rows = {}
  local function observe(label, expected)
    T.eq(f.visible(), expected, label .. " native predicate")
    local drawn = f.draw()
    T.eq(drawn, expected, label .. " native bottom draw")
    rows[#rows + 1] = { label = label, visible = drawn }
  end
  if api.supports then
    T.eq(api:supports("hooks", "battle.bottom_ui_visible"), true, "native capability")
  end
  f.stack.states = { b }
  observe("native", true)
  T.eq(e.seen.state, b, "original battle handle in every callback format")
  T.eq(e.seen.extra, 0, "no invented arguments")
  e.hide(true)
  observe("hidden", false)
  T.eq(f.stack:top(), b, "hidden bottom leaves native state on stack")
  local polls = e.seen.calls
  f.input:keypressed("z")
  f.input:step()
  T.eq(f.input:wasPressed("a"), true, "predicate does not consume native input")
  T.eq(e.seen.calls, polls, "input does not query rendering predicate")
  f.input:keyreleased("z")
  f.input:step()
  local text, choice = f.textBox(), f.choiceBox()
  f.stack.states = { b, text, choice }
  T.eq(f.inherited(text, true), false, "text inherits enclosing battle false")
  T.eq(e.seen.state, b, "inherited decision receives enclosing battle")
  T.eq(f.inherited(choice, false), false, "choice inherits enclosing battle false")
  e.hide(false)
  T.eq(f.inherited(text, true), true, "text returns when enclosing battle visible")
  T.eq(e.seen.state, text, "visible battle permits individual text predicate")
  local off = api.hooks:wrap("battle.bottom_ui_visible", function(next, state)
    if state == text then
      return false
    end
    return next(state)
  end, 100)
  T.eq(f.inherited(text, true), false, "individual text can hide without hiding battle")
  T.eq(f.inherited(choice, false), true, "individual text decision does not hide choice")
  off()
  for _, case in ipairs({
    { name = "nil" },
    { name = "true", value = true },
    { name = "zero", value = 0 },
    { name = "empty string", value = "" },
    { name = "table", value = {} },
  }) do
    off = api.hooks:wrap("battle.bottom_ui_visible", function()
      return case.value
    end, 100)
    T.eq(f.visible(), true, case.name .. " result remains visible")
    off()
  end
  off = api.hooks:wrap("battle.bottom_ui_visible", function()
    return false, true
  end, 100)
  T.eq(f.visible(), false, "first result alone controls visibility")
  off()
  local replacement = { isBattle = true, contract = "replacement" }
  off = api.hooks:wrap("battle.bottom_ui_visible", function(next, state)
    T.eq(state, b, "outer sees original battle")
    return next(replacement)
  end, 100)
  T.eq(f.visible(), true, "next forwards replacement predicate argument")
  T.eq(e.seen.state, replacement, "downstream sees replacement identity")
  off()
  local order = {}
  local outer = api.hooks:wrap("battle.bottom_ui_visible", function(next)
    order[#order + 1] = "outer"
    local value = next()
    order[#order + 1] = "after"
    return value
  end, 20)
  local inner = api.hooks:wrap("battle.bottom_ui_visible", function(next, state)
    order[#order + 1] = "inner"
    T.eq(state, b, "next() retains current handle")
    return next()
  end, 10)
  T.eq(f.visible(), true, "forwarded default true")
  T.same(order, { "outer", "inner", "after" }, "descending priority")
  outer()
  inner()
  e.hide(true)
  for _, after in ipairs({ false, true }) do
    off = api.hooks:wrap("battle.bottom_ui_visible", function(next)
      if after then
        next()
      end
      error("intentional bottom UI predicate failure")
    end, 100)
    T.eq(f.visible(), false, "wrapper failure preserves downstream false")
    off()
  end
  if f.api >= 3 then
    off = api.hooks:wrap("battle.bottom_ui_visible", function(next)
      next()
      return next()
    end, 100)
    polls = e.seen.calls
    T.eq(f.visible(), false, "API-3 cached false")
    T.eq(e.seen.calls, polls + 1, "API-3 repeated next does not replay downstream")
    off()
  end
  e.hide(false)
  observe("restored", true)
  e.stop()
  e.stop()
  polls = e.seen.calls
  observe("unsubscribed", true)
  T.eq(e.seen.calls, polls, "unsubscribe is idempotent")
  api.hooks:wrap("battle.bottom_ui_visible", function()
    return false
  end, 100)
  local peerCalls = 0
  local peer = f.result.loader.hooks:wrap("battle.bottom_ui_visible", function(next, ...)
    peerCalls = peerCalls + 1
    return next(...)
  end, 10, "other_bottom_owner")
  f.result.loader.hooks:removeOwner("portable_battle_bottom_ui")
  T.eq(f.visible(), true, "owner cleanup restores native visibility")
  T.eq(peerCalls, 1, "owner cleanup preserves another mod")
  peer()
  return rows
end
return M
