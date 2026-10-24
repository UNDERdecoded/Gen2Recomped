local M = {}
function M.run(f)
  local T, e = f.T, f.exports
  if e.api.supports then
    T.eq(e.api:supports("hooks", "ui.party.grid_navigation"), true, "native capability")
  end
  T.eq(f.grid(), false, "native party navigation remains the default")
  e.grid(true)
  T.eq(f.grid(), true, "opt-in grid")
  T.eq(e.seen.menu, f.menu, "original opaque menu")
  local rows = {}
  for count = 1, 6 do
    f.count(count)
    for index = 1, count + (f.generation == 3 and 1 or 0) do
      local slot = index > count and "cancel" or index
      for _, dir in ipairs({ "left", "right", "up", "down" }) do
        f.index(slot)
        local target = f.press(dir)
        T.check(
          target == "cancel" or (type(target) == "number" and target >= 1 and target <= count),
          "native target is occupied or cancel"
        )
        rows[#rows + 1] = { count = count, index = slot, direction = dir, target = target }
      end
    end
  end
  f.count(6)
  f.index(1)
  T.eq(f.press("right"), f.generation == 3 and 3 or 2, "lead's horizontal peer")
  f.index(1)
  T.eq(f.press("up"), f.generation == 3 and "cancel" or 5, "top edge follows native grid policy")
  f.count(5)
  f.index(5)
  T.eq(f.press("down"), f.generation == 3 and "cancel" or 1, "odd final row")
  for _, row in ipairs({ {}, { value = false }, { value = 0 }, { value = "" }, { value = {} } }) do
    local off = e.api.hooks:wrap("ui.party.grid_navigation", function()
      return row.value
    end, 100)
    T.eq(f.grid(), false, "only literal true enables grid")
    off()
  end
  for _, after in ipairs({ false, true }) do
    local off = e.api.hooks:wrap("ui.party.grid_navigation", function(next)
      if after then
        next()
      end
      error("intentional party navigation predicate failure")
    end, 100)
    local calls = e.seen.calls
    T.eq(f.grid(), true, "failure preserves downstream decision")
    T.eq(e.seen.calls, calls + 1, "failure does not replay downstream")
    off()
  end
  local calls = e.seen.calls
  f.battleMode(false)
  T.eq(f.grid(), false, "field party does not opt in")
  T.eq(e.seen.calls, calls, "field party bypasses battle predicate")
  f.battleMode(true)
  e.stop()
  e.stop()
  T.eq(f.grid(), false, "unsubscribe restores native controller")
  T.eq(e.seen.calls, calls, "unsubscribe stops consumer")
  return rows
end
return M
