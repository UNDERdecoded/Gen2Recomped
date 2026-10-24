local M = {}
function M.run(f)
  local T, e = f.T, f.exports
  local rows = {}
  if e.api.supports then
    T.eq(e.api:supports("hooks", "battle.move_grid_navigation"), true, "native capability")
  end
  -- The exact same consumer drives every slot, direction and missing-cell
  -- shape through the native controller. Expected values are contract data.
  for _, mode in ipairs({ "grid", "list" }) do
    e.mode(mode)
    T.eq(f.grid(), mode == "grid", "public mode selection")
    T.eq(e.seen.battle, f.handle, "original opaque battle/screen handle")
    for count = 1, 4 do
      f.count(count)
      for index = 1, count do
        for _, dir in ipairs({ "left", "right", "up", "down" }) do
          f.index(index)
          local expected = index
          if mode == "list" then
            if dir == "up" then
              expected = index > 1 and index - 1 or count
            end
            if dir == "down" then
              expected = index < count and index + 1 or 1
            end
          else
            if dir == "left" or dir == "right" then
              expected = index % 2 == 1 and index + 1 or index - 1
            else
              expected = index <= 2 and index + 2 or index - 2
            end
            if expected > count then
              expected = index
            end
          end
          T.eq(f.press(dir), expected, "native " .. mode .. " " .. count .. "/" .. index .. " " .. dir)
          rows[#rows + 1] = { mode = mode, count = count, index = index, direction = dir, target = f.index() }
        end
      end
    end
  end
  f.count(4)
  for _, row in ipairs({ {}, { value = false }, { value = 0 }, { value = "" }, { value = {} } }) do
    local off = e.api.hooks:wrap("battle.move_grid_navigation", function()
      return row.value
    end, 100)
    T.eq(f.grid(), false, "only literal true enables grid")
    off()
  end
  e.mode("grid")
  for _, after in ipairs({ false, true }) do
    local off = e.api.hooks:wrap("battle.move_grid_navigation", function(next)
      if after then
        next()
      end
      error("intentional navigation predicate failure")
    end, 100)
    local calls = e.seen.calls
    T.eq(f.grid(), true, "failure preserves downstream grid")
    T.eq(e.seen.calls, calls + 1, "failure does not replay downstream")
    off()
  end
  if f.generation == 3 then
    f.double(true)
    e.mode("grid")
    for count = 1, 4 do
      f.count(count)
      for index = 1, count do
        for _, dir in ipairs({ "left", "right", "up", "down" }) do
          f.index(index)
          local target = index
          if dir == "left" and index % 2 == 0 then
            target = index - 1
          elseif dir == "right" and index % 2 == 1 then
            target = index + 1
          elseif dir == "up" and index >= 3 then
            target = index - 2
          elseif dir == "down" and index <= 2 then
            target = index + 2
          end
          if target > count then
            target = index
          end
          T.eq(f.press(dir), target, "native GBA doubles edge and sparse row")
          rows[#rows + 1] =
            { mode = "double", count = count, index = index, direction = dir, target = f.index() }
        end
      end
    end
    f.double(false)
  end
  return rows
end
return M
