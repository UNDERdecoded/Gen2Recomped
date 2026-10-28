local Logger = require("src.core.Logger")
local FrameProfile = require("src.core.FrameProfile")
local Runtime = require("src.mods.Runtime")

local Events = {}
Events.__index = Events

function Events.new()
  return setmetatable({ listeners = {} }, Events)
end

-- owner is the subscribing mod id; failures are attributed to it
function Events:on(name, callback, priority, owner)
  assert(type(name) == "string" and name ~= "", "event name is required")
  assert(type(callback) == "function", "event callback must be a function")
  local list = self.listeners[name] or {}
  self.listeners[name] = list
  local entry = { callback = callback, priority = priority or 0, owner = owner }
  list[#list + 1] = entry
  table.sort(list, function(a, b) return a.priority > b.priority end)
  return function()
    for i, candidate in ipairs(list) do
      if candidate == entry then table.remove(list, i) break end
    end
    -- an emptied name drops its key, as removeOwner does, so Runtime.wants
    -- stops telling hot call sites to build payloads for nobody; the
    -- identity check keeps a stale second call off a later subscription
    if #list == 0 and self.listeners[name] == list then
      self.listeners[name] = nil
    end
  end
end

-- retires itself after the first fire; safe to unsubscribe from inside the
-- dispatch because emit walks a copy
function Events:once(name, callback, priority, owner)
  assert(type(callback) == "function", "event callback must be a function")
  local unsubscribe
  unsubscribe = self:on(name, function(payload)
    unsubscribe()
    return callback(payload)
  end, priority, owner)
  return unsubscribe
end

-- a throwing listener is logged and skipped so the emitting engine path
-- always completes; the error never propagates
function Events:emit(name, payload)
  local list = self.listeners[name]
  if not list then return end
  -- dispatch over a snapshot: a listener may retire itself or a sibling
  -- mid-emit (once, or the closure on() returns), and table.remove on the
  -- live list shifts the entries ipairs has not reached yet
  local snapshot = {}
  for i = 1, #list do snapshot[i] = list[i] end
  for _, entry in ipairs(snapshot) do
    -- ATTRIBUTED TO THE MOD, not to "events": an engine event fired once a
    -- frame with three listeners on it is three different owners' code, and
    -- lumping them together names the seam instead of the culprit.
    local close = FrameProfile.section(
      "  mod " .. tostring(entry.owner or "?") .. ": " .. tostring(name))
    local facade = package.loaded['src.core.Game3']
    local ok, err
    -- Native lifecycle/UI option changes are synchronous transactions. Capture only
    -- the current bus's real subscriber; preserve coroutine callback ABI by
    -- leaving non-main dispatch on its existing path. Frame events stay lean.
    local lifecycle=name=='mods.loaded'or name=='game.ready'
    local options=(lifecycle or name=='mod.options_changed'or name=='mod.option_action')
      and Runtime.events==self and(lifecycle or entry.owner~=nil and entry.owner~='base')
    if options then local co,main=coroutine.running();options=not co or main end
    local seams=options and package.loaded['src.mods.ModSeams']
    local seamOwner=entry.owner
    if seams and(entry.owner==nil or entry.owner=='base')then seamOwner='lifecycle:'..name end
    if facade and facade._usesCallbacks and facade._usesCallbacks(entry.owner) then
      if seams then ok,err=seams.run(seamOwner,facade._invokeEvent,entry.owner,name,entry.callback,payload)
      else ok,err=pcall(facade._invokeEvent,entry.owner,name,entry.callback,payload)end
    else
      if seams then ok,err=seams.run(seamOwner,entry.callback,payload)
      else ok,err=pcall(entry.callback,payload)end
    end
    close()
    if not ok then
      local message=tostring(err)
      local feed=Runtime.events==self and Runtime.errors
      local reportable=feed and entry.owner~=nil and entry.owner~='base'
      if not reportable or entry._failureFeed~=feed or entry._failureMessage~=message then
        Logger.error("[%s] event %s: %s",tostring(entry.owner or "?"),name,message)
        if reportable then
          Runtime.reportError(entry.owner,'event '..name..': '..message)
          entry._failureFeed,entry._failureMessage=feed,message
        end
      end
    else
      entry._failureFeed,entry._failureMessage=nil,nil
    end
  end
end

-- drops every subscription a mod made; used by entry-chunk rollback
function Events:removeOwner(owner)
  if owner == nil then return end
  for name, list in pairs(self.listeners) do
    for i = #list, 1, -1 do
      if list[i].owner == owner then table.remove(list, i) end
    end
    if #list == 0 then self.listeners[name] = nil end
  end
end

-- deprecated no-op: subscription stays legal for the life of the process
function Events:seal() end

return Events
