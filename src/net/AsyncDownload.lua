-- File downloads have bounded, engine-owned workers. Poll only drains results,
-- reads coalesced progress. All file IO/publication stays on the workers.
local M = { MAX_JOBS = 8, MAX_BYTES = 512 * 1024 * 1024 }
local jobs, workers, destinations, nextId = {}, {}, {}, 0
local commands, results, quit, directory, ready, failure
local function now() return love.timer.getTime() end

local function ensure()
  if ready ~= nil then return ready end
  if not (love and love.thread and love.thread.newThread and love.filesystem and love.timer)
      or not require("src.core.HostShell").canSpawnProcess() then
    ready, failure = false, "background file downloads unavailable"; return false
  end
  commands, results, quit = love.thread.newChannel(), love.thread.newChannel(), love.thread.newChannel()
  directory = "net-download/" .. os.time() .. "-" .. tostring({}):gsub("[^%w]", "")
  local ok, made = pcall(love.filesystem.createDirectory, directory)
  if not ok or not made then ready, failure = false, "could not create download workspace"; return false end
  for _ = 1, 2 do
    local created, thread = pcall(love.thread.newThread, "src/net/download_worker.lua")
    if created and thread and pcall(thread.start, thread, commands, results, quit) then workers[#workers + 1] = thread end
  end
  ready = #workers > 0
  if not ready then failure = "could not start file-download workers" end
  return ready
end

local function retire(job)
  if destinations[job.key] == job.id then destinations[job.key] = nil end
end
local function cancelTransfer(job)
  if not job.control then return true end
  return job.control:performAtomic(function(control)
    if control:peek() ~= "open" then return false end
    control:clear(); control:push("cancelled"); job.cancel:push(true)
    return true
  end)
end
local function failed(job, reason)
  job.state = {status = "error", err = reason, progress = 0}
  retire(job)
end
local function drain()
  if not results then return end
  while true do
    local response = results:pop()
    if not response then break end
    local job = type(response) == "table" and jobs[response.id]
    if job then
      job.busy = false
      if job.retained and job.state.status == "pending" then
        if not response.ok then failed(job, response.err or "download failed")
        else
          job.state = {status = "ok", progress = 1, receivedBytes = response.bytes, httpStatus = response.httpStatus}
          retire(job)
        end
        if job.state.status == "error" then job.state.httpStatus = response.httpStatus end
      end
      retire(job)
      if not job.retained then jobs[response.id] = nil end
    end
  end
  for _, thread in ipairs(workers) do
    local err = thread:getError()
    if err then
      ready, failure = false, tostring(err)
      quit:push(true); commands:clear()
      for _ = 1, #workers do commands:push(false) end
      for _, job in pairs(jobs) do
        if job.state.status == "pending" then cancelTransfer(job); failed(job, failure) end
      end
      break
    end
  end
  for _, job in pairs(jobs) do
    if job.state.status == "pending" and now() >= job.deadline and cancelTransfer(job) then
      failed(job, "download timed out")
    end
  end
end

local function path(value)
  if type(value) ~= "string" or #value == 0 or #value > 2048 or value:find("[%z%c:]") then return nil end
  value = value:gsub("\\", "/")
  if value:sub(1, 1) == "/" or value:sub(-1) == "/" or value:find("//", 1, true)
      or value == "net-download" or value:sub(1, 13) == "net-download/" then return nil end
  for part in value:gmatch("[^/]+") do if part == "." or part == ".." then return nil end end
  return value
end
local function number(value, default, maximum)
  if value == nil then return default end
  value = tonumber(value)
  if not value or value ~= value or value < 0 or value > maximum then return nil end
  return value
end

function M.download(url, destination, options)
  options = type(options) == "table" and options or {}
  if type(url) ~= "string" or #url > 8192 or url:find("[%z%c%s]")
      or not url:lower():match("^https?://[^/?#]+") then return nil, "invalid HTTP URL" end
  if options.boundedHttpsGet == 1 and not url:lower():match("^https://") then return nil, "HTTPS required" end
  for _, name in ipairs({"userAgent", "accept"}) do
    local value = options[name]
    if value ~= nil and (type(value) ~= "string" or #value > 1024 or value:find("[%z%c]")) then
      return nil, "invalid HTTP header"
    end
  end
  local dest = path(destination)
  if not dest then return nil, "relative download file path required" end
  local size = number(options.size, nil, M.MAX_BYTES)
  if options.size ~= nil and (size == nil or size % 1 ~= 0) then return nil, "invalid expected size" end
  local limit = number(options.maxBytes, math.max(size or 0, 64 * 1024 * 1024), M.MAX_BYTES)
  local seconds = number(options.maxSeconds, 60, 300)
  if not limit or limit < 1 or limit % 1 ~= 0 or size and size > limit then return nil, "invalid byte limit" end
  if not seconds or seconds < .1 then return nil, "invalid download timeout" end
  drain()
  local busy = 0
  for _, job in pairs(jobs) do if job.busy then busy = busy + 1 end end
  if busy >= M.MAX_JOBS then return nil, "file-download worker queue is full" end
  local key = love and love.system and love.system.getOS and love.system.getOS() == "Windows" and dest:lower() or dest
  if destinations[key] then return nil, "download destination is busy" end
  nextId = nextId + 1
  local id = nextId
  local job = {id = id, dest = dest, key = key, size = size, retained = true,
    state = {status = "pending", progress = 0, receivedBytes = 0}}
  jobs[id] = job
  if not ensure() then failed(job, failure); return id end
  job.stage, job.cancel = directory .. "/" .. id .. ".part", love.thread.newChannel()
  job.control, job.progress = love.thread.newChannel(), love.thread.newChannel()
  job.control:push("open")
  job.deadline, job.busy = now() + seconds, true
  destinations[key] = id
  commands:push({id = id, url = url, stage = job.stage, dest = dest, cancel = job.cancel,
    control = job.control, progress = job.progress,
    deadline = job.deadline, maxSeconds = seconds, size = size, maxBytes = limit,
    userAgent = options.userAgent, accept = options.accept, httpsOnly = options.boundedHttpsGet == 1})
  return id
end

function M.poll(id)
  drain()
  local job = jobs[id]
  if not job or not job.retained then return {status = "error", err = "invalid job handle"} end
  local state = {}
  for k, v in pairs(job.state) do state[k] = v end
  if state.status == "pending" and job.progress then
    local received = job.progress:peek()
    job.receivedBytes = math.max(job.receivedBytes or 0, tonumber(received) or 0)
    state.receivedBytes = job.receivedBytes
    state.progress = job.size and job.size > 0 and math.min(1, state.receivedBytes / job.size) or 0
    state.cancellable = job.control:peek() == "open"
    if not state.cancellable then state.phase = "publishing" end
  end
  return state
end
function M.cancel(id)
  local job = jobs[id]
  if not job or not job.retained then return false end
  if job.state.status == "pending" then
    -- Publication claims and accepted cancellations are ordered by one short
    -- channel transaction. No disk IO runs under that lock. Once publication
    -- has claimed the completed transfer, cancellation is too late.
    if not cancelTransfer(job) then return false end
    failed(job, "cancelled")
  end
  return job.state.status ~= "ok"
end
function M.release(id)
  local job = jobs[id]
  if not job then return end
  M.cancel(id); job.retained = false
  if not job.busy then jobs[id] = nil end
end
function M.shutdown()
  for id in pairs(jobs) do M.cancel(id) end
  if quit then quit:push(true); commands:clear(); for _ = 1, #workers do commands:push(false) end end
  for _, thread in ipairs(workers) do pcall(thread.wait, thread) end
  drain()
  for _, job in pairs(jobs) do
    job.busy = false
    if job.stage then love.filesystem.remove(job.stage) end
    if job.stage then love.filesystem.remove(job.stage .. ".cfg"); love.filesystem.remove(job.stage .. ".stderr") end
  end
  if directory then love.filesystem.remove(directory) end
  workers, destinations = {}, {}
  commands, results, quit, directory, ready, failure = nil, nil, nil, nil, nil, nil
end

return M
