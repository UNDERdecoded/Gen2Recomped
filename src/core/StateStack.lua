-- Game state stack.  The top state updates; all states draw bottom-up
-- (so a text box can overlay the overworld, a battle replaces it, etc).
-- States are tables with optional enter/exit/update/draw/isOpaque.

local Runtime = require("src.mods.Runtime")
local Logger = require("src.core.Logger")

local StateStack = {}

-- ---------------------------------------------------------------------------
-- WHO IS ON TOP, AND HOW IT GOT THERE.
--
-- Only the top state updates, and only the top state reads input.  So a state
-- that is pushed and never popped does not look like a bug in the state stack
-- -- it looks like the game has died: nothing walks, no menu opens, no button
-- does anything, and there is no error, because nothing went wrong.  Reported
-- twice from play as "no input is working at all ... i cant look around walk
-- or open any menus", and both times the only way to find out what was sitting
-- there was to add printing and reproduce it.
--
-- A state is an anonymous table, so it has no name to print.  What it does
-- have is functions, and a function knows which file it was written in -- so
-- the label is the source of its `update` (or `draw`, or `enter`), which is
-- exactly the file somebody would have to open next anyway.
local function fileOf(fn)
  if type(fn) ~= "function" or not debug or not debug.getinfo then return nil end
  local ok, info = pcall(debug.getinfo, fn, "S")
  if not (ok and info and info.short_src) then return nil end
  local src = info.short_src:gsub("^%./", "")
  if info.linedefined and info.linedefined > 0 then
    return src .. ":" .. info.linedefined
  end
  return src
end

-- WHAT KIND OF STATE THIS IS, from its class rather than from the function it
-- is currently carrying.
--
-- A mod may replace a method on an engine class -- this one replaces
-- `TextBox.update` outright -- and then `debug.getinfo(state.update)` names
-- the MOD's file for a state the ENGINE owns.  That is how a stuck text box
-- came to be reported as `UIMain.lua:12671`, which sent the reader to the
-- patch instead of to the class.  The metatable's __index still holds the
-- class, so ask that first and mention the patch separately.
local CLASS_KEYS = { "update", "draw", "enter", "exit", "onKeyPressed" }

local function classOf(state)
  local mt = getmetatable(state)
  local idx = mt and mt.__index
  if type(idx) ~= "table" then return nil end
  for _, key in ipairs(CLASS_KEYS) do
    local where = fileOf(rawget(idx, key))
    if where then return where end
  end
  return nil
end

function StateStack.describe(state)
  if type(state) ~= "table" then return tostring(state) end
  local name = state.name or state.id or state.stateName or state.screenId
  if type(name) == "string" and name ~= "" then return name end
  local class = classOf(state)
  local live = fileOf(state.update) or fileOf(state.draw) or fileOf(state.enter)
  if class then
    -- name the patch too when one is in the way: both halves matter, and
    -- which is which is the part a reader cannot guess
    if live and live ~= class then
      return class .. " (update from " .. live .. ")"
    end
    return class
  end
  if live then return live end
  return state.isOverworld and "overworld" or "<anonymous state>"
end

-- A stack this deep is a leak, not a game: the deepest the engine itself goes
-- is a handful (world -> menu -> submenu -> text box).  Said once per depth so
-- a mod that pushes every frame does not fill the log with the evidence.
local DEEP = 12
local deepSaid = {}

function StateStack:init()
  self.states = {}
  self._modalTracker = nil
end

-- screen.pushed/popped fire after enter/exit so listeners observe the
-- settled state; the wants guard keeps the no-listener path allocation-free

function StateStack:push(state, ...)
  table.insert(self.states, state)
  if self._modalTracker then self._modalTracker:added(state) end
  if state.enter then state:enter(...) end
  local depth = #self.states
  Logger.debug("state stack: push %s (depth %d)",
               StateStack.describe(state), depth)
  if depth >= DEEP and not deepSaid[depth] then
    deepSaid[depth] = true
    local names = {}
    for i = 1, depth do names[i] = StateStack.describe(self.states[i]) end
    Logger.warn("state stack is %d deep -- something is pushing and not "
      .. "popping, and only the top state updates or reads input: %s",
      depth, table.concat(names, " > "))
  end
  if Runtime.wants("screen.pushed") then
    Runtime.emit("screen.pushed", { state = state })
  end
end

