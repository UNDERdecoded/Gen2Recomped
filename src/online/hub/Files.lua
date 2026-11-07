-- Plain-file helpers for the hub (no love.filesystem: the hub writes under
-- its own data directory, wherever the operator put it).

local Json = require("src.link.Json")

local Files = {}

Files.isWindows = package.config:sub(1, 1) == "\\"

function Files.clean(path)
  return (tostring(path):gsub("\\", "/"):gsub("/+$", ""))
end

function Files.join(a, b)
  if b == nil or b == "" then return Files.clean(a) end
  if b:match("^/") or b:match("^%a:[/\\]") then return Files.clean(b) end
  return Files.clean(a) .. "/" .. b
end

function Files.dirname(path)
  return Files.clean(path):match("^(.*)/[^/]*$") or "."
end

function Files.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- create `dir` and its parents (best effort; the same os.execute fallback
-- WS7's GtsStore.dirFs uses, because plain Lua has no mkdir)
function Files.mkdirs(dir)
  dir = Files.clean(dir)
  local probe = dir .. "/.hub_probe"
  local f = io.open(probe, "wb")
  if f then f:close() os.remove(probe) return true end
  if Files.isWindows then
    os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null")
  end
  f = io.open(probe, "wb")
  if f then f:close() os.remove(probe) return true end
  return false, "can't create " .. dir
end

function Files.read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- write to <path>.part, then move over <path> (Windows' rename cannot replace
-- a file, so the old one goes first; a crash in between leaves the .part)
function Files.writeAtomic(path, text)
  local part = path .. ".part"
  local f, err = io.open(part, "wb")
  if not f then return false, err end
  local ok, werr = f:write(text)
  f:flush()
  f:close()
  if not ok then return false, werr end
  os.remove(path)
  local okR, rerr = os.rename(part, path)
  if not okR then return false, rerr end
  return true
end

function Files.readJson(path)
  local text = Files.read(path) or Files.read(path .. ".part")
  if not text or text == "" then return nil end
  local ok, v = pcall(Json.decode, text)
  if ok and type(v) == "table" then return v end
  return nil
end

function Files.writeJson(path, value)
  local ok, text = pcall(Json.encode, value)
  if not ok then return false, text end
  return Files.writeAtomic(path, text)
end

-- a WorldStore (src/online/world/WorldStore.lua) file system rooted at `base`
function Files.worldFs(base)
  base = Files.clean(base)
  local function full(p) return base .. "/" .. p end
  return {
    read = function(p) return Files.read(full(p)) end,
    write = function(p, text)
      Files.mkdirs(Files.dirname(full(p)))
      local f = io.open(full(p), "wb")
      if not f then return false end
      f:write(text)
      f:close()
      return true
    end,
    remove = function(p) os.remove(full(p)) end,
    list = function() return {} end, -- the hub opens its world by id
  }
end

return Files
