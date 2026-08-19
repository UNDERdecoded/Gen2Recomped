-- A frame-level watchdog for LOVE's graphics state stack.
--
-- love.graphics.push / pop share one fixed-depth stack for the whole process,
-- and the failure mode when something forgets to pop is the worst kind: it does
-- not fail where the bug is.  The stack simply sits one deeper, frame after
-- frame, until some UNRELATED push -- typically the engine's own, deep inside
-- the compositor and outside anyone's pcall -- throws
--
--     Maximum stack depth reached (more pushes than pops?)
--
-- and takes the process with it, naming a file that did nothing wrong.  That is
-- how a leak in one mod's party-menu preview ended up killing the game from
-- src/render/Pipelines.lua, and it is why the traceback was no help.
--
-- So the engine counts.  install() swaps in counting versions of push and pop
-- for the life of the process; drain() is called at the top of every update and
-- every draw and pops whatever the last frame left standing.  A leak then costs
-- one frame of wrong state instead of the session, and the log says how deep it
-- got -- which, unlike the crash, is a number a mod author can act on.
--
-- The cost is one Lua call per push and per pop.  A busy frame in this engine
-- makes a couple of hundred; it does not show up.
--
-- Deliberately NOT a mod hook: a mod cannot opt out of this, because the whole
-- point is to survive mods that are wrong.  Pipelines.guardRender does the same
-- counting around a single callback so it can name the pipeline responsible;
-- the two nest correctly, because it saves and restores whatever push/pop it
-- found rather than assuming the raw ones.

local Logger = require("src.core.Logger")

local GraphicsStack = {}

local depth = 0
local installed = false
local reported = false
local worst = 0

function GraphicsStack.depth() return depth end
function GraphicsStack.worst() return worst end

-- Test seam: forget everything, including the shims.
function GraphicsStack.reset()
  depth, installed, reported, worst = 0, false, false, 0
end

function GraphicsStack.install()
  if installed then return false end
  local g = love and love.graphics
  if not (g and type(g.push) == "function" and type(g.pop) == "function") then
    return false
  end
  local realPush, realPop = g.push, g.pop
  g.push = function(...)
    depth = depth + 1
    if depth > worst then worst = depth end
    return realPush(...)
  end
  g.pop = function(...)
    depth = depth - 1
    return realPop(...)
  end
  GraphicsStack.realPush, GraphicsStack.realPop = realPush, realPop
  installed = true
  return true
end

-- Pop anything the previous frame left behind.  Returns how many it had to
-- unwind, which is 0 on every well-behaved frame.
function GraphicsStack.drain()
  if depth == 0 then return 0 end
  local leaked = depth
  if leaked > 0 then
    local pop = GraphicsStack.realPop
    for _ = 1, leaked do
      if not pcall(pop) then break end
    end
  end
  -- A negative count means something popped past its own pushes.  There is
  -- nothing to unwind -- the damage is to state, not depth -- so just get the
  -- counter back to a sane base for the next frame.
  depth = 0
  if not reported then
    reported = true
    if leaked > 0 then
      Logger.error("graphics stack: %d push(es) were left unpopped by the last "
        .. "frame -- unwound.  Something is calling love.graphics.push without "
        .. "a matching pop; left alone this crashes the process a second later "
        .. "in whichever unrelated push happens to overflow the stack.", leaked)
    else
      Logger.error("graphics stack: the last frame popped %d more state(s) "
        .. "than it pushed.", -leaked)
    end
  end
  return leaked
end

return GraphicsStack
