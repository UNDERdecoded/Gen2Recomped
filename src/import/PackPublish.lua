-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- A private staging name per Lua state plus a monotonic call sequence. Native
-- extractors and inbox installs share this publication path, including workers.
local Data=require("src.import.PackData")
local MD5=require("src.mods.StreamMD5")
local clock=love and love.timer and love.timer.getTime or os.clock
local owner={sequence=0} -- retained by the publisher; no gameplay RNG draws
local identity=table.concat({tostring(owner),tostring(os.time()),string.format("%.9f",clock())},":")
local nonce=MD5.new():update(identity):final()
return function(fs,path,bytes)
  if not (fs and fs.write and fs.rename and fs.remove) then return nil,"atomic pack publication is unavailable" end
  owner.sequence=owner.sequence+1
  local pending=path..".pending-"..nonce.."-"..owner.sequence
  local called,ok,err=pcall(function()
    local dir=path:match("^(.*)/[^/]+$")
    if dir and fs.createDirectory then
      local made,why=fs.createDirectory(dir);if not made then return nil,why end
    end
    local wrote,why=fs.write(pending,bytes);if not wrote then return nil,why end
    local staged;staged,why=Data.read(fs,pending,#bytes)
    if staged~=bytes then return nil,why or "pack staging write did not match" end
    return fs.rename(pending,path)
  end)
  if not called then err,ok=tostring(ok),nil end
  if not ok then pcall(fs.remove,pending);return nil,err or "pack publication failed" end
  return true
end
