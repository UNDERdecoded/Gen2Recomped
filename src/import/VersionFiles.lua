-- Exact version-qualified reads. Never changes GameVersion, prefixes or mounts.
local Version = require("src.core.GameVersion")
local V = {}
function V.new(fs)
  local native = love and fs == love.filesystem
  local function physical(path, maximum, infoOnly)
    local f = io.open(path, "rb")
    if not f then
      return nil
    end
    local size = f:seek("end")
    if not size then
      f:close()
      return nil
    end
    if infoOnly then
      f:close()
      return { type = "file", size = size }
    end
    if size > maximum then
      f:close()
      return nil, "size limit"
    end
    f:seek("set")
    local data = f:read(maximum + 1)
    f:close()
    if type(data) == "string" and #data <= maximum then
      return data
    end
    return nil, "size limit"
  end
  local function identity()
    if not native then
      return fs
    end
    local Cache = require("src.import.CacheFs")
    return table.concat(
      {
        Cache.datasetRoot() or "<source>",
        fs.getSaveDirectory and fs.getSaveDirectory() or "",
        fs.getSource and fs.getSource() or "",
      },
      "\n"
    )
  end
  local function file(version, path, maximum, infoOnly)
    local full = Version.cachePrefix(version) .. path
    if not native then
      if infoOnly then
        return fs.getInfo(full, "file")
      end
      return fs.read(full)
    end
    local Cache = require("src.import.CacheFs")
    local root, ready = Cache.datasetRoot()
    if root then
      return physical(root .. "/" .. full, maximum, infoOnly)
    end
    local save = ready and fs.getSaveDirectory and fs.getSaveDirectory()
    if save then
      local data, why = physical(save .. "/" .. full, maximum, infoOnly)
      if data ~= nil or why then
        return data, why
      end
    end
    local source = fs.getSource and fs.getSource()
    if source then
      local data, why = physical(source .. "/" .. full, maximum, infoOnly)
      if data ~= nil or why then
        return data, why
      end
    end
    return Cache.datasetSourceFile(full, maximum, infoOnly)
  end
  local function source(version, paths)
    local prefix = Version.cachePrefix(version)
    if native then
      local Cache = require("src.import.CacheFs")
      if Cache.datasetRoot() then
        return false
      end
      for _, path in ipairs(paths) do
        if not Cache.datasetSourceFile(prefix .. path, 0, true) then
          return false
        end
      end
      return true
    end
    if not fs.getSource or not fs.getRealDirectory then
      return false
    end
    for _, path in ipairs(paths) do
      if fs.getRealDirectory(prefix .. path) ~= fs.getSource() then
        return false
      end
    end
    return true
  end
  return {
    read = function(v, p, max)
      return file(v, p, max, false)
    end,
    info = function(v, p)
      return file(v, p, 0, true)
    end,
    identity = identity,
    source = source,
    path = function(version, path)
      -- An unprefixed asset path would be redirected by the active overlay.
      if native and version == "red" and Version.get() ~= "red" then
        return nil, "unavailable asset path"
      end
      return Version.cachePrefix(version) .. path
    end,
  }
end
return V
