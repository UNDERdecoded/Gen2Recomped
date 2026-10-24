-- GETs run on bounded engine workers; poll never waits for a GET transport.
-- The older download-to-file API retains its synchronous first-poll behavior.

local Fetch = {}
local AsyncGet = require("src.net.AsyncGet")

-- Active jobs table: jobId -> { url, dest, size, userAgent, startedAt, maxSeconds, state, progress, err, downloaded }
local jobs = {}
local nextJobId = 1

-- Job states: "pending", "ok", "error"
local function newJob(url, dest, options)
  local job = {
    id = nextJobId,
    url = url,
    dest = dest,
    size = options and options.size,
    userAgent = options and options.userAgent or "gen1recomp-fetch",
    maxSeconds = options and options.maxSeconds or 60,
    state = "pending",
    progress = 0,
    err = nil,
    startedAt = os.time(),
    downloaded = false,
  }
  jobs[nextJobId] = job
  nextJobId = nextJobId + 1
  return job.id
end

-- Start a download job. Returns job handle (integer).
-- options: { size?, userAgent?, maxSeconds? }
function Fetch.download(url, dest, options)
  if type(url) ~= "string" or url == "" then
    return nil
  end
  if type(dest) ~= "string" or dest == "" then
    return nil
  end
  local jobId = newJob(url, dest, options)
  local job = jobs[jobId]

  -- Resolve the legacy download transport
  local HostShell = require("src.core.HostShell")
  if not HostShell.canFetch() then
    job.state = "error"
    job.err = "no network transport on this platform"
    return jobId
  end

  -- Convert dest to absolute path if relative
  local absDest = dest
  if love and love.filesystem then
    local saveOk, saveDir = pcall(function()
      return love.filesystem.getSaveDirectory()
    end)
    if saveOk and saveDir and saveDir ~= "" then
      absDest = saveDir .. "/" .. dest
    end
  end

  -- Note: HostShell.httpDownload is synchronous, so we mark it as started
  -- The actual download will happen on the first poll
  job.absDest = absDest
  return jobId
end

-- Poll a job's status. Returns { status, progress?, err? }
-- status: "pending", "ok", "error"
function Fetch.poll(jobId)
  local job = jobs[jobId]
  if not job then
    return { status = "error", err = "invalid job handle" }
  end
  if job.kind == "get" then return AsyncGet.poll(job.request) end

  if job.state ~= "pending" then
    return { status = job.state, progress = job.progress, err = job.err }
  end

  -- Check timeout
  if os.time() - job.startedAt > job.maxSeconds then
    job.state = "error"
    job.err = "download timed out"
    return { status = "error", err = job.err }
  end

  -- Perform the actual download on first poll (synchronous but framed)
  if not job.downloaded then
    job.downloaded = true
    local HostShell = require("src.core.HostShell")
    local ok, err = pcall(function()
      HostShell.httpDownload(job.url, job.absDest, job.userAgent)
    end)

    if not ok then
      job.state = "error"
      job.err = err or "download failed"
      return { status = "error", err = job.err }
    end
  end

  -- Check file size to estimate progress
  local currentSize = 0
  if love and love.filesystem then
    local infoOk, info = pcall(love.filesystem.getInfo, job.dest)
    if infoOk and info and info.size then
      currentSize = tonumber(info.size) or 0
    end
  end

  -- If we have an expected size, calculate progress
  if job.size and job.size > 0 then
    job.progress = math.min(1.0, currentSize / job.size)
  else
    job.progress = 0
  end

  -- Check if download is complete (file exists and non-zero)
  if currentSize > 0 then
    -- If we have an expected size, verify it matches
    if job.size and job.size > 0 then
      if currentSize >= job.size then
        job.state = "ok"
        job.progress = 1.0
      end
    else
      -- No expected size, assume complete if file exists
      job.state = "ok"
      job.progress = 1.0
    end
  end

  return { status = job.state, progress = job.progress, err = job.err }
end

-- Cancel an active job.
function Fetch.cancel(jobId)
  local job = jobs[jobId]
  if not job then return end
  if job.kind == "get" then return AsyncGet.cancel(job.request) end
  if job.state == "pending" then
    job.state = "error"
    job.err = "cancelled"
    -- Try to remove partial file
    if love and love.filesystem then
      pcall(love.filesystem.remove, job.dest)
    end
  end
end

-- Release job resources. Call after job is complete or cancelled.
function Fetch.release(jobId)
  local job = jobs[jobId]
  if job and job.kind == "get" then AsyncGet.release(job.request) end
  jobs[jobId] = nil
end

-- The existing download API keeps its call shape. GETs use a real worker
-- pool, so a mod's per-frame poll never performs a network/pipe read.
function Fetch.get(url, options)
  local request, err = AsyncGet.get(url, options)
  if not request then return nil, err end
  local id = newJob(url, nil, options)
  jobs[id].kind, jobs[id].request = "get", request
  return id
end

function Fetch.available() return AsyncGet.available() end
function Fetch.isPending(id)
  local job = jobs[id]
  if not job then return false end
  if job.kind == "get" then return AsyncGet.poll(job.request).status == "pending" end
  return job.state == "pending"
end
function Fetch.shutdown() AsyncGet.shutdown() end

return Fetch
