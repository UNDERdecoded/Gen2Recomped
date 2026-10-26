-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native immediate draws only; records and hook arguments never contain this cache.
local Performance = require("src.core.Performance")
local M = {}
local owners = setmetatable({}, { __mode = "k" })
function M.get(owner, slot, image, x, y, w, h, iw, ih)
  if not Performance.lowTierBudget then
    return love.graphics.newQuad(x, y, w, h, iw, ih)
  end
  local record = owners[owner]
  if not record then
    record = {}
    owners[owner] = record
  end
  local q = record[slot]
  if not q then
    q = love.graphics.newQuad(x, y, w, h, iw, ih)
    record[slot] = q
  else
    q:setViewport(x, y, w, h, iw, ih)
  end
  return q
end
return M
