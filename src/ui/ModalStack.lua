-- A modal plane over actual native states. World/battle controllers remain
-- owned by StateStack; this plane never builds another simulation or UI clock.
local Plane = {}
local methods = {}
local metadata = setmetatable({}, { __mode = "k" })
local arrays = setmetatable({}, { __mode = "k" })
local serial = 0

local function baseIndex(stack)
  local base = 0
  local battle = package.loaded["src.battle.BattleState"]
  for i, state in ipairs(stack.states) do
    if state.isOverworld or state.isBattleState
      or type(battle) == "table" and getmetatable(state) == battle then base = i end
  end
  return base
end

function methods:isCurrent()
  local owner = self.owner
  return owner.nativeStackReady ~= false and owner.stack == self.stack and self.stack.states == self.states
    and self.stack._modalTracker == self and owner.save == self.save
    and owner.sessionStartedAt == self.session
end

function methods:check()
  assert(self:isCurrent(), "native modal stack belongs to a retired Game/session")
end

function methods:added(state)
  if not self:isCurrent() then return end
  local prior = self.records[state]
  if prior then metadata[prior].retired = true end
  self.records[state] = nil
end

function methods:removed(state)
  local layer = self.records[state]
  if layer then metadata[layer].retired = true; self.records[state] = nil end
end

function methods:layer(state)
  local layer = self.records[state]
  if layer then return layer end
  serial = serial + 1
  local modOwned = state.modOwnedScreen == true
  local widget = state.nativeModalWidget or { state = state, isMenu = state.isMenu == true }
  layer = {
    id = state.nativeModalId or (modOwned and "modui:" .. serial)
      or state.screenId or "nativeui:" .. serial,
    mod = widget,
    isMenu = widget.isMenu == true,
    drawUnder = state.drawUnder == true,
    hideBelow = state.isOpaque == true,
    fullscreen = state.isOpaque == true,
  }
  local base = self.states[baseIndex(self.stack)]
  metadata[layer] = { plane = self, state = state, base = base, map = base and base.map }
  self.records[state] = layer
  return layer
end

function methods:sync()
  self:check()
  local count = 0
  for i = baseIndex(self.stack) + 1, #self.states do
    count = count + 1
    self.layers[count] = self:layer(self.states[i])
  end
  for i = #self.layers, count + 1, -1 do self.layers[i] = nil end
  local base = self.states[baseIndex(self.stack)]
  arrays[self.layers] = { plane = self, base = base, map = base and base.map }
  return self.layers
end

