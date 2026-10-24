-- API-3 script labels can have the same spelling as engine prose without
-- sharing a value. A present row with nil value masks a removed script text.
local M = {}
function M.get(data, id)
  local private = data and data._portableScriptText
  local row = private and private[id]
  if row then
    return row.value, true
  end
  return data and data.text and data.text[id] or nil, false
end
return M
