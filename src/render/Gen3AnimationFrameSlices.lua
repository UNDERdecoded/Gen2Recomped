-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Retain only the currently selected immutable frame for each animation.
-- Placement, cadence, ordering and dirty-tile detection stay with the decoder.
local M = {}

function M.get(cache, index, frame, count)
  local prior = cache[index]
  if prior and prior.frame == frame and prior.count == count then
    return prior.pieces, true
  end
  local pieces = {}
  for tile = 0, count - 1 do
    local offset = tile * 32
    if offset + 32 <= #frame then
      pieces[tile + 1] = frame:sub(offset + 1, offset + 32)
    end
  end
  cache[index] = { frame = frame, count = count, pieces = pieces }
  return pieces, false
end

function M.trim(cache, count)
  for index in pairs(cache) do
    if index > count then cache[index] = nil end
  end
end

return M