local function finishRemoval(self, state)
  if state and state.exit then state:exit() end
  -- A POP THAT EMPTIES THE STACK is not debug-level news.  The engine does it
  -- on purpose in exactly two places and pushes the replacement in the same
  -- breath; everywhere else it is one pop too many, and the thing it leaves
  -- behind -- a screen that never changes, with no error -- gives the reader
  -- nothing to search for.  So it is said in words, once per culprit.
  if state ~= nil and #self.states == 0 then
    Logger.warn("state stack: popping %s emptied the stack -- nothing will "
      .. "update or draw until something is pushed back", 
      StateStack.describe(state))
  else
    Logger.debug("state stack: pop %s (depth %d)",
                 StateStack.describe(state), #self.states)
  end
  if state and Runtime.wants("screen.popped") then
    Runtime.emit("screen.popped", { state = state })
  end
  return state
end

function StateStack:pop()
  local state = table.remove(self.states)
  if state and self._modalTracker then self._modalTracker:removed(state) end
  return finishRemoval(self, state)
end

-- Remove actual native states, including a named modal beneath another one.
-- Detach the whole selection before callbacks: a new screen opened by exit
-- must survive and must never receive another removed screen's exit event.
function StateStack:removeAll(selected)
  local wanted, removed = {}, {}
  for _, state in ipairs(selected) do wanted[state] = true end
  for i = #self.states, 1, -1 do
    local state = self.states[i]
    if wanted[state] then
      table.remove(self.states, i)
      if self._modalTracker then self._modalTracker:removed(state) end
      removed[#removed + 1] = state
    end
  end
  local firstError
  for _, state in ipairs(removed) do
    local ok, err = pcall(finishRemoval, self, state)
    if not ok and not firstError then firstError = err end
  end
  if firstError then error(firstError, 0) end
  return #removed
end

function StateStack:top()
  return self.states[#self.states]
end

-- Put a state back that should never have left.
--
-- Deliberately NOT a push: the state never exited, so it must not re-enter --
-- the overworld's enter() calls setMap, which would boot the map over again
-- and move the player.  This undoes a pop; it does not perform a push, and it
-- does not emit screen.pushed, because nothing was entered.
function StateStack:restore(state)
  if type(state) ~= "table" then return false end
  table.insert(self.states, state)
  if self._modalTracker then self._modalTracker:added(state) end
  Logger.warn("state stack: restored %s (depth %d)",
              StateStack.describe(state), #self.states)
  return true
end

-- "overworld > src/ui/Gen3StartMenu.lua:41 > <anonymous state>", bottom first.
-- Cheap enough to put in a warning that is already being written, and the one
-- line that turns "input is dead" into a file to open.
function StateStack:describeAll()
  local names = {}
  for i = 1, #self.states do names[i] = StateStack.describe(self.states[i]) end
  if not names[1] then return "<empty>" end
  return table.concat(names, " > ")
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
-- Update/covered animation follows native opacity, regardless of rendering.
-- Hiding a mirrored menu must not animate newly exposed states during logic.
local function opaqueBase(states, modal)
  for i = #states, 1, -1 do
    if modal then
      if modal:allows(states[i]) and modal:opaque(states[i]) then return i end
    elseif states[i].isOpaque then return i end
  end
  return 1
end

function StateStack:update(dt)
  local top = self:top()
  if top and top.update then top:update(dt) end
  local modal = self._modalTracker
  if modal and not modal:isCurrent() then modal = nil end
  for i = opaqueBase(self.states, modal), #self.states - 1 do
    local state = self.states[i]
    if state.animate and (not modal or modal:allows(state)) then state:animate(dt) end
  end
end

local function visibleByDefault() return true end

-- A pure main-screen predicate: only literal false hides the native state.
-- Update/input ownership and the stored stack remain unchanged.
local function modalRenderPlan(self)
  local modal = self._modalTracker
  if not modal or not modal:isCurrent() then return end
  local visible, hooked = {}, Runtime.wantsHook("screen.render_visible")
  for _, state in ipairs(self.states) do
    visible[state] = not hooked or Runtime.call("screen.render_visible", visibleByDefault, state) ~= false
  end
  return modal:renderPlan(visible)
end

function StateStack:renderVisible(state, plan)
  if not state then return false end
  plan = plan or modalRenderPlan(self)
  if plan then return plan.visible[state] == true end
  if not Runtime.wantsHook("screen.render_visible") then return true end
  return Runtime.call("screen.render_visible", visibleByDefault, state) ~= false
end

-- index of the lowest state drawn this frame (highest visible opaque, else 1)
function StateStack:visibleBase(plan)
  plan = plan or modalRenderPlan(self)
  if plan then
    for i = #self.states, 1, -1 do
      local state = self.states[i]
      if plan.visible[state] and (state == plan.opaque
        or not self._modalTracker.records[state] and state.isOpaque) then return i end
    end
    return 1
  end
  local modal = self._modalTracker
  if modal and not modal:isCurrent() then modal = nil end
  if not Runtime.wantsHook("screen.render_visible") then return opaqueBase(self.states, modal) end
  for i = #self.states, 1, -1 do
    local state = self.states[i]
    if self:renderVisible(state) and (modal and modal:opaque(state) or not modal and state.isOpaque) then return i end
  end
  return 1
end

function StateStack:draw()
  local plan = modalRenderPlan(self)
  for i = self:visibleBase(plan), #self.states do
    local state = self.states[i]
    if self:renderVisible(state, plan) and state.draw then state:draw() end
  end
end

return StateStack
