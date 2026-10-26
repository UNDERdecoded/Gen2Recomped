-- Worker-only streaming HTTP transport. Remote values stay in a curl config;
-- the response is never assembled in the main thread or retained in memory.
local Host = require("src.core.HostShell")
local M = {}

function M.run(job, output)
  if not Host.canSpawnProcess() then return nil, "background downloads require desktop curl" end
  local fs = love.filesystem
  local errorPath, configPath = job.stage .. ".stderr", job.stage .. ".cfg"
  local absolute = fs.getSaveDirectory() .. "/" .. configPath
  if love.system.getOS() == "Windows" and absolute:find('[%%!"^]') then
    return nil, "unsupported characters in worker path"
  end
  local function quote(value)
    value = tostring(value)
    if value:find("[%z%c]") then return nil end
    return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
  end
  local ua, accept = quote(job.userAgent or "gen2recomp-fetch"), quote(job.accept or "*/*")
  if not ua or not accept then return nil, "invalid HTTP header" end
  local seconds = math.max(.1, math.min(job.maxSeconds, job.deadline - love.timer.getTime()))
  local protocol = job.httpsOnly and "https" or "http,https"
  local config = table.concat({ "silent", "show-error", "fail", "location", "globoff",
    "connect-timeout = " .. math.min(10, seconds), "max-time = " .. seconds,
    "max-filesize = " .. job.maxBytes, "max-redirs = 5",
    'proto = "=' .. protocol .. '"', 'proto-redir = "=' .. protocol .. '"',
    "user-agent = " .. ua, "header = " .. quote("Accept: " .. (job.accept or "*/*")),
    "stderr = " .. quote(fs.getSaveDirectory() .. "/" .. errorPath),
    'write-out = "\\n%{http_code}"', "url = " .. quote(job.url), "" }, "\n")
  local wrote, why = fs.write(configPath, config)
  if not wrote then return nil, tostring(why or "could not write download config") end
  local pipe = Host.popen("curl --disable --config " .. Host.quote(absolute),
    love.system.getOS() == "Windows" and "rb" or "r")
  if not pipe then fs.remove(configPath); return nil, "could not start download" end
  local bytes, tail, failure = 0, "", nil
  local ok, err = pcall(function()
    while true do
      if job.cancel:peek() then failure = "cancelled"; break end
      if love.timer.getTime() >= job.deadline then failure = "download timed out"; break end
      local chunk = pipe:read(65536)
      if not chunk or chunk == "" then break end
      -- Retain curl's four-byte HTTP trailer, even across arbitrary reads.
      chunk = tail .. chunk
      local n = math.max(0, #chunk - 4)
      if bytes + n > job.maxBytes then failure = "response exceeds byte limit"; break end
      if n > 0 then
        local saved, reason = output:write(chunk:sub(1, n))
        if not saved then error(reason or "download write failed") end
        local flushed, flushWhy = output:flush()
        if not flushed then error(flushWhy or "download flush failed") end
        bytes = bytes + n
        -- One progress slot per request; a paused menu cannot accumulate an
        -- unbounded message queue while a large file keeps streaming.
        job.progress:clear(); job.progress:push(bytes)
      end
      tail = chunk:sub(n + 1)
    end
  end)
  local closed, done, _, code = pcall(pipe.close, pipe)
  local readOk, complaint = pcall(fs.read, errorPath, 4096)
  fs.remove(configPath); fs.remove(errorPath)
  if not ok then return nil, tostring(err) end
  if failure then return nil, failure end
  local status = tonumber(tail:match("^\n(%d%d%d)$"))
  complaint = readOk and Host.curlComplaint(complaint) or nil
  if complaint then return nil, complaint, status end
  if not closed or done == nil or type(code) == "number" and code ~= 0 then
    return nil, "download transport failed", status
  end
  if not status or status < 200 or status >= 300 then
    return nil, "incomplete HTTP response", status
  end
  if job.cancel:peek() then return nil, "cancelled", status end
  if job.size ~= nil and bytes ~= job.size then return nil, "download size mismatch", status end
  return bytes, nil, status
end

return M
