local mod = ...
local mode, calls, cleanups, argumentCount = "forward", 0, 0, nil
local cleaned = false
local off = mod.hooks:wrap("core.quit_to_launcher", function(next, ...)
  calls = calls + 1
  argumentCount = select("#", ...)
  -- Real consumers can dispose their own resources here. This decision hook
  -- is not a generic unload event and may also lead back to the Lua launcher.
  if not cleaned then
    cleanups = cleanups + 1
    cleaned = true
  end
  if mode == "exit" then
    return false
  end
  if mode == "launcher" then
    return true
  end
  return next()
end)
mod.exports = {
  api = mod,
  mode = function(value)
    mode = value
  end,
  calls = function()
    return calls
  end,
  cleanups = function()
    return cleanups
  end,
  argumentCount = function()
    return argumentCount
  end,
  stop = off,
}
