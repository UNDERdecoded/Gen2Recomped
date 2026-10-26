require("love.thread")
require("love.filesystem")
require("love.timer")
require("love.system")
local commands, results, quit = ...
local Transport = require("src.net.DownloadTransport")
local publish = require("src.net.DownloadPublish")
while true do
  local job = commands:demand()
  if quit:peek() or job == false then break end
  if type(job) == "table" then
    local output
    local ok, bytes, err, status = pcall(function()
      if job.cancel:peek() then return nil, "cancelled" end
      if love.timer.getTime() >= job.deadline then return nil, "download timed out" end
      local why
      local openFile = love.filesystem.openFile or love.filesystem.newFile
      output, why = openFile(job.stage, "w")
      if not output then return nil, tostring(why or "could not create download staging file") end
      return Transport.run(job, output)
    end)
    if output then
      local closed, result = pcall(output.close, output)
      if not closed or not result then bytes, err = nil, "could not close download staging file" end
    end
    if not ok then err, bytes = tostring(bytes or err), nil end
    if bytes ~= nil then
      local checked, result, why = pcall(function()
        local info = love.filesystem.getInfo(job.stage, "file")
        if not info or info.size ~= bytes then return nil, "download size mismatch" end
        local parent = job.dest:match("^(.+)/[^/]+$")
        if parent and not love.filesystem.createDirectory(parent) then
          return nil, "could not create download destination directory"
        end
        -- The claim is the completion boundary. Cancel either wins before it
        -- or reports false after it; it can never race a later file overwrite.
        local claimed = job.control:performAtomic(function(control)
          if control:peek() ~= "open" or job.cancel:peek() then return false end
          if love.timer.getTime() >= job.deadline then return false end
          control:clear(); control:push("publishing"); return true
        end)
        if not claimed then return nil, job.cancel:peek() and "cancelled" or "download timed out" end
        local base = love.filesystem.getSaveDirectory() .. "/"
        return publish(base .. job.stage, base .. job.dest)
      end)
      if not checked or not result then err, bytes = tostring(why or result or "could not publish download"), nil end
    end
    love.filesystem.remove(job.stage .. ".cfg")
    love.filesystem.remove(job.stage .. ".stderr")
    if bytes == nil then
      love.filesystem.remove(job.stage)
      results:push({id = job.id, ok = false, err = err or "cancelled", httpStatus = status})
    else
      results:push({id = job.id, ok = true, bytes = bytes, httpStatus = status})
    end
  end
end
