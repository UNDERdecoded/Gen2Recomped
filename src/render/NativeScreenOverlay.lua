-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Controller-owned feedback is painted after its replaceable screen view.
-- The same state keeps input/continuations; no extra modal is pushed.
local Scope = require('src.render.GraphicsScope')
local M = {}
function M.draw(state, width, height)
  local draw = state.drawNativeOverlay
  if type(draw) ~= 'function' then return end
  if state.wantsNativeOverlay and not state:wantsNativeOverlay() then return end
  local ok, why = Scope.call(draw, state, width, height)
  if not ok then error(why, 0) end
end
local function view(state, fn, ...)
  -- Ordinary screens keep their original route. A controller with feedback
  -- fences its replaceable view before drawing its native continuation.
  if type(state.drawNativeOverlay) == 'function' and
      (not state.wantsNativeOverlay or state:wantsNativeOverlay()) then
    local ok, why = Scope.call(fn, state, ...)
    if not ok then error(why, 0) end
  else
    fn(state, ...)
  end
end
function M.screen(state, width, height)
  view(state, state.draw)
  return M.draw(state, width, height)
end
function M.window(state, width, height)
  view(state, state.drawWidescreen, width, height)
  return M.draw(state, width, height)
end
return M
