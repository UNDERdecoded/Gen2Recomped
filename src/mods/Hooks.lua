local Logger = require("src.core.Logger")
local FrameProfile = require("src.core.FrameProfile")

local Hooks = {}
Hooks.__index = Hooks
local unpack = table.unpack or unpack

local function pack(...) return { n = select("#", ...), ... } end

-- errors raised below the chain (the vanilla function itself) must not be
-- attributed to a mod link or retried; they ride out wrapped under this key
-- so every guard re-raises instead of skipping
local PASS = {}
local function live()
  local scopes=package.loaded['src.compat.gen1.CoroutineScopes']
  assert(not(scopes and scopes.retired()),'native hook coroutine retired')
end

function Hooks.new()
  return setmetatable({ chains = {} }, Hooks)
end

-- owner is the wrapping mod id; failures are attributed to it
function Hooks:wrap(name, callback, priority, owner)
  assert(type(name) == "string" and name ~= "", "hook name is required")
  assert(type(callback) == "function", "hook callback must be a function")
  local chain = self.chains[name] or {}
  self.chains[name] = chain
  local entry = { callback = callback, priority = priority or 0, owner = owner }
  chain[#chain + 1] = entry
  table.sort(chain, function(a, b) return a.priority > b.priority end)
  return function()
    for i, candidate in ipairs(chain) do
      if candidate == entry then table.remove(chain, i) break end
    end
  end
end

-- each link runs under pcall: a throwing wrapper is logged and skipped and
-- the chain continues with the current arguments, so a broken mod degrades
-- to "not installed for this call" instead of breaking the pipeline.
-- vanilla must run at most once per call -- it has side effects -- so a link
-- that throws after its next() returned keeps the downstream results (its
-- post-processing is discarded) rather than re-walking the chain, and a link
-- that swallowed a vanilla error then threw propagates instead of retrying
-- WHICH REGISTRATION, not just which mod.
--
-- One mod wrapping the same seam nine times reads as one 46 ms line, and
-- "DRAMATIC_SHAPE is slow" is not something anybody can act on.  A callback
-- knows the file and line it was written at, so the label carries them and the
-- report names the nine places instead of the one mod.  Cached weakly on the
-- callback: debug.getinfo is not free and this runs inside the frame.
local siteCache = setmetatable({}, { __mode = "k" })

local function siteOf(entry)
  local fn = entry and entry.callback
  local hit = fn and siteCache[fn]
  if hit then return hit end
  local who = tostring(entry and entry.owner or "?")
  if type(fn) == "function" and debug and debug.getinfo then
    local ok, info = pcall(debug.getinfo, fn, "S")
    if ok and info and info.short_src then
      who = who .. " @ " .. info.short_src:gsub("^%./", "")
        .. ":" .. tostring(info.linedefined or 0)
    end
  end
  if fn then siteCache[fn] = who end
  return who
end

function Hooks:call(name, vanilla, ...)
  live()
  local chain = self.chains[name]
  if not chain or #chain == 0 then return vanilla(...) end
  local args = pack(...)
  local ranVanilla = false
  local function run(index)
    live()
    if index > #chain then
      ranVanilla = true
      local res = pack(pcall(vanilla, unpack(args, 1, args.n)))
      live()
      if res[1] then return unpack(res, 2, res.n) end
      error({ [PASS] = res[2] }, 0)
    end
    local entry = chain[index]
    local downstream
    -- EACH LINK'S OWN TIME, which is the only number that means anything here.
    -- A link calls `next` into the rest of the chain, so its wall time
    -- includes every link below it and the vanilla at the bottom; timing the
    -- bracket alone would charge the outermost mod with the whole seam.  So
    -- the time spent inside `next` is accumulated separately and subtracted.
    -- Zero cost when the profiler is off: `now()` is not called at all.
    local measuring = FrameProfile.enabled()
    local below = 0
    local function nextFn(...)
      local t0 = measuring and FrameProfile.now() or nil
      if select("#", ...) == 0 then
        downstream = pack(run(index + 1))
      else
        local saved = args
        args = pack(...)
        downstream = pack(run(index + 1))
        args = saved
      end
      if t0 then below = below + (FrameProfile.now() - t0) end
      return unpack(downstream, 1, downstream.n)
    end
    local started = measuring and FrameProfile.now() or nil
    local facade = package.loaded['src.core.Game3']
    local res
    if facade and facade._usesCallbacks and facade._usesCallbacks(entry.owner) then
      res = pack(pcall(facade._invokeHook, entry.owner, entry.callback, nextFn, unpack(args, 1, args.n)))
    else
      res = pack(pcall(entry.callback, nextFn, unpack(args, 1, args.n)))
    end
    if started then
      FrameProfile.add("      hook " .. tostring(name) .. " <- "
        .. siteOf(entry),
        (FrameProfile.now() - started) - below)
    end
    live()
    if res[1] then return unpack(res, 2, res.n) end
    local err = res[2]
    if type(err) == "table" and err[PASS] ~= nil then error(err, 0) end
    if downstream ~= nil then
      Logger.warn("[%s] hook %s failed after next: %s -- downstream result kept",
        tostring(entry.owner or "?"), name, tostring(err))
      return unpack(downstream, 1, downstream.n)
    end
    if ranVanilla then
      Logger.warn("[%s] hook %s failed: %s -- vanilla already ran, not retried",
        tostring(entry.owner or "?"), name, tostring(err))
      error({ [PASS] = err }, 0)
    end
    Logger.warn("[%s] hook %s failed: %s -- link skipped",
      tostring(entry.owner or "?"), name, tostring(err))
    return run(index + 1)
  end
  local res = pack(pcall(run, 1))
  if res[1] then return unpack(res, 2, res.n) end
  local err = res[2]
  if type(err) == "table" and err[PASS] ~= nil then error(err[PASS], 0) end
  error(err, 0)
end

-- drops every wrap a mod made; used by entry-chunk rollback
function Hooks:removeOwner(owner)
  if owner == nil then return end
  for name, chain in pairs(self.chains) do
    for i = #chain, 1, -1 do
      if chain[i].owner == owner then table.remove(chain, i) end
    end
    if #chain == 0 then self.chains[name] = nil end
  end
end

-- deprecated no-op: wrapping stays legal for the life of the process
function Hooks:seal() end

return Hooks
