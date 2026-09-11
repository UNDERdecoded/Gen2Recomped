-- Game state stack.  The top state updates; all states draw bottom-up
-- (so a text box can overlay the overworld, a battle replaces it, etc).
-- States are tables with optional enter/exit/update/draw/isOpaque.

local Runtime = require("src.mods.Runtime")

local StateStack = {}

function StateStack:init()
  self.states = {}
end

-- screen.pushed/popped fire after enter/exit so listeners observe the
-- settled state; the wants guard keeps the no-listener path allocation-free

function StateStack:push(state, ...)
  table.insert(self.states, state)
  if state.enter then state:enter(...) end
  if Runtime.wants("screen.pushed") then
    Runtime.emit("screen.pushed", { state = state })
  end
end

function StateStack:pop()
  local state = table.remove(self.states)
  if state and state.exit then state:exit() end
  if state and Runtime.wants("screen.popped") then
    Runtime.emit("screen.popped", { state = state })
  end
  return state
end

function StateStack:top()
  return self.states[#self.states]
end

-- A STATE THAT IS DRAWN BUT NOT UPDATED CANNOT MOVE.
--
-- Only the top state updates, which is right: a text box over the overworld
-- must not have the player walking underneath it. But every state from
-- visibleBase up is still DRAWN, and some of them are scenery -- Emerald's
-- title screen drifts its clouds behind the main menu, and its Birch intro
-- fades him in while his own first line is already on screen. Both pushed a
-- child in `enter`, so their `update` never ran once, and both were silently
-- frozen: the clouds stood still, and Birch -- loaded, positioned, correct --
-- was drawn at alpha zero for the entire introduction.
--
-- So a covered state gets `animate`, and only `animate`. It is a separate
-- name rather than a flag on `update` because the contract is different and
-- has to be: animate MOVES PICTURES. It must not read input (the title's
-- update opens the menu on A, and running that under the menu would open a
-- second one on the same press) and it must not push, pop or finish. A state
-- that wants both puts the motion in animate and calls it from update.
function StateStack:update(dt)
  local top = self:top()
  if top and top.update then top:update(dt) end
  for i = self:visibleBase(), #self.states - 1 do
    local state = self.states[i]
    if state.animate then state:animate(dt) end
  end
end

-- index of the lowest state drawn this frame (highest opaque, else 1)
function StateStack:visibleBase()
  for i = #self.states, 1, -1 do
    if self.states[i].isOpaque then return i end
  end
  return 1
end

function StateStack:draw()
  for i = self:visibleBase(), #self.states do
    if self.states[i].draw then self.states[i]:draw() end
  end
end

return StateStack
