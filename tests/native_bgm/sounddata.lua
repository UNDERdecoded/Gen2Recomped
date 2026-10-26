-- Match LÖVE's userdata admission while retaining the headless sample store.
-- Only hardware constructors change; renderers and native audio stay intact.
local M = {}
function M.install()
  assert(type(newproxy) == "function", "native audio hardware tests require LuaJIT/newproxy")
  local sound, source = love.sound.newSoundData, love.audio.newSource
  local storage = setmetatable({}, { __mode = "k" })
  local state = { created = 0, staticInputs = 0, sources = {} }
  love.sound.newSoundData = function(...)
    local data = sound(...)
    local proxy, methods = newproxy(true), {}
    storage[proxy] = data
    getmetatable(proxy).__index = function(_, key)
      local value = data[key]
      if type(value) ~= "function" then
        return value
      end
      if not methods[key] then
        methods[key] = function(_, ...)
          return value(data, ...)
        end
      end
      return methods[key]
    end
    state.created = state.created + 1
    return proxy
  end
  love.audio.newSource = function(input, ...)
    if storage[input] then
      assert(type(input) == "userdata")
      state.staticInputs = state.staticInputs + 1
    end
    -- The CPU Source records all samples from the backing store.
    local made = source(storage[input] or input, ...)
    if storage[input] and made then
      state.sources[#state.sources + 1] = made
    end
    return made
  end
  state.close = function()
    love.sound.newSoundData, love.audio.newSource = sound, source
  end
  return state
end
return M
