-- Engine-owned GET and file-download workers. No HTTP/pipe read in poll.
local Fetch = {}
local Get = require("src.net.AsyncGet")
local Download = require("src.net.AsyncDownload")
local jobs, nextId = {}, 0
local function start(service, method, ...)
  local request, err = service[method](...)
  if not request then return nil, err end
  nextId = nextId + 1
  jobs[nextId] = {service = service, request = request}
  return nextId
end

-- Legacy shape: download(url, relativeSavePath, {size?,userAgent?,maxSeconds?}).
-- Additional optional bounds: maxBytes, accept, boundedHttpsGet.
function Fetch.download(url, dest, options)
  return start(Download, "download", url, dest, options)
end
function Fetch.get(url, options) return start(Get, "get", url, options) end
function Fetch.postLog(url, body, options) return start(Get, "postLog", url, body, options) end
function Fetch.poll(id)
  local job = jobs[id]
  if not job then return {status = "error", err = "invalid job handle"} end
  return job.service.poll(job.request)
end
function Fetch.cancel(id)
  local job = jobs[id]
  if not job then return false end
  return job.service.cancel(job.request)
end
function Fetch.release(id)
  local job = jobs[id]
  if job then job.service.release(job.request); jobs[id] = nil end
end
function Fetch.available() return Get.available() end
function Fetch.isPending(id) return Fetch.poll(id).status == "pending" end
function Fetch.shutdown() Get.shutdown(); Download.shutdown() end
return Fetch
