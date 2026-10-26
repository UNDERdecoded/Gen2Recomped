require("love.thread")
require("love.filesystem")
require("love.timer")
require("love.system")
require("love.data")
local commands, results, quit, token, workerIndex = ...
local Transport = require("src.net.BoundedHttp")
local directory = "net-get/" .. token .. "/" .. workerIndex
-- The main thread creates this workspace before starting any worker.
local saveDir = love.filesystem.getSaveDirectory()

local function run(job)
  if job.cancel:peek() or love.timer.getTime() >= job.deadline then
    return {id = job.id, ok = false, err = "cancelled"}
  end
  local path = directory .. "/" .. job.id .. ".stderr"
  local body, err, httpStatus = Transport.request(job.url, {
    method=job.method,body=job.body,discardBody=job.discardBody,contentType=job.contentType,
    userAgent = job.userAgent, accept = job.accept,
    maxSeconds = math.max(0.1, math.min(job.maxSeconds, job.deadline - love.timer.getTime())),
    maxBytes = job.maxBytes, httpsOnly = job.httpsOnly,
    errorPath = saveDir .. "/" .. path,
  })
  love.filesystem.remove(path)
  if job.cancel:peek() then return {id = job.id, ok = false, err = "cancelled"} end
  if job.discardBody then err=body==nil and 'log upload failed' or nil end
  return {id = job.id, ok = body ~= nil, body = not job.discardBody and body or nil,
    err = err, httpStatus = httpStatus}
end

while true do
  local job = commands:demand()
  if quit:peek() or job == false then break end
  if type(job) == "table" then
    local ok, response = pcall(run, job)
    love.filesystem.remove(directory .. "/" .. job.id .. ".stderr")
    love.filesystem.remove(directory .. "/" .. job.id .. ".stderr.cfg")
    if not ok then response = {id = job.id, ok = false, err = tostring(response)} end
    results:push(response)
  end
end
love.filesystem.remove(directory)
