-- Hold only the final OS publication call, to exercise the real worker's
-- cancellation/commit boundary while the main thread keeps pumping.
require("love.thread")
require("love.filesystem")
require("love.timer")
require("love.system")
local publish = require("src.net.DownloadPublish")
package.loaded["src.net.DownloadPublish"] = function(source, target)
  if target:sub(-18) == "/delay-publish.bin" then love.timer.sleep(.25) end
  return publish(source, target)
end
-- Hold the bounded-queue fixture before the real worker reads cancellation.
-- A wall-clock HTTP delay can expire while a busy CI host deschedules main.
local commands, results, quit = ...
local actualResults=results
results={push=function(_,response)
  -- Forward unchanged production results before the QA acknowledgement.
  actualResults:push(response)
  love.thread.getChannel("download-qa-completed"):push(response.id)
end}

local gate = love.thread.getChannel("download-qa-hold")
local entered = love.thread.getChannel("download-qa-entered")
local firstFile = true
local proxy = { demand = function()
  local job = commands:demand()
  if type(job) == "table" and firstFile and job.dest == "downloads/target.bin" then
    firstFile = false
    love.thread.getChannel("download-qa-start-entered"):push(job.id)
    while not love.thread.getChannel("download-qa-start"):peek() do love.timer.sleep(.001) end
  end
  if type(job)=="table" and job.dest=="downloads/retiring.bin" then
    love.thread.getChannel("download-qa-retire-entered"):push(job.id)
    while not love.thread.getChannel("download-qa-retire-release"):peek()do love.timer.sleep(.001)end
  end
  if type(job) == "table" and job.dest:match("^downloads/held%d+$") then
    entered:push(job.id)
    while not gate:peek() do love.timer.sleep(.001) end
  end
  return job
end }
assert(love.filesystem.load("src/net/download_worker.lua"))(proxy, results, quit)
