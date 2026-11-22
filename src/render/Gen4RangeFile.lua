-- Gen4RangeFile: open one of the packed terrain files (chunks / heights /
-- permissions .bin) for ranged reads, with a fallback that needs nothing but
-- love.filesystem.read.
--
-- The ground reads these with love.filesystem.newFile + seek + read so a map
-- holds a few hundred KB of a 17 MB file.  On the Switch the version cache is
-- reachable only through CacheFs's prefix shim, and a File handle is exactly
-- the kind of loader that shim did not cover -- which is why every DS game
-- drew its buildings and sprites over the clear colour with no ground at all
-- (docs/switch.md).  The shim now redirects newFile too; this is the second
-- line: if a handle still will not open (a port whose File:seek misbehaves, a
-- loader wrapped in the wrong order), read the whole file once through
-- love.filesystem.read -- the path every other generated asset already loads
-- through -- and serve the same seek/read calls from the string.
--
-- Returns an object with :seek(pos) and :read(bytes), or nil, why.

local Gen4RangeFile = {}

local StringFile = {}
StringFile.__index = StringFile

function StringFile:seek(pos)
  pos = tonumber(pos)
  if not pos or pos < 0 or pos > #self.bytes then return false end
  self.pos = pos
  return true
end

function StringFile:read(bytes)
  bytes = tonumber(bytes)
  if not bytes or bytes <= 0 then return nil end
  local chunk = self.bytes:sub(self.pos + 1, self.pos + bytes)
  self.pos = self.pos + #chunk
  if chunk == "" then return nil end
  return chunk, #chunk
end

function StringFile:release() self.bytes = "" end
function StringFile:close() return true end

-- EVERY HANDLE THIS MODULE OPENED, weakly, so closeAll can reach the ones
-- whose owner is gone but not yet collected.  The last map's ground outlives
-- the game that drew it (the session the player just left, a launcher
-- preview) and keeps its three files open; with the version's cache packed
-- into one archive, those handles are what kept a re-import from taking the
-- old archive off the read path ("still in use; restart the game").
local handles = setmetatable({}, { __mode = "k" })

-- Is `file` still usable?  A LÖVE File closed by closeAll answers isOpen()
-- false; the string fallback is never closed.
function Gen4RangeFile.isLive(file)
  if not file then return false end
  if type(file.isOpen) == "function" then
    local ok, open = pcall(file.isOpen, file)
    return ok and open == true
  end
  return true
end

-- Close every handle still open.  Only for moments when no ground is drawing
-- (the launcher about to replace a cache); a ground that does draw again
-- reopens through isLive on its next read.  Returns how many were closed.
function Gen4RangeFile.closeAll()
  local closed = 0
  for file in pairs(handles) do
    if Gen4RangeFile.isLive(file) then
      pcall(file.close, file)
      closed = closed + 1
    end
    handles[file] = nil
  end
  return closed
end

function Gen4RangeFile.open(path)
  local fs = love and love.filesystem
  if not (fs and type(path) == "string") then return nil, "no filesystem" end
  local why
  if type(fs.newFile) == "function" then
    local ok, file, err = pcall(fs.newFile, path, "r")
    if ok and file then
      handles[file] = true
      return file
    end
    why = ok and err or file
  end
  if type(fs.read) == "function" then
    local ok, bytes = pcall(fs.read, path)
    if ok and type(bytes) == "string" and #bytes > 0 then
      local Logger = require("src.core.Logger")
      Logger.info("gen4 ground: %s read whole (%d bytes) -- newFile refused it (%s)",
                  path, #bytes, tostring(why))
      return setmetatable({ bytes = bytes, pos = 0 }, StringFile)
    end
  end
  return nil, why or "not found"
end

return Gen4RangeFile
