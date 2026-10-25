local M = {}
function M.new(root, backend, version)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  assert(Version.VERSIONS[version], "unsupported native game: " .. tostring(version))
  Version.set(version)
  local Save = require("src.core.SaveData")
  local Json = require("src.link.Json")
  local files = {}
  for _, id in ipairs({ "portable_storage", "other_storage" }) do
    local function read(name)
      local f = assert(io.open(root .. "/examples/portable_storage/" .. name, "rb"))
      local s = f:read("*a")
      f:close()
      return s
    end
    local manifest = Json.decode(read("manifest.json"))
    manifest.id = id
    files["mods/" .. id .. "/manifest.json"] = Json.encode(manifest)
    files["mods/" .. id .. "/main.lua"] = read("main.lua")
  end
  local fs = T.sdk.memfs(files)
  local write = fs.write
  fs.write = function(path, body)
    if fs.fail and path:sub(-#fs.fail) == fs.fail then
      return false, "intentional write denial"
    end
    return write(path, body)
  end
  fs.remove = function(path)
    files[path] = nil
    return true
  end
  fs.createDirectory = function()
    return true
  end
  local oldFs, oldPortable = love.filesystem, Save.portableFs
  love.filesystem, Save.portableFs = fs, function()
    return fs
  end
  Save.resetSlotState()
  local result = T.sdk.loadMods({ "mods/portable_storage", "mods/other_storage" }, {
    fs = fs,
    data = T.fixtures.fresh(),
    generation = Version.generation(),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  return {
    T = T,
    fs = fs,
    files = files,
    Save = Save,
    result = result,
    e = result.loader.exports.portable_storage,
    other = result.loader.exports.other_storage,
    game = function(id)
      return { save = { version = version, meta = { playthroughId = id } } }
    end,
    close = function()
      result.release()
      love.filesystem, Save.portableFs = oldFs, oldPortable
      Save.resetSlotState()
    end,
  }
end
return M
