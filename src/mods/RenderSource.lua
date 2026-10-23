-- Private bounded source reader, shared by render-data extensions.
local Assets = require("src.render.Assets")
local M = {}
function M.reader(loader)
  return function(path, limit)
    -- Resolve exactly the asset used by native sprites, including overrides.
    -- The caller supplies only a resident opaque sheet ID, never a path.
    if
      type(path) ~= "string"
      or path:sub(1, 1) == "/"
      or path:find("\\", 1, true)
      or path:find(":", 1, true)
      or path:find("%z")
    then
      return nil
    end
    for part in path:gmatch("[^/]+") do
      if part == ".." then
        return nil
      end
    end
    local resolved = Assets.resolve(path)
    local fs = loader.fs
    local modern = fs and type(fs.openFile) == "function"
    if not (fs and (modern or fs.newFile)) then
      return nil
    end
    local f
    if modern then
      -- Native generated assets may be redirected to a version cache.
      -- Existing runtimes shim newFile, but not LÖVE 12's replacement.
      local cache = package.loaded["src.import.CacheFs"]
      if love and fs == love.filesystem and cache and cache._redirect then
        resolved = cache._redirect(resolved)
      end
      f = fs.openFile(resolved, "r")
    else
      f = fs.newFile(resolved)
    end
    if not f then
      return nil
    end
    local ok, bytes = pcall(function()
      if not modern and not f:open("r") then
        return nil
      end
      local size = f:getSize()
      if type(size) ~= "number" or size < 33 or size > limit then
        return nil
      end
      return f:read(limit + 1)
    end)
    pcall(f.close, f)
    return ok and bytes or nil
  end
end
return M