function methods:drawOrder(visible)
  local layers = self:sync()
  if visible then
    local filtered = {}
    for _, layer in ipairs(layers) do
      if visible[metadata[layer].state] then filtered[#filtered + 1] = layer end
    end
    layers = filtered
  end
  local first = 1
  for i = #layers, 2, -1 do if layers[i].hideBelow then first = i; break end end
  if layers[#layers] and layers[#layers].drawUnder then first = 1 end
  local out = {}
  for i = first, #layers do out[#out + 1] = layers[i] end
  return out
end

-- Rendering can mirror a native menu onto a different surface. Such a menu
-- must not hide the world or lower UI on this surface; logic remains modal.
function methods:renderPlan(visible)
  local order, full = self:drawOrder(visible), false
  for _, layer in ipairs(order) do
    local value = layer.fullscreen
    if type(value) == "function" then value = value() end
    if value then full = true end
  end
  local allowed = {}
  for state, shown in pairs(visible) do
    if not self.records[state] then allowed[state] = shown and not full end
  end
  for _, layer in ipairs(order) do allowed[metadata[layer].state] = true end
  return { visible = allowed, opaque = full and metadata[order[1]].state or nil }
end

function methods:fullscreen()
  for _, layer in ipairs(self:drawOrder()) do
    local value = layer.fullscreen
    if type(value) == "function" then value = value() end
    if value then return true end
  end
  return false
end

function methods:allows(state)
  local own = self.records[state]
  if not own then
    -- sync can discover native screens pushed without this facade.
    self:sync(); own = self.records[state]
  end
  if not own then return not self:fullscreen() end
  for _, layer in ipairs(self:drawOrder()) do if layer == own then return true end end
  return false
end

function methods:opaque(state)
  local layer = self.records[state]
  if not layer then return state.isOpaque end
  -- Fullscreen hides the scene, not UI explicitly retained by drawUnder.
  -- The first visible modal is therefore the single native opacity boundary.
  return self:drawOrder()[1] == layer and self:fullscreen()
end

function methods:depth() return #self:sync() end
function methods:top() local layers = self:sync(); return layers[#layers] end
function methods:busy() return self:depth() > 0 end
function methods:has(id)
  for _, layer in ipairs(self:sync()) do if layer.id == id then return true end end
  return false
end

function methods:push(id, widget, options)
  self:check()
  assert(type(id) == "string" and id ~= "", "native modal id must be a non-empty string")
  assert(type(widget) == "table", "native modal widget must be a table")
  local opts = options or {}
  if opts.hideBelow ~= false then
    local message = package.loaded["src.ui.game3.message"]
    if message and message.closeStay then
      message.closeStay()
    else
      -- The shared engine's stay message is a real native TextBox state.
      -- Closing it must not run its completion callback or ordinary prompts.
      local boxes = {}
      local class = package.loaded["src.render.TextBox"]
      for i = baseIndex(self.stack) + 1, #self.states do
        local state = self.states[i]
        if class and getmetatable(state) == class and state.stay then boxes[#boxes + 1] = state end
      end
      self.stack:removeAll(boxes)
    end
    self:check()
  end
  local old = {}
  for _, layer in ipairs(self:sync()) do
    if layer.id == id then old[#old + 1] = metadata[layer].state end
  end
  self.stack:removeAll(old)
  self:check()
  local game = self.owner
  local plane = self
  local state = { game = game, nativeModalId = id, nativeModalWidget = widget }
  -- These modules draw in GBA coordinates. Without a native surface request
  -- Game would centre them as 160x144 Game Boy overlays and clip the right edge.
  function state:uiSize() return 240, 160 end
  function state:wantsFillScale() return true end
  -- Legacy native menu modules use dot callbacks; StateStack uses methods.
  function state:update(dt)
    if widget.handleInput then widget.handleInput(game.input) end
    if plane:isCurrent() and plane.stack:top() == self and widget.update then widget.update(dt) end
  end
  function state:draw() if widget.draw then widget.draw() end end
  self.stack:push(state)
  local layer = self:layer(state)
  layer.isMenu = opts.isMenu == nil and widget.isMenu == true or opts.isMenu == true
  layer.drawUnder = opts.drawUnder == true
  layer.hideBelow = opts.hideBelow ~= false
  layer.fullscreen = opts.fullscreen
  self:sync()
end

function methods:pop(id)
  local layers = self:sync()
  for i = #layers, 1, -1 do
    local layer = layers[i]
    if not id or layer.id == id then
      self.stack:removeAll({ metadata[layer].state }); self:sync(); return true
    end
  end
  return false
end

function methods:clear()
  local selected = {}
  for _, layer in ipairs(self:sync()) do selected[#selected + 1] = metadata[layer].state end
  local ok, err = pcall(self.stack.removeAll, self.stack, selected)
  self:sync()
  if self.onCleared then self.onCleared() end
  if not ok then error(err, 0) end
end

-- Preview suspension is a lease, not pop/exit. Restoring a stale/foreign or
-- already retired state is rejected before mutating the actual native stack.
function methods:setLayers(layers)
  self:check()
  assert(type(layers) == "table", "native modal layers must be a table")
  local lease = arrays[layers]
  local base = baseIndex(self.stack)
  local root = self.states[base]
  assert(not lease or lease.plane == self and lease.base == root and lease.map == (root and root.map),
    "native modal lease belongs to another scene")
  local seen, states, count, last = {}, {}, 0, 0
  for key, layer in pairs(layers) do
    assert(type(key) == "number" and key >= 1 and key % 1 == 0, "native modal layers must be an array")
    local meta = metadata[layer]
    assert(meta and meta.plane == self and not meta.retired, "foreign or retired native modal layer")
    assert(meta.base == root and meta.map == (root and root.map), "native modal layer belongs to another scene")
    assert(not seen[meta.state], "duplicate native modal layer")
    seen[meta.state] = true; states[key] = meta.state; count = count + 1
    last = math.max(last, key)
  end
  assert(count == last, "native modal layers must be a dense array")
  for i = #self.states, base + 1, -1 do self.states[i] = nil end
  for i = 1, #layers do self.states[base + i] = states[i] end
  self.layers = layers
end

function Plane.forGame(game)
  assert(type(game) == "table" and type(game.stack) == "table"
    and type(game.stack.states) == "table", "native modal stack needs a live Game state stack")
  local stack = game.stack
  local prior = stack._modalTracker
  if prior and prior.owner == game and prior:isCurrent() then return prior.view end
  local model = setmetatable({ owner = game, stack = stack, states = stack.states,
    save = game.save, session = game.sessionStartedAt, layers = {},
    records = setmetatable({}, { __mode = "k" }) }, { __index = methods })
  local view = setmetatable({}, {
    __index = function(_, key)
      if key == "_layers" then return model:sync() end
      local fn = methods[key]
      if fn then return function(...) return fn(model, ...) end end
    end,
    __newindex = function(_, key, value)
      if key == "_layers" then return model:setLayers(value) end
      error("unknown native modal stack field " .. tostring(key), 2)
    end,
  })
  model.view = view; stack._modalTracker = model
  return view
end

return Plane
