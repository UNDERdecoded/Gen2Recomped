-- Fence a native render seam, including leaked pushes and canvas changes.
local S = {}
local current
-- Opaque lifetime for paired helpers inside a guarded render callback.
function S.token() return current end
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
function S.call(fn, ...)
  local G = love.graphics
  local canvas = pack(G.getCanvas())
  local scissor = G.getScissor and pack(G.getScissor())
  local realPush, realPop = G.push, G.pop
  local before = G.getStackDepth and G.getStackDepth()
  local pushed, why = pcall(realPush, "all")
  if not pushed then
    return false, why
  end
  local depth = 0
  G.push = function(...)
    local result = pack(realPush(...))
    depth = depth + 1
    return unpack(result, 1, result.n)
  end
  G.pop = function(...)
    if depth <= 0 then
      error("render callback cannot pop caller graphics state", 0)
    end
    local result = pack(realPop(...))
    depth = depth - 1
    return unpack(result, 1, result.n)
  end
  local parent = current
  current = {}
  local out = pack(pcall(fn, ...))
  current = parent
  G.push, G.pop = realPush, realPop
  if before and G.getStackDepth then
    local current = G.getStackDepth()
    if current < before + 1 then
      G.setCanvas(unpack(canvas, 1, canvas.n))
      return false, "render callback removed its graphics guard"
    end
    depth = current - before - 1
  end
  for _ = 1, depth do
    pcall(realPop)
  end
  -- OpenGL applies scissor pixels using the currently bound canvas DPI.
  -- Rebind the caller before restoring its saved logical graphics state.
  G.setCanvas(unpack(canvas, 1, canvas.n))
  local restored, err = pcall(realPop)
  if not restored then
    return false, err
  end
  -- A leaked push may already have restored the same logical rectangle
  -- against another DPI. Reapply it after the entire stack is restored.
  if scissor then G.setScissor(unpack(scissor, 1, scissor.n)) end
  return unpack(out, 1, out.n)
end
return S
