-- Native GBA modal UI over the current Game's real StateStack.
local Plane = require("src.ui.ModalStack")
local Runtime = require("src.mods.Runtime")
local M, clearHooks = {}, {}
local function current(required)
  local game = package.loaded["src.core.Game"]
  if type(game) == "table" and game.nativeStackReady ~= false and game.stack
    and require("src.core.GameVersion").isGen3() then
    local view = Plane.forGame(game)
    game.stack._modalTracker.onCleared = function()
      for i = #clearHooks, 1, -1 do
        local row = clearHooks[i]
        if row.stopped or row.bus and row.bus ~= Runtime.hooks then table.remove(clearHooks, i) end
      end
      local pending = {}; for i, row in ipairs(clearHooks) do pending[i] = row end
      for _, row in ipairs(pending) do if not row.stopped then row.fn() end end
    end
    return view
  end
  assert(not required, "Gen3 modal UI needs a live Gen3 Game")
end
function M.onClear(fn)
  assert(type(fn) == "function", "native modal clear hook must be a function")
  local row = { fn = fn, bus = Runtime.currentMod and Runtime.hooks }
  clearHooks[#clearHooks + 1] = row
  return function() row.stopped = true end
end
for _, name in ipairs({ "push", "pop", "clear", "top", "has", "busy", "fullscreen", "drawOrder", "depth" }) do
  M[name] = function(...)
    local view = current(name == "push" or name == "clear")
    if view then return view[name](...) end
    if name == "drawOrder" then return {} end
    if name == "depth" then return 0 end
    if name ~= "top" then return false end
  end
end
return setmetatable(M, {
  __index = function(_, key) if key == "_layers" then local view = current(true); return view._layers end end,
  __newindex = function(t, key, value)
    if key == "_layers" then current(true)._layers = value else rawset(t, key, value) end
  end,
})
