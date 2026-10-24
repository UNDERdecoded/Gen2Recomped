-- Native label-keyed prose, formatted before the ordinary textbox resolves
-- player/rival tokens. This is distinct from bank/address script text.
local Strings = require("src.core.Strings")
local ENDING = { ["{DONE}"] = true, ["{PROMPT}"] = true }
return function(data, label, fallback, ...)
  local prose = data and data._romTextGeneration == 2 and data.romText
  local text = prose and prose[label] or nil
  if text == nil and not (prose and data._romTextTouched and data._romTextTouched[label]) then
    text = data and data.text and data.text[label]
  end
  if not text then
    if fallback == nil then
      error("ROM text " .. tostring(label) .. " is not in the cache", 2)
    end
    return Strings(fallback, ...)
  end
  local values = { ... }
  if #values == 0 then
    return text
  end
  if #values == 1 and type(values[1]) == "table" then
    local named = values[1]
    return (
      text:gsub("%b{}", function(token)
        local value = named[token] or named[token:sub(2, -2)]
        return value == nil and token or tostring(value)
      end)
    )
  end
  local count, deferred = 0, 0
  for token in text:gmatch("%b{}") do
    if not ENDING[token] then
      count = count + 1
      if token == "{PLAYER}" or token == "{RIVAL}" then
        deferred = deferred + 1
      end
    end
  end
  local fillNames = #values == count
  if not fillNames and #values ~= count - deferred then
    if fallback == nil then
      error("ROM text " .. tostring(label) .. " does not fit the call", 2)
    end
    return Strings(fallback, ...)
  end
  local index = 0
  return (
    text:gsub("%b{}", function(token)
      if ENDING[token] or not fillNames and (token == "{PLAYER}" or token == "{RIVAL}") then
        return token
      end
      index = index + 1
      return values[index] == nil and token or tostring(values[index])
    end)
  )
end
