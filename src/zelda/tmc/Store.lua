-- Minish Cap cache I/O.
--
-- `root` is what the foundation hands extract/isReady/newGame.  Two shapes:
--
--   * a cache-relative prefix ("minishcap/"): every read and write goes
--     through src/import/CacheFs, the same road the Pokemon caches take, so
--     portable mode, custom data folders and bulkWrites all apply;
--   * an absolute folder ("G:/scratch/tmc" or "/home/x/tmc"): plain io.*,
--     which is what the tests and the scratch harness use (they run without
--     LOVE's filesystem or outside the save directory).
--
-- Files are flat inside root (no sub-folders), so nothing here has to make
-- directories beyond root itself.

local Store = {}
Store.__index = Store

local function isAbsolute(root)
  return root:match("^%a:[/\\]") ~= nil or root:sub(1, 1) == "/"
end

local mkdirFn
local function mkdir(path)
  if mkdirFn == nil then
    mkdirFn = false
    local ok, ffi = pcall(require, "ffi")
    if ok then
      if ffi.os == "Windows" then
        pcall(ffi.cdef, "int CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);")
        mkdirFn = function(p) pcall(ffi.C.CreateDirectoryA, p, nil) end
      else
        pcall(ffi.cdef, "int mkdir(const char *pathname, unsigned int mode);")
        mkdirFn = function(p) pcall(ffi.C.mkdir, p, 493) end
      end
    end
  end
  if mkdirFn then
    -- make each parent in turn; existing ones fail harmlessly
    local acc = ""
    for part in path:gmatch("[^/\\]+") do
      acc = (acc == "" and (path:sub(1, 1) == "/" and "/" or "") or acc .. "/") .. part
      if not acc:match("^%a:$") then mkdirFn(acc) end
    end
  end
end

-- The foundation's ZeldaCache object (src/zelda/ZeldaCache.lua): it pins
-- CacheFs.prefix per call.  Files go under data/generated/, the subtree the
-- import worker clears before every import (CONTRACT.md "ctx.fresh"), so a
-- re-import never finds leftovers of an older one.
local SUB = "data/generated/"
Store.CACHE_SUBDIR = SUB
local ObjStore = {}
ObjStore.__index = function(t, k) return ObjStore[k] or Store[k] end
function ObjStore:path(name) return tostring(self.cache) .. SUB .. name end
function ObjStore:write(name, data) return self.cache:write(SUB .. name, data) end
function ObjStore:read(name) return self.cache:read(SUB .. name) end
function ObjStore:exists(name) return self.cache:exists(SUB .. name) end
function ObjStore:remove(name) if self.cache.remove then return self.cache:remove(SUB .. name) end end

function Store.new(root)
  if type(root) == "table" and root.read and root.write then
    return setmetatable({ cache = root, root = tostring(root) }, ObjStore)
  end
  assert(type(root) == "string" and root ~= "", "Store.new wants a root")
  if root:sub(-1) ~= "/" and root:sub(-1) ~= "\\" then root = root .. "/" end
  root = root:gsub("\\", "/")
  local self = setmetatable({ root = root, absolute = isAbsolute(root) }, Store)
  if self.absolute then mkdir(root) end
  return self
end

function Store:path(name)
  return self.root .. name
end

local CacheFs
local function cachefs()
  CacheFs = CacheFs or require("src.import.CacheFs")
  return CacheFs
end

function Store:write(name, data)
  if self.absolute then
    local f, err = io.open(self.root .. name, "wb")
    if not f then return false, err end
    local ok, werr = f:write(data)
    f:close()
    if not ok then return false, werr end
    return true
  end
  return cachefs().write(self.root .. name, data)
end

function Store:read(name)
  if self.absolute then
    local f = io.open(self.root .. name, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end
  return cachefs().read(self.root .. name)
end

function Store:exists(name)
  if self.absolute then
    local f = io.open(self.root .. name, "rb")
    if not f then return false end
    f:close()
    return true
  end
  return cachefs().exists(self.root .. name)
end

function Store:remove(name)
  if self.absolute then return os.remove(self.root .. name) ~= nil end
  return cachefs().remove(self.root .. name)
end

-- Lua table files: written as `return {...}`, read back in an empty env
function Store:writeTable(name, t)
  return self:write(name, "return " .. Store.serialize(t) .. "\n")
end

function Store:readTable(name)
  local src = self:read(name)
  if not src then return nil end
  local load_ = loadstring or load
  local fn, err = load_(src, "=" .. name)
  if not fn then return nil, err end
  if setfenv then setfenv(fn, {}) end
  local ok, value = pcall(fn)
  if not ok then return nil, value end
  return value
end

-- ---------------------------------------------------------------------------
-- A small serializer: numbers, strings, booleans, nested tables.  Arrays are
-- written as sequences, everything else as [key]=value; output is stable
-- (keys sorted) so a re-import produces the same bytes.
-- ---------------------------------------------------------------------------
local function keyLess(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  return a < b
end

local function ser(v, out, depth)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "0"
    elseif v == math.floor(v) and math.abs(v) < 2^53 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.17g", v) end
  elseif t == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif t == "table" then
    if depth > 40 then error("serialize: too deep") end
    out[#out + 1] = "{"
    local n = #v
    for i = 1, n do
      ser(v[i], out, depth + 1)
      out[#out + 1] = ","
    end
    local keys = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, keyLess)
    for _, k in ipairs(keys) do
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        out[#out + 1] = k .. "="
      else
        out[#out + 1] = "["
        ser(k, out, depth + 1)
        out[#out + 1] = "]="
      end
      ser(v[k], out, depth + 1)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "nil"
  end
end

function Store.serialize(v)
  local out = {}
  ser(v, out, 0)
  return table.concat(out)
end

return Store
