-- Per-loader, per-mod ownership for logical GB input. No Game/Input import:
-- handles may be constructed at the title screen or in a headless loader.
local Control = {}
Control.__index = Control
local sessions = setmetatable({}, { __mode = "k" })
-- Keep sessions with outstanding holds alive until release/reset/teardown.
local holding = {}
local serial = 0
local BUTTONS = {
  up = true,
  down = true,
  left = true,
  right = true,
  a = true,
  b = true,
  start = true,
  select = true,
}

local function idle(session)
  for _, bucket in pairs(session.owners) do
    if next(bucket.tokens) then
      return
    end
  end
  holding[session] = nil
end

function Control.new()
  serial = serial + 1
  local self = setmetatable({ serial = serial, owners = {} }, Control)
  sessions[self] = true
  return self
end

function Control:release(owner)
  if owner == nil then
    for id in pairs(self.owners) do
      self:release(id)
    end
    return
  end
  local bucket = self.owners[owner]
  if not bucket then
    return
  end
  for token, record in pairs(bucket.tokens) do
    bucket.tokens[token] = nil
    record.input:sourceRelease(record.button, record.source)
  end
  idle(self)
end

function Control:retire(owner)
  local bucket = self.owners[owner]
  if not bucket then
    return
  end
  self:release(owner)
  bucket.retired = true
  self.owners[owner] = nil
end

function Control:close()
  for owner in pairs(self.owners) do
    self:retire(owner)
  end
  self.closed = true
  sessions[self] = nil
  holding[self] = nil
end

function Control:api(owner)
  assert(not self.closed, "mod.input is no longer active")
  self:retire(owner)
  local bucket = { tokens = {}, seq = 0 }
  self.owners[owner] = bucket
  local function sourceFor(game, button)
    assert(not self.closed and not bucket.retired, "mod.input is no longer active")
    local input = type(game) == "table" and game.input
    assert(
      type(input) == "table"
        and type(input.sourcePress) == "function"
        and type(input.sourceRelease) == "function",
      "mod.input needs the live game (see game.ready)"
    )
    assert(BUTTONS[button], "unknown GB button: " .. tostring(button))
    bucket.seq = bucket.seq + 1
    -- A retired loader's sources cannot alias those of its replacement.
    return input, ("mod:%s:%d:%d"):format(owner, self.serial, bucket.seq)
  end
  return {
    tap = function(_, game, button)
      local input, source = sourceFor(game, button)
      input:sourcePress(button, source)
      input:sourceRelease(button, source)
    end,
    press = function(_, game, button)
      local input, source = sourceFor(game, button)
      input:sourcePress(button, source)
      local token = {}
      bucket.tokens[token] = { input = input, button = button, source = source }
      holding[self] = true
      return token
    end,
    release = function(_, token)
      local record = bucket.tokens[token]
      if not record then
        return false
      end
      bucket.tokens[token] = nil
      idle(self)
      record.input:sourceRelease(record.button, record.source)
      return true
    end,
  }
end

-- Input:reset already discards every physical and synthetic source. Retire
-- only tokens bound to that Input, without touching another game's holds.
function Control.forget(input)
  for session in pairs(sessions) do
    for _, bucket in pairs(session.owners) do
      for token, record in pairs(bucket.tokens) do
        if record.input == input then
          bucket.tokens[token] = nil
        end
      end
    end
    idle(session)
  end
end

function Control.closeAll()
  for session in pairs(sessions) do
    session:close()
  end
end

return Control
