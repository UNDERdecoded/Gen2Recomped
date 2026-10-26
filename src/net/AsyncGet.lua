-- Bounded engine-owned GET workers. No network or pipe read runs in poll().
local Get = { MAX_JOBS = 16, MAX_BYTES = 16 * 1024 * 1024 }
local jobs, workers, nextId = {}, {}, 0
local commands, results, quit, ready, failure, poolDirectory

local function now() return love.timer.getTime() end

local function ensure()
  if ready ~= nil then return ready end
  if not (love and love.thread and love.thread.newThread and love.thread.newChannel) then
    ready, failure = false, "background threads unavailable"; return false
  end
  commands, results, quit = love.thread.newChannel(), love.thread.newChannel(), love.thread.newChannel()
  local token = tostring(os.time()) .. "-" .. tostring({}):gsub("[^%w]", "")
  poolDirectory = "net-get/" .. token
  for workerIndex = 1, 3 do
    -- Initialize the writable filesystem on the main thread, before any
    -- workers race its first write-directory creation. Each owns its files.
    if love.filesystem then
      local made, done = pcall(love.filesystem.createDirectory, poolDirectory .. "/" .. workerIndex)
      if not made or not done then
        ready, failure = false, "could not create GET worker directory"
        return false
      end
    end
  end
  for workerIndex = 1, 3 do
    local ok, thread = pcall(love.thread.newThread, "src/net/get_worker.lua")
    if ok and thread then
      local started = pcall(thread.start, thread, commands, results, quit, token, workerIndex)
      if started then workers[#workers + 1] = thread end
    end
  end
  ready = #workers > 0
  if not ready then failure = "could not start GET workers" end
  return ready
end

local function drain()
  if not results then return end
  while true do
    local msg = results:pop()
    if not msg then break end
    local job = type(msg) == "table" and jobs[msg.id]
    if job then
      job.busy = false
      if not job.retained then jobs[msg.id] = nil
      elseif job.state.status == "pending" then
        local body=not job.oneWay and msg.body or nil
        local failure=msg.err
        if job.oneWay then failure=not msg.ok and 'log upload failed' or nil end
        job.state = { status = msg.ok and "ok" or "error", body = body,
          err = failure, httpStatus = msg.httpStatus,
          receivedBytes = body and #body or 0, progress = msg.ok and 1 or 0 }
      end
    end
  end
  for _, thread in ipairs(workers) do
    local err = thread:getError()
    if err then
      ready, failure = false, tostring(err)
      quit:push(true); commands:clear()
      for _ = 1, #workers do commands:push(false) end
      for _, job in pairs(jobs) do
        if job.state.status == "pending" then job.state = { status = "error", err = failure } end
      end
      break
    end
  end
  for _, job in pairs(jobs) do
    if job.state.status == "pending" and now() >= job.deadline then
      job.cancel:push(true); job.state = { status = "error", err = "request timed out" }
    end
  end
end

local function finite(value, fallback, maximum)
  value = tonumber(value)
  if not value or value ~= value then value = fallback end
  return math.max(1, math.min(maximum, value))
end

function Get.available() return ensure() end

local function request(url, opts, method, body)
  opts = type(opts) == "table" and opts or {}
  if type(url) ~= "string" or #url > 8192 or url:find("[%z%c%s]")
      or not url:lower():match("^https?://[^/?#]+") then return nil, "invalid HTTP URL" end
  if (opts.boundedHttpsGet == 1 or method=="POST") and not url:lower():match("^https://") then return nil, "HTTPS required" end
  if method=="POST" and (type(body)~="string" or #body>512*1024) then return nil,"POST body exceeds byte limit" end
  drain()
  local busy = 0
  for _, job in pairs(jobs) do if job.busy then busy = busy + 1 end end
  if busy >= Get.MAX_JOBS then return nil, "GET worker queue is full" end
  nextId = nextId + 1
  local id = nextId
  local seconds = finite(opts.maxSeconds, 20, 30)
  local state = { status = "pending", progress = 0, receivedBytes = 0 }
  if not ensure() then
    jobs[id] = { retained = true, state = {status = "error", err = failure} }
    return id
  end
  local cancel = love.thread.newChannel()
  local deadline = now() + seconds
  jobs[id] = { retained = true, busy = true, cancel = cancel, state = state, deadline = deadline,oneWay=method=="POST" }
  commands:push({ id = id, url = url, cancel = cancel, deadline = deadline,
    method=method,body=body,discardBody=method=="POST",contentType=opts.contentType,
    userAgent = opts.userAgent, accept = opts.accept,
    maxSeconds = seconds, maxBytes = math.floor(finite(opts.maxBytes, 4 * 1024 * 1024, Get.MAX_BYTES)),
    httpsOnly = opts.boundedHttpsGet == 1 or method=="POST" })
  return id
end

function Get.get(url,opts)return request(url,opts,"GET")end
function Get.postLog(url,body,opts)return request(url,opts,"POST",body)end

function Get.poll(id)
  drain()
  local job = jobs[id]
  if not job or not job.retained then return {status = "error", err = "unknown request"} end
  local out = {}
  for key, value in pairs(job.state) do out[key] = value end
  return out
end

function Get.cancel(id)
  local job = jobs[id]
  if not job or not job.retained then return false end
  if job.state.status == "pending" then
    job.cancel:push(true); job.state = {status = "cancelled"}
  end
  return true
end

function Get.release(id)
  local job = jobs[id]
  if not job then return end
  Get.cancel(id)
  job.retained = false
  if not job.busy then jobs[id] = nil end
end

function Get.shutdown()
  if quit then quit:push(true) end
  if commands then
    commands:clear()
    for _ = 1, #workers do commands:push(false) end
  end
  for _, thread in ipairs(workers) do pcall(thread.wait, thread) end
  if poolDirectory and love.filesystem then love.filesystem.remove(poolDirectory) end
  poolDirectory = nil
  for _, job in pairs(jobs) do
    job.busy = false
    if job.state.status == "pending" then job.state = {status = "cancelled"} end
  end
  commands, results, quit, ready, failure = nil, nil, nil, nil, nil
  workers = {}
end

return Get
