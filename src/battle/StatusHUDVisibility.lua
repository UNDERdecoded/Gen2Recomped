-- One native predicate for GB/GBA and DS healthboxes. Only literal false hides.
local Runtime = require("src.mods.Runtime")
local M = {}
local function defaultVisible()
  return true
end
function M.visible(battle)
  if not Runtime.wantsHook("battle.status_hud_visible") then
    return true
  end
  return Runtime.call("battle.status_hud_visible", defaultVisible, battle) ~= false
end
-- Standalone renderers also accept partial battle fixtures and legacy overrides.
-- The native method is M.visible itself, so it must not dispatch the hook twice.
function M.forBattle(battle)
  local method = type(battle) == "table" and battle.statusHUDVisible
  if type(method) == "function" and method ~= M.visible then
    local ok, visible = pcall(method, battle)
    if ok and visible == false then
      return false
    end
  end
  return M.visible(battle)
end
return M
