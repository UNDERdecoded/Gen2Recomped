require("love.filesystem")
require("love.thread")
require("love.system")
local Json = require("src.link.Json")
local job = assert(Json.decode(...))
local channel = love.thread.getChannel(job.channel)
local function post(e)
  channel:push(Json.encode(e))
end
local root = job.root .. "/" .. job.relative
local ok, why = pcall(function()
  local pipe = assert(
    require("src.translation.DesktopProcess").open(job.helper, root .. "/request.json", true),
    "Could not start shader importer"
  )
  local terminal = false
  local complaint = "Shader importer stopped"
  for line in pipe:lines() do
    if #line <= 262144 then
      local event = Json.decode(line)
      if type(event) == "table" and type(event.kind) == "string" then
        if event.kind == "catalog" or event.kind == "installed" then
          terminal = true
        end
        post(event)
      else
        complaint = line:sub(1, 240)
      end
    else
      complaint = "Shader importer response exceeds limit"
    end
  end
  pipe:close()
  if not terminal then
    error(complaint, 0)
  end
end)
if not ok then
  post({ kind = "error", message = tostring(why):sub(1, 240) })
end
-- The helper removes its private source/prepared trees, including failed jobs.
-- These control files were created only for this worker.
for _, name in ipairs({ "request.json", "approve", "cancel" }) do
  os.remove(root .. "/" .. name)
end
-- Use the configured absolute root, not a worker's independently chosen save root.
local ffiOk, ffi = pcall(require, "ffi")
if ffiOk then
  if love.system.getOS() == "Windows" then
    pcall(function()
      ffi.cdef("int _rmdir(const char *);")
      ffi.C._rmdir(root)
    end)
  else
    pcall(function()
      ffi.cdef("int rmdir(const char *);")
      ffi.C.rmdir(root)
    end)
  end
end
