-- Callback leases for the native mart's menu, quantity and confirmation phases.
-- Only explicit UI fields are visited, never a state's Game/save/data graph.
local U = {}
local methods = { "select", "choose", "cancel", "close", "buy", "sell", "askQuantity", "askQuantityInput" }
local callbacks =
  { onDone = true, onChoose = true, onCancel = true, onQuit = true, onSelect = true, choice = true }
function U.new(control)
  local wrapped = setmetatable({}, { __mode = "k" })
  local function bind(state, holder, key, once, phase)
    local original = holder[key]
    if type(original) ~= "function" or wrapped[original] then
      return
    end
    local fired = false
    local guarded
    guarded = function(...)
      if fired or holder[key] ~= guarded or not control.alive(state) or phase and not phase() then
        return
      end
      if once then
        fired = true
      end
      return control.invoke(state, original, ...)
    end
    holder[key] = guarded
    wrapped[guarded] = true
  end
  local function attach(state)
    for key in pairs(callbacks) do
      if rawget(state, key) ~= nil then
        local once = key == "onDone"
          or key == "choice"
          or key == "onChoose" and getmetatable(state) == require("src.ui.ChoiceBox")
        bind(state, state, key, once)
      end
    end
    for _, key in ipairs(methods) do
      bind(state, state, key, false)
    end
    for _, item in ipairs(state.items or {}) do
      if type(item) == "table" then
        bind(state, item, "onSelect", false, function()
          for _, current in ipairs(state.items or {}) do
            if current == item then
              return true
            end
          end
          return false
        end)
      end
    end
    local asking = state.asking
    if type(asking) == "table" then
      bind(state, asking, "onDone", true, function()
        return state.asking == asking or control.phase(state) == asking
      end)
    end
  end
  return attach
end
return U
