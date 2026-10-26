-- Per-mod, opaque ownership over the engine's non-blocking GET transport.
local Fetch = require("src.net.Fetch")
local Host = require("src.core.HostShell")
local Net = { MAX_INFLIGHT = 4 }
local loaders = setmetatable({}, {__mode = "k"})

function Net.urlDenial(url)
  if type(url) ~= "string" or #url > 8192 or url:find("[%z%c%s]") then return "invalid URL" end
  if not url:match("^[Hh][Tt][Tt][Pp][Ss]?://[^/?#]+") then return "HTTP or HTTPS URL with a host required" end
end

local function bucket(loader, owner)
  loader.netJobs = loader.netJobs or {}
  loader.netJobs[owner] = loader.netJobs[owner] or {}
  loaders[loader] = true
  return loader.netJobs[owner]
end

function Net.releaseAll(loader, owner)
  local b = loader.netJobs and loader.netJobs[owner]
  if not b then return end
  for handle, id in pairs(b) do Fetch.cancel(id); Fetch.release(id); b[handle] = nil end
  loader.netJobs[owner] = nil
end

function Net.unloadAll()
  for loader in pairs(loaders) do
    for owner in pairs(loader.netJobs or {}) do Net.releaseAll(loader, owner) end
  end
end

function Net.forMod(loader, mod)
  local owner = mod.manifest.id
  if not mod.manifest.permissionSet.network then
    local function refuse() error(('mod.fetch for %s needs the "network" permission'):format(owner), 2) end
    return { available = function() return false end, get = refuse,
      poll = refuse, cancel = refuse, release = refuse,
      capabilities = function() return {} end }
  end
  local api = {}
  function api:available() return Host.canSpawnProcess() and Fetch.available() end
  function api:capabilities()
    return Host.canSpawnProcess() and {boundedHttpsGet = 1, maxResponseBytes = require("src.net.AsyncGet").MAX_BYTES} or {}
  end
  function api:get(url, opts)
    local denial = Net.urlDenial(url)
    if denial then return nil, denial end
    opts = type(opts) == "table" and opts or {}
    if opts.boundedHttpsGet == 1 and not url:lower():match("^https://") then return nil, "HTTPS required" end
    local b, count = bucket(loader, owner), 0
    for _, id in pairs(b) do if Fetch.isPending(id) then count = count + 1 end end
    if count >= Net.MAX_INFLIGHT then return nil, "too many requests in flight" end
    local id, err = Fetch.get(url, { userAgent = "gen2recomp-mod/" .. owner,
      accept = type(opts.accept) == "string" and opts.accept or nil,
      maxSeconds = opts.maxSeconds, maxBytes = opts.maxBytes, boundedHttpsGet = opts.boundedHttpsGet })
    if not id then return nil, err end
    local handle = {}; b[handle] = id
    return handle
  end
  function api:poll(handle)
    local id = bucket(loader, owner)[handle]
    if not id then return {status = "error", err = "unknown request"} end
    local state = Fetch.poll(id); local out = {}
    for key, value in pairs(state) do out[key] = value end
    return out
  end
  function api:cancel(handle)
    local id = bucket(loader, owner)[handle]
    if not id then return false end
    Fetch.cancel(id); return true
  end
  function api:release(handle)
    local b = bucket(loader, owner); local id = b[handle]
    if not id then return false end
    Fetch.cancel(id); Fetch.release(id); b[handle] = nil; return true
  end
  return api
end

return Net
